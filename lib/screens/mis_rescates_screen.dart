import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import '../data/creator_role.dart';
import '../data/rescates_repository.dart';
import '../data/rescate_fotos_repository.dart';
import 'editar_rescate_screen.dart';
import 'compartir_animal.dart';
import 'visor_foto_completa.dart';
import 'solicitudes_rescatista_screen.dart' show contactarPersonaEnProceso;

class TodosLosRescatesScreen extends StatefulWidget {
  final String? filtroInicial;
  final bool esAlbergue;
  const TodosLosRescatesScreen({super.key, this.filtroInicial, this.esAlbergue = false});
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
  // Configurable por perfil (albergue_perfil_screen.dart /
  // perfil_rescatista_screen.dart), no fijo en 30 — cada organización
  // conoce su propio ritmo de adopciones (pedido de Eliza). Se carga una
  // sola vez al abrir la pantalla; 30 es el valor por defecto mientras
  // carga o si nunca se configuró.
  int _umbralEstancado = umbralEstancadoDefault;

  Future<void> _cargarUmbralEstancado() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
    if (!mounted) return;
    setState(() => _umbralEstancado = umbralEstancadoDe(doc.data()));
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

  Future<void> _eliminar(BuildContext context, String docId, String nombre) async {
    if (!_eliminandoIds.add(docId)) return;
    try {
      await _eliminarImpl(context, docId, nombre);
    } finally {
      _eliminandoIds.remove(docId);
    }
  }

