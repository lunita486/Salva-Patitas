import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart' as fsm;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:patitas_medellin/data/rescate_fotos_repository.dart';

// firebase_storage_mocks simula el camino feliz (subir/borrar un archivo que
// existe) pero su delete() nunca tira object-not-found para un archivo que
// no existe — siempre resuelve en silencio. Para probar esa rama puntual de
// eliminar() hace falta un mock manual con mocktail.
class MockFirebaseStorage extends Mock implements FirebaseStorage {}

class MockReference extends Mock implements Reference {}

void main() {
  group('RescateFotosRepository', () {
    test('subir() sube los bytes y devuelve una URL de descarga con el path correcto '
        '(el path es el contrato que storage.rules usa para verificar dueño — '
        'un cambio silencioso acá rompe la regla en producción)', () async {
      final storage = fsm.MockFirebaseStorage();
      final repo = RescateFotosRepository(storage: storage);
      final bytes = Uint8List.fromList([1, 2, 3]);

      final url = await repo.subir(rescateId: 'rescate-1', slot: 1, bytes: bytes);

      expect(url, contains('rescates/rescate-1/foto1.jpg'));
    });

    test('eliminar() borra un archivo que existe', () async {
      final storage = fsm.MockFirebaseStorage();
      final repo = RescateFotosRepository(storage: storage);
      await repo.subir(rescateId: 'rescate-2', slot: 1, bytes: Uint8List.fromList([9]));

      await expectLater(repo.eliminar(rescateId: 'rescate-2', slot: 1), completes);
    });

    test('eliminar() ignora el error object-not-found (borrar un slot que nunca tuvo foto)', () async {
      final storage = MockFirebaseStorage();
      final ref = MockReference();
      when(() => storage.ref(any())).thenReturn(ref);
      when(() => ref.delete()).thenThrow(
          FirebaseException(plugin: 'firebase_storage', code: 'object-not-found'));

      final repo = RescateFotosRepository(storage: storage);
      await expectLater(repo.eliminar(rescateId: 'r1', slot: 2), completes);
    });

    test('eliminar() propaga cualquier otro error que no sea object-not-found', () async {
      final storage = MockFirebaseStorage();
      final ref = MockReference();
      when(() => storage.ref(any())).thenReturn(ref);
      when(() => ref.delete()).thenThrow(
          FirebaseException(plugin: 'firebase_storage', code: 'unauthorized'));

      final repo = RescateFotosRepository(storage: storage);
      await expectLater(
        repo.eliminar(rescateId: 'r1', slot: 1),
        throwsA(isA<FirebaseException>()),
      );
    });

    test('eliminarTodas() borra los dos slots posibles, ignorando los que no existían', () async {
      final storage = fsm.MockFirebaseStorage();
      final repo = RescateFotosRepository(storage: storage);
      await repo.subir(rescateId: 'rescate-3', slot: 1, bytes: Uint8List.fromList([1]));
      // slot 2 nunca se subió — eliminarTodas no debería fallar por eso.

      await expectLater(repo.eliminarTodas('rescate-3'), completes);
    });

    test('eliminarTodas() devuelve un Future<void> real: un .catchError((_) {}) '
        'del llamador no revienta con "Invalid argument (onError)" aunque el '
        'borrado falle (el bug que escondía el 403 de Storage detrás de una '
        'publicación que fallaba en silencio)', () async {
      final storage = MockFirebaseStorage();
      final ref = MockReference();
      when(() => storage.ref(any())).thenReturn(ref);
      when(() => ref.delete()).thenThrow(
          FirebaseException(plugin: 'firebase_storage', code: 'unauthorized'));

      final repo = RescateFotosRepository(storage: storage);
      // Antes del fix, esto lanzaba ArgumentError (Invalid argument (onError))
      // porque el Future devuelto era en runtime un Future<List<void>> y el
      // handler void no coincidía con ese tipo. Ahora debe completar sin más.
      await expectLater(
        repo.eliminarTodas('r1').catchError((_) {}),
        completes,
      );
    });
  });
}
