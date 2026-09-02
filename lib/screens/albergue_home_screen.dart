import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../widgets/boton_cambiar_rol.dart';
import '../domain/reglas_negocio.dart';
import '../widgets/avatares.dart';
import '../widgets/cambiar_estado_sheet.dart';
import '../widgets/dialogo_cerrar_sesion.dart';
import '../widgets/elegir_foto_perfil.dart';
import '../widgets/fondo_decorativo.dart';
import '../widgets/fotos.dart';
import '../widgets/resultado_guardado_snackbar.dart';
import '../widgets/umbral_estancado_sheet.dart';
import '../services/notificaciones_service.dart';
import '../data/chats_repository.dart';
import '../data/creator_role.dart';
import '../data/firestore_resiliencia.dart';
import '../data/rescates_repository.dart';
import '../data/solicitudes_repository.dart';
import 'package:go_router/go_router.dart';
import '../routing/app_router.dart';
import 'solicitudes_rescatista_screen.dart'
    show verificarVencimientos, verificarSeguimientoPostAdopcion, contactarPersonaEnProceso;
import 'solicitudes_preview.dart';
import 'eliminar_cuenta_dialog.dart';

class AlbergueHomeScreen extends StatefulWidget {
  const AlbergueHomeScreen({super.key});
  @override
  State<AlbergueHomeScreen> createState() => _AlbergueHomeScreenState();
}

class _AlbergueHomeScreenState extends State<AlbergueHomeScreen> {
  // A partir de acá la barra de capacidad ya se pinta en rojo (ver
  // `_panel`) — este aviso lo hace explícito con texto, en vez de dejar
  // que la persona tenga que notar sola el cambio de color.
  static const _pctAvisoCapacidad = 0.9;

  /// Lo que muestran los cuadritos mientras el contador todavía no llegó.
  /// NO un cero: un cero se lee como un dato ya traído. Mismo criterio, y
  /// mismo carácter, que los dos perfiles.
  static const _cargandoValor = '—';
  int _nav = 0;
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final _rescatesRepo = RescatesRepository();
  final _solicitudesRepo = SolicitudesRepository();

  // late final, no getters (lo que había acá antes) — un getter reevalúa su
  // cuerpo cada vez que se lo LEE, y build() lo lee en cada rebuild (cada
  // toque del menú de abajo, _nav). Como el body usa IndexedStack (mantiene
  // las pestañas vivas, no las arma de nuevo), esto tiraba abajo y volvía a
  // levantar los 4 listeners de esta pantalla juntos en cada toque, con el
  // parpadeo de "cargando" que eso genera para datos que ya estaban
  // cargados — mismo bug ya encontrado y arreglado en aliado_home_screen.
  // dart y home_screen.dart, nunca replicado acá. Hallazgo de auditoría de
  // código.
  late final Stream<DocumentSnapshot> _perfilStream = FirebaseFirestore.instance
      .collection('usuarios')
      .doc(_uid)
      .snapshots();
  /// Los tres números del panel, contados del lado del servidor.
  ///
  /// Antes salían de filtrar en Dart el stream COMPLETO de rescates del
  /// albergue: abrir el panel descargaba todos los animales para mostrar
  /// "0 de 40". Con 1.000 son 1.000 lecturas y ~2,5 MB; con 100.000, cien
  /// veces más. Un panel no puede costar en proporción al tamaño del
  /// refugio.
  ///
  /// Son 3 consultas `count()` en vez de 1 descarga: Firestore cobra cada
  /// una como 1 lectura por cada 1.000 documentos contados, así que un
  /// refugio con 100.000 animales paga 300 lecturas en vez de 100.000, y no
  /// baja ni un documento. Ver RescatesRepository.contar().
  Future<List<int>> _numeros = Future.value(const [0, 0, 0]);

  /// Los dos carruseles del panel son VISTAS PREVIAS, no listas: la lista
  /// completa está en "Jauría" / "Ver todas", que pagina sola. Traen una
  /// página acotada cada uno en vez de la colección entera.
  ///
  /// Se piden por separado y filtrados en la CONSULTA. Traer una sola página
  /// y repartirla en Dart daría resultados falsos: si los 10 más recientes
  /// fueran todos adoptados, la Jauría se vería vacía teniendo cientos.
  static const PaginaDeRescates _sinNada = (
    docs: <QueryDocumentSnapshot<Map<String, dynamic>>>[],
    hayMas: false,
    ultimo: null,
  );
  Future<PaginaDeRescates> _jauria = Future.value(_sinNada);

  /// Lo que devolvió [_adoptados], para que la sección "Encontraron hogar"
  /// pueda decidir si mostrarse sin anidar otro FutureBuilder adentro de la
  /// columna que ya se está construyendo.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _adoptadosCache = const [];

