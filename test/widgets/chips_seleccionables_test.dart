import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/widgets/chips_seleccionables.dart';

Widget _envolver(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ChipsSeleccionables — la grilla de opciones (Wrap, nunca scroll '
      'horizontal oculto) que consolida las 3 copias sueltas que había en '
      'tipo_animal_screen.dart, subir_rescate_screen.dart y '
      'editar_rescate_screen.dart', () {
    testWidgets('muestra todas las opciones sin necesitar scroll — el bug '
        'real: antes una de las 3 copias las escondía detrás de un '
        'deslizamiento horizontal sin ninguna señal de que había más', (
      tester,
    ) async {
      String seleccion = 'Mediano';
      await tester.pumpWidget(
        _envolver(
          ChipsSeleccionables(
            opciones: const ['Pequeño', 'Mediano', 'Grande', 'Cualquiera'],
            seleccion: seleccion,
            onSeleccionar: (v) => seleccion = v,
          ),
        ),
      );

      for (final o in ['Pequeño', 'Mediano', 'Grande', 'Cualquiera']) {
        expect(find.text(o), findsOneWidget);
      }
    });

    testWidgets('tocar una opción distinta llama a onSeleccionar con ese '
        'valor', (tester) async {
      String? tocada;
      await tester.pumpWidget(
        _envolver(
          ChipsSeleccionables(
            opciones: const ['Cachorro', 'Adulto', 'Senior'],
            seleccion: 'Cachorro',
            onSeleccionar: (v) => tocada = v,
          ),
        ),
      );

      await tester.tap(find.text('Senior'));
      await tester.pump();

      expect(tocada, 'Senior');
    });

    testWidgets('un valor guardado que NO está en la lista se muestra igual, '
        'como una opción más y marcada — sin esto queda invisible: ningún '
        'chip seleccionado, parece que el dato se perdió, y tocar otra '
        'opción lo pisa sin que nadie note que había algo. Pasó de verdad '
        'con un animal publicado como "Herido" abierto en Editar, cuya '
        'lista no incluía ese estado', (tester) async {
      await tester.pumpWidget(
        _envolver(
          ChipsSeleccionables(
            opciones: const ['Sano', 'En tratamiento'],
            seleccion: 'Herido', // guardado por la otra pantalla
            onSeleccionar: (_) {},
          ),
        ),
      );

      expect(find.text('Herido'), findsOneWidget);
      expect(find.text('Sano'), findsOneWidget);
      expect(find.text('En tratamiento'), findsOneWidget);
    });

    testWidgets('una selección vacía no agrega ningún chip fantasma — un '
        'campo todavía sin elegir es normal, no un valor desconocido', (
      tester,
    ) async {
      await tester.pumpWidget(
        _envolver(
          ChipsSeleccionables(
            opciones: const ['Sí', 'No'],
            seleccion: '',
            onSeleccionar: (_) {},
          ),
        ),
      );

      expect(find.byType(GestureDetector), findsNWidgets(2));
    });

    testWidgets('un contenedor angosto no produce overflow — las opciones '
        'que no entran en la primera línea bajan solas a la siguiente', (
      tester,
    ) async {
      await tester.pumpWidget(
        _envolver(
          SizedBox(
            width: 180,
            child: ChipsSeleccionables(
              opciones: const ['Pequeño', 'Mediano', 'Grande', 'Cualquiera'],
              seleccion: 'Mediano',
              onSeleccionar: (_) {},
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
