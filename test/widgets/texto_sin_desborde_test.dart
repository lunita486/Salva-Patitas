import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/widgets/texto_sin_desborde.dart';

Widget _envolver(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('TextoSinDesborde — nombre + algo al lado (puntito de "en línea", '
      'ícono) sin desbordarse. Bug real: un nombre largo empujaba ese algo '
      'fuera de la pantalla, encontrado por separado en el chat y en el '
      'panel del aliado ("Veterinario Huellitas...")', () {
    testWidgets('un nombre corto se muestra entero, junto al indicador', (
      tester,
    ) async {
      await tester.pumpWidget(
        _envolver(
          SizedBox(
            width: 300,
            child: TextoSinDesborde(
              texto: 'Ana',
              style: const TextStyle(fontSize: 16),
              despues: const Icon(Icons.circle, size: 8, key: Key('punto')),
            ),
          ),
        ),
      );

      expect(find.text('Ana'), findsOneWidget);
      expect(find.byKey(const Key('punto')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un nombre tan largo que no entra en el ancho disponible NO '
        'desborda (no tira "RenderFlex overflowed") — el caso real que '
        'rompía el panel del aliado', (tester) async {
      await tester.pumpWidget(
        _envolver(
          SizedBox(
            width: 200,
            child: TextoSinDesborde(
              texto:
                  'Veterinario Huellitas Prueba Con Un Nombre Larguísimo '
                  'Que Antes Desbordaba La Pantalla Por Más De Mil Píxeles',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              despues: const Icon(Icons.circle, size: 10, key: Key('punto')),
            ),
          ),
        ),
      );

      // Con Flexible + ellipsis, el layout no lanza ningún error — antes
      // (Row + Text suelto) esto tiraba una excepción de overflow en el
      // momento de construir el widget.
      expect(tester.takeException(), isNull);
      // El indicador se sigue viendo: no quedó empujado fuera de la
      // pantalla como en el bug original.
      expect(find.byKey(const Key('punto')), findsOneWidget);
    });

    testWidgets('sin indicador, solo se muestra el nombre — el indicador es '
        'opcional', (tester) async {
      await tester.pumpWidget(
        _envolver(
          const TextoSinDesborde(
            texto: 'Solo el nombre',
            style: TextStyle(fontSize: 16),
          ),
        ),
      );

      expect(find.text('Solo el nombre'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
