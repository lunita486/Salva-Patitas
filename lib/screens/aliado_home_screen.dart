import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import 'subir_servicio_screen.dart';

class AliadoHomeScreen extends StatefulWidget {
  const AliadoHomeScreen({super.key});
  @override
  State<AliadoHomeScreen> createState() => _AliadoHomeScreenState();
}

class _AliadoHomeScreenState extends State<AliadoHomeScreen> {
  int _nav = 0;
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

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
    await FirebaseFirestore.instance
        .collection('servicios').doc(docId)
        .update({'activo': !actual});
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
    if (ok == true) {
      await FirebaseFirestore.instance.collection('servicios').doc(docId).delete();
    }
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
          body: Stack(children: [
            const Positioned.fill(child: LeafOverlay()),
            SafeArea(
              child: _nav == 0
                  ? _panelTab(context, nombre, tipo, foto, iniciales)
                  : _perfilTab(context, nombre, tipo, foto, iniciales),
            ),
          ]),
          floatingActionButton: _nav == 0
              ? FloatingActionButton.extended(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SubirServicioScreen())),
                  backgroundColor: appTeal,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.add),
                  label: const Text('Nuevo servicio',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                )
              : null,
          bottomNavigationBar: _bottomNav(),
        );
      },
    );
  }

  // ── Panel de servicios ────────────────────────────────────────────────────

  Widget _panelTab(BuildContext ctx, String nombre, String tipo, String? foto, String iniciales) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('servicios')
          .where('aliadoId', isEqualTo: _uid)
          .orderBy('creadoEn', descending: true)
          .snapshots(),
      builder: (context, snap) {
        final docs    = snap.data?.docs ?? [];
        final activos = docs.where((d) => (d.data() as Map)['activo'] == true).length;

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 100),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Hero card
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
              child: Row(children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2.5),
                  ),
                  child: CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    backgroundImage: foto != null
                        ? MemoryImage(base64Decode(foto)) as ImageProvider
                        : null,
                    child: foto == null
                        ? Text(iniciales, style: const TextStyle(color: Colors.white,
                            fontWeight: FontWeight.bold, fontSize: 18))
                        : null,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Hola 👋', style: TextStyle(fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.75))),
                  const SizedBox(height: 2),
                  Text(nombre, style: const TextStyle(fontSize: 22,
                      fontWeight: FontWeight.bold, color: Colors.white),
                      overflow: TextOverflow.ellipsis),
                  if (tipo.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(tipo, style: TextStyle(fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.75))),
                  ],
                ])),
              ]),
            ),

            // Stats
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(children: [
                _statCard('$activos', 'Activos', appTeal),
                const SizedBox(width: 12),
                _statCard('${docs.length}', 'Total', const Color(0xFF444444)),
              ]),
            ),

            // Lista servicios
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Text('MIS SERVICIOS',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                      letterSpacing: 1.2, color: Colors.grey.shade500)),
            ),

            if (docs.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(children: [
                    Icon(Icons.spa_outlined, size: 52, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text('Aún no tenés servicios publicados',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
                    const SizedBox(height: 6),
                    Text('Tocá "Nuevo servicio" para agregar el primero',
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                  ]),
                ),
              )
            else
              ...docs.map((doc) {
                final d      = doc.data() as Map<String, dynamic>;
                final nombre = d['nombre']      as String? ?? '';
                final precio = d['precio']      as int?    ?? 0;
                final desc   = d['descripcion'] as String? ?? '';
                final activo = d['activo']      as bool?   ?? true;
                final cat    = d['categoria']   as String? ?? '';

                return Container(
                  margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(nombre, style: const TextStyle(fontSize: 15,
                          fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                      if (cat.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(cat, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                      ],
                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(desc, style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                      const SizedBox(height: 6),
                      Text('\$${_formatPrecio(precio)}',
                          style: const TextStyle(fontSize: 16,
                              fontWeight: FontWeight.bold, color: appTeal)),
                    ])),
                    Column(children: [
                      Switch(
                        value: activo,
                        onChanged: (_) => _toggleActivo(doc.id, activo),
                        activeThumbColor: appTeal,
                        activeTrackColor: appTeal.withValues(alpha: 0.5),
                      ),
                      GestureDetector(
                        onTap: () => _eliminarServicio(doc.id),
                        child: Icon(Icons.delete_outline,
                            size: 20, color: Colors.grey.shade400),
                      ),
                    ]),
                  ]),
                );
              }),
          ]),
        );
      },
    );
  }

  String _formatPrecio(int precio) {
    final s = precio.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  Widget _statCard(String valor, String label, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Text(valor, style: TextStyle(fontSize: 28,
            fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      ]),
    ),
  );

  // ── Perfil ─────────────────────────────────────────────────────────────────

  Widget _perfilTab(BuildContext ctx, String nombre, String tipo, String? foto, String iniciales) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        const SizedBox(height: 16),
        CircleAvatar(
          radius: 48,
          backgroundColor: appTeal.withValues(alpha: 0.15),
          backgroundImage: foto != null ? MemoryImage(base64Decode(foto)) as ImageProvider : null,
          child: foto == null
              ? Text(iniciales, style: const TextStyle(fontSize: 28,
                  fontWeight: FontWeight.bold, color: appTeal))
              : null,
        ),
        const SizedBox(height: 16),
        Text(nombre, style: const TextStyle(fontSize: 22,
            fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
        if (tipo.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(tipo, style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
        ],
        const SizedBox(height: 8),
        Text(email, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        const SizedBox(height: 32),
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
    );
  }

  // ── Bottom Nav ─────────────────────────────────────────────────────────────

  Widget _bottomNav() => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07),
          blurRadius: 12, offset: const Offset(0, -2))],
    ),
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _navItem(Icons.dashboard_outlined, Icons.dashboard, 'Panel', 0),
          _navItem(Icons.person_outline, Icons.person, 'Perfil', 1),
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
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 10,
            color: active ? appTeal : Colors.grey.shade400,
            fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
      ]),
    );
  }
}
