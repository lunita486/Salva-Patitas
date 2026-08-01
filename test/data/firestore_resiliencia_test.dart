import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:patitas_medellin/data/firestore_resiliencia.dart';

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUser extends Mock implements User {}

void main() {
  group('guardarConAviso', () {
    test('confirmado si la escritura termina antes del timeout', () async {
      final resultado = await guardarConAviso(
        () async {},
        timeout: const Duration(milliseconds: 200),
      );
      expect(resultado, ResultadoGuardado.confirmado);
    });

    // El caso real que esto arregla: 3 pantallas distintas (perfil de
    // albergue, perfil de aliado, publicar servicio) se quedaban con el
    // botón de "Guardar" pegado para siempre, sin ningún aviso, si la
    // escritura nunca terminaba (sin conexión) ni lanzaba ningún error
    // (un `.update()` de Firestore sin señal no lanza, simplemente no
    // vuelve hasta que reconecta). Esta prueba simula exactamente eso:
    // una escritura que nunca se resuelve sola.
    test('siguePendiente (no fallo) si la escritura nunca termina — el bug real que arregla esto', () async {
      final resultado = await guardarConAviso(
        () => Completer<void>().future, // nunca se resuelve
        timeout: const Duration(milliseconds: 200),
      );
      expect(resultado, ResultadoGuardado.siguePendiente);
    });

    test('fallo si la escritura lanza de verdad', () async {
      final resultado = await guardarConAviso(
        () async => throw Exception('permission-denied'),
        timeout: const Duration(milliseconds: 200),
      );
      expect(resultado, ResultadoGuardado.fallo);
    });

    test('nunca deja una excepción sin atrapar, ni con timeout ni con error real '
        '— la garantía completa: quien llama a esto SIEMPRE puede soltar el '
        'botón de guardar, pase lo que pase', () async {
      await expectLater(
        guardarConAviso(() => Completer<void>().future,
            timeout: const Duration(milliseconds: 50)),
        completion(isA<ResultadoGuardado>()),
      );
      await expectLater(
        guardarConAviso(() async => throw Exception('boom'),
            timeout: const Duration(milliseconds: 50)),
        completion(isA<ResultadoGuardado>()),
      );
    });
  });

  group('conReintentoSiTokenVencido', () {
    late MockFirebaseAuth auth;
    late MockUser user;

    setUp(() {
      auth = MockFirebaseAuth();
      user = MockUser();
      when(() => auth.currentUser).thenReturn(user);
      when(() => user.getIdToken(true)).thenAnswer((_) async => 'token-nuevo');
    });

    test('la escritura feliz se resuelve normal, sin tocar auth', () async {
      var llamadas = 0;
      await conReintentoSiTokenVencido(
        () => auth,
        () async { llamadas++; },
        timeout: const Duration(milliseconds: 200),
      );
      expect(llamadas, 1);
      verifyNever(() => user.getIdToken(true));
    });

    // El bug real que esto arregla: un `.set()`/`.update()` de Firestore sin
    // señal no lanza ningún error — se queda esperando al servidor para
    // siempre. Antes esta función no tenía ningún límite, así que
    // actualizarRoles()/crearPerfil() (usados por seleccion_rol_screen.dart
    // al elegir tu primer rol) podían quedarse colgados de por vida, sin
    // que el try/catch de la pantalla llegara a dispararse nunca — quedaba
    // el spinner trabado en vez del aviso de error que la pantalla ya
    // tenía escrito.
    test('una escritura que nunca termina (sin señal) se corta sola con '
        'timeout, en vez de colgarse para siempre', () async {
      await expectLater(
        conReintentoSiTokenVencido(
          () => auth,
          () => Completer<void>().future,
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('un permission-denied SÍ sigue reintentando una vez tras refrescar '
        'el token — no se rompió el comportamiento existente', () async {
      var llamadas = 0;
      await conReintentoSiTokenVencido(
        () => auth,
        () async {
          llamadas++;
          if (llamadas == 1) {
            throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
          }
        },
        timeout: const Duration(milliseconds: 200),
      );
      expect(llamadas, 2);
      verify(() => user.getIdToken(true)).called(1);
    });

    test('si el permission-denied persiste incluso con el token ya '
        'refrescado, se propaga — no es un reintento infinito', () async {
      await expectLater(
        conReintentoSiTokenVencido(
          () => auth,
          () async => throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
          timeout: const Duration(milliseconds: 200),
        ),
        throwsA(isA<FirebaseException>()),
      );
    });

    test('cualquier OTRO error (no permission-denied) se propaga de una, '
        'sin reintentar ni tocar el token', () async {
      var llamadas = 0;
      await expectLater(
        conReintentoSiTokenVencido(
          () => auth,
          () async {
            llamadas++;
            throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
          },
          timeout: const Duration(milliseconds: 200),
        ),
        throwsA(isA<FirebaseException>()),
      );
      expect(llamadas, 1);
      verifyNever(() => user.getIdToken(true));
    });

    test('si el REINTENTO (después de refrescar el token) también se '
        'cuelga, igual se corta con timeout en vez de colgarse para '
        'siempre', () async {
      var llamadas = 0;
      await expectLater(
        conReintentoSiTokenVencido(
          () => auth,
          () {
            llamadas++;
            if (llamadas == 1) {
              return Future<void>.error(
                  FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
            }
            return Completer<void>().future;
          },
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
