import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../theme.dart';
import 'mis_solicitudes_screen.dart';
import 'notificaciones_screen.dart';
import 'ubicacion_alcance_screen.dart';
import 'tipo_animal_screen.dart';
import 'solicitud_rescatista_screen.dart';

class PerfilAdoptanteScreen extends StatelessWidget {
  const PerfilAdoptanteScreen({super.key});

  Widget _settingsCard(List<Widget> items) => Container(
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.75),
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
    ),
    child: Column(children: items),
  );

  Widget _settingsRow(String label, IconData icon, {Color? color, VoidCallback? onTap, bool last = false}) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: Colors.grey.shade100)),
        ),
        child: Row(children: [
          Icon(icon, size: 20, color: color ?? Colors.grey.shade600),
          const SizedBox(width: 14),
          Expanded(child: Text(label, style: TextStyle(fontSize: 15, color: color ?? const Color(0xFF1A1A1A)))),
          Icon(Icons.chevron_right, size: 20, color: Colors.grey.shade400),
        ]),
      ),
    );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appBg,
      body: Stack(fit: StackFit.expand, children: [
        CustomPaint(painter: LeafPainter()),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Header
              Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.arrow_back_ios_new, size: 20, color: Color(0xFF1A1A1A)),
                ),
                const SizedBox(width: 12),
                const Text('PERFIL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    letterSpacing: 1.2, color: appTeal)),
              ]),
              const SizedBox(height: 16),
              // Avatar + nombre + stats
              Builder(builder: (context) {
                final user = FirebaseAuth.instance.currentUser;
                final nombre = user?.displayName ?? 'Tú';
                final foto   = user?.photoURL;
                final inicial = nombre.isNotEmpty ? nombre[0].toUpperCase() : 'T';
                return Row(children: [
                  foto != null
                      ? CircleAvatar(backgroundImage: NetworkImage(foto), radius: 32)
                      : CircleAvatar(backgroundColor: appOrange, radius: 32,
                          child: Text(inicial, style: const TextStyle(color: Colors.white,
                              fontSize: 24, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 16),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(nombre, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A))),
                  const SizedBox(height: 4),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('favoritos').snapshots(),
                    builder: (_, snap) {
                      final count = snap.data?.docs.length ?? 0;
                      return Row(children: [
                        Icon(Icons.location_on, size: 13, color: Colors.grey.shade500),
                        const SizedBox(width: 2),
                        Text('Medellín · $count favorito${count == 1 ? "" : "s"}',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                      ]);
                    },
                  ),
                  ]),
                ]);
              }),
              const SizedBox(height: 24),
              // CTA rescatista
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('¿RESCATAS ANIMALES?', style: TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w700, letterSpacing: 1.2, color: appTeal)),
                  const SizedBox(height: 6),
                  const Text('Vuélvete rescatista verificado',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                  const SizedBox(height: 6),
                  Text('Publica animales, gestiona solicitudes y construye tu historial público.',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const SolicitudRescatistaScreen())),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1A1A1A),
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    child: const Text('Empezar solicitud', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
              const SizedBox(height: 28),
              // Configuración
              const Text('CONFIGURACIÓN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  letterSpacing: 1.2, color: appTeal)),
              const SizedBox(height: 8),
              const Text('Preferencias', style: TextStyle(fontSize: 24,
                  fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
              const SizedBox(height: 16),
              _settingsCard([
                _settingsRow('Mis solicitudes', Icons.pets,
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const MisSolicitudesScreen()))),
                _settingsRow('Notificaciones', Icons.notifications_outlined,
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const NotificacionesScreen()))),
                _settingsRow('Ubicación y alcance', Icons.location_on_outlined,
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const UbicacionAlcanceScreen()))),
                _settingsRow('Tipo de animal preferido', Icons.pets, last: true,
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const TipoAnimalScreen()))),
              ]),
              const SizedBox(height: 12),
              _settingsCard([
                _settingsRow('Cerrar sesión', Icons.logout,
                    color: Colors.red.shade400, last: true,
                    onTap: () => showDialog(context: context, builder: (_) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: const Text('Cerrar sesión'),
                      content: const Text('¿Seguro que quieres cerrar sesión?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context),
                            child: const Text('Cancelar')),
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            await GoogleSignIn().signOut();
                            await FirebaseAuth.instance.signOut();
                            if (context.mounted) {
                              Navigator.of(context).popUntil((route) => route.isFirst);
                            }
                          },
                          child: const Text('Cerrar sesión', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ))),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}
