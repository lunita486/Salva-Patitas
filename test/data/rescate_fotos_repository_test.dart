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

    test('moverFoto() mueve el ARCHIVO de verdad (no solo la URL): los bytes '
        'quedan en el slot destino, el origen se borra, y la URL devuelta '
        'apunta al destino — la promoción "quité la foto 1, la 2 pasa a ser '
        'la 1" copiaba solo la URL entre campos y el mismo guardado borraba '
        'foto2.jpg como slot vacío, dejando la ficha apuntando a un archivo '
        'muerto (bug real: "rarito 2" con emoji en el feed)', () async {
      final storage = fsm.MockFirebaseStorage();
      final repo = RescateFotosRepository(storage: storage);
      final bytes = Uint8List.fromList([7, 8, 9]);
      await repo.subir(rescateId: 'rescate-m', slot: 2, bytes: bytes);

      final url = await repo.moverFoto(rescateId: 'rescate-m', deSlot: 2, aSlot: 1);

      expect(url, contains('rescates/rescate-m/foto1.jpg'));
      expect(await storage.ref('rescates/rescate-m/foto1.jpg').getData(), bytes);
      expect(await storage.ref('rescates/rescate-m/foto2.jpg').getData(), isNull,
          reason: 'el archivo de origen tiene que borrarse — si queda, una '
              'segunda foto agregada después lo pisa y cambia la foto 1 en silencio');
    });

    test('moverFoto() devuelve null sin tocar nada si el origen no existe '
        '(ficha ya dañada por el bug: fotoUrl apuntando a un archivo borrado)', () async {
      final storage = fsm.MockFirebaseStorage();
      final repo = RescateFotosRepository(storage: storage);

      final url = await repo.moverFoto(rescateId: 'rescate-n', deSlot: 2, aSlot: 1);

      expect(url, isNull);
    });

    test('moverFoto() también devuelve null cuando el SDK real tira '
        'object-not-found en la descarga (el mock de arriba devuelve null; '
        'Firebase de verdad lanza excepción — las dos ramas existen)', () async {
      final storage = MockFirebaseStorage();
      final ref = MockReference();
      when(() => storage.ref(any())).thenReturn(ref);
      when(() => ref.getData(any())).thenThrow(
          FirebaseException(plugin: 'firebase_storage', code: 'object-not-found'));

      final repo = RescateFotosRepository(storage: storage);
      expect(await repo.moverFoto(rescateId: 'r1', deSlot: 2, aSlot: 1), isNull);
      verifyNever(() => ref.delete());
    });

    group('urlApuntaASlot() — única regla de "¿este campo apunta a este slot?"', () {
      // URL real de descarga tal como la produce getDownloadURL: el path
      // viene CODIFICADO (%2F en vez de /) — la detección de la promoción
      // foto 2 → foto 1 en editar depende de reconocer esta forma exacta.
      const urlReal =
          'https://firebasestorage.googleapis.com/v0/b/patitas-dd0bb.firebasestorage.app'
          '/o/rescates%2FmDECMMPyH3kyBzjOaq3C%2Ffoto2.jpg?alt=media&token=6b8d449b-49ee';

      test('reconoce el slot en una URL real con el path codificado (%2F)', () {
        expect(RescateFotosRepository.urlApuntaASlot(urlReal, 2), true);
        expect(RescateFotosRepository.urlApuntaASlot(urlReal, 1), false,
            reason: 'foto2.jpg no debe confundirse con el slot 1');
      });

      test('también reconoce la forma ya decodificada (con / literales)', () {
        final decodificada = Uri.decodeFull(urlReal);
        expect(RescateFotosRepository.urlApuntaASlot(decodificada, 2), true);
        expect(RescateFotosRepository.urlApuntaASlot(decodificada, 1), false);
      });

      test('null y URLs malformadas devuelven false sin lanzar — una '
          'detección que crashea rompe el guardado entero, peor que no '
          'detectar', () {
        expect(RescateFotosRepository.urlApuntaASlot(null, 2), false);
        expect(RescateFotosRepository.urlApuntaASlot('%zz-malformada', 2), false);
        expect(RescateFotosRepository.urlApuntaASlot('', 2), false);
      });
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
