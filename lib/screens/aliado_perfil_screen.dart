import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import '../theme.dart';

class AliadoPerfilScreen extends StatefulWidget {
  const AliadoPerfilScreen({super.key});
  @override
  State<AliadoPerfilScreen> createState() => _AliadoPerfilScreenState();
}

class _AliadoPerfilScreenState extends State<AliadoPerfilScreen> {
  final _nombreCtl  = TextEditingController();
  final _ciudadCtl  = TextEditingController();
  String? _tipo;
  String? _fotoBase64;
  bool    _guardando = false;

  static const _tipos = [
    'Veterinaria',
    'Tienda de mascotas',
    'Spa canino',
    'Peluquería canina',
    'Otro',
  ];

  bool get _completo =>
      _nombreCtl.text.trim().isNotEmpty &&
      _ciudadCtl.text.trim().isNotEmpty &&
      _tipo != null;

  @override
  void initState() {
    super.initState();
    _cargarDatosExistentes();
  }

  Future<void> _cargarDatosExistentes() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
    if (!doc.exists || !mounted) return;
    final data = doc.data() as Map<String, dynamic>;
    setState(() {
      _nombreCtl.text = data['aliadoNombre'] as String? ?? '';
      _ciudadCtl.text = data['ciudad']       as String? ?? '';
      _tipo           = data['aliadoTipo']   as String?;
      _fotoBase64     = data['fotoBase64']   as String?;
    });
  }

  Future<void> _pickFoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (picked == null) return;
    final bytes   = await File(picked.path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) { setState(() => _fotoBase64 = base64Encode(bytes)); return; }
    final rotated = img.bakeOrientation(decoded);
    setState(() => _fotoBase64 = base64Encode(img.encodeJpg(rotated, quality: 80)));
  }

  Future<void> _guardar() async {
    if (!_completo) return;
    setState(() => _guardando = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await FirebaseFirestore.instance.collection('usuarios').doc(uid).update({
      'aliadoNombre': _nombreCtl.text.trim(),
      'aliadoTipo':   _tipo ?? '',
      'ciudad':       _ciudadCtl.text.trim(),
      if (_fotoBase64 != null) 'fotoBase64': _fotoBase64,
    });
  }

  @override
  void dispose() {
    _nombreCtl.dispose();
    _ciudadCtl.dispose();
    super.dispose();
  }

  Future<void> _cambiarRolDebug() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final opciones = <String, List<String>>{
      'Solo Adoptante':         ['adoptante'],
      'Solo Rescatista':        ['rescatista'],
      'Adoptante + Rescatista': ['adoptante', 'rescatista'],
      'Albergue':               ['albergue'],
      'Aliado':                 ['aliado'],
    };
    final sel = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('🛠 Cambiar rol (DEBUG)'),
        children: opciones.entries.map((e) => SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, e.value),
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(e.key)),
        )).toList(),
      ),
    );
    if (sel == null) return;
    await FirebaseFirestore.instance.collection('usuarios').doc(uid).update({'roles': sel});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appBg,
      floatingActionButton: kDebugMode
          ? FloatingActionButton.small(
              heroTag: 'debug_perfil',
              onPressed: _cambiarRolDebug,
              backgroundColor: Colors.purple.shade100,
              elevation: 4,
              child: Icon(Icons.developer_mode, color: Colors.purple.shade700),
            )
          : null,
      body: Stack(fit: StackFit.expand, children: [
        const LeafOverlay(),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 40),

              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: appTeal,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.store_outlined, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 20),
              const Text('Configura tu negocio',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
              const SizedBox(height: 6),
              Text('Esta información aparecerá en tu perfil público',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
              const SizedBox(height: 32),

              // Foto
              Center(
                child: GestureDetector(
                  onTap: _pickFoto,
                  child: Container(
                    width: 90, height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: appTeal, width: 2),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: _fotoBase64 != null
                        ? Image.memory(base64Decode(_fotoBase64!), fit: BoxFit.cover)
                        : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.camera_alt_outlined, color: appTeal, size: 24),
                            const SizedBox(height: 4),
                            Text('Logo', style: TextStyle(fontSize: 11, color: appTeal)),
                          ]),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              _campo(_nombreCtl, 'Nombre del negocio', Icons.business_outlined),
              const SizedBox(height: 16),
              _campo(_ciudadCtl, 'Ciudad', Icons.location_on_outlined),
              const SizedBox(height: 16),

              // Tipo
              DropdownButtonFormField<String>(
                value: _tipo,
                decoration: InputDecoration(
                  labelText: 'Tipo de negocio',
                  prefixIcon: const Icon(Icons.category_outlined),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                ),
                items: _tipos.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setState(() => _tipo = v),
              ),
              const SizedBox(height: 40),

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
                      : const Text('Guardar y continuar',
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
