import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../theme.dart';

class SubirRescateScreen extends StatefulWidget {
  final bool esAlbergue;
  const SubirRescateScreen({super.key, this.esAlbergue = false});
  @override
  State<SubirRescateScreen> createState() => _SubirRescateScreenState();
}

class _SubirRescateScreenState extends State<SubirRescateScreen> {
  final _picker    = ImagePicker();
  final _nombreCtl = TextEditingController();
  final _lugarCtl  = TextEditingController();
  final _descCtl   = TextEditingController();

  final _razaCtl = TextEditingController();
  final List<XFile> _fotos = [];
  String _especie      = 'Perro';
  String _estado       = 'Sano';
  String _urgencia     = 'Alta';
  String _energia      = 'Tranquilo';
  String _tamano       = 'Mediano';
  String _edad         = 'Cachorro';
  String _genero       = 'No sé';
  String _okNinos      = 'Sí';
  String _okMascotas   = 'Sí';
  String _requiereExp  = 'No';
  String _tipoRaza     = 'Criolla';

  static const _especies      = ['Perro', 'Gato', 'Otro'];
  static const _estados       = ['Sano', 'Herido', 'En tratamiento', 'Crítico'];
  static const _urgencias     = ['Alta', 'Media', 'Baja'];
  static const _energias      = ['Tranquilo', 'Activo', 'Muy activo'];
  static const _tamanos       = ['Pequeño', 'Mediano', 'Grande'];
  static const _edades        = ['Cachorro', 'Adulto', 'Senior'];
  static const _generos       = ['Macho', 'Hembra', 'No sé'];
  static const _siNoOpts      = ['Sí', 'No'];
  static const _tipoRazaOpts  = ['Criolla', 'Raza definida'];

  Color _urgenciaColor(String u) => switch (u) {
    'Alta'  => const Color(0xFFD32F2F),
    'Media' => const Color(0xFFE65100),
    _       => const Color(0xFF1F8A62),
  };

