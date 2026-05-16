import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';

class SolicitudRescatistaScreen extends StatefulWidget {
  const SolicitudRescatistaScreen({super.key});
  @override
  State<SolicitudRescatistaScreen> createState() => _SolicitudRescatistaScreenState();
}

class _SolicitudRescatistaScreenState extends State<SolicitudRescatistaScreen> {
  final _nombreCtl  = TextEditingController();
  final _barrioCtl  = TextEditingController();
  bool? _experiencia;
  int   _paso       = 1;
  bool  _enviando   = false;

  @override
  void dispose() {
    _nombreCtl.dispose();
    _barrioCtl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_nombreCtl.text.trim().isEmpty || _barrioCtl.text.trim().isEmpty || _experiencia == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor completa todos los campos')));
      return;
    }
    setState(() => _enviando = true);
    await FirebaseFirestore.instance.collection('solicitudes_rescatista').add({
      'nombre':      _nombreCtl.text.trim(),
      'barrio':      _barrioCtl.text.trim(),
      'experiencia': _experiencia,
      'estado':      'pendiente',
      'creadoEn':    FieldValue.serverTimestamp(),
    });
    if (mounted) setState(() { _enviando = false; _paso = 2; });
  }

  Widget _campo(String label, TextEditingController ctl, String hint) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      RichText(text: TextSpan(
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A)),
        children: [TextSpan(text: label), const TextSpan(text: ' *', style: TextStyle(color: appTeal))],
      )),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.88),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
        child: TextField(
          controller: ctl,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appBg,
      body: Stack(fit: StackFit.expand, children: [
        const LeafOverlay(),
        SafeArea(
          child: _paso == 1 ? _paso1() : _paso2(),
        ),
      ]),
    );
  }

  Widget _paso1() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GestureDetector(
        onTap: () => Navigator.pop(context),
        child: const Icon(Icons.arrow_back_ios_new, size: 20, color: Color(0xFF1A1A1A)),
      ),
      const SizedBox(height: 24),
      const Text('ÚNETE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          letterSpacing: 1.2, color: appTeal)),
      const SizedBox(height: 6),
      const Text('Vuélvete rescatista\nverificado', style: TextStyle(fontSize: 28,
          fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
      const SizedBox(height: 8),
      Text('Completa estos datos y revisaremos tu solicitud en 24-48 horas.',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
      const SizedBox(height: 28),
      _campo('Nombre completo', _nombreCtl, 'ej. Ana Restrepo'),
      const SizedBox(height: 20),
      _campo('Barrio en Medellín', _barrioCtl, 'ej. Laureles'),
      const SizedBox(height: 20),
      RichText(text: const TextSpan(
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A)),
        children: [TextSpan(text: '¿Ya tienes experiencia rescatando?'),
          TextSpan(text: ' *', style: TextStyle(color: appTeal))],
      )),
      const SizedBox(height: 10),
      Row(children: [
        _chip('Sí', _experiencia == true, () => setState(() => _experiencia = true)),
        const SizedBox(width: 10),
        _chip('No', _experiencia == false, () => setState(() => _experiencia = false)),
      ]),
      const SizedBox(height: 36),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _enviando ? null : _enviar,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A1A1A),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: _enviando
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Enviar solicitud', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
    ]),
  );

  Widget _chip(String label, bool sel, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: sel ? const Color(0xFF1A1A1A) : Colors.white.withOpacity(0.88),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: sel ? const Color(0xFF1A1A1A) : Colors.grey.shade300),
      ),
      child: Text(label, style: TextStyle(
          color: sel ? Colors.white : Colors.grey.shade700,
          fontWeight: FontWeight.w600)),
    ),
  );

  Widget _paso2() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 80, height: 80,
          decoration: const BoxDecoration(color: appTeal, shape: BoxShape.circle),
          child: const Icon(Icons.check, color: Colors.white, size: 40),
        ),
        const SizedBox(height: 24),
        const Text('¡Solicitud enviada!', style: TextStyle(fontSize: 24,
            fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
        const SizedBox(height: 12),
        Text('El equipo de Salva Patitas revisará tu solicitud en 24-48 horas. '
            'Te notificaremos cuando sea aprobada.',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            textAlign: TextAlign.center),
        const SizedBox(height: 36),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A1A1A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Entendido', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    ),
  );
}
