import 'dart:async';
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

    test('un timeout corto hace que se rinda pronto en vez de colgarse para '
        'siempre — antes este era el único paso de publicar sin ningún '
        'límite de tiempo: una foto corrupta o enorme en un celular con '
        'poca RAM podía dejar el botón de publicar esperando sin ninguna '
        'salida', () async {
      final archivo = await _crearImagenTemp('lenta.jpg', width: 4000, height: 4000);
      try {
        final arranque = DateTime.now();
        await expectLater(
          normalizarFoto(archivo.path, timeout: const Duration(milliseconds: 1)),
          throwsA(isA<TimeoutException>()),
        );
        // No alcanza con que lance la excepción — tiene que lanzarla PRONTO.
        // Un simple "dejar de esperar" también termina lanzando una
        // excepción tarde o temprano; lo que hace falta es que no haga
        // falta esperar a que la imagen de 4000x4000 termine de procesarse
        // sola de fondo para que el test (y en la app real, el usuario)
        // sigan su camino.
        expect(DateTime.now().difference(arranque), lessThan(const Duration(seconds: 5)));
      } finally {
        await archivo.delete();
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('normaliza varias fotos en paralelo sin que se pisen entre sí '
        '(cada llamada usa su propio isolate y su propio puerto)', () async {
      final archivo1 = await _crearImagenTemp('par1.jpg', width: 2000, height: 1000);
      final archivo2 = await _crearImagenTemp('par2.jpg', width: 1500, height: 2000);
      try {
        final resultados = await Future.wait([
          normalizarFoto(archivo1.path),
          normalizarFoto(archivo2.path),
        ]);

        expect(img.decodeImage(resultados[0])!.width, 1000);
        expect(img.decodeImage(resultados[1])!.width, 1000);
        expect(img.decodeImage(resultados[1])!.height, greaterThan(1000),
            reason: 'la segunda imagen es más alta que ancha (1500x2000) — '
                'si los resultados se mezclaran entre isolates, este chequeo '
                'lo detectaría');
      } finally {
        await archivo1.delete();
        await archivo2.delete();
      }
    });
  });
}
