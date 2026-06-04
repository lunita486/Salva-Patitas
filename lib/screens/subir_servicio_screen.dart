import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';

class SubirServicioScreen extends StatefulWidget {
  const SubirServicioScreen({super.key});
  @override
  State<SubirServicioScreen> createState() => _SubirServicioScreenState();
}

class _SubirServicioScreenState extends State<SubirServicioScreen> {
  final _nombreCtl      = TextEditingController();
  final _precioCtl      = TextEditingController();
  final _descripcionCtl = TextEditingController();
  bool _guardando = false;

  static const _categorias = [
    ('Baño y peluquería', '🛁'),
    ('Veterinaria',       '🩺'),
    ('Tienda',            '🛍️'),
    ('Adiestramiento',    '🎓'),
    ('Transporte',        '🚗'),
    ('Otro',              '🐾'),
  ];

  String _categoriaSeleccionada = 'Baño y peluquería';

  bool get _completo =>
      _nombreCtl.text.trim().isNotEmpty &&
      _precioCtl.text.trim().isNotEmpty;

  Future<void> _guardar() async {
    if (!_completo) return;
    setState(() => _guardando = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await FirebaseFirestore.instance.collection('servicios').add({
      'aliadoId':    uid,
      'nombre':      _nombreCtl.text.trim(),
      'precio':      int.tryParse(_precioCtl.text.trim().replaceAll('.', '')) ?? 0,
      'descripcion': _descripcionCtl.text.trim(),
      'categoria':   _categoriaSeleccionada,
      'activo':      true,
      'creadoEn':    FieldValue.serverTimestamp(),
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _nombreCtl.dispose();
    _precioCtl.dispose();
    _descripcionCtl.dispose();
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
              const SizedBox(height: 20),
              Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 12),
                const Text('Nuevo servicio',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A))),
              ]),
              const SizedBox(height: 28),

              // Categoría
              const Text('Categoría',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                      color: Color(0xFF444444))),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: _categorias.map((cat) {
                  final sel = _categoriaSeleccionada == cat.$1;
                  return GestureDetector(
                    onTap: () => setState(() => _categoriaSeleccionada = cat.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel ? appTeal : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: sel ? appTeal : Colors.grey.shade300),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(cat.$2, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Text(cat.$1,
                            style: TextStyle(fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: sel ? Colors.white : const Color(0xFF444444))),
                      ]),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              _campo(_nombreCtl, 'Nombre del servicio', Icons.spa_outlined),
              const SizedBox(height: 16),
              TextFormField(
                controller: _precioCtl,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Precio',
                  prefixIcon: const Icon(Icons.attach_money),
                  prefixText: '\$ ',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descripcionCtl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Descripción (opcional)',
                  alignLabelWithHint: true,
                  prefixIcon: const Icon(Icons.notes_outlined),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 36),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_completo && !_guardando) ? _guardar : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: appTeal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: _guardando
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Publicar servicio',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 32),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _campo(TextEditingController ctl, String label, IconData icon) =>
      TextFormField(
        controller: ctl,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
        ),
      );
}
