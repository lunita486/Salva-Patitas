import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:salva_patitas/widgets/elegir_foto_perfil.dart';

// Mismo patrón que elegir_foto_animal_test.dart (fake del picker) combinado
// con foto_normalizador_test.dart (imagen real en un archivo temporal,
// porque normalizarFoto() decodifica de verdad — no hay forma de probar
// esto con un path falso).
class _FakeImagePicker extends ImagePickerPlatform {
  _FakeImagePicker({this.devuelve});
  XFile? devuelve;
  ImageSource? fuenteUsada;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    fuenteUsada = source;
    return devuelve;
  }
}

Future<File> _crearImagenTemp(
  String nombre, {
  required int width,
  required int height,
}) async {
  final imagen = img.Image(width: width, height: height);
  img.fill(imagen, color: img.ColorRgb8(200, 160, 90));
  final archivo = File('${Directory.systemTemp.path}/$nombre');
  await archivo.writeAsBytes(img.encodeJpg(imagen, quality: 100));
  return archivo;
}

void main() {
  group('elegirFotoPerfil() — el selector de galería para foto de perfil/'
      'logo (albergue, aliado). Estaba escrito 3 veces y ya habían '
      'divergido: 2 de las 3 copias se saltaban normalizarFoto(), así que '
      'una foto tomada con el celular "al revés" se guardaba rotada '
      '(nada corregía el EXIF), y una de las 3 no tenía try/catch', () {
    late _FakeImagePicker picker;

    setUp(() {
      picker = _FakeImagePicker();
      ImagePickerPlatform.instance = picker;
    });

    test('cancelar la elección devuelve null, sin tocar la red ni el '
        'estado', () async {
      picker.devuelve = null;

      final r = await elegirFotoPerfil();

      expect(r, isNull);
      expect(picker.fuenteUsada, ImageSource.gallery);
    });

    test(
      'elige de la galería, SIEMPRE por normalizarFoto() — así una foto '
      'con la orientación EXIF "al revés" queda corregida antes de '
      'guardarse, algo que 2 de las 3 copias originales se saltaban',
      () async {
        final archivo = await _crearImagenTemp(
          'perfil.jpg',
          width: 2000,
          height: 1500,
        );
        try {
          picker.devuelve = XFile(archivo.path);

          final r = await elegirFotoPerfil();

          expect(r, isNotNull);
          final decodificada = img.decodeImage(base64Decode(r!));
          expect(decodificada, isNotNull);
          // maxWidth default (512) — el que usan las pantallas que guardan
          // la foto en base64 dentro del doc de Firestore, no en Storage.
          expect(decodificada!.width, 512);
        } finally {
          await archivo.delete();
        }
      },
    );

    test('maxWidth propio se respeta — no todas las pantallas necesitan el '
        'mismo tamaño', () async {
      final archivo = await _crearImagenTemp(
        'logo.jpg',
        width: 2000,
        height: 1000,
      );
      try {
        picker.devuelve = XFile(archivo.path);

        final r = await elegirFotoPerfil(maxWidth: 256);

        final decodificada = img.decodeImage(base64Decode(r!));
        expect(decodificada!.width, 256);
      } finally {
        await archivo.delete();
      }
    });

    test(
      'si normalizarFoto() falla (archivo corrupto/inexistente), '
      'devuelve null en vez de propagar la excepción — best-effort, '
      'mismo criterio que el resto de los selectores de foto de la app',
      () async {
        // Un XFile a un path que no existe hace que normalizarFoto() falle al
        // leer los bytes — simula la única copia (albergue_perfil_screen.dart)
        // que no tenía NINGÚN manejo de error para este caso.
        picker.devuelve = XFile(
          '${Directory.systemTemp.path}/no-existe-de-verdad.jpg',
        );

        final r = await elegirFotoPerfil();

        expect(r, isNull);
      },
    );
  });
}
