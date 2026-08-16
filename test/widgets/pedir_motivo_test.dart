import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/widgets/pedir_motivo.dart';

void main() {
  group('pedirMotivo() — el diálogo de texto libre (motivo de rechazo, nota '
      'de fallecido/regresado). Estaba escrito a mano 3 veces y las 3 '
      'liberaban el TextEditingController con .then() sobre el showDialog, '
      'que se completa ANTES de que el diálogo termine de cerrarse: el '
      'campo se desmontaba sobre un controller ya destruido y Flutter '
      'pintaba su pantalla roja de error. Hallazgo real de Eliza marcando '
      'un animal como Regresado', () {
    testWidgets('cerrar con Guardar/Confirmar NO deja ninguna excepción — es '
        'el bug exacto: el controller se destruía mientras el TextField '
        'seguía animándose hacia afuera', (tester) async {
      String? resultado;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  resultado = await pedirMotivo(ctx, titulo: 'Motivo');
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'se mudó');
      await tester.tap(find.text('Confirmar'));
      // pumpAndSettle corre la animación de cierre COMPLETA — que es
      // justamente cuando el TextField se desmontaba sobre el controller
      // destruido y saltaba la excepción.
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(resultado, 'se mudó');
    });

    testWidgets('Cancelar devuelve null, no un texto vacío — "cancelé" y '
        '"no puse motivo" son cosas distintas: la primera no debe cambiar '
        'nada', (tester) async {
      String? resultado = 'sin tocar';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  resultado = await pedirMotivo(ctx, titulo: 'Motivo');
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'algo escrito');
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(resultado, isNull);
    });

    testWidgets('el texto inicial viene precargado y se puede confirmar tal '
        'cual — es como se usa al rechazar una solicitud, con el mensaje '
        'sugerido ya escrito', (tester) async {
      String? resultado;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  resultado = await pedirMotivo(
                    ctx,
                    titulo: 'Mensaje de rechazo',
                    textoInicial: 'Gracias por tu interés 🐾',
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Gracias por tu interés 🐾'), findsOneWidget);

      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(resultado, 'Gracias por tu interés 🐾');
    });
  });
}
