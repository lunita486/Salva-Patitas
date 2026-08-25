import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../theme.dart';

// Caché con límite (LRU simple) del último resultado de bytesFotoSegura()
// por string — ver el porqué en el doc de la función. `_maxCacheado`
// acotado a propósito: esto vive para toda la vida de la app, no por
// pantalla, así que sin un tope crecería sin límite si la persona navega
// por muchos perfiles/animales distintos con foto.
const _maxCacheado = 30;
final _cacheBytesFotoSegura = <String, Uint8List?>{};

/// Decodifica un string base64 de forma segura — devuelve `null` en vez de
/// tirar una excepción si el string está corrupto o incompleto (ej. una
/// subida de foto que se cortó a la mitad). Usar antes de armar un
/// `MemoryImage`/`DecorationImage` a mano, para poder caer al fallback
/// (inicial/emoji) en vez de crashear.
///
/// Cachea el resultado por string de entrada — sin esto, cada foto se
/// decodificaba de nuevo en CADA build (ej. cada tecla escrita en un campo
/// de texto vecino, que dispara `setState()` y redibuja toda la pantalla).
/// `base64Decode` arma un `Uint8List` NUEVO cada vez, y `MemoryImage`
/// compara por identidad de esa lista, no por contenido — así que aunque
/// la foto fuera exactamente la misma, Flutter la trataba como una imagen
/// DISTINTA en cada tecleo, la volvía a decodificar y a pintar desde cero,
/// visible como un parpadeo. Con el mismo `Uint8List` reusado entre
/// builds, `MemoryImage` los ve iguales y no vuelve a hacer nada. Hallazgo
/// real de Eliza: "cada vez que escribo el nombre del aliado, la foto se
/// pone a titilar".
Uint8List? bytesFotoSegura(String? base64) {
  if (base64 == null || base64.isEmpty) return null;
  if (_cacheBytesFotoSegura.containsKey(base64)) {
    // Se saca y se vuelve a poner para que quede como el más reciente
    // (orden de inserción = orden de "usado hace menos"), así el tope de
    // abajo descarta primero lo que hace más tiempo que no se pide.
    final bytes = _cacheBytesFotoSegura.remove(base64);
    _cacheBytesFotoSegura[base64] = bytes;
    return bytes;
  }
  Uint8List? bytes;
  try {
    bytes = base64Decode(base64);
  } catch (_) {
    bytes = null;
  }
  _cacheBytesFotoSegura[base64] = bytes;
  if (_cacheBytesFotoSegura.length > _maxCacheado) {
    _cacheBytesFotoSegura.remove(_cacheBytesFotoSegura.keys.first);
  }
  return bytes;
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
///
/// `CachedNetworkImage` en vez de `Image.network`: este último solo cachea
/// en el `ImageCache` en RAM de Flutter, que vive mientras la app está
/// abierta — cada apertura nueva de la app volvía a descargar TODAS las
/// fotos desde Storage, aunque fueran las mismas de siempre. Con esto,
/// una foto ya vista se lee del disco del teléfono, no de la red. Hallazgo
/// real de Eliza: Adoptar tardando demasiado en cargar fotos, en sus 2
/// teléfonos.
///
/// `LayoutBuilder` + `memCacheWidth` (en vez de decodificar siempre a la
/// resolución completa de la foto subida): sin esto, un avatar de 64px de
/// ancho igual decodificaba y guardaba en RAM el bitmap entero de la foto
/// (hasta 1000px de foto_normalizador.dart) — trabajo de CPU y memoria de
/// más en cada foto, en cada pantalla que usa este widget.
///
/// SOLO `memCacheWidth`, nunca `memCacheHeight` a la vez — mandarle los DOS
/// a `CachedNetworkImage` decodifica la foto a esas dos medidas EXACTAS
/// (`ResizeImage` con su política por defecto, `exact`, no `fit`), estirando
/// cualquier foto cuya proporción no calce con la del recuadro ANTES de que
/// `fit`/`BoxFit` llegue a hacer nada — el estiramiento queda en el bitmap
/// ya decodificado, no algo que `BoxFit.cover` pueda corregir después.
/// Pasando solo el ancho, `ResizeImage` calcula el alto solo (mantiene la
/// proporción real de la foto) — un poco menos preciso en memoria para
/// recuadros muy angostos y altos, pero nunca deforma la imagen. Hallazgo
/// real de Eliza, el mismo día que se agregó memCacheWidth/Height: fotos
/// de "Mis rescates" (Luna, bobby) se veían estiradas horizontalmente.
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
    return LayoutBuilder(
      builder: (context, constraints) {
        // El tamaño real en pantalla puede venir de `width`/`height` (si se
        // pasaron) o de las constraints que le da el padre (ej. FotoAnimal,
        // que no fija tamaño propio) — se toma lo que esté disponible,
        // multiplicado por devicePixelRatio para no verse borrosa en
        // pantallas de alta densidad. `null` cuando ninguna de las dos está
        // acotada (raro): se decodifica a resolución completa, mismo
        // comportamiento que antes.
        final dpr = MediaQuery.of(context).devicePixelRatio;
        final anchoDisponible = width ?? constraints.maxWidth;
        final cacheWidth = anchoDisponible.isFinite
            ? (anchoDisponible * dpr).round()
            : null;
        return CachedNetworkImage(
          imageUrl: url,
          width: width,
          height: height,
          fit: fit,
          alignment: alignment,
          memCacheWidth: cacheWidth,
          fadeInDuration: const Duration(milliseconds: 150),
          errorWidget: (_, _, _) => fallback,
          placeholder: (_, _) => SizedBox(
            width: width,
            height: height,
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: appTeal),
              ),
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
/// Para miniaturas chicas (64px en una lista) va [fondoBorroso] en `false`:
/// a ese tamaño el desenfoque no se distingue, así que se paga su costo
/// para algo que nadie llega a ver. Ver el comentario de ese parámetro.
class FotoAnimal extends StatelessWidget {
  final String url;
  final Widget fallback;
  final double? width;
  final double? height;

  /// `true` (por defecto): las franjas sobrantes se rellenan con la misma
  /// foto ampliada y desenfocada. `false`: se rellenan con un color plano.
  ///
  /// **Existe por costo de dibujado, no por gusto.** `ImageFiltered` obliga
  /// a Flutter a abrir una capa aparte (`saveLayer`) por cada foto para
  /// aplicarle el desenfoque, y eso en una LISTA que se desplaza se paga en
  /// cada cuadro y por cada fila visible. En una tarjeta grande vale la
  /// pena; en una miniatura de 64px el resultado del desenfoque ocupa unos
  /// pocos píxeles al costado de la foto y directamente no se distingue de
  /// un color plano.
  ///
  /// El comentario de esta clase ya decía que a 64px no convenía usar este
  /// widget, y aun así 3 pantallas de listas (Mis rescates, Mis solicitudes
  /// y Solicitudes del rescatista) lo usaban a ese tamaño — habían llegado
  /// acá para arreglar OTRO bug real (el recorte fijo cortaba animales que
  /// no quedan cerca del borde de la foto: "Chanchis", "Tobyiii"), y ese
  /// motivo sigue siendo válido. Por eso el arreglo no es volver al
  /// recorte: es conservar la foto entera (BoxFit.contain, que es lo que
  /// resolvía ese bug) y cambiar SOLO el relleno del fondo.
  ///
  /// Ojo con lo que esto NO arregla: el desenfoque afecta la fluidez del
  /// scroll, no cuánto tarda en bajar la foto. Sacarlo no acelera la
  /// descarga.
  final bool fondoBorroso;

  const FotoAnimal({
    super.key,
    required this.url,
    required this.fallback,
    this.width,
    this.height,
    this.fondoBorroso = true,
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
            if (fondoBorroso) ...[
              // Fondo: misma foto, estirada a cubrir y desenfocada. Una sola
              // descarga real: comparten URL, así que las dos capas usan la
              // misma imagen del caché.
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
            ] else
              // Color plano en vez de la foto desenfocada: una capa menos,
              // sin saveLayer y sin una segunda imagen que dibujar. Sin
              // `child` a propósito — este Container no decodifica ninguna
              // imagen, así que no hay "si falla" que cubrir. Bug real que
              // esto arregla: con `child: fallback` acá, el emoji de
              // repuesto quedaba pintado SIEMPRE (visible en las franjas
              // que BoxFit.contain deja libres), no solo cuando la foto de
              // verdad fallaba — se veía la foto Y el emoji al mismo
              // tiempo. Hallazgo real de Eliza en "Mis rescates".
              Container(color: const Color(0xFFE8F2EC)),
            // La foto de verdad, entera. Con fondo borroso, sin fallback
            // propio (dos fallbacks apilados se verían duplicados — ya lo
            // cubre la capa de fondo, que si el fondo desenfocado falla
            // muestra el suyo). Sin fondo borroso, la capa de arriba es
            // solo un color sin fallback propio: ACÁ es donde tiene que
            // aparecer el emoji si la foto de verdad no carga.
            FotoUrl(
              url: url,
              fit: BoxFit.contain,
              fallback: fondoBorroso ? const SizedBox.shrink() : fallback,
            ),
          ],
        ),
      ),
    );
  }
}
