import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import '../theme.dart';
import '../data/usuarios_repository.dart';
import '../data/firestore_resiliencia.dart';

class AliadoPerfilScreen extends StatefulWidget {
  const AliadoPerfilScreen({super.key});
  @override
  State<AliadoPerfilScreen> createState() => _AliadoPerfilScreenState();
}

class _AliadoPerfilScreenState extends State<AliadoPerfilScreen> {
  final _nombreCtl    = TextEditingController();
  final _ciudadCtl    = TextEditingController();
  final _telefonoCtl  = TextEditingController();
  final _direccionCtl = TextEditingController();
  final _emailCtl     = TextEditingController();
  final _webCtl       = TextEditingController();
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
      _nombreCtl.text    = data['aliadoNombre']     as String? ?? '';
      _ciudadCtl.text    = data['ciudad']           as String? ?? '';
      _telefonoCtl.text  = data['aliadoTelefono']  as String? ?? '';
      _direccionCtl.text = data['aliadoDireccion'] as String? ?? '';
      _emailCtl.text     = data['aliadoEmail']     as String? ?? '';
      _webCtl.text       = data['aliadoSitioWeb']  as String? ?? '';
      _tipo              = data['aliadoTipo']       as String?;
      _fotoBase64        = data['aliadoFotoBase64'] as String?;
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
    if (!mounted) return;
    if (decoded == null) { setState(() => _fotoBase64 = base64Encode(bytes)); return; }
    final rotated = img.bakeOrientation(decoded);
    setState(() => _fotoBase64 = base64Encode(img.encodeJpg(rotated, quality: 80)));
  }

  Future<void> _guardar() async {
    if (!_completo) return;
    setState(() => _guardando = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    // guardarConAviso, no un await directo: sin esto, sin conexión o con
    // el token de sesión vencido, el botón de guardar se quedaba pegado
    // para siempre sin ningún aviso — mismo bug ya arreglado una vez en
    // editar_rescate_screen.dart, que nunca se replicó acá (hallazgo de
    // auditoría de código).
    final resultado = await guardarConAviso(() =>
        FirebaseFirestore.instance.collection('usuarios').doc(uid).update({
          'aliadoNombre': _nombreCtl.text.trim(),
          'aliadoTipo':   _tipo ?? '',
          'ciudad':       _ciudadCtl.text.trim(),
          // Opcionales a propósito, mismo criterio que albergue_perfil_screen.dart.
          // Prefijo "aliado" a propósito: ver el comentario largo en
          // albergue_perfil_screen.dart — una cuenta con doble rol (albergue +
          // aliado) compartía estos mismos campos genéricos entre los dos
          // perfiles, y "email" además pisaba el email de LOGIN de la cuenta.
          'aliadoTelefono':  _telefonoCtl.text.trim(),
          'aliadoDireccion': _direccionCtl.text.trim(),
          'aliadoEmail':     _emailCtl.text.trim(),
          'aliadoSitioWeb':  _webCtl.text.trim(),
          if (_fotoBase64 != null) 'aliadoFotoBase64': _fotoBase64,
        }));
    if (!mounted) return;
    setState(() => _guardando = false);
    switch (resultado) {
      case ResultadoGuardado.confirmado:
        if (Navigator.canPop(context)) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Perfil actualizado'), backgroundColor: msgExito));
          Navigator.pop(context);
        }
      case ResultadoGuardado.siguePendiente:
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Esto está tardando. Tu perfil se va a actualizar solo apenas vuelva la señal.'),
            backgroundColor: msgAdvertencia));
        if (Navigator.canPop(context)) Navigator.pop(context);
      case ResultadoGuardado.fallo:
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo guardar. Revisá tu conexión e intentá de nuevo.'),
            backgroundColor: msgError));
    }
  }

  @override
  void dispose() {
    _nombreCtl.dispose();
    _ciudadCtl.dispose();
    _telefonoCtl.dispose();
    _direccionCtl.dispose();
    _emailCtl.dispose();
    _webCtl.dispose();
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
    try {
      await UsuariosRepository().actualizarRoles(uid, sel);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo cambiar el rol. Revisá tu conexión e intentá de nuevo.'),
          backgroundColor: msgError));
    }
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
              tooltip: 'Cambiar rol (debug)',
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
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: appInk,
                      fontFamily: 'Baloo2')),
              const SizedBox(height: 6),
              Text('Esta información aparecerá en tu perfil público',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
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
                        ? FotoSegura(
                            base64: _fotoBase64!,
                            fit: BoxFit.cover,
                            fallback: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(Icons.camera_alt_outlined, color: appTeal, size: 24),
                                const SizedBox(height: 4),
                                Text('Logo', style: TextStyle(fontSize: 11, color: appTeal)),
                              ]),
                          )
                        : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.camera_alt_outlined, color: appTeal, size: 24),
                            const SizedBox(height: 4),
                            Text('Logo', style: TextStyle(fontSize: 11, color: appTeal)),
                          ]),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Mismo estilo que "Configura tu albergue" (label arriba del
              // campo, en vez del ícono + label flotante que tenía esta
              // pantalla antes) — Eliza las comparó una al lado de la otra
              // y pidió que las dos se vean con la misma tipografía.
              perfilLabel('NOMBRE DEL NEGOCIO *'),
              const SizedBox(height: 8),
              perfilCampo(_nombreCtl, 'ej. Veterinaria La 30',
                  autofocus: true, onChanged: (_) => setState(() {})),
              const SizedBox(height: 24),

              perfilLabel('CIUDAD *'),
              const SizedBox(height: 8),
              perfilCampo(_ciudadCtl, 'ej. Medellín, Bogotá, Santiago',
                  onChanged: (_) => setState(() {})),
              const SizedBox(height: 24),

              // Teléfono/WhatsApp y dirección, opcionales — no van en
              // _completo a propósito, un negocio recién sumándose puede
              // no tener todavía un número de atención separado.
              perfilLabel('TELÉFONO / WHATSAPP (OPCIONAL)'),
              const SizedBox(height: 8),
              perfilCampo(_telefonoCtl, 'ej. 300 123 4567',
                  tipo: TextInputType.phone,
                  formato: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +()-]'))]),
              const SizedBox(height: 24),

              perfilLabel('DIRECCIÓN (OPCIONAL)'),
              const SizedBox(height: 8),
              perfilCampo(_direccionCtl, 'ej. Calle 10 #43-12, El Poblado'),
              const SizedBox(height: 24),

              perfilLabel('EMAIL (OPCIONAL)'),
              const SizedBox(height: 8),
              perfilCampo(_emailCtl, 'ej. contacto@tunegocio.com',
                  tipo: TextInputType.emailAddress),
              const SizedBox(height: 24),

              perfilLabel('PÁGINA WEB (OPCIONAL)'),
              const SizedBox(height: 8),
              perfilCampo(_webCtl, 'ej. www.tunegocio.com',
                  tipo: TextInputType.url),
              const SizedBox(height: 24),

              // Tipo — mismo look que el resto de los campos (caja blanca
              // sin ícono, radio 12): solo cambia que es un desplegable.
              perfilLabel('TIPO DE NEGOCIO *'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _tipo,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
}
