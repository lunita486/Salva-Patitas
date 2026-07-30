import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import '../theme.dart';

// Extraído de adoptante_feed_screen.dart (que llegó a 1642 líneas mezclando
// varias responsabilidades) — este grupo (tarjeta + render + share) es
// autocontenido y lo usan otras pantallas (mis_rescates_screen.dart), así
// que vivir en su propio archivo es más claro que dentro de la del feed.

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

  // Acento decorativo simple (huella o corazón), sin depender de assets
  // ilustrados nuevos — un ícono ya existente en la app, rotado y con poca
  // opacidad, para dar un aire más "volante de adopción" sin salir de la
  // paleta ni sumar peso a la build.
  static Widget _sticker(IconData icon, {required double size, required double angle,
      required double opacity, required Color color}) =>
      Transform.rotate(angle: angle, child: Icon(icon, size: size, color: color.withValues(alpha: opacity)));

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
        // Huellitas y corazones sueltos arriba de la foto, como en los
        // volantes de adopción hechos a mano — discretos (opacidad baja)
        // para no competir con el nombre del animal.
        Positioned(top: 170, right: 64, child: _sticker(Icons.favorite,
            size: 40, angle: -0.35, opacity: 0.55, color: appOrange)),
        Positioned(top: 260, right: 150, child: _sticker(Icons.pets,
            size: 30, angle: 0.4, opacity: 0.45, color: Colors.white)),
        Positioned(
          top: 48, left: 48,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            decoration: BoxDecoration(color: appTeal, borderRadius: BorderRadius.circular(32)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Text('🐾', style: TextStyle(fontSize: 26)),
              SizedBox(width: 10),
              Text('Salva Patitas', style: TextStyle(
                  color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700, fontFamily: 'Baloo2')),
            ]),
          ),
        ),
        // Arriba a la derecha, en espejo con "Salva Patitas" — antes iba
        // pegada al nombre abajo y tapaba buena parte de la foto en
        // animales con la cara centrada o abajo del encuadre (el caso real
        // que reportó Eliza: "Canela" quedaba casi tapada). Acá arriba
        // siempre hay más aire en una foto de mascota, y deja el bloque de
        // abajo más corto (solo nombre + especie/edad + ubicación).
        Positioned(
          top: 48, right: 48,
          child: Transform.rotate(
            angle: 0.045,
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: appOrange, borderRadius: BorderRadius.circular(32),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: const Text('¡Necesito un hogar! 💚', style: TextStyle(
                  color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700, fontFamily: 'Baloo2')),
            ),
          ),
        ),
        Positioned(
          left: 48, right: 48, bottom: 56,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nombre, style: const TextStyle(
                color: Colors.white, fontSize: 72, fontWeight: FontWeight.w800, height: 1.0, fontFamily: 'Baloo2')),
            const SizedBox(height: 10),
            Text(
              [if (especie.isNotEmpty) especie, if (edad.isNotEmpty) edad].join(' · '),
              style: const TextStyle(color: Colors.white70, fontSize: 28, fontWeight: FontWeight.w700, fontFamily: 'Baloo2'),
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
      '\n¡Ayúdalo a encontrar familia descargando *Salva Patitas* 💚\n'
      'https://play.google.com/store/apps/details?id=com.salvapatitas.app';

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
    // fotoBytes no es null acá (por el if de más arriba) y ya se descargó
    // bien de Storage — este fallback solo entra si falló la CAPTURA de la
    // tarjeta (cardBytes null), no por un problema con la foto en sí, así
    // que compartir la foto cruda es un fallback seguro.
    final xfile = cardBytes != null
        ? XFile.fromData(cardBytes, mimeType: 'image/png', name: '$nombre.png')
        : XFile.fromData(fotoBytes, mimeType: 'image/jpeg', name: '$nombre.jpg');
    await Share.shareXFiles([xfile], text: texto);
  } else {
    await Share.share(texto);
  }
}
