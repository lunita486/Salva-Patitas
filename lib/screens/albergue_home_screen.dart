import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../services/notificaciones_service.dart';
import '../data/creator_role.dart';
import '../data/rescates_repository.dart';
import '../data/solicitudes_repository.dart';
import '../data/usuarios_repository.dart';
import 'subir_rescate_screen.dart';
import 'subir_lote_screen.dart';
import 'mis_rescates_screen.dart';
import 'solicitudes_rescatista_screen.dart';
import 'adoptante_chats_screen.dart';
import 'albergue_perfil_screen.dart';
import 'adoptante_feed_screen.dart' show AliadosScreen;

class AlbergueHomeScreen extends StatefulWidget {
  const AlbergueHomeScreen({super.key});
  @override
  State<AlbergueHomeScreen> createState() => _AlbergueHomeScreenState();
}

class _AlbergueHomeScreenState extends State<AlbergueHomeScreen> {
  int _nav = 0;
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final _rescatesRepo = RescatesRepository();
  final _solicitudesRepo = SolicitudesRepository();

  @override
  void initState() {
    super.initState();
    _verificarVencimientos();
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
  Future<void> _verificarVencimientos() async {
    if (_uid.isEmpty) return;
    final ahora = DateTime.now();
    final snap = await _rescatesRepo.misRescatesPorEstado(
      uid: _uid,
      role: CreatorRole.albergue,
      estadoAdopcion: 'Hogar de paso',
    );
    for (final doc in snap.docs) {
      final d = doc.data();
      final fechaFin = (d['fechaFinHogar'] as Timestamp?)?.toDate();
      if (fechaFin == null) continue;
      if (fechaFin.isAfter(ahora)) continue;
      if (d['vencimientoAvisado'] == true) continue;
      final nombre      = d['nombre']            as String? ?? 'El animal';
      final adoptanteId = d['adoptanteIdEnProceso'] as String?;
      final msg = '📋 El período de hogar de paso de $nombre ha vencido. '
          'Por favor coordina la devolución o el proceso de adopción definitivo. 🐾';
      await enviarMensajeChat(
        adoptanteId ?? '',
        nombre,
        msg,
        fotoUrl: d['fotoUrl'] as String?,
        rescateId: doc.id,
        creadoPor: 'albergue',
      );
      await doc.reference.update({'vencimientoAvisado': true});
    }
  }

  Future<void> _uploadFotoPerfil() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (picked == null) return;
    try {
      final bytes = await picked.readAsBytes();
      final b64 = base64Encode(bytes);
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(_uid)
          .update({'fotoBase64': b64});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto de perfil actualizada'), backgroundColor: appTeal));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo subir la foto: $e')));
    }
  }

  Future<void> _cambiarRolDebug() async {
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
    if (seleccion == null || !mounted) return;
    await UsuariosRepository().actualizarRoles(_uid, seleccion);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> get _rescatesStream =>
      _rescatesRepo.misRescates(uid: _uid, role: CreatorRole.albergue);

  Stream<QuerySnapshot<Map<String, dynamic>>> get _solicitudesStream =>
      _solicitudesRepo.paraOwner(uid: _uid, role: CreatorRole.albergue, estado: 'pendiente');

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('usuarios').doc(_uid).snapshots(),
      builder: (context, userSnap) {
        final data         = userSnap.data?.data() as Map<String, dynamic>? ?? {};
        final nombre       = data['albergueNombre']    as String? ?? 'Albergue';
        final tipo         = data['albergueTipo']      as String? ?? '';
        final ciudad       = data['ciudad']            as String? ?? '';
        final capacidad    = (data['capacidadTotal']   as int?)   ?? 0;
        final fotoBase64   = data['fotoBase64']       as String?;
        final iniciales    = nombre.trim().split(' ')
            .take(2).map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();

        return Scaffold(
          backgroundColor: appBg,
          body: StreamBuilder<QuerySnapshot>(
            stream: _rescatesStream,
            builder: (context, rSnap) {
              if (rSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: appTeal));
              }
              final rescates = rSnap.data?.docs ?? [];
              final enCuidado  = rescates.where((d) {
                final e = (d.data() as Map)['estadoAdopcion'] as String? ?? 'Rescatado';
                return e == 'Rescatado' || e == 'Hogar de paso';
              }).length;
              final enAdopcion = rescates.where((d) =>
                (d.data() as Map)['estadoAdopcion'] == 'En proceso de adopción').length;
              final adoptados  = rescates.where((d) =>
                (d.data() as Map)['estadoAdopcion'] == 'Adoptado').length;
              final totalActivos = enCuidado + enAdopcion;
              final pct = capacidad > 0
                  ? (totalActivos / capacidad).clamp(0.0, 1.0)
                  : 0.0;

              return Stack(children: [
                const Positioned.fill(child: LeafOverlay()),
                SafeArea(
                  child: _nav == 0
                    ? _panel(context, nombre, tipo, ciudad, iniciales, fotoBase64,
                        capacidad, enCuidado, enAdopcion, adoptados, totalActivos, pct, rescates)
                    : _nav == 3
                      ? _perfilTab(context, nombre, tipo, ciudad, iniciales, fotoBase64)
                      : const SizedBox.shrink(),
                ),
              ]);
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

  Widget _panel(BuildContext ctx, String nombre, String tipo, String ciudad, String iniciales,
      String? fotoBase64,
      int capacidad, int enCuidado, int enAdopcion,
      int adoptados, int totalActivos, double pct,
      List<QueryDocumentSnapshot> rescates) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 100),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        if (kDebugMode)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 16, top: 8),
              child: GestureDetector(
                onTap: _cambiarRolDebug,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade100,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 4, offset: const Offset(0, 2))],
                  ),
                  child: Icon(Icons.developer_mode,
                      color: Colors.purple.shade700, size: 18),
                ),
              ),
            ),
          ),

        // ── Hero card ────────────────────────────────────────────────────────
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0A5C40), Color(0xFF1F8A62)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: const Color(0xFF1F8A62).withValues(alpha: 0.35),
                  blurRadius: 20, offset: const Offset(0, 8)),
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              // Avatar
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2.5),
                ),
                child: Builder(builder: (_) {
                  final fotoBytes = bytesFotoSegura(fotoBase64);
                  final photoUrl = FirebaseAuth.instance.currentUser?.photoURL;
                  final ImageProvider? avatarImg = fotoBytes != null
                      ? MemoryImage(fotoBytes)
                      : photoUrl != null ? NetworkImage(photoUrl) : null;
                  return CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    backgroundImage: avatarImg,
                    onBackgroundImageError: avatarImg != null ? (_, __) {} : null,
                    child: avatarImg == null
                        ? Text(iniciales, style: const TextStyle(color: Colors.white,
                            fontWeight: FontWeight.bold, fontSize: 18))
                        : null,
                  );
                }),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Hola 👋', style: TextStyle(fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.75))),
                const SizedBox(height: 2),
                Text(nombre, style: const TextStyle(fontSize: 22,
                    fontWeight: FontWeight.bold, color: Colors.white),
                    overflow: TextOverflow.ellipsis),
                if (tipo.isNotEmpty || ciudad.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(children: [
                    Icon(Icons.location_on, size: 12,
                        color: Colors.white.withValues(alpha: 0.7)),
                    const SizedBox(width: 3),
                    Expanded(child: Text(
                      [if (tipo.isNotEmpty) tipo, if (ciudad.isNotEmpty) ciudad].join(' · '),
                      style: TextStyle(fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.75)),
                      overflow: TextOverflow.ellipsis,
                    )),
                  ]),
                ],
              ])),
            ]),

            // Estadística histórica
            if (adoptados > 0) ...[
              const SizedBox(height: 12),
              Row(children: [
                const Icon(Icons.emoji_events_outlined,
                    size: 13, color: Colors.amber),
                const SizedBox(width: 5),
                Text(
                  '${adoptados == 1 ? '1 animal' : '$adoptados animales'} ya encontraron hogar',
                  style: TextStyle(fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.85)),
                ),
              ]),
            ],

            // Barra de capacidad
            if (capacidad > 0) ...[
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('$totalActivos de $capacidad animales',
                    style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w600)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${(pct * 100).round()}% ocupado',
                      style: const TextStyle(fontSize: 11,
                          fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ]),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: pct == 0 ? 0.01 : pct,
                  minHeight: 8,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(
                      pct >= 0.9 ? Colors.red.shade300 : Colors.white),
                ),
              ),
            ],
          ]),
        ),

        const SizedBox(height: 20),

        // ── Stats ─────────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            _statCard(ctx, enCuidado, 'En cuidado', appTeal,
                Icons.favorite_outline, 'En cuidado'),
            const SizedBox(width: 10),
            _statCard(ctx, adoptados, 'Adoptados', const Color(0xFF2196F3),
                Icons.home_outlined, 'Adoptado'),
          ]),
        ),

        const SizedBox(height: 20),

        // ── CTAs ──────────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            _subirLoteCard(ctx),
            const SizedBox(height: 10),
            _subirUnoCard(ctx),
          ]),
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
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const SolicitudesRescatistaScreen(esAlbergue: true))),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: count > 0 ? appOrange.withValues(alpha: 0.1) : appTeal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: count > 0 ? appOrange.withValues(alpha: 0.3) : appTeal.withValues(alpha: 0.3)),
                    ),
                    child: Text(count > 0 ? '$count pendientes' : 'Ver todas',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                            color: count > 0 ? appOrange : appTeal)),
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 20),

        // ── Jauría ────────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _sectionHeader(
            'LA JAURÍA',
            trailing: GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const TodosLosRescatesScreen(esAlbergue: true))),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: appTeal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: appTeal.withValues(alpha: 0.3)),
                ),
                child: const Text('Gestionar',
                    style: TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w700, color: appTeal)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: _jauriaCarousel(rescates.where((d) {
            final e = (d.data() as Map)['estadoAdopcion'] as String? ?? 'Rescatado';
            return e != 'Adoptado' && e != 'Fallecido';
          }).toList()),
        ),

        // ── Ya encontraron hogar ──────────────────────────────────────────
        Builder(builder: (_) {
          final adoptadosDocs = rescates.where((d) =>
              (d.data() as Map)['estadoAdopcion'] == 'Adoptado').toList();
          if (adoptadosDocs.isEmpty) return const SizedBox.shrink();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _sectionHeader('YA ENCONTRARON HOGAR 🏡',
                trailing: GestureDetector(
                  onTap: () => Navigator.push(ctx, MaterialPageRoute(
                      builder: (_) => TodosLosRescatesScreen(
                          filtroInicial: 'Adoptado', esAlbergue: true))),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2196F3).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: const Color(0xFF2196F3).withValues(alpha: 0.3)),
                    ),
                    child: const Text('Ver todos',
                        style: TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2196F3))),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: _adoptadosCarousel(adoptadosDocs),
            ),
          ]);
        }),

        const SizedBox(height: 20),
      ]),
    );
  }

  // ── Perfil tab ───────────────────────────────────────────────────────────────

  Widget _perfilTab(BuildContext ctx, String nombre, String tipo, String ciudad, String iniciales, String? fotoBase64) {
    final user = FirebaseAuth.instance.currentUser;
    return SingleChildScrollView(
      child: Column(children: [
        // Header verde — mismo estilo que el perfil de aliado
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0A5C40), Color(0xFF1F8A62)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
          ),
          child: Column(children: [
            GestureDetector(
              onTap: _uploadFotoPerfil,
              child: Stack(clipBehavior: Clip.none, children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 3),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: Builder(builder: (_) {
                    final fotoBytes = bytesFotoSegura(fotoBase64);
                    final ImageProvider? avatarImg = fotoBytes != null
                        ? MemoryImage(fotoBytes)
                        : user?.photoURL != null ? NetworkImage(user!.photoURL!) : null;
                    return CircleAvatar(
                      radius: 52,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      backgroundImage: avatarImg,
                      onBackgroundImageError: avatarImg != null ? (_, __) {} : null,
                      child: avatarImg == null
                          ? Text(iniciales, style: const TextStyle(color: Colors.white,
                              fontWeight: FontWeight.bold, fontSize: 32))
                          : null,
                    );
                  }),
                ),
                Positioned(
                  bottom: 0, right: 0,
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: appTeal,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                    ),
                    child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            Text(nombre, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                color: Colors.white), textAlign: TextAlign.center),
            if (tipo.isNotEmpty || ciudad.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text([if (tipo.isNotEmpty) tipo, if (ciudad.isNotEmpty) ciudad].join(' · '),
                  style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.8))),
            ],
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            _infoTile(Icons.email_outlined, 'Correo', user?.email ?? '-'),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(ctx,
                    MaterialPageRoute(builder: (_) => const AlberguePerfilScreen())),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Editar perfil del albergue'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: appTeal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final confirmar = await showDialog<bool>(
                    context: ctx,
                    builder: (_) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: const Text('Cerrar sesión'),
                      content: const Text('¿Seguro que quieres cerrar sesión?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Cerrar sesión',
                              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  );
                  if (confirmar == true) {
                    await GoogleSignIn().signOut();
                    await FirebaseAuth.instance.signOut();
                  }
                },
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Cerrar sesión'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade400,
                  side: BorderSide(color: Colors.red.shade200),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => launchUrl(
                Uri.parse('https://lunita486.github.io/Salva-Patitas/privacidad.html'),
                mode: LaunchMode.externalApplication,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.shield_outlined, size: 16, color: Colors.grey.shade500),
                  const SizedBox(width: 6),
                  Text('Política de Privacidad',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade500,
                          decoration: TextDecoration.underline)),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _infoTile(IconData icono, String label, String valor) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 6, offset: const Offset(0, 2))],
    ),
    child: Row(children: [
      Icon(icono, size: 20, color: appTeal),
      const SizedBox(width: 14),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500,
            fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(valor, style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.w500)),
      ]),
    ]),
  );

  // ── Widgets ──────────────────────────────────────────────────────────────────

  Widget _statCard(BuildContext ctx, int valor, String label, Color color,
      IconData icono, String? filtro) {
    return Expanded(
      child: GestureDetector(
        onTap: () => Navigator.push(ctx, MaterialPageRoute(
            builder: (_) => filtro != null
                ? TodosLosRescatesScreen(filtroInicial: filtro, esAlbergue: true)
                : const SolicitudesRescatistaScreen(esAlbergue: true))),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8, offset: const Offset(0, 3))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icono, size: 17, color: color),
            ),
            const SizedBox(height: 10),
            Text('$valor', style: TextStyle(fontSize: 28,
                fontWeight: FontWeight.bold, color: color, height: 1)),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontSize: 10,
                color: Colors.grey.shade500, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }

  Widget _subirLoteCard(BuildContext ctx) => GestureDetector(
    onTap: () => Navigator.push(ctx, MaterialPageRoute(
        builder: (_) => const SubirLoteScreen())),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A5C40), Color(0xFF1F8A62)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: const Color(0xFF1F8A62).withValues(alpha: 0.35),
            blurRadius: 12, offset: const Offset(0, 5))],
      ),
      child: Row(children: [
        // Icono apilado: 3 patitas
        SizedBox(
          width: 52, height: 52,
          child: Stack(children: [
            Positioned(left: 0, bottom: 0,
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.pets, color: Colors.white, size: 20),
              )),
            Positioned(right: 0, bottom: 0,
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.pets, color: Colors.white70, size: 15),
              )),
            Positioned(top: 0, left: 8,
              child: Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(7)),
                child: const Icon(Icons.pets, color: Colors.white54, size: 13),
              )),
          ]),
        ),
        const SizedBox(width: 16),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Subir lote',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold,
                    color: Colors.white)),
            SizedBox(height: 4),
            Text('Sube varios animales a la vez',
                style: TextStyle(fontSize: 12, color: Color(0xFFAAD9C4))),
          ]),
        ),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 14),
        ),
      ]),
    ),
  );

  Widget _subirUnoCard(BuildContext ctx) => GestureDetector(
    onTap: () => Navigator.push(ctx, MaterialPageRoute(
        builder: (_) => const SubirRescateScreen(esAlbergue: true))),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Row(children: [
        // Icono: patita + cámara
        Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: appTeal.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.pets, color: appTeal, size: 24),
          ),
          Positioned(right: -4, bottom: -4,
            child: Container(
              width: 20, height: 20,
              decoration: const BoxDecoration(
                  color: appOrange, shape: BoxShape.circle),
              child: const Icon(Icons.add, color: Colors.white, size: 14),
            )),
        ]),
        const SizedBox(width: 18),
        const Text('Subir uno solo',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A))),
        const Spacer(),
        Icon(Icons.chevron_right, color: Colors.grey.shade400),
      ]),
    ),
  );

  Widget _sectionHeader(String label, {Widget? trailing}) =>
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 16,
          fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
      ?trailing,
    ]);

  Widget _jauriaCarousel(List<QueryDocumentSnapshot> rescates) {
    if (rescates.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Aún no tienes animales publicados.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => const SubirRescateScreen(esAlbergue: true))),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(color: appTeal, borderRadius: BorderRadius.circular(20)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add, color: Colors.white, size: 16),
                SizedBox(width: 4),
                Text('Publicar el primero', style: TextStyle(color: Colors.white,
                    fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),
      );
    }
    final sorted = [...rescates]..sort((a, b) {
      final ta = ((a.data() as Map)['creadoEn'] as Timestamp?);
      final tb = ((b.data() as Map)['creadoEn'] as Timestamp?);
      if (ta == null || tb == null) return 0;
      return tb.compareTo(ta);
    });

    return SizedBox(
      height: 195,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: sorted.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (ctx, i) {
          final d              = sorted[i].data() as Map<String, dynamic>;
          final docId          = sorted[i].id;
          final nombre         = (d['nombre'] as String?)?.isNotEmpty == true
              ? d['nombre'] as String : 'Sin nombre';
          final especie        = d['especie']        as String? ?? 'Perro';
          final edad           = d['edad']           as String? ?? '';
          final fotoUrl        = d['fotoUrl']        as String?;
          final estadoAdopcion = d['estadoAdopcion'] as String? ?? 'Rescatado';
          final ts             = d['creadoEn']       as Timestamp?;
          final urgencia       = d['urgencia']       as String? ?? '';
          final emoji          = especie == 'Gato' ? '🐱' : '🐶';
          final esNuevo        = ts != null &&
              DateTime.now().difference(ts.toDate()).inHours < 24;
          final fechaStr       = ts != null ? _fmtFecha(ts.toDate()) : '';
          final estadoColor    = cicloColor(estadoAdopcion);

          return Container(
            width: 128,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6, offset: const Offset(0, 2))],
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(children: [
              Column(children: [
                Expanded(
                  child: fotoUrl != null
                    ? FotoUrl(
                        url: fotoUrl,
                        width: double.infinity,
                        fallback: Container(
                            width: double.infinity,
                            color: const Color(0xFFD8F0E4),
                            child: Center(child: Text(emoji,
                                style: const TextStyle(fontSize: 36)))),
                      )
                    : Container(
                        width: double.infinity,
                        color: const Color(0xFFD8F0E4),
                        child: Center(child: Text(emoji,
                            style: const TextStyle(fontSize: 36)))),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(nombre,
                        style: const TextStyle(fontSize: 12,
                            fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      [if (edad.isNotEmpty) edad, if (fechaStr.isNotEmpty) fechaStr]
                          .join(' · '),
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    // ── Chip de estado tappable ──────────────────
                    GestureDetector(
                      onTap: estadoAdopcion == 'Fallecido' ? null : () => showModalBottomSheet(
                        context: ctx,
                        shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                        builder: (_) => CambiarEstadoSheet(
                          docId: docId,
                          estadoActual: estadoAdopcion,
                          nombre: nombre,
                          adoptanteIdEnProceso: d['adoptanteIdEnProceso'] as String?,
                        ),
                      ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: estadoColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: estadoColor.withValues(alpha: 0.35)),
                        ),
                        child: Row(children: [
                          Expanded(
                            child: Text(estadoAdopcion,
                                style: TextStyle(fontSize: 9,
                                    fontWeight: FontWeight.w700, color: estadoColor),
                                overflow: TextOverflow.ellipsis),
                          ),
                          Icon(Icons.expand_more, size: 11, color: estadoColor),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ]),
              if (urgencia == 'Alta')
                Positioned(top: 6, left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                        color: const Color(0xFFD32F2F),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Text('URGENTE',
                        style: TextStyle(fontSize: 9,
                            fontWeight: FontWeight.w700, color: Colors.white)),
                  )),
              if (esNuevo)
                Positioned(top: 6, right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: appOrange, borderRadius: BorderRadius.circular(8)),
                    child: const Text('Nuevo',
                        style: TextStyle(fontSize: 9,
                            fontWeight: FontWeight.w700, color: Colors.white)),
                  )),
            ]),
          );
        },
      ),
    );
  }

  Widget _adoptadosCarousel(List<QueryDocumentSnapshot> docs) {
    final sorted = [...docs]..sort((a, b) {
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
          final d         = sorted[i].data() as Map<String, dynamic>;
          final nombre    = (d['nombre'] as String?)?.isNotEmpty == true
              ? d['nombre'] as String : 'Sin nombre';
          final especie   = d['especie']    as String? ?? 'Perro';
          final fotoUrl   = d['fotoUrl']    as String?;
          final emoji     = especie == 'Gato' ? '🐱' : '🐶';

          return Container(
            width: 120,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6, offset: const Offset(0, 2))],
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(children: [
              Column(children: [
                Expanded(
                  child: fotoUrl != null
                    ? FotoUrl(
                        url: fotoUrl,
                        width: double.infinity,
                        fallback: Container(
                            width: double.infinity,
                            color: const Color(0xFFD8F0E4),
                            child: Center(child: Text(emoji,
                                style: const TextStyle(fontSize: 32)))),
                      )
                    : Container(
                        width: double.infinity,
                        color: const Color(0xFFD8F0E4),
                        child: Center(child: Text(emoji,
                            style: const TextStyle(fontSize: 32)))),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                  child: Text(nombre,
                      style: const TextStyle(fontSize: 12,
                          fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
              Positioned(top: 6, right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                      color: const Color(0xFF2196F3),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Text('🏠',
                      style: TextStyle(fontSize: 10)),
                )),
            ]),
          );
        },
      ),
    );
  }

  String _fmtFecha(DateTime d) {
    const m = ['ene','feb','mar','abr','may','jun',
                'jul','ago','sep','oct','nov','dic'];
    return '${d.day} ${m[d.month - 1]}';
  }

  // ── Bottom nav ───────────────────────────────────────────────────────────────

  Widget _bottomNav(int pendientes) {
    final items = [
      _NavItem(Icons.dashboard_outlined,  Icons.dashboard,  'Panel'),
      _NavItem(Icons.pets_outlined,       Icons.pets,       'Jauría'),
      _NavItem(Icons.assignment_outlined, Icons.assignment, 'Solicitudes',
          badge: pendientes),
    ];
    // 'Perfil' se agrega al final, después de 'Chats' — mismo orden que en
    // el resto de la app (Rescatista, Aliado): Perfil siempre es el último ícono.
    const perfilIndex = 3;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12, offset: const Offset(0, -2))],
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
                    Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const TodosLosRescatesScreen(esAlbergue: true)));
                  } else if (i == 2) {
                    Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const SolicitudesRescatistaScreen(esAlbergue: true)));
                  } else {
                    setState(() => _nav = i);
                  }
                },
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Stack(clipBehavior: Clip.none, children: [
                    Icon(active ? item.iconActive : item.icon,
                        color: active ? appTeal : Colors.grey.shade400, size: 24),
                    if (item.badge > 0)
                      Positioned(top: -4, right: -6,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                          decoration: const BoxDecoration(
                              color: appOrange, shape: BoxShape.circle),
                          child: Text(
                            item.badge > 9 ? '9+' : '${item.badge}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 9,
                                color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        )),
                  ]),
                  const SizedBox(height: 4),
                  Text(item.label,
                      style: TextStyle(fontSize: 10,
                          color: active ? appTeal : Colors.grey.shade400,
                          fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
                ]),
              );
              }),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('chats')
                    .where('rescatistaId', isEqualTo: _uid).snapshots(),
                builder: (_, snap) {
                  final unread = (snap.data?.docs ?? []).where((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    final creadoPor = d['creadoPor'] as String? ?? 'rescatista';
                    if (creadoPor != 'albergue') return false;
                    return ((d['noLeidosRescatista'] as int?) ?? 0) > 0;
                  }).length;
                  return GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const AdoptanteChatsScreen(esRescatista: true, esAlbergue: true))),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Stack(clipBehavior: Clip.none, children: [
                        Icon(Icons.chat_bubble_outline,
                            color: Colors.grey.shade400, size: 24),
                        if (unread > 0)
                          Positioned(top: -4, right: -6,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                              decoration: const BoxDecoration(
                                  color: appOrange, shape: BoxShape.circle),
                              child: Text(
                                unread > 9 ? '9+' : '$unread',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 9,
                                    color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            )),
                      ]),
                      const SizedBox(height: 4),
                      Text('Chats', style: TextStyle(fontSize: 10,
                          color: Colors.grey.shade400)),
                    ]),
                  );
                },
              ),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const AliadosScreen(esRescatista: true))),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.store_outlined, color: Colors.grey.shade400, size: 24),
                  const SizedBox(height: 4),
                  Text('Negocios', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                ]),
              ),
              Builder(builder: (_) {
                final active = _nav == perfilIndex;
                return GestureDetector(
                  onTap: () => setState(() => _nav = perfilIndex),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(active ? Icons.person : Icons.person_outline,
                        color: active ? appTeal : Colors.grey.shade400, size: 24),
                    const SizedBox(height: 4),
                    Text('Perfil', style: TextStyle(fontSize: 10,
                        color: active ? appTeal : Colors.grey.shade400,
                        fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
                  ]),
                );
              }),
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




