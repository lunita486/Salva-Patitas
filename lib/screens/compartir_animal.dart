import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import '../theme/salva_patitas_theme.dart';
import '../widgets/sp_widgets.dart';
import '../widgets/campo_pais_telefono.dart' show banderaPais;

// Extraído de adoptante_feed_screen.dart (que llegó a 1642 líneas mezclando
// varias responsabilidades) — este grupo (tarjeta + render + share) es
// autocontenido y lo usan otras pantallas (mis_rescates_screen.dart), así
// que vivir en su propio archivo es más claro que dentro de la del feed.

// Mismo límite que RescateFotosRepository._maxBytesFoto — sin esto getData()
// usa el default del plugin (10MB) en vez de un tamaño elegido a propósito
// para lo que puede llegar a pesar una foto de animal.
const _maxBytesFoto = 15 * 1024 * 1024;

// Cuánto se espera la foto antes de compartir solo el texto.
//
// `getData()` no trae timeout propio: con señal mala se quedaba esperando
// para siempre y el botón de compartir parecía muerto — sin spinner, sin
// error, sin hoja de compartir. Nunca aparecía nada. Los dos pasos de
// después (precache + captura de la tarjeta) ya se rendían a los 5s cada
// uno; el único que no tenía límite era justo el que depende de la red.
//
// 15s y no 5: bajar una foto de hasta 15 MB tarda de verdad, y rendirse
// antes de tiempo cambia un botón colgado por una tarjeta que no sale
// nunca. Pasado el plazo se comparte igual, solo que sin imagen.
const _esperaMaximaFoto = Duration(seconds: 15);

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
  static Widget _sticker(
    IconData icon, {
    required double size,
    required double angle,
    required double opacity,
    required Color color,
  }) => Transform.rotate(
    angle: angle,
    child: Icon(
      icon,
      size: size,
      color: color.withValues(alpha: opacity),
    ),
  );

  // Siempre con los colores claros de la marca, no con los del tema del
  // teléfono: es una imagen que sale de la app y se tiene que ver igual
  // para todo el mundo.
  static const _c = SpColors.light;

  static TextStyle _texto(double size, Color color, [FontWeight? w]) =>
      TextStyle(
        fontFamily: spFontFamily,
        fontSize: size,
        fontWeight: w ?? FontWeight.w800,
        color: color,
      );

  /// Píldora 3D con canto (como las del diseño de la app).
  static Widget _pildora({
    required Widget child,
    required Color fondo,
    required Color canto,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    decoration: BoxDecoration(
      color: fondo,
      borderRadius: BorderRadius.circular(40),
      border: Border(
        top: BorderSide(color: SpDeco.shine.withValues(alpha: .35), width: 3),
      ),
      boxShadow: [
        BoxShadow(color: canto, offset: const Offset(0, 6)),
        BoxShadow(
          color: SpDeco.shade.withValues(alpha: 0.25),
          blurRadius: 16,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: child,
  );

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      // alignment sesgado hacia arriba (no center): con BoxFit.cover
      // centrado, una foto vertical de mascota (la mayoría, tomadas con el
      // celular) recorta justo la cara al forzarla al cuadrado de
      // 1080x1080 — mismo ajuste que se hizo en la vidriera de la landing.
      Image.memory(
        fotoBytes,
        fit: BoxFit.cover,
        alignment: const Alignment(0, -0.5),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              SpDeco.shade.withValues(alpha: 0),
              SpDeco.shade.withValues(alpha: 0.78),
            ],
            stops: const [0.35, 1.0],
          ),
        ),
      ),
      // Huellitas y corazones sueltos arriba de la foto, como en los
      // volantes de adopción hechos a mano — discretos (opacidad baja)
      // para no competir con el nombre del animal.
      Positioned(
        top: 170,
        right: 64,
        child: _sticker(
          Icons.favorite_rounded,
          size: 40,
          angle: -0.35,
          opacity: 0.7,
          color: _c.accent,
        ),
      ),
      Positioned(
        top: 260,
        right: 150,
        child: Transform.rotate(
          angle: 0.4,
          child: SpPaw(size: 34, color: SpDeco.shine.withValues(alpha: .5)),
        ),
      ),
      Positioned(
        top: 48,
        left: 48,
        child: _pildora(
          fondo: _c.primary,
          canto: _c.primaryEdge,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SpPaw(size: 28, color: _c.onPrimary),
              const SizedBox(width: 10),
              Text('Salva Patitas', style: _texto(26, _c.onPrimary)),
            ],
          ),
        ),
      ),
      // Arriba a la derecha, en espejo con "Salva Patitas" — antes iba
      // pegada al nombre abajo y tapaba buena parte de la foto en
      // animales con la cara centrada o abajo del encuadre (el caso real
      // que reportó Eliza: "Canela" quedaba casi tapada). Acá arriba
      // siempre hay más aire en una foto de mascota, y deja el bloque de
      // abajo más corto (solo nombre + especie/edad + ubicación).
      Positioned(
        top: 48,
        right: 48,
        child: Transform.rotate(
          angle: 0.045,
          alignment: Alignment.centerRight,
          child: _pildora(
            fondo: _c.accent,
            canto: _c.accentInk,
            child: Text(
              '¡Necesito un hogar! 💚',
              style: _texto(26, _c.onAccent),
            ),
          ),
        ),
      ),
      Positioned(
        left: 48,
        right: 48,
        bottom: 56,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // maxLines + ellipsis: sin esto, un nombre largo (no hay tope
            // de longitud al cargar un animal) crecía hacia arriba desde
            // este punto fijo y terminaba recortado por fuera de la
            // imagen de 1080x1080, o chocando con las 2 insignias de
            // arriba — nunca "no cabe", pero sí ilegible.
            Text(
              nombre,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _texto(
                76,
                SpDeco.shine,
              ).copyWith(height: 1.0, letterSpacing: -1.5),
            ),
            const SizedBox(height: 12),
            Text(
              [
                if (especie.isNotEmpty) especie,
                if (edad.isNotEmpty) edad,
              ].join(' · '),
              style: _texto(30, _c.mint, FontWeight.w700),
            ),
            if (ubicacion.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.location_on_rounded,
                    color: SpDeco.shine.withValues(alpha: .8),
                    size: 28,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    ubicacion,
                    style: _texto(
                      28,
                      SpDeco.shine.withValues(alpha: .8),
                      FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

Future<Uint8List?> _renderShareCardToPng(
  BuildContext context,
  Widget card, {
  double size = 1080,
}) async {
  final key = GlobalKey();
  final overlay = Overlay.of(context, rootOverlay: true);
  // La tarjeta se arma DENTRO del área visible (no fuera de pantalla): en
  // algunos dispositivos, una imagen posicionada fuera de la vista nunca
  // llega a pintarse (aunque los colores/textos sí), y la captura sale sin
  // foto. Para que el usuario no vea el proceso, se tapa con un scrim +
  // spinner por encima.
  final cardEntry = OverlayEntry(
    builder: (_) => Positioned(
      left: 0,
      top: 0,
      child: Material(
        type: MaterialType.transparency,
        child: RepaintBoundary(
          key: key,
          child: SizedBox(width: size, height: size, child: card),
        ),
      ),
    ),
  );
  final scrimEntry = OverlayEntry(
    builder: (_) => Positioned.fill(
      child: Material(
        color: SpDeco.shade.withValues(alpha: 0.55),
        child: const Center(
          child: CircularProgressIndicator(color: SpDeco.shine),
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
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary
        .toImage(pixelRatio: 1.0)
        .timeout(const Duration(seconds: 5));
    final byteData = await image
        .toByteData(format: ui.ImageByteFormat.png)
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
  String? paisCodigo,
}) async {
  final emoji = especie == 'Gato' ? '🐱' : '🐶';
  final tagsTexto = tags.isNotEmpty ? tags.map((t) => '✅ $t').join('  ') : '';
  // La bandera al lado de la ciudad, mismo motivo que en la tarjeta del
  // feed (ver banderaPais): "Córdoba" sola no dice si es la de Argentina o
  // la de España, y esto se comparte fuera de la app, sin el contexto del
  // resto de la pantalla para desambiguar. Pregunta real de Eliza sobre
  // este mismo texto.
  final bandera = banderaPais(paisCodigo);
  final ubicacionConPais = bandera.isNotEmpty
      ? '$ubicacion $bandera'
      : ubicacion;
  final texto =
      '$emoji *$nombre* necesita un hogar!\n'
      '${[if (especie.isNotEmpty) especie, if (edad.isNotEmpty) edad].join(' · ')}\n'
      '📍 $ubicacionConPais\n'
      '${tagsTexto.isNotEmpty ? '$tagsTexto\n' : ''}'
      '\n¡Ayúdalo a encontrar familia descargando *Salva Patitas* 💚\n'
      'https://play.google.com/store/apps/details?id=com.salvapatitas.app';

  // La foto ya no es un string local (base64) — hay que bajarla de Storage
  // antes de poder compartirla como archivo. Si falla (sin red, URL rota),
  // se comparte solo el texto en vez de romper el flujo de compartir.
  Uint8List? fotoBytes;
  if (fotoUrl != null) {
    try {
      fotoBytes = await FirebaseStorage.instance
          .refFromURL(fotoUrl)
          .getData(_maxBytesFoto)
          .timeout(_esperaMaximaFoto);
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
            _ShareCard(
              nombre: nombre,
              especie: especie,
              edad: edad,
              ubicacion: ubicacion,
              fotoBytes: fotoBytes,
            ),
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
        : XFile.fromData(
            fotoBytes,
            mimeType: 'image/jpeg',
            name: '$nombre.jpg',
          );
    await Share.shareXFiles([xfile], text: texto);
  } else {
    await Share.share(texto);
  }
}
