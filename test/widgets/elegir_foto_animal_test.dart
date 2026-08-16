import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:salva_patitas/widgets/elegir_foto_animal.dart';

// Fake del picker — mismo patrón que los fakes de geolocator/geocoding de
// campo_ciudad_test.dart. `getImageFromSource` es el método al que
// ImagePicker.pickImage() delega, así que reemplazarlo alcanza para
// simular las 3 respuestas reales: la persona eligió una foto, canceló,
// o la cámara falló.
class _FakeImagePicker extends ImagePickerPlatform {
  _FakeImagePicker({this.devuelve, this.lanza});

  /// Qué "archivo" devuelve cuando la elección sale bien.
  XFile? devuelve;

  /// Si no es null, se lanza en vez de devolver — simula una cámara no
  /// disponible / permiso denegado / emulador sin cámara.
  Object? lanza;

  /// Con qué fuente se llamó, para poder afirmar que la hoja mandó la
  /// opción que se tocó (cámara vs galería).
  ImageSource? fuenteUsada;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    fuenteUsada = source;
    if (lanza != null) throw lanza!;
    return devuelve;
  }
}

void main() {
  group('elegirFotoAnimal() — la hoja "Tomar foto / Elegir de la galería" '
      'con su pickImage. Estaba escrita 2 veces (publicar y editar) y las '
      'copias habían divergido: solo la de publicar envolvía la cámara en '
      'un try/catch. En la de editar, un dispositivo sin cámara (o con el '
      'permiso denegado, o un emulador sin cámara) hacía que tocar "Tomar '
      'foto" no hiciera absolutamente nada, sin ningún aviso', () {
    late _FakeImagePicker picker;

    setUp(() {
      picker = _FakeImagePicker();
      ImagePickerPlatform.instance = picker;
    });

    Future<XFile?> abrirYElegir(WidgetTester tester, String opcion) async {
      XFile? resultado;
      var termino = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  resultado = await elegirFotoAnimal(ctx);
                  termino = true;
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(opcion));
      await tester.pumpAndSettle();
      expect(termino, isTrue, reason: 'elegirFotoAnimal no terminó');
      return resultado;
    }

    testWidgets('la cámara falla → devuelve null y AVISA, en vez de quedar '
        'en silencio. Es el bug exacto que tenía la pantalla de editar', (
      tester,
    ) async {
      picker.lanza = Exception('no camera available');

      final r = await abrirYElegir(tester, 'Tomar foto');

      expect(r, isNull);
      expect(picker.fuenteUsada, ImageSource.camera);
      // Lo importante: la excepción NO se escapa (antes reventaba sin que
      // nadie la atrapara) y la persona ve por qué no pasó nada.
      expect(tester.takeException(), isNull);
      expect(find.text('Cámara no disponible, usa la galería'), findsOneWidget);
    });

    testWidgets('elegir de la galería devuelve el archivo', (tester) async {
      picker.devuelve = XFile('/tmp/perrito.jpg');

      final r = await abrirYElegir(tester, 'Elegir de la galería');

      expect(r?.path, '/tmp/perrito.jpg');
      expect(picker.fuenteUsada, ImageSource.gallery);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tomar foto con la cámara andando devuelve el archivo — el '
        'try/catch no se come el caso bueno', (tester) async {
      picker.devuelve = XFile('/tmp/gatito.jpg');

      final r = await abrirYElegir(tester, 'Tomar foto');

      expect(r?.path, '/tmp/gatito.jpg');
      expect(picker.fuenteUsada, ImageSource.camera);
    });

    testWidgets('cancelar la elección (sin elegir archivo) devuelve null sin '
        'avisar nada — cancelar no es un error', (tester) async {
      picker.devuelve = null; // el picker del sistema se cerró sin elegir

      final r = await abrirYElegir(tester, 'Elegir de la galería');

      expect(r, isNull);
      expect(find.text('Cámara no disponible, usa la galería'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
