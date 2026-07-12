import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import '../theme.dart';
import '../compatibilidad.dart';
import '../data/rescates_repository.dart';
import '../data/preferencias_repository.dart';
import 'animal_detalle_screen.dart';
import 'albergue_publico_screen.dart';
import 'aliado_publico_screen.dart';
import 'solicitud_adopcion_screen.dart';
import 'chat_screen.dart';

// Tarjeta cuadrada (1080x1080) tipo post de Instagram, generada a partir de la
// foto del animal para que compartir se vea como una publicación de marca en
// vez de la foto pelada.
class _ShareCard extends StatelessWidget {
  final String nombre;
  final String especie;
  final String edad;
  final String ubicacion;
  final Uint8List fotoBytes;
  const _ShareCard({
    required this.nombre,
    required this.especie,
    required this.edad,
    required this.ubicacion,
    required this.fotoBytes,
  });

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        Image.memory(fotoBytes, fit: BoxFit.cover),
        DecoratedBox(decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.78)],
            stops: const [0.35, 1.0],
          ),
        )),
        Positioned(
          top: 48, left: 48,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            decoration: BoxDecoration(color: appTeal, borderRadius: BorderRadius.circular(32)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Text('🐾', style: TextStyle(fontSize: 26)),
              SizedBox(width: 10),
              Text('Salva Patitas', style: TextStyle(
                  color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
            ]),
          ),
        ),
        Positioned(
          left: 48, right: 48, bottom: 56,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(color: appOrange, borderRadius: BorderRadius.circular(32)),
              child: const Text('¡Necesito un hogar!', style: TextStyle(
                  color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 22),
            Text(nombre, style: const TextStyle(
                color: Colors.white, fontSize: 68, fontWeight: FontWeight.w900, height: 1.0)),
            const SizedBox(height: 10),
            Text(
              [if (especie.isNotEmpty) especie, if (edad.isNotEmpty) edad].join(' · '),
              style: const TextStyle(color: Colors.white70, fontSize: 30, fontWeight: FontWeight.w600),
            ),
            if (ubicacion.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(children: [
                const Icon(Icons.location_on, color: Colors.white70, size: 26),
                const SizedBox(width: 6),
                Text(ubicacion, style: const TextStyle(color: Colors.white70, fontSize: 26)),
              ]),
            ],
          ]),
        ),
      ]);
}

Future<Uint8List?> _renderShareCardToPng(BuildContext context, Widget card, {double size = 1080}) async {
  final key = GlobalKey();
  final overlay = Overlay.of(context, rootOverlay: true);
  // La tarjeta se arma DENTRO del área visible (no fuera de pantalla): en
  // algunos dispositivos, una imagen posicionada fuera de la vista nunca
  // llega a pintarse (aunque los colores/textos sí), y la captura sale sin
  // foto. Para que el usuario no vea el proceso, se tapa con un scrim +
  // spinner por encima.
  final cardEntry = OverlayEntry(
    builder: (_) => Positioned(
      left: 0, top: 0,
      child: Material(
        color: Colors.transparent,
        child: RepaintBoundary(key: key, child: SizedBox(width: size, height: size, child: card)),
      ),
    ),
  );
  final scrimEntry = OverlayEntry(
    builder: (_) => Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      ),
    ),
  );
  overlay.insert(cardEntry);
  overlay.insert(scrimEntry);
  try {
    // Espera de tiempo fijo, no endOfFrame — endOfFrame puede quedar
    // colgado esperando un cuadro que nunca se vuelve a programar, y eso
    // congela toda la pantalla (le pasó a una usuaria en un dispositivo real).
    await Future.delayed(const Duration(milliseconds: 300));
    final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 1.0).timeout(const Duration(seconds: 5));
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png)
        .timeout(const Duration(seconds: 5));
    return byteData?.buffer.asUint8List();
  } finally {
    scrimEntry.remove();
    cardEntry.remove();
  }
}

