import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../theme.dart';

class SeleccionRolScreen extends StatefulWidget {
  final User user;
  const SeleccionRolScreen({super.key, required this.user});
  @override
  State<SeleccionRolScreen> createState() => _SeleccionRolScreenState();
}

class _SeleccionRolScreenState extends State<SeleccionRolScreen> {
  final Set<String> _roles = {'adoptante'};
  bool _guardando = false;

  Future<String> _detectarCiudad() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return '';
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

  Future<void> _continuar() async {
    setState(() => _guardando = true);
    try {
      final ciudad = await _detectarCiudad().timeout(
        const Duration(seconds: 5), onTimeout: () => '');
      await FirebaseFirestore.instance
          .collection('usuarios').doc(widget.user.uid).set({
        'nombre':   widget.user.displayName ?? 'Usuario',
        'email':    widget.user.email,
        'foto':     widget.user.photoURL,
        'roles':    _roles.toList(),
        'ciudad':   ciudad,
        'creadoEn': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      setState(() => _guardando = false);
    }
  }

  static const _rolesExclusivos = {'albergue', 'aliado'};

  void _toggleRol(String rol) {
    setState(() {
      if (_roles.contains(rol)) {
        if (_roles.length > 1) _roles.remove(rol);
      } else if (_rolesExclusivos.contains(rol)) {
        // Albergue y Aliado son exclusivos — limpian todo lo demás
        _roles
          ..clear()
          ..add(rol);
      } else {
        // Adoptante/Rescatista no pueden combinarse con roles exclusivos
        _roles.removeWhere((r) => _rolesExclusivos.contains(r));
        _roles.add(rol);
      }
    });
  }

  Widget _rolCard({
    required String rol,
    required IconData icono,
    required Color iconoBg,
    required Color iconoColor,
    required String nombre,
    required String descripcion,
    String? badgeLabel,
    Color? badgeBg,
  }) {
    final sel = _roles.contains(rol);
    return GestureDetector(
      onTap: () => _toggleRol(rol),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: sel ? appTeal : Colors.grey.shade200,
            width: sel ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: sel ? appTeal.withValues(alpha: 0.15) : iconoBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icono, color: sel ? appTeal : iconoColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(nombre,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A))),
              if (badgeLabel != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeBg ?? appTeal,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(badgeLabel,
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                          color: Colors.white, letterSpacing: 0.4)),
                ),
              ],
            ]),
            const SizedBox(height: 3),
            Text(descripcion,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ])),
          const SizedBox(width: 8),
          if (sel)
            const Icon(Icons.check_circle_rounded, color: appTeal, size: 22)
          else
            Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 22),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nombre = widget.user.displayName?.split(' ').first ?? 'Usuario';
    return Scaffold(
      backgroundColor: appBg,
      body: Stack(fit: StackFit.expand, children: [
        const LeafOverlay(),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 40),
              Text('Hola, $nombre 👋',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A))),
              const SizedBox(height: 6),
              Text('¿CÓMO VAS A ENTRAR?',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                      letterSpacing: 1.5, color: Colors.grey.shade500)),
              const SizedBox(height: 28),
              _rolCard(
                rol: 'adoptante',
                icono: Icons.pets,
                iconoBg: const Color(0xFFD8F0E4),
                iconoColor: appTeal,
                nombre: 'Adoptante',
                descripcion: 'Quiero adoptar un animal',
              ),
              const SizedBox(height: 10),
              _rolCard(
                rol: 'rescatista',
                icono: Icons.eco_outlined,
                iconoBg: const Color(0xFFE8F5E9),
                iconoColor: const Color(0xFF388E3C),
                nombre: 'Rescatista',
                descripcion: 'Rescato animales por mi cuenta',
              ),
              const SizedBox(height: 10),
              _rolCard(
                rol: 'albergue',
                icono: Icons.account_balance_outlined,
                iconoBg: const Color(0xFFF5F5F5),
                iconoColor: const Color(0xFF757575),
                nombre: 'Albergue',
                descripcion: 'Represento un albergue oficial',
                badgeLabel: 'VERIFICACIÓN OFICIAL',
                badgeBg: const Color(0xFF1F8A62),
              ),
              const SizedBox(height: 10),
              _rolCard(
                rol: 'aliado',
                icono: Icons.storefront_outlined,
                iconoBg: const Color(0xFFEDE7F6),
                iconoColor: const Color(0xFF7C4DFF),
                nombre: 'Aliado',
                descripcion: 'Soy veterinario, tienda o servicio',
                badgeLabel: 'NEGOCIO ALIADO',
                badgeBg: const Color(0xFFE91E63),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _guardando ? null : _continuar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A1A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _guardando
                      ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                          SizedBox(width: 12),
                          Text('Creando tu perfil...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ])
                      : const Text('Continuar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 32),
            ]),
          ),
        ),
      ]),
    );
  }
}
