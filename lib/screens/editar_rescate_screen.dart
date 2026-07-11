import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../theme.dart';
import '../data/rescates_repository.dart';
import '../data/rescate_fotos_repository.dart';

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
  String? _fotoUrlExistente;
  String? _foto2UrlExistente;
  XFile? _nuevaFoto;
  XFile? _nuevaFoto2;
  final _picker = ImagePicker();

  bool _detectandoUbicacion = false;
  double? _latitud;
  double? _longitud;
  String _paisCodigo = '';

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
    _fotoUrlExistente  = d['fotoUrl']  as String?;
    _foto2UrlExistente = d['fotoUrl2'] as String?;
    _latitud     = d['latitud']    as double?;
    _longitud    = d['longitud']   as double?;
    _paisCodigo  = d['paisCodigo'] as String? ?? '';
  }

  /// Igual que en subir_rescate_screen.dart: con timeLimit para que un GPS
  /// lento o que falla no se quede esperando para siempre sin avisar nada.
  /// Totalmente opcional acá — guardar nunca depende de esto.
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
      // Mismo criterio que subir_rescate_screen.dart: un botón que abre
      // directo la pantalla de permisos, no solo el texto "andá a Ajustes".
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Permiso de ubicación bloqueado.'),
        action: SnackBarAction(
          label: 'Abrir Ajustes',
          onPressed: () => Geolocator.openAppSettings(),
        ),
        duration: const Duration(seconds: 8),
      ));
      setState(() => _detectandoUbicacion = false);
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 12),
          ));
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
      if (!mounted) return;
      setState(() {
        _latitud  = pos.latitude;
        _longitud = pos.longitude;
        if (ciudad.isNotEmpty) _lugarCtl.text = ciudad;
        _paisCodigo = paisCodigo;
        _detectandoUbicacion = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _detectandoUbicacion = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo detectar tu ubicación. Podés reintentar tocando de nuevo.')));
    }
  }

  @override
  void dispose() {
    _nombreCtl.dispose(); _descCtl.dispose(); _lugarCtl.dispose();
    super.dispose();
  }

  Future<void> _pickFoto(ImageSource src, {int slot = 1}) async {
    final img = await _picker.pickImage(source: src, imageQuality: 80, maxWidth: 1000, maxHeight: 1000);
    if (img == null || !mounted) return;
    setState(() {
      if (slot == 1) { _nuevaFoto  = img; }
      else           { _nuevaFoto2 = img; }
    });
  }

  void _mostrarOpcionesFoto(int slot) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.camera_alt, color: appTeal),
            title: const Text('Tomar foto'),
            onTap: () { Navigator.pop(context); _pickFoto(ImageSource.camera, slot: slot); },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, color: appTeal),
            title: const Text('Elegir de la galería'),
            onTap: () { Navigator.pop(context); _pickFoto(ImageSource.gallery, slot: slot); },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<void> _eliminar() async {
    final nombre = _nombreCtl.text.trim().isNotEmpty ? _nombreCtl.text.trim() : 'este animal';
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Eliminar publicación'),
        content: Text('¿Seguro que quieres eliminar a $nombre? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    setState(() => _guardando = true);
    try {
      await RescatesRepository().eliminar(widget.docId);
      // Best-effort: borrar también las fotos de Storage para no dejarlas
      // huérfanas pagando almacenamiento indefinidamente. try/catch, no
      // .catchError — un catchError mal tipado revienta acá y el flujo
      // muere en silencio antes del SnackBar.
      try { await RescateFotosRepository().eliminarTodas(widget.docId); } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Publicación eliminada'), backgroundColor: appTeal));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  /// Resuelve un slot de foto comparando estado inicial vs. final: foto
  /// nueva → subirla (sobreescribe el mismo path); sin cambios → mantener
  /// la URL que ya había, sin tocar Storage; se quitó sin reemplazarla →
  /// borrarla de Storage para no dejarla huérfana pagando almacenamiento.
  Future<String?> _resolverSlot({
    required int slot,
    required XFile? nuevaFoto,
    required String? urlExistente,
  }) async {
    if (nuevaFoto != null) {
      final bytes = await File(nuevaFoto.path).readAsBytes();
      return RescateFotosRepository().subir(rescateId: widget.docId, slot: slot, bytes: bytes);
    }
    if (urlExistente != null) return urlExistente;
    await RescateFotosRepository().eliminar(rescateId: widget.docId, slot: slot);
    return null;
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      final fotoUrl = await _resolverSlot(
          slot: 1, nuevaFoto: _nuevaFoto, urlExistente: _fotoUrlExistente);
      final fotoUrl2 = await _resolverSlot(
          slot: 2, nuevaFoto: _nuevaFoto2, urlExistente: _foto2UrlExistente);

      await RescatesRepository().actualizar(widget.docId, {
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
        'okConNinos':          _okNinos    == 'Sí',
        'okConMascotas':       _okMascotas == 'Sí',
        'requiereExperiencia': _requiereExp == 'Sí',
        'fotoUrl':  fotoUrl  ?? FieldValue.delete(),
        'fotoUrl2': fotoUrl2 ?? FieldValue.delete(),
        if (_latitud    != null) 'latitud':    _latitud,
        if (_longitud   != null) 'longitud':   _longitud,
        if (_paisCodigo.isNotEmpty) 'paisCodigo': _paisCodigo,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('¡Cambios guardados!'), backgroundColor: appTeal));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
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
                _seccion('FOTOS'),
                const SizedBox(height: 10),
                _fotoSection(),
                const SizedBox(height: 20),
                _campo('Nombre', _nombreCtl, 'ej. Luna'),
                const SizedBox(height: 16),
                _campo('Ubicación', _lugarCtl, 'ej. Laureles'),
                const SizedBox(height: 8),
                _locationField(),
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
                _selector('¿Amigable con niños?', _okNinos, _siNo, (v) => setState(() => _okNinos = v)),
                const SizedBox(height: 12),
                _selector('¿Sociable con animales?', _okMascotas, _siNo, (v) => setState(() => _okMascotas = v)),
                const SizedBox(height: 12),
                _selector('¿Requiere experiencia?', _requiereExp, _siNo, (v) => setState(() => _requiereExp = v)),
                const SizedBox(height: 32),
                GestureDetector(
                  onTap: _guardando ? null : _eliminar,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.delete_outline, color: Colors.red.shade400, size: 18),
                      const SizedBox(width: 8),
                      Text('Eliminar publicación',
                          style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
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
    final bool tiene1 = _nuevaFoto != null || _fotoUrlExistente != null;
    final bool tiene2 = _nuevaFoto2 != null || _foto2UrlExistente != null;
    final int total   = (tiene1 ? 1 : 0) + (tiene2 ? 1 : 0);
    final items       = <Widget>[];

    if (tiene1) {
      items.add(_fotoThumbEdit(
        file: _nuevaFoto,
        url: _fotoUrlExistente,
        onRemove: () => setState(() { _nuevaFoto = null; _fotoUrlExistente = null; }),
      ));
    }
    if (tiene2) {
      items.add(_fotoThumbEdit(
        file: _nuevaFoto2,
        url: _foto2UrlExistente,
        onRemove: () => setState(() { _nuevaFoto2 = null; _foto2UrlExistente = null; }),
      ));
    }
    if (total < 2) {
      items.add(_fotoAddBtnEdit(nextSlot: tiene1 ? 2 : 1));
    }

    return Wrap(spacing: 10, runSpacing: 10, children: items);
  }

  Widget _fotoThumbEdit({XFile? file, String? url, required VoidCallback onRemove}) {
    return Stack(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: file != null
            ? Image.file(File(file.path), width: 90, height: 90, fit: BoxFit.cover)
            : FotoUrl(
                url: url!,
                width: 90, height: 90,
                fallback: Container(
                  width: 90, height: 90,
                  color: Colors.grey.shade200,
                  child: Icon(Icons.broken_image_outlined, color: Colors.grey.shade400),
                ),
              ),
      ),
      Positioned(
        top: 4, right: 4,
        child: GestureDetector(
          onTap: onRemove,
          child: Container(
            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
            padding: const EdgeInsets.all(3),
            child: const Icon(Icons.close, size: 14, color: Colors.white),
          ),
        ),
      ),
    ]);
  }

  Widget _fotoAddBtnEdit({required int nextSlot}) {
    return GestureDetector(
      onTap: () => _mostrarOpcionesFoto(nextSlot),
      child: Container(
        width: 90, height: 90,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: appTeal.withValues(alpha: 0.4), width: 1.5),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.add_a_photo_outlined, color: appTeal, size: 28),
          const SizedBox(height: 4),
          Text(
            nextSlot == 1 ? 'Agregar' : '1/2',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ]),
      ),
    );
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

  Widget _locationField() {
    final obtenida = _latitud != null;
    final ciudad = _lugarCtl.text;
    return GestureDetector(
      onTap: _detectandoUbicacion ? null : _obtenerUbicacionGPS,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: obtenida ? appTeal.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: obtenida ? appTeal : Colors.grey.shade300),
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
