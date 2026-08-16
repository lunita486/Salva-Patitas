import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';

import '../theme.dart';

/// Decodifica un string base64 de forma segura — devuelve `null` en vez de
/// tirar una excepción si el string está corrupto o incompleto (ej. una
/// subida de foto que se cortó a la mitad). Usar antes de armar un
/// `MemoryImage`/`DecorationImage` a mano, para poder caer al fallback
/// (inicial/emoji) en vez de crashear.
Uint8List? bytesFotoSegura(String? base64) {
  if (base64 == null || base64.isEmpty) return null;
  try {
    return base64Decode(base64);
  } catch (_) {
    return null;
  }
}

/// Muestra una foto guardada en base64 de forma segura: si el string está
/// corrupto, o los bytes no son una imagen válida, muestra [fallback] en vez
/// de crashear la pantalla que la contiene. Antes cada pantalla decodificaba
/// `base64Decode(...)` a mano sin ninguna protección — un solo dato corrupto
/// (una subida interrumpida, por ejemplo) tumbaba toda la pantalla.
class FotoSegura extends StatelessWidget {
  final String base64;
  final Widget fallback;
  final double? width;
  final double? height;
  final BoxFit fit;
  const FotoSegura({
    super.key,
    required this.base64,
    required this.fallback,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final bytes = bytesFotoSegura(base64);
    if (bytes == null) return fallback;
    return Image.memory(
      bytes,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

/// Muestra una foto alojada en Firebase Storage (`url`) de forma segura:
/// mientras carga, un indicador liviano; si la red falla o la URL ya no es
/// válida, [fallback] en vez de crashear. Mismo contrato que [FotoSegura]
/// (base64) para minimizar el diff en cada pantalla — se usa para fotos de
/// animales (`rescates`), que viven en Storage y no embebidas en Firestore.
class FotoUrl extends StatelessWidget {
  final String url;
  final Widget fallback;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  const FotoUrl({
    super.key,
    required this.url,
    required this.fallback,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      errorBuilder: (_, _, _) => fallback,
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return SizedBox(
          width: width,
          height: height,
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: appTeal),
            ),
          ),
        );
      },
    );
  }
}

/// Foto de animal a prueba de CUALQUIER encuadre: muestra la foto COMPLETA
/// (BoxFit.contain, nunca recorta) y rellena las franjas sobrantes con la
/// misma foto ampliada y desenfocada de fondo — la técnica estándar de las
/// apps de fotos para encajar cualquier proporción en cualquier recuadro.
///
/// Existe porque ningún recorte fijo funciona para todas las fotos: el
/// ancla arriba (Alignment.topCenter) salva a la mayoría (la cara suele
/// estar cerca del borde superior) pero rompe fotos con el animal abajo —
/// el bug real de "Tobyiii": un retrato vertical con el gato al fondo del
/// mueble se veía como un mueble vacío en el feed, el detalle y favoritos.
/// Con esta técnica el animal se ve entero SIEMPRE, sin elegir recorte,
/// sin datos nuevos por foto y sin migrar las fotos existentes. Cuando la
/// proporción de la foto ya calza con la del recuadro, el fondo borroso
/// queda tapado por completo — se ve igual que antes.
///
/// Para miniaturas chicas (avatares de 64px en listas) conviene seguir
/// usando [FotoUrl] con recorte: a ese tamaño el desenfoque se vuelve
/// ruido y el recorte no molesta.
class FotoAnimal extends StatelessWidget {
  final String url;
  final Widget fallback;
  final double? width;
  final double? height;
  const FotoAnimal({
    super.key,
    required this.url,
    required this.fallback,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      // ClipRect: el fondo cover se desborda del recuadro a propósito
      // (para que el blur no muestre bordes transparentes) — sin el clip,
      // pintaría encima de lo que rodee al widget.
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Fondo: misma foto, estirada a cubrir y desenfocada. Una sola
            // descarga real: Image.network con la misma URL comparte el
            // caché de imágenes de Flutter entre las dos capas.
            ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: 14,
                sigmaY: 14,
                tileMode: TileMode.clamp,
              ),
              child: FotoUrl(url: url, fit: BoxFit.cover, fallback: fallback),
            ),
            // Velo suave para que el fondo no compita con la foto nítida.
            Container(color: Colors.black.withValues(alpha: 0.12)),
            // La foto de verdad, entera. Sin fallback propio: si la carga
            // falla, ya lo muestra la capa de fondo — dos fallbacks apilados
            // se verían duplicados.
            FotoUrl(
              url: url,
              fit: BoxFit.contain,
              fallback: const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
