import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Redimensiona (máx 1000px de ancho) y recomprime (JPEG q80) los bytes de
/// una foto antes de subirla — mantiene el peso bajo para el feed/detalle.
///
/// Corre en un isolate aparte a propósito: decodificar/redimensionar/
/// codificar una imagen es trabajo de CPU sincrónico y pesado. Hecho en el
/// isolate principal (como estaba antes, duplicado en subir_rescate_screen.
/// dart y subir_lote_screen.dart), bloqueaba la UI mientras corría, y — más
/// importante en el lote — dos animales "publicándose en paralelo" con
/// Future.wait en realidad procesaban sus fotos una atrás de la otra igual,
/// porque el isolate principal es de un solo hilo: el paralelismo de esa
/// parte era ilusorio, solo la red (Firestore/Storage) corría de verdad al
/// mismo tiempo. Con un isolate propio por llamada, el procesamiento de
/// fotos de distintos animales sí se superpone.
Uint8List _procesarBytes(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final rotated = img.bakeOrientation(decoded);
  final resized = rotated.width > 1000
      ? img.copyResize(rotated, width: 1000)
      : rotated;
  return img.encodeJpg(resized, quality: 80);
}

/// Mensaje que llega por [_Trabajo.respuesta] cuando [_procesarBytes] lanzó
/// dentro del isolate (ej. una imagen corrupta que decodeImage no puede
/// leer) — un Object cualquiera no cruza isolates de forma confiable, así
/// que el error se manda como texto envuelto en este tipo, no como la
/// excepción original.
class _ErrorEnIsolate {
  _ErrorEnIsolate(this.mensaje);
  final String mensaje;
}

class _Trabajo {
  _Trabajo(this.bytes, this.respuesta);
  final Uint8List bytes;
  final SendPort respuesta;
}

void _puntoDeEntrada(_Trabajo trabajo) {
  try {
    trabajo.respuesta.send(_procesarBytes(trabajo.bytes));
  } catch (e) {
    trabajo.respuesta.send(_ErrorEnIsolate(e.toString()));
  }
}

/// Se usa `Isolate.spawn` a mano en vez de `compute()` por una sola razón:
/// `compute()` no da ninguna forma de cancelar el trabajo una vez lanzado.
/// [timeout] importa de verdad, no es un detalle — es el único paso de
/// todo el flujo de publicar que no tenía límite de tiempo: crear el doc,
/// subir cada foto y guardar la URL final ya lo tenían. Una foto corrupta
/// (`img.decodeImage` colgado) o una foto enorme en un celular con poca
/// RAM (redimensionar/recomprimir puede tardar mucho, o directamente
/// trabar el isolate) dejaba el botón de publicar esperando para siempre,
/// sin ninguna salida — ni siquiera cerrando y reabriendo la pantalla, si
/// el `await` nunca vuelve.
///
/// Al vencerse [timeout] se llama a `isolate.kill()` — no alcanza con
/// dejar de esperar el resultado (`Future.timeout()` a secas, como se hacía
/// para las subidas antes de que se corrigiera el mismo problema ahí):
/// el trabajo de CPU seguiría corriendo de fondo, compitiendo por la
/// misma RAM escasa que causó el cuelgue en primer lugar, quizás nunca
/// terminando en ese celular. `kill()` para el isolate de verdad, ahí
/// mismo.
Future<Uint8List> normalizarFoto(
  String path, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final bytes = await File(path).readAsBytes();

  final puerto = ReceivePort();
  Isolate? isolate;
  try {
    isolate = await Isolate.spawn(_puntoDeEntrada, _Trabajo(bytes, puerto.sendPort));

    final resultado = await puerto.first.timeout(timeout, onTimeout: () {
      isolate?.kill(priority: Isolate.immediate);
      throw TimeoutException('Se agotó el tiempo procesando la foto.');
    });

    if (resultado is _ErrorEnIsolate) {
      throw Exception('No se pudo procesar la foto: ${resultado.mensaje}');
    }
    return resultado as Uint8List;
  } finally {
    // Cubre también el camino feliz: el isolate no se mata solo apenas
    // manda la respuesta (queda vivo hasta que alguien lo cierre), así
    // que sin esto cada foto normalizada dejaba un isolate colgado. Matar
    // uno que ya terminó (o uno que ya se mató en el onTimeout de arriba)
    // no hace nada — es seguro llamarlo de más.
    isolate?.kill(priority: Isolate.immediate);
    puerto.close();
  }
}