  /// Los 10 de la Jauría, **por prioridad y no por fecha**.
  ///
  /// Antes esto era UNA página de 10 ordenada por `creadoEn` descendente, y
  /// el orden por prioridad se hacía después en Dart sobre esos 10. O sea
  /// que un animalito en proceso de adopción publicado hace meses no entraba
  /// en la página y no se veía NUNCA, aunque fuera justo el que hay que
  /// mirar. Hallazgo real de Eliza: "en la Jauría ahora solo aparecen
  /// animales en estado Rescatado". Regresión que introduje al paginar esta
  /// pantalla.
  ///
  /// Se piden en dos consultas, no en una: primero los que necesitan
  /// atención (en proceso de adopción, hogar de paso) y solo se rellena con
  /// el resto si sobra lugar. Así los prioritarios entran siempre, sin
  /// importar cuán viejos sean, que es justo lo que se había perdido.
  ///
  /// No se puede hacer en una sola consulta: Firestore no sabe ordenar por
  /// una lista de prioridades, solo por un campo.
  ///
  /// 'Adoptado' queda afuera de las dos: esos viven en su propia sección.
  /// 'Fallecido' SÍ va, al final, porque si no desaparecería de la pantalla.
  Future<PaginaDeRescates> _cargarJauria() async {
    const cuantos = 10;
    final prioritarios = await _rescatesRepo.paginaDeMisRescates(
      uid: _uid,
      role: CreatorRole.albergue,
      estados: estadosQueNecesitanAtencion,
      porPagina: cuantos,
    );
    final docs = [...prioritarios.docs];
    if (docs.length < cuantos) {
      final resto = await _rescatesRepo.paginaDeMisRescates(
        uid: _uid,
        role: CreatorRole.albergue,
        estados: const ['Rescatado', 'Regresado', 'Fallecido'],
        porPagina: cuantos - docs.length,
      );
      docs.addAll(resto.docs);
    }
    // Dentro de cada grupo el orden ya viene por fecha; esto ordena ENTRE
    // grupos (en proceso antes que hogar de paso, y fallecido al final).
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

  void _refrescarNumeros() {
    if (!mounted) return;
    setState(() {
      // Solo se excluye 'Adoptado' de la Jauría — esos viven en su propia
      // sección de abajo ("Encontraron hogar"). 'Fallecido' SÍ va en la
      // Jauría: antes se excluía junto con 'Adoptado' y un animal fallecido
      // desaparecía de la pantalla por completo.
      _jauria = _cargarJauria();
      _rescatesRepo
          .paginaDeMisRescates(
            uid: _uid,
            role: CreatorRole.albergue,
            estados: const ['Adoptado'],
            porPagina: 10,
          )
          .then(
            (p) {
              if (mounted) setState(() => _adoptadosCache = p.docs);
            },
            // Sin esto, si la consulta falla (sin señal, permiso denegado)
            // queda una excepción asíncrona sin capturar: no rompe la
            // pantalla, pero se reporta a Crashlytics como error no
            // manejado y ensucia lo que sí importa mirar ahí.
            //
            // Se deja lo que hubiera en _adoptadosCache en vez de vaciarlo:
            // no poder confirmar la lista no es lo mismo que "no hay
            // adoptados", y borrarla haría desaparecer la sección entera
            // por un tropiezo de red. El próximo refresco vuelve a
            // intentarlo.
            //
            // onError del `.then` y no un `.catchError` colgado después: así
            // solo se atrapa el fallo de la CONSULTA, y un error dentro del
            // setState de arriba sigue subiendo como corresponde.
            onError: (Object _) {},
          );
      _numeros = Future.wait([
        // "En cuidado" son DOS estados — cuentaComoEnCuidado, en
        // domain/reglas_negocio.dart, sigue siendo la única fuente de esa
        // regla; acá se traduce a la consulta.
        _rescatesRepo.contar(
          uid: _uid,
          role: CreatorRole.albergue,
          estados: const ['Rescatado', 'Regresado'],
        ),
        _rescatesRepo.contar(
          uid: _uid,
          role: CreatorRole.albergue,
          estados: const ['En proceso de adopción'],
        ),
        _rescatesRepo.contar(
          uid: _uid,
          role: CreatorRole.albergue,
          estados: const ['Adoptado'],
        ),
      ]);
    });
  }
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _solicitudesStream =
      _solicitudesRepo.paraOwner(
        uid: _uid,
        role: CreatorRole.albergue,
        estado: 'pendiente',
      );
  final _chatsRepo = ChatsRepository();
  late final Stream<QuerySnapshot> _chatsUnreadStream = _chatsRepo.mios(
    uid: _uid,
    esRescatista: true,
  );
  // Consultas que ESTA cuenta le mandó a un negocio aliado (acá `adoptanteId`
  // soy yo, no `rescatistaId` — ver contarMensajesSinLeer en domain/reglas_negocio.dart).
  // Sin esto, el badge de "mensajes sin leer" nunca contaba una respuesta a
  // una consulta propia, aunque sí apareciera en la lista de Chats.
  late final Stream<QuerySnapshot> _consultasEnviadasStream = _chatsRepo
      .consultasEnviadas(uid: _uid);

  @override
  void initState() {
    _refrescarNumeros();
    super.initState();
    _verificarVencimientos();
    _verificarSeguimientoPostAdopcion();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        NotificacionesService.guardarToken();
        NotificacionesService.escucharEnPrimerPlano(context);
      }
    });
  }

  // Mismo aviso automático que tiene el rescatista (home_screen.dart) para
  // los "hogar de paso" vencidos — antes solo corría ahí, así que un
  // albergue con animales en hogar de paso nunca los veía revisados.
  // Ambas centralizadas en solicitudes_rescatista_screen.dart — antes
  // duplicadas byte a byte con home_screen.dart (hallazgo de auditoría de
  // código).
  Future<void> _verificarVencimientos() async {
    if (!mounted) return;
    await verificarVencimientos(
      context,
      uid: _uid,
      role: CreatorRole.albergue,
      creadoPor: 'albergue',
    );
  }

  Future<void> _verificarSeguimientoPostAdopcion() async {
    await verificarSeguimientoPostAdopcion(
      uid: _uid,
      role: CreatorRole.albergue,
      creadoPor: 'albergue',
    );
  }

  // Estandarizado con perfil_rescatista_screen.dart: mismo ajuste, misma
  // hoja compartida (UmbralEstancadoSheet, widgets/umbral_estancado_sheet.dart), mismo lugar en la
  // pantalla de Perfil — antes esto vivía metido adentro de "Editar perfil
  // del albergue" en vez de junto al resto de los ajustes de cuenta.
  // Pedido real de Eliza.
  Future<void> _configurarUmbralEstancado(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .get();
    if (!context.mounted) return;
    final seleccion = await showModalBottomSheet<int>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => UmbralEstancadoSheet(
        actual: umbralEstancadoDe(doc.data(), esAlbergue: true),
      ),
    );
    if (seleccion == null) return;
    final resultado = await guardarConAviso(
      () => FirebaseFirestore.instance.collection('usuarios').doc(uid).update({
        'umbralEstancadoDiasAlbergue': seleccion,
      }),
    );
    if (!context.mounted) return;
    mostrarResultadoGuardado(context, resultado, exito: 'Umbral actualizado');
  }

  Future<void> _uploadFotoPerfil() async {
    final b64 = await elegirFotoPerfil();
    if (b64 == null) return;
    try {
      await FirebaseFirestore.instance.collection('usuarios').doc(_uid).update({
        'fotoBase64': b64,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Foto de perfil actualizada'),
          backgroundColor: msgExito,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: msgError,
          content: Text('No se pudo subir la foto: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _perfilStream,
      builder: (context, userSnap) {
        final data = userSnap.data?.data() as Map<String, dynamic>? ?? {};
        final nombre = data['albergueNombre'] as String? ?? 'Albergue';
        final tipo = data['albergueTipo'] as String? ?? '';
        final ciudad = data['ciudad'] as String? ?? '';
        final capacidad = (data['capacidadTotal'] as int?) ?? 0;
        final fotoBase64 = data['fotoBase64'] as String?;
        final iniciales = nombre
            .trim()
            .split(' ')
            .take(2)
            .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
            .join();

        return Scaffold(
          backgroundColor: appBg,
          body: FutureBuilder<List<int>>(
            future: _numeros,
            builder: (context, rSnap) {
              // Los tres contadores YA NO bloquean la pantalla.
              //
              // Acá había un `if (waiting) return CircularProgressIndicator()`
              // que envolvía el body ENTERO: hasta que no volvían las tres
              // consultas no se pintaba nada, ni el encabezado, ni la barra
              // de capacidad, ni la Jauría. Y son tres `count()`, que es una
              // agregación: su única fuente posible es el servidor
              // (`AggregateSource` tiene un solo valor), así que no hay
              // caché y en cada inicio de sesión se paga el viaje entero, en
              // frío. Eliza: "cada vez que entro como albergue la Jauría
              // tarda bastante en aparecer" — y la Jauría no tenía nada que
              // ver, no podía ni empezar a mostrarse.
              //
              // El panel del rescatista nunca lo tuvo: ahí este mismo
              // FutureBuilder envuelve UN cuadrito (home_screen.dart), no la
              // pantalla, y el carrusel tiene su propio spinner en su lugar.
              //
              // Ahora los números viajan como `int?`: null es "todavía no se
              // sabe". No es cero, y por eso las piezas que dependen de
              // ellos esperan mientras el resto del panel ya se ve. Mismo
              // criterio que el `?? 0` que sacamos de los dos perfiles: un
              // cero mientras carga se lee como un dato ya traído.
              //
              // Nota sobre errores: antes un fallo mostraba `errorFeedState()`
              // en toda la pantalla. Ahora `rSnap.data` queda en null, así
              // que los números muestran su marcador en vez de un 0 falso.
              // Se conserva lo que ese estado protegía (no mentir) y se
              // pierde el cartel de error a pantalla completa.
              final enCuidado = rSnap.data?.elementAtOrNull(0);
              final enAdopcion = rSnap.data?.elementAtOrNull(1);
              final adoptados = rSnap.data?.elementAtOrNull(2);

              return Stack(
                children: [
                  const Positioned.fill(child: LeafOverlay()),
                  SafeArea(
                    child: _nav == 0
                        ? _panel(
                            context,
                            nombre,
                            tipo,
                            ciudad,
                            iniciales,
                            fotoBase64,
                            capacidad,
                            enCuidado,
                            enAdopcion,
                            adoptados,
                          )
                        : _nav == 3
                        ? _perfilTab(
                            context,
                            nombre,
                            tipo,
                            ciudad,
                            iniciales,
                            fotoBase64,
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              );
            },
          ),
          bottomNavigationBar: StreamBuilder<QuerySnapshot>(
            stream: _solicitudesStream,
            builder: (context, solSnap) {
              final pendientes = solSnap.data?.docs.length ?? 0;
              return _bottomNav(pendientes);
            },
          ),
        );
      },
    );
  }

  // ── Panel principal ──────────────────────────────────────────────────────────

  Widget _panel(
    BuildContext ctx,
    String nombre,
    String tipo,
    String ciudad,
    String iniciales,
    String? fotoBase64,
    int capacidad,
    // `null` = todavía no llegó el contador. NO es cero: las piezas que
    // dependen de estos números esperan, y el resto del panel ya se pinta.
    int? enCuidado,
    int? enAdopcion,
    int? adoptados,
  ) {
    // Se calculan acá, y solo si hay con qué. Antes venían ya resueltos
    // desde build(), que era justo lo que obligaba a esperar a las tres
    // consultas antes de dibujar nada.
    final totalActivos = enCuidado != null && enAdopcion != null
        ? enCuidado + enAdopcion
        : null;
    final pct = totalActivos != null && capacidad > 0
        ? (totalActivos / capacidad).clamp(0.0, 1.0)
        : 0.0;
    // Con capacidades chicas, el % solo no alcanza a avisar con margen: con
    // capacidad=3, no existe ningún totalActivos entero entre el 90% (2.7)
    // y el 100% — se salta directo del "sin aviso" al "ya lleno". Por eso
    // el aviso de abajo se dispara con esta condición O el porcentaje de
    // siempre — alcanza que se cumpla una de las dos (pedido real de
    // Eliza, probando con un albergue de capacidad chica).
    final lugaresLibres = capacidad > 0 && totalActivos != null
        ? capacidad - totalActivos
        : null;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (chipCambiarRol(context) case final boton?)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 16, top: 8),
                child: boton,
              ),
            ),

          // ── Hero card ────────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0A5C40), appTeal],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: appTeal.withValues(alpha: 0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Avatar
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                          width: 2.5,
                        ),
                      ),
                      // AvatarPersona (widgets/avatares.dart), no un
                      // CircleAvatar armado a mano: con
                      // onBackgroundImageError vacío, si la foto fallaba al
                      // cargar quedaba un círculo vacío en vez de caer a
                      // las iniciales. AvatarPersona ya resuelve el mismo
                      // orden de prioridad (logo propio → foto de Google →
                      // iniciales) que antes se armaba acá a mano. Hallazgo
                      // de auditoría de código.
                      child: AvatarPersona(
                        fotoBase64: fotoBase64,
                        fotoUrl: FirebaseAuth.instance.currentUser?.photoURL,
                        inicial: iniciales,
                        radius: 28,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        textColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hola 👋',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            nombre,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontFamily: 'Baloo2',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (tipo.isNotEmpty || ciudad.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on,
                                  size: 12,
                                  color: Colors.white.withValues(alpha: 0.7),
                                ),
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(
                                    [
                                      if (tipo.isNotEmpty) tipo,
                                      if (ciudad.isNotEmpty) ciudad,
                                    ].join(' · '),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white.withValues(
                                        alpha: 0.75,
                                      ),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),

                // Estadística histórica. Mientras el contador no llegó no
                // se muestra: decir "0 animales ya encontraron hogar" sería
                // afirmar algo que todavía no se sabe.
                if ((adoptados ?? 0) > 0) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.emoji_events_outlined,
                        size: 13,
                        color: Colors.amber,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${adoptados == 1 ? '1 animal' : '$adoptados animales'} ya encontraron hogar',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ],

                // Barra de capacidad. Necesita `totalActivos`, así que
                // espera igual que la estadística de arriba; el resto de la
                // tarjeta (nombre, foto, ciudad) ya se pintó.
                if (capacidad > 0 && totalActivos != null) ...[
                  const SizedBox(height: 20),
                  // Antes también se mostraba el porcentaje ("67% ocupado") al
                  // lado de "N de M animales" — confundía más de lo que ayudaba
                  // (Eliza esperaba ver el 90% del umbral interno reflejado acá,
                  // en vez del porcentaje real de ocupación). El umbral del 90%
                  // sigue existiendo por dentro (define cuándo la barra se pone
                  // roja y cuándo aparece el aviso), solo se dejó de mostrar el
                  // número.
                  Text(
                    '$totalActivos de $capacidad animales',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: pct == 0 ? 0.01 : pct,
                      minHeight: 8,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        pct >= 0.9 ? Colors.red.shade300 : Colors.white,
                      ),
                    ),
                  ),
                  if (pct >= _pctAvisoCapacidad ||
                      (lugaresLibres != null && lugaresLibres <= 1)) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 14,
                            color: Colors.amber.shade200,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              pct >= 1.0
                                  ? 'Llegaste al límite de capacidad. Considerá frenar nuevos ingresos.'
                                  : 'Cerca del límite de capacidad. Considerá acelerar adopciones.',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Stats ─────────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _statCard(
                  ctx,
                  enCuidado == null ? _cargandoValor : '$enCuidado',
                  'En cuidado',
                  appTeal,
                  Icons.favorite_outline,
                  'En cuidado',
                ),
                const SizedBox(width: 10),
                _statCard(
                  ctx,
                  adoptados == null ? _cargandoValor : '$adoptados',
                  'Adoptados',
                  const Color(0xFF2196F3),
                  Icons.home_outlined,
                  'Adoptado',
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── CTAs ──────────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                _subirLoteCard(ctx),
                const SizedBox(height: 10),
                _subirUnoCard(ctx),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ── Solicitudes ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: StreamBuilder<QuerySnapshot>(
              stream: _solicitudesStream,
              builder: (context, snap) {
                final count = snap.data?.docs.length ?? 0;
                return _sectionHeader(
                  'SOLICITUDES',
                  trailing: GestureDetector(
                    onTap: () =>
                        context.push(AppRoutes.solicitudesRescatista, extra: true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: count > 0
                            ? appOrange.withValues(alpha: 0.1)
                            : appTeal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: count > 0
                              ? appOrange.withValues(alpha: 0.3)
                              : appTeal.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        count > 0 ? '$count pendientes' : 'Ver todas',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: count > 0 ? appOrange : appTeal,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SolicitudesPreview(role: CreatorRole.albergue),
          ),

          const SizedBox(height: 20),

          // ── Red de hogares de paso ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GestureDetector(
              onTap: () => ctx.push(AppRoutes.hogaresDePaso),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: appTeal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('🫶', style: TextStyle(fontSize: 18)),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Red de hogares de paso',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.grey.shade400),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Jauría ────────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _sectionHeader(
              'LA JAURÍA',
              trailing: GestureDetector(
                // Refrescar AL VOLVER, igual que home_screen.dart hace con
                // este mismo destino.
                //
                // "Ver todas" lleva a mis_rescates_screen, y desde ahí se
                // puede cambiar el estado de un animalito (esa pantalla
                // abre su propia CambiarEstadoSheet). Al volver, este panel
                // no se reconstruye: su State sigue vivo debajo, con
                // `_jauria`, `_adoptadosCache` y `_numeros` congelados en lo
                // que cargó `initState`. Resultado: adoptabas desde "Ver
                // todas" y el animalito no aparecía en "Encontraron hogar",
                // ni se movían los números de arriba, por el resto de la
                // sesión. Hallazgo de Eliza.
                //
                // El panel del rescatista nunca tuvo el problema porque su
                // push a esta misma ruta sí llevaba el `.then`.
                onTap: () => context
                    .push(
                      AppRoutes.misRescates,
                      extra: (filtroInicial: null, esAlbergue: true),
                    )
                    .then((_) => _refrescarNumeros()),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: appTeal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: appTeal.withValues(alpha: 0.3)),
                  ),
                  child: const Text(
                    'Gestionar',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: appTeal,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: FutureBuilder<PaginaDeRescates>(
              future: _jauria,
              builder: (_, snap) => _jauriaCarousel([...?snap.data?.docs]),
            ),
          ),

          // ── Ya encontraron hogar ──────────────────────────────────────────
          Builder(
            builder: (_) {
              final adoptadosDocs = _adoptadosCache;
              if (adoptadosDocs.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 28),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _sectionHeader(
                      'ENCONTRARON HOGAR 🏡',
                      // "Gestionar" (no "Ver todos") y verde (no el azul suelto
                      // que no es de la paleta) — mismo texto y color que el
                      // botón gemelo de "LA JAURÍA" de arriba, que hace
                      // exactamente el mismo tipo de navegación. "Ver todos" era
                      // engañoso: la fila de acá abajo YA muestra todos los
                      // adoptados sin límite, nada queda escondido — lo que este
                      // botón realmente ofrece es ir a editar/compartir/eliminar,
                      // acciones que la tarjeta chica del carrusel no tiene
                      // (sugerencia real de Eliza).
                      trailing: GestureDetector(
                        // Mismo motivo que en la cabecera de LA JAURÍA.
                        onTap: () => ctx
                            .push(
                              AppRoutes.misRescates,
                              extra: (
                                filtroInicial: 'Adoptado',
                                esAlbergue: true,
                              ),
                            )
                            .then((_) => _refrescarNumeros()),
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
                          child: const Text(
                            'Gestionar',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: appTeal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: _adoptadosCarousel(adoptadosDocs),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── Perfil tab ───────────────────────────────────────────────────────────────

  Widget _perfilTab(
    BuildContext ctx,
    String nombre,
    String tipo,
    String ciudad,
    String iniciales,
    String? fotoBase64,
  ) {
    final user = FirebaseAuth.instance.currentUser;
    return SingleChildScrollView(
      child: Column(
        children: [
          // Header verde — mismo estilo que el perfil de aliado
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0A5C40), appTeal],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: _uploadFotoPerfil,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.5),
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: AvatarPersona(
                          fotoBase64: fotoBase64,
                          fotoUrl: user?.photoURL,
                          inicial: iniciales,
                          radius: 52,
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          textColor: Colors.white,
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: appTeal,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  nombre,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (tipo.isNotEmpty || ciudad.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (tipo.isNotEmpty) tipo,
                      if (ciudad.isNotEmpty) ciudad,
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                _infoTile(Icons.email_outlined, 'Correo', user?.email ?? '-'),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => ctx.push(AppRoutes.alberguePerfil),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Editar perfil del albergue'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: appTeal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => _configurarUmbralEstancado(ctx),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.schedule, color: appOrange, size: 20),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Aviso sin adoptar',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(Icons.chevron_right, color: Colors.grey.shade400),
                      ],
                    ),
                  ),
                ),
                // Acá NO va "Gestionar mis roles", y es a propósito.
                //
                // Estuvo un rato y había que sacarlo: la hoja de roles
                // (widgets/roles_sheet.dart) solo ofrece Adoptante y
                // Rescatista. No tiene casilla para Albergue ni para Aliado,
                // y arranca copiando los roles que ya están, así que desde
                // acá solo se podían AGREGAR roles, nunca salir de este.
                //
                // Y agregarlos no cambiaba nada: resolverPantallaPerfil
                // (domain/resolucion_perfil.dart) manda a albergue y a aliado
                // antes que a cualquier otro rol, así que después de guardar
                // se volvía a aterrizar exactamente acá. Un botón que promete
                // una salida y no la da es peor que no tenerlo.
                //
                // La salida de verdad sigue sin existir: quien tiene rol de
                // negocio no puede volver al lado de adoptante/rescatista
                // desde la app. Queda como trabajo para después del
                // lanzamiento, y la forma que tiene más sentido es un cambio
                // de VISTA (como el interruptor Adoptante/Rescatista que ya
                // existe en el inicio), no tocar los roles guardados.
                //
                // Si estás por volver a poner este botón: no alcanza con
                // ponerlo. Hay que hacer que la hoja o el enrutado permitan
                // salir, o vuelve a no hacer nada.
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => mostrarDialogoCerrarSesion(ctx),
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Cerrar sesión'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade400,
                      side: BorderSide(color: Colors.red.shade200),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => mostrarEliminarCuentaDialog(ctx),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Eliminar mi cuenta'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade200),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => launchUrl(
                    Uri.parse(
                      'https://lunita486.github.io/Salva-Patitas/privacidad.html',
                    ),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 16,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Política de Privacidad',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                            decoration: TextDecoration.underline,
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

  Widget _infoTile(IconData icono, String label, String valor) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      children: [
        Icon(icono, size: 20, color: appTeal),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              valor,
              style: const TextStyle(
                fontSize: 14,
                color: appInk,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  // ── Widgets ──────────────────────────────────────────────────────────────────

  Widget _statCard(
    BuildContext ctx,
    String valor,
    String label,
    Color color,
    IconData icono,
    String? filtro,
  ) {
    return Expanded(
      child: GestureDetector(
        // Los cuadritos de arriba también llevan a "Ver todas", filtrados.
        // Mismo motivo que en la cabecera de LA JAURÍA: sin el `.then`, el
        // cuadrito azul de Adoptados se quedaba con el número viejo después
        // de adoptar desde esa pantalla.
        onTap: () => filtro != null
            ? ctx
                  .push(
                    AppRoutes.misRescates,
                    extra: (filtroInicial: filtro, esAlbergue: true),
                  )
                  .then((_) => _refrescarNumeros())
            : ctx.push(AppRoutes.solicitudesRescatista, extra: true),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icono, size: 17, color: color),
              ),
              const SizedBox(height: 10),
              Text(
                valor,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: color,
                  height: 1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _subirLoteCard(BuildContext ctx) => GestureDetector(
    onTap: () => ctx.push(AppRoutes.subirLote),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A5C40), appTeal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: appTeal.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icono apilado: 3 animalitos distintos (antes eran 3 patitas
          // blancas idénticas — "lindo, con colorcito", pedido real de
          // Eliza) — el emoji de cada uno ya trae su propio color, no hace
          // falta pintarlo a mano.
          SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('🐶', style: TextStyle(fontSize: 19)),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('🐱', style: TextStyle(fontSize: 15)),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 8,
                  child: Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Text('🐰', style: TextStyle(fontSize: 13)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Subir lote',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Sube varios animales a la vez',
                  style: TextStyle(fontSize: 12, color: Color(0xFFAAD9C4)),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.arrow_forward_ios,
              color: Colors.white,
              size: 14,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _subirUnoCard(BuildContext ctx) => GestureDetector(
    onTap: () => ctx.push(AppRoutes.subirRescate, extra: true),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Mismo círculo naranja con "+" que usa el rescatista en su propio
          // "Subir un rescate" (home_screen.dart, _ctaCard) — Eliza lo vio ahí
          // y pidió el mismo acá, en vez del combo con emoji que había antes.
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: appOrange,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.add, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 18),
          const Text(
            'Subir uno solo',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: appInk,
            ),
          ),
          const Spacer(),
          Icon(Icons.chevron_right, color: Colors.grey.shade400),
        ],
      ),
    ),
  );

  // Antes copiado byte a byte en las dos tarjetas de animal de este archivo
  // (la de "La Jauría" y la de "Ya encontraron hogar") — hallazgo de
  // auditoría de código. Devuelve SizedBox.shrink() (sin alto, invisible)
  // cuando no corresponde mostrar el botón, así el llamador lo agrega
  // siempre como un solo ítem de la lista, sin repetir el `if` en cada
  // lugar.
  Widget _botonContactar(
    BuildContext ctx, {
    required String docId,
    required String nombre,
    required String especie,
    required String? fotoUrl,
    required Map<String, dynamic> d,
  }) {
    final estadoAdopcion = d['estadoAdopcion'] as String? ?? '';
    final adoptanteIdEnProceso = d['adoptanteIdEnProceso'] as String? ?? '';
    if (!(estadoAdopcion == 'Hogar de paso' ||
            estadoAdopcion == 'En proceso de adopción') ||
        adoptanteIdEnProceso.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 6),
        Semantics(
          button: true,
          label: 'Contactar a quien está en proceso con $nombre',
          child: GestureDetector(
            onTap: () => contactarPersonaEnProceso(
              ctx,
              docId: docId,
              nombre: nombre,
              especie: especie,
              fotoUrl: fotoUrl,
              creadoPor: d['creadoPor'] as String?,
              adoptanteIdEnProceso: adoptanteIdEnProceso,
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 5),
              decoration: BoxDecoration(
                color: appOrange,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 11,
                    color: Colors.white,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Contactar',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String label, {Widget? trailing}) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      // Expanded + ellipsis: sin esto, un título largo (ej. "YA ENCONTRARON
      // HOGAR 🏡") empujaba el botón "Gestionar" fuera de pantalla en vez
      // de acortarse — el botón quedaba cortado (bug real reportado por
      // Eliza probando en el celular).
      Expanded(
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: appInk,
          ),
        ),
      ),
      if (trailing != null) ...[const SizedBox(width: 8), trailing],
    ],
  );

  Widget _jauriaCarousel(List<QueryDocumentSnapshot> rescates) {
    if (rescates.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Aún no tienes animales publicados.',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => context.push(AppRoutes.subirRescate, extra: true),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: appTeal,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text(
                      'Publicar el primero',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    // SIN re-ordenar acá: quien llama (más arriba, "── Jauría ──") ya deja
    // `rescates` ordenado por prioridad de estado (en proceso de adopción →
    // hogar de paso → rescatado → fallecido) con empate por fecha. Antes
    // este widget volvía a ordenar TODO de nuevo, solo por fecha —
    // pisando ese orden en silencio. Con pocos animales de estados
    // distintos podía coincidir por casualidad (el más nuevo también era
    // el de mayor prioridad, como en la captura de Eliza), pero en
    // general el orden por prioridad nunca llegaba a verse. Hallazgo real
    // de Eliza: "no está organizado la jauría como en el rescatista".
    final sorted = rescates;

    return SizedBox(
      height: 195,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: sorted.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (ctx, i) {
          final d = sorted[i].data() as Map<String, dynamic>;
          final docId = sorted[i].id;
          final nombre = nombreDeAnimal(d['nombre'] as String?);
          final especie = d['especie'] as String? ?? 'Perro';
          final edad = d['edad'] as String? ?? '';
          final fotoUrl = d['fotoUrl'] as String?;
          final estadoAdopcion = d['estadoAdopcion'] as String? ?? 'Rescatado';
          final ts = d['creadoEn'] as Timestamp?;
          final urgencia = d['urgencia'] as String? ?? '';
          final emoji = especie == 'Gato' ? '🐱' : '🐶';
          final esNuevo =
              ts != null && DateTime.now().difference(ts.toDate()).inHours < 24;
          // El año solo se agrega cuando DIFIERE del actual — mismo
          // criterio que mis_rescates_screen.dart y chat_screen.dart. Sin
          // esto, un animal de hace más de un año se ve indistinguible de
          // uno de ayer. Hallazgo real de Eliza, probando ya entrado 2027.
          final fechaStr = ts != null
              ? formatearFecha(
                  ts.toDate(),
                  conAnio: ts.toDate().year != DateTime.now().year,
                )
              : '';
          final estadoColor = cicloColor(estadoAdopcion);

          return Container(
            // Sin esto, aprobar una solicitud (o cualquier cambio que
            // mueva a este animal de posición dentro del orden por
            // prioridad) hacía que Flutter reutilizara por POSICIÓN la
            // tarjeta de otro animal para este lugar — la foto vieja se
            // veía un instante, un parpadeo. Mismo arreglo que
            // home_screen.dart:_misRescatesCarousel. Hallazgo real de
            // Eliza.
            key: ValueKey(docId),
            width: 128,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      // FotoAnimal en vez de recorte — mismo caso "Tobyiii" que
                      // el feed del adoptante: esta tarjeta del panel de
                      // albergue es grande y el recorte fijo podía dejar
                      // afuera al animal entero en fotos verticales.
                      child: fotoUrl != null
                          ? FotoAnimal(
                              url: fotoUrl,
                              width: double.infinity,
                              fallback: Container(
                                width: double.infinity,
                                color: const Color(0xFFD8F0E4),
                                child: Center(
                                  child: Text(
                                    emoji,
                                    style: const TextStyle(fontSize: 36),
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              width: double.infinity,
                              color: const Color(0xFFD8F0E4),
                              child: Center(
                                child: Text(
                                  emoji,
                                  style: const TextStyle(fontSize: 36),
                                ),
                              ),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nombre,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: appInk,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (edad.isNotEmpty) edad,
                              if (fechaStr.isNotEmpty) fechaStr,
                            ].join(' · '),
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          // ── Chip de estado tappable ──────────────────
                          // Semantics explícito — hallazgo de auditoría de código
                          // (mismo arreglo que en mis_rescates_screen.dart).
                          Semantics(
                            button: estadoAdopcion != 'Fallecido',
                            label: estadoAdopcion == 'Fallecido'
                                ? 'Estado: Fallecido'
                                : 'Cambiar estado, actualmente $estadoAdopcion',
                            child: GestureDetector(
                              onTap: estadoAdopcion == 'Fallecido'
                                  ? null
                                  : () => showModalBottomSheet(
                                      context: ctx,
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
                                            d['adoptanteIdEnProceso']
                                                as String?,
                                        esAlbergue: true,
                                      ),
                                    ).then((_) => _refrescarNumeros()),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: estadoColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: estadoColor.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        estadoAdopcion,
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: estadoColor,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Icon(
                                      Icons.expand_more,
                                      size: 11,
                                      color: estadoColor,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Antes el albergue no tenía NINGUNA forma de contactar
                          // a quien tiene el animal en "Hogar de paso" o "En
                          // proceso de adopción" — este botón solo existía en el
                          // panel del rescatista (home_screen.dart), nunca acá.
                          _botonContactar(
                            ctx,
                            docId: docId,
                            nombre: nombre,
                            especie: especie,
                            fotoUrl: fotoUrl,
                            d: d,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (urgencia == 'Alta')
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD32F2F),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'URGENTE',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                if (esNuevo)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: appOrange,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Nuevo',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _adoptadosCarousel(List<QueryDocumentSnapshot> docs) {
    final sorted = [...docs]
      ..sort((a, b) {
        final ta = ((a.data() as Map)['creadoEn'] as Timestamp?);
        final tb = ((b.data() as Map)['creadoEn'] as Timestamp?);
        if (ta == null || tb == null) return 0;
        return tb.compareTo(ta);
      });

    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: sorted.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (ctx, i) {
          final d = sorted[i].data() as Map<String, dynamic>;
          final docId = sorted[i].id;
          final nombre = nombreDeAnimal(d['nombre'] as String?);
          final especie = d['especie'] as String? ?? 'Perro';
          final fotoUrl = d['fotoUrl'] as String?;
          final estadoAdopcion = d['estadoAdopcion'] as String? ?? 'Adoptado';
          final emoji = especie == 'Gato' ? '🐱' : '🐶';
          final estadoColor = cicloColor(estadoAdopcion);

          return Container(
            key: ValueKey(docId),
            width: 128,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      // FotoAnimal en vez de recorte — mismo motivo que la
                      // otra tarjeta de arriba (caso "Tobyiii").
                      child: fotoUrl != null
                          ? FotoAnimal(
                              url: fotoUrl,
                              width: double.infinity,
                              fallback: Container(
                                width: double.infinity,
                                color: const Color(0xFFD8F0E4),
                                child: Center(
                                  child: Text(
                                    emoji,
                                    style: const TextStyle(fontSize: 32),
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              width: double.infinity,
                              color: const Color(0xFFD8F0E4),
                              child: Center(
                                child: Text(
                                  emoji,
                                  style: const TextStyle(fontSize: 32),
                                ),
                              ),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nombre,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: appInk,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          // Mismo chip tappable que _jauriaCarousel — antes acá
                          // solo había un ícono fijo, así que si un animal
                          // "Adoptado" era devuelto no había forma de cambiarle
                          // el estado desde el panel (había que ir a "Gestionar").
                          Semantics(
                            button: true,
                            label:
                                'Cambiar estado, actualmente $estadoAdopcion',
                            child: GestureDetector(
                              onTap: () => showModalBottomSheet(
                                context: ctx,
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
                                      d['adoptanteIdEnProceso'] as String?,
                                  esAlbergue: true,
                                ),
                              ).then((_) => _refrescarNumeros()),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: estadoColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: estadoColor.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        estadoAdopcion,
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: estadoColor,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Icon(
                                      Icons.expand_more,
                                      size: 11,
                                      color: estadoColor,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          _botonContactar(
                            ctx,
                            docId: docId,
                            nombre: nombre,
                            especie: especie,
                            fotoUrl: fotoUrl,
                            d: d,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Bottom nav ───────────────────────────────────────────────────────────────

  Widget _bottomNav(int pendientes) {
    final items = [
      _NavItem(Icons.dashboard_outlined, Icons.dashboard, 'Panel'),
      _NavItem(Icons.pets_outlined, Icons.pets, 'Jauría'),
      _NavItem(
        Icons.assignment_outlined,
        Icons.assignment,
        'Solicitudes',
        badge: pendientes,
      ),
    ];
    // 'Perfil' se agrega al final, después de 'Chats' — mismo orden que en
    // el resto de la app (Rescatista, Aliado): Perfil siempre es el último ícono.
    const perfilIndex = 3;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
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
              ...List.generate(items.length, (i) {
                final item = items[i];
                final active = _nav == i;
                return GestureDetector(
                  onTap: () {
                    if (i == 1) {
                      // Mismo motivo que en la cabecera de LA JAURÍA.
                      context
                          .push(
                            AppRoutes.misRescates,
                            extra: (filtroInicial: null, esAlbergue: true),
                          )
                          .then((_) => _refrescarNumeros());
                    } else if (i == 2) {
                      context.push(AppRoutes.solicitudesRescatista, extra: true);
                    } else {
                      setState(() => _nav = i);
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(
                            active ? item.iconActive : item.icon,
                            color: active ? appTeal : Colors.grey.shade400,
                            size: 24,
                          ),
                          if (item.badge > 0)
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
                                  item.badge > 9 ? '9+' : '${item.badge}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 10,
                          color: active ? appTeal : Colors.grey.shade400,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                );
              }),
              StreamBuilder<QuerySnapshot>(
                stream: _chatsUnreadStream,
                builder: (_, snap) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: _consultasEnviadasStream,
                    builder: (_, consultaSnap) {
                      final unread = contarMensajesSinLeer(
                        recibidos: snap.data?.docs,
                        consultasEnviadas: consultaSnap.data?.docs,
                        esAlbergue: true,
                        uid: _uid,
                      );
                      return GestureDetector(
                        onTap: () => context.push(
                          AppRoutes.adoptanteChats,
                          extra: (
                            esRescatista: true,
                            soloConsultas: false,
                            esAlbergue: true,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline,
                                  color: Colors.grey.shade400,
                                  size: 24,
                                ),
                                if (unread > 0)
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
                                        unread > 9 ? '9+' : '$unread',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 9,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Chats',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade400,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
              GestureDetector(
                onTap: () => context.push(
                  AppRoutes.aliados,
                  extra: (esRescatista: true, esAlbergue: true),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.store_outlined,
                      color: Colors.grey.shade400,
                      size: 24,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Negocios',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
              Builder(
                builder: (_) {
                  final active = _nav == perfilIndex;
                  return GestureDetector(
                    onTap: () => setState(() => _nav = perfilIndex),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          active ? Icons.person : Icons.person_outline,
                          color: active ? appTeal : Colors.grey.shade400,
                          size: 24,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Perfil',
                          style: TextStyle(
                            fontSize: 10,
                            color: active ? appTeal : Colors.grey.shade400,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData iconActive;
  final String label;
  final int badge;
  const _NavItem(this.icon, this.iconActive, this.label, {this.badge = 0});
}
