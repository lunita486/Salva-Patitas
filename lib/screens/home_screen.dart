import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../theme.dart';
import '../services/notificaciones_service.dart';
import '../data/creator_role.dart';
import '../data/rescates_repository.dart';
import '../data/solicitudes_repository.dart';
import '../data/usuarios_repository.dart';
import '../data/chats_repository.dart';
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
import 'solicitudes_preview.dart';

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
  final _rescatesRepo = RescatesRepository();
  final _solicitudesRepo = SolicitudesRepository();

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        NotificacionesService.guardarToken();
        NotificacionesService.escucharEnPrimerPlano(context);
      }
    });
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

  // ── Debug: cambio rápido de rol (solo en builds de desarrollo) ─────────────
  Future<void> _cambiarRolDebug() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final opciones = <String, List<String>>{
      'Solo Adoptante':         ['adoptante'],
      'Solo Rescatista':        ['rescatista'],
      'Adoptante + Rescatista': ['adoptante', 'rescatista'],
      'Albergue':               ['albergue'],
      'Aliado':                 ['aliado'],
    };
    final seleccion = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('🛠 Cambiar rol (DEBUG)'),
        children: opciones.entries.map((e) => SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, e.value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(e.key),
          ),
        )).toList(),
      ),
    );
    if (seleccion == null) return;
    await UsuariosRepository().actualizarRoles(uid, seleccion);
    await _cargarRol();
  }


  Future<void> _verificarVencimientos() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ahora = DateTime.now();
    final snap = await _rescatesRepo.misRescatesPorEstado(
      uid: uid,
      role: CreatorRole.rescatista,
      estadoAdopcion: 'Hogar de paso',
    );
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
        fotoUrl: d['fotoUrl'] as String?,
        rescateId: doc.id,
        creadoPor: 'rescatista',
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
      floatingActionButton: kDebugMode
          ? FloatingActionButton.small(
              onPressed: _cambiarRolDebug,
              backgroundColor: Colors.purple.shade100,
              elevation: 4,
              child: Icon(Icons.developer_mode, color: Colors.purple.shade700),
            )
          : null,
      bottomNavigationBar: _bottomNav(),
    );
  }

  // ── Vista Rescatista ──────────────────────────────────────────────────────

  Widget _rescatistaView(BuildContext ctx) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _rolToggle(),
          _avatar('A', appOrange),
        ]),
        const SizedBox(height: 24),
        const Text('Hola,', style: TextStyle(fontSize: 18, color: Color(0xFF444444))),
        const SizedBox(height: 2),
        Row(children: [
          Text('${FirebaseAuth.instance.currentUser?.displayName?.split(' ').first ?? 'Rescatista'} ',
              style: const TextStyle(fontSize: 38, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
          const Text('🌿', style: TextStyle(fontSize: 28)),
        ]),
        const SizedBox(height: 4),
        // El ícono solo tiene sentido junto a un texto — antes se mostraba
        // solo (sin ciudad al lado) cuando el GPS estaba bloqueado o sin
        // detectar, quedando un pin "flotando" sin explicación.
        if (_ciudad.isNotEmpty)
          Row(children: [
            const Icon(Icons.location_on, size: 14, color: appTeal),
            const SizedBox(width: 2),
            Text(_ciudad, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          ]),
        const SizedBox(height: 20),
        _label('ESTA SEMANA'),
        const SizedBox(height: 10),
        _statsRowDynamic(),
        const SizedBox(height: 16),
        _ctaCard(ctx),
        const SizedBox(height: 28),
        _sectionHeader('ESPERAN RESPUESTA', 'Solicitudes', 'Ver todas',
            onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SolicitudesRescatistaScreen()))),
        const SizedBox(height: 12),
        const SolicitudesPreview(role: CreatorRole.rescatista),
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

  Widget _misRescatesCarousel() {
    return SizedBox(
      height: 245,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _rescatesRepo.misRescates(
          uid: FirebaseAuth.instance.currentUser?.uid ?? '',
          role: CreatorRole.rescatista,
        ),
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
              final data = docs[i].data();
              final nombre         = (data['nombre'] as String?)?.isNotEmpty == true ? data['nombre'] : 'Sin nombre';
              final especie        = data['especie']        ?? '';
              final estadoAdopcion = data['estadoAdopcion'] ?? 'Rescatado';
              final fotoUrl        = data['fotoUrl']        as String?;
              final docId          = docs[i].id;
              return _animalCard(
                nombre, especie,
                estado: estadoAdopcion,
                emoji: especie == 'Gato' ? '🐱' : '🐶',
                fotoUrl: fotoUrl,
                onCambiarEstado: estadoAdopcion == 'Fallecido' ? null : () => showModalBottomSheet(
                  context: context,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                  builder: (_) => CambiarEstadoSheet(
                    docId: docId,
                    estadoActual: estadoAdopcion,
                    nombre: nombre,
                    adoptanteIdEnProceso: data['adoptanteIdEnProceso'] as String?,
                  ),
                ),
                onContactarAdoptante: estadoAdopcion == 'En proceso de adopción' ? () async {
                  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                  final adoptanteIdEnProceso = data['adoptanteIdEnProceso'] as String? ?? '';
                  QueryDocumentSnapshot<Map<String, dynamic>>? chatDoc;
                  Map<String, dynamic>? d;
                  // try/catch: leer un chat que NO existe da permission-denied
                  // con nuestras reglas — sin esto la excepción mataba el
                  // onTap y "Contactar adoptante" no hacía nada.
                  try {
                    if (adoptanteIdEnProceso.isNotEmpty) {
                      final doc = await FirebaseFirestore.instance.collection('chats')
                          .doc(ChatsRepository().idAnimal(rescateId: docId, adoptanteId: adoptanteIdEnProceso))
                          .get();
                      if (doc.exists) d = doc.data();
                    } else {
                      final chats = await FirebaseFirestore.instance.collection('chats')
                          .where('animalNombre', isEqualTo: nombre)
                          .where('rescatistaId', isEqualTo: uid)
                          .limit(1).get();
                      if (chats.docs.isNotEmpty) {
                        chatDoc = chats.docs.first;
                        d = chatDoc.data();
                      }
                    }
                  } catch (_) {
                    d = null;
                  }
                  if (!context.mounted) return;
                  // Sin chat previo pero con adoptante conocido: se abre el
                  // chat igual con chatId null y ChatScreen lo crea — antes
                  // el botón simplemente no hacía nada en este caso.
                  if (d == null && adoptanteIdEnProceso.isEmpty) return;
                  final dFinal = d ?? const <String, dynamic>{};
                  final chatId = d == null
                      ? null
                      : adoptanteIdEnProceso.isNotEmpty
                          ? ChatsRepository().idAnimal(rescateId: docId, adoptanteId: adoptanteIdEnProceso)
                          : chatDoc!.id;
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      esRescatista: true,
                      chatId: chatId,
                      animal: {
                        'nombre':        nombre,
                        'rescatista':    FirebaseAuth.instance.currentUser?.displayName ?? 'Rescatista',
                        'rescatistaId':  dFinal['rescatistaId'] as String? ?? uid,
                        'rescateId':     docId,
                        'adoptanteId':   adoptanteIdEnProceso,
                        'adoptanteNombre': dFinal['adoptanteNombre'],
                        'especie':       especie,
                        'creadoPor':     data['creadoPor'] as String? ?? 'rescatista',
                        'tipoSolicitud': dFinal['tipoSolicitud'] as String? ?? 'adopcion',
                        'fotoUrl':       dFinal['fotoUrl'] ?? data['fotoUrl'],
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
      {String emoji = '🐾', String estado = 'En adopción', String? fotoUrl, VoidCallback? onCambiarEstado, VoidCallback? onContactarAdoptante}) {
    final color = cicloColor(estado);
    return Container(
      width: 150,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: fotoUrl != null
            ? FotoUrl(
                url: fotoUrl,
                height: 100, width: double.infinity, fit: BoxFit.cover,
                fallback: Container(
                    height: 100, width: double.infinity,
                    color: const Color(0xFFD8F0E4),
                    child: Center(child: Text(emoji, style: const TextStyle(fontSize: 40))),
                  ),
              )
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
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _solicitudesRepo.paraOwner(
        uid: FirebaseAuth.instance.currentUser?.uid ?? '',
        role: CreatorRole.rescatista,
        estado: 'pendiente',
      ),
      builder: (context, snap) {
        final count = snap.data?.docs.length ?? 0;
        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('chats')
              .where('rescatistaId', isEqualTo: uid).snapshots(),
          builder: (context, chatSnap) {
            final noLeidos = (chatSnap.data?.docs ?? []).where((doc) {
              final d = doc.data() as Map<String, dynamic>;
              if ((d['tipoSolicitud'] as String? ?? '') == 'consulta_aliado') return false;
              if ((d['creadoPor'] as String? ?? 'rescatista') == 'albergue') return false;
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
              Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _rescatesRepo.misRescates(uid: uid, role: CreatorRole.rescatista),
                builder: (context, rescSnap) {
                  final total = (rescSnap.data?.docs ?? []).length;
                  return _stat('$total', 'Animales\nrescatados', Colors.white, const Color(0xFF1A1A1A));
                },
              )),
            ]);
          },
        );
      },
    );
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
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A5C40), Color(0xFF1F8A62)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(children: [
        Container(width: 44, height: 44,
          decoration: const BoxDecoration(color: appOrange, shape: BoxShape.circle),
          child: const Icon(Icons.add, color: Colors.white, size: 24)),
        const SizedBox(width: 16),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Subir un rescate', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
          SizedBox(height: 2),
          Text('Publica un animal en minutos', style: TextStyle(color: Color(0xFFB8E0CC), fontSize: 13)),
        ])),
        const Icon(Icons.chevron_right, color: Color(0xFFB8E0CC), size: 22),
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
                  if ((d['tipoSolicitud'] as String? ?? '') == 'consulta_aliado') return false;
                  if ((d['creadoPor'] as String? ?? 'rescatista') == 'albergue') return false;
                  return ((d['noLeidosRescatista'] as int?) ?? 0) > 0;
                }).length;
                return _navTapConBadge(
                  Icons.chat_bubble_outline, 'Chats', unread,
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdoptanteChatsScreen(esRescatista: true))),
                );
              },
            ),
            _navTap(Icons.store_outlined, 'Negocios', 5,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AliadosScreen(esRescatista: true)))),
            _navTap(Icons.person_outline, 'Perfil', 4,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PerfilRescatistaScreen()))),
          ] else ...[
            _navItem(Icons.pets, 'Adoptar', 0),
            _navTap(Icons.favorite_outline, 'Favoritos', 1,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritosScreen()))),
            _navTap(Icons.assignment_outlined, 'Solicitudes', 2,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MisSolicitudesScreen()))),
            // Mismo orden que en Rescatista/Albergue/Aliado: Chats siempre va
            // después de Solicitudes, antes de Negocios/Perfil.
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('chats')
                  .where('adoptanteId', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
                  .snapshots(),
              builder: (_, snap) {
                final unread = (snap.data?.docs ?? []).where((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  if ((d['tipoSolicitud'] as String? ?? '') == 'consulta_aliado') return false;
                  return ((d['noLeidosAdoptante'] as int?) ?? 0) > 0;
                }).length;
                return _navTapConBadge(
                  Icons.chat_bubble_outline, 'Chats', unread,
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdoptanteChatsScreen())),
                );
              },
            ),
            _navTap(Icons.store_outlined, 'Negocios', 3,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AliadosScreen(esRescatista: false)))),
            _navTap(Icons.person_outline, 'Perfil', 4,
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

