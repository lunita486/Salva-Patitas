import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../theme.dart';
import 'subir_rescate_screen.dart';
import 'solicitudes_rescatista_screen.dart';
import 'adoptante_chats_screen.dart';
import 'perfil_rescatista_screen.dart';
import 'favoritos_screen.dart';
import 'perfil_adoptante_screen.dart';
import 'mis_rescates_screen.dart';
import 'adoptante_feed_screen.dart';
import 'chat_screen.dart';
import 'mis_solicitudes_screen.dart';

// ─── Home Screen ──────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool? _isRescatista;
  List<String> _roles = [];
  int  _selectedNav  = 0;
  String _ciudad = '';

  static const _rolLabel = {
    'rescatista': 'Rescatista',
    'adoptante':  'Adoptante',
    'institucion':'Institución',
    'padrino':    'Padrino',
  };

  @override
  void initState() {
    super.initState();
    _cargarRol();
    _verificarVencimientos();
    _detectarCiudad();
  }

  Future<void> _detectarCiudad() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;

      Position? pos = await Geolocator.getLastKnownPosition();
      pos ??= await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.low));

      final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (marks.isEmpty) return;
      final p = marks.first;
      final ciudad = p.locality?.isNotEmpty == true ? p.locality! : (p.administrativeArea ?? '');
      if (!mounted || ciudad.isEmpty) return;
      setState(() => _ciudad = ciudad);
    } catch (_) {}
  }

  Future<void> _cargarRol() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
    if (!mounted) return;
    final roles = List<String>.from((doc.data()?['roles'] as List?) ?? []);
    setState(() {
      _roles = roles;
      _isRescatista = roles.contains('rescatista');
    });
  }

  Future<void> _verificarVencimientos() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ahora = DateTime.now();
    final snap = await FirebaseFirestore.instance
        .collection('rescates')
        .where('rescatistaId', isEqualTo: uid)
        .where('estadoAdopcion', isEqualTo: 'Hogar de paso')
        .get();
    for (final doc in snap.docs) {
      final d = doc.data();
      final fechaFin = (d['fechaFinHogar'] as Timestamp?)?.toDate();
      if (fechaFin == null) continue;
      if (fechaFin.isAfter(ahora)) continue;
      if (d['vencimientoAvisado'] == true) continue;
      final nombre      = d['nombre']           as String? ?? 'El animal';
      final adoptanteId = d['adoptanteIdEnProceso'] as String?;
      final msg = '📋 El período de hogar de paso de $nombre ha vencido. '
          'Por favor coordina la devolución o el proceso de adopción definitivo. 🐾';
      await enviarMensajeChat(
        adoptanteId ?? '',
        nombre,
        msg,
        fotoBase64: d['fotoBase64'] as String?,
      );
      await doc.reference.update({'vencimientoAvisado': true});
    }
  }

  Widget _rolToggle() {
    final visibles = _roles.where((r) => r == 'adoptante' || r == 'rescatista').toList();
    if (visibles.length <= 1) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.80),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: visibles.map((rol) {
          final activo = (_isRescatista == true && rol == 'rescatista') ||
                         (_isRescatista == false && rol != 'rescatista');
          final label  = _rolLabel[rol] ?? rol;
          return GestureDetector(
            onTap: () => setState(() {
              _isRescatista = rol == 'rescatista';
              _selectedNav  = 0;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: activo ? const Color(0xFF1A1A1A) : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: activo ? Colors.white : Colors.grey.shade500)),
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
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: appBg),
          const LeafOverlay(),
          SafeArea(
            child: _isRescatista!
                ? _rescatistaView(context)
                : _adoptanteView(context),
          ),
        ],
      ),
      bottomNavigationBar: _bottomNav(),
    );
  }

  // ── Vista Rescatista ──────────────────────────────────────────────────────

  Widget _rescatistaView(BuildContext ctx) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [_rolToggle(), _avatar('A', appOrange)]),
        const SizedBox(height: 24),
        const Text('Hola,', style: TextStyle(fontSize: 18, color: Color(0xFF444444))),
        const SizedBox(height: 2),
        Row(children: [
          Text('${FirebaseAuth.instance.currentUser?.displayName?.split(' ').first ?? 'Rescatista'} ',
              style: const TextStyle(fontSize: 38, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
          const Text('🌿', style: TextStyle(fontSize: 28)),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          const Icon(Icons.location_on, size: 14, color: appTeal),
          const SizedBox(width: 2),
          if (_ciudad.isNotEmpty)
            Text(_ciudad, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
        ]),
        const SizedBox(height: 20),
        _label('ESTA SEMANA'),
        const SizedBox(height: 10),
        _statsRowDynamic(),
        const SizedBox(height: 16),
        _ctaCard(ctx),
        const SizedBox(height: 28),
        _sectionHeader('ESPERAN RESPUESTA', 'Solicitudes de adopción', 'Ver todas',
            onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SolicitudesRescatistaScreen()))),
        const SizedBox(height: 12),
        _solicitudesFirestore(),
        const SizedBox(height: 28),
        _sectionHeader('MIS ANIMALES', 'Tus rescates activos', 'Gestionar',
            onAction: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TodosLosRescatesScreen()))),
        const SizedBox(height: 12),
        _misRescatesCarousel(),
        const SizedBox(height: 90),
      ]),
    );
  }

  Widget _sectionHeader(String label, String title, String action, {VoidCallback? onAction}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _label(label),
        GestureDetector(
          onTap: onAction,
          child: const Text('Ver todas', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: appTeal)),
        ),
      ]),
      const SizedBox(height: 6),
      Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
    ],
  );

  Widget _solicitudDetalle(String ini, Color col, String nombre, String detalle,
      String tiempo, String animal, {String? docId, Map<String, dynamic>? data}) {
    final tipo        = data?['tipoSolicitud']    as String? ?? 'adopcion';
    final esHogar     = tipo == 'hogar_de_paso';
    final fechaInicio = (data?['fechaInicioHogar'] as Timestamp?)?.toDate();
    final fechaFin    = (data?['fechaFinHogar']    as Timestamp?)?.toDate();
    final diasHogar   = (fechaInicio != null && fechaFin != null)
        ? fechaFin.difference(fechaInicio).inDays
        : null;
    final score      = data != null ? calcularCompatibilidad(data) : -1;
    final scoreColor = score >= 80 ? const Color(0xFF1F8A62) : score >= 60 ? const Color(0xFFE65100) : const Color(0xFFB71C1C);

    return Builder(builder: (ctx) => GestureDetector(
        onTap: docId == null ? null : () => showModalBottomSheet(
          context: ctx,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          builder: (_) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            maxChildSize: 0.92,
            minChildSize: 0.4,
            builder: (_, scrollCtl) => SingleChildScrollView(
              controller: scrollCtl,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              Row(children: [
                _avatar(ini, col, radius: 22, fontSize: 18),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(nombre, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Text('Para $animal', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: esHogar ? appTeal.withValues(alpha: 0.12) : appOrange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: esHogar ? appTeal.withValues(alpha: 0.4) : appOrange.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        esHogar ? '🏡 Hogar de paso' : '🏠 Adopción',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                            color: esHogar ? appTeal : appOrange),
                      ),
                    ),
                  ]),
                ])),
              ]),
              if (esHogar && fechaInicio != null && fechaFin != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: appTeal.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: appTeal.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.calendar_today, size: 13, color: appTeal),
                    const SizedBox(width: 8),
                    Text(
                      '${fechaInicio.day}/${fechaInicio.month}/${fechaInicio.year} → ${fechaFin.day}/${fechaFin.month}/${fechaFin.year}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: appTeal),
                    ),
                    const Spacer(),
                    Text('$diasHogar días', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: appTeal)),
                  ]),
                ),
              ],
              const SizedBox(height: 16),
              if (score >= 0) Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: scoreColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scoreColor.withOpacity(0.35))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(score >= 80 ? '✅' : score >= 60 ? '⚠️' : '❌', style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(score >= 80 ? 'Perfil ideal ($score%)' : score >= 60 ? 'Perfil aceptable ($score%)' : 'No recomendado ($score%)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scoreColor)),
                    const SizedBox(height: 8),
                    if (data != null) ...explicarCompatibilidad(data).map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.$2 ? '✓' : '✗',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                                color: r.$2 ? appTeal : Colors.red.shade400)),
                        const SizedBox(width: 5),
                        Expanded(child: Text(r.$1,
                            style: TextStyle(fontSize: 11,
                                color: r.$2 ? Colors.grey.shade700 : Colors.red.shade600))),
                      ]),
                    )),
                  ])),
                ]),
              ),
              const SizedBox(height: 20),
              Text('Perfil del adoptante', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade500)),
              const SizedBox(height: 10),
              _infoFila('🏠', 'Vivienda', data?['vivienda'] ?? '-'),
              _infoFila('⏰', 'Horas fuera al día', data?['horasFuera'] ?? '-'),
              _infoFila('👥', 'Personas en casa', data?['integrantes'] ?? '-'),
              _infoFila('👶', 'Niños menores de 8 años', (data?['tieneNinos'] as bool? ?? false) ? 'Sí' : 'No'),
              _infoFila('🐾', 'Otras mascotas', (data?['tieneMascotas'] as bool? ?? false) ? 'Sí' : 'No'),
              _infoFila('📚', 'Experiencia previa', (data?['experienciaPrevia'] as bool? ?? false) ? 'Sí' : 'No, primera mascota'),
              if (data?['motivacion'] != null) ...[
                const SizedBox(height: 16),
                Text('Motivación', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade500)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
                  child: Text('"${data!['motivacion']}"', style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.5)),
                ),
              ],
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () { Navigator.pop(ctx); if (data != null) aprobarSolicitud(docId, data); },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(color: appTeal, borderRadius: BorderRadius.circular(12)),
                      child: const Text('Aprobar', textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      final motivoCtl = TextEditingController(
                        text: 'Hola, gracias por tu interés en adoptar a $animal. '
                            'Luego de revisar tu solicitud, en esta ocasión no podemos continuar con el proceso. '
                            '¡Esperamos que pronto encuentres a tu compañero perfecto! 🐾',
                      );
                      showDialog(context: ctx, builder: (dlg) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        title: const Text('Mensaje de rechazo'),
                        content: TextField(
                          controller: motivoCtl,
                          maxLines: 5,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: appTeal, width: 2),
                            ),
                          ),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(dlg), child: const Text('Cancelar')),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(dlg);
                              Navigator.pop(ctx);
                              if (data != null) rechazarSolicitud(docId, data, motivoCtl.text.trim());
                            },
                            child: const Text('Confirmar', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(border: Border.all(color: Colors.red.shade300), borderRadius: BorderRadius.circular(12)),
                      child: Text('Rechazar', textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                ),
              ]),
            ]),
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _avatar(ini, col, radius: 20, fontSize: 16),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 2),
                Text(detalle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ])),
              Text(tiempo, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFFD8F0E4), borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 32, height: 32,
                  decoration: BoxDecoration(color: Colors.brown.shade300, borderRadius: BorderRadius.circular(6)),
                  child: const Icon(Icons.pets, size: 18, color: Colors.white)),
                const SizedBox(width: 8),
                Text('Para $animal', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              ]),
            ),
            if (docId != null) ...[
              const SizedBox(height: 12),
              const Text('Revisar →', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: appTeal)),
            ],
          ]),
        ),
      ));
  }

  Widget _infoFila(String emoji, String label, String valor) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 15)),
      const SizedBox(width: 8),
      Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600))),
      Text(valor, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
    ]),
  );

  Widget _misRescatesCarousel() {
    return SizedBox(
      height: 245,
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('rescates')
            .where('rescatistaId', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: appTeal));
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}', style: const TextStyle(fontSize: 12)));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Text('Aún no tienes rescates publicados.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            );
          }
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              final nombre         = (data['nombre'] as String?)?.isNotEmpty == true ? data['nombre'] : 'Sin nombre';
              final especie        = data['especie']        ?? '';
              final estadoAdopcion = data['estadoAdopcion'] ?? 'Rescatado';
              final fotoBase64     = data['fotoBase64']     as String?;
              final docId          = docs[i].id;
              return _animalCard(
                nombre, especie,
                estado: estadoAdopcion,
                emoji: especie == 'Gato' ? '🐱' : '🐶',
                fotoBase64: fotoBase64,
                onCambiarEstado: () => showModalBottomSheet(
                  context: context,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                  builder: (_) => CambiarEstadoSheet(docId: docId, estadoActual: estadoAdopcion),
                ),
                onContactarAdoptante: estadoAdopcion == 'En proceso de adopción' ? () async {
                  final uid   = FirebaseAuth.instance.currentUser?.uid ?? '';
                  final chats = await FirebaseFirestore.instance.collection('chats')
                      .where('animalNombre', isEqualTo: nombre)
                      .where('rescatistaId', isEqualTo: uid)
                      .limit(1).get();
                  if (chats.docs.isEmpty || !context.mounted) return;
                  final chatDoc = chats.docs.first;
                  final d = chatDoc.data();
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      esRescatista: true,
                      chatId: chatDoc.id,
                      animal: {
                        'nombre':     nombre,
                        'rescatista': FirebaseAuth.instance.currentUser?.displayName ?? 'Rescatista',
                        'especie':    especie,
                        'fotoBase64': d['fotoBase64'],
                      },
                    ),
                  ));
                } : null,
              );
            },
          );
        },
      ),
    );
  }

  Widget _animalCard(String nombre, String especie,
      {String emoji = '🐾', String estado = 'En adopción', String? fotoBase64, VoidCallback? onCambiarEstado, VoidCallback? onContactarAdoptante}) {
    final color = cicloColor(estado);
    return Container(
      width: 150,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: fotoBase64 != null
            ? Image.memory(base64Decode(fotoBase64),
                height: 100, width: double.infinity, fit: BoxFit.cover)
            : Container(
                height: 100, width: double.infinity,
                color: const Color(0xFFD8F0E4),
                child: Center(child: Text(emoji, style: const TextStyle(fontSize: 40))),
              ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                overflow: TextOverflow.ellipsis),
            Text(especie, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: onCambiarEstado,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withOpacity(0.4)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Flexible(child: Text(estado,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
                    overflow: TextOverflow.ellipsis)),
                  if (onCambiarEstado != null) ...[
                    const SizedBox(width: 2),
                    Icon(Icons.expand_more, size: 12, color: color),
                  ],
                ]),
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
                  child: const Text('Contactar 💬',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  // ── Vista Adoptante ───────────────────────────────────────────────────────

  Widget _adoptanteView(BuildContext ctx) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_rolToggle(), _avatar('A', appOrange)]),
        ),
        const Expanded(child: AdoptanteFeedScreen()),
      ],
    );
  }

  Widget _label(String t) => Text(t, style: TextStyle(
      fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2, color: Colors.grey.shade600));

  Widget _statsRowDynamic() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('solicitudes')
          .where('rescatistaId', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
          .where('estado', isEqualTo: 'pendiente')
          .snapshots(),
      builder: (context, snap) {
        final count = snap.data?.docs.length ?? 0;
        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('chats')
              .where('rescatistaId', isEqualTo: uid).snapshots(),
          builder: (context, chatSnap) {
            final noLeidos = (chatSnap.data?.docs ?? []).where((doc) {
              final d = doc.data() as Map<String, dynamic>;
              return ((d['noLeidosRescatista'] as int?) ?? 0) > 0;
            }).length;
            return Row(children: [
              Expanded(child: GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SolicitudesRescatistaScreen())),
                child: _stat('$count', 'Nuevas\nsolicitudes', const Color(0xFFF9DDD5), const Color(0xFFCC4422)))),
              const SizedBox(width: 10),
              Expanded(child: GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdoptanteChatsScreen(esRescatista: true))),
                child: _stat('$noLeidos', 'Mensajes\nsin leer', const Color(0xFFD8EEFA), const Color(0xFF2070B0)))),
              const SizedBox(width: 10),
              Expanded(child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('rescates')
                    .where('rescatistaId', isEqualTo: uid).snapshots(),
                builder: (context, rescSnap) {
                  final total = rescSnap.data?.docs.length ?? 0;
                  return _stat('$total', 'Animales\nrescatados', Colors.white, const Color(0xFF1A1A1A));
                },
              )),
            ]);
          },
        );
      },
    );
  }

  Widget _solicitudesFirestore() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('solicitudes')
          .where('rescatistaId', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
          .where('estado', isEqualTo: 'pendiente')
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: appTeal));
        }
        final docs = [...(snap.data?.docs ?? [])]
          ..sort((a, b) {
            final ta = (a.data() as Map)['creadoEn'] as Timestamp?;
            final tb = (b.data() as Map)['creadoEn'] as Timestamp?;
            if (ta == null || tb == null) return 0;
            return tb.compareTo(ta);
          });
        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Center(child: Text('No hay solicitudes por ahora.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500))),
          );
        }
        final limited = docs.take(3).toList();
        return Column(
          children: List.generate(limited.length, (i) {
            final d = limited[i].data() as Map<String, dynamic>;
            final animal      = d['animalNombre'] as String? ?? 'Animal';
            final nombre      = d['nombre']      as String? ?? '';
            final apellido    = d['apellido']    as String? ?? '';
            final integrantes = d['integrantes'] as String? ?? '';
            final vivienda    = d['vivienda']    as String? ?? '';
            final mascotas    = (d['tieneMascotas'] as bool? ?? false) ? 'con mascotas' : 'sin mascotas';
            final ninos       = (d['tieneNinos']    as bool? ?? false) ? 'con niños' : 'sin niños';
            final nombreCompleto = nombre.isNotEmpty ? '$nombre $apellido' : 'Adoptante ${i + 1}';
            final detalle     = '$vivienda · $integrantes personas · $ninos · $mascotas';
            final ts          = d['creadoEn'] as Timestamp?;
            final tiempo      = ts != null ? _tiempoRelativo(ts.toDate()) : '';
            final ini         = nombreCompleto[0].toUpperCase();
            final col         = i.isEven ? appTeal : appOrange;
            return Padding(
              padding: EdgeInsets.only(bottom: i < limited.length - 1 ? 10 : 0),
              child: _solicitudDetalle(ini, col, nombreCompleto, detalle, tiempo, animal,
                  docId: limited[i].id, data: d),
            );
          }),
        );
      },
    );
  }

  String _tiempoRelativo(DateTime fecha) {
    final diff = DateTime.now().difference(fecha);
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}min';
    if (diff.inHours < 24)   return 'hace ${diff.inHours}h';
    return 'hace ${diff.inDays}d';
  }

  Widget _stat(String n, String lbl, Color bg, Color nc) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(n, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: nc)),
      const SizedBox(height: 4),
      Text(lbl, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.3)),
    ]),
  );

  Widget _ctaCard(BuildContext ctx) => GestureDetector(
    onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const SubirRescateScreen())),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: appDark, borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        Container(width: 44, height: 44,
          decoration: const BoxDecoration(color: appOrange, shape: BoxShape.circle),
          child: const Icon(Icons.add, color: Colors.white, size: 24)),
        const SizedBox(width: 16),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Subir un rescate', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
          SizedBox(height: 2),
          Text('Publica un animal en minutos', style: TextStyle(color: Color(0xFF7FAF7F), fontSize: 13)),
        ])),
        const Icon(Icons.chevron_right, color: Color(0xFF7FAF7F), size: 22),
      ]),
    ),
  );

  Widget _bottomNav() => Container(
    decoration: BoxDecoration(color: Colors.white,
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, -2))]),
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          if (_isRescatista == true) ...[
            _navItem(Icons.pets,                    'Mis rescates', 0),
            _navTap(Icons.add_circle_outline, 'Subir', 1,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SubirRescateScreen()))),
            _navTap(Icons.notifications_outlined, 'Solicitudes', 2,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SolicitudesRescatistaScreen()))),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('chats')
                  .where('rescatistaId', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
                  .snapshots(),
              builder: (_, snap) {
                final unread = (snap.data?.docs ?? []).where((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  return ((d['noLeidosRescatista'] as int?) ?? 0) > 0;
                }).length;
                return _navTapConBadge(
                  Icons.chat_bubble_outline, 'Chats', unread,
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdoptanteChatsScreen(esRescatista: true))),
                );
              },
            ),
            _navTap(Icons.person_outline, 'Perfil', 4,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PerfilRescatistaScreen()))),
          ] else ...[
            _navItem(Icons.pets, 'Adoptar', 0),
            _navTap(Icons.favorite_outline, 'Favoritos', 1,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritosScreen()))),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('chats')
                  .where('adoptanteId', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
                  .snapshots(),
              builder: (_, snap) {
                final unread = (snap.data?.docs ?? []).where((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  return ((d['noLeidosAdoptante'] as int?) ?? 0) > 0;
                }).length;
                return _navTapConBadge(
                  Icons.chat_bubble_outline, 'Chats', unread,
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdoptanteChatsScreen())),
                );
              },
            ),
            _navTap(Icons.assignment_outlined, 'Solicitudes', 2,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MisSolicitudesScreen()))),
            _navTap(Icons.person_outline, 'Perfil', 3,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PerfilAdoptanteScreen()))),
          ],
        ]),
      ),
    ),
  );

  Widget _navItem(IconData icon, String label, int idx) {
    final active = _selectedNav == idx;
    final color  = active ? appTeal : Colors.grey.shade400;
    return GestureDetector(
      onTap: () => setState(() => _selectedNav = idx),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontSize: 10, color: color)),
      ]),
    );
  }

  Widget _navTap(IconData icon, String label, int idx, {required VoidCallback onTap}) {
    final color = Colors.grey.shade400;
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontSize: 10, color: color)),
      ]),
    );
  }

  Widget _navTapConBadge(IconData icon, String label, int badge, VoidCallback onTap) {
    final color = Colors.grey.shade400;
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Stack(clipBehavior: Clip.none, children: [
          Icon(icon, color: color, size: 24),
          if (badge > 0)
            Positioned(
              top: -4, right: -6,
              child: Container(
                padding: const EdgeInsets.all(3),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: const BoxDecoration(color: appOrange, shape: BoxShape.circle),
                child: Text(
                  badge > 9 ? '9+' : '$badge',
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ]),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontSize: 10, color: color)),
      ]),
    );
  }
}

