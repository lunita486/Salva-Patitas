import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import '../theme.dart';
import 'animal_detalle_screen.dart';

Widget _avatar(String letter, Color color, {double radius = 22, double fontSize = 20}) {
  final user = FirebaseAuth.instance.currentUser;
  final foto = user?.photoURL;
  if (foto != null) {
    return CircleAvatar(backgroundImage: NetworkImage(foto), radius: radius);
  }
  final inicial = user?.displayName?.isNotEmpty == true
      ? user!.displayName![0].toUpperCase() : letter;
  return CircleAvatar(backgroundColor: color, radius: radius,
      child: Text(inicial, style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.bold)));
}

int calcularCompatibilidadFeed(Map<String, dynamic> solicitud) {
  int score = 0;

  final energia    = solicitud['animalEnergia']  as String? ?? 'Tranquilo';
  final horas      = int.tryParse(solicitud['horasFuera']?.toString() ?? '0') ?? 0;
  final vivienda   = solicitud['vivienda']       as String? ?? '';
  final tienePatio = vivienda == 'Casa con jardín';

  if (energia == 'Tranquilo') {
    score += 20;
  } else if (energia == 'Activo') {
    score += horas <= 8 ? 20 : 10;
  } else {
    if (tienePatio && horas <= 6) score += 20;
    else if (tienePatio || horas <= 6) score += 10;
  }

  final tamano = solicitud['animalTamano'] as String? ?? 'Mediano';
  if (tamano == 'Pequeño') {
    score += 20;
  } else if (tamano == 'Mediano') {
    score += vivienda != 'Apartamento sin área exterior' ? 20 : 10;
  } else {
    score += tienePatio ? 20 : (vivienda == 'Apartamento con balcón' ? 10 : 0);
  }

  final okNinos    = solicitud['animalOkConNinos']   as bool? ?? true;
  final tieneNinos = solicitud['tieneNinos']         as bool? ?? false;
  score += (!tieneNinos || okNinos) ? 20 : 0;

  final okMascotas    = solicitud['animalOkConMascotas'] as bool? ?? true;
  final tieneMascotas = solicitud['tieneMascotas']       as bool? ?? false;
  score += (!tieneMascotas || okMascotas) ? 20 : 0;

  final requiereExp = solicitud['animalRequiereExp']   as bool? ?? false;
  final tieneExp    = solicitud['experienciaPrevia']   as bool? ?? false;
  score += (!requiereExp || tieneExp) ? 20 : 0;

  return score;
}

class AdoptanteFeedScreen extends StatefulWidget {
  const AdoptanteFeedScreen();
  @override
  State<AdoptanteFeedScreen> createState() => _AdoptanteFeedScreenState();
}

class _AdoptanteFeedScreenState extends State<AdoptanteFeedScreen> {
  int _idx = 0;
  Position? _userPosition;
  Map<String, dynamic>? _perfilAdopcion;

  @override
  void initState() {
    super.initState();
    _obtenerPosicion();
    _cargarPerfil();
  }

