import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:patitas_medellin/data/firestore_resiliencia.dart';

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
}
