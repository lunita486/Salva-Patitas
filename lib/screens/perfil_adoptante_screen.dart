import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../data/auth_helper.dart';
import '../data/usuarios_repository.dart';
import '../data/firestore_resiliencia.dart';
import 'mis_solicitudes_screen.dart';
import 'tipo_animal_screen.dart';

class PerfilAdoptanteScreen extends StatelessWidget {
  const PerfilAdoptanteScreen({super.key});

  Future<String> _detectarCiudad() async {
    try {
      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }
      if (permiso == LocationPermission.denied ||
          permiso == LocationPermission.deniedForever) return '';
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.low));
      final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (marks.isEmpty) return '';
      final p = marks.first;
      return p.locality?.isNotEmpty == true ? p.locality! : (p.administrativeArea ?? '');
    } catch (_) {
      return '';
    }
  }

  Widget _settingsCard(List<Widget> items) => Container(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
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
          Expanded(child: Text(label, style: TextStyle(fontSize: 15, color: color ?? appInk))),
          Icon(Icons.chevron_right, size: 20, color: Colors.grey.shade400),
        ]),
      ),
    );

  Future<void> _gestionarRoles(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
    final roles = List<String>.from((doc.data()?['roles'] as List?) ?? ['adoptante']);
    if (!context.mounted) return;

    final seleccion = await showModalBottomSheet<List<String>>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _RolesSheet(rolesActuales: roles),
    );
    if (seleccion == null || seleccion.isEmpty) return;
    // guardarConAviso, no un await directo suelto (lo que había acá
    // antes, sin try/catch ni aviso de ningún tipo): la hoja ya se cerró
    // para cuando esto corre, así que si la escritura fallaba de verdad
    // (ej. offline, o un permission-denied que ni siquiera reintenta más
    // que una vez), la persona quedaba creyendo que cambió de rol —
    // desbloqueando o escondiendo partes enteras de la app — sin que
    // nada se hubiera guardado. Hallazgo de auditoría de código.
    final resultado = await guardarConAviso(
        () => UsuariosRepository().actualizarRoles(uid, seleccion));
    if (!context.mounted) return;
    switch (resultado) {
      case ResultadoGuardado.confirmado:
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Roles actualizados'), backgroundColor: msgExito));
      case ResultadoGuardado.siguePendiente:
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Esto está tardando. Se va a guardar solo apenas vuelva la señal.'),
            backgroundColor: msgAdvertencia));
      case ResultadoGuardado.fallo:
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo guardar. Revisá tu conexión e intentá de nuevo.'),
            backgroundColor: msgError));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appBg,
      body: Stack(fit: StackFit.expand, children: [
        const LeafOverlay(),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Header
              Row(children: [
                Tooltip(
                  message: 'Volver',
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back_ios_new, size: 20, color: appInk),
                  ),
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
                  // AvatarPersona (theme.dart), no un CircleAvatar armado a
                  // mano — antes, si la foto de perfil de Google fallaba al
                  // cargar (sin señal, link vencido), se veía un círculo
                  // gris vacío en vez de caer a la inicial, justo en el
                  // propio perfil de la persona. Hallazgo de auditoría de
                  // código.
                  AvatarPersona(
                    fotoUrl: foto,
                    inicial: inicial,
                    radius: 32,
                    backgroundColor: appOrange,
                    textColor: Colors.white,
                  ),
                  const SizedBox(width: 16),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(nombre, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                        color: appInk)),
                  const SizedBox(height: 4),
                  Row(children: [
                    FutureBuilder<String>(
                      future: _detectarCiudad(),
                      builder: (_, snap) {
                        // También con ciudad vacía ('' cuando el GPS falla o
                        // está bloqueado): sin este guard quedaba el pin y el
                        // separador "·" flotando sin texto.
                        if (!snap.hasData || snap.data!.isEmpty) return const SizedBox.shrink();
                        return Row(children: [
                          Icon(Icons.location_on, size: 13, color: Colors.grey.shade500),
                          const SizedBox(width: 2),
                          Text(snap.data!,
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                          const SizedBox(width: 6),
                          Text('·', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
                          const SizedBox(width: 6),
                        ]);
                      },
                    ),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('favoritos')
                          .where('adoptanteId', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
                          .snapshots(),
                      builder: (_, snap) {
                        final count = snap.data?.docs.length ?? 0;
                        return Row(children: [
                          Icon(Icons.favorite_border, size: 13, color: Colors.grey.shade500),
                          const SizedBox(width: 2),
                          Text('$count favorito${count == 1 ? "" : "s"}',
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                        ]);
                      },
                    ),
                  ]),
                  ]),
                ]);
              }),
              const SizedBox(height: 28),
              // Configuración
              const Text('CONFIGURACIÓN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  letterSpacing: 1.2, color: appTeal)),
              const SizedBox(height: 8),
              const Text('Preferencias', style: TextStyle(fontSize: 24,
                  fontWeight: FontWeight.bold, color: appInk, fontFamily: 'Baloo2')),
              const SizedBox(height: 16),
              _settingsCard([
                _settingsRow('Mis solicitudes', Icons.assignment_outlined,
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const MisSolicitudesScreen()))),
                _settingsRow('Tipo de animal preferido', Icons.pets, last: true,
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const TipoAnimalScreen()))),
              ]),
              const SizedBox(height: 12),
              _settingsCard([
                _settingsRow('Gestionar mis roles', Icons.switch_account_outlined,
                    last: true,
                    onTap: () => _gestionarRoles(context)),
              ]),
              const SizedBox(height: 12),
              _settingsCard([
                _settingsRow('Política de Privacidad', Icons.shield_outlined, last: true,
                    onTap: () => launchUrl(
                      Uri.parse('https://lunita486.github.io/Salva-Patitas/privacidad.html'),
                      mode: LaunchMode.externalApplication,
                    )),
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
                            final ok = await cerrarSesion();
                            if (context.mounted) {
                              if (ok) {
                                Navigator.of(context).popUntil((route) => route.isFirst);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                    backgroundColor: msgError,
                                    content: Text('Esperá unos segundos e intentá de nuevo.')));
                              }
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
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
        const SizedBox(height: 20),
        _rolTile('adoptante', '🐾 Adoptante', 'Busco animales para adoptar'),
        const SizedBox(height: 10),
        _rolTile('rescatista', '🦺 Rescatista', 'Rescato y publico animales'),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _roles.isNotEmpty
                ? () => Navigator.pop(context, _roles)
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: appTeal,
              foregroundColor: Colors.white,
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
                color: activo ? appTeal : appInk)),
            const SizedBox(height: 2),
            Text(subtitulo, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ])),
          if (activo) const Icon(Icons.check_circle, color: appTeal, size: 22),
        ]),
      ),
    );
  }
}
