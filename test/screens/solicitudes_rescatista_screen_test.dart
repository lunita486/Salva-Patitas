import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/screens/solicitudes_rescatista_screen.dart';

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
  group(
    'aprobarSolicitud/rechazarSolicitud — candado compartido entre pantallas',
    () {
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

      test(
        'aprobarSolicitud y rechazarSolicitud sobre el MISMO docId también se '
        'bloquean entre sí — el caso real: tocar Aprobar y después Rechazar '
        'casi juntos, antes de que el primero termine',
        () async {
          final resultados = await Future.wait([
            _clasificar(() => aprobarSolicitud('sol-conc-2', {})),
            _clasificar(() => rechazarSolicitud('sol-conc-2', {}, 'motivo')),
          ]);
          expect(
            resultados.where((r) => r == _Resultado.bloqueada).length,
            1,
            reason: 'una de las dos tiene que haberse bloqueado',
          );
          expect(resultados.where((r) => r == _Resultado.intento).length, 1);
        },
      );

      test('dos docId DISTINTOS no se bloquean entre sí — no es un candado '
          'global, cada solicitud tiene el suyo', () async {
        final resultados = await Future.wait([
          _clasificar(() => aprobarSolicitud('sol-conc-3', {})),
          _clasificar(() => aprobarSolicitud('sol-conc-4', {})),
        ]);
        expect(
          resultados.every((r) => r == _Resultado.intento),
          true,
          reason:
              'las dos deberían haber podido intentarlo, ninguna bloqueada por la otra',
        );
      });

      test('el candado se libera al terminar — una llamada POSTERIOR (no '
          'concurrente) al mismo docId no queda trabada para siempre', () async {
        await _clasificar(() => aprobarSolicitud('sol-conc-5', {}));
        final segunda = await _clasificar(
          () => aprobarSolicitud('sol-conc-5', {}),
        );
        expect(
          segunda,
          _Resultado.intento,
          reason:
              'si el candado no se liberó, esto se hubiera bloqueado para siempre',
        );
      });
    },
  );

  // ── Quien puede tocar "Contactar" ────────────────────────────────────
  //
  // contactarPersonaEnProceso() solo sabe abrir el chat de alguien que
  // TIENE cuenta: `adoptanteIdEnProceso`, que se escribe unicamente al
  // aprobar una solicitud. Un hogar de paso cargado a mano no lo tiene,
  // porque esa persona ni siquiera usa la app.
  //
  // Sin ese dato, la funcion llama a buscarDeAnimal sin rescateId ni
  // adoptanteId, y cae en su busqueda legada POR NOMBRE acotada solo al
  // dueno. Con dos animalitos del mismo dueno llamados igual (o dos sin
  // nombre, que la UI muestra a los dos como "Sin nombre") devuelve uno
  // cualquiera: Eliza toco Contactar en un hogar de paso manual y se le
  // abrio el chat de otro animalito, uno ya fallecido. APK108.
  //
  // Este test NO copia la condicion: lee las pantallas reales y recorre
  // TODAS las llamadas, para que una cuarta pantalla que agregue el boton
  // sin la guarda rompa aca en vez de repetir el bug.
  group('todas las pantallas que ofrecen "Contactar" exigen que haya alguien '
      'con cuenta a quien contactar', () {
    /// Los archivos de lib/ que LLAMAN a la funcion (no el que la define).
    final llamadores = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => (ruta: f.path, fuente: f.readAsStringSync()))
        .where(
          (a) =>
              a.fuente.contains('contactarPersonaEnProceso(') &&
              !a.fuente.contains('Future<void> contactarPersonaEnProceso('),
        )
        .toList();

    test('hay pantallas que lo ofrecen, y son las que esperamos', () {
      expect(llamadores, isNotEmpty, reason: 'nadie ofrece Contactar');
      expect(
        llamadores.map((a) => a.ruta.split('/').last).toSet(),
        {
          'home_screen.dart',
          'albergue_home_screen.dart',
          'mis_rescates_screen.dart',
        },
        reason:
            'apareció (o desapareció) una pantalla con este botón: '
            'revisá que la nueva pida adoptanteIdEnProceso',
      );
    });

    test('cada llamada está guardada por adoptanteIdEnProceso no vacío', () {
      for (final a in llamadores) {
        for (final m in 'contactarPersonaEnProceso('.allMatches(a.fuente)) {
          // La guarda siempre va ANTES de la llamada: un `if` de early
          // return, un `if` de lista de widgets, o la condicion de un
          // ternario.
          final antes = a.fuente.substring(
            m.start < 900 ? 0 : m.start - 900,
            m.start,
          );
          expect(
            antes.contains('adoptanteIdEnProceso') &&
                (antes.contains('isNotEmpty') || antes.contains('isEmpty')),
            isTrue,
            reason:
                '${a.ruta} ofrece Contactar sin comprobar que exista alguien '
                'con cuenta: para un hogar de paso manual abre el chat de '
                'otro animalito',
          );
        }
      }
    });
  });
}
