import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../routing/app_router.dart';
import '../domain/reglas_negocio.dart';
import '../widgets/cambiar_estado_sheet.dart';
import '../widgets/dialogos_eliminar_rescate.dart';
import '../widgets/estado_error_feed.dart';
import '../widgets/fotos.dart';
import '../data/creator_role.dart';
import '../data/rescates_repository.dart';
import '../data/rescate_fotos_repository.dart';
import 'compartir_animal.dart';
import '../widgets/texto_sin_desborde.dart';
import '../widgets/sp_widgets.dart';
import '../theme/salva_patitas_theme.dart';
import 'solicitudes_rescatista_screen.dart' show contactarPersonaEnProceso;

class TodosLosRescatesScreen extends StatefulWidget {
  final String? filtroInicial;
  final bool esAlbergue;
  const TodosLosRescatesScreen({
    super.key,
    this.filtroInicial,
    this.esAlbergue = false,
  });
  @override
  State<TodosLosRescatesScreen> createState() => _TodosLosRescatesScreenState();
}

class _TodosLosRescatesScreenState extends State<TodosLosRescatesScreen> {
  String? _filtroEstado;
  String? _filtroEspecie;
  final _rescatesRepo = RescatesRepository();

  static const _estadosFiltroRescatista = [
    'Rescatado',
    'Hogar de paso',
    'En proceso de adopción',
    'Adoptado',
    'Regresado',
    'Fallecido',
    'Estancados',
  ];

  static const _especiesFiltro = ['Perro', 'Gato', 'Otro'];

  // Umbral de "estancado": a partir de acá se muestra el aviso (naranja),
  // y al doble escala a rojo. Solo aplica a 'Rescatado'/'Hogar de paso' —
  // son los únicos estados donde el animal todavía está esperando
  // encontrar hogar; 'En proceso de adopción' ya tiene a alguien
  // interesado y no necesita más visibilidad.
  //
  // Configurable por perfil (albergue_home_screen.dart /
  // perfil_rescatista_screen.dart), no fijo en 30 — cada organización
  // conoce su propio ritmo de adopciones (pedido de Eliza). Guardado por
  // separado para cada rol (ver umbralEstancadoDe en domain/reglas_negocio.dart) — por
  // eso hace falta widget.esAlbergue acá, para leer el que corresponde a
  // la bandeja que esta pantalla está mostrando. Se carga una sola vez al
  // abrir la pantalla; 30 es el valor por defecto mientras carga o si
  // nunca se configuró.
  int _umbralEstancado = umbralEstancadoDefault;

  // `late final`, no un `.snapshots()` armado dentro de `_listaAnimales()`
  // (que corre en cada build) — mismo patrón, y misma causa, que el
  // parpadeo/desactualización ya arreglado en home_screen.dart,
  // albergue_home_screen.dart, aliado_home_screen.dart, AdoptanteChatsScreen
  // y AliadoPublicoScreen. Acá el síntoma no era el parpadeo sino datos
  // VIEJOS: cualquier rebuild de esta pantalla (tocar un chip de filtro,
  // o el redibujado normal del árbol al volver de Editar) recreaba la
  // query, y StreamBuilder se desuscribe de la anterior y se resuscribe a
  // una NUEVA — el primer snapshot de una suscripción recién armada puede
  // venir de la caché local antes de que llegue el fresco del servidor,
  // así que un vistazo justo en ese instante veía la foto/nombre de antes
  // de guardar. Con una sola suscripción viva desde que se abre la
  // pantalla, no hay resuscripción que pueda mostrar la caché vieja.
  // Hallazgo real de Eliza: cambió la foto y la descripción de un animal
  // como rescatista, volvió a "Mis rescates" y seguía viendo la foto y el
  // nombre viejos — reportado 2-3 veces antes de encontrar esta causa.
  // ── Paginación ────────────────────────────────────────────────────────
  //
  // Antes esto era un stream de la consulta COMPLETA, sin `limit`: abrir la
  // lista descargaba TODOS los animales de la cuenta y los filtros se
  // aplicaban en Dart. Con 1.000 son 1.000 documentos cada vez; con
  // 100.000, cien veces más. La regla es que el total de animales de la
  // cuenta no cambie cuánto trabajo hace el teléfono para mostrar una
  // pantalla.
  //
  // Los filtros van ahora en la CONSULTA. Filtrar en Dart sobre una página
  // daría resultados falsos: si en la primera página no hubiera ningún
  // gato, "Gatos" se vería vacío teniendo cientos más abajo.
  /// Lo que trajo cada página, en orden. Cada una se reemplaza entera cuando
  /// su stream emite: es una foto en vivo de esa ventana.
  final _paginas = <List<QueryDocumentSnapshot<Map<String, dynamic>>>>[];
  final _subsPaginas =
      <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

  /// Si la última página vino llena, puede haber más abajo.
  bool _hayMas = true;

