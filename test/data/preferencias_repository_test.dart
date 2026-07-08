import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patitas_medellin/data/preferencias_repository.dart';

void main() {
  group('PreferenciasRepository', () {
    late FakeFirebaseFirestore firestore;
    late PreferenciasRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = PreferenciasRepository(db: firestore);
    });

    test('cada uid tiene su propio documento (arregla el bug del doc compartido)', () async {
      await repo.actualizar('user-1', {'tema': 'oscuro'});
      await repo.actualizar('user-2', {'tema': 'claro'});

      final doc1 = await repo.stream('user-1').first;
      final doc2 = await repo.stream('user-2').first;

      expect(doc1.id, 'user-1');
      expect(doc1['tema'], 'oscuro');
      expect(doc2.id, 'user-2');
      expect(doc2['tema'], 'claro');
    });

    test('actualizar() usa merge, no pisa campos existentes', () async {
      await repo.actualizar('user-1', {'tema': 'oscuro', 'idioma': 'es'});
      await repo.actualizar('user-1', {'tema': 'claro'});
      final doc = await repo.stream('user-1').first;
      expect(doc['tema'], 'claro');
      expect(doc['idioma'], 'es');
    });
  });
}