Future<void> compartirAnimal({
  required BuildContext context,
  required String nombre,
  required String especie,
  required String edad,
  required String ubicacion,
  required List<String> tags,
  String? fotoUrl,
}) async {
  final emoji = especie == 'Gato' ? '🐱' : '🐶';
  final tagsTexto = tags.isNotEmpty ? tags.map((t) => '✅ $t').join('  ') : '';
  final texto = '$emoji *$nombre* necesita un hogar!\n'
      '${[if (especie.isNotEmpty) especie, if (edad.isNotEmpty) edad].join(' · ')}\n'
      '📍 $ubicacion\n'
      '${tagsTexto.isNotEmpty ? '$tagsTexto\n' : ''}'
      '\n¡Ayúdalo a encontrar familia descargando *Salva Patitas* 💚';

  // La foto ya no es un string local (base64) — hay que bajarla de Storage
  // antes de poder compartirla como archivo. Si falla (sin red, URL rota),
  // se comparte solo el texto en vez de romper el flujo de compartir.
  Uint8List? fotoBytes;
  if (fotoUrl != null) {
    try {
      fotoBytes = await FirebaseStorage.instance.refFromURL(fotoUrl).getData();
    } catch (_) {}
  }
  if (fotoBytes != null) {
    Uint8List? cardBytes;
    try {
      // Decodifica la imagen ANTES de capturar la tarjeta — Image.memory no
      // pinta de forma instantánea, y sin este paso la captura puede ganarle
      // la carrera al decode y salir en negro.
      final fotoProvider = MemoryImage(fotoBytes);
      if (context.mounted) {
        await precacheImage(fotoProvider, context);
        if (context.mounted) {
          cardBytes = await _renderShareCardToPng(
            context,
            _ShareCard(nombre: nombre, especie: especie, edad: edad, ubicacion: ubicacion, fotoBytes: fotoBytes),
          );
        }
      }
    } catch (_) {}
    // fotoBytes ya se validó arriba (bytesFotoSegura), así que este
    // fallback no puede volver a fallar por el mismo dato corrupto.
    final xfile = cardBytes != null
        ? XFile.fromData(cardBytes, mimeType: 'image/png', name: '$nombre.png')
        : XFile.fromData(fotoBytes, mimeType: 'image/jpeg', name: '$nombre.jpg');
    await Share.shareXFiles([xfile], text: texto);
  } else {
    await Share.share(texto);
  }
}


class AdoptanteFeedScreen extends StatefulWidget {
  const AdoptanteFeedScreen();
  @override
  State<AdoptanteFeedScreen> createState() => _AdoptanteFeedScreenState();
}

class _AdoptanteFeedScreenState extends State<AdoptanteFeedScreen> {
  int _idx = 0;
  Position? _userPosition;
  bool _posicionPrecisa = false;
  Map<String, dynamic>? _perfilAdopcion;
  String _prefEspecie = 'Ambos';
  String _prefTamano  = 'Cualquiera';
  String _prefEdad    = 'Cualquiera';
  StreamSubscription? _prefSub;
  StreamSubscription? _perfilAdopcionSub;
  final _fotoPageNotifier = ValueNotifier<int>(0);
  // Animales recién marcados como favoritos en esta sesión: se ocultan del
  // feed al instante, sin esperar a que Firestore confirme el favorito.
  // Antes se avanzaba _idx a mano Y la lista se achicaba sola cuando
  // Firestore confirmaba — las dos cosas juntas salteaban un animal.
  final Set<String> _favoritosRecientes = {};

  @override
  void initState() {
    super.initState();
    _obtenerPosicion();
    _suscribirPerfil();
  }