  Future<void> _eliminarImpl(BuildContext context, String docId, String nombre) async {
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No pudimos verificar si se puede eliminar. Revisá tu conexión e intentá de nuevo.'),
          backgroundColor: msgError));
      return;
    }
    if (!context.mounted) return;
    if (bloqueo != null) {
      await showDialog<void>(
        context: context,
        builder: (dlgCtx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(bloqueo!.$1),
          content: Text(bloqueo.$2),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Entendido')),
          ],
        ),
      );
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Eliminar publicación'),
        content: Text('¿Seguro que quieres eliminar a $nombre? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmar != true || !context.mounted) return;
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
      ..showSnackBar(SnackBar(
        content: Text('Eliminando a $nombre…'),
        duration: const Duration(seconds: 30),
      ));
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
        await RescateFotosRepository().eliminarTodas(docId)
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
          const SnackBar(content: Text('Publicación eliminada'), backgroundColor: msgExito));
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
          const SnackBar(content: Text('Publicación eliminada'), backgroundColor: msgExito));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(RescatesRepository.mensajeErrorEliminar(e)),
          backgroundColor: msgError,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ));
    }
  }

  @override
  void initState() {
    super.initState();
    _filtroEstado = widget.filtroInicial;
    _cargarUmbralEstancado();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appBg,
      body: Stack(
        children: [
          Positioned.fill(child: Container(color: appBg)),
          SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
                child: Row(children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                tooltip: 'Volver',
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.esAlbergue ? 'Mis animales' : 'Mis rescates',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: appInk,
                              fontFamily: 'Baloo2')),
                      if (widget.esAlbergue && _filtroEstado != null)
                        Text(_filtroEstado!,
                            style: TextStyle(fontSize: 12, color: cicloColor(_filtroEstado!), fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ]),
              ),
              // Chips de estado: rescatista siempre, albergue solo sin filtroInicial
              if (!widget.esAlbergue || widget.filtroInicial == null) ...[
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _chip('Todos', null, _filtroEstado, (v) => setState(() => _filtroEstado = v)),
                      ..._estadosFiltroRescatista
                          .map((e) => _chip(e, e, _filtroEstado, (v) => setState(() => _filtroEstado = v))),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
              ],
              // Chips de especie — sin su propio chip "Todos": ya está el
              // de arriba (chips de estado) y tener dos con el mismo texto
              // se veía como un error visual, uno encima del otro (lo que
              // notó Eliza). Para volver a "todas las especies" alcanza con
              // tocar de nuevo la especie ya activa — _chip() ya soporta
              // ese toggle.
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: _especiesFiltro.map((e) => _chip(e, e, _filtroEspecie,
                      (v) => setState(() => _filtroEspecie = v), small: true)).toList(),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _rescatesRepo.misRescates(
                    uid: FirebaseAuth.instance.currentUser?.uid ?? '',
                    role: widget.esAlbergue ? CreatorRole.albergue : CreatorRole.rescatista,
                  ),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: appTeal));
                    }
                    if (snap.hasError) return errorFeedState();
                    var allDocs = (snap.data?.docs ?? []).toList()..sort((a, b) {
                      final ta = a.data()['creadoEn'] as Timestamp?;
                      final tb = b.data()['creadoEn'] as Timestamp?;
                      if (ta == null || tb == null) return 0;
                      return tb.compareTo(ta);
                    });
                    if (_filtroEstado != null) {
                      allDocs = allDocs.where((doc) {
                        final data = doc.data();
                        final ea = data['estadoAdopcion'] as String? ?? 'Rescatado';
                        // "En cuidado" = físicamente presente, no "del que
                        // sos responsable" — "Regresado" sí cuenta (volvió
                        // de verdad con vos), "Hogar de paso" no (está en
                        // la casa de otra persona, libera capacidad real).
                        // Mismo criterio que el contador del panel del
                        // albergue, para que el número y esta lista
                        // siempre coincidan (pedido explícito de Eliza).
                        if (_filtroEstado == 'En cuidado') {
                          return ea == 'Rescatado' || ea == 'Regresado';
                        }
                        // 'Estancados' no es un estadoAdopcion real — es un
                        // filtro calculado, mismo umbral que el aviso de la
                        // tarjeta (ver _umbralEstancado).
                        if (_filtroEstado == 'Estancados') {
                          final dias = _diasEsperando(data['creadoEn'] as Timestamp?);
                          return dias != null && dias >= _umbralEstancado &&
                              (ea == 'Rescatado' || ea == 'Hogar de paso' || ea == 'Regresado');
                        }
                        return ea == _filtroEstado;
                      }).toList();
                    }
                    if (_filtroEspecie != null) {
                      allDocs = allDocs.where((doc) {
                        final esp = doc.data()['especie'] as String? ?? '';
                        if (_filtroEspecie == 'Otro') return esp != 'Perro' && esp != 'Gato';
                        return esp == _filtroEspecie;
                      }).toList();
                    }
                    if (allDocs.isEmpty) {
                      return Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Text('🐾', style: TextStyle(fontSize: 48)),
                          const SizedBox(height: 12),
                          Text(
                            _filtroEstado == null
                                ? 'Aún no has publicado rescates'
                                : 'No hay animales en estado "$_filtroEstado"',
                            style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
                            textAlign: TextAlign.center,
                          ),
                        ]),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      itemCount: allDocs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        final d = allDocs[i].data();
                        final docId         = allDocs[i].id;
                        final nombre        = (d['nombre'] as String?)?.isNotEmpty == true ? d['nombre'] : 'Sin nombre';
                        final especie       = d['especie']       ?? '';
                        final estado        = d['estado']        ?? '';
                        final urgencia      = d['urgencia']      ?? '';
                        final ubicacion     = d['ubicacion']     ?? '';
                        final fotoUrl       = d['fotoUrl']       as String?;
                        final fotoUrl2      = d['fotoUrl2']      as String?;
                        final estadoAdopcion= d['estadoAdopcion'] as String? ?? 'Rescatado';
                        final motivoRegreso = d['motivoRegreso']  as String?;
                        final diasEsperando = _diasEsperando(d['creadoEn'] as Timestamp?);
                        // "Regresado" también puede quedar estancado — de
                        // hecho es el caso más urgente: ya falló una vez en
                        // encontrar hogar definitivo. Mismo criterio que el
                        // filtro "En cuidado" de arriba.
                        final estancado = diasEsperando != null &&
                            diasEsperando >= _umbralEstancado &&
                            (estadoAdopcion == 'Rescatado' || estadoAdopcion == 'Hogar de paso' || estadoAdopcion == 'Regresado');
                        final colorEstancado = (diasEsperando ?? 0) >= _umbralEstancado * 2
                            ? const Color(0xFFD32F2F)
                            : appOrange;
                        // Pregunta real de Eliza: "tengo 3 animalitos en
                        // hogar de paso, ¿cómo veo las fechas en que me los
                        // regresan?" — hasta ahora esa fecha solo se veía en
                        // "Solicitudes" (mezclada con todas las demás), no
                        // acá en la tarjeta del animal, que es donde de
                        // verdad se busca de un vistazo.
                        final fechaInicioHogar = (d['fechaInicioHogar'] as Timestamp?)?.toDate();
                        final fechaFinHogar    = (d['fechaFinHogar']    as Timestamp?)?.toDate();
                        final hoySinHora = DateTime.now();
                        final diasRestantesHogar = fechaFinHogar != null
                            ? DateTime(fechaFinHogar.year, fechaFinHogar.month, fechaFinHogar.day)
                                .difference(DateTime(hoySinHora.year, hoySinHora.month, hoySinHora.day))
                                .inDays
                            : null;
                        final emoji = especie == 'Gato' ? '🐱' : '🐶';
                        final urgColor = urgencia == 'Alta'
                            ? const Color(0xFFD32F2F)
                            : urgencia == 'Media' ? const Color(0xFFE65100) : appTeal;

                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              GestureDetector(
                                // Ver ampliada — mismo visor que ya usa el
                                // adoptante en el feed y en la ficha del
                                // animal (VisorFotoCompleta), ahora también
                                // para quien publicó, pedido de Eliza al
                                // notar que ahí no existía forma de ver la
                                // foto completa desde "Mis rescates".
                                onTap: fotoUrl == null ? null : () => Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => VisorFotoCompleta(
                                        fotos: [fotoUrl, if (fotoUrl2 != null) fotoUrl2],
                                        indiceInicial: 0))),
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
                                        width: 64, height: 64,
                                        fallback: Container(width: 64, height: 64,
                                            color: const Color(0xFFD8F0E4),
                                            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 32)))),
                                      )
                                    : Container(width: 64, height: 64,
                                      color: const Color(0xFFD8F0E4),
                                      child: Center(child: Text(emoji, style: const TextStyle(fontSize: 32)))),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 4),
                                Text('$especie · $estado', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                                // El pin solo se muestra si hay ubicación que
                                // mostrar — mismo criterio que el panel del
                                // rescatista en home_screen.dart.
                                if ((ubicacion as String).isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Row(children: [
                                    const Icon(Icons.location_on, size: 13, color: appTeal),
                                    const SizedBox(width: 2),
                                    Text(ubicacion, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                                  ]),
                                ],
                              ])),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(color: urgColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                                child: Text(urgencia, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: urgColor)),
                              ),
                            ]),
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
                                  border: Border.all(color: colorEstancado.withValues(alpha: 0.3)),
                                ),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Icon(Icons.schedule, size: 14, color: colorEstancado),
                                    const SizedBox(width: 6),
                                    Expanded(child: Text('Lleva $diasEsperando días esperando un hogar',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorEstancado))),
                                  ]),
                                  const SizedBox(height: 6),
                                  GestureDetector(
                                    onTap: () => compartirAnimal(
                                      context: context,
                                      nombre: nombre,
                                      especie: especie,
                                      edad: d['edad'] as String? ?? '',
                                      ubicacion: ubicacion,
                                      tags: <String>[
                                        if (d['okConNinos']    == true) 'Amigable con niños',
                                        if (d['okConMascotas'] == true) 'Es sociable',
                                        if ((d['energia'] as String?)?.isNotEmpty == true) d['energia'] as String,
                                      ],
                                      fotoUrl: fotoUrl,
                                    ),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      Icon(Icons.share_outlined, size: 13, color: colorEstancado),
                                      const SizedBox(width: 5),
                                      Text('Compartir en redes',
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colorEstancado)),
                                    ]),
                                  ),
                                ]),
                              ),
                            if (estadoAdopcion == 'Regresado' && motivoRegreso != null && motivoRegreso.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFEBEE),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFD32F2F).withValues(alpha: 0.3)),
                                ),
                                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  const Icon(Icons.info_outline, size: 14, color: Color(0xFFD32F2F)),
                                  const SizedBox(width: 6),
                                  Expanded(child: Text('Motivo: $motivoRegreso',
                                      style: const TextStyle(fontSize: 12, color: Color(0xFFD32F2F)))),
                                ]),
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
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  if (fechaInicioHogar != null)
                                    Text('📅 ${formatearFecha(fechaInicioHogar)} → ${formatearFecha(fechaFinHogar)}',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Text(
                                    diasRestantesHogar! < 0
                                        ? '⚠️ Período vencido hace ${diasRestantesHogar.abs()} días'
                                        : diasRestantesHogar == 0
                                            ? '⚠️ El período vence hoy'
                                            : '🕐 $diasRestantesHogar días restantes',
                                    style: TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.w700,
                                      color: diasRestantesHogar < 3 ? const Color(0xFFE65100) : appTeal,
                                    ),
                                  ),
                                ]),
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
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              GestureDetector(
                                onTap: estadoAdopcion == 'Fallecido' ? null : () => showModalBottomSheet(
                                  context: context,
                                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                                  builder: (_) => CambiarEstadoSheet(
                                    docId: docId,
                                    estadoActual: estadoAdopcion,
                                    nombre: nombre,
                                    adoptanteIdEnProceso: d['adoptanteIdEnProceso'] as String?,
                                  ),
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: cicloColor(estadoAdopcion).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: cicloColor(estadoAdopcion).withValues(alpha: 0.3)),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Text(estadoAdopcion, style: TextStyle(fontSize: 12,
                                        fontWeight: FontWeight.w700, color: cicloColor(estadoAdopcion))),
                                    if (estadoAdopcion != 'Fallecido') ...[
                                      const SizedBox(width: 4),
                                      Icon(Icons.expand_more, size: 14, color: cicloColor(estadoAdopcion)),
                                    ],
                                  ]),
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
                              if ((estadoAdopcion == 'Hogar de paso' || estadoAdopcion == 'En proceso de adopción') &&
                                  (d['adoptanteIdEnProceso'] as String? ?? '').isNotEmpty)
                                GestureDetector(
                                  onTap: () => contactarPersonaEnProceso(
                                    context,
                                    docId: docId,
                                    nombre: nombre,
                                    especie: especie,
                                    fotoUrl: fotoUrl,
                                    creadoPor: d['creadoPor'] as String?,
                                    adoptanteIdEnProceso: d['adoptanteIdEnProceso'] as String? ?? '',
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: appOrange,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: const [
                                      Icon(Icons.chat_bubble_outline, size: 13, color: Colors.white),
                                      SizedBox(width: 5),
                                      Text('Contactar', style: TextStyle(fontSize: 12,
                                          fontWeight: FontWeight.w700, color: Colors.white)),
                                    ]),
                                  ),
                                ),
                            ]),
                            const SizedBox(height: 8),
                            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
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
                              if (estadoAdopcion != 'Fallecido' && estadoAdopcion != 'Adoptado' && !estancado)
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
                                        if (d['okConNinos']    == true) 'Amigable con niños',
                                        if (d['okConMascotas'] == true) 'Es sociable',
                                        if ((d['energia'] as String?)?.isNotEmpty == true) d['energia'] as String,
                                      ],
                                      fotoUrl: fotoUrl,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: appTeal.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: appTeal.withValues(alpha: 0.3)),
                                      ),
                                      // Mismo ícono que usa el adoptante para compartir
                                      // (adoptante_feed_screen.dart) — antes eran dos
                                      // íconos de "compartir" distintos para la misma
                                      // acción, uno por rol (sugerencia real de Eliza).
                                      child: const Icon(Icons.share_outlined, size: 16, color: appTeal),
                                    ),
                                  ),
                                ),
                              if (estadoAdopcion != 'Adoptado' && estadoAdopcion != 'Fallecido')
                                Tooltip(
                                  message: 'Editar',
                                  child: GestureDetector(
                                    onTap: () => Navigator.push(context, MaterialPageRoute(
                                        builder: (_) => EditarRescateScreen(docId: docId, data: d))),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: Colors.grey.shade300),
                                      ),
                                      child: Icon(Icons.edit_outlined, size: 16, color: Colors.grey.shade600),
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
                                        border: Border.all(color: const Color(0xFFD32F2F).withValues(alpha: 0.3)),
                                      ),
                                      child: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFD32F2F)),
                                    ),
                                  ),
                                ),
                            ]),
                          ]),
                        );
                      },
                    );
                  },
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String? valor, String? filtroActivo,
      ValueChanged<String?> onTap, {bool small = false}) {
    final activo = filtroActivo == valor;
    final color  = valor == null ? appTeal : cicloColor(valor);
    return GestureDetector(
      onTap: () => onTap(activo ? null : valor),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: EdgeInsets.symmetric(horizontal: small ? 12 : 14, vertical: small ? 5 : 7),
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
