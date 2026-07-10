import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../data/creator_role.dart';
import '../data/rescates_repository.dart';
import '../data/solicitudes_repository.dart';
import '../data/usuarios_repository.dart';

class PerfilRescatistaScreen extends StatelessWidget {
  const PerfilRescatistaScreen({super.key});

  Future<void> _gestionarRoles(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
    final roles = List<String>.from((doc.data()?['roles'] as List?) ?? ['rescatista']);
    if (!context.mounted) return;
    final seleccion = await showModalBottomSheet<List<String>>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _RolesSheet(rolesActuales: roles),
    );
    if (seleccion == null || seleccion.isEmpty) return;
    await UsuariosRepository().actualizarRoles(uid, seleccion);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final nombre = user?.displayName ?? 'Rescatista';
    final foto   = user?.photoURL;
    final email  = user?.email ?? '';

    return Scaffold(
      backgroundColor: appBg,
      body: Stack(fit: StackFit.expand, children: [
        const LeafOverlay(),
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
                    child: Text(nombre.isNotEmpty ? nombre[0].toUpperCase() : 'R',
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
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: RescatesRepository().misRescates(
                  uid: user?.uid ?? '', role: CreatorRole.rescatista,
                ),
                builder: (context, snap) {
                  final total = snap.data?.docs.length ?? 0;
                  return Row(children: [
                    _statTile('$total', 'Animales\nrescatados', appTeal),
                    const SizedBox(width: 12),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: SolicitudesRepository().paraOwner(
                        uid: user?.uid ?? '', role: CreatorRole.rescatista, estado: 'aprobada',
                      ),
                      builder: (context, snap2) {
                        final aprobadas = snap2.data?.docs.length ?? 0;
                        return _statTile('$aprobadas', 'Adopciones\naprobadas', appOrange);
                      },
                    ),
                  ]);
                },
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => _gestionarRoles(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    Icon(Icons.switch_account_outlined, color: appTeal, size: 20),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('Gestionar mis roles',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                    Icon(Icons.chevron_right, color: Colors.grey.shade400),
                  ]),
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
              const SizedBox(height: 16),
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

class _RolesSheet extends StatefulWidget {
  final List<String> rolesActuales;
  const _RolesSheet({required this.rolesActuales});
  @override
  State<_RolesSheet> createState() => _RolesSheetState();
}

class _RolesSheetState extends State<_RolesSheet> {
  late List<String> _roles;

  @override
  void initState() {
    super.initState();
    _roles = List.from(widget.rolesActuales);
  }

  void _toggle(String rol) {
    setState(() {
      if (_roles.contains(rol)) {
        if (_roles.length > 1) _roles.remove(rol);
      } else {
        _roles.add(rol);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        const Text('Mis roles', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text('Podés tener los dos roles al mismo tiempo',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        const SizedBox(height: 20),
        _rolTile('adoptante', '🐾 Adoptante', 'Busco animales para adoptar'),
        const SizedBox(height: 10),
        _rolTile('rescatista', '🦺 Rescatista', 'Rescato y publico animales'),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _roles.isNotEmpty ? () => Navigator.pop(context, _roles) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: appTeal, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: const Text('Guardar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }

  Widget _rolTile(String rol, String titulo, String subtitulo) {
    final activo = _roles.contains(rol);
    return GestureDetector(
      onTap: () => _toggle(rol),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: activo ? appTeal.withValues(alpha: 0.08) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: activo ? appTeal : Colors.grey.shade200, width: activo ? 2 : 1),
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                color: activo ? appTeal : const Color(0xFF1A1A1A))),
            const SizedBox(height: 2),
            Text(subtitulo, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ])),
          if (activo) const Icon(Icons.check_circle, color: appTeal, size: 22),
        ]),
      ),
    );
  }
}