  void _suscribirPerfil() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _prefSub = FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .snapshots()
        .listen((doc) {
      if (!doc.exists || !mounted) return;
      final data = doc.data() as Map<String, dynamic>;
      setState(() {
        _prefEspecie = data['prefEspecie'] ?? 'Ambos';
        _prefTamano  = data['prefTamano']  ?? 'Cualquiera';
        _prefEdad    = data['prefEdad']    ?? 'Cualquiera';
      });
    });
    // perfilAdopcion vive en preferencias/{uid} (privado, solo el dueño lo
    // lee), no en usuarios/{uid} (legible por cualquier usuario logueado
    // porque hay perfiles públicos) — ver ARCHITECTURE.md.
    _perfilAdopcionSub = PreferenciasRepository().stream(uid).listen((doc) {
      if (!doc.exists || !mounted) return;
      final perfil = doc.data()?['perfilAdopcion'];
      if (perfil != null) {
        setState(() => _perfilAdopcion = Map<String, dynamic>.from(perfil));
      }
    });
  }

  @override
  void dispose() {
    _prefSub?.cancel();
    _perfilAdopcionSub?.cancel();
    _fotoPageNotifier.dispose();
    super.dispose();
  }

  int _calcularScore(Map<String, dynamic> animal) {
    if (_perfilAdopcion == null) return -1;
    return calcularCompatibilidad({
      ...animal,
      'animalEnergia':       animal['energia'],
      'animalTamano':        animal['tamano'],
      'animalOkConNinos':    animal['okConNinos'],
      'animalOkConMascotas': animal['okConMascotas'],
      'animalRequiereExp':   animal['requiereExperiencia'],
      ..._perfilAdopcion!,
    });
  }

  Future<void> _obtenerPosicion() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled()
          .timeout(const Duration(seconds: 3), onTimeout: () => false);
      if (!serviceEnabled) return;
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) return;
      }
      if (perm == LocationPermission.deniedForever) return;
      // Intenta posición conocida primero (más rápido)
      Position? pos = await Geolocator.getLastKnownPosition();
      if (pos != null && mounted) {
        setState(() => _userPosition = pos);
      }
      // Luego actualiza con posición actual
      pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 10),
          ));
      if (mounted) setState(() {
        _userPosition = pos;
        _posicionPrecisa = true;
      });
    } catch (_) {}
  }

  String _distancia(Map<String, dynamic> animal) {
    final lat = animal['latitud']  as double?;
    final lng = animal['longitud'] as double?;
    if (lat == null || lng == null || _userPosition == null) return '';
    final metros = Geolocator.distanceBetween(
        _userPosition!.latitude, _userPosition!.longitude, lat, lng);
    if (metros < 1000) return '${metros.round()} m';
    return '${(metros / 1000).toStringAsFixed(1)} km';
  }


  Future<void> _guardarFavorito(Map<String, dynamic> animal) async {
    final uid       = FirebaseAuth.instance.currentUser?.uid ?? '';
    final rescateId = animal['rescateId'] as String? ?? '';
    final docId = rescateId.isNotEmpty
        ? '${uid}_$rescateId'
        : '${uid}_${(animal['nombre'] as String? ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    await FirebaseFirestore.instance.collection('favoritos').doc(docId).set({
      'adoptanteId':  uid,
      'animalNombre': animal['nombre'],
      'especie':      animal['especie'],
      'edad':         animal['edad'],
      'ubicacion':    animal['ubicacion'],
      'descripcion':  animal['descripcion'],
      'tags':         animal['tags'],
      'rescatista':   animal['rescatista'],
      'rescatistaId': animal['rescatistaId'] ?? '',
      'rescateId':    animal['rescateId']    ?? '',
      'genero':       animal['genero'] ?? '',
      'fotoUrl':      animal['fotoUrl'],
      'verificado':   animal['verificado'] ?? false,
      'creadoPor':    animal['creadoPor'] ?? 'rescatista',
      'creadoEn':     FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('favoritos')
          .where('adoptanteId', isEqualTo: uid)
          .snapshots(),
      builder: (context, favSnap) {
        // Animales ya guardados en Favoritos: no hace falta mostrarlos de
        // nuevo en el feed principal, ya quedan a mano en esa pestaña.
        final favRescateIds = (favSnap.data?.docs ?? [])
            .map((d) => (d.data() as Map<String, dynamic>)['rescateId'] as String? ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();
        // _favoritosRecientes solo existe para tapar la ventana entre
        // "tocaste el corazón acá" y "Firestore ya confirmó el favorito".
        // Apenas el favorito aparece confirmado en favRescateIds, se lo
        // saca de la lista local: desde ahí lo oculta la fuente de verdad,
        // y si más tarde se le quita el corazón (desde cualquier pantalla)
        // desaparece de favRescateIds y reaparece solo en el carrusel.
        // OJO: la condición es "confirmado" y no "ausente" a propósito —
        // podar los ausentes borraría el id recién agregado en el rebuild
        // que dispara el propio toque del corazón (que corre con el
        // snapshot viejo, sin el favorito todavía) y la tarjeta parpadearía.
        _favoritosRecientes.removeWhere(favRescateIds.contains);
        return StreamBuilder<QuerySnapshot>(
      stream: RescatesRepository().feedPublico(),
      builder: (context, snap) {
        if (snap.hasError) return errorFeedState();
        final firestoreDocs = (snap.data?.docs ?? []).where((doc) {
          if (favRescateIds.contains(doc.id) || _favoritosRecientes.contains(doc.id)) return false;
          final d = doc.data() as Map<String, dynamic>;
          final estado = d['estadoAdopcion'] as String?;
          if (!(estado == null || estado == 'Rescatado' || estado == 'Regresado' || estado == 'Hogar de paso')) return false;
          final especie = d['especie'] as String? ?? 'Perro';
          if (_prefEspecie != 'Ambos' && especie != _prefEspecie) return false;
          final tamano = d['tamano'] as String? ?? '';
          if (_prefTamano != 'Cualquiera' && tamano != _prefTamano) return false;
          final edad = d['edad'] as String? ?? '';
          if (_prefEdad != 'Cualquiera' && edad != _prefEdad) return false;
          // filtro por país deshabilitado — se activa cuando haya masa crítica de animales por región
          return true;
        }).toList()
          // Más nuevos primero. Sin campo `creadoEn` (legado) se van al final
          // en vez de desaparecer del feed — ver feedPublico() en el repo.
          ..sort((a, b) {
            final ta = (a.data() as Map<String, dynamic>)['creadoEn'] as Timestamp?;
            final tb = (b.data() as Map<String, dynamic>)['creadoEn'] as Timestamp?;
            if (ta == null && tb == null) return 0;
            if (ta == null) return 1;
            if (tb == null) return -1;
            return tb.compareTo(ta);
          });
        final animals = <Map<String, dynamic>>[
          ...firestoreDocs.map((doc) {
            final d = doc.data() as Map<String, dynamic>;
            return {
              'nombre':              (d['nombre'] as String?)?.isNotEmpty == true ? d['nombre'] : 'Sin nombre',
              'edad':                d['edad']       ?? '',
              'genero':              d['genero']     ?? '',
              'especie':             d['especie']    ?? 'Perro',
              'raza':                d['raza']       ?? 'Criolla',
              'tamano':              d['tamano']     ?? 'Mediano',
              'ubicacion':           d['ubicacion']  ?? '',
              'distancia':           '~',
              'descripcion':         d['descripcion'] ?? '',
              'tags':                <String>[
                                      if (d['okConNinos']    == true)  'Amigable con niños',
                                      if (d['okConMascotas'] == true)  'Es sociable',
                                      if ((d['energia'] as String?)?.isNotEmpty == true) d['energia'] as String,
                                      if (d['estado'] != null && d['estado'] != 'Sano') d['estado'] as String,
                                    ],
              'rescatista':          d['rescatistaNombre'] ?? 'Rescatista',
              'rescatistaId':        d['rescatistaId'] ?? '',
              'rescatistaFotoBase64': d['rescatistaFotoBase64'],
              'rescatistaFotoUrl':   d['rescatistaFotoUrl'],
              'rescateId':           doc.id,
              'estadoAdopcion':      d['estadoAdopcion'] ?? '',
              'fotoUrl':             d['fotoUrl'],
              'fotoUrl2':            d['fotoUrl2'],
              'latitud':             d['latitud'],
              'longitud':            d['longitud'],
              'energia':             d['energia'],
              'okConNinos':          d['okConNinos'],
              'okConMascotas':       d['okConMascotas'],
              'requiereExperiencia': d['requiereExperiencia'],
              'urgencia':            d['urgencia'] ?? '',
              'creadoPor':           d['creadoPor'] ?? '',
            };
          }),
        ];

        // Ordenar por distancia si hay posición disponible
        if (_userPosition != null) {
          animals.sort((a, b) {
            final latA = a['latitud'] as double?;
            final lngA = a['longitud'] as double?;
            final latB = b['latitud'] as double?;
            final lngB = b['longitud'] as double?;
            if (latA == null || lngA == null) return 1;
            if (latB == null || lngB == null) return -1;
            final dA = Geolocator.distanceBetween(
                _userPosition!.latitude, _userPosition!.longitude, latA, lngA);
            final dB = Geolocator.distanceBetween(
                _userPosition!.latitude, _userPosition!.longitude, latB, lngB);
            return dA.compareTo(dB);
          });
        }

        if (_idx >= animals.length) return _emptyState();

        final animal = animals[_idx];

        // Detectar si el más cercano está lejos (>500 km) — solo con posición precisa,
        // para evitar mostrar el aviso con la ubicación rápida/desactualizada inicial
        bool sinAnimalesCerca = false;
        if (_posicionPrecisa && _userPosition != null && animals.isNotEmpty) {
          final lat = animals[0]['latitud'] as double?;
          final lng = animals[0]['longitud'] as double?;
          if (lat != null && lng != null) {
            final metros = Geolocator.distanceBetween(
                _userPosition!.latitude, _userPosition!.longitude, lat, lng);
            sinAnimalesCerca = metros > 500000;
          }
        }

        final distancia = _distancia(animal);
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: SizedBox(
              width: double.infinity,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if ((animal['ubicacion'] as String? ?? '').isNotEmpty)
                  Text(
                      distancia.isNotEmpty
                          ? 'EN ${(animal['ubicacion'] as String? ?? '').toUpperCase()} · A ${distancia.toUpperCase()} DE TI'
                          : 'EN ${(animal['ubicacion'] as String? ?? '').toUpperCase()}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                          letterSpacing: 1.2, color: appTeal)),
                const Text('Animales disponibles',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A))),
              ]),
            ),
          ),
          if (sinAnimalesCerca)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8F0),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE65100).withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  const Text('📍', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'No hay animales cerca de ti. Mostrando todos los disponibles.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF8B4513)),
                    ),
                  ),
                ]),
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SingleChildScrollView(
                child: _buildCard(animal, distancia, _calcularScore(animal)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _actionBtn(Icons.close, Colors.grey.shade200, Colors.grey.shade600, 52, () {
                _fotoPageNotifier.value = 0;
                setState(() => _idx++);
              }),
              const SizedBox(width: 18),
              _actionBtn(Icons.pets, Colors.white, const Color(0xFF1A1A1A), 46, () {
                Navigator.push(context, MaterialPageRoute(
                    builder: (_) => AnimalDetalleScreen(animal: animal)));
              }),
              const SizedBox(width: 18),
              _actionBtn(Icons.favorite, appOrange, Colors.white, 62, () async {
                // Se oculta de una (sin avanzar _idx a mano): la lista se
                // achica sola y el siguiente animal ocupa este mismo lugar.
                final favRescateId = animal['rescateId'] as String? ?? '';
                final messenger = ScaffoldMessenger.of(context);
                _fotoPageNotifier.value = 0;
                if (favRescateId.isNotEmpty) setState(() => _favoritosRecientes.add(favRescateId));
                try {
                  await _guardarFavorito(animal);
                } catch (e) {
                  if (!mounted) return;
                  if (favRescateId.isNotEmpty) setState(() => _favoritosRecientes.remove(favRescateId));
                  messenger.showSnackBar(const SnackBar(
                      content: Text('No se pudo guardar el favorito. Intentá de nuevo.')));
                }
              }),
            ]),
          ),
        ]);
      },
    );
      },
    );
  }

  Widget _emptyState() {
    return SingleChildScrollView(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: SizedBox(
            width: double.infinity,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('SALVA PATITAS', style: TextStyle(fontSize: 11,
                  fontWeight: FontWeight.w600, letterSpacing: 1.2, color: appTeal)),
              const Text('Cerca de ti',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
            ]),
          ),
        ),
        const SizedBox(height: 40),
        Container(
          width: 90, height: 90,
          decoration: BoxDecoration(
            color: appOrange.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.pets, size: 44, color: appOrange),
        ),
        const SizedBox(height: 20),
        const Text('Eso es todo por hoy',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
        const SizedBox(height: 8),
        Text('Vuelve mañana, nuevos amigos\nllegan cada día.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.5)),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () => setState(() => _idx = 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
            decoration: BoxDecoration(color: appOrange, borderRadius: BorderRadius.circular(30)),
            child: const Text('Ver de nuevo',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 36),
        _aliadosSection(),
        const SizedBox(height: 32),
      ]),
    );
  }

  Widget _aliadosSection() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('usuarios')
          .where('aliadoNombre', isGreaterThan: '')
          .snapshots(),
      builder: (context, snap) {
        final aliados = snap.data?.docs ?? [];
        if (aliados.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              const Text('NEGOCIOS ALIADOS', style: TextStyle(fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 1.2, color: appTeal)),
              const SizedBox(width: 6),
              Text('🐾', style: const TextStyle(fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: aliados.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final d      = aliados[i].data() as Map<String, dynamic>;
                final nombre = d['aliadoNombre'] as String? ?? 'Aliado';
                final tipo   = d['aliadoTipo']   as String? ?? '';
                final foto   = d['fotoBase64']   as String?;
                final ini    = nombre.isNotEmpty ? nombre[0].toUpperCase() : 'A';
                final uid    = aliados[i].id;

                return GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => AliadoPublicoScreen(aliadoId: uid, esRescatista: false))),
                  child: Container(
                    width: 100,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 8, offset: const Offset(0, 2))],
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Builder(builder: (_) {
                        final fotoBytes = bytesFotoSegura(foto);
                        return CircleAvatar(
                          radius: 26,
                          backgroundColor: appTeal.withValues(alpha: 0.12),
                          backgroundImage: fotoBytes != null ? MemoryImage(fotoBytes) : null,
                          onBackgroundImageError: fotoBytes != null ? (_, __) {} : null,
                          child: fotoBytes == null
                              ? Text(ini, style: const TextStyle(
                                  color: appTeal, fontWeight: FontWeight.bold, fontSize: 18))
                              : null,
                        );
                      }),
                      const SizedBox(height: 8),
                      Text(nombre, style: const TextStyle(fontSize: 11,
                          fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
                          textAlign: TextAlign.center, maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      if (tipo.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(tipo, style: TextStyle(fontSize: 9,
                            color: Colors.grey.shade500),
                            textAlign: TextAlign.center, maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ]),
                  ),
                );
              },
            ),
          ),
        ]);
      },
    );
  }

  Widget _flechaFoto(IconData icon, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.all(8),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.38),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
        ),
      );

  Widget _buildCard(Map<String, dynamic> a, String distancia, int score) {
    final fotoUrl  = a['fotoUrl']  as String?;
    final fotoUrl2 = a['fotoUrl2'] as String?;
    final fotos = [if (fotoUrl != null) fotoUrl, if (fotoUrl2 != null) fotoUrl2];
    final nombre      = a['nombre']     as String;
    final edad        = a['edad']       as String;
    final raza        = a['raza']       as String;
    final tamano      = a['tamano']     as String;
    final descripcion = a['descripcion'] as String;
    final tags        = (a['tags'] as List).cast<String>();
    final rescatista  = a['rescatista'] as String;
    final ubicacion   = a['ubicacion']  as String;
    final verificado      = a['verificado']     as bool?   ?? false;
    final estadoAdopcion  = a['estadoAdopcion'] as String? ?? '';
    final urgencia        = a['urgencia']       as String? ?? '';
    final creadoPor       = a['creadoPor']      as String? ?? '';
    final rescatistaId    = a['rescatistaId']   as String? ?? '';
    final rescatistaFotoBase64 = a['rescatistaFotoBase64'] as String?;
    final rescatistaFotoUrl    = a['rescatistaFotoUrl']    as String?;
    final rescateId       = a['rescateId']      as String? ?? '';
    final especie         = a['especie'] as String? ?? '';
    final emoji           = especie == 'Gato' ? '🐱' : '🐶';

    Color scoreColor(int s) {
      if (s >= 80) return const Color(0xFF1F8A62);
      if (s >= 60) return const Color(0xFFE65100);
      return const Color(0xFFB71C1C);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.09), blurRadius: 18, offset: const Offset(0, 4))],
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: (details) {
              if (fotos.length < 2 || details.primaryVelocity == null) return;
              final curr = _fotoPageNotifier.value;
              if (details.primaryVelocity! < -80 && curr < fotos.length - 1) {
                _fotoPageNotifier.value = curr + 1;
              } else if (details.primaryVelocity! > 80 && curr > 0) {
                _fotoPageNotifier.value = curr - 1;
              }
            },
            child: SizedBox(
            height: 300,
            child: Stack(fit: StackFit.expand, children: [
              fotos.isNotEmpty
                ? ValueListenableBuilder<int>(
                    valueListenable: _fotoPageNotifier,
                    builder: (_, fotoIdx, _) => AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: SizedBox.expand(
                        key: ValueKey(fotoIdx),
                        child: FotoUrl(
                          url: fotos[fotoIdx],
                          fit: BoxFit.cover,
                          fallback: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft, end: Alignment.bottomRight,
                                colors: [Color(0xFF3D7A52), Color(0xFF1F4A30)],
                              ),
                            ),
                            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 90))),
                          ),
                        ),
                      ),
                    ),
                  )
                : Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [Color(0xFF3D7A52), Color(0xFF1F4A30)],
                      ),
                    ),
                    child: Center(child: Text(emoji, style: const TextStyle(fontSize: 90))),
                  ),
              if (fotos.length > 1)
                Positioned(
                  top: 10, left: 0, right: 0,
                  child: ValueListenableBuilder<int>(
                    valueListenable: _fotoPageNotifier,
                    builder: (_, pageIdx, _) => Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(fotos.length, (i) => GestureDetector(
                        onTap: () => _fotoPageNotifier.value = i,
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: pageIdx == i ? 18 : 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: pageIdx == i ? Colors.white : Colors.white.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      )),
                    ),
                  ),
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.68)],
                      stops: const [0.45, 1.0],
                    ),
                  ),
                ),
              ),
              if (urgencia == 'Alta')
                Positioned(
                  top: 0, left: 0, right: 0,
                  child: Container(
                    color: const Color(0xFFD32F2F),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 13, color: Colors.white),
                        SizedBox(width: 6),
                        Text('URGENTE · NECESITA HOGAR YA',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.8)),
                      ],
                    ),
                  ),
                ),
              if (ubicacion.isNotEmpty || distancia.isNotEmpty)
                Positioned(top: urgencia == 'Alta' ? 40 : 12, left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.location_on, size: 12, color: appTeal),
                      const SizedBox(width: 3),
                      Text(
                        ubicacion.isNotEmpty ? ubicacion : distancia,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    ]),
                  )),
              Positioned(top: urgencia == 'Alta' ? 40 : 12, right: 12, left: 90,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 6, runSpacing: 6,
                  children: [
                  if (estadoAdopcion == 'Hogar de paso')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(color: appTeal, borderRadius: BorderRadius.circular(20)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.home_outlined, size: 11, color: Colors.white),
                        SizedBox(width: 3),
                        Text('Hogar de paso', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                      ]),
                    ),
                  if (estadoAdopcion == 'Regresado')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFFE65100), borderRadius: BorderRadius.circular(20)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.refresh, size: 11, color: Colors.white),
                        SizedBox(width: 3),
                        Text('Fue devuelto', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                      ]),
                    ),
                  if (score >= 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                          color: scoreColor(score), borderRadius: BorderRadius.circular(20)),
                      child: Text('$score% compatible',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  if (verificado)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(color: appTeal, borderRadius: BorderRadius.circular(20)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.verified, size: 11, color: Colors.white),
                        SizedBox(width: 3),
                        Text('Verificado',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
                      ]),
                    ),
                ])),
              if (fotos.length > 1)
                Positioned.fill(
                  child: ValueListenableBuilder<int>(
                    valueListenable: _fotoPageNotifier,
                    builder: (_, pageIdx, _) => Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        pageIdx > 0
                            ? _flechaFoto(Icons.chevron_left,
                                () => _fotoPageNotifier.value = pageIdx - 1)
                            : const SizedBox(width: 52),
                        pageIdx < fotos.length - 1
                            ? _flechaFoto(Icons.chevron_right,
                                () => _fotoPageNotifier.value = pageIdx + 1)
                            : const SizedBox(width: 52),
                      ],
                    ),
                  ),
                ),
              Positioned(bottom: 14, left: 16,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  RichText(text: TextSpan(
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                    children: [
                      TextSpan(text: '$nombre, '),
                      TextSpan(text: edad,
                          style: const TextStyle(color: Color(0xFFB8F0CC), fontWeight: FontWeight.w400)),
                    ],
                  )),
                  Text('$raza · $tamano',
                      style: const TextStyle(fontSize: 13, color: Colors.white70)),
                ])),
            ]),
          ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (descripcion.isNotEmpty) ...[
                Text(descripcion,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
                    maxLines: 3, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 12),
              ],
              if (tags.isNotEmpty) ...[
                Wrap(spacing: 8, runSpacing: 6, children: tags.map((t) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    border: Border.all(color: appTeal.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(20),
                    color: appTeal.withOpacity(0.07),
                  ),
                  child: Text(t, style: const TextStyle(fontSize: 12, color: appTeal, fontWeight: FontWeight.w500)),
                )).toList()),
                const SizedBox(height: 14),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: GestureDetector(
                    onTap: (creadoPor == 'albergue' && rescatistaId.isNotEmpty)
                        ? () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => AlberguePublicoScreen(
                                rescatistaId: rescatistaId)))
                        : null,
                    child: Row(children: [
                      AvatarPersona(
                        fotoBase64: rescatistaFotoBase64,
                        fotoUrl: rescatistaFotoUrl,
                        inicial: rescatista.isNotEmpty ? rescatista[0].toUpperCase() : 'R',
                        radius: 16,
                        backgroundColor: appTeal.withValues(alpha: 0.15),
                        textColor: appTeal,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(creadoPor == 'albergue' ? 'Albergue' : 'Rescatista',
                            style: const TextStyle(fontSize: 10, color: Color(0xFFAAAAAA))),
                        Row(children: [
                          Flexible(
                            child: Text(rescatista,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: const TextStyle(fontSize: 13,
                                    fontWeight: FontWeight.w600, color: appTeal)),
                          ),
                          if (creadoPor == 'albergue') ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right, size: 14, color: appTeal),
                          ],
                        ]),
                      ])),
                    ]),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => compartirAnimal(
                      context: context,
                      nombre: nombre,
                      especie: especie,
                      edad: edad,
                      ubicacion: ubicacion,
                      tags: tags,
                      fotoUrl: fotoUrl,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: appTeal.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: appTeal.withValues(alpha: 0.25)),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.share_outlined, size: 14, color: appTeal),
                        SizedBox(width: 5),
                        Text('Compartir', style: TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w600, color: appTeal)),
                      ]),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => showModalBottomSheet(
                  context: context,
                  useSafeArea: true,
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                  builder: (_) => _MeInteresaSheet(
                    nombre: nombre,
                    especie: especie,
                    edad: edad,
                    ubicacion: ubicacion,
                    tags: tags,
                    fotoUrl: fotoUrl,
                    rescatistaId: rescatistaId,
                    rescatista: rescatista,
                    rescateId: rescateId,
                    estadoAdopcion: estadoAdopcion,
                    creadoPor: creadoPor,
                  ),
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3CD),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFFB800).withValues(alpha: 0.4)),
                  ),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('💛', style: TextStyle(fontSize: 16)),
                    SizedBox(width: 8),
                    Text('Me interesa ayudar',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                            color: Color(0xFF8B6914))),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
    );
  }

  Widget _actionBtn(IconData icon, Color bg, Color iconColor, double size, VoidCallback onTap) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 8, offset: const Offset(0, 3))]),
        child: Icon(icon, color: iconColor, size: size * 0.40),
      ),
    );
}

