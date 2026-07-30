import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:patitas_medellin/data/foto_normalizador.dart';

// No usa fake_cloud_firestore (no aplica, este archivo no toca Firestore) —
// normalizarFoto() es una función pura sobre bytes de imagen, así que se
// prueba armando una imagen real en un archivo temporal y verificando la
// salida.
Future<File> _crearImagenTemp(String nombre, {required int width, required int height}) async {
  final imagen = img.Image(width: width, height: height);
  img.fill(imagen, color: img.ColorRgb8(120, 180, 140));
  final archivo = File('${Directory.systemTemp.path}/$nombre');
  await archivo.writeAsBytes(img.encodeJpg(imagen, quality: 100));
  return archivo;
}

void main() {
  group('normalizarFoto', () {
    test('una imagen más ancha que 1000px se redimensiona a 1000 de ancho', () async {
      final archivo = await _crearImagenTemp('grande.jpg', width: 2000, height: 1500);
      try {
        final resultado = await normalizarFoto(archivo.path);
        final decodificada = img.decodeImage(resultado);

        expect(decodificada, isNotNull);
        expect(decodificada!.width, 1000);
        // Alto proporcional al ancho recortado (2000x1500 -> 1000x750).
        expect(decodificada.height, 750);
      } finally {
        await archivo.delete();
      }
    });

    test('una imagen de menos de 1000px de ancho NO se agranda', () async {
      final archivo = await _crearImagenTemp('chica.jpg', width: 500, height: 400);
      try {
        final resultado = await normalizarFoto(archivo.path);
        final decodificada = img.decodeImage(resultado);

        expect(decodificada, isNotNull);
        expect(decodificada!.width, 500);
        expect(decodificada.height, 400);
      } finally {
        await archivo.delete();
      }
    });

    test('recomprime a JPEG calidad 80 — una foto subida a máxima calidad sale más liviana '
        '(el peso bajo es el motivo por el que existe esta función: mantener rescates '
        'y sus fotos livianos para el feed)', () async {
      final archivo = await _crearImagenTemp('pesada.jpg', width: 1200, height: 900);
      try {
        final pesoOriginal = await archivo.length();
        final resultado = await normalizarFoto(archivo.path);

        expect(resultado.length, lessThan(pesoOriginal));
      } finally {
        await archivo.delete();
      }
    });
  });
}
