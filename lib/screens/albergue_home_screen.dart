import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import 'subir_rescate_screen.dart';
import 'mis_rescates_screen.dart';
import 'solicitudes_rescatista_screen.dart';

class AlbergueHomeScreen extends StatefulWidget {
  const AlbergueHomeScreen({super.key});
  @override
  State<AlbergueHomeScreen> createState() => _AlbergueHomeScreenState();
}

class _AlbergueHomeScreenState extends State<AlbergueHomeScreen> {
  int _nav = 0;
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  Stream<QuerySnapshot> get _rescatesStream => FirebaseFirestore.instance
      .collection('rescates')
      .where('rescatistaId', isEqualTo: _uid)
      .snapshots();

  Stream<QuerySnapshot> get _solicitudesStream => FirebaseFirestore.instance
      .collection('solicitudes')
      .where('rescatistaId', isEqualTo: _uid)
      .where('estado', isEqualTo: 'pendiente')
      .snapshots();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('usuarios').doc(_uid).snapshots(),
      builder: (context, userSnap) {
        final data         = userSnap.data?.data() as Map<String, dynamic>? ?? {};
        final nombre       = data['albergueNombre']    as String? ?? 'Albergue';
        final tipo         = data['albergueTipo']      as String? ?? '';
        final capacidad    = (data['capacidadTotal']   as int?)   ?? 0;
        final iniciales    = nombre.trim().split(' ')
            .take(2).map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();

        return Scaffold(
          backgroundColor: appBg,
          body: StreamBuilder<QuerySnapshot>(
            stream: _rescatesStream,
            builder: (context, rSnap) {
              final rescates   = rSnap.data?.docs ?? [];
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
                    ? _panel(context, nombre, tipo, iniciales,
                        capacidad, enCuidado, enAdopcion, adoptados, totalActivos, pct, rescates)
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

  Widget _panel(BuildContext ctx, String nombre, String tipo, String iniciales,
      int capacidad, int enCuidado, int enAdopcion,
      int adoptados, int totalActivos, double pct,
      List<QueryDocumentSnapshot> rescates) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Header
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Hola,',
                style: TextStyle(fontSize: 15, color: Color(0xFF555555))),
            const SizedBox(height: 2),
            Text(nombre,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A))),
            if (tipo.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(children: [
                Icon(Icons.location_on, size: 13, color: Colors.grey.shade500),
                const SizedBox(width: 3),
                Text('$tipo · Medellín',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              ]),
            ],
          ]),
          CircleAvatar(
            radius: 26,
            backgroundColor: appTeal,
            child: Text(iniciales,
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ]),

