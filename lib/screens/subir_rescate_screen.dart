import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../theme.dart';
import '../data/creator_role.dart';
import '../data/rescates_repository.dart';
import '../data/rescate_fotos_repository.dart';

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
    if (img != null && mounted) setState(() => _fotos.add(img));
  }

  Future<void> _tomarFoto() async {
    if (_fotos.length >= 2) return;
    try {
      final img = await _picker.pickImage(
          source: ImageSource.camera, imageQuality: 90, maxWidth: 1000, maxHeight: 1000);
      if (img != null && mounted) setState(() => _fotos.add(img));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Cámara no disponible, usa la galería'),
        backgroundColor: appTeal,
      ));
    }
  }

  bool _publicando = false;
  double _progreso = 0;
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
    // Después de cada await hay que re-verificar mounted antes de setState:
    // la detección puede tardar y la usuaria puede haber salido de la
    // pantalla mientras tanto (setState tras dispose es una excepción).
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Activa el GPS en tu dispositivo')));
      setState(() => _detectandoUbicacion = false);
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        setState(() => _detectandoUbicacion = false);
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      // "Habilítalo en Ajustes" solo no le dice a la usuaria QUÉ tocar ni
      // A DÓNDE ir — con un botón que abre directo la pantalla de permisos
      // de la app no hace falta que busque nada por su cuenta.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
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
    // Con timeLimit: si el GPS tarda demasiado (señal débil, adentro de un
    // edificio) o falla por cualquier motivo, esto antes podía quedar
    // esperando para siempre sin avisar nada — ahora se rinde a los 12
    // segundos y deja reintentar. La ubicación de todas formas es opcional
    // para publicar (ver _publicar()), así que un fallo acá nunca bloquea.
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
        _lugarCtl.text = ciudad;
        _paisCodigo = paisCodigo;
        _detectandoUbicacion = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _detectandoUbicacion = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo detectar tu ubicación. Podés tocar para '
              'reintentar, o publicar igual sin ubicación exacta.')));
    }
  }

  /// Comprime la foto a JPEG liviano antes de subirla a Storage. El límite
  /// de 1000px ya no es por el límite de 1 MiB de un doc de Firestore (las
  /// fotos ya no viven ahí) — se mantiene igual que antes solo para no
  /// subir fotos más pesadas de lo necesario para el feed/detalle.
  Future<Uint8List> _normalizarFoto(String path) async {
    final bytes = await File(path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final rotated = img.bakeOrientation(decoded);
    final resized = rotated.width > 1000
        ? img.copyResize(rotated, width: 1000)
        : rotated;
    return img.encodeJpg(resized, quality: 80);
  }

  Future<void> _publicar() async {
    if (_fotos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes agregar al menos una foto del animal')));
      return;
    }
    // La ubicación ya no bloquea la publicación — antes, si el GPS fallaba
    // o tardaba (señal débil, permiso recién concedido, lo que sea), el
    // rescatista quedaba sin poder publicar y sin un aviso claro de por qué.
    // Ahora se avisa y se deja elegir: publicar igual (sin distancia en el
    // feed hasta que se agregue la ubicación editando) o cancelar y reintentar.
    if (_latitud == null && !widget.esAlbergue) {
      final continuar = await showDialog<bool>(
        context: context,
        builder: (dlgCtx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Sin ubicación detectada'),
          content: const Text(
              'No se detectó tu ubicación GPS. Podés publicar igual — el animal '
              'no va a aparecer con distancia en el feed hasta que agregues la '
              'ubicación más tarde, editando la publicación.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx, false),
              child: const Text('Volver y detectar de nuevo'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx, true),
              child: const Text('Publicar sin ubicación', style: TextStyle(color: appTeal)),
            ),
          ],
        ),
      );
      // "Volver y detectar de nuevo" antes solo cerraba el diálogo y
      // dejaba al rescatista de nuevo en el formulario sin indicar qué
      // hacer — el botón decía "reintentar" pero no reintentaba nada.
      // Ahora dispara la detección de GPS de una, en vez de obligarlo a
      // encontrar y tocar el campo de ubicación por su cuenta.
      if (continuar != true) {
        if (mounted && !_detectandoUbicacion) _obtenerUbicacionGPS();
        return;
      }
    }
    setState(() { _publicando = true; _progreso = 0; });

    final fotosRepo = RescateFotosRepository();
    String? rescateId;
    var foto2Fallo = false;

    try {
      final foto1Bytes = await _normalizarFoto(_fotos[0].path);
      final foto2Bytes = _fotos.length > 1 ? await _normalizarFoto(_fotos[1].path) : null;

      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      var nombrePublicador = FirebaseAuth.instance.currentUser?.displayName ?? 'Rescatista';
      String? fotoPublicadorBase64;
      String? fotoPublicadorUrl;
      if (widget.esAlbergue) {
        final userDoc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
        final albergueNombre = userDoc.data()?['albergueNombre'] as String?;
        if (albergueNombre != null && albergueNombre.isNotEmpty) nombrePublicador = albergueNombre;
        fotoPublicadorBase64 = userDoc.data()?['fotoBase64'] as String?;
      } else {
        fotoPublicadorUrl = FirebaseAuth.instance.currentUser?.photoURL;
      }

      // 1) Crear el doc SIN fotos todavía — storage.rules necesita que el
      // rescate ya exista (con el rescatistaId correcto) para poder
      // verificar dueño cuando se suba la foto en el paso 2.
      //
      // Cada paso de red tiene un .timeout() a propósito: sin conexión
      // (ej. modo avión), tanto el write de Firestore como la subida a
      // Storage se quedan esperando sin nunca completar ni fallar — el
      // try/catch de acá abajo nunca llegaba a dispararse, y la app
      // quedaba "colgada" (spinner infinito, sin ningún mensaje) hasta que
      // volvía la señal. El timeout fuerza el error para que el catch
      // pueda avisar y hacer el rollback.
      final ref = await RescatesRepository().crear(
        uid: uid,
        role: widget.esAlbergue ? CreatorRole.albergue : CreatorRole.rescatista,
        datos: {
          'nombre':           _nombreCtl.text.trim(),
          'especie':          _especie,
          'raza':             _tipoRaza == 'Criolla' ? 'Criolla' : _razaCtl.text.trim().isEmpty ? 'Raza definida' : _razaCtl.text.trim(),
          'estado':           _estado,
          'urgencia':         _urgencia,
          'ubicacion':        _lugarCtl.text.trim(),
          'descripcion':      _descCtl.text.trim(),
          'estadoAdopcion':   'Rescatado',
          'rescatistaNombre':    nombrePublicador,
          if (fotoPublicadorBase64 != null) 'rescatistaFotoBase64': fotoPublicadorBase64,
          if (fotoPublicadorUrl    != null) 'rescatistaFotoUrl':    fotoPublicadorUrl,
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
        },
      ).timeout(const Duration(seconds: 15), onTimeout: () =>
          throw Exception('No hay conexión a internet. Revisá tu wifi/datos e intentá de nuevo.'));
      rescateId = ref.id;

      // 2) Foto obligatoria — si falla, no tiene sentido dejar un rescate
      // sin ninguna foto: se hace rollback completo (ver catch de abajo).
      final fotoUrl = await fotosRepo.subir(
        rescateId: rescateId, slot: 1, bytes: foto1Bytes,
        onProgreso: (p) {
          if (mounted) setState(() => _progreso = foto2Bytes != null ? p / 2 : p);
        },
      ).timeout(const Duration(seconds: 45), onTimeout: () =>
          throw Exception('No hay conexión a internet. Revisá tu wifi/datos e intentá de nuevo.'));

      // 3) Segunda foto — opcional: si falla, se publica igual sin ella en
      // vez de perder todo el trabajo ya hecho.
      String? fotoUrl2;
      if (foto2Bytes != null) {
        try {
          fotoUrl2 = await fotosRepo.subir(
            rescateId: rescateId, slot: 2, bytes: foto2Bytes,
            onProgreso: (p) {
              if (mounted) setState(() => _progreso = 0.5 + p / 2);
            },
          ).timeout(const Duration(seconds: 45), onTimeout: () =>
              throw Exception('tiempo agotado'));
        } catch (_) {
          foto2Fallo = true;
        }
      }

      // 4) Vincular las fotos ya subidas al doc.
      await RescatesRepository().actualizar(rescateId, {
        'fotoUrl': fotoUrl,
        if (fotoUrl2 != null) 'fotoUrl2': fotoUrl2,
      }).timeout(const Duration(seconds: 15), onTimeout: () =>
          throw Exception('No hay conexión a internet. Revisá tu wifi/datos e intentá de nuevo.'));

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('¡Rescate publicado! 🐾'),
          content: Text('${_nombreCtl.text.isEmpty ? "El animal" : _nombreCtl.text} '
              'fue publicado con urgencia $_urgencia'
              '${_lugarCtl.text.isNotEmpty ? ' en ${_lugarCtl.text}' : ''}.'
              '${foto2Fallo ? ' La segunda foto no se pudo subir — podés agregarla después editando la publicación.' : ''}'),
          actions: [
            TextButton(
              onPressed: () { Navigator.pop(context); Navigator.pop(context); },
              child: const Text('Ver rescates', style: TextStyle(color: appTeal)),
            ),
          ],
        ),
      );
    } catch (e) {
      // Rollback: si el doc llegó a crearse pero algo después falló (la
      // foto obligatoria, o el paso 4), no dejar un rescate fantasma sin
      // datos — se borra el doc y cualquier foto que haya llegado a subir.
      // try/catch por paso (no .catchError): un catchError con el tipo
      // equivocado revienta DENTRO de este catch y el SnackBar de abajo
      // nunca llega a mostrarse — el bug de "toco publicar y no pasa nada".
      if (rescateId != null) {
        final id = rescateId;
        try { await RescatesRepository().eliminar(id); } catch (_) {}
        try { await fotosRepo.eliminarTodas(id); } catch (_) {}
      }
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
                              'Ya pasó por mucho. Ahora solo le falta alguien que decida quedarse. '
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
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(height: 20, width: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2,
                      value: _progreso > 0 ? _progreso : null)),
              if (_progreso > 0) ...[
                const SizedBox(width: 10),
                Text('${(_progreso * 100).round()}%',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
              ],
            ])
          : const Text('Publicar rescate 🐾', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    ),
  );
}