// ─── Avatar helper (global dentro del archivo) ───────────────────────────────

Widget _avatar(String letter, Color color, {double radius = 22, double fontSize = 20}) {
  final user = FirebaseAuth.instance.currentUser;
  final foto = user?.photoURL;
  if (foto != null) {
    return CircleAvatar(backgroundImage: NetworkImage(foto), radius: radius);
  }
  final inicial = user?.displayName?.isNotEmpty == true
      ? user!.displayName![0].toUpperCase() : letter;
  return CircleAvatar(backgroundColor: color, radius: radius,
      child: Text(inicial, style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.bold)));
}

// ─── Función compatibilidad (global, usada por home y solicitudes) ───────────

int calcularCompatibilidad(Map<String, dynamic> solicitud) {
  int score = 0;

  final energia    = solicitud['animalEnergia']  as String? ?? 'Tranquilo';
  final horas      = int.tryParse(solicitud['horasFuera']?.toString() ?? '0') ?? 0;
  final vivienda   = solicitud['vivienda']       as String? ?? '';
  final tienePatio = vivienda == 'Casa con jardín';

  if (energia == 'Tranquilo') {
    score += 20;
  } else if (energia == 'Activo') {
    score += horas <= 8 ? 20 : 10;
  } else {
    if (tienePatio && horas <= 6) score += 20;
    else if (tienePatio || horas <= 6) score += 10;
  }

  final tamano = solicitud['animalTamano'] as String? ?? 'Mediano';
  if (tamano == 'Pequeño') {
    score += 20;
  } else if (tamano == 'Mediano') {
    score += vivienda != 'Apartamento sin área exterior' ? 20 : 10;
  } else {
    score += tienePatio ? 20 : (vivienda == 'Apartamento con balcón' ? 10 : 0);
  }

  final okNinos    = solicitud['animalOkConNinos']   as bool? ?? true;
  final tieneNinos = solicitud['tieneNinos']         as bool? ?? false;
  score += (!tieneNinos || okNinos) ? 20 : 0;

  final okMascotas    = solicitud['animalOkConMascotas'] as bool? ?? true;
  final tieneMascotas = solicitud['tieneMascotas']       as bool? ?? false;
  score += (!tieneMascotas || okMascotas) ? 20 : 0;

  final requiereExp = solicitud['animalRequiereExp']   as bool? ?? false;
  final tieneExp    = solicitud['experienciaPrevia']   as bool? ?? false;
  score += (!requiereExp || tieneExp) ? 20 : 0;

  return score;
}