  Future<void> _pickFoto() async {
    if (_fotos.length >= 2) return;
    final img = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 90, maxWidth: 1000, maxHeight: 1000);
    if (img != null) setState(() => _fotos.add(img));
  }

  Future<void> _tomarFoto() async {
    if (_fotos.length >= 2) return;
    try {
      final img = await _picker.pickImage(
          source: ImageSource.camera, imageQuality: 90, maxWidth: 1000, maxHeight: 1000);
      if (img != null) setState(() => _fotos.add(img));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Cámara no disponible — usa la galería'),
        backgroundColor: appTeal,
      ));
    }
  }

  bool _publicando = false;
  bool _detectandoUbicacion = false;
  double? _latitud;
  double? _longitud;
  String _paisCodigo = '';

  @override
  void initState() {
    super.initState();
    if (widget.esAlbergue) _cargarCiudadAlbergue();
    else _obtenerUbicacionGPS();
  }

  Future<void> _cargarCiudadAlbergue() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
    final ciudad = (doc.data()?['ciudad'] as String?) ?? '';
    if (ciudad.isNotEmpty && mounted) setState(() => _lugarCtl.text = ciudad);
  }

  Future<void> _obtenerUbicacionGPS() async {
    setState(() => _detectandoUbicacion = true);
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Activa el GPS en tu dispositivo')));
      setState(() => _detectandoUbicacion = false);
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _detectandoUbicacion = false);
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permiso de ubicación bloqueado. Habilítalo en Ajustes.')));
      setState(() => _detectandoUbicacion = false);
      return;
    }
    final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
    String ciudad = '';
    String paisCodigo = '';
    try {
      final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (placemarks.isNotEmpty) {
        ciudad = placemarks.first.locality?.isNotEmpty == true
            ? placemarks.first.locality!
            : placemarks.first.administrativeArea ?? '';
        paisCodigo = placemarks.first.isoCountryCode ?? '';
      }
    } catch (_) {}
    setState(() {
      _latitud  = pos.latitude;
      _longitud = pos.longitude;
      _lugarCtl.text = ciudad;
      _paisCodigo = paisCodigo;
      _detectandoUbicacion = false;
    });
  }

  Future<String> _normalizarFoto(String path) async {
    final bytes = await File(path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return base64Encode(bytes);
    final rotated = img.bakeOrientation(decoded);
    // Redimensiona si es muy grande para no exceder el límite de Firestore (1MB por doc)
    final resized = rotated.width > 1000
        ? img.copyResize(rotated, width: 1000)
        : rotated;
    final jpeg = img.encodeJpg(resized, quality: 80);
    return base64Encode(jpeg);
  }

  Future<void> _publicar() async {
    if (_fotos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes agregar al menos una foto del animal')));
      return;
    }
    if (_latitud == null && !widget.esAlbergue) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor detecta tu ubicación GPS')));
      return;
    }
    setState(() => _publicando = true);
    try {
      String? fotoBase64;
      String? fotoBase642;
      if (_fotos.isNotEmpty) {
        fotoBase64 = await _normalizarFoto(_fotos[0].path);
      }
      if (_fotos.length > 1) {
        fotoBase642 = await _normalizarFoto(_fotos[1].path);
      }

      await FirebaseFirestore.instance.collection('rescates').add({
        'nombre':           _nombreCtl.text.trim(),
        'especie':          _especie,
        'raza':             _tipoRaza == 'Criolla' ? 'Criolla' : _razaCtl.text.trim().isEmpty ? 'Raza definida' : _razaCtl.text.trim(),
        'estado':           _estado,
        'urgencia':         _urgencia,
        'ubicacion':        _lugarCtl.text.trim(),
        'descripcion':      _descCtl.text.trim(),
        'estadoAdopcion':   'Rescatado',
        if (fotoBase64  != null) 'fotoBase64':  fotoBase64,
        if (fotoBase642 != null) 'fotoBase642': fotoBase642,
        'rescatistaId':        FirebaseAuth.instance.currentUser?.uid ?? '',
        'rescatistaNombre':    FirebaseAuth.instance.currentUser?.displayName ?? 'Rescatista',
        'creadoPor':           widget.esAlbergue ? 'albergue' : 'rescatista',
        if (_latitud  != null) 'latitud':  _latitud,
        if (_longitud != null) 'longitud': _longitud,
        if (_paisCodigo.isNotEmpty) 'paisCodigo': _paisCodigo,
        'edad':             _edad,
        'genero':           _genero,
        'energia':          _energia,
        'tamano':           _tamano,
        'okConNinos':       _okNinos == 'Sí',
        'okConMascotas':    _okMascotas == 'Sí',
        'requiereExperiencia': _requiereExp == 'Sí',
        'creadoEn':         FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('¡Rescate publicado! 🐾'),
          content: Text('${_nombreCtl.text.isEmpty ? "El animal" : _nombreCtl.text} '
              'fue publicado con urgencia $_urgencia'
              '${_lugarCtl.text.isNotEmpty ? ' en ${_lugarCtl.text}' : ''}.'),
          actions: [
            TextButton(
              onPressed: () { Navigator.pop(context); Navigator.pop(context); },
              child: const Text('Ver rescates', style: TextStyle(color: appTeal)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al publicar: $e')));
    } finally {
      if (mounted) setState(() => _publicando = false);
    }
  }

  @override
  void dispose() {
    _nombreCtl.dispose();
    _lugarCtl.dispose();
    _descCtl.dispose();
    _razaCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appBg,
      body: SafeArea(
          child: Column(children: [
            _appBar(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SizedBox(height: 8),
                  _section('Fotos del animal'),
                  const SizedBox(height: 10),
                  _fotoGrid(),
                  const SizedBox(height: 20),
                  _field('Nombre del animal (opcional)', _nombreCtl, hint: 'ej. Luna, sin nombre...'),
                  const SizedBox(height: 16),
                  _section('Raza'),
                  const SizedBox(height: 8),
                  _chips(_tipoRazaOpts, _tipoRaza,
                      (v) => setState(() { _tipoRaza = v; _razaCtl.clear(); }), appTeal),
                  if (_tipoRaza == 'Raza definida') ...[
                    const SizedBox(height: 10),
                    _field('¿Cuál raza?', _razaCtl, hint: 'ej. Golden Retriever, Siamés...'),
                  ],
                  const SizedBox(height: 16),
                  _section('Especie'),
                  const SizedBox(height: 8),
                  _chips(_especies, _especie, (v) => setState(() => _especie = v), appTeal),
                  const SizedBox(height: 20),
                  _section('Edad aproximada'),
                  const SizedBox(height: 8),
                  _chips(_edades, _edad, (v) => setState(() => _edad = v), appTeal),
                  const SizedBox(height: 20),
                  _section('Género'),
                  const SizedBox(height: 8),
                  _chips(_generos, _genero, (v) => setState(() => _genero = v), appTeal),
                  const SizedBox(height: 20),
                  _section('Estado de salud'),
                  const SizedBox(height: 8),
                  _chips(_estados, _estado, (v) => setState(() => _estado = v), appTeal),
                  const SizedBox(height: 20),
                  _section('Urgencia'),
                  const SizedBox(height: 8),
                  _chips(_urgencias, _urgencia,
                    (v) => setState(() => _urgencia = v), _urgenciaColor(_urgencia)),
                  const SizedBox(height: 28),
                  _sectionLabel('Compatibilidad para adopción'),
                  const SizedBox(height: 4),
                  Text('Estas etiquetas ayudan a encontrar el hogar ideal',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  const SizedBox(height: 16),
                  _section('Nivel de energía'),
                  const SizedBox(height: 8),
                  _chips(_energias, _energia,
                      (v) => setState(() => _energia = v), const Color(0xFF7C4DFF)),
                  const SizedBox(height: 20),
                  _section('Tamaño'),
                  const SizedBox(height: 8),
                  _chips(_tamanos, _tamano,
                      (v) => setState(() => _tamano = v), appTeal),
                  const SizedBox(height: 20),
                  _section('¿Es amigable con niños?'),
                  const SizedBox(height: 8),
                  _chips(_siNoOpts, _okNinos,
                      (v) => setState(() => _okNinos = v), appTeal),
                  const SizedBox(height: 20),
                  _section('¿Es sociable con otros animales?'),
                  const SizedBox(height: 8),
                  _chips(_siNoOpts, _okMascotas,
                      (v) => setState(() => _okMascotas = v), appTeal),
                  const SizedBox(height: 20),
                  _section('¿Requiere adoptante con experiencia?'),
                  const SizedBox(height: 8),
                  _chips(_siNoOpts, _requiereExp,
                      (v) => setState(() => _requiereExp = v), appOrange),
                  const SizedBox(height: 28),
                  if (!widget.esAlbergue) ...[
                    _section('Ubicación'),
                    const SizedBox(height: 8),
                    _locationField(),
                    const SizedBox(height: 20),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Descripción', style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700)),
                      GestureDetector(
                        onTap: () {
                          final nombre = _nombreCtl.text.trim().isNotEmpty
                              ? _nombreCtl.text.trim()
                              : '[Nombre]';
                          final plantilla =
                              '$nombre fue encontrado/a [contá cómo o dónde lo/la encontraste]. '
                              'Lo/la que lo/la hace único/a es [una costumbre, gesto o anécdota que lo/la describa]. '
                              'Ya pasó por mucho — ahora solo le falta alguien que decida quedarse. '
                              '¿Serás vos?';
                          _descCtl.value = TextEditingValue(
                            text: plantilla,
                            selection: TextSelection.collapsed(offset: plantilla.length),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: appTeal.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: appTeal.withValues(alpha: 0.3)),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Text('✨', style: TextStyle(fontSize: 13)),
                            SizedBox(width: 4),
                            Text('Usar plantilla',
                                style: TextStyle(fontSize: 12,
                                    fontWeight: FontWeight.w600, color: appTeal)),
                          ]),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _field('', _descCtl,
                      hint: 'Estado del animal, dónde fue encontrado, necesidades especiales...',
                      maxLines: 5),
                  const SizedBox(height: 28),
                  _publishBtn(),
                  const SizedBox(height: 40),
                ]),
              ),
            ),
          ]),
      ),
    );
  }

  Widget _appBar(BuildContext ctx) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
    child: Row(children: [
      IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        onPressed: () => Navigator.pop(ctx),
      ),
      const Expanded(
        child: Text('Subir un rescate',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
      ),
    ]),
  );

  Widget _section(String t) => Text(t,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF222222)));

  Widget _sectionLabel(String t) => Text(t,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF7C4DFF)));

  Widget _fotoGrid() {
    final items = List<Widget>.from(_fotos.map((f) => _fotoThumb(f)));
    if (_fotos.length < 2) items.add(_fotoAddBtn());
    return Wrap(spacing: 10, runSpacing: 10, children: items);
  }

  Widget _fotoThumb(XFile f) => Stack(children: [
    ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.file(File(f.path), width: 90, height: 90, fit: BoxFit.cover),
    ),
    Positioned(top: 4, right: 4,
      child: GestureDetector(
        onTap: () => setState(() => _fotos.remove(f)),
        child: Container(
          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
          padding: const EdgeInsets.all(3),
          child: const Icon(Icons.close, size: 14, color: Colors.white),
        ),
      )),
  ]);

  Widget _fotoAddBtn() => GestureDetector(
    onTap: _mostrarOpcionesFoto,
    child: Container(
      width: 90, height: 90,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: appTeal.withOpacity(0.4), width: 1.5),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.add_a_photo_outlined, color: appTeal, size: 28),
        const SizedBox(height: 4),
        Text(_fotos.isEmpty ? 'Agregar' : '${_fotos.length}/2', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ]),
    ),
  );

  void _mostrarOpcionesFoto() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          ListTile(leading: const Icon(Icons.camera_alt, color: appTeal), title: const Text('Tomar foto'),
            onTap: () { Navigator.pop(context); _tomarFoto(); }),
          ListTile(leading: const Icon(Icons.photo_library, color: appTeal), title: const Text('Elegir de la galería'),
            onTap: () { Navigator.pop(context); _pickFoto(); }),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _chips(List<String> options, String selected, ValueChanged<String> onSelect, Color activeColor) =>
      Wrap(spacing: 8, runSpacing: 8, children: options.map((o) {
        final sel = o == selected;
        return GestureDetector(
          onTap: () => onSelect(o),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? activeColor : Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: sel ? activeColor : Colors.grey.shade300),
            ),
            child: Text(o, style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: sel ? Colors.white : Colors.grey.shade700)),
          ),
        );
      }).toList());

  Widget _field(String label, TextEditingController ctl, {String hint = '', int maxLines = 1}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _section(label),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.88), borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
          child: TextField(
            controller: ctl, maxLines: maxLines,
            decoration: InputDecoration(
              hintText: hint, hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
      ]);

  Widget _locationField() {
    final obtenida = _latitud != null;
    final ciudad = _lugarCtl.text;
    return GestureDetector(
      onTap: _detectandoUbicacion ? null : _obtenerUbicacionGPS,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: obtenida ? appTeal.withOpacity(0.08) : Colors.white.withOpacity(0.88),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: obtenida ? appTeal : Colors.grey.shade300),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
        ),
        child: Row(children: [
          if (_detectandoUbicacion)
            const SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: appTeal))
          else
            Icon(obtenida ? Icons.check_circle : Icons.my_location,
                color: obtenida ? appTeal : Colors.grey.shade500, size: 22),
          const SizedBox(width: 12),
          Text(
            _detectandoUbicacion
                ? 'Detectando ubicación...'
                : obtenida
                    ? (ciudad.isNotEmpty ? '$ciudad ✓' : 'Ubicación detectada ✓')
                    : 'Toca para detectar tu ubicación',
            style: TextStyle(
              fontSize: 14,
              color: obtenida || _detectandoUbicacion ? appTeal : Colors.grey.shade500,
              fontWeight: obtenida ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _publishBtn() => SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: _publicando ? null : _publicar,
      style: ElevatedButton.styleFrom(
        backgroundColor: appDark, foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
      ),
      child: _publicando
          ? const SizedBox(height: 20, width: 20,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : const Text('Publicar rescate 🐾', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    ),
  );
}
