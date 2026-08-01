import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patitas_medellin/theme.dart';

Widget _envolver(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('whatsappUrl()', () {
    test('vacío o solo espacios da null', () {
      expect(whatsappUrl(''), isNull);
      expect(whatsappUrl('   '), isNull);
    });

    test('celular colombiano de 10 dígitos sin +57: se le antepone 57', () {
      expect(whatsappUrl('300 123 4567'), 'https://wa.me/573001234567');
    });

    test('fijo colombiano de 10 dígitos (prefijo 60, ej. un fijo de '
        'Medellín) sin +57: también se le antepone 57 — el bug real: antes '
        'solo se cubría el caso celular, así que un fijo tecleado tal como '
        'lo sugiere el propio campo armaba un link roto', () {
      expect(whatsappUrl('604 444 4444'), 'https://wa.me/576044444444');
    });

    test('ya viene con un indicativo (formato que arma CampoTelefono, o '
        'alguien que ya había puesto el suyo a mano): se usa tal cual, sin '
        'inventarle un 57 que no le corresponde', () {
      expect(whatsappUrl('+52 55 1234 5678'), 'https://wa.me/525512345678');
    });

    test('tolera espacios, guiones y paréntesis sueltos', () {
      expect(whatsappUrl('(300) 123-4567'), 'https://wa.me/573001234567');
    });

    // Regresión de esta misma sesión: un celular cubano (indicativo 53 +
    // 8 dígitos) o un fijo panameño (indicativo 507 + 7 dígitos) TAMBIÉN
    // dan 10 dígitos en total — la adivinanza de "10 dígitos sin + =
    // colombiano" los agarraba igual que a un número viejo sin país,
    // aunque la persona hubiera elegido bien su país en CampoTelefono.
    test('un celular cubano con indicativo (53 + 8 dígitos = 10 en total) '
        'NO se confunde con un número colombiano sin indicativo', () {
      expect(whatsappUrl('+53 12345678'), 'https://wa.me/5312345678');
    });

    test('un fijo panameño con indicativo (507 + 7 dígitos = 10 en total) '
        'NO se confunde con un número colombiano sin indicativo', () {
      expect(whatsappUrl('+507 1234567'), 'https://wa.me/5071234567');
    });
  });

  group('partirTelefono()', () {
    test('sin "+" adelante: asume Colombia y deja el texto tal cual — '
        'mismo comportamiento que tenía el campo antes de este selector, '
        'para no desordenar lo que alguien ya había guardado', () {
      final r = partirTelefono('300 123 4567');
      expect(r.pais.nombre, 'Colombia');
      expect(r.local, '300 123 4567');
    });

    test('vacío: también asume Colombia, con el local vacío', () {
      final r = partirTelefono('');
      expect(r.pais.nombre, 'Colombia');
      expect(r.local, '');
    });

    test('con "+" y un indicativo reconocido: separa el país correcto y '
        'deja solo los dígitos locales', () {
      final r = partirTelefono('+52 55 1234 5678');
      expect(r.pais.nombre, 'México');
      expect(r.local, '5512345678');
    });

    test('con "+" pero un indicativo que no está en la lista: cae a '
        'Colombia con el texto completo, no explota', () {
      final r = partirTelefono('+81 90 1234 5678');
      expect(r.pais.nombre, 'Colombia');
    });
  });

  group('CampoTelefono', () {
    testWidgets('vacío por defecto: escribir un número arma "+57 <numero>" '
        '— Colombia es el país por defecto', (tester) async {
      final ctl = TextEditingController();
      await tester.pumpWidget(_envolver(CampoTelefono(controller: ctl)));

      await tester.enterText(find.byType(TextField), '300 123 4567');
      await tester.pump();

      expect(ctl.text, '+57 300 123 4567');
    });

    testWidgets('si el controlador ya trae un número con indicativo al '
        'momento de armar el widget, muestra el país y el número local '
        'correctos', (tester) async {
      final ctl = TextEditingController(text: '+52 55 1234 5678');
      await tester.pumpWidget(_envolver(CampoTelefono(controller: ctl)));

      expect(find.text('🇲🇽 +52'), findsOneWidget);
      expect(find.widgetWithText(TextField, '5512345678'), findsOneWidget);
      // No reescribe nada que la persona no tocó.
      expect(ctl.text, '+52 55 1234 5678');
    });

    testWidgets('si el controlador se llena TARDE (el caso real: '
        '_cargarDatosExistentes() de las pantallas de perfil llega después '
        'de que este widget ya se armó con el controlador vacío), el '
        'campo se actualiza solo — sin esto, un teléfono ya guardado se '
        'vería vacío al abrir la pantalla', (tester) async {
      final ctl = TextEditingController();
      await tester.pumpWidget(_envolver(CampoTelefono(controller: ctl)));
      expect(find.widgetWithText(TextField, '5512345678'), findsNothing);

      ctl.text = '+52 55 1234 5678';
      await tester.pump();

      expect(find.text('🇲🇽 +52'), findsOneWidget);
      expect(find.widgetWithText(TextField, '5512345678'), findsOneWidget);
    });

    testWidgets('cambiar el país en el desplegable rearma el número con el '
        'indicativo nuevo, conservando el número local ya escrito', (tester) async {
      final ctl = TextEditingController();
      await tester.pumpWidget(_envolver(CampoTelefono(controller: ctl)));
      await tester.enterText(find.byType(TextField), '300 123 4567');
      await tester.pump();
      expect(ctl.text, '+57 300 123 4567');

      await tester.tap(find.byType(DropdownButton<Pais>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('🇲🇽 México  +52').last);
      await tester.pumpAndSettle();

      expect(ctl.text, '+52 300 123 4567');
    });

    testWidgets('borrar el número local deja el controlador vacío, no '
        '"+57 " colgado — el campo sigue siendo opcional', (tester) async {
      final ctl = TextEditingController();
      await tester.pumpWidget(_envolver(CampoTelefono(controller: ctl)));
      await tester.enterText(find.byType(TextField), '300 123 4567');
      await tester.pump();
      expect(ctl.text, isNotEmpty);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      expect(ctl.text, '');
    });
  });
}
