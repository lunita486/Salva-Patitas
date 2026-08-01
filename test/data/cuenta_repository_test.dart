import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:patitas_medellin/data/cuenta_repository.dart';

// Mismo patrón que usuarios_repository_test.dart: se mockean los tipos de
// Firebase (acá cloud_functions) para poder controlar a mano qué devuelve/
// lanza la llamada, algo que no hay forma de simular sin una Cloud
// Function real desplegada.
class MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class MockHttpsCallable extends Mock implements HttpsCallable {}

class MockHttpsCallableResult extends Mock
    implements HttpsCallableResult<dynamic> {}

void main() {
  group('CuentaRepository', () {
    late MockFirebaseFunctions functions;
    late MockHttpsCallable callable;
    late CuentaRepository repo;

    setUp(() {
      functions = MockFirebaseFunctions();
      callable = MockHttpsCallable();
      when(() => functions.httpsCallable('eliminarCuenta')).thenReturn(callable);
      repo = CuentaRepository(functions: functions);
    });

    test('eliminarCuenta() invoca la Cloud Function "eliminarCuenta" y no lanza nada si sale bien', () async {
      when(() => callable.call()).thenAnswer((_) async => MockHttpsCallableResult());

      await repo.eliminarCuenta();

      verify(() => functions.httpsCallable('eliminarCuenta')).called(1);
    });

    test('eliminarCuenta() traduce un failed-precondition del servidor a CuentaBloqueada, '
        'con el mismo mensaje que mandó la función (ya viene listo para mostrar)', () async {
      when(() => callable.call()).thenThrow(FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'Tenés un animal en hogar de paso o en proceso de adopción a tu cargo ahora mismo.',
      ));

      await expectLater(
        repo.eliminarCuenta(),
        throwsA(isA<CuentaBloqueada>().having(
            (e) => e.mensaje, 'mensaje', contains('hogar de paso'))),
      );
    });

    test('eliminarCuenta() propaga sin traducir cualquier otro error (ej. internal, unauthenticated)', () async {
      when(() => callable.call()).thenThrow(FirebaseFunctionsException(
        code: 'internal',
        message: 'No pudimos eliminar tu cuenta por completo. Volvé a intentar en un momento.',
      ));

      await expectLater(
        repo.eliminarCuenta(),
        throwsA(isA<FirebaseFunctionsException>()),
      );
    });
  });

  group('CuentaRepository.mensajeError', () {
    test('para CuentaBloqueada, devuelve el mensaje tal cual (ya es específico y accionable)', () {
      final error = CuentaBloqueada('Tenés un animal en hogar de paso ahora mismo.');
      expect(CuentaRepository.mensajeError(error), 'Tenés un animal en hogar de paso ahora mismo.');
    });

    test('para cualquier otro error, devuelve un mensaje genérico de conexión', () {
      expect(CuentaRepository.mensajeError(Exception('lo que sea')),
          contains('Revisá tu conexión'));
    });
  });
}