  /// Hay una página abriéndose y todavía no llegó su primer snapshot.
  ///
  /// Sin esto, `_alDesplazar` (que se dispara en CADA evento de scroll,
  /// muchos por segundo) abría una página por evento. Y peor: como
  /// `_abrirPagina` agrega la página vacía sincrónicamente, la llamada
  /// siguiente veía esa vacía, no encontraba cursor y volvía a abrir la
  /// ventana de la página 1. El deduplicado lo tapaba, así que no se veía:
  /// se pagaba en lecturas y en listeners.
  bool _pidiendo = false;

  /// El instante en que se armó la lista. Las páginas históricas piden
  /// `creadoEn <= _t0` y los nuevos `creadoEn > _t0`.
  ///
  /// **Por qué existe.** El orden es descendente, así que un animalito nuevo
  /// entra ARRIBA DE TODO. Sin este corte, correría la ventana de la página
  /// 1 hacia abajo y el último de esa página se caía por el borde: no
  /// quedaba ni en la página 1 (se corrió) ni en la 2 (que empieza después
  /// de él). Desaparecía de la lista hasta recargar.
  ///
  /// Con el ancla, ninguna ventana ya cargada se puede mover: lo nuevo no
  /// entra por ahí, entra por [_subNuevos]. Es la misma propiedad que hace
  /// inmune al feed, que ordena ascendente y por eso recibe lo nuevo al
  /// final.
  DateTime _t0 = DateTime.now();

  /// Los publicados después de [_t0], que van arriba de todo.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _nuevos = const [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subNuevos;

  /// Tope de la consulta de nuevos.
  ///
  /// **Qué pasa al alcanzarlo, explícitamente:** se muestran los 20 MÁS
  /// recientes y los que sobren no aparecen hasta que la lista se rearme
  /// (cambiar un filtro, o salir y volver a entrar). No se recarga sola: una
  /// recarga silenciosa mientras alguien mira la lista le movería todo bajo
  /// el dedo.
  ///
  /// 20 es de sobra para el caso real: hay que publicar más de 20
  /// animalitos, desde otro dispositivo, con esta pantalla abierta.
  static const _maxNuevos = 20;

  /// Hasta que la primera página emite algo, la lista muestra el spinner.
  /// Con streams eso suele durar un instante: Firestore entrega la caché
  /// local antes de ir al servidor.
  bool _primeraLlego = false;
  Object? _errorCarga;
  final _scroll = ScrollController();

