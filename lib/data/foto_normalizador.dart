import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Redimensiona (máx 1000px de ancho) y recomprime (JPEG q80) los bytes de
/// una foto antes de subirla — mantiene el peso bajo para el feed/detalle.
///
/// Corre en un isolate aparte vía [compute] a propósito: decodificar/
/// redimensionar/codificar una imagen es trabajo de CPU sincrónico y
/// pesado. Hecho en el isolate principal (como estaba antes, duplicado en
/// subir_rescate_screen.dart y subir_lote_screen.dart), bloqueaba la UI
/// mientras corría, y — más importante en el lote — dos animales
/// "publicándose en paralelo" con Future.wait en realidad procesaban sus
/// fotos una atrás de la otra igual, porque el isolate principal es de un
/// solo hilo: el paralelismo de esa parte era ilusorio, solo la red
/// (Firestore/Storage) corría de verdad al mismo tiempo. Con compute(),
/// cada llamada corre en su propio isolate y el procesamiento de fotos de
/// distintos animales sí se superpone.
Uint8List _procesarBytes(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final rotated = img.bakeOrientation(decoded);
  final resized = rotated.width > 1000
      ? img.copyResize(rotated, width: 1000)
      : rotated;
  return img.encodeJpg(resized, quality: 80);
}

Future<Uint8List> normalizarFoto(String path) async {
  final bytes = await File(path).readAsBytes();
  return compute(_procesarBytes, bytes);
}
