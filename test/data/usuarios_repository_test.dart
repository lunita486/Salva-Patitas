import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:patitas_medellin/data/usuarios_repository.dart';

// Mismo patrón que rescates_repository_test.dart: para probar el reintento
// tras un permission-denied hace falta controlar a mano cuándo falla la
// escritura, algo que FakeFirebaseFirestore no simula.
class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class MockCollectionReference extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class MockDocumentReference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUser extends Mock implements User {}

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

    test('asegurarPerfilBase crea el doc desde el primer login, SIN roles — '
        'así AuthWrapper nunca espera que el servidor confirme "cuenta '
        'nueva" (el camino frágil donde facturasmaxiloncheras quedaba '
        'atrapada en el spinner de arranque) y el guard de roles vacíos la '
        'manda directo a elegir rol', () async {
      await repo.asegurarPerfilBase(
        uid: 'u5',
        nombre: 'Carmen',
        email: 'facturas@x.com',
        foto: 'https://foto',
      );
      final doc = await firestore.collection('usuarios').doc('u5').get();
      expect(doc.exists, true);
      expect(doc['nombre'], 'Carmen');
      expect(doc['email'], 'facturas@x.com');
      expect(doc.data()!.containsKey('roles'), false,
          reason: 'elegir rol sigue siendo del onboarding, no del login');
    });

    test('asegurarPerfilBase sobre una cuenta que YA tiene perfil solo '
        'refresca nombre/email/foto — no pisa roles ni ningún otro campo', () async {
      await firestore.collection('usuarios').doc('u6').set({
        'nombre': 'Ana',
        'roles': ['albergue'],
        'albergueNombre': 'La Perla',
        'fcmToken': 'token-importante',
      });

      await repo.asegurarPerfilBase(uid: 'u6', nombre: 'Ana García', email: 'ana@x.com');

      final doc = await firestore.collection('usuarios').doc('u6').get();
      expect(doc['roles'], ['albergue']);
      expect(doc['albergueNombre'], 'La Perla');
      expect(doc['fcmToken'], 'token-importante');
      expect(doc['nombre'], 'Ana García');
      expect(doc['email'], 'ana@x.com');
    });

    test('asegurarPerfilBase con datos vacíos o null no escribe basura — '
        'crea el doc igual (vacío), que es lo único que AuthWrapper necesita '
        'para no quedarse esperando al servidor', () async {
      await repo.asegurarPerfilBase(uid: 'u7', nombre: null, email: '', foto: null);
      final doc = await firestore.collection('usuarios').doc('u7').get();
      expect(doc.exists, true);
      expect(doc.data(), isEmpty);
    });

    group('permission-denied casi siempre es un token vencido, no falta de '
        'permiso real (la regla solo exige uid() == userId, y quien llega a '
        'elegir rol ya está logueado con ese uid) — el bug real: justo '
        'después de un borrado masivo de cuentas de prueba, una cuenta que '
        'recién inicia sesión puede traer un token viejo, y el mensaje '
        'engañaba diciendo "revisá tu conexión" cuando no era de red', () {
      test('crearPerfil renueva el token y reintenta UNA vez', () async {
        final db = MockFirebaseFirestore();
        final col = MockCollectionReference();
        final ref = MockDocumentReference();
        final auth = MockFirebaseAuth();
        final user = MockUser();
        when(() => db.collection('usuarios')).thenReturn(col);
        when(() => col.doc('u8')).thenReturn(ref);
        when(() => auth.currentUser).thenReturn(user);
        when(() => user.getIdToken(true)).thenAnswer((_) async => 'token-nuevo');
        var intentos = 0;
        when(() => ref.set(any(), any())).thenAnswer((_) {
          intentos++;
          if (intentos == 1) {
            throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
          }
          return Future.value();
        });

        final repoConMock = UsuariosRepository(db: db, auth: auth);
        await repoConMock.crearPerfil(uid: 'u8', nombre: 'Carmen', roles: ['albergue']);

        expect(intentos, 2);
        verify(() => user.getIdToken(true)).called(1);
      });

      test('actualizarRoles renueva el token y reintenta UNA vez', () async {
        final db = MockFirebaseFirestore();
        final col = MockCollectionReference();
        final ref = MockDocumentReference();
        final auth = MockFirebaseAuth();
        final user = MockUser();
        when(() => db.collection('usuarios')).thenReturn(col);
        when(() => col.doc('u9')).thenReturn(ref);
        when(() => auth.currentUser).thenReturn(user);
        when(() => user.getIdToken(true)).thenAnswer((_) async => 'token-nuevo');
        var intentos = 0;
        when(() => ref.update(any())).thenAnswer((_) {
          intentos++;
          if (intentos == 1) {
            throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
          }
          return Future.value();
        });

        final repoConMock = UsuariosRepository(db: db, auth: auth);
        await repoConMock.actualizarRoles('u9', ['adoptante']);

        expect(intentos, 2);
        verify(() => user.getIdToken(true)).called(1);
      });

      test('si sigue fallando incluso con el token renovado, propaga la '
          'excepción — no es un reintento infinito', () async {
        final db = MockFirebaseFirestore();
        final col = MockCollectionReference();
        final ref = MockDocumentReference();
        final auth = MockFirebaseAuth();
        final user = MockUser();
        when(() => db.collection('usuarios')).thenReturn(col);
        when(() => col.doc('u10')).thenReturn(ref);
        when(() => auth.currentUser).thenReturn(user);
        when(() => user.getIdToken(true)).thenAnswer((_) async => 'token-nuevo');
        when(() => ref.update(any())).thenThrow(
            FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));

        final repoConMock = UsuariosRepository(db: db, auth: auth);
        await expectLater(
          repoConMock.actualizarRoles('u10', ['adoptante']),
          throwsA(isA<FirebaseException>()),
        );
      });

      test('en cualquier OTRO error (ej. sin conexión) NO reintenta ni toca '
          'el token', () async {
        final db = MockFirebaseFirestore();
        final col = MockCollectionReference();
        final ref = MockDocumentReference();
        final auth = MockFirebaseAuth();
        when(() => db.collection('usuarios')).thenReturn(col);
        when(() => col.doc('u11')).thenReturn(ref);
        when(() => ref.update(any())).thenThrow(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));

        final repoConMock = UsuariosRepository(db: db, auth: auth);
        await expectLater(
          repoConMock.actualizarRoles('u11', ['adoptante']),
          throwsA(isA<FirebaseException>()),
        );
        verifyNever(() => auth.currentUser);
      });
    });
  });
}
