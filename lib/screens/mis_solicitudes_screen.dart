import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';

class MisSolicitudesScreen extends StatelessWidget {
  const MisSolicitudesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: appBg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 20, 12),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              const Expanded(child: Text('Mis solicitudes',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)))),
            ]),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('solicitudes')
                  .where('adoptanteId', isEqualTo: uid)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: appTeal));
                }
                final docs = [...(snap.data?.docs ?? [])]..sort((a, b) {
                    final ta = (a.data() as Map)['creadoEn'] as Timestamp?;
                    final tb = (b.data() as Map)['creadoEn'] as Timestamp?;
                    if (ta == null || tb == null) return 0;
                    return tb.compareTo(ta);
                  });
                if (docs.isEmpty) {
                  return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.pets_outlined, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('Aún no has enviado solicitudes',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
                      const SizedBox(height: 8),
                      Text('Cuando te interese un animal, toca\n"Quiero adoptarlo"',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
                    ]),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final d       = docs[i].data() as Map<String, dynamic>;
                    final animal  = d['animalNombre'] as String? ?? 'Animal';
                    final estado  = d['estado']       as String? ?? 'pendiente';
                    final motivo  = d['motivoRechazo'] as String?;
                    final ts      = d['creadoEn'] as Timestamp?;
                    final tiempo  = ts != null ? _formatFecha(ts.toDate()) : '';

                    final estadoColor = estado == 'aprobada'
                        ? const Color(0xFF1F8A62)
                        : estado == 'rechazada'
                            ? const Color(0xFFB71C1C)
                            : const Color(0xFFE65100);
                    final estadoLabel = estado == 'aprobada' ? '✅ Aprobada'
                        : estado == 'rechazada' ? '❌ Rechazada'
                        : '⏳ Pendiente';

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Container(width: 40, height: 40,
                            decoration: BoxDecoration(color: appTeal.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.pets, color: appTeal, size: 22)),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Para $animal',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                            Text(tiempo, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                          ])),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: estadoColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: estadoColor.withOpacity(0.4)),
                            ),
                            child: Text(estadoLabel,
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: estadoColor)),
                          ),
                        ]),
                        if (estado == 'rechazada' && motivo != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Motivo del rechazo',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.red.shade400)),
                              const SizedBox(height: 4),
                              Text(motivo, style: TextStyle(fontSize: 13, color: Colors.red.shade700, height: 1.4)),
                            ]),
                          ),
                        ],
                        if (estado == 'aprobada') ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD8F0E4),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('¡El rescatista aprobó tu solicitud! Escríbele por el chat para coordinar.',
                                style: TextStyle(fontSize: 13, color: Colors.green.shade800, height: 1.4)),
                          ),
                        ],
                      ]),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  String _formatFecha(DateTime fecha) {
    final diff = DateTime.now().difference(fecha);
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}min';
    if (diff.inHours < 24)   return 'hace ${diff.inHours}h';
    return 'hace ${diff.inDays}d';
  }
}
