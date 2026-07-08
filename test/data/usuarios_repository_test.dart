import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patitas_medellin/data/usuarios_repository.dart';

void main() {
  group('UsuariosRepository', () {
    late FakeFirebaseFirestore firestore;
    late UsuariosRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = UsuariosRepository(db: firestore);
    });

    test('actualizarRoles guarda una lista de roles válidos', () async {
      await firestore.collection('usuarios').doc('u1').set({'nombre': 'Ana'});
      await repo.actualizarRoles('u1', ['rescatista', 'albergue']);
      final doc = await firestore.collection('usuarios').doc('u1').get();
      expect(doc['roles'], ['rescatista', 'albergue']);
    });

    test('actualizarRoles rechaza un rol inválido en modo debug (assert)', () {
      expect(
        () => repo.actualizarRoles('u1', ['rescatista', 'no-es-un-rol']),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