  Future<void> _cargarPerfil() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
    if (doc.exists && mounted) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['perfilAdopcion'] != null) {
        setState(() => _perfilAdopcion = Map<String, dynamic>.from(data['perfilAdopcion']));
      }
    }
  }

  int _calcularScore(Map<String, dynamic> animal) {
    if (_perfilAdopcion == null) return -1;
    return calcularCompatibilidadFeed({
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
      if (mounted) setState(() => _userPosition = pos);
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
    final uid    = FirebaseAuth.instance.currentUser?.uid ?? '';
    final nombre = (animal['nombre'] as String).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
    final docId  = '${uid}_$nombre';
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
      'genero':       animal['genero'] ?? '',
      'fotoBase64':   animal['fotoBase64'],
      'verificado':   animal['verificado'] ?? false,
      'creadoEn':     FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('rescates')
          .orderBy('creadoEn', descending: true)
          .snapshots(),
      builder: (context, snap) {
        final firestoreDocs = (snap.data?.docs ?? []).where((doc) {
          final estado = (doc.data() as Map<String, dynamic>)['estadoAdopcion'] as String?;
          return estado == null || estado == 'Rescatado' || estado == 'Regresado';
        }).toList();
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
              'ubicacion':           d['ubicacion']  ?? 'Medellín',
              'distancia':           '~',
              'descripcion':         d['descripcion'] ?? '',
              'tags':                <String>[
                                      if (d['okConNinos']    == true)  'Con niños',
                                      if (d['okConMascotas'] == true)  'Con mascotas',
                                      if ((d['energia'] as String?)?.isNotEmpty == true) d['energia'] as String,
                                      if (d['estado'] != null && d['estado'] != 'Sano') d['estado'] as String,
                                    ],
              'rescatista':          d['rescatistaNombre'] ?? 'Rescatista',
              'rescatistaId':        d['rescatistaId'] ?? '',
              'fotoBase64':          d['fotoBase64'],
              'latitud':             d['latitud'],
              'longitud':            d['longitud'],
              'energia':             d['energia'],
              'okConNinos':          d['okConNinos'],
              'okConMascotas':       d['okConMascotas'],
              'requiereExperiencia': d['requiereExperiencia'],
            };
          }),
        ];

        if (_idx >= animals.length) return _emptyState();

        final animal = animals[_idx];

        final distancia = _distancia(animal);
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: SizedBox(
              width: double.infinity,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    distancia.isNotEmpty
                        ? '${(animal['ubicacion'] as String).toUpperCase()} · ${distancia.toUpperCase()}'
                        : (animal['ubicacion'] as String).toUpperCase(),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                        letterSpacing: 1.2, color: appTeal)),
                const Text('Cerca de ti',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A))),
              ]),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Align(
                alignment: Alignment.topCenter,
                child: _buildCard(animal, distancia, _calcularScore(animal)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _actionBtn(Icons.close, Colors.grey.shade200, Colors.grey.shade600, 52,
                  () => setState(() => _idx++)),
              const SizedBox(width: 18),
              _actionBtn(Icons.pets, Colors.white, const Color(0xFF1A1A1A), 46, () {
                Navigator.push(context, MaterialPageRoute(
                    builder: (_) => AnimalDetalleScreen(animal: animal)));
              }),
              const SizedBox(width: 18),
              _actionBtn(Icons.favorite, appOrange, Colors.white, 62, () async {
                await _guardarFavorito(animal);
                setState(() => _idx++);
              }),
            ]),
          ),
        ]);
      },
    );
  }

  Widget _emptyState() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: SizedBox(
          width: double.infinity,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('MEDELLÍN', style: TextStyle(fontSize: 11,
                fontWeight: FontWeight.w600, letterSpacing: 1.2, color: appTeal)),
            const Text('Cerca de ti',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
          ]),
        ),
      ),
      Expanded(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 90, height: 90,
            decoration: BoxDecoration(
              color: appOrange.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.pets, size: 44, color: appOrange),
          ),
          const SizedBox(height: 24),
          const Text('Eso es todo por hoy',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
          const SizedBox(height: 10),
          Text('Vuelve mañana — nuevos amigos\nllegan cada día.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.5)),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: () => setState(() => _idx = 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
              decoration: BoxDecoration(color: appOrange, borderRadius: BorderRadius.circular(30)),
              child: const Text('Ver de nuevo',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _buildCard(Map<String, dynamic> a, String distancia, int score) {
    final fotoBase64  = a['fotoBase64'] as String?;
    final nombre      = a['nombre']     as String;
    final edad        = a['edad']       as String;
    final raza        = a['raza']       as String;
    final tamano      = a['tamano']     as String;
    final descripcion = a['descripcion'] as String;
    final tags        = (a['tags'] as List).cast<String>();
    final rescatista  = a['rescatista'] as String;
    final ubicacion   = a['ubicacion']  as String;
    final verificado  = a['verificado'] as bool? ?? false;
    final emoji       = a['especie'] == 'Gato' ? '🐱' : '🐶';

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
          SizedBox(
            height: 245,
            child: Stack(fit: StackFit.expand, children: [
              fotoBase64 != null
                ? Image.memory(base64Decode(fotoBase64), fit: BoxFit.cover)
                : Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [Color(0xFF3D7A52), Color(0xFF1F4A30)],
                      ),
                    ),
                    child: Center(child: Text(emoji, style: const TextStyle(fontSize: 90))),
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
              Positioned(top: 12, left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.location_on, size: 12, color: appTeal),
                    const SizedBox(width: 3),
                    Text(distancia.isNotEmpty ? '$ubicacion · $distancia' : ubicacion,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  ]),
                )),
              Positioned(top: 12, right: 12,
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  if (score >= 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                          color: scoreColor(score), borderRadius: BorderRadius.circular(20)),
                      child: Text('$score% compatible',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  if (verificado) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: appTeal, borderRadius: BorderRadius.circular(20)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.verified, size: 12, color: Colors.white),
                        SizedBox(width: 3),
                        Text('Verificado',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                      ]),
                    ),
                  ],
                ])),
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
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (descripcion.isNotEmpty) ...[
                Text('"$descripcion"',
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
              Row(children: [
                _avatar('A', appOrange, radius: 16, fontSize: 13),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('A cargo de',
                      style: TextStyle(fontSize: 10, color: Color(0xFFAAAAAA))),
                  Text(rescatista,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: appTeal)),
                ]),
                const Spacer(),
                const Text('★★★★★', style: TextStyle(fontSize: 14, color: Color(0xFFFFB800))),
              ]),
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
