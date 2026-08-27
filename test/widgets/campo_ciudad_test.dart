import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/widgets/campo_ciudad.dart';

/// El campo de ciudad de toda la app.
///
/// **Por qué existe este archivo.** Había DOS versiones con reglas
/// distintas: esta (texto editable + ícono de GPS) para los perfiles, y
/// otra dentro de publicar un animalito que SOLO detectaba — no se podía
/// escribir nada. La idea era que un rescate se publica desde donde está
/// el animal, así que el GPS alcanzaba.
///
/// No alcanza. En Medellín el mapa devuelve el barrio ("Los Olivos") en vez
/// de la ciudad, y quien publicaba quedaba atrapada con ese nombre, por el
/// que nadie va a buscar, hasta ir a editar. Hallazgo real de Eliza.
///
/// Ahora las cuatro pantallas usan este widget. Estas pruebas fijan lo que
/// no puede volver a perderse: que se pueda escribir Y detectar.
void main() {
  Future<void> montar(
    WidgetTester tester,
    TextEditingController ctl, {
    CampoCiudadControlador? controlador,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CampoCiudad(
          controller: ctl,
          hint: 'ej. Laureles',
          controlador: controlador,
        ),
      ),
    ),
  );

  testWidgets('se puede ESCRIBIR la ciudad a mano', (tester) async {
    final ctl = TextEditingController();
    await montar(tester, ctl);

    await tester.enterText(find.byType(TextField), 'Medellín');
    expect(ctl.text, 'Medellín');
  });

  testWidgets('y además está el botón para detectarla por GPS', (
    tester,
  ) async {
    await montar(tester, TextEditingController());
    expect(find.byType(IconButton), findsOneWidget);
  });

  testWidgets('lo que ya estaba escrito se muestra, no se pisa', (
    tester,
  ) async {
    final ctl = TextEditingController(text: 'Los Olivos');
    await montar(tester, ctl);
    expect(find.text('Los Olivos'), findsOneWidget);
  });

  // El controlador es lo que dejó que las pantallas de animalitos borraran
  // su copia de la detección: publicar la dispara sola al abrir, y al
  // volver de los Ajustes del teléfono.
  group('CampoCiudadControlador', () {
    test('sin campo montado, pedir detectar no revienta', () {
      expect(() => CampoCiudadControlador().detectar(), returnsNormally);
    });

    test('arranca sin ninguna detección en curso', () {
      expect(CampoCiudadControlador().detectando, isFalse);
    });

    testWidgets('al desmontarse deja de responder', (tester) async {
      final c = CampoCiudadControlador();
      await montar(tester, TextEditingController(), controlador: c);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(() => c.detectar(), returnsNormally);
    });
  });
}