        // Barra de capacidad
        if (capacidad > 0) ...[
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('$totalActivos / $capacidad animales',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600)),
            Text('${(pct * 100).round()}%',
                style: const TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w700, color: appTeal)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 7,
              backgroundColor: Colors.white.withValues(alpha: 0.6),
              valueColor: AlwaysStoppedAnimation<Color>(
                pct >= 0.9 ? Colors.red.shade400 : appTeal),
            ),
          ),
        ],

        const SizedBox(height: 20),

        // Stats
        Row(children: [
          _statCard('$enCuidado',  'En cuidado',  appTeal,              flex: 2),
          const SizedBox(width: 10),
          _statCard('$enAdopcion', 'En adopción', const Color(0xFFE65100), flex: 2),
          const SizedBox(width: 10),
          _statCard('$adoptados',  'Adoptados',   const Color(0xFF1A1A1A), flex: 2),
        ]),

        const SizedBox(height: 20),

        // CTAs
        _subirLoteCard(ctx),
        const SizedBox(height: 10),
        _subirUnoCard(ctx),

        const SizedBox(height: 28),

        // Solicitudes
        StreamBuilder<QuerySnapshot>(
          stream: _solicitudesStream,
          builder: (context, snap) {
            final count = snap.data?.docs.length ?? 0;
            return _sectionHeader(
              'ESPERAN RESPUESTA', 'Solicitudes',
              trailing: count > 0
                ? GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const SolicitudesRescatistaScreen())),
                    child: Text('$count abiertas →',
                        style: const TextStyle(fontSize: 13,
                            fontWeight: FontWeight.w600, color: appOrange)),
                  )
                : GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const SolicitudesRescatistaScreen())),
                    child: const Text('Ver todas',
                        style: TextStyle(fontSize: 13,
                            fontWeight: FontWeight.w600, color: appTeal)),
                  ),
            );
          },
        ),

        const SizedBox(height: 20),

        // Jauría
        _sectionHeader(
          'LA JAURÍA', 'Tus animales activos',
          trailing: GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => const TodosLosRescatesScreen())),
            child: const Text('Gestionar',
                style: TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w600, color: appTeal)),
          ),
        ),
        const SizedBox(height: 12),
        _jauriaCarousel(rescates),
      ]),
    );
  }

  // ── Widgets ──────────────────────────────────────────────────────────────────

  Widget _statCard(String valor, String label, Color color, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(valor, style: TextStyle(fontSize: 26,
              fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11,
              color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }

  Widget _subirLoteCard(BuildContext ctx) => GestureDetector(
    onTap: () => Navigator.push(ctx, MaterialPageRoute(
        builder: (_) => const SubirRescateScreen())),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: appDark, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: appTeal.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.upload_rounded, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Subir lote',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                    color: Colors.white)),
            SizedBox(height: 4),
            Text('Sube varios animales a la vez',
                style: TextStyle(fontSize: 12, color: Color(0xFF8ABEAA))),
          ]),
        ),
        const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 16),
      ]),
    ),
  );

  Widget _subirUnoCard(BuildContext ctx) => GestureDetector(
    onTap: () => Navigator.push(ctx, MaterialPageRoute(
        builder: (_) => const SubirRescateScreen())),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: appTeal.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.add, color: appTeal, size: 22),
        ),
        const SizedBox(width: 14),
        const Text('Subir uno solo',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A))),
        const Spacer(),
        Icon(Icons.chevron_right, color: Colors.grey.shade400),
      ]),
    ),
  );

  Widget _sectionHeader(String label, String title, {Widget? trailing}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
            letterSpacing: 1.2, color: Colors.grey.shade500)),
        ?trailing,
      ]),
      const SizedBox(height: 4),
      Text(title, style: const TextStyle(fontSize: 22,
          fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
    ]);

  Widget _jauriaCarousel(List<QueryDocumentSnapshot> rescates) {
    if (rescates.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text('Aún no tienes animales publicados.',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
      );
    }
    final sorted = [...rescates]..sort((a, b) {
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
        itemBuilder: (_, i) {
          final d            = sorted[i].data() as Map<String, dynamic>;
          final nombre       = (d['nombre'] as String?)?.isNotEmpty == true
              ? d['nombre'] as String : 'Sin nombre';
          final especie      = d['especie']    as String? ?? 'Perro';
          final edad         = d['edad']       as String? ?? '';
          final fotoBase64   = d['fotoBase64'] as String?;
          final ts           = d['creadoEn']   as Timestamp?;
          final emoji        = especie == 'Gato' ? '🐱' : '🐶';
          final esNuevo      = ts != null &&
              DateTime.now().difference(ts.toDate()).inHours < 24;
          final fechaStr     = ts != null ? _fmtFecha(ts.toDate()) : '';

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
                  child: fotoBase64 != null
                    ? Image.memory(base64Decode(fotoBase64),
                        width: double.infinity, fit: BoxFit.cover)
                    : Container(
                        width: double.infinity,
                        color: const Color(0xFFD8F0E4),
                        child: Center(child: Text(emoji,
                            style: const TextStyle(fontSize: 36)))),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
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
                  ]),
                ),
              ]),
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

  String _fmtFecha(DateTime d) {
    const m = ['ene','feb','mar','abr','may','jun',
                'jul','ago','sep','oct','nov','dic'];
    return '${d.day} ${m[d.month - 1]}';
  }

  // ── Bottom nav ───────────────────────────────────────────────────────────────

  Widget _bottomNav(int pendientes) {
    final items = [
      _NavItem(Icons.dashboard_outlined,   Icons.dashboard,          'Panel'),
      _NavItem(Icons.upload_file_outlined, Icons.upload_file,        'Subir lote'),
      _NavItem(Icons.pets_outlined,        Icons.pets,               'Jauría'),
      _NavItem(Icons.assignment_outlined,  Icons.assignment,         'Solicitudes',
          badge: pendientes),
      _NavItem(Icons.person_outline,       Icons.person,             'Perfil'),
    ];

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
            children: List.generate(items.length, (i) {
              final item = items[i];
              final active = _nav == i;
              return GestureDetector(
                onTap: () {
                  if (i == 1) {
                    Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const SubirRescateScreen()));
                  } else if (i == 2) {
                    Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const TodosLosRescatesScreen()));
                  } else if (i == 3) {
                    Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const SolicitudesRescatistaScreen()));
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
                          width: 16, height: 16,
                          decoration: const BoxDecoration(
                              color: appOrange, shape: BoxShape.circle),
                          child: Center(
                            child: Text(
                              item.badge > 9 ? '9+' : '${item.badge}',
                              style: const TextStyle(fontSize: 9,
                                  color: Colors.white, fontWeight: FontWeight.bold),
                            ),
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
