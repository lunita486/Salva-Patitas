import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/adoptante_tab_bar.dart';
import '../widgets/rescatista_tab_bar.dart';
import '../widgets/sp_widgets.dart';
import '../theme/salva_patitas_theme.dart';
import '../widgets/boton_cambiar_rol.dart';
import '../domain/reglas_negocio.dart';
import '../widgets/avatares.dart';
import '../widgets/cambiar_estado_sheet.dart';
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
    show
        verificarVencimientos,
        verificarSeguimientoPostAdopcion,
        contactarPersonaEnProceso;
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
  /// sobra lugar. El relleno va SIN filtro de estado en la CONSULTA a
  /// propósito: así entran también los animalitos legados que no tienen
  /// `estadoAdopcion` guardado, que un `whereIn` dejaría afuera. Por eso
  /// hace falta deduplicar.
  ///
  /// Lo único que se descarta es 'Fallecido', y se hace en Dart por ese
  /// mismo motivo. Es "Tus rescates activos": un animalito que ya no está
  /// no es algo que quede por hacer, y encima ocupaba uno de los 10 lugares
  /// (el límite se aplica en la consulta). Mismo criterio que la Jauría del
  /// albergue, ver albergue_home_screen.dart:_cargarJauria. Se lo sigue
  /// alcanzando desde "Gestionar" filtrando por estado.
  ///
  /// 'Adoptado' NO se toca: sigue entrando igual que hasta ahora, al final
  /// del orden.
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
        if (d.data()['estadoAdopcion'] == 'Fallecido') continue;
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
    final c = context.sp;
    // Selector hundido (`.segmented--mode`): la opción activa en tinta con
    // letra clara, como en el prototipo.
    return Container(
      decoration: SpDeco.sunken(c, radius: SpRadius.full),
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
              setState(() => _isRescatista = rol == 'rescatista');
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: activo ? c.ink : null,
                borderRadius: BorderRadius.circular(SpRadius.full),
                boxShadow: activo
                    ? [
                        BoxShadow(
                          color: c.ink.withValues(alpha: .25),
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: activo ? c.bg : c.inkMuted,
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
      return Scaffold(
        backgroundColor: context.sp.bg,
        body: Center(
          child: CircularProgressIndicator(color: context.sp.primary),
        ),
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
                  Container(color: context.sp.bg),
                  const SpPawBackground(),
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
            children: [_rolToggle(), _avatar('A')],
          ),
          const SizedBox(height: 24),
          // Mismo estándar que el saludo de la vista adoptante (una sola línea
          // en negrita) — antes era "Hola," gris arriba y el nombre grande
          // debajo, un estilo distinto al del resto de la app.
          Row(
            children: [
              Flexible(
                child: Text(
                  'Hola, ${FirebaseAuth.instance.currentUser?.displayName?.split(' ').first ?? 'Rescatista'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SpText.screen.copyWith(color: ctx.sp.ink),
                ),
              ),
              const SizedBox(width: 8),
              const SpPaw(size: 22, angle: -12),
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
              antes: Icon(
                Icons.location_on_rounded,
                size: 15,
                color: ctx.sp.primaryStrong,
              ),
              style: SpText.label.copyWith(color: ctx.sp.inkMuted),
            ),
          const SizedBox(height: SpSpace.s6),
          _statsRowDynamic(noLeidosRescatista),
          const SizedBox(height: SpSpace.s4),
          _ctaCard(ctx),
          const SizedBox(height: SpSpace.s6),
          _sectionHeader(
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
            onAction: () => _irARescatista(RescatistaTab.solicitudes),
          ),
          const SizedBox(height: SpSpace.s3),
          const SolicitudesPreview(role: CreatorRole.rescatista),
          const SizedBox(height: SpSpace.s6),
          _sectionHeader(
            'Mis animales',
            'Gestionar',
            onAction: () => context
                .push(AppRoutes.misRescates)
                .then((_) => _refrescarRescates()),
          ),
          const SizedBox(height: SpSpace.s3),
          _misRescatesCarousel(),
          const SizedBox(height: 90),
        ],
      ),
    );
  }

  Widget _sectionHeader(
    String title,
    String action, {
    VoidCallback? onAction,
  }) => SpSectionTitle(
    title,
    trailing: onAction == null ? null : SpLink(action, onTap: onAction),
  );

  Widget _misRescatesCarousel() {
    return SizedBox(
      height: 250,
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
            return Center(
              child: CircularProgressIndicator(color: context.sp.primary),
            );
          }
          if (snap.hasError) {
            return Center(
              child: Text(
                'Error: ${snap.error}',
                style: SpText.caption.copyWith(color: context.sp.danger),
              ),
            );
          }
          final docs = [...?snap.data?.docs];

          if (docs.isEmpty) {
            return Align(
              alignment: Alignment.topCenter,
              child: SpEmpty(
                title: 'Aún no tienes rescates publicados',
                animal: SpAnimalKind.perro,
                action: SpButton(
                  label: 'Publicar el primero',
                  icon: Icons.add_rounded,
                  compacto: true,
                  onTap: () => context
                      .push(AppRoutes.subirRescate, extra: false)
                      .then((_) => _refrescarRescates()),
                ),
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
            clipBehavior: Clip.none,
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(width: SpSpace.s3),
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
                fotoUrl: fotoUrl,
                // El `.then` de abajo no es opcional: este carrusel es un
                // .get() pedido una sola vez al abrir la pantalla, no un
                // stream. La escritura sale bien (cambiarEstadoAdopcion es
                // un solo update, y nada del servidor toca estadoAdopcion
                // después), pero sin volver a preguntar, la tarjeta se
                // queda mostrando el estado con el que se cargó la
                // pantalla. Hallazgo real de Eliza: puso un animalito en
                // hogar de paso y lo siguió viendo como Rescatado hasta que
                // otra navegación provocó un refresco. Mismo patrón que los
                // dos sheets del panel del albergue.
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
                      ).then((_) => _refrescarRescates()),
                // 'Hogar de paso' antes se quedaba afuera de esta condición
                // sin querer: el rescatista aprobaba un hogar de paso y no
                // tenía forma de contactar a esa persona (el bug real que
                // reportó Eliza).
                //
                // Y hace falta que HAYA a quién contactar: `adoptanteIdEnProceso`
                // solo existe cuando se aprobó una solicitud, así que un hogar
                // de paso cargado A MANO no lo tiene (esa persona ni siquiera
                // usa la app). Sin este chequeo el botón aparecía igual, y
                // contactarPersonaEnProceso llegaba a buscarDeAnimal sin
                // identificadores: caía en su búsqueda legada POR NOMBRE, que
                // con dos animalitos del mismo dueño llamados igual devuelve
                // uno cualquiera. Bug real de Eliza en el APK108: abrió el
                // chat de otro animalito, uno ya fallecido. Las otras dos
                // pantallas que muestran este botón (el panel del albergue y
                // "Gestionar") ya pedían esto; faltaba solo acá.
                onContactarAdoptante:
                    (estadoAdopcion == 'En proceso de adopción' ||
                            estadoAdopcion == 'Hogar de paso') &&
                        (data['adoptanteIdEnProceso'] as String? ?? '')
                            .isNotEmpty
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

  /// Tarjeta de un animalito del carrusel, igual a la del panel del
  /// albergue (`.sp-pet2`).
  Widget _animalCard(
    String nombre,
    String especie, {
    Key? key,
    String estado = 'En adopción',
    String? fotoUrl,
    VoidCallback? onCambiarEstado,
    VoidCallback? onContactarAdoptante,
  }) {
    final c = context.sp;
    return Container(
      key: key,
      width: 152,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(SpSpace.s2),
      decoration: SpDeco.card(c, radius: SpRadius.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              // FotoAnimal en vez de recorte — esta tarjeta (el resumen de "tus
              // animales" en el panel del rescatista) es lo bastante grande
              // como para sufrir el mismo caso "Tobyiii" que el feed del
              // adoptante ya tenía arreglado; el rescatista se había quedado
              // viendo sus propios animalitos peor que como los ve quien
              // adopta.
              child: fotoUrl != null
                  ? FotoAnimal(
                      url: fotoUrl,
                      width: double.infinity,
                      fallback: SpFotoVacia(especie: especie),
                    )
                  : SpFotoVacia(especie: especie),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
            child: Text(
              nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: c.ink,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              especie,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SpText.caption.copyWith(color: c.inkMuted),
            ),
          ),
          const SizedBox(height: SpSpace.s2),
          SpStatus(estado, height: 30, onTap: onCambiarEstado),
          if (onContactarAdoptante != null) ...[
            const SizedBox(height: 6),
            Semantics(
              button: true,
              label: 'Contactar a quien está en proceso con $nombre',
              child: GestureDetector(
                onTap: onContactarAdoptante,
                child: Container(
                  width: double.infinity,
                  height: 30,
                  decoration: SpDeco.primary(c, radius: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 13,
                        color: c.onPrimary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Contactar',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: c.onPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
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
                children: [_rolToggle(), _avatar('A')],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      'Hola, $nombre',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SpText.screen.copyWith(color: ctx.sp.ink),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const SpPaw(size: 22, angle: -12),
                ],
              ),
            ],
          ),
        ),
        const Expanded(child: AdoptanteFeedScreen()),
      ],
    );
  }

  Widget _statsRowDynamic(int noLeidosRescatista) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      key: const ValueKey('stats-solicitudes-pendientes'),
      stream: _solicitudesPendientesStream,
      builder: (context, snap) {
        final count = snap.data?.docs.length ?? 0;
        return Row(
          children: [
            Expanded(
              child: SpMiniStat(
                tone: SpTone.lilac,
                animal: SpAnimalKind.gato,
                value: '$count',
                label: 'Solicitudes',
                // Mismo motivo que la cabecera de SOLICITUDES.
                onTap: () => _irARescatista(RescatistaTab.solicitudes),
              ),
            ),
            const SizedBox(width: SpSpace.s3),
            Expanded(
              child: SpMiniStat(
                tone: SpTone.sky,
                animal: SpAnimalKind.conejo,
                value: '$noLeidosRescatista',
                label: 'Sin leer',
                onTap: () => _irARescatista(RescatistaTab.chats),
              ),
            ),
            const SizedBox(width: SpSpace.s3),
            Expanded(
              // contar() y no el stream completo: antes este número salía
              // de `docs.length` sobre TODOS los rescates de la cuenta, o
              // sea que abrir el inicio los descargaba enteros para pintar
              // un número. Con 1.000 son 1.000 lecturas; con 100.000, cien
              // veces más. Ver RescatesRepository.contar().
              child: FutureBuilder<int>(
                future: _totalRescates,
                builder: (context, rescSnap) => SpMiniStat(
                  tone: SpTone.mint,
                  animal: SpAnimalKind.huella,
                  value: '${rescSnap.data ?? 0}',
                  label: 'Rescatados',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// "Subir un rescate": tarjeta blanca con el "+" verde 3D girado, como
  /// "Subir uno" en el panel del albergue.
  Widget _ctaCard(BuildContext ctx) {
    final c = ctx.sp;
    return SpCard(
      padding: const EdgeInsets.all(SpSpace.s3),
      onTap: () => ctx
          .push(AppRoutes.subirRescate, extra: false)
          .then((_) => _refrescarRescates()),
      child: Row(
        children: [
          Transform.rotate(
            angle: -0.14,
            child: Container(
              width: 56,
              height: 56,
              decoration: SpDeco.primary(c, radius: 18, gradient: true),
              child: Icon(Icons.add_rounded, size: 32, color: c.onPrimary),
            ),
          ),
          const SizedBox(width: SpSpace.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Subir un rescate',
                  style: SpText.headline.copyWith(
                    color: c.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Publica un animal en minutos',
                  style: SpText.caption.copyWith(color: c.inkMuted),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: c.inkFaint),
        ],
      ),
    );
  }

  // Barra flotante 3D (SpTabBar), como la del albergue. Cada ítem conserva
  // su misma acción de siempre.
  Widget _bottomNav(int noLeidosRescatista) => _isRescatista == true
      ? _bottomNavRescatista(noLeidosRescatista)
      // La del adoptante es la misma barra que sale en cada sección que se
      // abre desde acá (ver AdoptanteTabBar).
      : AdoptanteTabBar(actual: AdoptanteTab.adoptar, onTap: _irAAdoptante);

  // La del rescatista también es la misma barra en cada sección que se abre
  // desde acá (ver RescatistaTabBar), salvo en el formulario de Subir.
  Widget _bottomNavRescatista(int noLeidosRescatista) => RescatistaTabBar(
    actual: RescatistaTab.misRescates,
    onTap: _irARescatista,
  );

  /// Abre la pestaña elegida en la barra del rescatista (en el inicio o en
  /// cualquier sección: ver RescatistaTabBar.volverAlInicio).
  void _irARescatista(RescatistaTab t) {
    switch (t) {
      // Ya está en el inicio: no hay nada que abrir.
      case RescatistaTab.misRescates:
        break;
      case RescatistaTab.subir:
        context
            .push(AppRoutes.subirRescate, extra: false)
            .then((_) => _refrescarRescates());
      // Refrescar AL VOLVER: desde Solicitudes se APRUEBA, y aprobar cambia
      // el estado del animalito. Este carrusel es un .get() pedido una sola
      // vez; sin esto seguía mostrando el estado viejo (hallazgo de Eliza).
      case RescatistaTab.solicitudes:
        context.push(AppRoutes.solicitudesRescatista).then(_alVolverRescatista);
      case RescatistaTab.chats:
        context
            .push(
              AppRoutes.adoptanteChats,
              extra: (
                esRescatista: true,
                soloConsultas: false,
                esAlbergue: false,
              ),
            )
            .then(_siOtraPestanaRescatista);
      case RescatistaTab.negocios:
        context
            .push(
              AppRoutes.aliados,
              extra: (esRescatista: true, esAlbergue: false),
            )
            .then(_siOtraPestanaRescatista);
      // .then(_cargarRol): "Gestionar mis roles" vive en Perfil — sin este
      // refresco, un rol nuevo no aparecía hasta reabrir la app (hallazgo
      // de prueba en teléfono real, 2026-08-03).
      case RescatistaTab.perfil:
        context.push(AppRoutes.perfilRescatista).then((r) {
          _cargarRol();
          _siOtraPestanaRescatista(r);
        });
    }
  }

  /// Al volver de Solicitudes: refresca el carrusel (es un .get() pedido una
  /// sola vez, y desde ahí se aprueba) y, si se tocó otra pestaña en la
  /// barra, la abre. Mismo patrón que `_alVolver` del panel del albergue.
  void _alVolverRescatista(Object? resultado) {
    _refrescarRescates();
    _siOtraPestanaRescatista(resultado);
  }

  /// Si en la barra de la sección se tocó otra pestaña, abrirla.
  void _siOtraPestanaRescatista(Object? resultado) {
    if (resultado is RescatistaTab && mounted) _irARescatista(resultado);
  }

  /// Abre la pestaña elegida en la barra del adoptante (en el inicio o en
  /// cualquier sección: ver AdoptanteTabBar.volverAlInicio).
  void _irAAdoptante(AdoptanteTab t) {
    switch (t) {
      // Ya está en el inicio: no hay nada que abrir.
      case AdoptanteTab.adoptar:
        break;
      case AdoptanteTab.favoritos:
        context.push(AppRoutes.favoritos).then(_alVolverAdoptante);
      case AdoptanteTab.solicitudes:
        context.push(AppRoutes.misSolicitudes).then(_alVolverAdoptante);
      case AdoptanteTab.chats:
        context.push(AppRoutes.adoptanteChats).then(_alVolverAdoptante);
      case AdoptanteTab.negocios:
        context
            .push(
              AppRoutes.aliados,
              extra: (esRescatista: false, esAlbergue: false),
            )
            .then(_alVolverAdoptante);
      // .then(_cargarRol): "Gestionar mis roles" vive en Perfil — sin este
      // refresco, un rol nuevo no aparecía hasta reabrir la app (hallazgo
      // de prueba en teléfono real, 2026-08-03).
      case AdoptanteTab.perfil:
        context.push(AppRoutes.perfilAdoptante, extra: _ciudad).then((r) {
          _cargarRol();
          _alVolverAdoptante(r);
        });
    }
  }

  /// Si en la barra de la sección se tocó otra pestaña, abrirla.
  void _alVolverAdoptante(Object? resultado) {
    if (resultado is AdoptanteTab && mounted) _irAAdoptante(resultado);
  }
}

// ─── Avatar helper (global dentro del archivo) ───────────────────────────────

// AvatarPersona (widgets/avatares.dart), no un CircleAvatar armado a mano — antes,
// si la foto de perfil de Google fallaba al cargar (sin señal, link
// vencido), se veía un círculo de color vacío en vez de caer a la
// inicial, justo en el avatar del encabezado del dashboard principal.
// Hallazgo de auditoría de código.
Widget _avatar(String letter, {double radius = 22}) {
  final user = FirebaseAuth.instance.currentUser;
  final inicial = user?.displayName?.isNotEmpty == true
      ? user!.displayName![0].toUpperCase()
      : letter;
  return Builder(
    builder: (context) => Container(
      padding: const EdgeInsets.all(3),
      decoration: SpDeco.soft(context.sp, radius: SpRadius.full),
      child: AvatarPersona(
        fotoUrl: user?.photoURL,
        inicial: inicial,
        radius: radius,
        backgroundColor: context.sp.lilac,
        textColor: context.sp.lilacInk,
      ),
    ),
  );
}
