import 'package:flutter_test/flutter_test.dart';
import 'package:patitas_medellin/screens/solicitudes_rescatista_screen.dart';

// aprobarSolicitud()/rechazarSolicitud() tocan Firestore de verdad apenas
// pasan su candado (SolicitudesRepository()/RescatesRepository() sin
// inyección, igual que auth_helper.dart — ver el comentario en
// auth_helper_test.dart) — sin Firebase inicializado en este entorno,
// esa parte explota. No es lo que estas pruebas verifican: lo que importa
// acá es que el candado bloquee a TIEMPO, antes de llegar a esa parte.
// Una llamada "bloqueada" nunca toca Firestore y devuelve null al toque;
// una llamada que "pasa" el candado sí llega a intentarlo (y explota acá,
// lo cual también sirve de prueba: si el candado no bloqueara, las DOS
// llamadas concurrentes intentarían tocar Firestore a la vez).
enum _Resultado { bloqueada, intento }

Future<_Resultado> _clasificar(Future<Object?> Function() llamada) async {
  try {
    final r = await llamada();
    return r == null ? _Resultado.bloqueada : _Resultado.intento;
  } catch (_) {
    return _Resultado.intento;
  }
}

void main() {
  group('aprobarSolicitud/rechazarSolicitud — candado compartido entre pantallas', () {
    test('dos llamadas concurrentes a aprobarSolicitud con el MISMO docId — '
        'exactamente una pasa el candado, la otra se bloquea — el caso real: '
        'la vista previa del dashboard y la lista completa aprobando la misma '
        'solicitud al mismo tiempo', () async {
      final resultados = await Future.wait([
        _clasificar(() => aprobarSolicitud('sol-conc-1', {})),
        _clasificar(() => aprobarSolicitud('sol-conc-1', {})),
      ]);
      expect(resultados.where((r) => r == _Resultado.bloqueada).length, 1);
      expect(resultados.where((r) => r == _Resultado.intento).length, 1);
    });

    test('aprobarSolicitud y rechazarSolicitud sobre el MISMO docId también se '
        'bloquean entre sí — el caso real: tocar Aprobar y después Rechazar '
        'casi juntos, antes de que el primero termine', () async {
      final resultados = await Future.wait([
        _clasificar(() => aprobarSolicitud('sol-conc-2', {})),
        _clasificar(() => rechazarSolicitud('sol-conc-2', {}, 'motivo')),
      ]);
      expect(resultados.where((r) => r == _Resultado.bloqueada).length, 1,
          reason: 'una de las dos tiene que haberse bloqueado');
      expect(resultados.where((r) => r == _Resultado.intento).length, 1);
    });

    test('dos docId DISTINTOS no se bloquean entre sí — no es un candado '
        'global, cada solicitud tiene el suyo', () async {
      final resultados = await Future.wait([
        _clasificar(() => aprobarSolicitud('sol-conc-3', {})),
        _clasificar(() => aprobarSolicitud('sol-conc-4', {})),
      ]);
      expect(resultados.every((r) => r == _Resultado.intento), true,
          reason: 'las dos deberían haber podido intentarlo, ninguna bloqueada por la otra');
    });

    test('el candado se libera al terminar — una llamada POSTERIOR (no '
        'concurrente) al mismo docId no queda trabada para siempre', () async {
      await _clasificar(() => aprobarSolicitud('sol-conc-5', {}));
      final segunda = await _clasificar(() => aprobarSolicitud('sol-conc-5', {}));
      expect(segunda, _Resultado.intento,
          reason: 'si el candado no se liberó, esto se hubiera bloqueado para siempre');
    });
  });
}
