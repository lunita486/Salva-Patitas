import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import '../theme.dart';
import '../domain/reglas_negocio.dart';
import '../widgets/avatares.dart';
import '../widgets/campo_pais_telefono.dart';
import '../widgets/especie_chip.dart';
import '../widgets/estado_error_feed.dart';
import '../widgets/fotos.dart';
import '../domain/compatibilidad.dart';
import '../data/creator_role.dart';
import '../data/favoritos_repository.dart';
import '../data/rescates_repository.dart';
import '../data/preferencias_repository.dart';
import '../data/firestore_resiliencia.dart';
import '../data/usuarios_repository.dart';
import '../services/ubicacion_service.dart';
import '../services/ubicacion_lifecycle.dart';
import 'package:go_router/go_router.dart';
import '../routing/app_router.dart';
import 'compartir_animal.dart';

class AdoptanteFeedScreen extends StatefulWidget {
  const AdoptanteFeedScreen();
  @override
  State<AdoptanteFeedScreen> createState() => _AdoptanteFeedScreenState();
}

class _AdoptanteFeedScreenState extends State<AdoptanteFeedScreen>
    with WidgetsBindingObserver, ReintentoUbicacionAlVolver {
  int _idx = 0;
  // Antes se llamaba `RescatesRepository()` (instancia nueva) directo
  // adentro del StreamBuilder, en build() — mismo bug ya encontrado y
  // arreglado en aliado_home_screen.dart y albergue_home_screen.dart,
  // nunca replicado acá: `feedPublico()` se volvía a llamar (y su stream
  // se recreaba) en CADA rebuild de esta pantalla. Hallazgo de auditoría
  // de código.
  final _rescatesRepo = RescatesRepository();
  // Mismo motivo que _feedStream (arriba): esto vivía inline en build()
  // como `FirebaseFirestore.instance.collection('favoritos').where(...)
  // .snapshots()`, así que se recreaba en CADA rebuild de esta pantalla —
  // y esta pantalla hace setState() por cada tarjeta que se pasa (`_idx++`
  // en el botón "Pasar"), así que cada toque tiraba abajo el listener de
  // favoritos y levantaba uno nuevo de cero. Sin este chequeo, dos
  // StreamBuilder en cascada suscribiéndose de nuevo en cada toque además
  // competía por CPU/red justo con la carga de la próxima tarjeta —
  // hallazgo real de Eliza: "cuando le doy X se está demorando en cargar
  // el próximo". Mismo bug ya encontrado y arreglado para el feed
  // principal en esta misma pantalla, nunca replicado acá para favoritos.
  late final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _favoritosStream =
      FavoritosRepository().mios(_uid);
  // Paginación del feed (ver RescatesRepository.feedPublico): arranca en
  // una tanda y va creciendo de a `feedPageSize` a medida que la persona
  // se acerca al final de lo ya cargado — ver _pedirMasAnimalesSiHaceFalta.
  // Sigue siendo el MISMO stream en vivo, solo que le vamos pidiendo más:
  // un animal nuevo de otra cuenta aparece solo, sin reabrir la pantalla,
  // apenas el límite crezca lo suficiente para alcanzarlo.
  int _limiteFeed = RescatesRepository.feedPageSize;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _feedStream;
  // Guarda contra pedir más de una tanda a la vez: sin esto, si el
  // rebuild siguiente corre antes de que el setState de abajo termine de
  // aplicarse (y el nuevo `_feedStream` traiga el snapshot más grande),
  // la misma condición "estoy cerca del final" se cumple de nuevo y se
  // agranda el límite dos veces por una sola vez que hizo falta.
  bool _pidiendoMasAnimales = false;
  Position? _userPosition;
  // Evita que dos detecciones corran encima (el reintento al volver a
  // primer plano puede caer mientras la primera sigue en curso).
  bool _detectandoPosicion = false;
  Map<String, dynamic>? _perfilAdopcion;
  String _prefEspecie = 'Ambos';
  String _prefTamano = 'Cualquiera';
  String _prefEdad = 'Cualquiera';
  StreamSubscription? _prefSub;
  StreamSubscription? _perfilAdopcionSub;
  final _fotoPageNotifier = ValueNotifier<int>(0);
  // Animales recién marcados como favoritos en esta sesión: se ocultan del
  // feed al instante, sin esperar a que Firestore confirme el favorito.
  // Antes se avanzaba _idx a mano Y la lista se achicaba sola cuando
  // Firestore confirmaba — las dos cosas juntas salteaban un animal.
  final Set<String> _favoritosRecientes = {};
  // URLs cuya descarga ya se disparó de antemano — evita pedir la misma
  // foto de nuevo en cada rebuild (el card se reconstruye seguido: cambia
  // la distancia, el score, etc., sin que cambie el animal mostrado).
  final Set<String> _fotosPrecacheadas = {};
  // UsuariosRepository.aliados() es la única fuente de esta consulta para
  // toda la app — se pide UNA sola vez acá (no en cada build de
  // _aliadosSection()), ver el doc del método para el porqué completo.
  late final Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _aliadosFuture =
      UsuariosRepository().aliados();

  /// Descarga por adelantado la 2da foto (y siguientes) de la tarjeta
  /// visible — el widget que las muestra de verdad (FotoUrl, en
  /// fotos.dart) no empieza a pedir una foto hasta que su widget
  /// realmente se construye, y la foto 2 vive detrás de un
  /// ValueListenableBuilder que solo la construye cuando la persona ya
  /// deslizó para verla. El resultado era un salto/demora visible justo
  /// al deslizar (el bug real que reportó Eliza: "la segunda foto se
  /// demora en cargar"). Precargando apenas se muestra el animal, para
  /// cuando desliza la foto ya está lista — la foto 1 no necesita esto
  /// porque FotoUrl ya la pide sola al construirse (es la que se ve de
  /// entrada).
  ///
  /// `CachedNetworkImageProvider`, no `NetworkImage`: son dos tipos de
  /// `ImageProvider` distintos, con distinta clave de caché — precargar
  /// con uno no evita que el otro vuelva a pedir la foto por red. Como
  /// FotoUrl arma su `CachedNetworkImage` con `CachedNetworkImageProvider`
  /// por debajo, esta precarga con `NetworkImage` nunca llegaba a servir
  /// al widget que de verdad se dibuja: cada segunda foto se descargaba
  /// DOS veces (acá y de nuevo al deslizar), sin ningún ahorro real.
  /// Con `CachedNetworkImageProvider` las dos pasan por el mismo
  /// `flutter_cache_manager`, así que el archivo ya queda en el disco del
  /// teléfono para cuando FotoUrl lo pida de verdad — no hace falta que
  /// las dos coincidan en tamaño exacto de decodificado, solo que la
  /// descarga por red no se repita. Hallazgo de auditoría de código:
  /// esta pantalla se quedó afuera de la migración a caché en disco que
  /// ya tienen las demás.
  void _precacharUrls(Iterable<String> urls) {
    for (final url in urls) {
      if (_fotosPrecacheadas.add(url))
        // onError vacío a propósito: es una precarga best-effort, la foto
        // se termina pidiendo igual cuando el widget la necesita de
        // verdad. Sin este onError, un simple corte de señal (SocketException:
        // Failed host lookup) se reportaba a Crashlytics como un crash
        // fatal — main.dart conecta FlutterError.onError a Crashlytics, y
        // precacheImage() reporta ahí cualquier falla si no le pasás su
        // propio onError. Hallazgo real en producción, APK61.
        precacheImage(
          CachedNetworkImageProvider(url),
          context,
          onError: (_, _) {},
        );
    }
  }

  void _precachearFotosSiguientes(List<String> fotos) =>
      _precacharUrls(fotos.skip(1));

  /// Descarga por adelantado la(s) foto(s) del PRÓXIMO animal de la fila —
  /// sin esto, tocar la X pedía la foto del siguiente animal recién al
  /// construir esa tarjeta, con una demora visible antes de que apareciera
  /// (el bug real: "cuando le doy X se demora mucho en cargar la próxima
  /// foto"). Se llama con el animal actual ya visible, así que la descarga
  /// corre en paralelo mientras la persona todavía lo está mirando — para
  /// cuando toca X, la del siguiente ya está en el caché de imágenes.
  void _precacharSiguienteAnimal(List<Map<String, dynamic>> animals, int idx) {
    if (idx + 1 >= animals.length) return;
    final siguiente = animals[idx + 1];
    _precacharUrls([
      if (siguiente['fotoUrl'] != null) siguiente['fotoUrl'] as String,
      if (siguiente['fotoUrl2'] != null) siguiente['fotoUrl2'] as String,
    ]);
  }

  /// Escribe `prefEspecie` — el mismo campo que lee/escribe
  /// tipo_animal_screen.dart — así que este chip y esa pantalla de perfil
  /// jamás pueden mostrar valores distintos entre sí: es una sola
  /// preferencia guardada, con dos lugares para tocarla.
  Future<void> _cambiarPrefEspecie(String valor) async {
    if (_prefEspecie == valor) return;
    final anterior = _prefEspecie;
    // _idx también se reinicia: es una posición dentro de la lista YA
    // filtrada, no la identidad de un animal puntual — si no se resetea,
    // cambiar de filtro con el índice a mitad de la lista vieja podía caer
    // directo en "Eso es todo por hoy" aunque el nuevo filtro sí tuviera
    // animales, solo que menos que ese índice.
    // _fotoPageNotifier también se reinicia: es "qué foto se está viendo",
    // compartido entre todas las tarjetas, no algo propio de cada animal —
    // si venías viendo la 2da foto de uno y el nuevo filtro te lleva a un
    // animal con una sola foto, quedaba pidiendo una foto que no existía
    // (RangeError, caso real reportado por Eliza con "Leoncio").
    _fotoPageNotifier.value = 0;
    setState(() {
      _prefEspecie = valor;
      _idx = 0;
    }); // sensación instantánea; _prefSub confirma después
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    // guardarConAviso, no un await directo suelto: antes, si esta escritura
    // fallaba de verdad (ej. token vencido), el chip se quedaba mostrando
    // el filtro nuevo pero nada se guardaba — al volver a abrir la app,
    // _suscribirPerfil() releía el valor viejo del servidor y la
    // preferencia "se olvidaba" sin ningún aviso (hallazgo de auditoría de
    // código). Si de verdad falla (no si solo está lenta: siguePendiente
    // significa que Firestore ya la encoló) se revierte el chip y se avisa.
    final resultado = await guardarConAviso(
      () => FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
        'prefEspecie': valor,
      }, SetOptions(merge: true)),
    );
    if (resultado == ResultadoGuardado.fallo && mounted) {
      setState(() => _prefEspecie = anterior);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar tu filtro. Probá de nuevo.'),
          backgroundColor: msgError,
        ),
      );
    }
  }

  /// Texto tipo "Perro · Pequeño · Cachorro" con los filtros que están
  /// activos ahora mismo (omite los que están en su valor "sin filtro").
  /// Se usa en _emptyState() para que quede clarísimo QUÉ combinación no
  /// tiene animales — antes solo decía "ajustá tamaño/edad en tu perfil" en
  /// genérico, y una tester probando con Perro+Pequeño+Cachorro (sin
  /// animales así en el catálogo) pensó que la app tenía un error, en vez
  /// de entender que esa combinación puntual estaba vacía.
  String _resumenFiltros() {
    final partes = <String>[
      if (_prefEspecie != 'Ambos') _prefEspecie,
      if (_prefTamano != 'Cualquiera') _prefTamano,
      if (_prefEdad != 'Cualquiera') _prefEdad,
    ];
    return partes.join(' · ');
  }

  /// Saca TODOS los filtros que pueden estar bloqueando (especie, tamaño y
  /// edad juntos), no solo especie. La usan tanto "Ver todos" del estado
  /// vacío como el chip "Todos" de _chipsEspecie() — antes cada uno hacía
  /// una cosa distinta ("Ver todos" limpiaba los 3, pero el chip "Todos"
  /// solo tocaba especie y dejaba tamaño/edad viejos aplicados en
  /// silencio), y "Todos son todos" para quien lo toca, sin importar cuál
  /// de los dos botones usó. Hallazgo real de Eliza.
  Future<void> _limpiarFiltrosExtra() async {
    if (_prefEspecie == 'Ambos' &&
        _prefTamano == 'Cualquiera' &&
        _prefEdad == 'Cualquiera') {
      return;
    }
    final anteriorEspecie = _prefEspecie;
    final anteriorTamano = _prefTamano;
    final anteriorEdad = _prefEdad;
    _fotoPageNotifier.value = 0;
    setState(() {
      _prefEspecie = 'Ambos';
      _prefTamano = 'Cualquiera';
      _prefEdad = 'Cualquiera';
      _idx = 0;
    });
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    // Mismo motivo que _cambiarPrefEspecie(): si esto falla de verdad hay
    // que revertir los 3 filtros y avisar, no dejarlos "limpios" en
    // pantalla mientras el servidor sigue con los viejos.
    final resultado = await guardarConAviso(
      () => FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
        'prefEspecie': 'Ambos',
        'prefTamano': 'Cualquiera',
        'prefEdad': 'Cualquiera',
      }, SetOptions(merge: true)),
    );
    if (resultado == ResultadoGuardado.fallo && mounted) {
      setState(() {
        _prefEspecie = anteriorEspecie;
        _prefTamano = anteriorTamano;
        _prefEdad = anteriorEdad;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar tu filtro. Probá de nuevo.'),
          backgroundColor: msgError,
        ),
      );
    }
  }

  // El widget del chip y el orden de las opciones viven en widgets/especie_chip.dart
  // (especieChip/especieOpciones) — se comparten con tipo_animal_screen.dart
  // para que el feed y el perfil muestren siempre el mismo estilo y el
  // mismo orden para esta misma preferencia.
  Widget _chipsEspecie() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < especieOpciones.length; i++) ...[
            if (i > 0) const SizedBox(width: especieChipGap),
            especieChip(
              label: especieOpciones[i].$2,
              active: _prefEspecie == especieOpciones[i].$1,
              // "Todos" (especieOpciones[0], valor 'Ambos') limpia también
              // tamaño y edad — es el botón de "empezar de cero", no solo
              // "cualquier especie". Perro/Gato/Otro siguen cambiando solo
              // la especie, para no perder un tamaño/edad que la persona
              // sí quiere mantener al comparar entre especies.
              onTap: () => especieOpciones[i].$1 == 'Ambos'
                  ? _limpiarFiltrosExtra()
                  : _cambiarPrefEspecie(especieOpciones[i].$1),
            ),
          ],
        ],
      ),
    ),
  );

  @override
  void initState() {
    super.initState();
    _feedStream = _rescatesRepo.feedPublico(limite: _limiteFeed);
    _obtenerPosicion();
    _suscribirPerfil();
  }

  // El reintento al volver de segundo plano vive en
  // ReintentoUbicacionAlVolver — mismo criterio que home_screen.dart/
  // perfil_adoptante_screen.dart, que esta pantalla no tenía (hallazgo
  // real de Eliza: "el pin no aparece en el menú de Adoptar, pero sí en
  // el Perfil"). Ver ese archivo para el hallazgo completo del reintento
  // en sí.
  @override
  bool get yaTieneUbicacion => _userPosition != null;
  @override
  bool get detectandoUbicacion => _detectandoPosicion;
  @override
  void reintentarSinPedirPermiso() => _obtenerPosicion(pedirPermiso: false);

  /// Agranda `_limiteFeed` (y con eso, `_feedStream`) en `feedPageSize` más
  /// — se llama cuando la persona ya está por llegar al final de los
  /// animales que se trajeron hasta ahora. `addPostFrameCallback`, no un
  /// `setState` directo: esto se dispara desde adentro del `builder` del
  /// StreamBuilder (durante build()), y llamar setState ahí mismo tira
  /// "setState() called during build".
  void _pedirMasAnimalesSiHaceFalta() {
    if (_pidiendoMasAnimales) return;
    _pidiendoMasAnimales = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _limiteFeed += RescatesRepository.feedPageSize;
        _feedStream = _rescatesRepo.feedPublico(limite: _limiteFeed);
      });
      _pidiendoMasAnimales = false;
    });
  }

  void _suscribirPerfil() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _prefSub = FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .snapshots()
        .listen((doc) {
          if (!doc.exists || !mounted) return;
          final data = doc.data() as Map<String, dynamic>;
          setState(() {
            _prefEspecie = data['prefEspecie'] ?? 'Ambos';
            _prefTamano = data['prefTamano'] ?? 'Cualquiera';
            _prefEdad = data['prefEdad'] ?? 'Cualquiera';
          });
        });
    // perfilAdopcion vive en preferencias/{uid} (privado, solo el dueño lo
    // lee), no en usuarios/{uid} (legible por cualquier usuario logueado
    // porque hay perfiles públicos) — ver ARCHITECTURE.md.
    _perfilAdopcionSub = PreferenciasRepository().stream(uid).listen((doc) {
      if (!doc.exists || !mounted) return;
      final perfil = doc.data()?['perfilAdopcion'];
      if (perfil != null) {
        setState(() => _perfilAdopcion = Map<String, dynamic>.from(perfil));
      }
    });
  }

  @override
  void dispose() {
    // El removeObserver de WidgetsBindingObserver ahora lo hace
    // ReintentoUbicacionAlVolver.dispose(), alcanzado por el super.dispose()
    // de acá abajo — esta limpieza es la propia de esta pantalla.
    _prefSub?.cancel();
    _perfilAdopcionSub?.cancel();
    _fotoPageNotifier.dispose();
    super.dispose();
  }

  int _calcularScore(Map<String, dynamic> animal) {
    if (_perfilAdopcion == null) return -1;
    return calcularCompatibilidad({
      ...animal,
      'animalEnergia': animal['energia'],
      'animalTamano': animal['tamano'],
      'animalOkConNinos': animal['okConNinos'],
      'animalOkConMascotas': animal['okConMascotas'],
      'animalRequiereExp': animal['requiereExperiencia'],
      ..._perfilAdopcion!,
    });
  }

  /// Solo coordenadas (sin `conCiudad`): acá la ubicación se usa para
  /// calcular distancias y ordenar el feed, nunca para mostrar un nombre de
  /// ciudad — pedir el geocoding inverso sería una llamada de red de más.
  ///
  /// `comoAnticipo`: la última posición conocida se aplica al instante (el
  /// feed ya puede ordenar por distancia con ella) y después se refina con
  /// la real, sin que la persona vea ningún salto.
  Future<void> _obtenerPosicion({bool pedirPermiso = true}) async {
    _detectandoPosicion = true;
    try {
      final resultado = await UbicacionService.actual(
        ultimaConocida: UsoUltimaConocida.comoAnticipo,
        pedirPermisoSiFalta: pedirPermiso,
        onAproximada: (aproximada) {
          if (mounted) setState(() => _userPosition = aproximada);
        },
      );
      if (resultado.ok && mounted) {
        setState(() => _userPosition = resultado.posicion);
      }
    } finally {
      _detectandoPosicion = false;
    }
  }

  String _distancia(Map<String, dynamic> animal) {
    // coordenadasDe (domain/reglas_negocio.dart) — descarta (0,0) y lee
    // `num` en vez de `double`. Ver su doc: acá se mostraban distancias
    // inventadas para animales con coordenadas basura, y un entero
    // guardado podía tirar abajo la pestaña entera.
    final coords = coordenadasDe(animal);
    if (coords == null || _userPosition == null) return '';
    final lat = coords.lat;
    final lng = coords.lng;
    final metros = Geolocator.distanceBetween(
      _userPosition!.latitude,
      _userPosition!.longitude,
      lat,
      lng,
    );
    if (metros < 1000) return '${metros.round()} m';
    return '${(metros / 1000).toStringAsFixed(1)} km';
  }

  Future<void> _guardarFavorito(Map<String, dynamic> animal) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final rescateId = animal['rescateId'] as String? ?? '';
    // El id lo arma FavoritosRepository.idDe(), no esta pantalla: la regla
    // tiene que ser IDÉNTICA al guardar y al borrar, o se borra un
    // documento distinto del que se guardó.
    await FavoritosRepository().guardar(
      uid: uid,
      rescateId: rescateId,
      animalNombre: animal['nombre'] as String? ?? '',
      datos: {
        'animalNombre': animal['nombre'],
        'especie': animal['especie'],
        'edad': animal['edad'],
        'ubicacion': animal['ubicacion'],
        'descripcion': animal['descripcion'],
        'tags': animal['tags'],
        'rescatista': animal['rescatista'],
        'rescatistaId': animal['rescatistaId'] ?? '',
        'rescateId': animal['rescateId'] ?? '',
        'genero': animal['genero'] ?? '',
        'fotoUrl': animal['fotoUrl'],
        'creadoPor': animal['creadoPor'] ?? 'rescatista',
      },
    );
    FirebaseAnalytics.instance
        .logEvent(
          name: 'favorito_agregado',
          parameters: {
            'rescatista_id': (animal['rescatistaId'] as String?) ?? '',
          },
        )
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _favoritosStream,
      builder: (context, favSnap) {
        // Antes esto no se revisaba: si la consulta de favoritos fallaba
        // (token vencido, permiso denegado), favRescateIds quedaba vacío
        // en silencio y los animales ya marcados como favoritos volvían a
        // aparecer en el feed principal, como si nunca se hubieran
        // guardado — sin ningún aviso de que algo salió mal. Hallazgo de
        // auditoría de código.
        if (favSnap.hasError) return errorFeedState();
        // Animales ya guardados en Favoritos: no hace falta mostrarlos de
        // nuevo en el feed principal, ya quedan a mano en esa pestaña.
        final favRescateIds = (favSnap.data?.docs ?? [])
            .map(
              (d) =>
                  (d.data() as Map<String, dynamic>)['rescateId'] as String? ??
                  '',
            )
            .where((id) => id.isNotEmpty)
            .toSet();
        // _favoritosRecientes solo existe para tapar la ventana entre
        // "tocaste el corazón acá" y "Firestore ya confirmó el favorito".
        // Apenas el favorito aparece confirmado en favRescateIds, se lo
        // saca de la lista local: desde ahí lo oculta la fuente de verdad,
        // y si más tarde se le quita el corazón (desde cualquier pantalla)
        // desaparece de favRescateIds y reaparece solo en el carrusel.
        // OJO: la condición es "confirmado" y no "ausente" a propósito —
        // podar los ausentes borraría el id recién agregado en el rebuild
        // que dispara el propio toque del corazón (que corre con el
        // snapshot viejo, sin el favorito todavía) y la tarjeta parpadearía.
        _favoritosRecientes.removeWhere(favRescateIds.contains);
        return StreamBuilder<QuerySnapshot>(
          stream: _feedStream,
          builder: (context, snap) {
            if (snap.hasError) return errorFeedState();
            // Antes del primer snapshot real (instalación nueva, sin caché
            // local) favSnap y snap vienen sin datos por un instante — sin
            // este chequeo, `animals` quedaba vacío momentáneamente más abajo
            // y el feed le mostraba "Eso es todo por hoy, vuelve mañana" a
            // alguien que recién se instaló la app, justo cuando SÍ hay
            // animales, todavía cargando. Es la primera pantalla que ve un
            // adoptante nuevo. Hallazgo de auditoría de código.
            //
            // `&& snap.data == null` a propósito — no alcanza con mirar
            // solo connectionState: _pedirMasAnimalesSiHaceFalta() arma un
            // _feedStream NUEVO (mismo Query, límite más grande) cada vez
            // que la persona se acerca al final de lo ya cargado, y
            // StreamBuilder pasa por ConnectionState.waiting un instante
            // cada vez que el `stream:` que recibe cambia de identidad —
            // aunque el snapshot anterior siga siendo perfectamente válido
            // (Flutter conserva `data` en esa transición, solo cambia el
            // estado). Sin este chequeo, cada vez que se pedía más tanda el
            // feed entero desaparecía detrás de un spinner de pantalla
            // completa hasta que volvía el servidor — justo lo que este
            // mecanismo se armó para evitar (ver el comentario de arriba,
            // "para que la persona nunca vea un corte ni un 'cargando' a
            // mitad de pasar animalitos"). Hallazgo real de Eliza: "cuando
            // le doy X se está demorando en cargar el próximo".
            if ((favSnap.connectionState == ConnectionState.waiting &&
                    favSnap.data == null) ||
                (snap.connectionState == ConnectionState.waiting &&
                    snap.data == null)) {
              return const Center(
                child: CircularProgressIndicator(color: appTeal),
              );
            }
            // Separado en 2 pasos (disponibles → firestoreDocs) para poder
            // distinguir "no queda NADA en el catálogo" de "no queda nada CON
            // ESTOS FILTROS" — antes era un solo .where() y _emptyState() no
            // podía diferenciar los dos casos. Importa porque "Ver de nuevo"
            // solo reinicia _idx a 0, y eso no sirve de nada si la lista
            // filtrada ya está vacía (0 >= 0 sigue siendo cierto): el botón
            // quedaba mudo para siempre apenas la especie/tamaño/edad elegidos
            // no tenían ningún animal en ese momento — bug real reportado por
            // una tester ("el botón Ver de nuevo no le funciona").
            final disponibles = (snap.data?.docs ?? []).where((doc) {
              if (favRescateIds.contains(doc.id) ||
                  _favoritosRecientes.contains(doc.id))
                return false;
              final d = doc.data() as Map<String, dynamic>;
              // sePuedeAdoptar (domain/reglas_negocio.dart) — única fuente
              // de esta pregunta. Antes esta lista de estados vivía escrita
              // a mano acá, y Favoritos tenía la SUYA, que se contradecía
              // con esta en 'Hogar de paso'.
              return sePuedeAdoptar(d['estadoAdopcion'] as String?);
            }).toList();
            final firestoreDocs =
                disponibles.where((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    final especie = d['especie'] as String? ?? 'Perro';
                    if (_prefEspecie != 'Ambos' && especie != _prefEspecie)
                      return false;
                    final tamano = d['tamano'] as String? ?? '';
                    if (_prefTamano != 'Cualquiera' && tamano != _prefTamano)
                      return false;
                    final edad = d['edad'] as String? ?? '';
                    if (_prefEdad != 'Cualquiera' && edad != _prefEdad)
                      return false;
                    // filtro por país deshabilitado — se activa cuando haya masa crítica de animales por región
                    return true;
                  }).toList()
                  // Más nuevos primero. Sin campo `creadoEn` (legado) se van al final
                  // en vez de desaparecer del feed — ver feedPublico() en el repo.
                  ..sort((a, b) {
                    final ta =
                        (a.data() as Map<String, dynamic>)['creadoEn']
                            as Timestamp?;
                    final tb =
                        (b.data() as Map<String, dynamic>)['creadoEn']
                            as Timestamp?;
                    if (ta == null && tb == null) return 0;
                    if (ta == null) return 1;
                    if (tb == null) return -1;
                    return tb.compareTo(ta);
                  });
            final animals = <Map<String, dynamic>>[
              ...firestoreDocs.map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                return {
                  'nombre': RescatesRepository.nombreDe(d),
                  'edad': d['edad'] ?? '',
                  'genero': d['genero'] ?? '',
                  'especie': d['especie'] ?? 'Perro',
                  'raza': d['raza'] ?? 'Criolla',
                  'tamano': d['tamano'] ?? 'Mediano',
                  'ubicacion': d['ubicacion'] ?? '',
                  'descripcion': d['descripcion'] ?? '',
                  'tags': <String>[
                    if (d['okConNinos'] == true) 'Amigable con niños',
                    if (d['okConMascotas'] == true) 'Es sociable',
                    if ((d['energia'] as String?)?.isNotEmpty == true)
                      d['energia'] as String,
                    if (d['estado'] != null && d['estado'] != 'Sano')
                      d['estado'] as String,
                  ],
                  'rescatista': d['rescatistaNombre'] ?? 'Rescatista',
                  'rescatistaId': d['rescatistaId'] ?? '',
                  'rescatistaFotoBase64': d['rescatistaFotoBase64'],
                  'rescatistaFotoUrl': d['rescatistaFotoUrl'],
                  'rescateId': doc.id,
                  'estadoAdopcion': d['estadoAdopcion'] ?? '',
                  'fotoUrl': d['fotoUrl'],
                  'fotoUrl2': d['fotoUrl2'],
                  'latitud': d['latitud'],
                  'longitud': d['longitud'],
                  'energia': d['energia'],
                  'okConNinos': d['okConNinos'],
                  'okConMascotas': d['okConMascotas'],
                  'requiereExperiencia': d['requiereExperiencia'],
                  'vacunado': d['vacunado'],
                  'desparasitado': d['desparasitado'],
                  'urgencia': d['urgencia'] ?? '',
                  'creadoPor': d['creadoPor'] ?? '',
                  // Para la bandera junto a la ciudad en la tarjeta: sin
                  // ella, "Córdoba" no distingue Argentina de España.
                  'paisCodigo': d['paisCodigo'] ?? '',
                };
              }),
            ];

            // Ordenar por distancia si hay posición disponible
            if (_userPosition != null) {
              animals.sort((a, b) {
                // Misma fuente que _distancia — sin esto, un animal con
                // (0,0) se ordenaba por una distancia falsa.
                final ca = coordenadasDe(a);
                final cb = coordenadasDe(b);
                // Los dos sin ubicación: EMPATE (0), no `1`. Antes los dos
                // casos devolvían 1, así que el comparador se contradecía
                // a sí mismo (comparar A con B y B con A daba lo mismo) y
                // el orden entre animales sin ubicación cambiaba solo entre
                // redibujados.
                if (ca == null && cb == null) return 0;
                if (ca == null) return 1;
                if (cb == null) return -1;
                final latA = ca.lat;
                final lngA = ca.lng;
                final latB = cb.lat;
                final lngB = cb.lng;
                final dA = Geolocator.distanceBetween(
                  _userPosition!.latitude,
                  _userPosition!.longitude,
                  latA,
                  lngA,
                );
                final dB = Geolocator.distanceBetween(
                  _userPosition!.latitude,
                  _userPosition!.longitude,
                  latB,
                  lngB,
                );
                return dA.compareTo(dB);
              });
            }

            // Pedir la próxima tanda ANTES de que se acaben los animales
            // filtrados que ya se cargaron — no cuando ya se acabaron, para
            // que la persona nunca vea un corte ni un "cargando" a mitad de
            // pasar animalitos. `rawCount >= _limiteFeed` es la señal de que
            // puede haber más en el servidor (si Firestore devolvió MENOS que
            // el límite pedido, es que no queda nada más y no hace falta
            // pedir de nuevo).
            final rawCount = snap.data?.docs.length ?? 0;
            if (rawCount >= _limiteFeed && _idx >= animals.length - 10) {
              _pedirMasAnimalesSiHaceFalta();
            }

            if (_idx >= animals.length) {
              return _emptyState(
                hayMasSinFiltros: disponibles.isNotEmpty && animals.isEmpty,
              );
            }

            final animal = animals[_idx];
            _precacharSiguienteAnimal(animals, _idx);

            final distancia = _distancia(animal);
            return Column(
              children: [
                Expanded(
                  // Todo el bloque de arriba (chips + ubicación + aviso + tarjeta)
                  // comparte un solo scroll en vez de que solo la tarjeta viviera
                  // en un Expanded propio: en horizontal, chips + ubicación +
                  // botones + barra inferior ya ocupan casi toda la poca altura
                  // disponible, y a ese Expanded de la tarjeta le quedaba tan
                  // poco espacio que no llegaba a mostrar nada — ni foto, ni
                  // forma de desplazarse para verla. Con todo este bloque adentro
                  // de un solo SingleChildScrollView, siempre hay algo que
                  // desplazar para llegar a la tarjeta completa, sea cual sea la
                  // altura real disponible. Los botones de acción quedan afuera,
                  // fijos y siempre alcanzables. Hallazgo de prueba en teléfono
                  // real, 2026-08-02: en horizontal no se veía ningún animalito
                  // ni aparecía nada para desplazar.
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        // Antes acá iba también un título grande "Animales
                        // disponibles" — con el saludo nuevo arriba de esta
                        // pantalla ("Encuentra a tu amigo fiel ideal"), quedaba un
                        // segundo título diciendo básicamente lo mismo, apilado
                        // antes de la tarjeta del animal — mucho scroll vertical
                        // para llegar a lo que importa. Se saca, y queda solo la
                        // línea de ubicación (información nueva, no repetida).
                        //
                        // Chips de especie: antes la única forma de filtrar por
                        // especie era entrar a Perfil → "Tipo de animal preferido",
                        // una pantalla aparte que casi nadie encontraba sola. Viven
                        // acá (no en home_screen.dart, que solo envuelve este feed)
                        // porque ya existe el estado reactivo de _prefEspecie con su
                        // propio listener — tocar un chip escribe el mismo campo
                        // `prefEspecie` que esa pantalla de perfil, así que nunca
                        // pueden quedar desincronizados entre sí (son la misma
                        // preferencia, vista desde dos lugares).
                        _chipsEspecie(),
                        // Antes repetía la ciudad del animal ("EN TOLEDO")
                        // acá arriba Y de nuevo en el pin 📍 de la foto —
                        // mismo dato dos veces, sin sumar nada. La distancia
                        // sí es información nueva (ayuda a decidir si es
                        // viable), así que es lo único que queda acá.
                        // Pedido real de Eliza.
                        // Frase normal, no mayúsculas con letterSpacing: en
                        // versalitas apretadas ("A 4 KM DE TI") se leía como
                        // una clave o código, no como una frase — sobre todo
                        // con decimales ("A 5836.1 KM DE TI"). Pedido real
                        // de Eliza.
                        if (distancia.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                            child: Text(
                              'Se encuentra a $distancia de ti',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: appTeal,
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: _buildCard(
                            animal,
                            distancia,
                            _calcularScore(animal),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _actionBtn(
                        Icons.close,
                        Colors.grey.shade200,
                        Colors.grey.shade700,
                        52,
                        () {
                          _fotoPageNotifier.value = 0;
                          setState(() => _idx++);
                        },
                        'Pasar',
                      ),
                      const SizedBox(width: 18),
                      _actionBtn(
                        Icons.pets,
                        Colors.white,
                        appInk,
                        46,
                        () {
                          context.push(AppRoutes.animalDetalle, extra: animal);
                        },
                        'Ver más detalles de ${animal['nombre']}',
                      ),
                      const SizedBox(width: 18),
                      _actionBtn(
                        Icons.favorite,
                        appOrange,
                        Colors.white,
                        62,
                        () async {
                          // Se oculta de una (sin avanzar _idx a mano): la lista se
                          // achica sola y el siguiente animal ocupa este mismo lugar.
                          final favRescateId =
                              animal['rescateId'] as String? ?? '';
                          final messenger = ScaffoldMessenger.of(context);
                          _fotoPageNotifier.value = 0;
                          if (favRescateId.isNotEmpty)
                            setState(
                              () => _favoritosRecientes.add(favRescateId),
                            );
                          try {
                            await _guardarFavorito(animal);
                          } catch (e) {
                            if (!mounted) return;
                            if (favRescateId.isNotEmpty)
                              setState(
                                () => _favoritosRecientes.remove(favRescateId),
                              );
                            messenger.showSnackBar(
                              const SnackBar(
                                backgroundColor: msgError,
                                content: Text(
                                  'No se pudo guardar el favorito. Intentá de nuevo.',
                                ),
                              ),
                            );
                          }
                        },
                        'Marcar como favorito',
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _emptyState({required bool hayMasSinFiltros}) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Antes esta pantalla no tenía los chips de especie — si el filtro
          // activo (ej. "Otros") no tenía animales para mostrar, quedaba en
          // un callejón sin salida: "Ver de nuevo" solo reinicia el índice de
          // la MISMA lista filtrada (sigue vacía), y sin los chips acá la
          // única forma de volver a "Todos" era ir hasta el perfil (el bug
          // real que reportó Eliza). Con los chips siempre visibles, cambiar
          // de filtro nunca deja a nadie sin salida.
          _chipsEspecie(),
          // El título "SALVA PATITAS / Cerca de ti" que iba acá se sacó: ya
          // está el saludo "Hola, Eliza" arriba de esta pantalla (home_screen.
          // dart) y ahora también los chips — un tercer título repitiendo lo
          // mismo era ruido antes de llegar al mensaje real (sugerencia real
          // de Eliza).
          const SizedBox(height: 40),
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: appOrange.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.pets, size: 44, color: appOrange),
          ),
          const SizedBox(height: 20),
          Text(
            hayMasSinFiltros ? 'Nada con estos filtros' : 'Eso es todo por hoy',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: appInk,
            ),
          ),
          // Caso real: una tester probó Perro+Pequeño+Cachorro (sin ningún
          // animal así en el catálogo) y pensó que la app tenía un error —
          // acá se nombra la combinación exacta en vez de solo insinuar
          // "ajustá tamaño/edad", para que quede claro que es ese filtro
          // puntual el que no tiene resultados, no un bug.
          if (hayMasSinFiltros) ...[
            const SizedBox(height: 6),
            Text(
              'Filtros activos: ${_resumenFiltros()}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: appTeal,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            hayMasSinFiltros
                // Caso real: la especie/tamaño/edad elegidos no tienen
                // ningún animal disponible AHORA, aunque el catálogo no
                // esté vacío — "vuelve mañana" sería mentira acá, lo que
                // hace falta es cambiar de filtro, no esperar.
                ? 'Todavía no hay ningún animal con esa combinación exacta.'
                : 'Vuelve mañana, nuevos amigos\nllegan cada día.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () {
              // Ahora saca especie, tamaño Y edad juntos — antes solo tocaba
              // especie, y si el bloqueo era tamaño/edad el botón no hacía
              // nada (había que ir al perfil a mano para sacarlos).
              if (hayMasSinFiltros) {
                _limpiarFiltrosExtra();
              } else {
                setState(() => _idx = 0);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
              decoration: BoxDecoration(
                color: appOrange,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                hayMasSinFiltros ? 'Ver todos' : 'Ver de nuevo',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 36),
          _aliadosSection(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _aliadosSection() {
    return FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      future: _aliadosFuture,
      builder: (context, snap) {
        // aliados() ya devuelve la lista filtrada, no un QuerySnapshot.
        final aliados = snap.data ?? [];
        if (aliados.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Text(
                    'NEGOCIOS ALIADOS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: appTeal,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('🐾', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: aliados.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final d = aliados[i].data();
                  final nombre = d['aliadoNombre'] as String? ?? 'Aliado';
                  final tipo = d['aliadoTipo'] as String? ?? '';
                  final foto = d['aliadoFotoBase64'] as String?;
                  final ini = nombre.isNotEmpty ? nombre[0].toUpperCase() : 'A';
                  final uid = aliados[i].id;

                  return GestureDetector(
                    onTap: () {
                      FirebaseAnalytics.instance
                          .logEvent(
                            name: 'vio_perfil_aliado',
                            parameters: {'aliado_id': uid},
                          )
                          .catchError((_) {});
                      context.push(
                        AppRoutes.aliadoPublico,
                        extra: (
                          aliadoId: uid,
                          esRescatista: false,
                          esAlbergue: false,
                        ),
                      );
                    },
                    child: Container(
                      width: 100,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AvatarPersona(
                            fotoBase64: foto,
                            inicial: ini,
                            radius: 26,
                            backgroundColor: appTeal.withValues(alpha: 0.12),
                            textColor: appTeal,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            nombre,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: appInk,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (tipo.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              tipo,
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.grey.shade700,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _flechaFoto(IconData icon, VoidCallback onTap, String label) =>
      Padding(
        padding: const EdgeInsets.all(8),
        child: Tooltip(
          message: label,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.38),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
          ),
        ),
      );

  Widget _buildCard(Map<String, dynamic> a, String distancia, int score) {
    final fotoUrl = a['fotoUrl'] as String?;
    final fotoUrl2 = a['fotoUrl2'] as String?;
    final fotos = [
      if (fotoUrl != null) fotoUrl,
      if (fotoUrl2 != null) fotoUrl2,
    ];
    _precachearFotosSiguientes(fotos);
    final nombre = a['nombre'] as String;
    final edad = a['edad'] as String;
    final raza = a['raza'] as String;
    final tamano = a['tamano'] as String;
    final descripcion = a['descripcion'] as String;
    final tags = (a['tags'] as List).cast<String>();
    final rescatista = a['rescatista'] as String;
    final ubicacion = a['ubicacion'] as String;
    final estadoAdopcion = a['estadoAdopcion'] as String? ?? '';
    final urgencia = a['urgencia'] as String? ?? '';
    final creadoPor = a['creadoPor'] as String? ?? '';
    final rescatistaId = a['rescatistaId'] as String? ?? '';
    final rescatistaFotoBase64 = a['rescatistaFotoBase64'] as String?;
    final rescatistaFotoUrl = a['rescatistaFotoUrl'] as String?;
    final rescateId = a['rescateId'] as String? ?? '';
    final especie = a['especie'] as String? ?? '';
    final bandera = banderaPais(a['paisCodigo'] as String?);
    final emoji = especie == 'Gato' ? '🐱' : '🐶';

    Color scoreColor(int s) {
      if (s >= 80) return appTeal;
      if (s >= 60) return const Color(0xFFE65100);
      return const Color(0xFFB71C1C);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.09),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: (details) {
              if (fotos.length < 2 || details.primaryVelocity == null) return;
              final curr = _fotoPageNotifier.value;
              if (details.primaryVelocity! < -80 && curr < fotos.length - 1) {
                _fotoPageNotifier.value = curr + 1;
              } else if (details.primaryVelocity! > 80 && curr > 0) {
                _fotoPageNotifier.value = curr - 1;
              }
            },
            // La tarjeta recorta la foto para que se vea linda y llamativa
            // (ver comentario de alignment más abajo) — tocarla abre la
            // foto completa, sin recortar, para quien quiera ver al animal
            // entero antes de decidir.
            // Mismo clamp que el idxSeguro de acá abajo (caso "Leoncio"): sin
            // esto, abrir la foto completa justo cuando el notifier todavía
            // apunta al índice de un animal anterior con más fotos tira un
            // RangeError al construir el PageController con initialPage
            // fuera de rango.
            onTap: fotos.isEmpty
                ? null
                : () {
                    final idxSeguro = _fotoPageNotifier.value < fotos.length
                        ? _fotoPageNotifier.value
                        : 0;
                    context.push(
                      AppRoutes.visorFoto,
                      extra: (fotos: fotos, indiceInicial: idxSeguro),
                    );
                  },
            child: SizedBox(
              height: 300,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  fotos.isNotEmpty
                      ? ValueListenableBuilder<int>(
                          valueListenable: _fotoPageNotifier,
                          builder: (_, fotoIdx, _) {
                            // _fotoPageNotifier es UN solo contador compartido por
                            // todas las tarjetas (no algo propio de cada animal).
                            // Se reinicia a 0 en cada camino conocido que cambia de
                            // animal (X, favorito, cambio de filtro, "ver de
                            // nuevo") — pero un límite de seguridad acá evita que
                            // un camino nuevo que se olvide de resetearlo vuelva a
                            // romper la tarjeta con un RangeError (caso real:
                            // "Leoncio", con 1 sola foto, mientras el índice seguía
                            // en 1 de un animal anterior con 2).
                            final idxSeguro = fotoIdx < fotos.length
                                ? fotoIdx
                                : 0;
                            return AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              child: SizedBox.expand(
                                key: ValueKey(idxSeguro),
                                // FotoAnimal en vez de recorte: la foto se ve
                                // ENTERA sobre un fondo de sí misma desenfocado —
                                // ningún recorte fijo funcionaba para todas (el
                                // ancla arriba rompía fotos con el animal abajo,
                                // caso real "Tobyiii": se veía el mueble vacío).
                                child: FotoAnimal(
                                  url: fotos[idxSeguro],
                                  fallback: Container(
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color(0xFF3D7A52),
                                          Color(0xFF1F4A30),
                                        ],
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        emoji,
                                        style: const TextStyle(fontSize: 90),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        )
                      : Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF3D7A52), Color(0xFF1F4A30)],
                            ),
                          ),
                          child: Center(
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 90),
                            ),
                          ),
                        ),
                  if (fotos.length > 1)
                    Positioned(
                      top: urgencia == 'Alta' ? 38 : 10,
                      left: 0,
                      right: 0,
                      child: ValueListenableBuilder<int>(
                        valueListenable: _fotoPageNotifier,
                        builder: (_, pageIdx, _) => Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            fotos.length,
                            (i) => GestureDetector(
                              onTap: () => _fotoPageNotifier.value = i,
                              child: Padding(
                                padding: const EdgeInsets.all(5),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: pageIdx == i ? 18 : 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: pageIdx == i
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.68),
                          ],
                          stops: const [0.45, 1.0],
                        ),
                      ),
                    ),
                  ),
                  if (urgencia == 'Alta')
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        color: const Color(0xFFD32F2F),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 13,
                              color: Colors.white,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'URGENTE · NECESITA HOGAR YA',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // El pin de ubicación y las insignias de la derecha (Hogar de
                  // paso/compatible) antes eran dos Positioned
                  // independientes con un hueco fijo de 90px calculado para
                  // nombres de ciudad cortos — con un nombre más largo (ej.
                  // "Schiffdorf") el pin se comía ese hueco y quedaba tapado
                  // por "Hogar de paso" (el bug real que encontró Eliza
                  // probando). Con un Row de verdad, el ancho del pin se mide
                  // según su texto y el Wrap de la derecha ocupa lo que sobra
                  // — nunca se pueden superponer, sea cual sea el idioma o
                  // largo del nombre de la ciudad.
                  Positioned(
                    top: urgencia == 'Alta' ? 40 : 12,
                    left: 12,
                    right: 12,
                    // mainAxisAlignment.spaceBetween en vez de Expanded en el
                    // Wrap: con Expanded, el Wrap ocupaba TODO el ancho
                    // sobrante y WrapAlignment.end debía empujar su contenido
                    // al borde — pero con solo 1 o 2 insignias (menos ancho
                    // que el disponible) terminaban quedando bastante más al
                    // centro que pegadas al borde derecho (el caso real que
                    // reportó Eliza con "Eddy"). Con Flexible (no Expanded) +
                    // spaceBetween, el Wrap mide su propio contenido y el Row
                    // empuja ese bloque exacto contra el borde derecho — sin
                    // espacio de sobra que lo corra hacia el centro. Si el
                    // pin + las insignias no entran igual, Flexible deja que
                    // el pin achique su texto (ellipsis) y el Wrap pase a 2
                    // líneas, en vez de desbordar.
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Este pin es "dónde está", no "qué tan lejos" — no
                        // se le mezcla la distancia (esa ya tiene su propio
                        // texto aparte, "Se encuentra a X km de ti"). Antes
                        // cuando faltaba la ciudad cambiaba a mostrar la
                        // distancia acá mismo ("8875.1 km"), que se leía
                        // como si fuera el lugar — eso ya se sacó. La
                        // bandera SOLA (sin ciudad) también se sacó
                        // después: mostraba un país sin ningún lugar
                        // concreto adentro ("🇨🇴" a secas no es una
                        // ubicación útil), así que sin ciudad no se
                        // muestra el pin en absoluto. Pedido real de Eliza
                        // viendo a "Naranjita Lange" (sin ciudad guardada)
                        // con la bandera de Colombia sola en el feed.
                        if (ubicacion.isNotEmpty)
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.location_on,
                                    size: 12,
                                    color: appTeal,
                                  ),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: Text(
                                      ubicacion,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (bandera.isNotEmpty)
                                    const SizedBox(width: 3),
                                  // La bandera del país al lado de la
                                  // ciudad: "Córdoba" sola no distingue
                                  // Argentina de España, y una ciudad mal
                                  // geocodificada se notaba solo por una
                                  // distancia rara. Separada del texto de
                                  // la ciudad a propósito, en vez de
                                  // concatenada en el mismo Text — así el
                                  // "..." de una ciudad larga ("San
                                  // Cristóbal de las Casas") recorta SOLO
                                  // el nombre, sin comerse la bandera con
                                  // él. Hallazgo real de Eliza: "San
                                  // Cristóbal de ..." sin ninguna bandera
                                  // visible.
                                  if (bandera.isNotEmpty)
                                    Text(
                                      bandera,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                ],
                              ),
                            ),
                          )
                        else
                          const SizedBox.shrink(),
                        Flexible(
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (estadoAdopcion == 'Hogar de paso')
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: appTeal,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.home_outlined,
                                        size: 11,
                                        color: Colors.white,
                                      ),
                                      SizedBox(width: 3),
                                      Text(
                                        'Hogar de paso',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (estadoAdopcion == 'Regresado')
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE65100),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.refresh,
                                        size: 11,
                                        color: Colors.white,
                                      ),
                                      SizedBox(width: 3),
                                      Text(
                                        'Fue devuelto',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (score >= 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scoreColor(score),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '$score% compatible',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (fotos.length > 1)
                    Positioned.fill(
                      child: ValueListenableBuilder<int>(
                        valueListenable: _fotoPageNotifier,
                        builder: (_, pageIdx, _) => Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            pageIdx > 0
                                ? _flechaFoto(
                                    Icons.chevron_left,
                                    () => _fotoPageNotifier.value = pageIdx - 1,
                                    'Foto anterior',
                                  )
                                : const SizedBox(width: 52),
                            pageIdx < fotos.length - 1
                                ? _flechaFoto(
                                    Icons.chevron_right,
                                    () => _fotoPageNotifier.value = pageIdx + 1,
                                    'Foto siguiente',
                                  )
                                : const SizedBox(width: 52),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 14,
                    left: 16,
                    // `right` es lo que faltaba: sin él, este Positioned no
                    // tiene ningún ancho acotado (el Column mide lo que su
                    // contenido pida, sin límite), así que un nombre largo
                    // desbordaba derecho hacia afuera de la foto en vez de
                    // achicarse o cortarse — ni maxLines ni overflow hacen
                    // nada sin un ancho contra el cual medirse. Hallazgo
                    // real de Eliza: "Luna Maria blablablabla, Senior" se
                    // salía de la tarjeta, tapado por el borde de la foto.
                    right: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            children: [
                              TextSpan(text: '$nombre, '),
                              TextSpan(
                                text: edad,
                                style: const TextStyle(
                                  color: Color(0xFFB8F0CC),
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '$raza · $tamano',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Señal de que la foto se puede tocar para verla completa —
                  // antes el gesto existía pero era invisible, nada indicaba
                  // que la foto respondía al toque. Va abajo a la derecha porque
                  // la franja superior está siempre ocupada (píldora de
                  // ubicación, puntitos del carrusel y la badge de
                  // compatible, que puede ocupar varias filas):
                  // anclado arriba, la badge de "% compatible" se dibujaba
                  // encima y lo tapaba. Abajo a la izquierda va el nombre;
                  // esta esquina es la única siempre libre. Último en el Stack
                  // para pintarse sobre el degradado oscuro del pie de foto.
                  if (fotos.isNotEmpty)
                    Positioned(
                      bottom: 14,
                      right: 12,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.38),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.zoom_out_map,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (descripcion.isNotEmpty) ...[
                  Text(
                    descripcion,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                      height: 1.4,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                ],
                if (tags.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: tags
                        .map(
                          (t) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: appTeal.withValues(alpha: 0.5),
                              ),
                              borderRadius: BorderRadius.circular(20),
                              color: appTeal.withValues(alpha: 0.07),
                            ),
                            child: Text(
                              t,
                              style: const TextStyle(
                                fontSize: 12,
                                color: appTeal,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 14),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap:
                            (esCreadoPorAlbergue(creadoPor) &&
                                rescatistaId.isNotEmpty)
                            ? () {
                                FirebaseAnalytics.instance
                                    .logEvent(
                                      name: 'vio_perfil_albergue',
                                      parameters: {'albergue_id': rescatistaId},
                                    )
                                    .catchError((_) {});
                                context.push(
                                  AppRoutes.alberguePublico,
                                  extra: rescatistaId,
                                );
                              }
                            : null,
                        child: Row(
                          children: [
                            AvatarPersona(
                              fotoBase64: rescatistaFotoBase64,
                              fotoUrl: rescatistaFotoUrl,
                              inicial: rescatista.isNotEmpty
                                  ? rescatista[0].toUpperCase()
                                  : 'R',
                              radius: 16,
                              backgroundColor: appTeal.withValues(alpha: 0.15),
                              textColor: appTeal,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    esCreadoPorAlbergue(creadoPor)
                                        ? 'Albergue'
                                        : 'Rescatista',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFFAAAAAA),
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          rescatista,
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: appTeal,
                                          ),
                                        ),
                                      ),
                                      if (esCreadoPorAlbergue(creadoPor)) ...[
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.chevron_right,
                                          size: 14,
                                          color: appTeal,
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Solo ícono, sin el texto "Compartir" que tenía antes —
                    // mis_rescates_screen.dart ya mostraba este mismo botón
                    // sin texto (con Tooltip), y tener las dos variantes en la
                    // misma app era la inconsistencia real que notó Eliza.
                    // El Tooltip conserva la accesibilidad que el texto daba.
                    Tooltip(
                      message: 'Compartir',
                      child: GestureDetector(
                        onTap: () => compartirAnimal(
                          context: context,
                          nombre: nombre,
                          especie: especie,
                          edad: edad,
                          ubicacion: ubicacion,
                          tags: tags,
                          fotoUrl: fotoUrl,
                          paisCodigo: a['paisCodigo'] as String?,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: appTeal.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: appTeal.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Icon(
                            Icons.share_outlined,
                            size: 16,
                            color: appTeal,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => showModalBottomSheet(
                    context: context,
                    useSafeArea: true,
                    isScrollControlled: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    builder: (_) => _MeInteresaSheet(
                      nombre: nombre,
                      especie: especie,
                      edad: edad,
                      ubicacion: ubicacion,
                      tags: tags,
                      fotoUrl: fotoUrl,
                      rescatistaId: rescatistaId,
                      rescatista: rescatista,
                      rescateId: rescateId,
                      estadoAdopcion: estadoAdopcion,
                      creadoPor: creadoPor,
                      tamano: tamano,
                      energia: a['energia'] as String?,
                      okConNinos: a['okConNinos'] as bool?,
                      okConMascotas: a['okConMascotas'] as bool?,
                      requiereExperiencia: a['requiereExperiencia'] as bool?,
                    ),
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3CD),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFFFB800).withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('💛', style: TextStyle(fontSize: 16)),
                        SizedBox(width: 8),
                        Text(
                          'Me interesa ayudar',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF8B6914),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // `label` es obligatorio a propósito (no opcional con default) — así
  // ningún botón nuevo que use este widget compartido puede olvidarse de
  // pasarlo. Antes las 3 acciones principales del feed (pasar, ver más,
  // favorito) no tenían ninguna etiqueta para lectores de pantalla.
  // Hallazgo de auditoría de código.
  Widget _actionBtn(
    IconData icon,
    Color bg,
    Color iconColor,
    double size,
    VoidCallback onTap,
    String label,
  ) => Tooltip(
    message: label,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(icon, color: iconColor, size: size * 0.40),
      ),
    ),
  );
}

class _MeInteresaSheet extends StatelessWidget {
  final String nombre,
      especie,
      edad,
      ubicacion,
      rescatistaId,
      rescatista,
      rescateId,
      estadoAdopcion,
      creadoPor,
      tamano;
  final List<String> tags;
  final String? fotoUrl;
  final String? energia;
  final bool? okConNinos, okConMascotas, requiereExperiencia;

  const _MeInteresaSheet({
    required this.nombre,
    required this.especie,
    required this.edad,
    required this.ubicacion,
    required this.rescatistaId,
    required this.rescatista,
    required this.rescateId,
    required this.tags,
    required this.estadoAdopcion,
    required this.creadoPor,
    required this.tamano,
    this.fotoUrl,
    this.energia,
    this.okConNinos,
    this.okConMascotas,
    this.requiereExperiencia,
  });

  /// Abre la pantalla de solicitud con [tipo] ('adopcion' u
  /// 'hogar_de_paso').
  ///
  /// Los dos caminos mandan EXACTAMENTE los mismos datos del animal: es un
  /// solo mapa y no uno por opción, para que no puedan volver a divergir.
  /// Ya pasó una vez con las etiquetas de compatibilidad —faltaban acá, y
  /// entonces compatibilidad.dart las completaba con sus valores por
  /// defecto: el puntaje salía calculado contra un animal "Mediano" aunque
  /// el de verdad fuera "Pequeño"— y no se notaba, porque un puntaje
  /// equivocado se ve igual de convincente que uno correcto.
  void _pedir(BuildContext context, String tipo) {
    Navigator.pop(context);
    context.push(
      AppRoutes.solicitudAdopcion,
      extra: {
        'nombre': nombre, 'especie': especie, 'edad': edad,
        'ubicacion': ubicacion, 'rescatista': rescatista,
        'rescatistaId': rescatistaId, 'rescateId': rescateId,
        'fotoUrl': fotoUrl,
        'tipoSolicitud': tipo,
        'creadoPor': creadoPor,
        'tamano': tamano,
        'energia': energia,
        'okConNinos': okConNinos,
        'okConMascotas': okConMascotas,
        'requiereExperiencia': requiereExperiencia,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      // SingleChildScrollView a propósito: mismo motivo que
      // perfil_rescatista_screen.dart/perfil_adoptante_screen.dart — en
      // horizontal, en un teléfono real (menos alto disponible que el
      // emulador con el que lo había probado), este Column no entraba
      // entero y "Hacer una pregunta" quedaba cortado. Hallazgo de prueba
      // en teléfono real, 2026-08-03.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '¿Cómo querés ayudar a $nombre?',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            // Adoptar va PRIMERO y por eso existe: este panel pregunta
            // "¿cómo querés ayudar?" y hasta ahora ofrecía dos de las tres
            // formas, justo sin la principal. Para adoptar desde el feed
            // había que entrar por "Ser hogar de paso" y recién en la
            // pantalla siguiente cambiar el botón a "Adoptar", o salir del
            // panel e ir por la ficha. Quien tocaba "Me interesa ayudar"
            // con ganas de adoptar no encontraba la palabra en ningún lado.
            //
            // sePuedeAdoptar() decide si mostrarlo, la misma función que ya
            // usan el feed, la ficha, favoritos, el perfil público del
            // albergue y el repositorio al aprobar. No hay una lista de
            // estados nueva acá: un animalito en "Hogar de paso" SÍ se
            // puede adoptar (por eso la opción de abajo se esconde y esta
            // no), y ese matiz vive en un solo lugar a propósito.
            if (sePuedeAdoptar(estadoAdopcion)) ...[
              _opcion(
                context,
                emoji: '🏠',
                titulo: 'Adoptar',
                subtitulo: 'Querés que sea parte de tu familia para siempre',
                onTap: () => _pedir(context, 'adopcion'),
              ),
              const SizedBox(height: 10),
            ],
            // sePuedeSerHogarDePaso(), no una comparación a mano: está
            // definida sobre sePuedeAdoptar() para que las dos opciones de
            // arriba no puedan contradecirse entre sí.
            if (sePuedeSerHogarDePaso(estadoAdopcion)) ...[
              _opcion(
                context,
                emoji: '🏡',
                titulo: 'Ser hogar de paso',
                subtitulo:
                    'Lo/la cuidás temporalmente mientras encuentra familia',
                onTap: () => _pedir(context, 'hogar_de_paso'),
              ),
              const SizedBox(height: 10),
            ],
            _opcion(
              context,
              emoji: '💬',
              titulo: 'Hacer una pregunta',
              subtitulo: 'Escribile directamente al rescatista',
              onTap: () {
                Navigator.pop(context);
                // Abre el chat vacío (sin mensaje enlatado) para que el adoptante
                // escriba su propia pregunta. ChatScreen ya sabe crear/encontrar
                // el chat solo, usando el mismo id determinístico (rescateId+uid)
                // que el resto de la app — así este chat es uno más normal y
                // aparece en la bandeja del rescatista como cualquier otro.
                context.push(
                  AppRoutes.chat,
                  extra: (
                    esRescatista: false,
                    chatId: null,
                    animal: {
                      'nombre': nombre,
                      'rescatista': rescatista,
                      'rescatistaId': rescatistaId,
                      'fotoUrl': fotoUrl,
                      'rescateId': rescateId,
                      'especie': especie,
                      'ubicacion': ubicacion,
                      'descripcion': '',
                      'tags': tags,
                      'edad': edad,
                      'creadoPor': creadoPor,
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _opcion(
    BuildContext context, {
    required String emoji,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: appInk,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitulo,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: Colors.grey.shade400),
        ],
      ),
    ),
  );
}
