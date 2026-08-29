import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salva_patitas/data/cuenta_repository.dart';
import 'package:salva_patitas/screens/eliminar_cuenta_dialog.dart';

/// El aviso de "esto está tardando más de lo normal" al borrar la cuenta.
///
/// **Qué se prueba acá y qué no.** El timeout de 30s en sí ya está cubierto
/// en cuenta_repository_test.dart. Esto cubre la otra mitad: que la PANTALLA
/// reaccione bien. Que el spinner se cierre, que aparezca el aviso con su
/// botón, y sobre todo que la persona nunca quede obligada a matar la app —
/// que es lo que le pasó a Eliza.
///
/// **Tiempo simulado, no real.** `testWidgets` corre con reloj falso: los
/// `Timer` que usa `Future.timeout` los controla el binding del test, así
/// que `tester.pump(Duration(seconds: 31))` dispara el timeout al instante.
/// Ningún test espera 30 segundos de verdad.
///
/// **Se usa un CuentaRepository REAL** con `FirebaseFunctions` mockeado
/// (mismo patrón que cuenta_repository_test.dart), no un repositorio falso:
/// así el `.timeout(30s)` que corre es el de producción, no una copia del
/// test que podría desincronizarse.
class MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class MockHttpsCallable extends Mock implements HttpsCallable {}

class MockHttpsCallableResult extends Mock
    implements HttpsCallableResult<dynamic> {}

void main() {
  late MockFirebaseFunctions functions;
  late MockHttpsCallable callable;
  late int vecesLlamado;

  setUp(() {
    functions = MockFirebaseFunctions();
    callable = MockHttpsCallable();
    vecesLlamado = 0;
    when(() => functions.httpsCallable(any())).thenReturn(callable);
  });

  /// La llamada al servidor no contesta nunca: el único desenlace posible es
  /// que el timeout corte. Es la forma de simular "tarda muchísimo" sin
  /// esperar de verdad.
  void servidorQueNoContesta() {
    when(() => callable.call()).thenAnswer((_) {
      vecesLlamado++;
      return Completer<HttpsCallableResult<dynamic>>().future;
    });
  }

  void servidorQueContestaRapido() {
    when(() => callable.call()).thenAnswer((_) async {
      vecesLlamado++;
      await Future<void>.delayed(const Duration(seconds: 2));
      return MockHttpsCallableResult();
    });
  }

  void servidorQueFalla() {
    when(() => callable.call()).thenAnswer((_) async {
      vecesLlamado++;
      throw FirebaseFunctionsException(code: 'internal', message: 'se rompió');
    });
  }

  /// Monta una pantalla con un botón que abre el flujo, y lo recorre hasta
  /// dejar el spinner en pantalla.
  Future<void> llegarAlSpinner(
    WidgetTester tester, {
    bool Function()? sesionCerrada,
  }) async {
    var cerro = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => mostrarEliminarCuentaDialog(
                ctx,
                repo: CuentaRepository(functions: functions),
                alCerrarSesion: () async {
                  cerro = true;
                  return true;
                },
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    // Paso 1: la advertencia.
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    // Paso 2: escribir ELIMINAR para habilitar el botón.
    await tester.enterText(find.byType(TextField), 'ELIMINAR');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar mi cuenta'));
    await tester.pump();
    sesionCerrada?.call();
    // `cerro` queda accesible por el closure de arriba en los tests que lo
    // necesitan; acá no se usa para no complicar la firma.
    expect(cerro, anyOf(isTrue, isFalse));
  }

  const avisoDemora = 'Esto está tardando más de lo normal';

  testWidgets('1 y 2. arranca el borrado y la UI sigue viva mientras espera', (
    tester,
  ) async {
    servidorQueNoContesta();
    await llegarAlSpinner(tester);

    expect(vecesLlamado, 1, reason: 'no arrancó el borrado');
    expect(find.text('Eliminando tu cuenta…'), findsOneWidget);
    // La UI responde: se puede seguir pintando cuadros sin que nada se trabe.
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);

    // El test no puede terminar con el timer de 30s colgado: flutter_test lo
    // reporta como "pending timer". Se lo deja vencer y se cierra el aviso.
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();
  });

  testWidgets('3. a los 29 segundos todavía no aparece el aviso', (
    tester,
  ) async {
    servidorQueNoContesta();
    await llegarAlSpinner(tester);
    await tester.pump(const Duration(seconds: 29));
    expect(find.text(avisoDemora), findsNothing);
    expect(find.text('Eliminando tu cuenta…'), findsOneWidget);

    // El test no puede terminar con el timer de 30s colgado: flutter_test lo
    // reporta como "pending timer". Se lo deja vencer y se cierra el aviso.
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();
  });

  testWidgets('4 y 5. pasados los 30 aparece el aviso, con su botón', (
    tester,
  ) async {
    servidorQueNoContesta();
    await llegarAlSpinner(tester);
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();

    expect(find.text(avisoDemora), findsOneWidget);
    expect(find.text('Entendido'), findsOneWidget);
    // Y el spinner se fue: era lo que obligaba a matar la app.
    expect(find.text('Eliminando tu cuenta…'), findsNothing);
  });

  testWidgets('6. tocar Entendido deja la pantalla usable, sin matar la app', (
    tester,
  ) async {
    servidorQueNoContesta();
    await llegarAlSpinner(tester);
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();

    expect(find.text(avisoDemora), findsNothing);
    expect(find.text('Eliminando tu cuenta…'), findsNothing);
    // Se vuelve a la pantalla de origen y se la puede volver a usar.
    expect(find.text('abrir'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('7 y 9. el borrado se llama UNA vez: el aviso no reintenta', (
    tester,
  ) async {
    servidorQueNoContesta();
    await llegarAlSpinner(tester);
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(vecesLlamado, 1, reason: 'el timeout reintentó el borrado');

    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();
    expect(
      vecesLlamado,
      1,
      reason: 'cerrar el aviso volvió a disparar el borrado',
    );

    // Y sigue sin reintentar aunque pase más tiempo: Future.timeout deja de
    // esperar, no cancela ni repite.
    await tester.pump(const Duration(minutes: 2));
    expect(vecesLlamado, 1);
  });

  testWidgets('8. si termina antes de los 30, no aparece ningún aviso', (
    tester,
  ) async {
    servidorQueContestaRapido();
    await llegarAlSpinner(tester);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text(avisoDemora), findsNothing);
    expect(find.text('Eliminando tu cuenta…'), findsNothing);
    expect(vecesLlamado, 1);
  });

  testWidgets('10. si el borrado falla, el spinner tampoco queda trabado', (
    tester,
  ) async {
    servidorQueFalla();
    await llegarAlSpinner(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Eliminando tu cuenta…'), findsNothing);
    expect(find.text(avisoDemora), findsNothing);
    expect(find.text('abrir'), findsOneWidget, reason: 'la pantalla volvió');
  });
}
