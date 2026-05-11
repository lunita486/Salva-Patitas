import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../theme.dart';

class EditarRescateScreen extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;
  const EditarRescateScreen({super.key, required this.docId, required this.data});
  @override
  State<EditarRescateScreen> createState() => _EditarRescateScreenState();
}

class _EditarRescateScreenState extends State<EditarRescateScreen> {
  late TextEditingController _nombreCtl;
  late TextEditingController _descCtl;
  late TextEditingController _lugarCtl;
  late String _especie;
  late String _estado;
  late String _urgencia;
  late String _energia;
  late String _tamano;
  late String _edad;
  late String _genero;
  late String _okNinos;
  late String _okMascotas;
  late String _requiereExp;
  bool _guardando = false;
  String? _fotoBase64Existente;
  XFile? _nuevaFoto;
  final _picker = ImagePicker();

  static const _especies  = ['Perro', 'Gato', 'Otro'];
  static const _estados   = ['Sano', 'En tratamiento', 'Recuperado'];
  static const _urgencias = ['Alta', 'Media', 'Baja'];
  static const _energias  = ['Tranquilo', 'Activo', 'Muy activo'];
  static const _tamanos   = ['Pequeño', 'Mediano', 'Grande'];
  static const _edades    = ['Cachorro', 'Adulto', 'Senior'];
  static const _generos   = ['Macho', 'Hembra', 'No sé'];
  static const _siNo      = ['Sí', 'No'];

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    _nombreCtl = TextEditingController(text: d['nombre'] ?? '');
    _descCtl   = TextEditingController(text: d['descripcion'] ?? '');
    _lugarCtl  = TextEditingController(text: d['ubicacion'] ?? '');
    _especie   = d['especie']   ?? 'Perro';
    _estado    = d['estado']    ?? 'Sano';
    _urgencia  = d['urgencia']  ?? 'Media';
    _energia   = d['energia']   ?? 'Tranquilo';
    _tamano    = d['tamano']    ?? 'Mediano';
    _edad      = d['edad']      ?? 'Cachorro';
    _genero    = d['genero']    ?? 'No sé';
    _okNinos   = (d['okConNinos']    as bool? ?? false) ? 'Sí' : 'No';
    _okMascotas= (d['okConMascotas'] as bool? ?? false) ? 'Sí' : 'No';
    _requiereExp=(d['requiereExperiencia'] as bool? ?? false) ? 'Sí' : 'No';
    _fotoBase64Existente = d['fotoBase64'] as String?;
  }

  @override
  void dispose() {
    _nombreCtl.dispose(); _descCtl.dispose(); _lugarCtl.dispose();
    super.dispose();
  }

  Future<void> _pickFoto(ImageSource src) async {
    final img = await _picker.pickImage(source: src, imageQuality: 40, maxWidth: 400, maxHeight: 400);
    if (img != null) setState(() => _nuevaFoto = img);
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    String? fotoBase64;
    if (_nuevaFoto != null) {
      final bytes = await File(_nuevaFoto!.path).readAsBytes();
      fotoBase64 = base64Encode(bytes);
    }
    await FirebaseFirestore.instance.collection('rescates').doc(widget.docId).update({
      'nombre':      _nombreCtl.text.trim(),
      'descripcion': _descCtl.text.trim(),
      'ubicacion':   _lugarCtl.text.trim(),
      'especie':     _especie,
      'estado':      _estado,
      'urgencia':    _urgencia,
      'energia':     _energia,
      'tamano':      _tamano,
      'edad':        _edad,
      'genero':      _genero,
      'okConNinos':        _okNinos    == 'Sí',
      'okConMascotas':     _okMascotas == 'Sí',
      'requiereExperiencia': _requiereExp == 'Sí',
      if (fotoBase64 != null) 'fotoBase64': fotoBase64,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('¡Cambios guardados!'), backgroundColor: appTeal));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appBg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 20, 12),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              const Expanded(child: Text('Editar animal',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)))),
              if (_guardando)
                const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(color: appTeal, strokeWidth: 2))
              else
                TextButton(
                  onPressed: _guardar,
                  child: const Text('Guardar', style: TextStyle(color: appTeal, fontWeight: FontWeight.w700, fontSize: 15)),
                ),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _seccion('FOTO'),
                const SizedBox(height: 10),
                _fotoSection(),
                const SizedBox(height: 20),
                _campo('Nombre', _nombreCtl, 'ej. Luna'),
                const SizedBox(height: 16),
                _campo('Ubicación', _lugarCtl, 'ej. Laureles'),
                const SizedBox(height: 16),
                _campo('Descripción', _descCtl, 'Cuéntanos sobre el animal...', maxLines: 3),
                const SizedBox(height: 20),
                _seccion('INFORMACIÓN'),
                const SizedBox(height: 12),
                _selector('Especie', _especie, _especies, (v) => setState(() => _especie = v)),
                const SizedBox(height: 12),
                _selector('Estado de salud', _estado, _estados, (v) => setState(() => _estado = v)),
                const SizedBox(height: 12),
                _selector('Urgencia', _urgencia, _urgencias, (v) => setState(() => _urgencia = v)),
                const SizedBox(height: 20),
                _seccion('COMPATIBILIDAD'),
                const SizedBox(height: 12),
                _selector('Energía', _energia, _energias, (v) => setState(() => _energia = v)),
                const SizedBox(height: 12),
                _selector('Tamaño', _tamano, _tamanos, (v) => setState(() => _tamano = v)),
                const SizedBox(height: 12),
                _selector('Edad', _edad, _edades, (v) => setState(() => _edad = v)),
                const SizedBox(height: 12),
                _selector('Género', _genero, _generos, (v) => setState(() => _genero = v)),
                const SizedBox(height: 12),
                _selector('¿Ok con niños?', _okNinos, _siNo, (v) => setState(() => _okNinos = v)),
                const SizedBox(height: 12),
                _selector('¿Ok con otras mascotas?', _okMascotas, _siNo, (v) => setState(() => _okMascotas = v)),
                const SizedBox(height: 12),
                _selector('¿Requiere experiencia?', _requiereExp, _siNo, (v) => setState(() => _requiereExp = v)),
                const SizedBox(height: 40),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _seccion(String t) => Text(t,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: Colors.grey.shade500));

  Widget _fotoSection() {
    final bool tieneNueva = _nuevaFoto != null;
    final bool tieneExistente = _fotoBase64Existente != null && !tieneNueva;
    final bool tieneFoto = tieneNueva || tieneExistente;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Vista previa grande
      ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: double.infinity, height: 180,
          child: tieneFoto
            ? Stack(fit: StackFit.expand, children: [
                tieneNueva
                  ? Image.file(File(_nuevaFoto!.path), fit: BoxFit.cover)
                  : Image.memory(base64Decode(_fotoBase64Existente!), fit: BoxFit.cover),
                Positioned(bottom: 8, right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('Foto actual',
                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                  )),
              ])
            : GestureDetector(
                onTap: () => _pickFoto(ImageSource.gallery),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFD8F0E4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: appTeal.withOpacity(0.4), width: 2,
                        style: BorderStyle.solid),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.add_a_photo_outlined, size: 44, color: appTeal),
                    const SizedBox(height: 8),
                    const Text('Toca para agregar foto',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: appTeal)),
                    const SizedBox(height: 4),
                    Text('Requerida para publicar',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  ]),
                ),
              ),
        ),
      ),
      const SizedBox(height: 10),
      // Botones cambiar foto
      Row(children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _pickFoto(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined, size: 16),
            label: const Text('Galería'),
            style: ElevatedButton.styleFrom(
              backgroundColor: appTeal, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 0,
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _pickFoto(ImageSource.camera),
            icon: const Icon(Icons.camera_alt_outlined, size: 16),
            label: const Text('Cámara'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white, foregroundColor: appTeal,
              side: const BorderSide(color: appTeal),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 0,
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ]),
    ]);
  }

  Widget _campo(String label, TextEditingController ctl, String hint, {int maxLines = 1}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
      const SizedBox(height: 6),
      TextField(
        controller: ctl,
        maxLines: maxLines,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400),
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    ]);

  Widget _selector(String label, String valor, List<String> opts, ValueChanged<String> onChanged) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
      const SizedBox(height: 6),
      Wrap(spacing: 8, children: opts.map((o) {
        final sel = o == valor;
        return GestureDetector(
          onTap: () => onChanged(o),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? appTeal : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: sel ? appTeal : Colors.grey.shade300),
            ),
            child: Text(o, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: sel ? Colors.white : Colors.grey.shade600)),
          ),
        );
      }).toList()),
    ]);
}
