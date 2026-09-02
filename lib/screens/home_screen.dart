import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import '../widgets/boton_cambiar_rol.dart';
import '../domain/reglas_negocio.dart';
import '../widgets/avatares.dart';
import '../widgets/cambiar_estado_sheet.dart';
import '../widgets/fondo_decorativo.dart';
import '../widgets/fotos.dart';
import '../widgets/texto_sin_desborde.dart';
import '../services/notificaciones_service.dart';
import '../services/ubicacion_service.dart';
import '../services/ubicacion_lifecycle.dart';
import '../data/chats_repository.dart';
import '../data/creator_role.dart';
import '../data/rescates_repository.dart';
import '../data/solicitudes_repository.dart';
import 'package:go_router/go_router.dart';
import '../routing/app_router.dart';
import 'solicitudes_rescatista_screen.dart'
    show verificarVencimientos, verificarSeguimientoPostAdopcion, contactarPersonaEnProceso;
import 'adoptante_feed_screen.dart';
import 'solicitudes_preview.dart';

// ─── Home Screen ──────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, ReintentoUbicacionAlVolver {
  bool? _isRescatista;
  List<String> _roles = [];
  int _selectedNav = 0;
  String _ciudad = '';
  // Evita que dos detecciones corran encima (el reintento al volver a
  // primer plano puede caer mientras la primera sigue en curso).
  bool _detectandoCiudad = false;
  final _rescatesRepo = RescatesRepository();
  final _solicitudesRepo = SolicitudesRepository();

  // Antes estos 4 streams se armaban de nuevo (nueva instancia de Stream)
  // cada vez que build() corría — lo que pasa con CUALQUIER setState de
  // esta pantalla, no solo al cambiar de pestaña. StreamBuilder
  // resuscribe su listener cada vez que el Stream que recibe cambia de
  // identidad (aunque sea exactamente la misma consulta), así que
  // cualquier setState (ej. tocar el menú de abajo) tiraba abajo y volvía
  // a levantar TODOS estos listeners de golpe — el parpadeo visible de
  // "cargando" que eso genera, para datos que ya estaban cargados y no
  // habían cambiado en absoluto. `late final`: se arman una sola vez, la
  // primera vez que hacen falta — evaluación perezosa, así que el lado
  // (rescatista/adoptante) que no corresponde al rol actual ni se llega
  // a crear. Hallazgo de auditoría de código.
  late final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  late final Stream<QuerySnapshot<Map<String, dynamic>>>
  _solicitudesPendientesStream = _solicitudesRepo.paraOwner(
    uid: _uid,
    role: CreatorRole.rescatista,
    estado: 'pendiente',
  );
  /// El contador de "Animales rescatados". Se pide una vez y se vuelve a
  /// pedir al volver de publicar (ver _refrescarContador), que es cuando de
  /// verdad cambia para quien lo está mirando.
  Future<int> _totalRescates = Future.value(0);

  /// Vuelve a pedir el contador y la vista previa. Se llama al abrir y al
  /// volver de publicar o de la lista completa: son los momentos en que
  /// esto cambia para quien lo está mirando. Antes eran streams en vivo, y
  /// esa comodidad costaba descargar la colección entera.
  void _refrescarRescates() {
    if (!mounted) return;
    setState(() {
      _totalRescates = _rescatesRepo.contar(
        uid: _uid,
        role: CreatorRole.rescatista,
      );
      _activos = _cargarActivos();
    });
  }

  /// El carrusel "Tus rescates activos" es una VISTA PREVIA, no la lista:
  /// para eso está "Ver todas". Trae una página acotada en vez de la
  /// colección entera.
  late Future<PaginaDeRescates> _activos = _cargarActivos();

  /// Los 10 del carrusel, **por prioridad y no por fecha**.
  ///
  /// Mismo problema, y mismo arreglo, que la Jauría del albergue (ver
  /// albergue_home_screen.dart:_cargarJauria): pedir una página de 10 por
  /// `creadoEn` y ordenar después en Dart hacía que un animalito en proceso
  /// de adopción publicado hace meses no entrara nunca en esos 10, aunque
  /// fuera el que hay que mirar.
  ///
  /// Primero los que necesitan atención, y solo se rellena con el resto si
  /// sobra lugar. El relleno va SIN filtro de estado a propósito: así entran
  /// también los animalitos legados que no tienen `estadoAdopcion` guardado,
  /// que un `whereIn` dejaría afuera. Por eso hace falta deduplicar.
  Future<PaginaDeRescates> _cargarActivos() async {
    const cuantos = 10;
    final prioritarios = await _rescatesRepo.paginaDeMisRescates(
      uid: _uid,
      role: CreatorRole.rescatista,
      estados: estadosQueNecesitanAtencion,
      porPagina: cuantos,
    );
    final docs = [...prioritarios.docs];
    if (docs.length < cuantos) {
      final resto = await _rescatesRepo.paginaDeMisRescates(
        uid: _uid,
        role: CreatorRole.rescatista,
        porPagina: cuantos,
      );
      final vistos = docs.map((d) => d.id).toSet();
      for (final d in resto.docs) {
        if (docs.length >= cuantos) break;
        if (vistos.add(d.id)) docs.add(d);
      }
    }
    docs.sort((a, b) {
      final pa = prioridadEstado(a.data()['estadoAdopcion'] as String?);
      final pb = prioridadEstado(b.data()['estadoAdopcion'] as String?);
      if (pa != pb) return pa.compareTo(pb);
      final ta = a.data()['creadoEn'] as Timestamp?;
      final tb = b.data()['creadoEn'] as Timestamp?;
      if (ta == null || tb == null) return 0;
      return tb.compareTo(ta);
    });
    return (docs: docs, hayMas: false, ultimo: docs.isEmpty ? null : docs.last);
  }
  final _chatsRepo = ChatsRepository();
  late final Stream<QuerySnapshot> _chatsRescatistaStream = _chatsRepo.mios(
    uid: _uid,
    esRescatista: true,
  );
  // Consultas que ESTA cuenta le mandó a un negocio aliado (acá `adoptanteId`
  // soy yo, no `rescatistaId` — ver contarMensajesSinLeer en domain/reglas_negocio.dart).
  // Sin esto, el badge de "mensajes sin leer" nunca contaba una respuesta a
  // una consulta propia, aunque sí apareciera en la lista de Chats.
  late final Stream<QuerySnapshot> _consultasEnviadasStream = _chatsRepo
      .consultasEnviadas(uid: _uid);
  late final Stream<QuerySnapshot> _chatsAdoptanteStream = _chatsRepo.mios(
    uid: _uid,
    esRescatista: false,
  );

  static const _rolLabel = {
    'rescatista': 'Rescatista',
    'adoptante': 'Adoptante',
    'institucion': 'Institución',
    'padrino': 'Padrino',
  };

  @override
  void initState() {
    super.initState();
    _cargarRol();
    _refrescarRescates();
    _verificarVencimientos();
    _verificarSeguimientoPostAdopcion();
    _detectarCiudad();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        NotificacionesService.guardarToken();
        NotificacionesService.escucharEnPrimerPlano(context);
      }
    });
  }

  // El reintento al volver de segundo plano (GPS apagado → lo prenden sin
  // cerrar la app → vuelven) vive en ReintentoUbicacionAlVolver — acá solo
  // queda decirle qué mirar. Ver ese archivo para el hallazgo completo
  // (real de Eliza: "en el rescatista no aparece absolutamente nada"
  // después de prender el GPS sin reiniciar la app).
  @override
  bool get yaTieneUbicacion => _ciudad.isNotEmpty;
  @override
  bool get detectandoUbicacion => _detectandoCiudad;
  @override
  void reintentarSinPedirPermiso() => _detectarCiudad(pedirPermiso: false);

  /// Pin de ciudad del saludo ("Hola, Eliza 📍 Córdoba"). Todo el detalle de
  /// servicio/permiso/GPS/geocoding y sus reintentos vive en
  /// UbicacionService — acá solo queda la decisión propia de esta pantalla:
  /// `siAlcanza`, o sea que la última posición conocida es suficiente para
  /// un pin a nivel ciudad y no vale la pena encender el GPS en cada
  /// arranque (es el comportamiento que ya tenía con `pos ??=`).
  ///
  /// Ciudad vacía no es un caso de error acá: el pin simplemente no se
  /// dibuja, sin avisos.
  Future<void> _detectarCiudad({bool pedirPermiso = true}) async {
    _detectandoCiudad = true;
    try {
      final resultado = await UbicacionService.actual(
        conCiudad: true,
        ultimaConocida: UsoUltimaConocida.siAlcanza,
        pedirPermisoSiFalta: pedirPermiso,
      );
      if (!mounted || resultado.ciudad.isEmpty) return;
      setState(() => _ciudad = resultado.ciudad);
    } finally {
      _detectandoCiudad = false;
    }
  }

  Future<void> _cargarRol() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .get();
    if (!mounted) return;
    final roles = List<String>.from((doc.data()?['roles'] as List?) ?? []);
    final ultimoRolActivo = doc.data()?['ultimoRolActivo'] as String?;
    setState(() {
      _roles = roles;
      // No pisa el rol activo si sigue siendo válido — antes esto siempre
      // recalculaba _isRescatista = roles.contains('rescatista') sin
      // importar cuál estaba activo, así que cualquier cuenta con doble
      // rol (adoptante + rescatista) volvía a Rescatista cada vez que
      // _cargarRol() corría — incluido después de entrar a Perfil estando
      // en Adoptante y apretar atrás, porque esa pantalla también dispara
      // el refresco. Hallazgo real de Eliza probando en el teléfono.
      final rolActivoSigueValido = _isRescatista == true
          ? roles.contains('rescatista')
          : _isRescatista == false
          ? roles.contains('adoptante')
          : false;
      if (!rolActivoSigueValido) {
        // _isRescatista == null significa sesión nueva de verdad (recién
        // hecho login, nunca se tocó el toggle todavía en esta corrida) —
        // ahí SÍ vale usar el último rol que la persona eligió a mano,
        // guardado en `ultimoRolActivo` (ver _rolToggle). Antes no había
        // memoria de esto en ningún lado, así que cerrar sesión y volver a
        // entrar con doble rol siempre caía en Rescatista sin importar qué
        // se estuviera usando antes de salir — hallazgo real de Eliza.
        // Si el rol guardado ya no es válido (se lo sacaron a la cuenta),
        // se ignora y se cae al mismo criterio de siempre.
        _isRescatista =
            (_isRescatista == null &&
                ultimoRolActivo == 'adoptante' &&
                roles.contains('adoptante'))
            ? false
            : roles.contains('rescatista');
      }
    });
  }

  // Ambas centralizadas en solicitudes_rescatista_screen.dart — antes
  // duplicadas byte a byte con albergue_home_screen.dart (hallazgo de
  // auditoría de código).
  Future<void> _verificarVencimientos() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (!mounted) return;
    await verificarVencimientos(
      context,
      uid: uid,
      role: CreatorRole.rescatista,
      creadoPor: 'rescatista',
    );
  }

  Future<void> _verificarSeguimientoPostAdopcion() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    await verificarSeguimientoPostAdopcion(
      uid: uid,
      role: CreatorRole.rescatista,
      creadoPor: 'rescatista',
    );
  }

  Widget _rolToggle() {
    final visibles = _roles
        .where((r) => r == 'adoptante' || r == 'rescatista')
        .toList();
    if (visibles.length <= 1) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.80),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: visibles.map((rol) {
          final activo =
              (_isRescatista == true && rol == 'rescatista') ||
              (_isRescatista == false && rol != 'rescatista');
          final label = _rolLabel[rol] ?? rol;
          return GestureDetector(
            onTap: () {
              setState(() {
                _isRescatista = rol == 'rescatista';
                _selectedNav = 0;
              });
              // Best-effort, sin esperar ni avisar si falla — es solo para
              // recordar el rol la PRÓXIMA vez que la persona inicie
              // sesión (ver _cargarRol), no algo que deba trabar el toggle
              // ni mostrar un error si no hay señal en ese instante.
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid != null) {
                FirebaseFirestore.instance
                    .collection('usuarios')
                    .doc(uid)
                    .set({'ultimoRolActivo': rol}, SetOptions(merge: true))
                    .catchError((_) {});
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: activo ? appInk : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: activo ? Colors.white : Colors.grey.shade700,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isRescatista == null) {
      return const Scaffold(
        backgroundColor: appBg,
        body: Center(child: CircularProgressIndicator(color: appTeal)),
      );
    }
    // Único lugar que calcula "mensajes sin leer" del lado rescatista de
    // esta cuenta — el panel (_statsRowDynamic) y el ícono de Chats de
    // abajo (_bottomNav) reciben el mismo número ya calculado en vez de
    // suscribirse cada uno por su cuenta a los mismos streams y llamar a
    // contarMensajesSinLeer por separado. Hallazgo real de Eliza: con dos
    // StreamBuilder independientes escuchando exactamente los mismos
    // datos, uno podía recibir el snapshot nuevo de Firestore un frame
    // antes que el otro (o quedarse esperando si alguno tiene un problema
    // puntual) — el panel decía "2 mensajes sin leer" mientras el ícono de
    // abajo no mostraba ningún número, y entrando a Chats no había nada
    // pendiente. Con un solo cálculo, estructuralmente no pueden mostrar
    // números distintos nunca más, sin importar qué tan compleja se ponga
    // la lógica de conteo más adelante.
    return StreamBuilder<QuerySnapshot>(
      stream: _chatsRescatistaStream,
      builder: (context, chatSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: _consultasEnviadasStream,
          builder: (context, consultaSnap) {
            final noLeidosRescatista = contarMensajesSinLeer(
              recibidos: chatSnap.data?.docs,
              consultasEnviadas: consultaSnap.data?.docs,
              esAlbergue: false,
              uid: _uid,
            );
            return Scaffold(
              body: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: appBg),
                  const LeafOverlay(),
                  SafeArea(
                    // IndexedStack en vez de un condicional: las dos vistas quedan
                    // montadas siempre, así el toggle Adoptante/Rescatista no
                    // destruye el State del feed al cambiar de lado. Antes cada
                    // cambio de rol recreaba AdoptanteFeedScreen desde cero —
                    // sus StreamBuilder (línea ~447) arrancaban en
                    // ConnectionState.waiting otra vez y mostraban el spinner un
                    // instante antes de que Firestore volviera a entregar los
                    // datos, aunque fueran los mismos de hacía un segundo. Hallazgo
                    // real: "entro a ver los adoptantes y parpadea antes de cargar
                    // los animalitos" al volver de Negocios y tocar el toggle.
                    child: IndexedStack(
                      index: _isRescatista! ? 0 : 1,
                      children: [
                        _rescatistaView(context, noLeidosRescatista),
                        _adoptanteView(context),
                      ],
                    ),
                  ),
                ],
              ),
              floatingActionButton: botonCambiarRol(
                context,
                alVolver: () {
                  if (mounted) _cargarRol();
                },
              ),
              bottomNavigationBar: _bottomNav(noLeidosRescatista),
            );
          },
        );
      },
    );
  }

  // ── Vista Rescatista ──────────────────────────────────────────────────────

  Widget _rescatistaView(BuildContext ctx, int noLeidosRescatista) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [_rolToggle(), _avatar('A', appOrange)],
          ),
          const SizedBox(height: 24),
          // Mismo estándar que el saludo de la vista adoptante (una sola línea
          // en negrita) — antes era "Hola," gris arriba y el nombre grande
          // debajo, un estilo distinto al del resto de la app.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Hola, ${FirebaseAuth.instance.currentUser?.displayName?.split(' ').first ?? 'Rescatista'} ',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: appInk,
                  fontFamily: 'Baloo2',
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text('🐾', style: TextStyle(fontSize: 26)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // El ícono solo tiene sentido junto a un texto — antes se mostraba
          // solo (sin ciudad al lado) cuando el GPS estaba bloqueado o sin
          // detectar, quedando un pin "flotando" sin explicación.
          if (_ciudad.isNotEmpty)
            // TextoSinDesborde (widgets/texto_sin_desborde.dart): una ciudad larga que viene del
            // geocoder empujaba el resto de la fila fuera de la pantalla.
            TextoSinDesborde(
              texto: _ciudad,
              separacion: 2,
              antes: const Icon(Icons.location_on, size: 14, color: appTeal),
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          const SizedBox(height: 20),
          _label('ESTA SEMANA'),
          const SizedBox(height: 10),
          _statsRowDynamic(noLeidosRescatista),
          const SizedBox(height: 16),
          _ctaCard(ctx),
          const SizedBox(height: 28),
          _sectionHeader(
            'ESPERAN RESPUESTA',
            'Solicitudes',
            'Ver todas',
            // Refrescar AL VOLVER, igual que el push a misRescates de más
            // arriba. Desde Solicitudes se APRUEBA, y aprobar cambia el
            // estado del animalito (a 'Hogar de paso' o 'En proceso de
            // adopción'). Sin esto, el panel volvía con el estado anterior:
            // Eliza aprobó un hogar de paso y su carrusel lo seguía
            // mostrando como Rescatado. El feed del adoptante sí lo veía,
            // porque es un stream en vivo; este carrusel es un .get() que
            // se pidió una sola vez, al abrir.
            onAction: () => context
                .push(AppRoutes.solicitudesRescatista)
                .then((_) => _refrescarRescates()),
          ),
          const SizedBox(height: 12),
          const SolicitudesPreview(role: CreatorRole.rescatista),
          const SizedBox(height: 28),
          _sectionHeader(
            'MIS ANIMALES',
            'Tus rescates activos',
            'Gestionar',
            onAction: () => context
                .push(AppRoutes.misRescates)
                .then((_) => _refrescarRescates()),
          ),
          const SizedBox(height: 12),
          _misRescatesCarousel(),
          const SizedBox(height: 90),
        ],
      ),
    );
  }

  Widget _sectionHeader(
    String label,
    String title,
    String action, {
    VoidCallback? onAction,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _label(label),
          GestureDetector(
            onTap: onAction,
            child: const Text(
              'Ver todas',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: appTeal,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        title,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: appInk,
        ),
      ),
    ],
  );

  Widget _misRescatesCarousel() {
    return SizedBox(
      height: 245,
      // Una PÁGINA, no la colección. Este carrusel es una vista previa —
      // la lista completa está en "Ver todas" (mis_rescates_screen), que
      // pagina sola. Antes escuchaba la consulta entera: con 1.000 animales
      // descargaba 1.000 documentos para mostrar los primeros que entran en
      // una fila horizontal.
      //
      // El orden por prioridad de estado se sigue haciendo acá abajo, pero
      // ahora sobre 10 elementos en vez de sobre todo. Eso cambia algo y
      // conviene saberlo: la vista previa muestra los 10 MÁS RECIENTES
      // ordenados por prioridad, no los 10 de mayor prioridad de toda la
      // cuenta. Para eso está la lista completa, que sí puede filtrar.
      child: FutureBuilder<PaginaDeRescates>(
        future: _activos,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: appTeal),
            );
          }
          if (snap.hasError) {
            return Center(
              child: Text(
                'Error: ${snap.error}',
                style: const TextStyle(fontSize: 12),
              ),
            );
          }
          final docs = [...?snap.data?.docs];

          if (docs.isEmpty) {
            return Center(
              child: Text(
                'Aún no tienes rescates publicados.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
            );
          }
          // En proceso de adopción y hogar de paso primero (necesitan
          // atención activa), lo cerrado (adoptado/fallecido) al final —
          // ver prioridadEstado() en domain/reglas_negocio.dart. Empate por fecha de
          // publicación, más nuevo primero, para que el orden no salte
          // solo porque Firestore devolvió los docs en otro orden.
          docs.sort((a, b) {
            final pa = prioridadEstado(a.data()['estadoAdopcion'] as String?);
            final pb = prioridadEstado(b.data()['estadoAdopcion'] as String?);
            if (pa != pb) return pa.compareTo(pb);
            final ta = a.data()['creadoEn'] as Timestamp?;
            final tb = b.data()['creadoEn'] as Timestamp?;
            if (ta == null && tb == null) return 0;
            if (ta == null) return 1;
            if (tb == null) return -1;
            return tb.compareTo(ta);
          });
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final data = docs[i].data();
              final nombre = nombreDeAnimal(data['nombre'] as String?);
              final especie = data['especie'] ?? '';
              final estadoAdopcion = data['estadoAdopcion'] ?? 'Rescatado';
              final fotoUrl = data['fotoUrl'] as String?;
              final docId = docs[i].id;
              return _animalCard(
                nombre,
                especie,
                // Sin esto, aprobar/rechazar una solicitud (o cualquier
                // otro cambio que mueva a este animal de posición en la
                // lista, ya ordenada por prioridadEstado) hacía que
                // Flutter reutilizara por POSICIÓN el elemento visual de
                // otro animal para este lugar — la foto vieja se veía un
                // instante antes de que la nueva terminara de cargar, un
                // parpadeo. Con la key por docId, Flutter sabe que es un
                // animal distinto y arma la tarjeta de cero en vez de
                // reciclar la de al lado. Hallazgo real de Eliza.
                key: ValueKey(docId),
                estado: estadoAdopcion,
                emoji: especie == 'Gato' ? '🐱' : '🐶',
                fotoUrl: fotoUrl,
                onCambiarEstado: estadoAdopcion == 'Fallecido'
                    ? null
                    : () => showModalBottomSheet(
                        context: context,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
                        ),
                        builder: (_) => CambiarEstadoSheet(
                          docId: docId,
                          estadoActual: estadoAdopcion,
                          nombre: nombre,
                          adoptanteIdEnProceso:
                              data['adoptanteIdEnProceso'] as String?,
                          // home_screen es el panel del RESCATISTA: no
                          // tiene red de hogares de paso (es solo para
                          // albergues, decisión de producto).
                          esAlbergue: false,
                        ),
                      ),
                // 'Hogar de paso' antes se quedaba afuera de esta condición
                // sin querer: el rescatista aprobaba un hogar de paso y no
                // tenía forma de contactar a esa persona (el bug real que
                // reportó Eliza).
                onContactarAdoptante:
                    (estadoAdopcion == 'En proceso de adopción' ||
                        estadoAdopcion == 'Hogar de paso')
                    ? () => contactarPersonaEnProceso(
                        context,
                        docId: docId,
                        nombre: nombre,
                        especie: especie,
                        fotoUrl: fotoUrl,
                        creadoPor: data['creadoPor'] as String?,
                        adoptanteIdEnProceso:
                            data['adoptanteIdEnProceso'] as String? ?? '',
                      )
                    : null,
              );
            },
          );
        },
      ),
    );
  }

  Widget _animalCard(
    String nombre,
    String especie, {
    Key? key,
    String emoji = '🐾',
    String estado = 'En adopción',
    String? fotoUrl,
    VoidCallback? onCambiarEstado,
    VoidCallback? onContactarAdoptante,
  }) {
    final color = cicloColor(estado);
    return Container(
      key: key,
      width: 150,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            // FotoAnimal en vez de recorte — esta tarjeta (el resumen de "tus
            // animales" en el panel del rescatista) es lo bastante grande
            // como para sufrir el mismo caso "Tobyiii" que el feed del
            // adoptante ya tenía arreglado; el rescatista se había quedado
            // viendo sus propios animalitos peor que como los ve quien
            // adopta.
            child: fotoUrl != null
                ? FotoAnimal(
                    url: fotoUrl,
                    height: 100,
                    width: double.infinity,
                    fallback: Container(
                      height: 100,
                      width: double.infinity,
                      color: const Color(0xFFD8F0E4),
                      child: Center(
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 40),
                        ),
                      ),
                    ),
                  )
                : Container(
                    height: 100,
                    width: double.infinity,
                    color: const Color(0xFFD8F0E4),
                    child: Center(
                      child: Text(emoji, style: const TextStyle(fontSize: 40)),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  especie,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: onCambiarEstado,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: color.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            estado,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (onCambiarEstado != null) ...[
                          const SizedBox(width: 2),
                          Icon(Icons.expand_more, size: 12, color: color),
                        ],
                      ],
                    ),
                  ),
                ),
                if (onContactarAdoptante != null) ...[
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: onContactarAdoptante,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: appOrange,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Contactar 💬',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Vista Adoptante ───────────────────────────────────────────────────────

  Widget _adoptanteView(BuildContext ctx) {
    // Mismo saludo que la vista del rescatista ("Hola, Eliza 🐾"), pero más
    // compacto — acá abajo sigue el feed, que YA trae su propio encabezado
    // (chips de especie + ubicación + la tarjeta del animal), así que el
    // saludo no puede ocupar tanto como en el panel del rescatista (ahí no
    // hay nada debajo compitiendo por el espacio). Antes esto + el título
    // repetido del feed obligaba a hacer mucho scroll para llegar a la
    // tarjeta.
    //
    // El subtítulo "Encuentra a tu amigo fiel ideal" que iba acá se sacó
    // para hacerle lugar a los chips de especie del feed (Todos/Perros/
    // Gatos/Otros) sin agregar altura nueva — era puramente decorativo, no
    // informaba nada que los chips no cubran mejor (sugerencia real de
    // Eliza: la fila de chips por sí sola ya dejaba la pantalla muy llena).
    final nombre =
        FirebaseAuth.instance.currentUser?.displayName?.split(' ').first ??
        'Adoptante';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [_rolToggle(), _avatar('A', appOrange)],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Hola, $nombre ',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: appInk,
                      fontFamily: 'Baloo2',
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 2),
                    child: Text('🐾', style: TextStyle(fontSize: 20)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Expanded(child: AdoptanteFeedScreen()),
      ],
    );
  }

  Widget _label(String t) => Text(
    t,
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.2,
      color: Colors.grey.shade700,
    ),
  );

  Widget _statsRowDynamic(int noLeidosRescatista) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      key: const ValueKey('stats-solicitudes-pendientes'),
      stream: _solicitudesPendientesStream,
      builder: (context, snap) {
        final count = snap.data?.docs.length ?? 0;
        return Row(
          children: [
            Expanded(
              child: GestureDetector(
                // Mismo motivo que la cabecera de SOLICITUDES.
                onTap: () => context
                    .push(AppRoutes.solicitudesRescatista)
                    .then((_) => _refrescarRescates()),
                child: _stat(
                  '$count',
                  'Nuevas\nsolicitudes',
                  const Color(0xFFF9DDD5),
                  const Color(0xFFCC4422),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () => context.push(
                  AppRoutes.adoptanteChats,
                  extra: (
                    esRescatista: true,
                    soloConsultas: false,
                    esAlbergue: false,
                  ),
                ),
                child: _stat(
                  '$noLeidosRescatista',
                  'Mensajes\nsin leer',
                  const Color(0xFFD8EEFA),
                  const Color(0xFF2070B0),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              // contar() y no el stream completo: antes este número salía
              // de `docs.length` sobre TODOS los rescates de la cuenta, o
              // sea que abrir el inicio los descargaba enteros para pintar
              // un número. Con 1.000 son 1.000 lecturas; con 100.000, cien
              // veces más. Ver RescatesRepository.contar().
              child: FutureBuilder<int>(
                future: _totalRescates,
                builder: (context, rescSnap) => _stat(
                  '${rescSnap.data ?? 0}',
                  'Animales\nrescatados',
                  Colors.white,
                  appInk,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _stat(String n, String lbl, Color bg, Color nc) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          n,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: nc,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          lbl,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade700,
            height: 1.3,
          ),
        ),
      ],
    ),
  );

  Widget _ctaCard(BuildContext ctx) => GestureDetector(
    onTap: () => ctx
        .push(AppRoutes.subirRescate, extra: false)
        .then((_) => _refrescarRescates()),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A5C40), appTeal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: appOrange,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.add, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Subir un rescate',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Publica un animal en minutos',
                  style: TextStyle(color: Color(0xFFB8E0CC), fontSize: 13),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Color(0xFFB8E0CC), size: 22),
        ],
      ),
    ),
  );

  Widget _bottomNav(int noLeidosRescatista) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 12,
          offset: const Offset(0, -2),
        ),
      ],
    ),
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            if (_isRescatista == true) ...[
              _navItem(Icons.pets, 'Mis rescates', 0),
              _navTap(
                Icons.add_circle_outline,
                'Subir',
                1,
                onTap: () => context
                    .push(AppRoutes.subirRescate, extra: false)
                    .then((_) => _refrescarRescates()),
              ),
              _navTap(
                Icons.notifications_outlined,
                'Solicitudes',
                2,
                // Mismo motivo que la cabecera de SOLICITUDES.
                onTap: () => context
                    .push(AppRoutes.solicitudesRescatista)
                    .then((_) => _refrescarRescates()),
              ),
              // Antes este badge era su propio StreamBuilder anidado,
              // suscrito de nuevo a los mismos _chatsRescatistaStream /
              // _consultasEnviadasStream que ya escuchaba build() más
              // arriba para el panel — dos cálculos independientes de
              // "mensajes sin leer" en la misma pantalla, con su propio
              // riesgo de desincronizarse (frame de diferencia, filtro que
              // cambia en uno y no en el otro). Ahora recibe el número ya
              // calculado UNA sola vez en build() como parámetro — sin un
              // segundo StreamBuilder acá, no hay dos cálculos que puedan
              // divergir nunca más, ni un AsyncSnapshot propio que pueda
              // quedarse con datos viejos al cambiar de rol (el bug real
              // que tenían las ValueKey que este comentario reemplaza:
              // "cambio rápido de rol y veo un número, pero no tengo
              // ningún chat").
              _navTapConBadge(
                Icons.chat_bubble_outline,
                'Chats',
                noLeidosRescatista,
                () => context.push(
                  AppRoutes.adoptanteChats,
                  extra: (
                    esRescatista: true,
                    soloConsultas: false,
                    esAlbergue: false,
                  ),
                ),
              ),
              _navTap(
                Icons.store_outlined,
                'Negocios',
                5,
                onTap: () => context.push(
                  AppRoutes.aliados,
                  extra: (esRescatista: true, esAlbergue: false),
                ),
              ),
              // .then(_cargarRol): "Gestionar mis roles" vive en esta pantalla
              // de Perfil — sin este refresco, agregar un rol ahí guardaba
              // bien en el servidor (el aviso verde de éxito no mentía) pero
              // esta pantalla seguía usando los `_roles`/`_isRescatista` que
              // había cacheado al abrirse, así que el toggle nuevo no
              // aparecía hasta cerrar y volver a abrir la app. Hallazgo de
              // prueba en teléfono real, 2026-08-03.
              _navTap(
                Icons.person_outline,
                'Perfil',
                4,
                onTap: () => context
                    .push(AppRoutes.perfilRescatista)
                    .then((_) => _cargarRol()),
              ),
            ] else ...[
              _navItem(Icons.pets, 'Adoptar', 0),
              _navTap(
                Icons.favorite_outline,
                'Favoritos',
                1,
                onTap: () => context.push(AppRoutes.favoritos),
              ),
              _navTap(
                Icons.assignment_outlined,
                'Solicitudes',
                2,
                onTap: () => context.push(AppRoutes.misSolicitudes),
              ),
              // Mismo orden que en Rescatista/Albergue/Aliado: Chats siempre va
              // después de Solicitudes, antes de Negocios/Perfil.
              // Key propia — ver el comentario del badge de rescatista.
              StreamBuilder<QuerySnapshot>(
                key: const ValueKey('badge-chats-adoptante'),
                stream: _chatsAdoptanteStream,
                builder: (_, snap) {
                  // ChatsRepository.perteneceALaLista es la misma función
                  // que decide qué chats muestra AdoptanteChatsScreen (sin
                  // esRescatista) — antes este badge tenía su propia copia
                  // a mano de esa regla de membresía (bug real, mismo
                  // patrón que el badge de rescatista más abajo: excluía
                  // TODA consulta a un negocio del conteo, sin importar con
                  // qué sombrero se mandó, así que el ícono podía no
                  // mostrar nada mientras la lista sí tenía una
                  // conversación sin leer). Con la misma función acá, la
                  // lista y el badge no pueden volver a divergir en esto.
                  final unread = (snap.data?.docs ?? []).where((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    return ChatsRepository.perteneceALaLista(
                          d,
                          uid: _uid,
                          esRescatista: false,
                        ) &&
                        ChatsRepository.noLeidosPara(
                              d,
                              uid: _uid,
                              esRescatista: false,
                            ) >
                            0;
                  }).length;
                  return _navTapConBadge(
                    Icons.chat_bubble_outline,
                    'Chats',
                    unread,
                    () => context.push(AppRoutes.adoptanteChats),
                  );
                },
              ),
              _navTap(
                Icons.store_outlined,
                'Negocios',
                3,
                onTap: () => context.push(
                  AppRoutes.aliados,
                  extra: (esRescatista: false, esAlbergue: false),
                ),
              ),
              // .then(_cargarRol): mismo motivo que la rama de rescatista, más
              // arriba en este mismo archivo.
              _navTap(
                Icons.person_outline,
                'Perfil',
                4,
                onTap: () => context
                    .push(AppRoutes.perfilAdoptante, extra: _ciudad)
                    .then((_) => _cargarRol()),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _navItem(IconData icon, String label, int idx) {
    final active = _selectedNav == idx;
    final color = active ? appTeal : Colors.grey.shade400;
    return GestureDetector(
      onTap: () => setState(() => _selectedNav = idx),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(fontSize: 10, color: color)),
        ],
      ),
    );
  }

  Widget _navTap(
    IconData icon,
    String label,
    int idx, {
    required VoidCallback onTap,
  }) {
    final color = Colors.grey.shade400;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(fontSize: 10, color: color)),
        ],
      ),
    );
  }

  Widget _navTapConBadge(
    IconData icon,
    String label,
    int badge,
    VoidCallback onTap,
  ) {
    final color = Colors.grey.shade400;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, color: color, size: 24),
              if (badge > 0)
                Positioned(
                  top: -4,
                  right: -6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    decoration: const BoxDecoration(
                      color: appOrange,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      badge > 9 ? '9+' : '$badge',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(fontSize: 10, color: color)),
        ],
      ),
    );
  }
}

// ─── Avatar helper (global dentro del archivo) ───────────────────────────────

// AvatarPersona (widgets/avatares.dart), no un CircleAvatar armado a mano — antes,
// si la foto de perfil de Google fallaba al cargar (sin señal, link
// vencido), se veía un círculo de color vacío en vez de caer a la
// inicial, justo en el avatar del encabezado del dashboard principal.
// Hallazgo de auditoría de código.
Widget _avatar(String letter, Color color, {double radius = 22}) {
  final user = FirebaseAuth.instance.currentUser;
  final inicial = user?.displayName?.isNotEmpty == true
      ? user!.displayName![0].toUpperCase()
      : letter;
  return AvatarPersona(
    fotoUrl: user?.photoURL,
    inicial: inicial,
    radius: radius,
    backgroundColor: color,
    textColor: Colors.white,
  );
}
