import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/widgets/campo_pais_telefono.dart';

Widget _envolver(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
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
        'indicativo nuevo, conservando el número local ya escrito', (
      tester,
    ) async {
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

  group(
    'banderaPais() — la bandera junto a la ciudad en la tarjeta del feed. '
    'Pedido real de Eliza: "Córdoba" sola no distingue Argentina de España, '
    'y una ciudad mal geocodificada solo se notaba por una distancia rara',
    () {
      test('convierte el código ISO en su bandera', () {
        expect(banderaPais('AR'), '🇦🇷');
        expect(banderaPais('ES'), '🇪🇸');
        expect(banderaPais('CO'), '🇨🇴');
        expect(banderaPais('DE'), '🇩🇪');
      });

      test(
        'funciona para CUALQUIER país, no solo los de la lista de teléfonos — '
        'se calcula desde el código, no se busca en una tabla que haya que '
        'mantener',
        () {
          expect(banderaPais('JP'), '🇯🇵');
          expect(banderaPais('NZ'), '🇳🇿');
        },
      );

      test(
        'tolera minúsculas y espacios (los datos vienen de un geocoder, no de '
        'un campo controlado)',
        () {
          expect(banderaPais('ar'), '🇦🇷');
          expect(banderaPais(' Ar '), '🇦🇷');
        },
      );

      test(
        'vacío si el dato no sirve — un animal viejo sin paisCodigo tiene que '
        'verse igual que antes, no con un cuadradito roto al lado',
        () {
          expect(banderaPais(null), '');
          expect(banderaPais(''), '');
          expect(banderaPais('A'), '');
          expect(banderaPais('ARG'), '');
          expect(banderaPais('12'), '');
          expect(banderaPais('A1'), '');
        },
      );
    },
  );
}
