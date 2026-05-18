import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';

class AlberguePerfilScreen extends StatefulWidget {
  const AlberguePerfilScreen({super.key});
  @override
  State<AlberguePerfilScreen> createState() => _AlberguePerfilScreenState();
}

class _AlberguePerfilScreenState extends State<AlberguePerfilScreen> {
  final _nombreCtl    = TextEditingController();
  final _capacidadCtl = TextEditingController();
  final _direccionCtl = TextEditingController();
  String _tipo        = 'Fundación';
  bool   _guardando   = false;

  static const _tipos = ['Centro municipal', 'Fundación', 'ONG', 'Privado'];

  bool get _completo =>
      _nombreCtl.text.trim().isNotEmpty &&
      _capacidadCtl.text.trim().isNotEmpty;

  Future<void> _guardar() async {
    if (!_completo) return;
    setState(() => _guardando = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await FirebaseFirestore.instance.collection('usuarios').doc(uid).update({
      'albergueNombre':    _nombreCtl.text.trim(),
      'albergueTipo':      _tipo,
      'capacidadTotal':    int.tryParse(_capacidadCtl.text.trim()) ?? 0,
      'albergueDireccion': _direccionCtl.text.trim(),
    });
    // AuthWrapper detecta el cambio y navega a HomeScreen automáticamente
  }

  @override
  void dispose() {
    _nombreCtl.dispose();
    _capacidadCtl.dispose();
    _direccionCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appBg,
      body: Stack(fit: StackFit.expand, children: [
        const LeafOverlay(),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 40),

              // Header
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF1F8A62),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.account_balance_outlined,
                    color: Colors.white, size: 28),
              ),
              const SizedBox(height: 20),
              const Text('Configura tu albergue',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A))),
              const SizedBox(height: 6),
              Text('Esta información aparecerá en tu perfil oficial.',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
              const SizedBox(height: 32),

              // Nombre
              _label('NOMBRE DEL ALBERGUE *'),
              const SizedBox(height: 8),
              _campo(_nombreCtl, 'ej. Centro de Bienestar Animal La Perla', autofocus: true),
              const SizedBox(height: 24),

              // Tipo
              _label('TIPO DE ORGANIZACIÓN'),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8,
                children: _tipos.map((t) {
                  final sel = t == _tipo;
                  return GestureDetector(
                    onTap: () => setState(() => _tipo = t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(
                        color: sel ? const Color(0xFF1A1A1A) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: sel ? const Color(0xFF1A1A1A) : Colors.grey.shade300,
                        ),
                      ),
                      child: Text(t, style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : Colors.grey.shade700,
                      )),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Capacidad
              _label('CAPACIDAD TOTAL DE ANIMALES *'),
              const SizedBox(height: 8),
              _campo(_capacidadCtl, 'ej. 220',
                  tipo: TextInputType.number,
                  formato: [FilteringTextInputFormatter.digitsOnly]),
              const SizedBox(height: 6),
              Text('Cuántos animales puede albergar tu organización.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              const SizedBox(height: 24),

              // Dirección
              _label('BARRIO O DIRECCIÓN'),
              const SizedBox(height: 8),
              _campo(_direccionCtl, 'ej. Laureles, Medellín'),
              const SizedBox(height: 36),

              // Botón
              ListenableBuilder(
                listenable: Listenable.merge([_nombreCtl, _capacidadCtl]),
                builder: (_, _) => SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (_completo && !_guardando) ? _guardar : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1A1A),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: _guardando
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Crear perfil del albergue',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _label(String t) => Text(t,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          letterSpacing: 1.1, color: Colors.grey.shade500));

  Widget _campo(
    TextEditingController ctl,
    String hint, {
    TextInputType tipo = TextInputType.text,
    List<TextInputFormatter> formato = const [],
    bool autofocus = false,
  }) =>
      TextField(
        controller: ctl,
        keyboardType: tipo,
        inputFormatters: formato,
        autofocus: autofocus,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF1F8A62), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      );
}
