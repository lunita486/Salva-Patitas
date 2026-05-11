import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../theme.dart';

class PerfilRescatistaScreen extends StatelessWidget {
  const PerfilRescatistaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final nombre = user?.displayName ?? 'Rescatista';
    final foto   = user?.photoURL;
    final email  = user?.email ?? '';

    return Scaffold(
      backgroundColor: appBg,
      body: Stack(fit: StackFit.expand, children: [
        CustomPaint(painter: LeafPainter()),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
                const Spacer(),
              ]),
              const SizedBox(height: 8),
              foto != null
                ? CircleAvatar(backgroundImage: NetworkImage(foto), radius: 44)
                : CircleAvatar(backgroundColor: appTeal, radius: 44,
                    child: Text(nombre[0].toUpperCase(),
                        style: const TextStyle(fontSize: 36, color: Colors.white, fontWeight: FontWeight.bold))),
              const SizedBox(height: 14),
              Text(nombre, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
              const SizedBox(height: 4),
              Text(email, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(color: appTeal.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                child: const Text('Rescatista 🦺', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: appTeal)),
              ),
              const SizedBox(height: 32),
              // Stats
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('rescates')
                    .where('rescatistaId', isEqualTo: user?.uid ?? '').snapshots(),
                builder: (context, snap) {
                  final total = snap.data?.docs.length ?? 0;
                  return Row(children: [
                    _statTile('$total', 'Animales\nrescatados', appTeal),
                    const SizedBox(width: 12),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('solicitudes')
                          .where('rescatistaId', isEqualTo: user?.uid ?? '')
                          .where('estado', isEqualTo: 'aprobada').snapshots(),
                      builder: (context, snap2) {
                        final aprobadas = snap2.data?.docs.length ?? 0;
                        return _statTile('$aprobadas', 'Adopciones\naprobadas', appOrange);
                      },
                    ),
                  ]);
                },
              ),
              const SizedBox(height: 32),
              // Cerrar sesión
              GestureDetector(
                onTap: () => showDialog(context: context, builder: (dlgCtx) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: const Text('Cerrar sesión'),
                  content: const Text('¿Seguro que quieres cerrar sesión?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Cancelar')),
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(dlgCtx);
                        await GoogleSignIn().signOut();
                        await FirebaseAuth.instance.signOut();
                        if (context.mounted) {
                          Navigator.of(context).popUntil((route) => route.isFirst);
                        }
                      },
                      child: const Text('Cerrar sesión', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                )),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.logout, color: Colors.red.shade400, size: 18),
                    const SizedBox(width: 8),
                    Text('Cerrar sesión', style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _statTile(String n, String lbl, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)]),
      child: Column(children: [
        Text(n, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(lbl, style: TextStyle(fontSize: 12, color: Colors.grey.shade500, height: 1.3), textAlign: TextAlign.center),
      ]),
    ),
  );
}
