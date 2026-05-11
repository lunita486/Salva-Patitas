import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  Future<void> _continuar() async {
    setState(() => _guardando = true);
    await FirebaseFirestore.instance
        .collection('usuarios').doc(widget.user.uid).set({
      'nombre':   widget.user.displayName ?? 'Usuario',
      'email':    widget.user.email,
      'foto':     widget.user.photoURL,
      'roles':    _roles.toList(),
      'ciudad':   'Medellín',
      'creadoEn': FieldValue.serverTimestamp(),
    });
  }

  Widget _rolCard(String rol, String emoji, String descripcion) {
    final sel = _roles.contains(rol);
    return GestureDetector(
      onTap: () => setState(() {
        if (sel && _roles.length > 1) _roles.remove(rol);
        else _roles.add(rol);
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF1A1A1A) : Colors.white.withOpacity(0.8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: sel ? const Color(0xFF1A1A1A) : Colors.grey.shade300, width: 2),
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rol[0].toUpperCase() + rol.substring(1),
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold,
                    color: sel ? Colors.white : const Color(0xFF1A1A1A))),
            const SizedBox(height: 4),
            Text(descripcion, style: TextStyle(fontSize: 13,
                color: sel ? Colors.white70 : Colors.grey.shade600)),
          ])),
          if (sel) const Icon(Icons.check_circle, color: appTeal, size: 24),
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
        CustomPaint(painter: LeafPainter()),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 40),
              Text('Hola, $nombre 👋',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A))),
              const SizedBox(height: 8),
              Text('¿Cómo quieres usar Salva Patitas?',
                  style: TextStyle(fontSize: 15, color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              Text('Puedes elegir los dos',
                  style: const TextStyle(fontSize: 13, color: appTeal, fontWeight: FontWeight.w600)),
              const SizedBox(height: 32),
              _rolCard('adoptante',  '🏠', 'Encuentra tu compañero perfecto y solicita adopciones'),
              const SizedBox(height: 12),
              _rolCard('rescatista', '🦺', 'Publica animales rescatados y gestiona solicitudes'),
              const SizedBox(height: 12),
              _rolCard('institucion','🏛️', 'Refugios, fundaciones y perreras con muchos animales'),
              const SizedBox(height: 12),
              _rolCard('padrino',    '💛', 'Financia gastos de animales sin necesidad de adoptarlos'),
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
