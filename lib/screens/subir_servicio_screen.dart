import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';

class SubirServicioScreen extends StatefulWidget {
  final String? docId;
  final Map<String, dynamic>? data;
  const SubirServicioScreen({super.key, this.docId, this.data});
  @override
  State<SubirServicioScreen> createState() => _SubirServicioScreenState();
}

class _SubirServicioScreenState extends State<SubirServicioScreen> {
  final _nombreCtl      = TextEditingController();
  final _precioCtl      = TextEditingController();
  final _descripcionCtl = TextEditingController();
  bool _guardando = false;

  bool get _esEdicion => widget.docId != null;

  static const _categorias = [
    ('Baño y peluquería', '🛁'),
    ('Veterinaria',       '🩺'),
    ('Tienda',            '🛍️'),
    ('Adiestramiento',    '🎓'),
    ('Transporte',        '🚗'),
    ('Otro',              '🐾'),
  ];

  static const _catColor = {
    'Baño y peluquería': Color(0xFF42A5F5),
    'Veterinaria':       Color(0xFFEF5350),
    'Tienda':            Color(0xFFAB47BC),
    'Adiestramiento':    Color(0xFFFFCA28),
    'Transporte':        Color(0xFFFF7043),
    'Otro':              Color(0xFF26A69A),
  };

  String _categoriaSeleccionada = 'Baño y peluquería';

  @override
  void initState() {
    super.initState();
    if (widget.data != null) {
      _nombreCtl.text      = widget.data!['nombre']      as String? ?? '';
      _precioCtl.text      = '${widget.data!['precio']  as int?    ?? 0}';
      _descripcionCtl.text = widget.data!['descripcion'] as String? ?? '';
      _categoriaSeleccionada = widget.data!['categoria'] as String? ?? 'Baño y peluquería';
    }
  }

  bool get _completo =>
      _nombreCtl.text.trim().isNotEmpty &&
      _precioCtl.text.trim().isNotEmpty;

  Future<void> _guardar() async {
    if (!_completo) return;
    setState(() => _guardando = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final payload = {
      'nombre':      _nombreCtl.text.trim(),
      'precio':      int.tryParse(_precioCtl.text.trim().replaceAll('.', '')) ?? 0,
      'descripcion': _descripcionCtl.text.trim(),
      'categoria':   _categoriaSeleccionada,
    };
    if (_esEdicion) {
      await FirebaseFirestore.instance
          .collection('servicios').doc(widget.docId).update(payload);
    } else {
      await FirebaseFirestore.instance.collection('servicios').add({
        ...payload,
        'aliadoId': uid,
        'activo':   true,
        'creadoEn': FieldValue.serverTimestamp(),
      });
    }
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
    final catColor = _catColor[_categoriaSeleccionada] ?? appTeal;
    final catEmoji = _categorias
        .firstWhere((c) => c.$1 == _categoriaSeleccionada,
            orElse: () => _categorias.first)
        .$2;

    return Scaffold(
      backgroundColor: appBg,
      body: Column(children: [
        // Header compacto
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 8, 16, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [catColor, Color.lerp(catColor, Colors.white, 0.25)!],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back_ios_new,
                    color: Colors.white, size: 15),
              ),
            ),
            const SizedBox(width: 12),
            Text(catEmoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_esEdicion ? 'Editar servicio' : 'Nuevo servicio',
                  style: const TextStyle(fontSize: 18,
                      fontWeight: FontWeight.bold, color: Colors.white)),
              Text(_categoriaSeleccionada,
                  style: TextStyle(fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.85))),
            ]),
          ]),
        ),

        // Contenido
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // Grid de categorías
              const Text('Categoría',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                      color: Color(0xFF444444))),
              const SizedBox(height: 8),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.05,
                children: _categorias.map((cat) {
                  final sel = _categoriaSeleccionada == cat.$1;
                  final color = _catColor[cat.$1] ?? appTeal;
                  return GestureDetector(
                    onTap: () => setState(() => _categoriaSeleccionada = cat.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      decoration: BoxDecoration(
                        color: sel ? color.withValues(alpha: 0.1) : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: sel ? color : Colors.grey.shade200,
                          width: sel ? 2 : 1,
                        ),
                        boxShadow: sel ? [
                          BoxShadow(color: color.withValues(alpha: 0.2),
                              blurRadius: 8, offset: const Offset(0, 3)),
                        ] : [],
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(cat.$2, style: const TextStyle(fontSize: 26)),
                        const SizedBox(height: 5),
                        Text(cat.$1,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                                color: sel ? color : const Color(0xFF777777))),
                      ]),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 28),

              // Nombre
              _label('Nombre del servicio'),
              const SizedBox(height: 8),
              _campo(_nombreCtl, 'ej. Baño completo con secado', Icons.spa_outlined),
              const SizedBox(height: 20),

              // Precio
              _label('Precio'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _precioCtl,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: '0',
                  prefixText: '\$ ',
                  prefixStyle: TextStyle(fontSize: 16,
                      fontWeight: FontWeight.w600, color: catColor),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: catColor, width: 2)),
                ),
              ),
              const SizedBox(height: 20),

              // Descripción
              _label('Descripción (opcional)'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descripcionCtl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Contá qué incluye el servicio...',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: catColor, width: 2)),
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
              const SizedBox(height: 36),

              // Botón
              SizedBox(
                width: double.infinity,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    gradient: _completo && !_guardando
                        ? LinearGradient(colors: [
                            Color.lerp(catColor, Colors.black, 0.15)!,
                            catColor,
                          ])
                        : LinearGradient(colors: [
                            Colors.grey.shade300,
                            Colors.grey.shade300,
                          ]),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ElevatedButton(
                    onPressed: (_completo && !_guardando) ? _guardar : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white54,
                      disabledBackgroundColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: _guardando
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(_esEdicion ? 'Guardar cambios' : 'Publicar servicio',
                            style: const TextStyle(fontSize: 16,
                                fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
          color: Color(0xFF444444)));

  Widget _campo(TextEditingController ctl, String hint, IconData icon) =>
      TextFormField(
        controller: ctl,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          prefixIcon: Icon(icon, size: 20),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                  color: _catColor[_categoriaSeleccionada] ?? appTeal,
                  width: 2)),
        ),
      );
}
