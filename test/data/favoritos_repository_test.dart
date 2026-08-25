import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/data/favoritos_repository.dart';

void main() {
  group('FavoritosRepository', () {
    late FakeFirebaseFirestore firestore;
    late FavoritosRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = FavoritosRepository(db: firestore);
    });

    group(
      'idDe — la regla del id tiene que ser IDÉNTICA al guardar y al '
      'borrar, o se borra un documento distinto del que se guardó. Por eso '
      'vive acá y no en la pantalla que guarda.',
      () {
        test('con rescateId usa el id del animal', () {
          expect(
            FavoritosRepository.idDe(
              uid: 'u1',
              rescateId: 'r1',
              animalNombre: 'Toby',
            ),
            'u1_r1',
          );
        });

        // Favoritos guardados antes de que `rescateId` existiera.
        test('sin rescateId cae al nombre, normalizado', () {
          expect(
            FavoritosRepository.idDe(
              uid: 'u1',
              rescateId: '',
              animalNombre: 'Toby',
            ),
            'u1_toby',
          );
        });

        test('el nombre se normaliza: mayúsculas, tildes y espacios no '
            'generan ids distintos para el mismo animal', () {
          expect(
            FavoritosRepository.idDe(
              uid: 'u1',
              rescateId: '',
              animalNombre: 'Toby Papito',
            ),
            'u1_toby_papito',
          );
        });

        test('la misma persona sobre el mismo animal da SIEMPRE el mismo '
            'id — es lo que evita favoritos duplicados', () {
          final a = FavoritosRepository.idDe(
            uid: 'u1',
            rescateId: 'r1',
            animalNombre: 'Toby',
          );
          final b = FavoritosRepository.idDe(
            uid: 'u1',
            rescateId: 'r1',
            animalNombre: 'Toby',
          );
          expect(a, b);
        });

        test('personas distintas sobre el mismo animal NO comparten '
            'documento', () {
          expect(
            FavoritosRepository.idDe(
              uid: 'u1',
              rescateId: 'r1',
              animalNombre: 'Toby',
            ),
            isNot(
              FavoritosRepository.idDe(
                uid: 'u2',
                rescateId: 'r1',
                animalNombre: 'Toby',
              ),
            ),
          );
        });
      },
    );

    test('mios() trae solo los favoritos de esa persona', () async {
      await repo.guardar(
        uid: 'u1',
        rescateId: 'r1',
        animalNombre: 'Toby',
        datos: {'animalNombre': 'Toby'},
      );
      await repo.guardar(
        uid: 'otro',
        rescateId: 'r2',
        animalNombre: 'Luna',
        datos: {'animalNombre': 'Luna'},
      );

      final snap = await repo.mios('u1').first;

      expect(snap.docs.length, 1);
      expect(snap.docs.first['animalNombre'], 'Toby');
    });

    test('guardar() completa adoptanteId y creadoEn — la pantalla solo '
        'pasa los datos del animal', () async {
      await repo.guardar(
        uid: 'u1',
        rescateId: 'r1',
        animalNombre: 'Toby',
        datos: {'animalNombre': 'Toby', 'especie': 'Perro'},
      );

      final doc = await firestore.collection('favoritos').doc('u1_r1').get();
      expect(doc['adoptanteId'], 'u1');
      expect(doc['especie'], 'Perro');
      expect(doc.data()!.containsKey('creadoEn'), true);
    });

    test('guardar() dos veces el mismo animal NO duplica: actualiza el '
        'mismo documento (id determinístico + merge)', () async {
      await repo.guardar(
        uid: 'u1',
        rescateId: 'r1',
        animalNombre: 'Toby',
        datos: {'animalNombre': 'Toby', 'especie': 'Perro'},
      );
      await repo.guardar(
        uid: 'u1',
        rescateId: 'r1',
        animalNombre: 'Toby',
        datos: {'animalNombre': 'Tobías'},
      );

      final todos = await firestore.collection('favoritos').get();
      expect(todos.docs.length, 1);
      final doc = todos.docs.first;
      expect(doc['animalNombre'], 'Tobías');
      // merge: lo que no vino en la segunda llamada sobrevive.
      expect(doc['especie'], 'Perro');
    });

    test('eliminar() borra el favorito', () async {
      await repo.guardar(
        uid: 'u1',
        rescateId: 'r1',
        animalNombre: 'Toby',
        datos: const {},
      );
      await repo.eliminar('u1_r1');
      expect(
        (await firestore.collection('favoritos').doc('u1_r1').get()).exists,
        false,
      );
    });

    group(
      'deRescate — para limpiar los favoritos cuando se elimina un animal. '
      'El filtro por rescatistaId no es de más: las reglas solo dejan que '
      'el dueño toque estos documentos, y Firestore rechaza ENTERA una '
      'consulta que pudiera devolver algo sin permiso (mismo motivo, y '
      'mismo bug, que SolicitudesRepository._hayAlguna).',
      () {
        test('trae los favoritos de ESE animal', () async {
          await firestore.collection('favoritos').add({
            'rescateId': 'r1',
            'rescatistaId': 'dueno1',
            'animalNombre': 'Toby',
          });
          await firestore.collection('favoritos').add({
            'rescateId': 'r2',
            'rescatistaId': 'dueno1',
            'animalNombre': 'Luna',
          });

          final snap = await repo.deRescate(
            rescateId: 'r1',
            rescatistaId: 'dueno1',
          );

          expect(snap.docs.length, 1);
          expect(snap.docs.first['animalNombre'], 'Toby');
        });

        test('acotado al dueño: no devuelve el favorito de un animal de '
            'otra persona aunque coincida el rescateId', () async {
          await firestore.collection('favoritos').add({
            'rescateId': 'r1',
            'rescatistaId': 'otro-dueno',
            'animalNombre': 'Toby',
          });

          final snap = await repo.deRescate(
            rescateId: 'r1',
            rescatistaId: 'dueno1',
          );

          expect(snap.docs, isEmpty);
        });
      },
    );
  });
}