  /// Todos los animalitos de las páginas abiertas, en orden y SIN repetidos.
  ///
  /// El deduplicado hace falta de verdad, y acá más que en el feed: la
  /// consulta de cada página es "los 21 que siguen a este cursor", así que
  /// al BORRAR un animalito —y esta pantalla tiene un tacho por tarjeta— esa
  /// consulta se reevalúa sola y completa su ventana con uno más del final,
  /// que es justo el primero de la página siguiente. Sin esto, esa tarjeta
  /// aparecería dos veces.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _docs {
    final vistos = <String>{};
    final todos = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    // Los nuevos van primero: son los más recientes y el orden es
    // descendente. No pueden pisarse con las páginas históricas (una
    // consulta pide `> _t0` y la otra `<= _t0`), pero pasan igual por el
    // deduplicado, que es la red para el caso de los borrados.
    for (final doc in _nuevos) {
      if (vistos.add(doc.id)) todos.add(doc);
    }
    for (final pagina in _paginas) {
      for (final doc in pagina) {
        if (vistos.add(doc.id)) todos.add(doc);
      }
    }
    return todos;
  }

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  CreatorRole get _rol =>
      widget.esAlbergue ? CreatorRole.albergue : CreatorRole.rescatista;

  /// Traduce el filtro de la pantalla a algo que Firestore pueda consultar.
  ///
  /// `cuentaComoEnCuidado` y `esEstancado` (domain/reglas_negocio.dart)
  /// siguen siendo la única fuente de esas dos reglas — acá solo se
  /// traducen a una consulta, y los tests de este archivo comprueban que la
  /// traducción diga lo mismo que la regla.
  ({List<String>? estados, DateTime? antesDe}) get _consultaDelFiltro {
    switch (_filtroEstado) {
      case null:
        return (estados: null, antesDe: null);
      case 'En cuidado':
        return (estados: estadosEnCuidado, antesDe: null);
      case 'Estancados':
        return (
          estados: estadosQuePuedenEstancarse,
          antesDe: DateTime.now().subtract(Duration(days: _umbralEstancado)),
        );
      default:
        return (estados: [_filtroEstado!], antesDe: null);
    }
  }

  /// Vuelve a empezar desde la primera página, cerrando las anteriores. Se
  /// llama al abrir, al cambiar un filtro, y al volver de editar o publicar.
  void _recargar() {
    _cerrarPaginas();
    _paginas.clear();
    _nuevos = const [];
    _hayMas = true;
    _pidiendo = false;
    _primeraLlego = false;
    _errorCarga = null;
    // Ancla nueva en cada rearmado: si no, los "nuevos" de la vez anterior
    // se irían acumulando visita tras visita.
    _t0 = DateTime.now();
    _abrirNuevos();
    _abrirPagina();
  }

  void _cerrarPaginas() {
    for (final sub in _subsPaginas) {
      sub.cancel();
    }
    _subsPaginas.clear();
    _subNuevos?.cancel();
    _subNuevos = null;
  }

  /// Escucha lo publicado DESPUÉS de [_t0]. Ver [_t0] y [_maxNuevos].
  ///
  /// No se abre con el filtro "Estancados": ese ya trae su propio corte por
  /// fecha hacia atrás, y un animalito recién publicado no puede llevar
  /// meses esperando. Sin nada que traer, sería un listener al pedo.
  void _abrirNuevos() {
    final filtro = _consultaDelFiltro;
    if (filtro.antesDe != null) return;
    _subNuevos = _rescatesRepo
        .misRescatesEnVivo(
          uid: _uid,
          role: _rol,
          estados: filtro.estados,
          especie: _filtroEspecie,
          creadoDespuesDe: _t0,
          porPagina: _maxNuevos,
        )
        .listen(
          (snap) {
            if (!mounted) return;
            // La consulta pide _maxNuevos + 1; el sobrante no se muestra.
            setState(() => _nuevos = snap.docs.take(_maxNuevos).toList());
          },
          // Un fallo acá no debe romper la lista histórica, que es lo
          // importante: se queda sin los nuevos y nada más.
          onError: (Object _) {},
        );
  }

  /// Abre la página siguiente. Nunca se adelanta sola: la dispara abrir la
  /// pantalla, cambiar un filtro, o llegar cerca del final desplazándose.
  void _abrirPagina() {
    if (_pidiendo) return;
    if (!_hayMas && _paginas.isNotEmpty) return;
    _pidiendo = true;
    final indice = _paginas.length;
    // El cursor es el último documento de la página anterior, capturado UNA
    // vez acá: startAfterDocument usa los valores que tenía en este momento,
    // así que sigue sirviendo aunque después ese animalito se borre.
    final anterior = _paginas.isEmpty ? null : _paginas.last;
    final cursor = (anterior == null || anterior.isEmpty)
        ? null
        : anterior.last;
    _paginas.add(const []);
    final filtro = _consultaDelFiltro;
    _subsPaginas.add(
      _rescatesRepo
          .misRescatesEnVivo(
            uid: _uid,
            role: _rol,
            estados: filtro.estados,
            especie: _filtroEspecie,
            // El más restrictivo de los dos cortes: el ancla temporal, o el
            // de "Estancados" si está puesto (siempre más viejo que _t0).
            creadoAntesDe:
                filtro.antesDe == null || filtro.antesDe!.isAfter(_t0)
                ? _t0
                : filtro.antesDe,
            despuesDe: cursor,
          )
          .listen(
            (snap) {
              // La página puede haber sido descartada por un _recargar()
              // mientras su primer snapshot venía en camino.
              if (!mounted || indice >= _paginas.length) return;
              // Se pidió una de más solo para saber si hay continuación; esa
              // no se muestra.
              final llena =
                  snap.docs.length > RescatesRepository.paginaRescatesSize;
              setState(() {
                _pidiendo = false;
                _paginas[indice] = llena
                    ? snap.docs
                          .take(RescatesRepository.paginaRescatesSize)
                          .toList()
                    : snap.docs;
                if (indice == _paginas.length - 1) _hayMas = llena;
                _primeraLlego = true;
                _errorCarga = null;
              });
            },
            onError: (Object e) {
              if (!mounted) return;
              setState(() {
                _pidiendo = false;
                _errorCarga = e;
                _primeraLlego = true;
              });
            },
          ),
    );
  }

  void _alDesplazar() {
    if (!_scroll.hasClients || !_hayMas) return;
    final falta = _scroll.position.maxScrollExtent - _scroll.position.pixels;
    // Un poco antes del final para que la siguiente página llegue sin que se
    // note el corte, pero solo porque la persona SE ESTÁ desplazando hacia
    // ahí: nunca se piden páginas que nadie pidió.
    if (falta < 600) _abrirPagina();
  }

  Future<void> _cargarUmbralEstancado() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .get();
    if (!mounted) return;
    setState(
      () => _umbralEstancado = umbralEstancadoDe(
        doc.data(),
        esAlbergue: widget.esAlbergue,
      ),
    );
  }

  int? _diasEsperando(Timestamp? creadoEn) {
    if (creadoEn == null) return null;
    return DateTime.now().difference(creadoEn.toDate()).inDays;
  }

  // Guard de reentrada POR ANIMAL, no global ni con aviso. La historia
  // completa, porque este guard ya pasó por tres formas:
  //
  // 1. Sin guard: doble toque al mismo tachito apilaba dos diálogos de
  //    "¿estás seguro?" sobre el mismo animal (bug real).
  // 2. Guard global (un bool para toda la pantalla) + aviso de "hay una
  //    eliminación en curso": el flujo de eliminar sigue vivo un rato
  //    DESPUÉS de que la tarjeta ya desapareció (la lista se actualiza
  //    con el borrado local inmediato, pero el await espera la
  //    confirmación del servidor — que tras alternar modo avión puede
  //    demorar varios segundos más). En esa ventana invisible, borrar
  //    OTRO animal — algo perfectamente seguro, son documentos y
  //    carpetas de fotos independientes — chocaba contra el candado de
  //    un borrado que a la vista ya había terminado, y el aviso solo
  //    generaba confusión ("¿cuál eliminación, si ya se borró?") — el
  //    bug real que reportó Eliza, dos veces.
  // 3. Esta forma: un candado por docId. Animales distintos se borran en
  //    paralelo sin mensajes raros; el doble toque al MISMO animal (el
  //    único caso peligroso) se ignora en silencio — no necesita aviso,
  //    porque el primer toque ya está mostrando algo (el diálogo de
  //    confirmación o el "Eliminando a…") un instante después.
  final Set<String> _eliminandoIds = {};

  Future<void> _eliminar(
    BuildContext context,
    String docId,
    String nombre,
  ) async {
    if (!_eliminandoIds.add(docId)) return;
    try {
      await _eliminarImpl(context, docId, nombre);
    } finally {
      _eliminandoIds.remove(docId);
    }
  }

  Future<void> _eliminarImpl(
    BuildContext context,
    String docId,
    String nombre,
  ) async {
    // Los 3 chequeos de elegibilidad (solicitud pendiente, estado actual,
    // tuvo alguna vez una adopción aprobada) viven centralizados en
    // RescatesRepository.bloqueoParaEliminar — antes estaban duplicados
    // acá y en editar_rescate_screen.dart (hallazgo de auditoría de
    // código). Este botón (el tacho en la tarjeta de "Mis animales") es un
    // segundo camino para eliminar que antes llegaba directo a borrar sin
    // este bloqueo — el bug real que reportó Eliza: una solicitud pendiente
    // podía aprobarse después contra un rescate que ya no existía.
    (String, String)? bloqueo;
    try {
      bloqueo = await RescatesRepository().bloqueoParaEliminar(
        rescateId: docId,
        nombre: nombre,
        rescatistaId: FirebaseAuth.instance.currentUser?.uid ?? '',
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No pudimos verificar si se puede eliminar. Revisá tu conexión e intentá de nuevo.',
          ),
          backgroundColor: context.sp.msgError,
        ),
      );
      return;
    }
    if (!context.mounted) return;
    if (bloqueo != null) {
      await mostrarBloqueoEliminarRescate(context, bloqueo);
      return;
    }

    final confirmar = await confirmarEliminarRescate(context, nombre);
    if (!confirmar || !context.mounted) return;
    // Feedback inmediato y persistente: sin señal, entre el timeout de
    // las fotos (10s) y el del documento (12s) pueden pasar ~20 segundos
    // en los que NADA en pantalla indicaba que había un borrado en curso —
    // la tarjeta desaparece recién a mitad de ese proceso y el mensaje
    // final llega al final. Esa ventana muda fue el reporte real de Eliza:
    // "borra sin preguntar y después tira un error". Los desenlaces de
    // abajo lo reemplazan con hideCurrentSnackBar antes de mostrarse.
    //
    // hideCurrentSnackBar también acá: los SnackBar se ENCOLAN, no se
    // pisan — con dos borrados solapados (permitido desde que el guard es
    // por animal), el "Eliminando a…" del segundo esperaría los 30s del
    // primero para recién mostrarse. Siempre gana el evento más reciente.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Eliminando a ${nombreDeAnimal(nombre, enFrase: true)}…',
          ),
          duration: const Duration(seconds: 30),
        ),
      );
    try {
      // Las fotos se borran ANTES que el documento, a propósito:
      // storage.rules verifica el dueño de una foto LEYENDO el documento
      // de rescates — con el documento ya borrado, esa lectura falla y el
      // borrado de fotos era rechazado (permission-denied tragado en
      // silencio): CADA animal eliminado dejaba sus fotos huérfanas
      // pagando almacenamiento para siempre. Best-effort igual (sin señal
      // falla y no importa): lo que no se pueda borrar acá queda huérfano,
      // pero ya no es el caso de SIEMPRE.
      try {
        await RescateFotosRepository()
            .eliminarTodas(docId)
            .timeout(const Duration(seconds: 10));
      } catch (_) {}
      // Con timeout: sin señal, .delete() se encola y su Future no
      // resuelve hasta reconectar — sin límite, este await quedaba colgado
      // para siempre: ni mensaje de éxito ni de error, aunque el animal ya
      // había desaparecido de la lista (el borrado local es inmediato).
      await _rescatesRepo.eliminar(docId).timeout(const Duration(seconds: 12));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Publicación eliminada'),
            backgroundColor: context.sp.msgExito,
          ),
        );
    } on TimeoutException {
      // Timeout ≠ error: sin señal, el borrado queda encolado y Firestore
      // lo aplica solo al reconectar — y la Cloud Function
      // onRescateEliminado (functions/index.js) limpia fotos y favoritos
      // del lado del servidor cuando eso pase, aunque la app esté
      // cerrada. Para la persona ya está borrado (la tarjeta desapareció)
      // y no depende de ella absolutamente nada — acá hubo un tiempo un
      // aviso naranja de "está tardando", y era peor: hacía parecer que
      // algo había salido mal justo cuando todo salió bien (el reporte
      // real de Eliza: "si borra el animalito, ¿para qué saca ese
      // mensaje?"). Mismo desenlace que el camino con señal.
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Publicación eliminada'),
            backgroundColor: context.sp.msgExito,
          ),
        );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(RescatesRepository.mensajeErrorEliminar(e)),
            backgroundColor: context.sp.msgError,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
    }
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_alDesplazar);
    // El filtro inicial va ANTES de _recargar(): la consulta se arma
    // sincrónicamente adentro, así que asignarlo después dejaba la primera
    // página SIN filtrar mientras el chip aparecía seleccionado.
    _filtroEstado = widget.filtroInicial;
    _recargar();
    _cargarUmbralEstancado();
  }

  @override
  void dispose() {
    // Esta pantalla no tenía dispose: el ScrollController quedaba sin
    // liberar. Ahora además hay un listener por página abierta, y hay que
    // cerrarlos TODOS o siguen escuchando Firestore después de salir.
    _cerrarPaginas();
    _pidiendo = false;
    _scroll.dispose();
    super.dispose();
  }

  // El body de build() vivía entero acá (los 3 bloques de arriba: header,
  // chips de estado, chips de especie, más la lista completa) como un solo
  // método de 547 líneas — el más largo de toda la app. Partido en método
  // por sección, sin cambiar NINGUNA línea de lógica (solo se movieron de
  // lugar), para que cada pieza se pueda leer/revisar sola. Hallazgo de
  // auditoría de código.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.sp.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: SpPawBackground()),
          SafeArea(
            child: Column(
              children: [
                _header(context),
                ..._seccionChipsEstado(),
                _chipsEspecie(),
                const SizedBox(height: 8),
                Expanded(child: _listaAnimales(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final c = context.sp;
    final tonoFiltro = _filtroEstado == null
        ? null
        : spToneEstado(_filtroEstado!);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Row(
        children: [
          SpRoundButton(
            icon: Icons.arrow_back_ios_new_rounded,
            tooltip: 'Volver',
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.esAlbergue ? 'La Jauría' : 'Mis rescates',
                  style: SpText.screen.copyWith(color: c.ink),
                ),
                if (widget.esAlbergue && _filtroEstado != null)
                  Text(
                    _filtroEstado!,
                    style: SpText.label.copyWith(
                      color: tonoFiltro == null
                          ? c.inkMuted
                          : SpToneColors.of(c, tonoFiltro).ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          // Huellitas junto al título, como en el prototipo.
          SpPaw(size: 16, angle: 20, color: c.mintDeep),
          const SizedBox(width: 4),
          SpPaw(size: 20, angle: 30, color: c.mint),
        ],
      ),
    );
  }

  // Chips de estado: rescatista siempre, albergue solo sin filtroInicial.
  // Devuelve una lista (0 o 2 widgets) para poder seguir usando el spread
  // `...` en build() tal cual estaba el `if` original.
  List<Widget> _seccionChipsEstado() {
    if (widget.esAlbergue && widget.filtroInicial != null) return const [];
    return [
      SizedBox(
        height: 46,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
          children: [
            // "Todos" limpia los DOS filtros, no solo el de estado
            // (esta fila) — antes solo tocaba _filtroEstado, así
            // que si tenías "Gato" activo en la fila de especie
            // (abajo) y tocabas "Todos" acá arriba, seguías viendo
            // solo gatos: "Todos" no se sentía como "todos" de
            // verdad (reportado por Eliza).
            _chip(
              'Todos',
              null,
              _filtroEstado,
              (v) => setState(() {
                _filtroEstado = v;
                _filtroEspecie = null;
                _recargar();
              }),
            ),
            ..._estadosFiltroRescatista.map(
              (e) => _chip(
                e,
                e,
                _filtroEstado,
                (v) => setState(() {
                  _filtroEstado = v;
                  _recargar();
                }),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 4),
    ];
  }

  // Chips de especie — sin su propio chip "Todos": ya está el
  // de arriba (chips de estado) y tener dos con el mismo texto
  // se veía como un error visual, uno encima del otro (lo que
  // notó Eliza). Para volver a "todas las especies" alcanza con
  // tocar de nuevo la especie ya activa — _chip() ya soporta
  // ese toggle.
  Widget _chipsEspecie() => SizedBox(
    height: 46,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      children: _especiesFiltro
          .map(
            (e) => _chip(
              e,
              e,
              _filtroEspecie,
              (v) => setState(() {
                _filtroEspecie = v;
                _recargar();
              }),
              animal: spEspecie(e).$2,
            ),
          )
          .toList(),
    ),
  );

  Widget _listaAnimales(BuildContext context) {
    if (_errorCarga != null && _docs.isEmpty) return errorFeedState();
    if (!_primeraLlego) {
      return Center(
        child: CircularProgressIndicator(color: context.sp.primary),
      );
    }
    if (_docs.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SpEmpty(
            title: _filtroEstado == null
                ? 'Aún no has publicado rescates'
                : 'No hay animales en estado "$_filtroEstado"',
            animal: SpAnimalKind.perro,
          ),
        ],
      );
    }
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      // Una fila más al final SOLO mientras quede algo por traer: es el
      // indicador de que se está cargando la página siguiente.
      itemCount: _docs.length + (_hayMas ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (_, i) {
        if (i >= _docs.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: CircularProgressIndicator(color: context.sp.primary),
            ),
          );
        }
        return _tarjetaAnimal(context, _docs[i].id, _docs[i].data());
      },
    );
  }

  Widget _tarjetaAnimal(
    BuildContext context,
    String docId,
    Map<String, dynamic> d,
  ) {
    final c = context.sp;
    final nombre = nombreDeAnimal(d['nombre'] as String?);
    final especie = d['especie'] ?? '';
    final estado = d['estado'] ?? '';
    final urgencia = d['urgencia'] ?? '';
    final ubicacion = d['ubicacion'] ?? '';
    // Todos los animales de un mismo albergue comparten la ubicación del
    // perfil del albergue (ver creator_role.dart:esRescateDeAlbergue) — el
    // albergue ya sabe dónde queda su propio refugio, mostrarla repetida en
    // cada tarjeta de "Mis animales" no aporta nada. Pedido real de Eliza.
    final esDeAlbergue = esRescateDeAlbergue(d);
    final fotoUrl = d['fotoUrl'] as String?;
    final fotoUrl2 = d['fotoUrl2'] as String?;
    final estadoAdopcion = d['estadoAdopcion'] as String? ?? 'Rescatado';
    final motivoRegreso = d['motivoRegreso'] as String?;
    final diasEsperando = _diasEsperando(d['creadoEn'] as Timestamp?);
    final creadoEnFecha = (d['creadoEn'] as Timestamp?)?.toDate();
    // esEstancado/esEstancadoGrave (domain/reglas_negocio.dart) — mismo criterio que el
    // filtro "Estancados" de arriba, única fuente para las dos.
    final estancado = esEstancado(
      diasEsperando: diasEsperando,
      estadoAdopcion: estadoAdopcion,
      umbral: _umbralEstancado,
    );
    final grave = esEstancadoGrave(
      diasEsperando: diasEsperando,
      umbral: _umbralEstancado,
    );
    // Pregunta real de Eliza: "tengo 3 animalitos en
    // hogar de paso, ¿cómo veo las fechas en que me los
    // regresan?" — hasta ahora esa fecha solo se veía en
    // "Solicitudes" (mezclada con todas las demás), no
    // acá en la tarjeta del animal, que es donde de
    // verdad se busca de un vistazo.
    final fechaInicioHogar = (d['fechaInicioHogar'] as Timestamp?)?.toDate();
    final fechaFinHogar = (d['fechaFinHogar'] as Timestamp?)?.toDate();
    final hoySinHora = DateTime.now();
    final diasRestantesHogar = fechaFinHogar != null
        ? DateTime(fechaFinHogar.year, fechaFinHogar.month, fechaFinHogar.day)
              .difference(
                DateTime(hoySinHora.year, hoySinHora.month, hoySinHora.day),
              )
              .inDays
        : null;
    final hogarNombre = (d['hogarDePasoNombre'] as String?) ?? '';
    final hogarContacto = (d['hogarDePasoContacto'] as String?) ?? '';
    void compartir() => compartirAnimal(
      context: context,
      nombre: nombre,
      especie: especie,
      edad: d['edad'] as String? ?? '',
      ubicacion: ubicacion,
      tags: <String>[
        if (d['okConNinos'] == true) 'Amigable con niños',
        if (d['okConMascotas'] == true) 'Es sociable',
        if ((d['energia'] as String?)?.isNotEmpty == true)
          d['energia'] as String,
      ],
      fotoUrl: fotoUrl,
      paisCodigo: d['paisCodigo'] as String?,
    );

    return Container(
      key: ValueKey(docId),
      padding: const EdgeInsets.all(12),
      decoration: SpDeco.card(c),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                // Ver ampliada — mismo visor que ya usa el
                // adoptante en el feed y en la ficha del
                // animal (VisorFotoCompleta), ahora también
                // para quien publicó, pedido de Eliza al
                // notar que ahí no existía forma de ver la
                // foto completa desde "Mis rescates".
                onTap: fotoUrl == null
                    ? null
                    : () => context.push(
                        AppRoutes.visorFoto,
                        extra: (
                          fotos: [fotoUrl, if (fotoUrl2 != null) fotoUrl2],
                          indiceInicial: 0,
                        ),
                      ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  // FotoAnimal en vez de recorte — el recorte fijo
                  // (topCenter) cortaba animales que no quedan cerca del
                  // borde superior de la foto (bug real reportado por
                  // Eliza probando con "Chanchis").
                  child: SizedBox(
                    width: 84,
                    height: 84,
                    child: fotoUrl != null
                        ? FotoAnimal(
                            url: fotoUrl,
                            width: 84,
                            height: 84,
                            // Miniatura de lista: sin fondo borroso, ver FotoAnimal.
                            fondoBorroso: false,
                            fallback: SpFotoVacia(especie: especie, size: 60),
                          )
                        : SpFotoVacia(especie: especie, size: 60),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 2),
                    Text(
                      nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$especie · $estado',
                      style: SpText.caption.copyWith(
                        color: c.inkMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    // Ciudad reemplazada por la fecha acá: la ubicación se
                    // repite tarjeta tras tarjeta sin sumar nada nuevo, y la
                    // fecha es distinta en cada animal (¿hace cuánto que
                    // espera?). Pedido real de Eliza.
                    if (creadoEnFecha != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 13,
                            color: c.primary,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${esDeAlbergue ? 'Ingresó' : 'Rescatado'} el '
                              // El año solo se agrega cuando DIFIERE del
                              // actual — mismo criterio que chat_screen.dart.
                              // Hallazgo real de Eliza.
                              '${formatearFecha(creadoEnFecha, conAnio: creadoEnFecha.year != DateTime.now().year)}',
                              style: SpText.caption.copyWith(color: c.inkMuted),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (urgencia != '') ...[
                      const SizedBox(height: 6),
                      urgencia == 'Alta'
                          ? const SpBadge('Prioridad alta')
                          : _pildora(
                              'Prioridad ${urgencia.toString().toLowerCase()}',
                              urgencia == 'Media' ? SpTone.peach : SpTone.mint,
                            ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Aviso de "estancado": lleva mucho tiempo sin
          // encontrar hogar. Trae el botón de compartir
          // metido adentro a propósito — el aviso solo no
          // sirve de nada si después hay que ir a buscar
          // el botón de compartir en otro lado; la acción
          // que resuelve el aviso vive junto al aviso
          // (pedido explícito de Eliza).
          if (estancado)
            SpNotice(
              fondo: grave ? c.dangerSoft : c.accentSoft,
              tinta: grave ? c.danger : c.accentInk,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.schedule_rounded),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Lleva $diasEsperando días esperando un hogar',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: compartir,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.share_outlined, size: 14),
                        SizedBox(width: 5),
                        Text(
                          'Compartir en redes',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (estadoAdopcion == 'Regresado' &&
              motivoRegreso != null &&
              motivoRegreso.isNotEmpty)
            SpNotice(
              fondo: c.dangerSoft,
              tinta: c.danger,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Motivo: $motivoRegreso')),
                ],
              ),
            ),
          if (estadoAdopcion == 'Hogar de paso' && fechaFinHogar != null)
            SpNotice(
              fondo: c.butter,
              tinta: c.butterInk,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Quién lo tiene, cuando es un hogar de paso puesto a
                  // mano: esa persona no tiene cuenta en la app, así que
                  // este texto es la única forma de saber a quién buscar.
                  if (hogarNombre.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.home_outlined),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextoSinDesborde(
                              texto:
                                  'Con $hogarNombre'
                                  '${hogarContacto.isNotEmpty ? ' · $hogarContacto' : ''}',
                              style: TextStyle(
                                fontSize: 12,
                                color: c.butterInk,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (fechaInicioHogar != null)
                    Row(
                      children: [
                        const Icon(Icons.event_outlined),
                        const SizedBox(width: 6),
                        Text(
                          '${formatearFecha(fechaInicioHogar)} → ${formatearFecha(fechaFinHogar)}',
                        ),
                      ],
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        diasRestantesHogar! <= 0
                            ? Icons.warning_amber_rounded
                            : Icons.schedule_rounded,
                        color: diasRestantesHogar < 3 ? c.accentInk : null,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        diasRestantesHogar < 0
                            ? 'Período vencido hace ${diasRestantesHogar.abs()} días'
                            : diasRestantesHogar == 0
                            ? 'El período vence hoy'
                            : '$diasRestantesHogar días restantes',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: diasRestantesHogar < 3 ? c.accentInk : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          // Estado y botones de acción SIEMPRE en dos filas separadas, no un
          // solo Wrap compartido: con "En proceso de adopción" (el estado
          // más largo) la píldora no entraba junto a los botones y esa
          // tarjeta se veía distinta a las demás. La píldora queda a la
          // izquierda y "Contactar" siempre a la derecha (sugerencia real
          // de Eliza).
          Row(
            children: [
              // Semantics explícito: sin esto, un lector de
              // pantalla anunciaba el texto del estado y la
              // flechita como dos piezas sueltas en vez de
              // "botón: cambiar estado, [estado actual]".
              // Hallazgo de auditoría de código.
              Expanded(
                child: Semantics(
                  button: estadoAdopcion != 'Fallecido',
                  label: estadoAdopcion == 'Fallecido'
                      ? 'Estado: Fallecido'
                      : 'Cambiar estado, actualmente $estadoAdopcion',
                  child: SpStatus(
                    estadoAdopcion,
                    onTap: estadoAdopcion == 'Fallecido'
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
                                  d['adoptanteIdEnProceso'] as String?,
                              esAlbergue: widget.esAlbergue,
                            ),
                          ),
                  ),
                ),
              ),
              // "Contactar" solo si hay alguien realmente en
              // proceso con este animal — antes esta pantalla
              // no tenía NINGUNA forma de escribirle a esa
              // persona (el bug real: Eliza aprobó un hogar
              // de paso y no encontró cómo contactarla).
              if ((estadoAdopcion == 'Hogar de paso' ||
                      estadoAdopcion == 'En proceso de adopción') &&
                  (d['adoptanteIdEnProceso'] as String? ?? '').isNotEmpty) ...[
                const SizedBox(width: 8),
                Semantics(
                  button: true,
                  label: 'Contactar a quien está en proceso con $nombre',
                  child: SpButton(
                    label: 'Contactar',
                    icon: Icons.chat_bubble_outline_rounded,
                    compacto: true,
                    onTap: () => contactarPersonaEnProceso(
                      context,
                      docId: docId,
                      nombre: nombre,
                      especie: especie,
                      fotoUrl: fotoUrl,
                      creadoPor: d['creadoPor'] as String?,
                      adoptanteIdEnProceso:
                          d['adoptanteIdEnProceso'] as String? ?? '',
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // El botón no depende de que haya foto: si no
              // la tiene, compartirAnimal() ya cae solo a
              // compartir el texto sin imagen (el bug real que
              // reportó Eliza: "el rescatista no tiene forma
              // de compartir", justo en un animal recién
              // publicado sin foto todavía).
              //
              // 'Adoptado' también se excluye: el mensaje
              // que arma compartirAnimal() dice "necesita un
              // hogar" — para un animal ya adoptado eso es
              // directamente falso (sugerencia real de Eliza).
              //
              // Tampoco si ya está "estancado": ese aviso
              // trae su propio botón "Compartir en redes"
              // arriba — mostrar los dos era el mismo botón
              // duplicado en la misma tarjeta (otra sugerencia
              // real de Eliza, la vio en vivo con "Orejas").
              if (estadoAdopcion != 'Fallecido' &&
                  estadoAdopcion != 'Adoptado' &&
                  !estancado) ...[
                // Mismo ícono que usa el adoptante para compartir
                // (adoptante_feed_screen.dart) (sugerencia real de Eliza).
                SpMiniButton(
                  icon: Icons.share_outlined,
                  tooltip: 'Compartir',
                  onTap: compartir,
                ),
                const SizedBox(width: 6),
              ],
              if (estadoAdopcion != 'Adoptado' &&
                  estadoAdopcion != 'Fallecido') ...[
                SpMiniButton(
                  icon: Icons.edit_outlined,
                  tooltip: 'Editar',
                  onTap: () => context.push(
                    AppRoutes.editarRescate,
                    extra: (docId: docId, data: d),
                  ),
                ),
                const SizedBox(width: 6),
                // Un animal 'Adoptado' o 'Fallecido' no se puede eliminar:
                // son el único registro de ese desenlace (pedido explícito
                // de Eliza). Los demás estados ('Hogar de paso', 'En
                // proceso de adopción', 'Regresado') sí muestran el botón:
                // son reversibles, así que el chequeo de _eliminarImpl los
                // bloquea con una explicación en vez de escondérselos.
                SpMiniButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Eliminar',
                  danger: true,
                  onTap: () => _eliminar(context, docId, nombre),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Píldora pastel chica (`.pill--peach`, etc.).
  Widget _pildora(String texto, SpTone tono) {
    final k = SpToneColors.of(context.sp, tono);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: k.fill,
        borderRadius: BorderRadius.circular(SpRadius.full),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: k.ink,
        ),
      ),
    );
  }

  Widget _chip(
    String label,
    String? valor,
    String? filtroActivo,
    ValueChanged<String?> onTap, {
    SpAnimalKind? animal,
  }) {
    final activo = filtroActivo == valor;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SpChip(
        label: label,
        selected: activo,
        animal: animal,
        onTap: () => onTap(activo ? null : valor),
      ),
    );
  }
}
