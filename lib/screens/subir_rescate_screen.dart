import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:go_router/go_router.dart';
import '../routing/app_router.dart';
import '../theme.dart';
import '../widgets/chips_seleccionables.dart';
import '../widgets/confirmar_ciudad_resuelta.dart';
import '../widgets/elegir_foto_animal.dart';
import '../widgets/tardando_mucho_mixin.dart';
import '../data/creator_role.dart';
import '../data/rescates_repository.dart';
import '../data/usuarios_repository.dart';
import '../data/foto_normalizador.dart';
import '../services/ubicacion_service.dart';
import '../services/ubicacion_lifecycle.dart';
import '../widgets/campo_ciudad.dart';

class SubirRescateScreen extends StatefulWidget {
  final bool esAlbergue;
  const SubirRescateScreen({super.key, this.esAlbergue = false});
  @override
  State<SubirRescateScreen> createState() => _SubirRescateScreenState();
}

class _SubirRescateScreenState extends State<SubirRescateScreen>
    with
        TardandoMuchoMixin,
        WidgetsBindingObserver,
        ReintentoUbicacionTrasAjustes {
  final _nombreCtl = TextEditingController();
  final _lugarCtl = TextEditingController();
  final _descCtl = TextEditingController();

  final _razaCtl = TextEditingController();
  final List<XFile> _fotos = [];
  String _especie = 'Perro';
  String _estado = 'Sano';
  String _urgencia = 'Alta';
  String _energia = 'Tranquilo';
  String _tamano = 'Mediano';
  String _edad = 'Cachorro';
  String _genero = 'No sé';
  String _okNinos = 'Sí';
  String _okMascotas = 'Sí';
  String _requiereExp = 'No';
  String _tipoRaza = 'Criolla';
  // 'Aún no lo sé' por defecto, no 'No' — un animal recién rescatado de la
  // calle todavía no pasó por veterinario, y forzar Sí/No hacía que la
  // gente adivinara o dejara el dato mal puesto sin querer (sugerencia
  // real de un tester que rescató un gato de la calle y no tenía cómo
  // saberlo en el momento de publicar).
  String _vacunado = 'Aún no lo sé';
  String _desparasitado = 'Aún no lo sé';

  // Del repositorio, no declaradas acá: son los valores válidos del dominio
  // y tienen que ser LOS MISMOS que usa editar_rescate_screen.dart. Cuando
  // cada pantalla tenía su propia copia ya se habían desincronizado (ver el
  // comentario en RescatesRepository) y un animal publicado como 'Herido'
  // se abría en Editar sin ningún estado marcado.
  static const _especies = RescatesRepository.especies;
  static const _estados = RescatesRepository.estados;
  static const _urgencias = RescatesRepository.urgencias;
  static const _energias = RescatesRepository.energias;
  static const _tamanos = RescatesRepository.tamanos;
  static const _edades = RescatesRepository.edades;
  static const _generos = RescatesRepository.generos;
  static const _siNoOpts = RescatesRepository.siNo;
  static const _saludOpts = RescatesRepository.salud;
  static const _tipoRazaOpts = RescatesRepository.tiposRaza;

  Color _urgenciaColor(String u) => switch (u) {
    'Alta' => const Color(0xFFD32F2F),
    'Media' => const Color(0xFFE65100),
    _ => appTeal,
  };

  /// elegirFotoAnimal (widgets/elegir_foto_animal.dart) muestra la hoja y hace el pickImage,
  /// con el manejo de "cámara no disponible" que antes vivía sólo acá — la
  /// pantalla de editar tenía su propia copia SIN ese try/catch. El tope de
  /// 2 fotos se queda de este lado: depende del estado propio de esta
  /// pantalla (una lista), no del picker.
  Future<void> _mostrarOpcionesFoto() async {
    if (_fotos.length >= 2) return;
    final img = await elegirFotoAnimal(context);
    if (img != null && mounted) setState(() => _fotos.add(img));
  }

  bool _publicando = false;
  double _progreso = 0;
  // Mientras no hay señal, la subida no tiene bytes que transferir todavía
  // — _progreso se queda en 0 y el botón solo muestra un círculo girando,
  // sin ningún texto, hasta que el timeout de 45s se cumple. Sin este
  // aviso parecía que la app estaba colgada (el bug real que reportó
  // Eliza: "el mensaje se demora mucho en presentarse").
  double? _latitud;
  double? _longitud;
  String _paisCodigo = '';

  // Se prende apenas la persona toca el campo de texto a mano, y se apaga
  // cada vez que texto y coordenadas vuelven a quedar sincronizados entre
  // sí (por GPS o por el geocodificador en _publicar()) — ver ese comentario
  // para el porqué completo. Mismo patrón que editar_rescate_screen.dart.
  bool _ubicacionTocadaAMano = false;

  /// Para dispararle la detección al campo de ciudad desde acá: al abrir la
  /// pantalla, al volver de los Ajustes, y desde el diálogo de "publicar
  /// sin ubicación". Ver CampoCiudadControlador — antes esta pantalla tenía
  /// su propia copia entera de la detección, y editar_rescate una tercera.
  final _ciudadCtrl = CampoCiudadControlador();
  // El texto que estaba en el campo la última vez que quedó sincronizado
  // con _latitud/_longitud (arranca vacío: acá no hay un "original" fijo
  // como en editar_rescate_screen.dart, el animal todavía no existe). Es a
  // donde se vuelve si la persona cancela la confirmación de una ciudad
  // nueva en _publicar() — revertir al texto Y no tocar las coordenadas
  // las deja consistentes entre sí, en vez de vaciar el campo y dejar
  // coordenadas de otro lugar colgadas.
  String _lugarSincronizado = '';

  @override
  void initState() {
    super.initState();
    _lugarCtl.addListener(() => _ubicacionTocadaAMano = true);
    if (widget.esAlbergue)
      _cargarCiudadAlbergue();
    else
      _ciudadCtrl.detectar();
  }

  // El botón "Abrir Ajustes" del aviso de permiso bloqueado saca a la
  // persona de la app; sin esto, volver de Ajustes con el permiso recién
  // otorgado la dejaba igual, con el aviso rojo todavía en pantalla, sin
  // ninguna señal de que ahora sí podía funcionar — tenía que darse cuenta
  // sola de tocar el campo de ubicación de nuevo. El reintento (solo una
  // vez, solo tras volver de Ajustes) vive en ReintentoUbicacionTrasAjustes
  // — ver ese archivo para el hallazgo completo del bucle que esto evita
  // (real de Eliza, 2026-08-06: "parpadeaba sin parar y la pantalla
  // quedaba inusable").
  @override
  bool get yaTieneUbicacion => widget.esAlbergue || _latitud != null;
  @override
  bool get detectandoUbicacion => _ciudadCtrl.detectando;
  @override
  void reintentarConPermiso() => _ciudadCtrl.detectar();

  Future<void> _cargarCiudadAlbergue() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    // UsuariosRepository.ubicacionDeAlbergue: la lectura del perfil Y la
    // red de seguridad que repara los perfiles viejos sin coordenadas.
    // Vive compartida porque la pantalla de publicar en LOTE necesita
    // exactamente lo mismo y antes solo leía, sin reparar — ver el doc de
    // esa función.
    final ubi = await UsuariosRepository().ubicacionDeAlbergue(
      uid: uid,
      geocodificar: UbicacionService.desdeTexto,
    );
    if (!mounted) return;
    setState(() {
      if (ubi.ciudad.isNotEmpty) _lugarCtl.text = ubi.ciudad;
      _latitud = ubi.latitud;
      _longitud = ubi.longitud;
      if (ubi.paisCodigo.isNotEmpty) _paisCodigo = ubi.paisCodigo;
      // El orden importa: escribir el texto prende _ubicacionTocadaAMano,
      // así que el reset va DESPUÉS.
      _ubicacionTocadaAMano = false;
      _lugarSincronizado = _lugarCtl.text;
    });
  }

  /// GPS-first: un rescate se publica desde donde está el animal, así que
  /// acá la ubicación se detecta sola al abrir la pantalla (ver initState) y
  /// el texto es el respaldo, no el camino principal. `precision: high` por
  /// el mismo motivo: la distancia que va a ver cada adoptante sale de acá.
  ///
  /// Toda la secuencia de servicio/permiso/GPS/geocoding y sus reintentos
  /// vive en UbicacionService. Lo único que queda acá es la UI, que es lo
  /// que de verdad distingue a esta pantalla: avisos con botón a Ajustes, y

  // Cuando la usuaria confirma "Publicar igual" habiendo un duplicado, se
  // guarda el rastro en el nuevo doc (con qué otro animal se cruzó y
  // cuándo) — un aviso que se puede ignorar sin dejar huella se siente
  // como "¿entonces para qué avisó?", y sin este dato no hay forma de
  // encontrar después, desde la base, qué publicaciones fueron duplicados
  // confirmados a propósito para poder limpiarlas.
  String? _duplicadoDeId;

  Future<void> _publicar() async {
    if (_fotos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes agregar al menos una foto del animal'),
          backgroundColor: msgError,
        ),
      );
      return;
    }
    _duplicadoDeId = null;
    // El spinner arranca ACÁ, antes del chequeo de duplicado (una consulta
    // a Firestore de TODOS tus animales publicados bajo este rol, que
    // tarda más cuanto más historial tengas — un albergue con muchos
    // animales ya publicados la nota más) — no recién en publicarConFotos.
    // Antes el botón se quedaba con su apariencia normal, sin ningún
    // spinner ni aviso, durante todo ese chequeo (y el diálogo de GPS más
    // abajo, si aplica): parecía que tocar "Publicar" no había hecho nada,
    // aunque sí estuviera trabajando. Hallazgo real de Eliza: "se demora
    // mucho en almacenarlo" al publicar sin GPS y al publicar como
    // albergue — los dos casos pasan por este mismo tramo silencioso.
    setState(() => _publicando = true);
    // Aviso, no bloqueo: si ya tenés otro animal publicado con este mismo
    // nombre EN ESTE MISMO ROL, lo más común es que sea una carga duplicada
    // por accidente — pero un nombre repetido entre dos animales reales
    // también puede pasar, así que se deja publicar igual si es a
    // propósito. No cruza rescatista con albergue de la misma cuenta: son
    // dos "negocios" distintos aunque el login sea el mismo.
    final nombreIngresado = _nombreCtl.text.trim();
    if (nombreIngresado.isNotEmpty) {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final duplicado = await RescatesRepository().buscarDuplicado(
        uid: uid,
        nombre: nombreIngresado,
        role: widget.esAlbergue ? CreatorRole.albergue : CreatorRole.rescatista,
        especie: _especie,
      );
      if (!mounted) return;
      if (duplicado != null) {
        // 3 salidas en vez de 2: "Ver ficha existente" además de
        // cancelar/continuar, para no dejar a la usuaria adivinando cuál
        // es el otro animal — antes solo podía cancelar y buscarlo ella
        // misma en "Mis animales".
        final accion = await showDialog<String>(
          context: context,
          builder: (dlgCtx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Posible animal duplicado'),
            content: Text(
              'Ya tenés otro animal llamado "$nombreIngresado" '
              '($_especie). Si es a propósito (dos animales distintos con '
              'el mismo nombre, uno que volvió, etc.) podés publicar igual. '
              'Si fue sin querer, revisá la ficha existente primero.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx, 'cancelar'),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx, 'ver'),
                child: const Text('Ver ficha existente'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx, 'continuar'),
                child: const Text(
                  'Publicar igual',
                  style: TextStyle(color: appTeal),
                ),
              ),
            ],
          ),
        );
        if (accion == 'ver') {
          if (!mounted) return;
          setState(() => _publicando = false);
          context.push(
            AppRoutes.editarRescate,
            extra: (docId: duplicado.id, data: duplicado.data()),
          );
          return;
        }
        if (accion != 'continuar') {
          setState(() => _publicando = false);
          return;
        }
        _duplicadoDeId = duplicado.id;
      }
    }
    // El diálogo de "posible duplicado" de arriba también es un await —
    // sin este chequeo, si la persona salía de la pantalla justo mientras
    // decidía "Publicar igual", el showDialog de abajo (unas líneas más)
    // usaba un context que ya no era válido (use_build_context_synchronously,
    // hallazgo real de la auditoría previa a subir a Play).
    if (!mounted) return;
    // Si el texto de ubicación se tocó a mano (nunca se usó el ícono de
    // GPS, o se usó y DESPUÉS se retocó el texto), hay que validarlo contra
    // un geocodificador real antes de guardar — sin esto, cualquier texto
    // (incluida "verduras") se guardaba tal cual, sin haber existido nunca
    // de verdad. El ícono de detección automática es un atajo para no
    // escribir a mano, no la única barrera contra datos falsos — esa
    // barrera tiene que vivir acá, en la validación, sea cual sea el
    // camino que se usó para llegar al texto. Mismo patrón ya probado en
    // editar_rescate_screen.dart, albergue_perfil_screen.dart y
    // aliado_perfil_screen.dart.
    if (_ubicacionTocadaAMano && _lugarCtl.text.trim().isNotEmpty) {
      // Misma función compartida que las otras 3 pantallas que piden una
      // ciudad — ver el comentario de resolverCiudadEscrita(). Antes acá
      // vivía una copia a mano de esta secuencia.
      final elegida = await resolverCiudadEscrita(
        context,
        _lugarCtl.text.trim(),
      );
      // null = canceló ("No, corregir"), o no se pudo verificar
      // (resolverCiudadEscrita ya explicó por qué). Ninguno de los dos debe
      // dejar a la persona TRABADA sin forma de publicar nada — se vuelve
      // al último texto que había quedado sincronizado con
      // _latitud/_longitud (vacío si nunca hubo ninguno), dejando las
      // coordenadas SIN tocar, y se corta ACÁ sin publicar todavía. Antes
      // seguía derecho a publicar con lo que ya había — mismo bug que
      // editar_rescate_screen.dart: tocar "No, corregir" (que suena a
      // "dejame corregir eso") terminaba publicando y sacando de la
      // pantalla igual, sin darte la chance de reintentar la ciudad.
      // Hallazgo real de Eliza en editar, mismo camino compartido acá. Si
      // de verdad no querés resolver la ciudad, un segundo toque de
      // "Publicar" sin volver a tocar ese campo publica igual (el texto ya
      // quedó revertido a uno válido) — se sigue pudiendo salir del paso
      // sin quedar en bucle, solo que ya no de forma silenciosa en el
      // mismo toque.
      if (elegida == null) {
        _lugarCtl.text = _lugarSincronizado;
        _ubicacionTocadaAMano = false;
        if (mounted) setState(() => _publicando = false);
        return;
      } else {
        // Los tres datos del MISMO candidato, siempre — ver el invariante
        // en confirmar_ciudad_resuelta.dart. El nombre es el que resolvió
        // el geocodificador, nunca el texto tecleado: si alguien escribió
        // "Córdoba, Argentina" para desambiguar de Córdoba, España, se
        // guarda "Córdoba" y el país sale de la bandera 🇦🇷, no repetido en
        // el texto. El orden importa: `_lugarCtl.text` antes de
        // `_ubicacionTocadaAMano = false`, para no reactivar el listener
        // que lo prendería de nuevo.
        _latitud = elegida.lat;
        _longitud = elegida.lng;
        _lugarCtl.text = elegida.ciudadResuelta;
        _paisCodigo = elegida.paisCodigo;
        _lugarSincronizado = _lugarCtl.text;
      }
      _ubicacionTocadaAMano = false;
    }
    // La ubicación ya no bloquea la publicación — antes, si el GPS fallaba
    // o tardaba (señal débil, permiso recién concedido, lo que sea), el
    // rescatista quedaba sin poder publicar y sin un aviso claro de por qué.
    // Ahora se avisa y se deja elegir: publicar igual (sin distancia en el
    // feed hasta que se agregue la ubicación editando) o cancelar y reintentar.
    // mounted otra vez acá: la validación de arriba agregó sus propios
    // await (geocodificarCiudad, placemarkFromCoordinates) después del
    // último chequeo — mismo tipo de bug que ya se encontró en la
    // auditoría previa a subir a Play (ver el diálogo de duplicado, más
    // arriba en esta función).
    if (!mounted) return;
    if (_latitud == null && !widget.esAlbergue) {
      final continuar = await showDialog<bool>(
        context: context,
        builder: (dlgCtx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Sin ubicación detectada'),
          content: const Text(
            'No se detectó tu ubicación GPS. Podés publicar igual. El animal '
            'no va a aparecer con distancia en el feed hasta que agregues la '
            'ubicación más tarde, editando la publicación.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx, false),
              child: const Text('Volver y detectar de nuevo'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx, true),
              child: const Text(
                'Publicar sin ubicación',
                style: TextStyle(color: appTeal),
              ),
            ),
          ],
        ),
      );
      // "Volver y detectar de nuevo" antes solo cerraba el diálogo y
      // dejaba al rescatista de nuevo en el formulario sin indicar qué
      // hacer — el botón decía "reintentar" pero no reintentaba nada.
      // Ahora dispara la detección de GPS de una, en vez de obligarlo a
      // encontrar y tocar el campo de ubicación por su cuenta.
      if (continuar != true) {
        setState(() => _publicando = false);
        if (mounted) _ciudadCtrl.detectar();
        return;
      }
    }
    setState(() => _progreso = 0);
    iniciarTimerTardando(const Duration(seconds: 6));

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      // Se dispara ACÁ, antes de esperar las fotos — es una lectura
      // independiente (el nombre/logo del albergue no depende en nada de
      // las fotos del animal), así que no hay motivo para esperarla recién
      // después de que las fotos terminen de normalizarse. Antes corría en
      // serie, sumando una ida y vuelta completa a Firestore ARRIBA del
      // tiempo que ya tardan las fotos — el tramo que más se notaba
      // publicando como albergue. Hallazgo real de Eliza: "guardar
      // animalitos se estaba demorando muchísimo".
      // Se lee el perfil SIEMPRE, no solo publicando como albergue.
      // Antes la rama de rescatista se quedaba con el displayName de
      // Google, mientras que los avisos por chat sobre ese MISMO animal
      // usaban nombrePropioDesde (que prefiere `usuarios.nombre`). Quien
      // se corrigio el nombre en la app publicaba con un nombre y
      // conversaba con otro, sobre el mismo animalito.
      final userDocFuture = FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get();

      // Las dos fotos se normalizan en paralelo — normalizarFoto() corre
      // en su propio isolate (compute()), así que esto sí es paralelismo
      // real, no solo dos await seguidos en el mismo hilo. Corre AL MISMO
      // TIEMPO que userDocFuture de arriba, no después.
      final normalizadas = await Future.wait([
        normalizarFoto(_fotos[0].path),
        if (_fotos.length > 1) normalizarFoto(_fotos[1].path),
      ]);

      final nombreDeLaCuenta =
          FirebaseAuth.instance.currentUser?.displayName ?? 'Rescatista';
      String? fotoPublicadorBase64;
      String? fotoPublicadorUrl;
      // Para cuando llegamos acá, userDocFuture ya viene corriendo desde
      // antes de las fotos — este await casi nunca espera de verdad.
      final userDoc = await userDocFuture;
      // UsuariosRepository.nombrePropioDesde — misma regla que usan los
      // avisos automáticos, en vez de la copia a mano que había acá
      // ("si hay albergueNombre y no está vacío, usalo"). La versión
      // `Desde` no vuelve a leer el documento: aprovecha el que esta
      // pantalla YA tiene cargado. Con `creadoPor` puesto segun el rol con
      // el que se publica, resuelve las dos ramas sin ramificar acá.
      final nombrePublicador = UsuariosRepository.nombrePropioDesde(
        datosUsuario: userDoc.data(),
        creadoPor: widget.esAlbergue ? 'albergue' : 'rescatista',
        nombreDeLaCuenta: nombreDeLaCuenta,
      );
      if (widget.esAlbergue) {
        fotoPublicadorBase64 = userDoc.data()?['fotoBase64'] as String?;
      } else {
        // `usuarios.foto` es la copia que main.dart mantiene al día contra
        // el photoURL de Google; leerla de acá (y no de FirebaseAuth) hace
        // que el trigger pueda refrescar esta misma copia después, porque
        // las dos miran el mismo campo. Ver CAMPOS_PERFIL_A_ANIMAL_RESCATISTA.
        fotoPublicadorUrl =
            userDoc.data()?['foto'] as String? ??
            FirebaseAuth.instance.currentUser?.photoURL;
      }

      // "Crear doc sin fotos → subir en paralelo → vincular", con rollback
      // automático si algo falla, vive en RescatesRepository.publicarConFotos
      // — antes esa secuencia estaba duplicada acá y en
      // subir_lote_screen.dart (hallazgo de auditoría de código).
      final resultado = await RescatesRepository().publicarConFotos(
        uid: uid,
        role: widget.esAlbergue ? CreatorRole.albergue : CreatorRole.rescatista,
        datos: {
          'nombre': _nombreCtl.text.trim(),
          'especie': _especie,
          'raza': _tipoRaza == 'Criolla'
              ? 'Criolla'
              : _razaCtl.text.trim().isEmpty
              ? 'Raza definida'
              : _razaCtl.text.trim(),
          'estado': _estado,
          'urgencia': _urgencia,
          'ubicacion': _lugarCtl.text.trim(),
          'descripcion': _descCtl.text.trim(),
          'estadoAdopcion': 'Rescatado',
          'rescatistaNombre': nombrePublicador,
          if (fotoPublicadorBase64 != null)
            'rescatistaFotoBase64': fotoPublicadorBase64,
          if (fotoPublicadorUrl != null) 'rescatistaFotoUrl': fotoPublicadorUrl,
          if (_latitud != null) 'latitud': _latitud,
          if (_longitud != null) 'longitud': _longitud,
          if (_paisCodigo.isNotEmpty) 'paisCodigo': _paisCodigo,
          'edad': _edad,
          'genero': _genero,
          'energia': _energia,
          'tamano': _tamano,
          'okConNinos': _okNinos == 'Sí',
          'okConMascotas': _okMascotas == 'Sí',
          'requiereExperiencia': _requiereExp == 'Sí',
          // String, no bool: a diferencia de los de arriba, acá "Aún no lo
          // sé" es una tercera respuesta honesta y real, no una falta de
          // dato — un animal recién rescatado de la calle todavía no pasó
          // por veterinario cuando se publica.
          'vacunado': _vacunado,
          'desparasitado': _desparasitado,
          if (_duplicadoDeId != null) 'duplicadoDeId': _duplicadoDeId,
          if (_duplicadoDeId != null)
            'duplicadoConfirmadoEn': FieldValue.serverTimestamp(),
        },
        fotos: normalizadas,
        onProgreso: (p) {
          if (mounted) setState(() => _progreso = p);
        },
      );

      FirebaseAnalytics.instance
          .logEvent(
            name: 'animal_publicado',
            parameters: {
              'especie': _especie,
              'creado_por': widget.esAlbergue ? 'albergue' : 'rescatista',
            },
          )
          .catchError((_) {});

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('¡Rescate publicado! 🐾'),
          content: Text(
            '${_nombreCtl.text.isEmpty ? "El animal" : _nombreCtl.text} '
            'fue publicado con urgencia $_urgencia'
            '${_lugarCtl.text.isNotEmpty ? ' en ${_lugarCtl.text}' : ''}.'
            '${resultado.foto2Fallo ? ' La segunda foto no se pudo subir. Podés agregarla después editando la publicación.' : ''}',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text(
                'Ver rescates',
                style: TextStyle(color: appTeal),
              ),
            ),
          ],
        ),
      );
    } catch (_) {
      // El rollback (borrar doc + fotos si algo falló a mitad de camino)
      // ya lo hace RescatesRepository.publicarConFotos internamente —
      // acá solo queda avisar.
      if (!mounted) return;
      // Mismo estilo y comportamiento que subir_lote_screen.dart (a
      // propósito, ver ese archivo): vuelve a la pantalla principal en vez
      // de dejar a la persona parada en el formulario con el error — antes
      // los dos flujos (uno y en lote) reaccionaban distinto ante la misma
      // falla de conexión, algo que reportó Eliza probando en modo avión.
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo publicar ${_nombreCtl.text.isEmpty ? "el animal" : _nombreCtl.text}. '
            'Revisá tu conexión e intentá de nuevo.',
          ),
          backgroundColor: msgError,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      cancelarTimerTardando();
      if (mounted)
        setState(() {
          _publicando = false;
          tardandoMucho = false;
        });
    }
  }

  // Sin esto, un aviso como "Activa el GPS en tu dispositivo" (duration: 8s)
  // seguía visible sobre la pantalla de ATRÁS si la persona volvía antes de
  // que se cerrara solo — MaterialApp usa un solo ScaffoldMessenger para
  // toda la app por default, así que un SnackBar no "pertenece" a la
  // pantalla que lo mostró. Capturado en didChangeDependencies (no en
  // dispose directamente): ScaffoldMessenger.of(context) necesita un
  // context todavía válido en el árbol, y dispose() ya no lo garantiza.
  // Hallazgo real de Eliza: "estoy en la pagina inicial del rescatista y el
  // mensaje sigue ahi".
  ScaffoldMessengerState? _scaffoldMessenger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scaffoldMessenger = ScaffoldMessenger.of(context);
  }

  @override
  void dispose() {
    // El removeObserver de WidgetsBindingObserver ahora lo hace
    // ReintentoUbicacionTrasAjustes.dispose(), alcanzado por el
    // super.dispose() de acá abajo.
    _scaffoldMessenger?.clearSnackBars();
    _nombreCtl.dispose();
    _lugarCtl.dispose();
    _descCtl.dispose();
    _razaCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appBg,
      body: SafeArea(
        child: Column(
          children: [
            _appBar(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    _section('Fotos del animal'),
                    const SizedBox(height: 10),
                    _fotoGrid(),
                    const SizedBox(height: 20),
                    _campoNombre(),
                    const SizedBox(height: 16),
                    _section('Raza'),
                    const SizedBox(height: 8),
                    _chips(
                      _tipoRazaOpts,
                      _tipoRaza,
                      (v) => setState(() {
                        _tipoRaza = v;
                        _razaCtl.clear();
                      }),
                      appTeal,
                    ),
                    if (_tipoRaza == 'Raza definida') ...[
                      const SizedBox(height: 10),
                      _field(
                        '¿Cuál raza?',
                        _razaCtl,
                        hint: 'ej. Golden Retriever, Siamés...',
                      ),
                    ],
                    const SizedBox(height: 16),
                    _section('Especie'),
                    const SizedBox(height: 8),
                    _chips(
                      _especies,
                      _especie,
                      (v) => setState(() => _especie = v),
                      appTeal,
                    ),
                    const SizedBox(height: 20),
                    _section('Edad aproximada'),
                    const SizedBox(height: 8),
                    _chips(
                      _edades,
                      _edad,
                      (v) => setState(() => _edad = v),
                      appTeal,
                    ),
                    const SizedBox(height: 20),
                    _section('Género'),
                    const SizedBox(height: 8),
                    _chips(
                      _generos,
                      _genero,
                      (v) => setState(() => _genero = v),
                      appTeal,
                    ),
                    const SizedBox(height: 20),
                    _section('Estado de salud'),
                    const SizedBox(height: 8),
                    _chips(
                      _estados,
                      _estado,
                      (v) => setState(() => _estado = v),
                      appTeal,
                    ),
                    const SizedBox(height: 20),
                    _section('¿Está vacunado?'),
                    const SizedBox(height: 8),
                    _chips(
                      _saludOpts,
                      _vacunado,
                      (v) => setState(() => _vacunado = v),
                      appTeal,
                    ),
                    const SizedBox(height: 20),
                    _section('¿Está desparasitado?'),
                    const SizedBox(height: 8),
                    _chips(
                      _saludOpts,
                      _desparasitado,
                      (v) => setState(() => _desparasitado = v),
                      appTeal,
                    ),
                    const SizedBox(height: 20),
                    _section('Urgencia'),
                    const SizedBox(height: 8),
                    _chips(
                      _urgencias,
                      _urgencia,
                      (v) => setState(() => _urgencia = v),
                      _urgenciaColor(_urgencia),
                    ),
                    const SizedBox(height: 28),
                    _sectionLabel('Compatibilidad para adopción'),
                    const SizedBox(height: 4),
                    Text(
                      'Estas etiquetas ayudan a encontrar el hogar ideal',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _section('Nivel de energía'),
                    const SizedBox(height: 8),
                    _chips(
                      _energias,
                      _energia,
                      (v) => setState(() => _energia = v),
                      const Color(0xFF7C4DFF),
                    ),
                    const SizedBox(height: 20),
                    _section('Tamaño'),
                    const SizedBox(height: 8),
                    _chips(
                      _tamanos,
                      _tamano,
                      (v) => setState(() => _tamano = v),
                      appTeal,
                    ),
                    const SizedBox(height: 20),
                    _section('¿Es amigable con niños?'),
                    const SizedBox(height: 8),
                    _chips(
                      _siNoOpts,
                      _okNinos,
                      (v) => setState(() => _okNinos = v),
                      appTeal,
                    ),
                    const SizedBox(height: 20),
                    _section('¿Es sociable con otros animales?'),
                    const SizedBox(height: 8),
                    _chips(
                      _siNoOpts,
                      _okMascotas,
                      (v) => setState(() => _okMascotas = v),
                      appTeal,
                    ),
                    const SizedBox(height: 20),
                    _section('¿Requiere adoptante con experiencia?'),
                    const SizedBox(height: 8),
                    _chips(
                      _siNoOpts,
                      _requiereExp,
                      (v) => setState(() => _requiereExp = v),
                      appOrange,
                    ),
                    const SizedBox(height: 28),
                    if (!widget.esAlbergue) ...[
                      _section('Ubicación'),
                      const SizedBox(height: 8),
                      _locationField(),
                      const SizedBox(height: 20),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Descripción',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            // Sin el nombre acá adentro a propósito — ya se
                            // muestra arriba, en su propio campo. Antes
                            // esta plantilla lo repetía como texto plano
                            // ("Hermoso fue encontrado/a..."), así que
                            // renombrar el animal después dejaba ese nombre
                            // viejo pegado en medio del párrafo para
                            // siempre — el mismo tipo de copia congelada
                            // que costó un día entero arreglar en otros
                            // lugares de la app. Sin el nombre acá, no hay
                            // nada que pueda quedar desactualizado. Pedido
                            // real de Eliza viendo "Hermoso" en la
                            // descripción de un animal que ya se llamaba
                            // "lino".
                            const plantilla =
                                'Fue encontrado/a [contá cómo o dónde lo/la encontraste]. '
                                'Lo/la que lo/la hace único/a es [una costumbre, gesto o anécdota que lo/la describa]. '
                                'Ya pasó por mucho. Ahora solo le falta alguien que decida quedarse. '
                                '¿Serás vos?';
                            _descCtl.value = TextEditingValue(
                              text: plantilla,
                              selection: TextSelection.collapsed(
                                offset: plantilla.length,
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: appTeal.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: appTeal.withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('✨', style: TextStyle(fontSize: 13)),
                                SizedBox(width: 4),
                                Text(
                                  'Usar plantilla',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: appTeal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _field(
                      '',
                      _descCtl,
                      hint:
                          'Estado del animal, dónde fue encontrado, necesidades especiales...',
                      maxLines: 5,
                      maxLength: 1000,
                    ),
                    const SizedBox(height: 28),
                    _publishBtn(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _appBar(BuildContext ctx) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
    child: Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          tooltip: 'Volver',
          // Apagado mientras se publica: sin esto, se podía salir de la
          // pantalla con el publish todavía corriendo de fondo — si terminaba
          // bien, el animal quedaba publicado sin que la persona lo viera (ni
          // el SnackBar de éxito, que ya no tiene dónde mostrarse), así que
          // podía creer que falló y reintentar, publicando el mismo animal
          // dos veces. Hallazgo de auditoría de código.
          onPressed: _publicando ? null : () => Navigator.pop(ctx),
        ),
        const Expanded(
          child: Text(
            'Subir un rescate',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: appInk,
              fontFamily: 'Baloo2',
            ),
          ),
        ),
      ],
    ),
  );

  Widget _section(String t) => Text(
    t,
    style: const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: Color(0xFF222222),
    ),
  );

  Widget _sectionLabel(String t) => Text(
    t,
    style: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w800,
      color: Color(0xFF7C4DFF),
    ),
  );

  Widget _fotoGrid() {
    final items = List<Widget>.from(_fotos.map((f) => _fotoThumb(f)));
    if (_fotos.length < 2) items.add(_fotoAddBtn());
    return Wrap(spacing: 10, runSpacing: 10, children: items);
  }

  Widget _fotoThumb(XFile f) => Stack(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(f.path),
          width: 90,
          height: 90,
          fit: BoxFit.cover,
        ),
      ),
      Positioned(
        top: 4,
        right: 4,
        child: GestureDetector(
          onTap: () => setState(() => _fotos.remove(f)),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(3),
            child: const Icon(Icons.close, size: 14, color: Colors.white),
          ),
        ),
      ),
    ],
  );

  Widget _fotoAddBtn() => GestureDetector(
    onTap: _mostrarOpcionesFoto,
    child: Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: appTeal.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.add_a_photo_outlined, color: appTeal, size: 28),
          const SizedBox(height: 4),
          Text(
            _fotos.isEmpty ? 'Agregar' : '${_fotos.length}/2',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        ],
      ),
    ),
  );

  // ChipsSeleccionables (widgets/chips_seleccionables.dart) — antes esto tenía su propia copia de
  // la grilla, una de tres iguales repartidas en otras tantas pantallas.
  // Ver el comentario en tipo_animal_screen.dart/_grupo para el hallazgo
  // completo.
  Widget _chips(
    List<String> options,
    String selected,
    ValueChanged<String> onSelect,
    Color activeColor,
  ) => ChipsSeleccionables(
    opciones: options,
    seleccion: selected,
    onSeleccionar: onSelect,
    colorActivo: activeColor,
    colorInactivo: Colors.white.withValues(alpha: 0.85),
    duracion: const Duration(milliseconds: 160),
  );

  // maxLength sin tope antes: un pegado gigante en nombre/descripción se
  // guardaba entero, inflando el tamaño del documento sin ninguna razón
  // real. Hallazgo de auditoría de código.
  // Mismo estilo exacto que editar_rescate_screen.dart (_campo): el campo
  // de nombre se ve distinto al crear y al editar un animal, aunque es la
  // misma pregunta en las dos pantallas (rescatista Y albergue, esta
  // pantalla es compartida por las dos — ver widget.esAlbergue). Pedido
  // real de Eliza: que se vea "exactamente el mismo campo de Nombre" en
  // toda la app. Campo aparte en vez de tocar _field() de acá abajo, que
  // sigue usándose para Raza y otros campos que no pidió cambiar.
  Widget _campoNombre() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Nombre del animal (opcional)',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: appInk,
        ),
      ),
      const SizedBox(height: 6),
      TextField(
        controller: _nombreCtl,
        maxLength: 30,
        decoration: InputDecoration(
          hintText: 'ej. Luna, sin nombre...',
          hintStyle: TextStyle(color: Colors.grey.shade400),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    ],
  );

  Widget _field(
    String label,
    TextEditingController ctl, {
    String hint = '',
    int maxLines = 1,
    int? maxLength,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _section(label),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
            ),
          ],
        ),
        child: TextField(
          controller: ctl,
          maxLines: maxLines,
          maxLength: maxLength,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ),
    ],
  );

  /// La ubicación del animalito: se puede escribir Y detectar por GPS.
  ///
  /// Antes acá había una versión propia que SOLO detectaba: un
  /// `GestureDetector` sobre un texto, sin forma de escribir nada. La idea
  /// era que un rescate se publica desde donde está el animal, así que el
  /// GPS alcanzaba. No alcanza: en Medellín el mapa devuelve el barrio en
  /// vez de la ciudad, y quien publicaba quedaba atrapada con ese nombre
  /// hasta ir a editar. Hallazgo real de Eliza.
  ///
  /// Ahora usa CampoCiudad, el mismo widget que los perfiles y que editar.
  Widget _locationField() => CampoCiudad(
    controller: _lugarCtl,
    hint: 'Ciudad donde está el animalito',
    maxLength: 60,
    controlador: _ciudadCtrl,
    antesDeAbrirAjustes: marcarVolviendoDeAjustes,
    // El GPS trae coordenadas y país junto con el nombre, y los tres tienen
    // que quedar del MISMO lugar: mezclar el nombre de uno con las
    // coordenadas de otro es lo que deja un animalito diciendo una ciudad y
    // apareciendo en otra.
    //
    // Escribir a mano NO pasa por acá, y está bien: ese texto todavía no lo
    // confirmó el mapa. De eso se encarga el guardado, que lo resuelve y
    // recién ahí fija las coordenadas (ver _publicar).
    onDetectado: (r) => setState(() {
      _latitud = r.posicion?.latitude;
      _longitud = r.posicion?.longitude;
      _paisCodigo = r.paisCodigo;
      // Texto y coordenadas quedan sincronizados por definición: salieron
      // del mismo punto. El listener de _lugarCtl prende la marca al
      // escribir el texto, así que hay que apagarla DESPUÉS.
      _ubicacionTocadaAMano = false;
      _lugarSincronizado = _lugarCtl.text;
    }),
  );

  Widget _publishBtn() => SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: _publicando ? null : _publicar,
      style: ElevatedButton.styleFrom(
        backgroundColor: appDark,
        foregroundColor: Colors.white,
        // Mientras publica, el botón queda deshabilitado (onPressed: null)
        // para no permitir un segundo toque — pero sin esto, Material pinta
        // un botón deshabilitado con SUS propios colores grises de tema en
        // vez de los de acá arriba, y el texto blanco de "tardando más de
        // lo normal" quedaba casi ilegible sobre ese gris apagado. Mismos
        // colores que el botón habilitado: sigue pareciendo el mismo botón,
        // solo que ocupado. Hallazgo real de Eliza, en modo avión.
        disabledBackgroundColor: appDark,
        disabledForegroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
      ),
      child: _publicando
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                        value: _progreso > 0 ? _progreso : null,
                      ),
                    ),
                    if (_progreso > 0) ...[
                      const SizedBox(width: 10),
                      Text(
                        '${(_progreso * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ],
                ),
                // Sin señal, la subida no tiene bytes que transferir todavía
                // — _progreso se queda en 0 y el círculo gira sin ningún
                // texto durante hasta 45s (el timeout de la foto). Sin este
                // aviso parecía que la app estaba colgada.
                if (tardandoMucho) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'Esto está tardando más de lo normal. Revisá tu conexión',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ],
            )
          : const Text(
              'Publicar rescate 🐾',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
    ),
  );
}
