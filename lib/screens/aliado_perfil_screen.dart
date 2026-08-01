import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../theme.dart';
import '../data/firestore_resiliencia.dart';
import '../data/foto_normalizador.dart';

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
  bool    _cargando  = true;
  bool    _errorCarga = false;

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

  // Antes esto no tenía ningún try/catch: si la carga inicial fallaba (o
  // tardaba y la persona no esperaba), los campos opcionales (teléfono,
  // dirección, email, web) quedaban vacíos en pantalla — y _guardar() los
  // escribía igual, sin ninguna protección, borrando de contrabando lo que
  // ya estaba guardado. Ahora la pantalla no muestra el formulario (ni el
  // botón de guardar) hasta confirmar que la carga terminó bien; si falla,
  // muestra un estado de reintento en vez de proceder con datos a medias.
  // Hallazgo de auditoría de código.
  Future<void> _cargarDatosExistentes() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _cargando = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
      if (!mounted) return;
      if (!doc.exists) {
        setState(() => _cargando = false);
        return;
      }
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
        _cargando          = false;
      });
    } catch (_) {
      if (mounted) setState(() { _cargando = false; _errorCarga = true; });
    }
  }

  Future<void> _reintentarCarga() async {
    setState(() { _cargando = true; _errorCarga = false; });
    await _cargarDatosExistentes();
  }

  Future<void> _pickFoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (picked == null) return;
    // normalizarFoto() corre en su propio isolate — decodificar/reorientar/
    // recomprimir es trabajo de CPU sincrónico, y hacerlo acá directo en el
    // isolate principal (como estaba antes) bloqueaba la UI mientras
    // corría, sin límite de tiempo ni forma de cortarlo ante una imagen
    // corrupta. maxWidth:512 porque el resultado se guarda en base64 DENTRO
    // del documento de Firestore (no aparte en Storage, como las fotos de
    // rescates), que tiene un tope de 1MB total — el 1000px por defecto de
    // normalizarFoto() es para las fotos que sí van a Storage. Hallazgo de
    // auditoría de código previa a subir a Play Store.
    Uint8List bytes;
    try {
      bytes = await normalizarFoto(picked.path, maxWidth: 512);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() => _fotoBase64 = base64Encode(bytes));
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

  // El diálogo/escritura viven en mostrarCambiarRolDebug (theme.dart,
  // compartida entre 5 pantallas que antes cada una tenía su propia copia
  // — hallazgo de auditoría de código).
  Future<void> _cambiarRolDebug() => mostrarCambiarRolDebug(context);

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(
        backgroundColor: appBg,
        body: Center(child: CircularProgressIndicator(color: appTeal)),
      );
    }
    if (_errorCarga) {
      return Scaffold(
        backgroundColor: appBg,
        body: SafeArea(
          child: Column(children: [
            Builder(builder: (ctx) => Navigator.canPop(ctx)
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                      tooltip: 'Volver',
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  )
                : const SizedBox.shrink()),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    errorFeedState(
                        mensaje: 'No pudimos cargar tu perfil. Revisá tu conexión e intentá de nuevo.'),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _reintentarCarga,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: appTeal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: const Text('Reintentar', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      );
    }
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
              CampoTelefono(controller: _telefonoCtl),
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
