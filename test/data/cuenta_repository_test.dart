import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salva_patitas/data/cuenta_repository.dart';

// Mismo patrón que usuarios_repository_test.dart: se mockean los tipos de
// Firebase (acá cloud_functions) para poder controlar a mano qué devuelve/
// lanza la llamada, algo que no hay forma de simular sin una Cloud
// Function real desplegada.
class MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class MockHttpsCallable extends Mock implements HttpsCallable {}

class MockHttpsCallableResult extends Mock
    implements HttpsCallableResult<dynamic> {}

void main() {
  // Bug real, roto para TODOS: FirebaseFunctions.instance (sin región)
  // apunta a us-central1 por defecto, pero eliminarCuenta se desplegó en
  // europe-west1 — cualquier pedido de borrado llamaba a una función que
  // no existe ahí, así que ni un solo intento real llegaba a ejecutarse
  // del lado del servidor, y la app mostraba el error genérico de "revisá
  // tu conexión" sin importar la conexión de la persona. No hay forma de
  // probar la construcción real de FirebaseFunctions.instanceFor(...) sin
  // Firebase inicializado — esto al menos deja una alarma si alguien
  // cambia la región acá sin actualizar también dónde vive la función
  // desplegada (o viceversa).
  test(
    'CuentaRepository.region coincide con la región real donde está '
    'desplegada la función eliminarCuenta (functions/eliminar_cuenta.js)',
    () {
      expect(CuentaRepository.region, 'europe-west1');
    },
  );

  // Antes 120s — nadie se queda mirando un spinner sin ninguna señal de
  // progreso durante dos minutos enteros; Eliza terminó cerrando la app a
  // la fuerza (el borrado había terminado bien del lado del servidor de
  // todos modos, pero no tenía forma de saberlo desde la pantalla). Este
  // test es la alarma si alguien vuelve a subirlo sin querer.
  test(
    'eliminarCuenta() espera 30s por defecto antes de avisar que puede '
    'seguir terminando de fondo, no los 2 minutos completos de antes — '
    'fakeAsync() para no hacer esperar 30s reales a cada corrida del '
    'suite',
    () {
      final functions = MockFirebaseFunctions();
      final callable = MockHttpsCallable();
      when(
        () => functions.httpsCallable('eliminarCuenta'),
      ).thenReturn(callable);
      // Nunca responde: el único desenlace posible es que timeout() corte.
      when(() => callable.call()).thenAnswer(
        (_) => Completer<HttpsCallableResult<dynamic>>().future,
      );
      final repo = CuentaRepository(functions: functions);

      fakeAsync((async) {
        var lanzoTimeout = false;
        repo.eliminarCuenta().catchError((e) {
          lanzoTimeout = e is TimeoutException;
        });

        async.elapse(const Duration(seconds: 29));
        expect(lanzoTimeout, isFalse); // todavía no, a los 29s no venció

        async.elapse(const Duration(seconds: 2)); // cruza los 30s
        expect(lanzoTimeout, isTrue);
      });
    },
  );

  group('CuentaRepository', () {
    late MockFirebaseFunctions functions;
    late MockHttpsCallable callable;
    late CuentaRepository repo;

    setUp(() {
      functions = MockFirebaseFunctions();
      callable = MockHttpsCallable();
      when(
        () => functions.httpsCallable('eliminarCuenta'),
      ).thenReturn(callable);
      repo = CuentaRepository(functions: functions);
    });

    test(
      'eliminarCuenta() invoca la Cloud Function "eliminarCuenta" y no lanza nada si sale bien',
      () async {
        when(
          () => callable.call(),
        ).thenAnswer((_) async => MockHttpsCallableResult());

        await repo.eliminarCuenta();

        verify(() => functions.httpsCallable('eliminarCuenta')).called(1);
      },
    );

    test(
      'eliminarCuenta() traduce un failed-precondition del servidor a CuentaBloqueada, '
      'con el mismo mensaje que mandó la función (ya viene listo para mostrar)',
      () async {
        when(() => callable.call()).thenThrow(
          FirebaseFunctionsException(
            code: 'failed-precondition',
            message:
                'Tenés un animal en hogar de paso o en proceso de adopción a tu cargo ahora mismo.',
          ),
        );

        await expectLater(
          repo.eliminarCuenta(),
          throwsA(
            isA<CuentaBloqueada>().having(
              (e) => e.mensaje,
              'mensaje',
              contains('hogar de paso'),
            ),
          ),
        );
      },
    );

    test(
      'eliminarCuenta() propaga sin traducir cualquier otro error (ej. internal, unauthenticated)',
      () async {
        when(() => callable.call()).thenThrow(
          FirebaseFunctionsException(
            code: 'internal',
            message:
                'No pudimos eliminar tu cuenta por completo. Volvé a intentar en un momento.',
          ),
        );

        await expectLater(
          repo.eliminarCuenta(),
          throwsA(isA<FirebaseFunctionsException>()),
        );
      },
    );
  });

  group('CuentaRepository.mensajeError', () {
    test(
      'para CuentaBloqueada, devuelve el mensaje tal cual (ya es específico y accionable)',
      () {
        final error = CuentaBloqueada(
          'Tenés un animal en hogar de paso ahora mismo.',
        );
        expect(
          CuentaRepository.mensajeError(error),
          'Tenés un animal en hogar de paso ahora mismo.',
        );
      },
    );

    test(
      'para cualquier otro error, devuelve un mensaje genérico de conexión',
      () {
        expect(
          CuentaRepository.mensajeError(Exception('lo que sea')),
          contains('Revisá tu conexión'),
        );
      },
    );
  });
}