// ─── Pantalla de Aliados ──────────────────────────────────────────────────────

class AliadosScreen extends StatelessWidget {
  final bool esRescatista;
  const AliadosScreen({super.key, this.esRescatista = false});

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
              const Expanded(child: Text('Negocios aliados',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A)))),
            ]),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('usuarios')
                  .where('aliadoNombre', isGreaterThan: '')
                  .snapshots(),
              builder: (context, snap) {
                final aliados = snap.data?.docs ?? [];
                if (aliados.isEmpty) {
                  return Center(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Text('🐾', style: TextStyle(fontSize: 48)),
                      const SizedBox(height: 16),
                      Text('Aún no hay negocios aliados',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade500)),
                    ]),
                  );
                }
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: aliados.length,
                  itemBuilder: (_, i) {
                    final d      = aliados[i].data() as Map<String, dynamic>;
                    final nombre = d['aliadoNombre'] as String? ?? 'Aliado';
                    final tipo   = d['aliadoTipo']   as String? ?? '';
                    final foto   = d['fotoBase64']   as String?;
                    final ini    = nombre.isNotEmpty ? nombre[0].toUpperCase() : 'A';
                    final uid    = aliados[i].id;
                    return GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => AliadoPublicoScreen(aliadoId: uid, esRescatista: esRescatista))),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 8, offset: const Offset(0, 2))],
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Builder(builder: (_) {
                            final fotoBytes = bytesFotoSegura(foto);
                            return CircleAvatar(
                              radius: 34,
                              backgroundColor: appTeal.withValues(alpha: 0.12),
                              backgroundImage: fotoBytes != null ? MemoryImage(fotoBytes) : null,
                              onBackgroundImageError: fotoBytes != null ? (_, __) {} : null,
                              child: fotoBytes == null
                                  ? Text(ini, style: const TextStyle(
                                      color: appTeal, fontWeight: FontWeight.bold, fontSize: 24))
                                  : null,
                            );
                          }),
                          const SizedBox(height: 10),
                          Text(nombre,
                              style: const TextStyle(fontSize: 13,
                                  fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
                              textAlign: TextAlign.center,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          if (tipo.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(tipo,
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                textAlign: TextAlign.center,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: appTeal.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text('Ver servicios',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                                    color: appTeal)),
                          ),
                        ]),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _MeInteresaSheet extends StatelessWidget {
  final String nombre, especie, edad, ubicacion, rescatistaId, rescatista, rescateId, estadoAdopcion, creadoPor;
  final List<String> tags;
  final String? fotoUrl;

  const _MeInteresaSheet({
    required this.nombre,
    required this.especie,
    required this.edad,
    required this.ubicacion,
    required this.rescatistaId,
    required this.rescatista,
    required this.rescateId,
    required this.tags,
    required this.estadoAdopcion,
    required this.creadoPor,
    this.fotoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Text('¿Cómo querés ayudar a $nombre?',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center),
        const SizedBox(height: 20),
        if (estadoAdopcion != 'Hogar de paso') ...[
          _opcion(context,
            emoji: '🏡',
            titulo: 'Ser hogar de paso',
            subtitulo: 'Lo/la cuidás temporalmente mientras encuentra familia',
            onTap: () {
              final nav = Navigator.of(context);
              nav.pop();
              nav.push(MaterialPageRoute(
                builder: (_) => SolicitudAdopcionScreen(animal: {
                  'nombre': nombre, 'especie': especie, 'edad': edad,
                  'ubicacion': ubicacion, 'rescatista': rescatista,
                  'rescatistaId': rescatistaId, 'rescateId': rescateId,
                  'fotoUrl': fotoUrl,
                  'tipoSolicitud': 'hogar_de_paso',
                  'creadoPor': creadoPor,
                }),
              ));
            },
          ),
          const SizedBox(height: 10),
        ],
        _opcion(context,
          emoji: '💬',
          titulo: 'Hacer una pregunta',
          subtitulo: 'Escribile directamente al rescatista',
          onTap: () {
            Navigator.pop(context);
            // Abre el chat vacío (sin mensaje enlatado) para que el adoptante
            // escriba su propia pregunta. ChatScreen ya sabe crear/encontrar
            // el chat solo, usando el mismo id determinístico (rescateId+uid)
            // que el resto de la app — así este chat es uno más normal y
            // aparece en la bandeja del rescatista como cualquier otro.
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => ChatScreen(
                esRescatista: false,
                animal: {
                  'nombre': nombre, 'rescatista': rescatista,
                  'rescatistaId': rescatistaId, 'fotoUrl': fotoUrl,
                  'rescateId': rescateId, 'especie': especie,
                  'ubicacion': ubicacion, 'descripcion': '', 'tags': tags,
                  'edad': edad, 'creadoPor': creadoPor,
                },
              ),
            ));
          },
        ),
      ]),
    );
  }

  Widget _opcion(BuildContext context, {
    required String emoji, required String titulo,
    required String subtitulo, required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo, style: const TextStyle(fontSize: 14,
              fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
          const SizedBox(height: 2),
          Text(subtitulo, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ])),
        Icon(Icons.chevron_right, color: Colors.grey.shade400),
      ]),
    ),
  );
}
