import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salva_patitas/data/hogares_de_paso_repository.dart';

// fake_cloud_firestore siempre resuelve al toque — para probar que una
// escritura que NUNCA resuelve (sin señal) se corta sola con timeout hace
// falta controlar la respuesta a mano.
class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class MockCollectionReference extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class MockDocumentReference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

void main() {
  group('HogaresDePasoRepository', () {
    late FakeFirebaseFirestore firestore;
    late HogaresDePasoRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = HogaresDePasoRepository(db: firestore);
    });

    test(
      'registrarAyuda() agrega a la persona con vecesAyudo=1 la primera vez',
      () async {
        await repo.registrarAyuda(
          albergueId: 'alb-1',
          adoptanteId: 'ad-1',
          nombre: 'Karen Cancino',
        );

        final doc = await firestore
            .collection('hogaresDePaso')
            .doc('alb-1_ad-1')
            .get();
        expect(doc.exists, true);
        expect(doc['nombre'], 'Karen Cancino');
        expect(doc['vecesAyudo'], 1);
        expect(doc['albergueId'], 'alb-1');
        expect(doc['agregadoManualmente'], false);
      },
    );

    test(
      'registrarAyuda() suma 1 (no duplica la fila) si la misma persona ya ayudó antes — '
      'es justo el punto de la mejora: la red recuerda el historial en vez de arrancar de cero '
      'con cada solicitud nueva',
      () async {
        await repo.registrarAyuda(
          albergueId: 'alb-1',
          adoptanteId: 'ad-1',
          nombre: 'Karen Cancino',
        );
        await repo.registrarAyuda(
          albergueId: 'alb-1',
          adoptanteId: 'ad-1',
          nombre: 'Karen Cancino',
        );
        await repo.registrarAyuda(
          albergueId: 'alb-1',
          adoptanteId: 'ad-1',
          nombre: 'Karen Cancino',
        );

        final todos = await firestore.collection('hogaresDePaso').get();
        expect(todos.docs.length, 1);
        expect(todos.docs.first['vecesAyudo'], 3);
      },
    );

    test(
      'registrarAyuda() con adoptanteId vacío no hace nada (dato legado sin adoptanteId)',
      () async {
        await repo.registrarAyuda(
          albergueId: 'alb-1',
          adoptanteId: '',
          nombre: 'Alguien',
        );

        final todos = await firestore.collection('hogaresDePaso').get();
        expect(todos.docs, isEmpty);
      },
    );

    test(
      'registrarAyuda() fusiona con una fila agregada a mano que tenga el mismo email, '
      'en vez de crear una fila duplicada para la misma persona',
      () async {
        await repo.agregarManual(
          albergueId: 'alb-1',
          nombre: 'David Casas',
          email: 'david@ejemplo.com',
        );

        await repo.registrarAyuda(
          albergueId: 'alb-1',
          adoptanteId: 'uid-david',
          nombre: 'David Casas',
          email: 'david@ejemplo.com',
        );

        final todos = await firestore.collection('hogaresDePaso').get();
        expect(
          todos.docs.length,
          1,
          reason:
              'no debería haber creado una segunda fila para la misma persona',
        );
        final d = todos.docs.first.data();
        expect(
          d['adoptanteId'],
          'uid-david',
          reason: 'la fila agregada a mano queda vinculada a la cuenta real',
        );
        expect(d['vecesAyudo'], 1);
        expect(
          d['agregadoManualmente'],
          false,
          reason:
              'ya quedó vinculada a una cuenta real — no debe seguir marcada como manual para siempre '
              '(hallazgo de auditoría de código)',
        );
      },
    );

    // El bug real: David.Casas@Gmail.com (como lo tipeó el albergue a mano)
    // y david.casas@gmail.com (el email real de Google Sign-In, ya en
    // minúsculas) no calzaban en una comparación exacta — el sistema
    // pensado justo para este caso terminaba creando una fila duplicada.
    test('registrarAyuda() fusiona con una fila a mano aunque el email tenga '
        'mayúsculas distintas — David.Casas@Gmail.com y david.casas@gmail.com '
        'son la misma persona', () async {
      await repo.agregarManual(
        albergueId: 'alb-1',
        nombre: 'David Casas',
        email: 'David.Casas@Gmail.com',
      );

      await repo.registrarAyuda(
        albergueId: 'alb-1',
        adoptanteId: 'uid-david',
        nombre: 'David Casas',
        email: 'david.casas@gmail.com',
      );

      final todos = await firestore.collection('hogaresDePaso').get();
      expect(
        todos.docs.length,
        1,
        reason:
            'no debería haber creado una segunda fila por la diferencia de mayúsculas',
      );
      expect(todos.docs.first['adoptanteId'], 'uid-david');
      expect(todos.docs.first['vecesAyudo'], 1);
    });

    test(
      'agregarManual() guarda el email en minúsculas, sin espacios alrededor',
      () async {
        await repo.agregarManual(
          albergueId: 'alb-1',
          nombre: 'David Casas',
          email: '  David.Casas@Gmail.com  ',
        );

        final todos = await firestore.collection('hogaresDePaso').get();
        expect(todos.docs.first['email'], 'david.casas@gmail.com');
      },
    );

    test(
      'actualizarContacto() también normaliza el email a minúsculas',
      () async {
        final ref = await firestore.collection('hogaresDePaso').add({
          'albergueId': 'alb-1',
          'nombre': 'Karen Cancino',
          'email': '',
        });

        await repo.actualizarContacto(
          ref.id,
          telefono: '',
          notas: '',
          email: 'Karen.Cancino@Gmail.com',
        );

        final doc = await ref.get();
        expect(doc['email'], 'karen.cancino@gmail.com');
      },
    );

    // El bug real que esto arregla: antes `email` tenía un valor por
    // defecto (`= ''`), así que CUALQUIER llamado que se olvidara de
    // pasarlo borraba en silencio el email ya guardado — justo el dato que
    // permite fusionar esta fila con la cuenta real de la persona más
    // adelante (ver registrarAyuda). Ahora email es `String?` sin default:
    // si no se pasa, el campo ni se toca.
    test(
      'actualizarContacto() SIN pasar email no borra el que ya estaba guardado',
      () async {
        final ref = await firestore.collection('hogaresDePaso').add({
          'albergueId': 'alb-1',
          'nombre': 'Karen Cancino',
          'email': 'karen@ejemplo.com',
        });

        await repo.actualizarContacto(
          ref.id,
          telefono: '3009999999',
          notas: 'Nueva nota',
        );

        final doc = await ref.get();
        expect(
          doc['email'],
          'karen@ejemplo.com',
          reason: 'el email no se tocó',
        );
        expect(doc['telefono'], '3009999999');
        expect(doc['notas'], 'Nueva nota');
      },
    );

    test('actualizarContacto() SÍ borra el email si se pasa explícitamente '
        'vacío — sigue siendo una decisión consciente y posible, no un '
        'accidente por omisión', () async {
      final ref = await firestore.collection('hogaresDePaso').add({
        'albergueId': 'alb-1',
        'nombre': 'Karen Cancino',
        'email': 'karen@ejemplo.com',
      });

      await repo.actualizarContacto(ref.id, telefono: '', notas: '', email: '');

      final doc = await ref.get();
      expect(doc['email'], '');
    });

    test(
      'registrarAyuda() después de fusionar por email, la segunda ayuda de esa cuenta suma '
      'sobre la misma fila (ya no vuelve a buscar por email)',
      () async {
        await repo.agregarManual(
          albergueId: 'alb-1',
          nombre: 'David Casas',
          email: 'david@ejemplo.com',
        );
        await repo.registrarAyuda(
          albergueId: 'alb-1',
          adoptanteId: 'uid-david',
          nombre: 'David Casas',
          email: 'david@ejemplo.com',
        );

        await repo.registrarAyuda(
          albergueId: 'alb-1',
          adoptanteId: 'uid-david',
          nombre: 'David Casas',
          email: 'david@ejemplo.com',
        );

        final todos = await firestore.collection('hogaresDePaso').get();
        expect(todos.docs.length, 1);
        expect(todos.docs.first['vecesAyudo'], 2);
      },
    );

    test(
      'registrarAyuda() sin email no fusiona con nada — crea su propia fila',
      () async {
        await repo.agregarManual(
          albergueId: 'alb-1',
          nombre: 'David Casas',
          email: 'david@ejemplo.com',
        );

        await repo.registrarAyuda(
          albergueId: 'alb-1',
          adoptanteId: 'uid-otro',
          nombre: 'Otra Persona',
        );

        final todos = await firestore.collection('hogaresDePaso').get();
        expect(todos.docs.length, 2);
      },
    );

    test('deAlbergue() solo devuelve las filas de ese albergue', () async {
      await repo.registrarAyuda(
        albergueId: 'alb-1',
        adoptanteId: 'ad-1',
        nombre: 'Karen',
      );
      await repo.registrarAyuda(
        albergueId: 'alb-2',
        adoptanteId: 'ad-2',
        nombre: 'Henning',
      );

      final propias = await repo.deAlbergue('alb-1').first;
      expect(propias.docs.length, 1);
      expect(propias.docs.first['nombre'], 'Karen');
    });

    group('buscarDuplicado() — evita que agregarManual() cree la misma '
        'persona varias veces (hallazgo real de Eliza: "Pepito Perez" '
        'repetido 3 veces en la red, porque agregarManual() no chequeaba '
        'nada antes de crear)', () {
      test(
        'encuentra una fila existente con el mismo nombre Y el mismo email',
        () async {
          await repo.agregarManual(
            albergueId: 'alb-1',
            nombre: 'Pepito Perez',
            email: 'pepito@ejemplo.com',
          );

          final duplicado = await repo.buscarDuplicado(
            albergueId: 'alb-1',
            nombre: 'Pepito Perez',
            email: 'pepito@ejemplo.com',
          );

          expect(duplicado, isNotNull);
          expect(duplicado!['nombre'], 'Pepito Perez');
        },
      );

      test(
        'encuentra el duplicado aunque cambien mayúsculas/espacios en nombre '
        'o email — el caso real: volver a tipear el mismo dato no calza siempre igual',
        () async {
          await repo.agregarManual(
            albergueId: 'alb-1',
            nombre: '  Pepito Perez  ',
            email: 'Pepito@Ejemplo.com',
          );

          final duplicado = await repo.buscarDuplicado(
            albergueId: 'alb-1',
            nombre: 'pepito perez',
            email: 'pepito@ejemplo.com',
          );

          expect(duplicado, isNotNull);
        },
      );

      test('NO avisa si el nombre coincide pero el email es distinto — dos '
          'personas reales pueden compartir nombre, pedido explícito de '
          'Eliza para no molestar con falsos positivos', () async {
        await repo.agregarManual(
          albergueId: 'alb-1',
          nombre: 'Pepito Perez',
          email: 'pepito.uno@ejemplo.com',
        );

        final duplicado = await repo.buscarDuplicado(
          albergueId: 'alb-1',
          nombre: 'Pepito Perez',
          email: 'pepito.dos@ejemplo.com',
        );

        expect(duplicado, isNull);
      });

      test('null si no hay ninguna fila con ese nombre+email', () async {
        await repo.agregarManual(
          albergueId: 'alb-1',
          nombre: 'Karen Cancino',
          email: 'karen@ejemplo.com',
        );

        final duplicado = await repo.buscarDuplicado(
          albergueId: 'alb-1',
          nombre: 'Pepito Perez',
          email: 'pepito@ejemplo.com',
        );

        expect(duplicado, isNull);
      });

      test(
        'no cruza con el mismo nombre+email en la red de OTRO albergue',
        () async {
          await repo.agregarManual(
            albergueId: 'alb-2',
            nombre: 'Pepito Perez',
            email: 'pepito@ejemplo.com',
          );

          final duplicado = await repo.buscarDuplicado(
            albergueId: 'alb-1',
            nombre: 'Pepito Perez',
            email: 'pepito@ejemplo.com',
          );

          expect(duplicado, isNull);
        },
      );

      test('nombre o email vacíos nunca cuentan como duplicado', () async {
        await repo.agregarManual(albergueId: 'alb-1', nombre: '', email: '');

        expect(
          await repo.buscarDuplicado(
            albergueId: 'alb-1',
            nombre: '',
            email: 'x@x.com',
          ),
          isNull,
        );
        expect(
          await repo.buscarDuplicado(
            albergueId: 'alb-1',
            nombre: 'Pepito',
            email: '',
          ),
          isNull,
        );
      });
    });

    test(
      'agregarManual() crea una fila con vecesAyudo=0 marcada como manual — '
      'para alguien de confianza que el albergue conoce fuera de la app',
      () async {
        await repo.agregarManual(
          albergueId: 'alb-1',
          nombre: 'Doña Marta',
          telefono: '3001234567',
        );

        final todos = await firestore.collection('hogaresDePaso').get();
        expect(todos.docs.length, 1);
        final d = todos.docs.first.data();
        expect(d['nombre'], 'Doña Marta');
        expect(d['telefono'], '3001234567');
        expect(d['vecesAyudo'], 0);
        expect(d['agregadoManualmente'], true);
      },
    );

    test(
      'actualizarContacto() carga teléfono/notas en una fila existente — '
      'para completar los datos de las filas que se agregaron solas, sin teléfono ni notas',
      () async {
        final ref = await firestore.collection('hogaresDePaso').add({
          'albergueId': 'alb-1',
          'nombre': 'Karen Cancino',
          'telefono': '',
          'notas': '',
        });

        await repo.actualizarContacto(
          ref.id,
          telefono: '3009999999',
          notas: 'Vive cerca del albergue',
        );

        final doc = await ref.get();
        expect(doc['telefono'], '3009999999');
        expect(doc['notas'], 'Vive cerca del albergue');
      },
    );

    test('eliminar() borra la fila', () async {
      final ref = await firestore.collection('hogaresDePaso').add({
        'nombre': 'X',
      });

      await repo.eliminar(ref.id);

      expect((await ref.get()).exists, false);
    });

    // El bug real que esto arregla: sin señal, un .add()/.update()/.delete()
    // de Firestore no falla, se queda esperando al servidor para siempre —
    // agregarManual() ya tenía un try/catch en hogares_de_paso_screen.dart
    // que nunca llegaba a dispararse porque nunca había una excepción que
    // atrapar, y actualizarContacto()/eliminar() ni siquiera tenían eso. El
    // timeout vive DENTRO del repositorio para que ningún llamador nuevo
    // pueda volver a olvidarse de ponerlo.
    group('timeout — sin señal, no se cuelga para siempre', () {
      test(
        'agregarManual() se corta con TimeoutException si el .add() nunca resuelve',
        () async {
          final db = MockFirebaseFirestore();
          final col = MockCollectionReference();
          when(() => db.collection('hogaresDePaso')).thenReturn(col);
          when(() => col.add(any())).thenAnswer(
            (_) => Completer<DocumentReference<Map<String, dynamic>>>().future,
          );

          final repoConMock = HogaresDePasoRepository(db: db);
          await expectLater(
            repoConMock.agregarManual(
              albergueId: 'alb-1',
              nombre: 'Doña Marta',
              timeout: const Duration(milliseconds: 50),
            ),
            throwsA(isA<TimeoutException>()),
          );
        },
      );

      test(
        'actualizarContacto() se corta con TimeoutException si el .update() nunca resuelve',
        () async {
          final db = MockFirebaseFirestore();
          final col = MockCollectionReference();
          final ref = MockDocumentReference();
          when(() => db.collection('hogaresDePaso')).thenReturn(col);
          when(() => col.doc(any())).thenReturn(ref);
          when(
            () => ref.update(any()),
          ).thenAnswer((_) => Completer<void>().future);

          final repoConMock = HogaresDePasoRepository(db: db);
          await expectLater(
            repoConMock.actualizarContacto(
              'hp1',
              telefono: '300',
              notas: '',
              timeout: const Duration(milliseconds: 50),
            ),
            throwsA(isA<TimeoutException>()),
          );
        },
      );

      test(
        'eliminar() se corta con TimeoutException si el .delete() nunca resuelve',
        () async {
          final db = MockFirebaseFirestore();
          final col = MockCollectionReference();
          final ref = MockDocumentReference();
          when(() => db.collection('hogaresDePaso')).thenReturn(col);
          when(() => col.doc(any())).thenReturn(ref);
          when(() => ref.delete()).thenAnswer((_) => Completer<void>().future);

          final repoConMock = HogaresDePasoRepository(db: db);
          await expectLater(
            repoConMock.eliminar(
              'hp1',
              timeout: const Duration(milliseconds: 50),
            ),
            throwsA(isA<TimeoutException>()),
          );
        },
      );
    });
  });

  group(
    'sumarAyudaManual() — el cuidador de un hogar de paso puesto A MANO no '
    'tiene cuenta en la app. registrarAyuda() no sirve para eso: corta de '
    'entrada si no hay adoptanteId, porque su trabajo es vincular a una '
    'cuenta real.',
    () {
      late FakeFirebaseFirestore db;
      late HogaresDePasoRepository repo;

      setUp(() {
        db = FakeFirebaseFirestore();
        repo = HogaresDePasoRepository(db: db);
      });

      Future<List<Map<String, dynamic>>> red() async =>
          (await db.collection('hogaresDePaso').get())
              .docs
              .map((d) => d.data())
              .toList();

      test('la primera vez la agrega a la red', () async {
        await repo.sumarAyudaManual(
          albergueId: 'refugio',
          nombre: 'María González',
          email: 'maria@correo.com',
        );
        final filas = await red();
        expect(filas, hasLength(1));
        expect(filas.first['nombre'], 'María González');
        expect(filas.first['adoptanteId'], '', reason: 'no tiene cuenta');
      });

      // Lo que evita la fila repetida: la misma persona cuidando un segundo
      // animalito suma una ayuda, no crea otra fila.
      test('la segunda vez suma una ayuda, no duplica', () async {
        await repo.sumarAyudaManual(
          albergueId: 'refugio',
          nombre: 'María González',
          email: 'maria@correo.com',
        );
        await repo.sumarAyudaManual(
          albergueId: 'refugio',
          nombre: 'María González',
          email: 'maria@correo.com',
        );
        final filas = await red();
        expect(filas, hasLength(1), reason: 'sigue habiendo una sola');
        expect(filas.first['vecesAyudo'], 2);
      });

      test('el email no distingue mayúsculas ni espacios', () async {
        await repo.sumarAyudaManual(
          albergueId: 'refugio',
          nombre: 'María González',
          email: 'maria@correo.com',
        );
        await repo.sumarAyudaManual(
          albergueId: 'refugio',
          nombre: 'María González',
          email: '  MARIA@Correo.com ',
        );
        expect(await red(), hasLength(1));
      });

      // Sin email no hay forma de afirmar que dos "María" son la misma
      // persona. Se agrega una fila nueva a propósito: preferimos dos filas
      // que se puedan unir a mano antes que fusionar a dos personas
      // distintas por tener el mismo nombre.
      test('sin email agrega fila nueva, no fusiona por nombre', () async {
        await repo.sumarAyudaManual(albergueId: 'refugio', nombre: 'María');
        await repo.sumarAyudaManual(albergueId: 'refugio', nombre: 'María');
        expect(await red(), hasLength(2));
      });

      test('otro albergue no ve ni pisa la red del primero', () async {
        await repo.sumarAyudaManual(
          albergueId: 'refugio',
          nombre: 'María González',
          email: 'maria@correo.com',
        );
        await repo.sumarAyudaManual(
          albergueId: 'otro_refugio',
          nombre: 'María González',
          email: 'maria@correo.com',
        );
        final filas = await red();
        expect(filas, hasLength(2));
        expect(filas.every((f) => f['vecesAyudo'] == 1), isTrue);
      });

      test('sin nombre no hace nada', () async {
        await repo.sumarAyudaManual(albergueId: 'refugio', nombre: '   ');
        expect(await red(), isEmpty);
      });
    },
  );
}
