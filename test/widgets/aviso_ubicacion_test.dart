import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/widgets/aviso_ubicacion.dart';

Future<void> _mostrar(
  WidgetTester tester, {
  Future<bool> Function()? accionAjustes,
  VoidCallback? antesDeAbrirAjustes,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => avisarErrorUbicacion(
              ctx,
              'Permiso de ubicación bloqueado.',
              accionAjustes: accionAjustes,
              antesDeAbrirAjustes: antesDeAbrirAjustes,
            ),
            child: const Text('avisar'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('avisar'));
  await tester.pump();
}

void main() {
  group(
    'avisarErrorUbicacion() — el aviso de GPS apagado/permiso bloqueado, '
    'compartido entre subir_rescate_screen.dart, editar_rescate_screen.dart '
    'y campo_ciudad.dart (antes escrito a mano 3 veces).',
    () {
      testWidgets(
        'usa SnackBarBehavior.floating, no el fixed por default — con '
        'fixed, el SnackBar (más alto cuando el texto y "Abrir Ajustes" no '
        'entran en una sola línea) quedaba pegado al borde inferior y '
        'tapaba campos reales del formulario de abajo. Hallazgo real de '
        'Eliza en "Subir un rescate": "es tan grande el mensaje que tapa '
        'la opción"',
        (tester) async {
          await _mostrar(tester, accionAjustes: () async => true);

          final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
          expect(snackBar.behavior, SnackBarBehavior.floating);
        },
      );

      testWidgets(
        'sin accionAjustes no muestra ningún botón — el caso de '
        '"permisoDenegado", donde un botón a Ajustes no tiene sentido '
        '(la persona recién dijo que no)',
        (tester) async {
          await _mostrar(tester, accionAjustes: null);

          final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
          expect(snackBar.action, isNull);
        },
      );

      testWidgets(
        'con accionAjustes, tocar el botón llama a antesDeAbrirAjustes '
        'ANTES de abrir Ajustes — es lo que habilita el reintento '
        'automático al volver (ReintentoUbicacionTrasAjustes)',
        (tester) async {
          final orden = <String>[];
          await _mostrar(
            tester,
            antesDeAbrirAjustes: () => orden.add('marcado'),
            accionAjustes: () async {
              orden.add('ajustes');
              return true;
            },
          );
          final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
          snackBar.action!.onPressed();

          expect(orden, ['marcado', 'ajustes']);
        },
      );
    },
  );
}
