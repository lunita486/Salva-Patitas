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

    test('crearPerfil crea el perfil con sus campos y roles', () async {
      await repo.crearPerfil(
        uid: 'u2',
        nombre: 'Eliza',
        email: 'e@x.com',
        foto: null,
        roles: ['adoptante', 'rescatista'],
        ciudad: 'Medellín',
      );
      final doc = await firestore.collection('usuarios').doc('u2').get();
      expect(doc['nombre'], 'Eliza');
      expect(doc['roles'], ['adoptante', 'rescatista']);
      expect(doc['ciudad'], 'Medellín');
    });

    test('crearPerfil sobre un perfil que YA existía no pisa campos ajenos '
        '(el bug de seleccion_rol_screen: un set() sin merge borraba '
        'fcmToken, fotoBase64, etc. del usuario existente)', () async {
      await firestore.collection('usuarios').doc('u3').set({
        'nombre': 'Ana',
        'roles': ['rescatista'],
        'fcmToken': 'token-importante',
        'fotoBase64': 'foto-perfil',
      });

      await repo.crearPerfil(
        uid: 'u3',
        nombre: 'Ana G.',
        roles: ['adoptante'],
      );

      final doc = await firestore.collection('usuarios').doc('u3').get();
      expect(doc['fcmToken'], 'token-importante',
          reason: 'merge:true no debe borrar campos que crearPerfil no escribe');
      expect(doc['fotoBase64'], 'foto-perfil');
      expect(doc['roles'], ['adoptante'],
          reason: 'los campos que sí escribe se actualizan normalmente');
    });

    test('crearPerfil rechaza un rol inválido en modo debug (assert)', () {
      expect(
        () => repo.crearPerfil(uid: 'u4', nombre: 'X', roles: ['hacker']),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
