import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import '../services/notificaciones_service.dart';
import 'adoptante_chats_screen.dart';
import 'subir_servicio_screen.dart';
import 'aliado_perfil_screen.dart';

class AliadoHomeScreen extends StatefulWidget {
  const AliadoHomeScreen({super.key});
  @override
  State<AliadoHomeScreen> createState() => _AliadoHomeScreenState();
}

class _AliadoHomeScreenState extends State<AliadoHomeScreen> {
  int _nav = 0;
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  static const _catEmoji = {
    'Baño y peluquería': '🛁',
    'Veterinaria':       '🩺',
    'Tienda':            '🛍️',
    'Adiestramiento':    '🎓',
    'Transporte':        '🚗',
    'Otro':              '🐾',
  };

  static const _catColor = {
    'Baño y peluquería': Color(0xFF1565C0),
    'Veterinaria':       Color(0xFFB71C1C),
    'Tienda':            Color(0xFF6A1B9A),
    'Adiestramiento':    Color(0xFFF57F17),
    'Transporte':        Color(0xFFE65100),
    'Otro':              Color(0xFF1F8A62),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        NotificacionesService.guardarToken();
        NotificacionesService.escucharEnPrimerPlano(context);
      }
    });
  }

  Future<void> _cambiarRolDebug() async {
    final opciones = <String, List<String>>{
      'Solo Adoptante':         ['adoptante'],
      'Solo Rescatista':        ['rescatista'],
      'Adoptante + Rescatista': ['adoptante', 'rescatista'],
      'Albergue':               ['albergue'],
      'Aliado':                 ['aliado'],
    };
    final sel = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('🛠 Cambiar rol (DEBUG)'),
        children: opciones.entries.map((e) => SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, e.value),
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(e.key)),
        )).toList(),
      ),
    );
    if (sel == null || !mounted) return;
    await FirebaseFirestore.instance.collection('usuarios').doc(_uid).update({'roles': sel});
  }

  Future<void> _cerrarSesion() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Seguro que querés cerrar sesión?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: appTeal, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (ok == true) await FirebaseAuth.instance.signOut();
  }

  Future<void> _toggleActivo(String docId, bool actual) async {
    await FirebaseFirestore.instance.collection('servicios').doc(docId).update({'activo': !actual});
  }

  Future<void> _eliminarServicio(String docId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar servicio'),
        content: const Text('¿Seguro que querés eliminar este servicio?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok == true) await FirebaseFirestore.instance.collection('servicios').doc(docId).delete();
  }

  String _fmt(int precio) {
    final s = precio.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('usuarios').doc(_uid).snapshots(),
      builder: (context, userSnap) {
        final data      = userSnap.data?.data() as Map<String, dynamic>? ?? {};
        final nombre    = data['aliadoNombre'] as String? ?? 'Mi negocio';
        final tipo      = data['aliadoTipo']   as String? ?? '';
        final foto      = data['fotoBase64']   as String?;
        final iniciales = nombre.trim().split(' ')
            .take(2).map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();

        return Scaffold(
          backgroundColor: appBg,
          floatingActionButton: kDebugMode
              ? FloatingActionButton.small(
                  heroTag: 'debug_rol',
                  onPressed: _cambiarRolDebug,
                  backgroundColor: Colors.purple.shade100,
                  elevation: 4,
                  child: Icon(Icons.developer_mode, color: Colors.purple.shade700),
                )
              : null,
          bottomNavigationBar: _bottomNav(),
          body: Stack(children: [
            const Positioned.fill(child: LeafOverlay()),
            SafeArea(
              child: IndexedStack(
                index: _nav,
                children: [
                  _panelTab(nombre, tipo, foto, iniciales),
                  _catalogoTab(nombre, foto, iniciales),
                  _perfilTab(nombre, tipo, foto, iniciales),
                ],
              ),
            ),
          ]),
        );
      },
    );
  }

  // ── Panel ────────────────────────────────────────────────────────────────────

  Widget _panelTab(String nombre, String tipo, String? foto, String iniciales) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('servicios').where('aliadoId', isEqualTo: _uid).snapshots(),
      builder: (context, svcSnap) {
        final servicios = svcSnap.data?.docs ?? [];
        final activos   = servicios.where((d) => (d.data() as Map)['activo'] == true).length;

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('chats')
              .where('rescatistaId', isEqualTo: _uid)
              .where('tipoSolicitud', isEqualTo: 'consulta_aliado')
              .snapshots(),
          builder: (context, chatSnap) {
            final chats       = (chatSnap.data?.docs ?? []).where((d) {
              final data = d.data() as Map<String, dynamic>;
              return ((data['ultimoMensaje'] as String?) ?? '').isNotEmpty;
            }).toList();
            final chatsNuevos = chats.where((d) {
              final data = d.data() as Map<String, dynamic>;
              return ((data['noLeidosRescatista'] as int?) ?? 0) > 0;
            }).length;

            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // ── Header ──────────────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF0A5C40), Color(0xFF1F8A62)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(children: [
                    // Avatar grande
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 3),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 16, offset: const Offset(0, 6))],
                      ),
                      child: CircleAvatar(
                        radius: 52,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        backgroundImage: foto != null
                            ? MemoryImage(base64Decode(foto)) as ImageProvider : null,
                        child: foto == null
                            ? Text(iniciales, style: const TextStyle(color: Colors.white,
                                fontWeight: FontWeight.bold, fontSize: 32))
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(nombre,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold,
                              color: Colors.white),
                          textAlign: TextAlign.center),
                      const SizedBox(width: 8),
                      Container(width: 10, height: 10,
                          decoration: const BoxDecoration(
                              color: Color(0xFF4ADE80), shape: BoxShape.circle)),
                    ]),
                    if (tipo.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(tipo, style: TextStyle(fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.75))),
                    ],
                  ]),
                ),

                // ── Stats ────────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: Row(children: [
                    _statCard('$activos', 'Servicios\nactivos',
                        const Color(0xFFD8F0E4), appTeal, Icons.spa_outlined,
                        onTap: () => setState(() => _nav = 1)),
                    const SizedBox(width: 12),
                    _statCard('${servicios.length}', 'Servicios\ntotales',
                        Colors.white, const Color(0xFF444444), Icons.list_alt_outlined,
                        onTap: () => setState(() => _nav = 1)),
                    const SizedBox(width: 12),
                    _statCard('$chatsNuevos', 'Mensajes\nnuevos',
                        const Color(0xFFFFF0E6), appOrange, Icons.chat_bubble_outline,
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => const AdoptanteChatsScreen(esRescatista: true, soloConsultas: true)))),
                  ]),
                ),

                // ── Acceso rápido ─────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                  child: Text('ACCIONES RÁPIDAS',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          letterSpacing: 1.2, color: Colors.grey.shade500)),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    _quickAction(Icons.add_circle_outline, 'Nuevo\nservicio', appTeal, () {
                      Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const SubirServicioScreen()));
                    }),
                    const SizedBox(width: 12),
                    _quickAction(Icons.list_alt_outlined, 'Ver\nservicios', const Color(0xFF444444), () {
                      setState(() => _nav = 1);
                    }),
                    const SizedBox(width: 12),
                    _quickAction(Icons.chat_bubble_outline, 'Ver\nchats', appOrange, () {
                      Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const AdoptanteChatsScreen(esRescatista: true, soloConsultas: true)));
                    }),
                  ]),
                ),

                // ── Últimos chats ─────────────────────────────────────────────
                if (chats.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('CONVERSACIONES RECIENTES',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                letterSpacing: 1.2, color: Colors.grey.shade500)),
                        GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => const AdoptanteChatsScreen(esRescatista: true, soloConsultas: true))),
                          child: const Text('Ver todas',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                  color: appTeal)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...chats.take(3).map((doc) {
                    final d        = doc.data() as Map<String, dynamic>;
                    final quien    = d['adoptanteNombre'] as String? ?? 'Usuario';
                    final ultimo   = d['ultimoMensaje']   as String? ?? '';
                    final hora     = d['ultimaHora']      as String? ?? '';
                    final noLeidos = (d['noLeidosRescatista'] as int?) ?? 0;
                    final ini      = quien.isNotEmpty ? quien[0].toUpperCase() : 'U';
                    return Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 6, offset: const Offset(0, 2))],
                      ),
                      child: Row(children: [
                        CircleAvatar(radius: 20, backgroundColor: appTeal.withValues(alpha: 0.12),
                            child: Text(ini, style: const TextStyle(color: appTeal,
                                fontWeight: FontWeight.bold, fontSize: 14))),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(quien, style: const TextStyle(fontSize: 13,
                              fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
                          if (ultimo.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(ultimo, style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ])),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          if (hora.isNotEmpty)
                            Text(hora, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                          if (noLeidos > 0) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: const BoxDecoration(color: appOrange, shape: BoxShape.circle),
                              child: Text('$noLeidos', style: const TextStyle(fontSize: 11,
                                  color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ]),
                      ]),
                    );
                  }),
                ],
              ]),
            );
          },
        );
      },
    );
  }

  Widget _statCard(String valor, String label, Color bg, Color color, IconData icon, {VoidCallback? onTap}) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: color.withValues(alpha: 0.7)),
          const SizedBox(height: 8),
          Text(valor, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.75), height: 1.3)),
        ]),
      ),
    ),
  );

  Widget _quickAction(IconData icon, String label, Color color, VoidCallback onTap) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color, height: 1.2)),
        ]),
      ),
    ),
  );

  // ── Catálogo ─────────────────────────────────────────────────────────────────

  Widget _catalogoTab(String nombre, String? foto, String iniciales) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('servicios').where('aliadoId', isEqualTo: _uid).snapshots(),
      builder: (context, snap) {
        final docs = (snap.data?.docs ?? [])
          ..sort((a, b) {
            final tA = (a.data() as Map)['creadoEn'] as Timestamp?;
            final tB = (b.data() as Map)['creadoEn'] as Timestamp?;
            if (tA == null) return 1;
            if (tB == null) return -1;
            return tB.compareTo(tA);
          });

        return Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('MIS SERVICIOS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    letterSpacing: 1.2, color: appTeal)),
                const Text('Servicios activos', style: TextStyle(fontSize: 26,
                    fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
              ])),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const SubirServicioScreen())),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(color: appTeal, borderRadius: BorderRadius.circular(20)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text('Nuevo', style: TextStyle(color: Colors.white,
                        fontSize: 13, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ]),
          ),

          // Lista
          Expanded(
            child: docs.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.spa_outlined, size: 56, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text('Sin servicios publicados',
                        style: TextStyle(fontSize: 15, color: Colors.grey.shade500)),
                    const SizedBox(height: 8),
                    Text('Toca "Nuevo" para agregar el primero',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
                  ]))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    itemCount: docs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final doc    = docs[i];
                      final d      = doc.data() as Map<String, dynamic>;
                      final sNombre = d['nombre']      as String? ?? '';
                      final precio  = d['precio']      as int?    ?? 0;
                      final desc    = d['descripcion'] as String? ?? '';
                      final activo  = d['activo']      as bool?   ?? true;
                      final cat     = d['categoria']   as String? ?? '';
                      final catColor = _catColor[cat] ?? appTeal;
                      final catEmoji = _catEmoji[cat] ?? '🐾';

                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 8, offset: const Offset(0, 2))],
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Container(
                              width: 48, height: 48,
                              decoration: BoxDecoration(
                                color: catColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(child: Text(catEmoji,
                                  style: const TextStyle(fontSize: 24))),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(sNombre, style: const TextStyle(fontSize: 15,
                                  fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                              if (desc.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(desc, style: TextStyle(fontSize: 12,
                                    color: Colors.grey.shade500),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            ])),
                            const SizedBox(width: 12),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text('\$${_fmt(precio)}', style: TextStyle(fontSize: 17,
                                  fontWeight: FontWeight.bold, color: catColor)),
                              const SizedBox(height: 6),
                              // Toggle
                              GestureDetector(
                                onTap: () => _toggleActivo(doc.id, activo),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 44, height: 24,
                                  decoration: BoxDecoration(
                                    color: activo ? appTeal : Colors.grey.shade300,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: AnimatedAlign(
                                    duration: const Duration(milliseconds: 200),
                                    alignment: activo ? Alignment.centerRight : Alignment.centerLeft,
                                    child: Padding(
                                      padding: const EdgeInsets.all(2),
                                      child: Container(
                                        width: 20, height: 20,
                                        decoration: const BoxDecoration(
                                            color: Colors.white, shape: BoxShape.circle),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ]),
                          ]),
                          const SizedBox(height: 12),
                          Row(children: [
                            _miniBtn(Icons.edit_outlined, 'Editar',
                                Colors.grey.shade600, Colors.grey.shade50,
                                Colors.grey.shade200, () => Navigator.push(context,
                                    MaterialPageRoute(builder: (_) =>
                                        SubirServicioScreen(docId: doc.id, data: d)))),
                            const SizedBox(width: 8),
                            _miniBtn(Icons.delete_outline, 'Eliminar',
                                Colors.red.shade400, Colors.red.shade50,
                                Colors.red.shade100, () => _eliminarServicio(doc.id)),
                          ]),
                        ]),
                      );
                    },
                  ),
          ),
        ]);
      },
    );
  }

  Widget _miniBtn(IconData icon, String label, Color fg, Color bg, Color border,
      VoidCallback onTap) =>
    Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border)),
          child: Icon(icon, size: 16, color: fg),
        ),
      ),
    );

  // ── Perfil ────────────────────────────────────────────────────────────────────

  Widget _perfilTab(String nombre, String tipo, String? foto, String iniciales) {
    return SingleChildScrollView(
      child: Column(children: [
        // Header verde
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
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 3),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: CircleAvatar(
                radius: 52,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                backgroundImage: foto != null
                    ? MemoryImage(base64Decode(foto)) as ImageProvider : null,
                child: foto == null
                    ? Text(iniciales, style: const TextStyle(color: Colors.white,
                        fontWeight: FontWeight.bold, fontSize: 32))
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            Text(nombre, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                color: Colors.white), textAlign: TextAlign.center),
            if (tipo.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(tipo, style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.8))),
            ],
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AliadoPerfilScreen())),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Editar perfil del negocio'),
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
                onPressed: _cerrarSesion,
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
          ]),
        ),
      ]),
    );
  }

  // ── Bottom Nav ───────────────────────────────────────────────────────────────

  Widget _bottomNav() => Container(
    decoration: BoxDecoration(color: Colors.white,
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07),
          blurRadius: 12, offset: const Offset(0, -2))]),
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _navItem(Icons.dashboard_outlined, Icons.dashboard, 'Panel', 0),
          _navItem(Icons.spa_outlined, Icons.spa, 'Servicios', 1),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('chats')
                .where('rescatistaId', isEqualTo: _uid)
                .where('tipoSolicitud', isEqualTo: 'consulta_aliado')
                .snapshots(),
            builder: (_, snap) {
              final unread = (snap.data?.docs ?? []).where((doc) {
                final d = doc.data() as Map<String, dynamic>;
                return ((d['noLeidosRescatista'] as int?) ?? 0) > 0;
              }).length;
              return _navTapBadge(Icons.chat_bubble_outline, Icons.chat_bubble, 'Chats', unread,
                () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const AdoptanteChatsScreen(esRescatista: true, soloConsultas: true))));
            },
          ),
          _navItem(Icons.person_outline, Icons.person, 'Perfil', 2),
        ]),
      ),
    ),
  );

  Widget _navItem(IconData icon, IconData iconActive, String label, int idx) {
    final active = _nav == idx;
    return GestureDetector(
      onTap: () => setState(() => _nav = idx),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(active ? iconActive : icon,
            color: active ? appTeal : Colors.grey.shade400, size: 24),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontSize: 10,
            color: active ? appTeal : Colors.grey.shade400,
            fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
      ]),
    );
  }

  Widget _navTapBadge(IconData icon, IconData iconActive, String label, int badge, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Stack(clipBehavior: Clip.none, children: [
          Icon(icon, color: Colors.grey.shade400, size: 24),
          if (badge > 0)
            Positioned(top: -4, right: -6,
              child: Container(
                width: 16, height: 16,
                decoration: const BoxDecoration(color: appOrange, shape: BoxShape.circle),
                child: Center(child: Text(badge > 9 ? '9+' : '$badge',
                    style: const TextStyle(fontSize: 9, color: Colors.white,
                        fontWeight: FontWeight.bold))),
              )),
        ]),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
      ]),
    );
  }
}
