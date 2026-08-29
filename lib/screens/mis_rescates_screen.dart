import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../routing/app_router.dart';
import '../theme.dart';
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
            setState(
              () => _nuevos = snap.docs.take(_maxNuevos).toList(),
            );
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
    final cursor = (anterior == null || anterior.isEmpty) ? null : anterior.last;
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
            creadoAntesDe: filtro.antesDe == null || filtro.antesDe!.isAfter(_t0)
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
              final llena = snap.docs.length > RescatesRepository.paginaRescatesSize;
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
        const SnackBar(
          content: Text(
            'No pudimos verificar si se puede eliminar. Revisá tu conexión e intentá de nuevo.',
          ),
          backgroundColor: msgError,
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
          content: Text('Eliminando a ${nombreDeAnimal(nombre, enFrase: true)}…'),
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
          const SnackBar(
            content: Text('Publicación eliminada'),
            backgroundColor: msgExito,
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
          const SnackBar(
            content: Text('Publicación eliminada'),
            backgroundColor: msgExito,
          ),
        );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(RescatesRepository.mensajeErrorEliminar(e)),
            backgroundColor: msgError,
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
      backgroundColor: appBg,
      body: Stack(
        children: [
          Positioned.fill(child: Container(color: appBg)),
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

  Widget _header(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
    child: Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          tooltip: 'Volver',
          onPressed: () => Navigator.pop(context),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.esAlbergue ? 'Mis animales' : 'Mis rescates',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: appInk,
                  fontFamily: 'Baloo2',
                ),
              ),
              if (widget.esAlbergue && _filtroEstado != null)
                Text(
                  _filtroEstado!,
                  style: TextStyle(
                    fontSize: 12,
                    color: cicloColor(_filtroEstado!),
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  // Chips de estado: rescatista siempre, albergue solo sin filtroInicial.
  // Devuelve una lista (0 o 2 widgets) para poder seguir usando el spread
  // `...` en build() tal cual estaba el `if` original.
  List<Widget> _seccionChipsEstado() {
    if (widget.esAlbergue && widget.filtroInicial != null) return const [];
    return [
      SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
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
      const SizedBox(height: 6),
    ];
  }

  // Chips de especie — sin su propio chip "Todos": ya está el
  // de arriba (chips de estado) y tener dos con el mismo texto
  // se veía como un error visual, uno encima del otro (lo que
  // notó Eliza). Para volver a "todas las especies" alcanza con
  // tocar de nuevo la especie ya activa — _chip() ya soporta
  // ese toggle.
  Widget _chipsEspecie() => SizedBox(
    height: 36,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
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
              small: true,
            ),
          )
          .toList(),
    ),
  );

  Widget _listaAnimales(BuildContext context) {
    if (_errorCarga != null && _docs.isEmpty) return errorFeedState();
    if (!_primeraLlego) {
      return const Center(child: CircularProgressIndicator(color: appTeal));
    }
    if (_docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🐾', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(
              _filtroEstado == null
                  ? 'Aún no has publicado rescates'
                  : 'No hay animales en estado "$_filtroEstado"',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      // Una fila más al final SOLO mientras quede algo por traer: es el
      // indicador de que se está cargando la página siguiente.
      itemCount: _docs.length + (_hayMas ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        if (i >= _docs.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator(color: appTeal)),
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
    final colorEstancado =
        esEstancadoGrave(diasEsperando: diasEsperando, umbral: _umbralEstancado)
        ? const Color(0xFFD32F2F)
        : appOrange;
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
    final emoji = especie == 'Gato' ? '🐱' : '🐶';
    final urgColor = urgencia == 'Alta'
        ? const Color(0xFFD32F2F)
        : urgencia == 'Media'
        ? const Color(0xFFE65100)
        : appTeal;

    return Container(
      key: ValueKey(docId),
      padding: const EdgeInsets.all(16),
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
          Row(
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
                  borderRadius: BorderRadius.circular(12),
                  // FotoAnimal en vez de recorte — mismo motivo
                  // y misma técnica que la tarjeta de "tus
                  // animales" en home_screen.dart: el recorte
                  // fijo (topCenter) cortaba animales que no
                  // quedan cerca del borde superior de la
                  // foto, mostrando solo fondo acá en la lista
                  // aunque la foto se viera completa en el
                  // resto de la app (bug real reportado por
                  // Eliza probando con "Chanchis").
                  child: fotoUrl != null
                      ? FotoAnimal(
                          url: fotoUrl,
                          width: 64,
                          height: 64,
                          // Miniatura de lista: sin fondo borroso, ver FotoAnimal.
                          fondoBorroso: false,
                          fallback: Container(
                            width: 64,
                            height: 64,
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
                          width: 64,
                          height: 64,
                          color: const Color(0xFFD8F0E4),
                          child: Center(
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 32),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$especie · $estado',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    // Ciudad reemplazada por la fecha acá — la ciudad ya no
                    // se mostraba para albergue (siempre la misma, heredada
                    // del perfil, ver el comentario de `esDeAlbergue` más
                    // arriba) y para un rescatista individual pasa casi lo
                    // mismo en la práctica: la ubicación que se guarda al
                    // publicar es "CIUDAD" (nivel ciudad, no una dirección
                    // puntual del rescate), y quien la escribe casi siempre
                    // pone la suya propia — se repite tarjeta tras tarjeta
                    // sin sumar nada nuevo. La fecha, en cambio, es distinta
                    // en cada animal y sí ayuda de un vistazo (¿hace cuánto
                    // que espera?). Pedido real de Eliza.
                    if (creadoEnFecha != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 12,
                            color: appTeal,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${esDeAlbergue ? 'Ingresó' : 'Rescatado'} el '
                            // Sin esto, un animal rescatado el año pasado se
                            // vería "18 ago" en pleno 2027 — indistinguible
                            // de uno rescatado ayer. Mismo criterio que
                            // chat_screen.dart: el año solo se agrega cuando
                            // DIFIERE del actual. Hallazgo real de Eliza.
                            '${formatearFecha(
                              creadoEnFecha,
                              conAnio: creadoEnFecha.year != DateTime.now().year,
                            )}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: urgColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  urgencia,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: urgColor,
                  ),
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
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorEstancado.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: colorEstancado.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.schedule, size: 14, color: colorEstancado),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Lleva $diasEsperando días esperando un hogar',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colorEstancado,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => compartirAnimal(
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
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.share_outlined,
                          size: 13,
                          color: colorEstancado,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Compartir en redes',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: colorEstancado,
                          ),
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
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFD32F2F).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 14,
                    color: Color(0xFFD32F2F),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Motivo: $motivoRegreso',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFD32F2F),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (estadoAdopcion == 'Hogar de paso' && fechaFinHogar != null)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: appTeal.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: appTeal.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Quién lo tiene, cuando es un hogar de paso puesto a
                  // mano: esa persona no tiene cuenta en la app, así que
                  // este texto es la única forma de saber a quién buscar.
                  if (((d['hogarDePasoNombre'] as String?) ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: TextoSinDesborde(
                        texto:
                            '🏡 Con ${d['hogarDePasoNombre']}'
                            '${((d['hogarDePasoContacto'] as String?) ?? '').isNotEmpty ? ' · ${d['hogarDePasoContacto']}' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (fechaInicioHogar != null)
                    Text(
                      '📅 ${formatearFecha(fechaInicioHogar)} → ${formatearFecha(fechaFinHogar)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    diasRestantesHogar! < 0
                        ? '⚠️ Período vencido hace ${diasRestantesHogar.abs()} días'
                        : diasRestantesHogar == 0
                        ? '⚠️ El período vence hoy'
                        : '🕐 $diasRestantesHogar días restantes',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: diasRestantesHogar < 3
                          ? const Color(0xFFE65100)
                          : appTeal,
                    ),
                  ),
                ],
              ),
            ),
          // Estado y botones de acción SIEMPRE en dos filas
          // separadas, no un solo Wrap compartido — antes,
          // con "En proceso de adopción" (el texto de
          // estado más largo de todos), la píldora no
          // entraba junto a los botones en el ancho del
          // teléfono y el Wrap los empujaba solo a ESE
          // estado a una segunda línea — la lista se veía
          // inconsistente, con esa tarjeta "distinta" a las
          // demás. Separarlas siempre hace que todas las
          // tarjetas midan y se vean igual sin importar
          // cuán largo sea el texto del estado.
          // spaceBetween en vez de dejarlas pegadas: con un
          // estado corto ("Hogar de paso") el botón
          // "Contactar" quedaba flotando cerca del centro,
          // y con uno largo ("En proceso de adopción")
          // quedaba pegado al borde derecho de la tarjeta —
          // dos tarjetas contiguas se veían con un layout
          // distinto entre sí. Ahora la píldora de estado
          // siempre queda pegada a la izquierda y
          // "Contactar" siempre pegado a la derecha, sin
          // importar cuán largo sea el texto del estado
          // (sugerencia real de Eliza).
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Semantics explícito: sin esto, un lector de
              // pantalla anunciaba el texto del estado y la
              // flechita como dos piezas sueltas en vez de
              // "botón: cambiar estado, [estado actual]".
              // Hallazgo de auditoría de código.
              Semantics(
                button: estadoAdopcion != 'Fallecido',
                label: estadoAdopcion == 'Fallecido'
                    ? 'Estado: Fallecido'
                    : 'Cambiar estado, actualmente $estadoAdopcion',
                child: GestureDetector(
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
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: cicloColor(estadoAdopcion).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: cicloColor(
                          estadoAdopcion,
                        ).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          estadoAdopcion,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: cicloColor(estadoAdopcion),
                          ),
                        ),
                        if (estadoAdopcion != 'Fallecido') ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.expand_more,
                            size: 14,
                            color: cicloColor(estadoAdopcion),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              // "Contactar" solo si hay alguien realmente en
              // proceso con este animal — antes esta pantalla
              // no tenía NINGUNA forma de escribirle a esa
              // persona (el bug real: Eliza aprobó un hogar
              // de paso y no encontró cómo contactarla, ni
              // acá ni en el panel principal, que además solo
              // habilitaba este botón para "En proceso de
              // adopción" y dejaba "Hogar de paso" afuera).
              if ((estadoAdopcion == 'Hogar de paso' ||
                      estadoAdopcion == 'En proceso de adopción') &&
                  (d['adoptanteIdEnProceso'] as String? ?? '').isNotEmpty)
                Semantics(
                  button: true,
                  label: 'Contactar a quien está en proceso con $nombre',
                  child: GestureDetector(
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
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: appOrange,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 13,
                            color: Colors.white,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'Contactar',
                            style: TextStyle(
                              fontSize: 12,
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
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // El botón no depende de que haya foto: si no
              // la tiene, compartirAnimal() ya cae solo a
              // compartir el texto sin imagen — filtrar acá
              // por fotoUrl != null solo escondía el botón
              // entero sin necesidad (el bug real que
              // reportó Eliza: "el rescatista no tiene forma
              // de compartir", justo en un animal recién
              // publicado sin foto todavía).
              //
              // 'Adoptado' también se excluye: el mensaje
              // que arma compartirAnimal() dice "necesita un
              // hogar, ayudalo a encontrar familia" — para
              // un animal ya adoptado eso es directamente
              // falso, no solo innecesario (sugerencia real
              // de Eliza).
              //
              // Tampoco si ya está "estancado": ese aviso
              // trae su propio botón "Compartir en redes"
              // arriba — mostrar los dos era el mismo botón
              // duplicado en la misma tarjeta (otra sugerencia
              // real de Eliza, la vio en vivo con "Orejas").
              if (estadoAdopcion != 'Fallecido' &&
                  estadoAdopcion != 'Adoptado' &&
                  !estancado)
                Tooltip(
                  message: 'Compartir',
                  child: GestureDetector(
                    onTap: () => compartirAnimal(
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
                      // Mismo ícono que usa el adoptante para compartir
                      // (adoptante_feed_screen.dart) — antes eran dos
                      // íconos de "compartir" distintos para la misma
                      // acción, uno por rol (sugerencia real de Eliza).
                      child: const Icon(
                        Icons.share_outlined,
                        size: 16,
                        color: appTeal,
                      ),
                    ),
                  ),
                ),
              if (estadoAdopcion != 'Adoptado' && estadoAdopcion != 'Fallecido')
                Tooltip(
                  message: 'Editar',
                  child: GestureDetector(
                    onTap: () => context.push(
                      AppRoutes.editarRescate,
                      extra: (docId: docId, data: d),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
              // Un animal 'Adoptado' o 'Fallecido' no se puede eliminar:
              // son el único registro de ese desenlace. Borrarlo
              // perdería para siempre la cuenta de cuántos animalitos
              // se adoptaron o fallecieron (pedido explícito de Eliza).
              // Los demás estados ('Hogar de paso', 'En proceso de
              // adopción', 'Regresado') sí muestran el botón: son
              // reversibles, así que el chequeo de _eliminarImpl los
              // bloquea con una explicación en vez de escondérselos.
              if (estadoAdopcion != 'Adoptado' && estadoAdopcion != 'Fallecido')
                Tooltip(
                  message: 'Eliminar',
                  child: GestureDetector(
                    onTap: () => _eliminar(context, docId, nombre),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFFD32F2F).withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Icon(
                        Icons.delete_outline,
                        size: 16,
                        color: Color(0xFFD32F2F),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(
    String label,
    String? valor,
    String? filtroActivo,
    ValueChanged<String?> onTap, {
    bool small = false,
  }) {
    final activo = filtroActivo == valor;
    final color = valor == null ? appTeal : cicloColor(valor);
    return GestureDetector(
      onTap: () => onTap(activo ? null : valor),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: EdgeInsets.symmetric(
          horizontal: small ? 12 : 14,
          vertical: small ? 5 : 7,
        ),
        decoration: BoxDecoration(
          color: activo ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: activo ? color : Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: small ? 11 : 12,
            fontWeight: FontWeight.w600,
            color: activo ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}
