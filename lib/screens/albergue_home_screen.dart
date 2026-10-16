import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/boton_cambiar_rol.dart';
import '../domain/reglas_negocio.dart';
import '../widgets/avatares.dart';
import '../widgets/cambiar_estado_sheet.dart';
import '../widgets/dialogo_cerrar_sesion.dart';
import '../widgets/elegir_foto_perfil.dart';
import '../widgets/sp_widgets.dart';
import '../widgets/albergue_tab_bar.dart';
import '../widgets/apariencia_sheet.dart';
import '../theme/apariencia.dart';
import '../theme/salva_patitas_theme.dart';
import '../widgets/fotos.dart';
import '../widgets/resultado_guardado_snackbar.dart';
import '../widgets/umbral_estancado_sheet.dart';
import '../services/notificaciones_service.dart';
import '../data/creator_role.dart';
import '../data/firestore_resiliencia.dart';
import '../data/rescates_repository.dart';
import '../data/solicitudes_repository.dart';
import 'package:go_router/go_router.dart';
import '../routing/app_router.dart';
import 'solicitudes_rescatista_screen.dart'
    show
        verificarVencimientos,
        verificarSeguimientoPostAdopcion,
        contactarPersonaEnProceso;
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

  /// El alto del carrusel de la Jauría. Está en una constante para que el
  /// spinner de "todavía cargando" ocupe exactamente lo mismo que las
  /// tarjetas y la pantalla no salte al reemplazar uno por otro.
  static const _altoCarruselJauria = 250.0;

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
  /// 'Adoptado' y 'Fallecido' quedan afuera de las dos consultas.
  ///
  /// 'Fallecido' estuvo dentro un tiempo, al final del orden, para que un
  /// animalito muerto no desapareciera del panel. Se sacó a pedido de
  /// Eliza: el problema es que **ocupaba uno de los 10 lugares**. El límite
  /// se aplica en la consulta, así que tres fallecidos dejaban al panel
  /// mostrando siete vivos, y el `sort` de abajo solo los mandaba al final
  /// cuando el lugar ya estaba gastado.
  ///
  /// Ahora los 10 son siempre animalitos vivos. Un fallecido se sigue
  /// alcanzando desde "Ver todas" filtrando por estado; lo que se pierde es
  /// verlo al abrir el panel.
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
        estados: const ['Rescatado', 'Regresado'],
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
      // 'Adoptado' queda afuera de la Jauría: esos viven en su propia
      // sección de abajo ("Encontraron hogar"). 'Fallecido' también, para
      // que no gaste uno de los 10 lugares — ver el doc de _cargarJauria().
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

  /// Solicitudes pendientes, para el Perfil y el encabezado de SOLICITUDES
  /// del Panel. `_solicitudesStream`
  /// es un stream de Firestore de tipo broadcast: quien se suscribe tarde
  /// (el Perfil, o el Panel al volver de otra pestaña) no
  /// recibe la última foto y se quedaba en "—" para siempre. Por eso el
  /// número se guarda acá, escuchado una sola vez desde el inicio.
  int? _pendientes;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subPendientes;

  @override
  void dispose() {
    _subPendientes?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    _refrescarNumeros();
    super.initState();
    _subPendientes = _solicitudesStream.listen((snap) {
      if (mounted) setState(() => _pendientes = snap.docs.length);
    }, onError: (_) {});
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
        SnackBar(
          content: const Text('Foto de perfil actualizada'),
          backgroundColor: context.sp.msgExito,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: context.sp.msgError,
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
          backgroundColor: context.sp.bg,
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
                  const Positioned.fill(child: SpPawBackground()),
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
                            enCuidado,
                            enAdopcion,
                            adoptados,
                            umbralEstancadoDe(data, esAlbergue: true),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              );
            },
          ),
          bottomNavigationBar: AlbergueTabBar(
            actual: _nav == 3 ? AlbergueTab.perfil : AlbergueTab.panel,
            onTap: _irA,
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
    final c = ctx.sp;
    final avisoCapacidad =
        pct >= _pctAvisoCapacidad ||
        (lugaresLibres != null && lugaresLibres <= 1);
    return SingleChildScrollView(
      // Una clave por pestaña: Panel y Perfil ocupan el mismo lugar del
      // árbol, y sin esto Flutter reusaba el mismo desplazamiento — el Perfil
      // abría tan abajo como hubieras bajado en el Panel.
      key: const PageStorageKey('panel'),
      padding: const EdgeInsets.fromLTRB(
        SpSpace.screen,
        SpSpace.s2,
        SpSpace.screen,
        24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Saludo ───────────────────────────────────────────────────────────
          // La campanita del prototipo no va: la app no tiene notificaciones
          // en pantalla. En su lugar queda el botón de cambiar rol (solo debug).
          Row(
            children: [
              // AvatarPersona (widgets/avatares.dart), no un CircleAvatar
              // armado a mano: con onBackgroundImageError vacío, si la foto
              // fallaba al cargar quedaba un círculo vacío en vez de caer a
              // las iniciales. Hallazgo de auditoría de código.
              Container(
                decoration: SpDeco.soft(c, radius: SpRadius.full),
                child: AvatarPersona(
                  fotoBase64: fotoBase64,
                  fotoUrl: FirebaseAuth.instance.currentUser?.photoURL,
                  inicial: iniciales,
                  radius: 22,
                  backgroundColor: c.mint,
                  textColor: c.primaryStrong,
                ),
              ),
              const SizedBox(width: SpSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hola de nuevo',
                      style: SpText.label.copyWith(color: c.inkMuted),
                    ),
                    Text(
                      nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SpText.section.copyWith(color: c.ink),
                    ),
                  ],
                ),
              ),
              ?chipCambiarRol(context),
            ],
          ),

          // ── Héroe ────────────────────────────────────────────────────────────
          const SizedBox(height: 46),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(
                  SpSpace.s4,
                  SpSpace.s6,
                  SpSpace.s4,
                  SpSpace.s4,
                ),
                decoration: SpDeco.primary(
                  c,
                  radius: SpRadius.xl,
                  gradient: true,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tu albergue hoy',
                      style: SpText.label.copyWith(
                        color: c.onPrimary.withValues(alpha: .85),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      width: 180,
                      child: Text(
                        totalActivos == 1
                            ? '1 patita en cuidado'
                            : '${totalActivos ?? _cargandoValor} patitas en cuidado',
                        style: SpText.screen.copyWith(color: c.onPrimary),
                      ),
                    ),
                    // Barra de capacidad. Necesita `totalActivos`, así que
                    // espera; el resto del héroe ya se pintó.
                    //
                    // Antes también se mostraba el porcentaje ("67% ocupado")
                    // — confundía más de lo que ayudaba (Eliza esperaba ver el
                    // 90% del umbral interno reflejado acá). El umbral sigue
                    // por dentro: define cuándo la barra se pone coral y
                    // cuándo aparece el aviso.
                    if (capacidad > 0 && totalActivos != null) ...[
                      const SizedBox(height: SpSpace.s4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Capacidad', style: _heroMeta(c)),
                          Text(
                            '$totalActivos de $capacidad',
                            style: _heroMeta(c),
                          ),
                        ],
                      ),
                      const SizedBox(height: SpSpace.s2),
                      _barraCapacidad(c, pct),
                      if (avisoCapacidad) ...[
                        const SizedBox(height: SpSpace.s3),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: SpDeco.shine.withValues(alpha: .55),
                            borderRadius: BorderRadius.circular(SpRadius.md),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 16,
                                color: c.accentInk,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  pct >= 1.0
                                      ? 'Llegaste al límite de capacidad. Considerá frenar nuevos ingresos.'
                                      : 'Cerca del límite de capacidad. Considerá acelerar adopciones.',
                                  style: SpText.caption.copyWith(
                                    color: c.onPrimary,
                                    fontWeight: FontWeight.w700,
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
              // Huellitas blancas translúcidas dentro del héroe.
              Positioned(
                left: 170,
                top: 70,
                child: SpPaw(
                  size: 30,
                  angle: -35,
                  color: SpDeco.shine.withValues(alpha: .34),
                ),
              ),
              Positioned(
                left: 210,
                top: 46,
                child: SpPaw(
                  size: 26,
                  angle: -25,
                  color: SpDeco.shine.withValues(alpha: .34),
                ),
              ),
              // Los tres animalitos 3D, asomándose por arriba del héroe.
              const Positioned(
                right: 4,
                top: -34,
                width: 168,
                height: 128,
                child: Stack(
                  children: [
                    Positioned(
                      left: 92,
                      top: 0,
                      child: SpAnimal(SpAnimalKind.conejo, size: 66),
                    ),
                    Positioned(
                      left: 6,
                      top: 30,
                      child: SpAnimal(SpAnimalKind.gato, size: 78),
                    ),
                    Positioned(
                      left: 62,
                      top: 40,
                      child: SpAnimal(SpAnimalKind.perro, size: 84),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Mini cifras ──────────────────────────────────────────────────────
          const SizedBox(height: 20),
          Row(
            children: [
              // El MISMO número que "N patitas en cuidado" de arriba (en
              // cuidado + en proceso de adopción). Antes mostraba solo
              // Rescatado/Regresado y el panel decía 6 arriba y 5 abajo
              // (pedido de Eliza: "realmente en cuidado son 6"). Por eso abre
              // La Jauría completa y no el filtro "En cuidado", que cuenta 5.
              Expanded(
                child: SpMiniStat(
                  tone: SpTone.mint,
                  animal: SpAnimalKind.huella,
                  value: totalActivos == null
                      ? _cargandoValor
                      : '$totalActivos',
                  label: 'En cuidado',
                  onTap: () => _irA(AlbergueTab.jauria),
                ),
              ),
              const SizedBox(width: SpSpace.s3),
              _statCard(
                ctx,
                adoptados == null ? _cargandoValor : '$adoptados',
                'Adoptados',
                SpTone.butter,
                SpAnimalKind.casa,
                'Adoptado',
              ),
              const SizedBox(width: SpSpace.s3),
              // Mismo `_pendientes` que la píldora de Solicitudes (ver su doc).
              _statCard(
                ctx,
                _pendientes == null ? _cargandoValor : '$_pendientes',
                'Solicitudes',
                SpTone.lilac,
                SpAnimalKind.gato,
                null,
              ),
            ],
          ),

          // ── Agregar animales ─────────────────────────────────────────────────
          const SizedBox(height: SpSpace.s6),
          _sectionHeader('Agregar animales'),
          const SizedBox(height: SpSpace.s3),
          Row(
            children: [
              Expanded(child: _subirLoteCard(ctx)),
              const SizedBox(width: SpSpace.s3),
              Expanded(child: _subirUnoCard(ctx)),
            ],
          ),

          // ── Solicitudes ──────────────────────────────────────────────────────
          const SizedBox(height: SpSpace.s6),
          // El conteo sale de `_pendientes` (ver su doc), no de un
          // StreamBuilder propio: al volver de otra pestaña este se
          // suscribía tarde y mostraba "Ver todas" con solicitudes nuevas.
          Builder(
            builder: (context) {
              final count = _pendientes ?? 0;
              // Refrescar AL VOLVER, igual que los accesos a "Ver todas".
              // Desde Solicitudes se APRUEBA, y aprobar cambia el estado del
              // animalito (a 'Hogar de paso' o 'En proceso de adopción'). Sin
              // esto el panel volvía con el estado anterior: Eliza aprobó un
              // hogar de paso y la Jauría lo seguía mostrando como Rescatado.
              // El feed del adoptante sí lo veía, porque es un stream en
              // vivo; la Jauría es un .get() que se pidió una sola vez.
              void abrir() => context
                  .push(AppRoutes.solicitudesRescatista, extra: true)
                  .then(_alVolver);
              return _sectionHeader(
                'Solicitudes',
                trailing: count > 0
                    ? SpCountPill(
                        count == 1 ? '1 pendiente' : '$count pendientes',
                        onTap: abrir,
                      )
                    : SpLink('Ver todas', onTap: abrir),
              );
            },
          ),
          const SizedBox(height: SpSpace.s3),
          const SolicitudesPreview(role: CreatorRole.albergue),

          // ── Red de hogares de paso ───────────────────────────────────────────
          const SizedBox(height: SpSpace.s3),
          SpCard(
            padding: const EdgeInsets.all(SpSpace.s3),
            onTap: () => ctx.push(AppRoutes.hogaresDePaso),
            child: Row(
              children: [
                const SpBigTile(tone: SpTone.butter, animal: SpAnimalKind.casa),
                const SizedBox(width: SpSpace.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Red de hogares de paso',
                        style: SpText.headline.copyWith(
                          color: c.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Familias temporales cerca de ti',
                        style: SpText.caption.copyWith(color: c.inkMuted),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c.inkFaint),
              ],
            ),
          ),

          // ── Jauría ───────────────────────────────────────────────────────────
          const SizedBox(height: SpSpace.s6),
          _sectionHeader(
            'La Jauría',
            // Refrescar AL VOLVER, igual que home_screen.dart hace con este
            // mismo destino.
            //
            // "Gestionar" lleva a mis_rescates_screen, y desde ahí se puede
            // cambiar el estado de un animalito (esa pantalla abre su propia
            // CambiarEstadoSheet). Al volver, este panel no se reconstruye:
            // su State sigue vivo debajo, con `_jauria`, `_adoptadosCache` y
            // `_numeros` congelados en lo que cargó `initState`. Resultado:
            // adoptabas desde ahí y el animalito no aparecía en "Encontraron
            // hogar", ni se movían los números de arriba, por el resto de la
            // sesión. Hallazgo de Eliza.
            trailing: SpLink(
              'Gestionar',
              onTap: () => context
                  .push(
                    AppRoutes.misRescates,
                    extra: (filtroInicial: null, esAlbergue: true),
                  )
                  .then(_alVolver),
            ),
          ),
          const SizedBox(height: SpSpace.s3),
          FutureBuilder<PaginaDeRescates>(
            future: _jauria,
            builder: (_, snap) {
              // Mientras carga NO se afirma que no hay animalitos.
              //
              // Sin esta rama, `snap.data` es null durante la espera, la
              // lista llega vacía y _jauriaCarousel muestra "Aún no tienes
              // animales publicados" con su botón de publicar el primero — a
              // un albergue con 66. Se veía al volver de "Gestionar":
              // `_refrescarNumeros()` reemplaza `_jauria`, el FutureBuilder
              // vuelve a `waiting` y aparecía ese cartel hasta que llegaba la
              // respuesta. Decir "no hay" cuando la verdad es "todavía no sé".
              //
              // La altura es la del carrusel para que la pantalla no salte al
              // reemplazarlo.
              if (snap.connectionState == ConnectionState.waiting) {
                return SizedBox(
                  height: _altoCarruselJauria,
                  child: Center(
                    child: CircularProgressIndicator(color: c.primary),
                  ),
                );
              }
              return _jauriaCarousel([...?snap.data?.docs]);
            },
          ),

          // ── Ya encontraron hogar ─────────────────────────────────────────────
          Builder(
            builder: (_) {
              final adoptadosDocs = _adoptadosCache;
              if (adoptadosDocs.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: SpSpace.s6),
                  _sectionHeader(
                    'Encontraron hogar',
                    // "Gestionar" (no "Ver todos"): la fila de abajo YA
                    // muestra todos los adoptados sin límite; lo que este
                    // enlace ofrece es ir a editar/compartir/eliminar,
                    // acciones que la tarjeta chica del carrusel no tiene
                    // (sugerencia real de Eliza).
                    trailing: SpLink(
                      'Gestionar',
                      // Mismo motivo que en la cabecera de La Jauría.
                      onTap: () => ctx
                          .push(
                            AppRoutes.misRescates,
                            extra: (
                              filtroInicial: 'Adoptado',
                              esAlbergue: true,
                            ),
                          )
                          .then(_alVolver),
                    ),
                  ),
                  const SizedBox(height: SpSpace.s3),
                  _adoptadosCarousel(adoptadosDocs),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  TextStyle _heroMeta(SpColors c) =>
      SpText.label.copyWith(color: c.onPrimary, fontWeight: FontWeight.w700);

  /// Barra de capacidad hundida con relleno blanco (`.sp-progress`). Pasa a
  /// coral desde el 90%, el mismo umbral que antes la ponía roja.
  Widget _barraCapacidad(SpColors c, double pct) => Container(
    height: 14,
    decoration: BoxDecoration(
      color: c.onPrimary.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(SpRadius.full),
    ),
    alignment: Alignment.centerLeft,
    child: FractionallySizedBox(
      widthFactor: pct < .04 ? .04 : pct,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: pct >= 0.9
                ? [c.accentSoft, c.accent]
                : [SpDeco.shine, c.mintLight],
          ),
          borderRadius: BorderRadius.circular(SpRadius.full),
        ),
      ),
    ),
  );

  // ── Perfil tab ───────────────────────────────────────────────────────────────

  Widget _perfilTab(
    BuildContext ctx,
    String nombre,
    String tipo,
    String ciudad,
    String iniciales,
    String? fotoBase64,
    int? enCuidado,
    int? enAdopcion,
    int? adoptados,
    int umbralDias,
  ) {
    final c = ctx.sp;
    final user = FirebaseAuth.instance.currentUser;
    return SingleChildScrollView(
      key: const PageStorageKey('perfil'),
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SpScreenHeader(
            title: 'Perfil',
            subtitle: 'Tu cuenta',
            conVolver: false,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Foto, nombre, tipo y ciudad (`.hero2`) ───────────────────────
                Center(
                  child: GestureDetector(
                    onTap: _uploadFotoPerfil,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: SpDeco.soft(c, radius: SpRadius.full),
                          child: AvatarPersona(
                            fotoBase64: fotoBase64,
                            fotoUrl: user?.photoURL,
                            inicial: iniciales,
                            radius: 58,
                            backgroundColor: c.mint,
                            textColor: c.primaryStrong,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 2,
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: SpDeco.primary(
                              c,
                              radius: SpRadius.full,
                            ),
                            child: Icon(
                              Icons.photo_camera_rounded,
                              size: 18,
                              color: c.onPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    nombre,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      color: c.ink,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                if (tipo.isNotEmpty || ciudad.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (tipo.isNotEmpty)
                          _perfilChip(Icons.home_work_outlined, tipo),
                        if (ciudad.isNotEmpty)
                          _perfilChip(Icons.place_outlined, ciudad),
                      ],
                    ),
                  ),
                ],

                // Sin las mini cifras del prototipo: son las mismas del Panel, a
                // un toque, y repetirlas solo alargaba el Perfil (pedido de Eliza).
                // ── Cuenta ───────────────────────────────────────────────────────
                const SizedBox(height: SpSpace.s6),
                _sectionHeader('Cuenta'),
                const SizedBox(height: SpSpace.s3),
                // "Apariencia" ya está, pero por ahora solo deja elegir Claro:
                // el modo oscuro se habilita cuando esté revisado (ver
                // widgets/apariencia_sheet.dart).
                SpCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      _perfilFila(
                        Icons.email_outlined,
                        user?.email ?? '-',
                        etiqueta: 'Correo',
                      ),
                      _perfilDivisor(),
                      _perfilFila(
                        Icons.edit_outlined,
                        'Editar perfil del albergue',
                        onTap: () => ctx.push(AppRoutes.alberguePerfil),
                      ),
                      _perfilDivisor(),
                      _perfilFila(
                        Icons.schedule_rounded,
                        'Aviso sin adoptar',
                        sub: 'Recordatorio a los $umbralDias días',
                        tono: SpTone.peach,
                        onTap: () => _configurarUmbralEstancado(ctx),
                      ),
                      _perfilDivisor(),
                      _perfilFila(
                        Icons.dark_mode_outlined,
                        'Apariencia',
                        sub: Apariencia.etiqueta,
                        tono: SpTone.lilac,
                        onTap: () => mostrarApariencia(ctx),
                      ),
                      _perfilDivisor(),
                      _perfilFila(
                        Icons.shield_outlined,
                        'Política de privacidad',
                        tono: SpTone.sky,
                        onTap: () => launchUrl(
                          Uri.parse(
                            'https://lunita486.github.io/Salva-Patitas/privacidad.html',
                          ),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                    ],
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
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: SpButton(
                    label: 'Cerrar sesión',
                    icon: Icons.logout_rounded,
                    suave: true,
                    onTap: () => mostrarDialogoCerrarSesion(ctx),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: TextButton(
                    onPressed: () => mostrarEliminarCuentaDialog(ctx),
                    style: TextButton.styleFrom(foregroundColor: c.danger),
                    child: const Text(
                      'Eliminar cuenta',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SpPaw(size: 14, angle: -12, color: c.mintDeep),
                      const SizedBox(width: 6),
                      Text(
                        'Salva Patitas',
                        style: SpText.caption.copyWith(
                          color: c.inkFaint,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Tipo o ciudad del albergue (`.sp-chip`), debajo del nombre.
  Widget _perfilChip(IconData icono, String texto) {
    final c = context.sp;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: SpDeco.soft(c, radius: SpRadius.full),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 16, color: c.primary),
          const SizedBox(width: 6),
          Text(
            texto,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c.inkMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _perfilDivisor() => const SpDivisorFilas();

  /// Una fila de la tarjeta "Cuenta" (SpFilaCuenta, compartida con el
  /// Perfil del adoptante). Con [onTap] lleva chevron; sin él es solo
  /// informativa (el correo).
  Widget _perfilFila(
    IconData icono,
    String texto, {
    String? etiqueta,
    String? sub,
    SpTone tono = SpTone.mint,
    VoidCallback? onTap,
  }) => SpFilaCuenta(
    icono: icono,
    texto: texto,
    etiqueta: etiqueta,
    sub: sub,
    tono: tono,
    onTap: onTap,
  );

  // ── Widgets ──────────────────────────────────────────────────────────────────

  Widget _statCard(
    BuildContext ctx,
    String valor,
    String label,
    SpTone tono,
    SpAnimalKind animal,
    String? filtro,
  ) {
    return Expanded(
      child: SpMiniStat(
        tone: tono,
        animal: animal,
        value: valor,
        label: label,
        // Las mini cifras también llevan a "Ver todas", filtradas. Mismo
        // motivo que en la cabecera de La Jauría: sin el `.then`, Adoptados
        // se quedaba con el número viejo después de adoptar desde esa
        // pantalla.
        onTap: () => filtro != null
            ? ctx
                  .push(
                    AppRoutes.misRescates,
                    extra: (filtroInicial: filtro, esAlbergue: true),
                  )
                  .then(_alVolver)
            // Mismo motivo que la cabecera de Solicitudes.
            : ctx
                  .push(AppRoutes.solicitudesRescatista, extra: true)
                  .then(_alVolver),
      ),
    );
  }

  Widget _subirLoteCard(BuildContext ctx) => SpActionTile(
    tone: SpTone.peach,
    title: 'Subir lote',
    subtitle: 'Varios a la vez',
    art: const Stack(
      children: [
        Positioned(
          left: 58,
          top: -2,
          child: SpAnimal(SpAnimalKind.conejo, size: 50),
        ),
        Positioned(
          left: -4,
          top: 16,
          child: SpAnimal(SpAnimalKind.gato, size: 58),
        ),
        Positioned(
          left: 40,
          top: 20,
          child: SpAnimal(SpAnimalKind.perro, size: 62),
        ),
      ],
    ),
    // Al volver se refresca la Jauría: el panel la pide una sola vez, y sin
    // esto lo recién subido no aparecía hasta pasar por "Gestionar".
    onTap: () => ctx.push(AppRoutes.subirLote).then(_alVolver),
  );

  Widget _subirUnoCard(BuildContext ctx) {
    final c = ctx.sp;
    return SpActionTile(
      tone: SpTone.lilac,
      title: 'Subir uno',
      subtitle: 'Paso a paso',
      // El "+" verde 3D girado del prototipo (`.sp-plus3d`).
      art: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 6, top: 6),
          child: Transform.rotate(
            angle: -0.14,
            child: Container(
              width: 60,
              height: 60,
              decoration: SpDeco.primary(c, radius: 20, gradient: true),
              child: Icon(Icons.add_rounded, size: 34, color: c.onPrimary),
            ),
          ),
        ),
      ),
      onTap: () =>
          ctx.push(AppRoutes.subirRescate, extra: true).then(_alVolver),
    );
  }

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
              height: 30,
              decoration: SpDeco.primary(ctx.sp, radius: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 13,
                    color: ctx.sp.onPrimary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Contactar',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: ctx.sp.onPrimary,
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

  Widget _sectionHeader(String label, {Widget? trailing}) =>
      SpSectionTitle(label, trailing: trailing);

  Widget _jauriaCarousel(List<QueryDocumentSnapshot> rescates) {
    if (rescates.isEmpty) {
      return SpEmpty(
        title: 'Aún no tienes animales publicados',
        animal: SpAnimalKind.perro,
        action: SpButton(
          label: 'Publicar el primero',
          icon: Icons.add_rounded,
          compacto: true,
          onTap: () =>
              context.push(AppRoutes.subirRescate, extra: true).then(_alVolver),
        ),
      );
    }
    // SIN re-ordenar acá: quien llama (más arriba, "── Jauría ──") ya deja
    // `rescates` ordenado por prioridad de estado (en proceso de adopción →
    // hogar de paso → rescatado → fallecido) con empate por fecha. Antes
    // este widget volvía a ordenar TODO de nuevo, solo por fecha —
    // pisando ese orden en silencio. Hallazgo real de Eliza: "no está
    // organizado la jauría como en el rescatista".
    final sorted = rescates;

    return SizedBox(
      height: _altoCarruselJauria,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: sorted.length,
        separatorBuilder: (_, _) => const SizedBox(width: SpSpace.s3),
        itemBuilder: (ctx, i) =>
            _tarjetaCarrusel(ctx, sorted[i], deLaJauria: true),
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
      height: 214,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: sorted.length,
        separatorBuilder: (_, _) => const SizedBox(width: SpSpace.s3),
        itemBuilder: (ctx, i) =>
            _tarjetaCarrusel(ctx, sorted[i], deLaJauria: false),
      ),
    );
  }

  /// Tarjeta de un animalito en los carruseles del panel (`.sp-pet2`).
  /// La de "Encontraron hogar" ([deLaJauria] = false) no lleva edad, fecha
  /// ni insignias, y su estado se puede tocar siempre.
  Widget _tarjetaCarrusel(
    BuildContext ctx,
    QueryDocumentSnapshot doc, {
    required bool deLaJauria,
  }) {
    final c = ctx.sp;
    final d = doc.data() as Map<String, dynamic>;
    final docId = doc.id;
    final nombre = nombreDeAnimal(d['nombre'] as String?);
    final especie = d['especie'] as String? ?? 'Perro';
    final edad = d['edad'] as String? ?? '';
    final fotoUrl = d['fotoUrl'] as String?;
    final estadoAdopcion =
        d['estadoAdopcion'] as String? ??
        (deLaJauria ? 'Rescatado' : 'Adoptado');
    final ts = d['creadoEn'] as Timestamp?;
    final urgencia = d['urgencia'] as String? ?? '';
    final esNuevo =
        ts != null && DateTime.now().difference(ts.toDate()).inHours < 24;
    // El año solo se agrega cuando DIFIERE del actual — mismo criterio que
    // mis_rescates_screen.dart y chat_screen.dart. Sin esto, un animal de
    // hace más de un año se ve indistinguible de uno de ayer. Hallazgo real
    // de Eliza, probando ya entrado 2027.
    final fechaStr = ts != null
        ? formatearFecha(
            ts.toDate(),
            conAnio: ts.toDate().year != DateTime.now().year,
          )
        : '';
    // En la Jauría, Fallecido no se puede cambiar. En "Encontraron hogar"
    // sí siempre: si un adoptado era devuelto, no había forma de cambiarle
    // el estado desde el panel (había que ir a "Gestionar").
    final sePuedeCambiar = !deLaJauria || estadoAdopcion != 'Fallecido';

    return Container(
      // Sin esto, aprobar una solicitud (o cualquier cambio que mueva a este
      // animal de posición dentro del orden por prioridad) hacía que Flutter
      // reutilizara por POSICIÓN la tarjeta de otro animal para este lugar —
      // la foto vieja se veía un instante, un parpadeo. Mismo arreglo que
      // home_screen.dart:_misRescatesCarousel. Hallazgo real de Eliza.
      key: ValueKey(docId),
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
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // FotoAnimal en vez de recorte — mismo caso "Tobyiii" que
                  // el feed del adoptante: el recorte fijo podía dejar
                  // afuera al animal entero en fotos verticales.
                  if (fotoUrl != null)
                    FotoAnimal(
                      url: fotoUrl,
                      width: double.infinity,
                      fallback: SpFotoVacia(especie: especie),
                    )
                  else
                    SpFotoVacia(especie: especie),
                  if (deLaJauria && urgencia == 'Alta')
                    const Positioned(
                      top: 8,
                      left: 8,
                      child: SpBadge('Urgente'),
                    ),
                  if (deLaJauria && esNuevo)
                    const Positioned(top: 8, right: 8, child: SpBadge('Nuevo')),
                ],
              ),
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
          if (deLaJauria)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
              child: Text(
                [
                  if (edad.isNotEmpty) edad,
                  if (fechaStr.isNotEmpty) fechaStr,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SpText.caption.copyWith(color: c.inkMuted),
              ),
            ),
          const SizedBox(height: SpSpace.s2),
          // Semantics explícito — hallazgo de auditoría de código (mismo
          // arreglo que en mis_rescates_screen.dart).
          Semantics(
            button: sePuedeCambiar,
            label: sePuedeCambiar
                ? 'Cambiar estado, actualmente $estadoAdopcion'
                : 'Estado: $estadoAdopcion',
            child: SpStatus(
              estadoAdopcion,
              height: 30,
              onTap: !sePuedeCambiar
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
                            d['adoptanteIdEnProceso'] as String?,
                        esAlbergue: true,
                      ),
                    ).then(_alVolver),
            ),
          ),
          // Antes el albergue no tenía NINGUNA forma de contactar a quien
          // tiene el animal en "Hogar de paso" o "En proceso de adopción" —
          // este botón solo existía en el panel del rescatista.
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
    );
  }

  // ── Barra de abajo ───────────────────────────────────────────────────────

  /// Al volver de cualquier pantalla abierta desde el Panel: refresca los
  /// números (el panel los pide con .get(), una sola vez) y, si la persona
  /// tocó otra pestaña en la barra de esa pantalla, la abre (ver
  /// AlbergueTabBar.volverAlPanel).
  void _alVolver(Object? resultado) {
    _refrescarNumeros();
    if (resultado is AlbergueTab && mounted) _irA(resultado);
  }

  void _irA(AlbergueTab t) {
    switch (t) {
      case AlbergueTab.panel:
        setState(() => _nav = 0);
      // 'Perfil' es una pestaña de esta misma pantalla, no una ruta.
      case AlbergueTab.perfil:
        setState(() => _nav = 3);
      case AlbergueTab.jauria:
        context
            .push(
              AppRoutes.misRescates,
              extra: (filtroInicial: null, esAlbergue: true),
            )
            .then(_alVolver);
      case AlbergueTab.solicitudes:
        context
            .push(AppRoutes.solicitudesRescatista, extra: true)
            .then(_alVolver);
      // Chats y Negocios no cambian números del panel: solo se mira si al
      // volver hay que abrir otra pestaña.
      case AlbergueTab.chats:
        context
            .push(
              AppRoutes.adoptanteChats,
              extra: (
                esRescatista: true,
                soloConsultas: false,
                esAlbergue: true,
              ),
            )
            .then(_siOtraPestana);
      case AlbergueTab.negocios:
        context
            .push(
              AppRoutes.aliados,
              extra: (esRescatista: true, esAlbergue: true),
            )
            .then(_siOtraPestana);
    }
  }

  void _siOtraPestana(Object? resultado) {
    if (resultado is AlbergueTab && mounted) _irA(resultado);
  }
}
