import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/data/firestore_resiliencia.dart';
import 'package:salva_patitas/theme.dart';
import 'package:salva_patitas/widgets/resultado_guardado_snackbar.dart';

Future<void> _mostrar(
  WidgetTester tester,
  ResultadoGuardado resultado, {
  String? exito,
  String? pendiente,
  String? fallo,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => mostrarResultadoGuardado(
              ctx,
              resultado,
              exito: exito,
              pendiente: pendiente ?? 'pendiente por defecto',
              fallo: fallo ?? 'falló por defecto',
            ),
            child: const Text('guardar'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('guardar'));
  await tester.pump();
}

void main() {
  group(
    'mostrarResultadoGuardado() — el switch de 3 ramas que se escribía a '
    'mano en 10 pantallas distintas (perfil de rescatista, adoptante, '
    'albergue, aliado, hogares de paso, subir servicio…), con 4 '
    'redacciones distintas para el mismo estado "todavía no confirmó".',
    () {
      testWidgets('confirmado con exito muestra ese mensaje en verde', (
        tester,
      ) async {
        await _mostrar(
          tester,
          ResultadoGuardado.confirmado,
          exito: 'Roles actualizados',
        );

        expect(find.text('Roles actualizados'), findsOneWidget);
        final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
        expect(snackBar.backgroundColor, msgExito);
      });

      testWidgets(
        'confirmado sin exito (default null) no muestra ningún SnackBar — '
        'el caso de togglear un switch o borrar una tarjeta, donde el '
        'cambio ya se ve solo en la lista',
        (tester) async {
          await _mostrar(tester, ResultadoGuardado.confirmado);

          expect(find.byType(SnackBar), findsNothing);
        },
      );

      testWidgets('siguePendiente muestra el texto de advertencia en naranja', (
        tester,
      ) async {
        await _mostrar(
          tester,
          ResultadoGuardado.siguePendiente,
          pendiente: 'Se va a eliminar solo apenas vuelva la señal.',
        );

        expect(
          find.text('Se va a eliminar solo apenas vuelva la señal.'),
          findsOneWidget,
        );
        final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
        expect(snackBar.backgroundColor, msgAdvertencia);
      });

      testWidgets('fallo muestra el texto de error en rojo', (tester) async {
        await _mostrar(
          tester,
          ResultadoGuardado.fallo,
          fallo: 'No se pudo eliminar. Revisá tu conexión e intentá de nuevo.',
        );

        expect(
          find.text(
            'No se pudo eliminar. Revisá tu conexión e intentá de nuevo.',
          ),
          findsOneWidget,
        );
        final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
        expect(snackBar.backgroundColor, msgError);
      });
    },
  );
}
