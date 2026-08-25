import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/widgets/me_interesa_sheet.dart';

/// El panel de "¿cómo querés ayudar?" del feed.
///
/// **Por qué existe este archivo.** El panel ofrecía dos de las tres formas
/// de ayudar y le faltaba justo Adoptar: para adoptar desde el feed había
/// que entrar por "Ser hogar de paso" y recién en la pantalla siguiente
/// cambiar el botón. Eso no lo encontró ninguna prueba ni ninguna lectura
/// del código: se encontró usando la app a mano, una sola vez.
///
/// Un panel que se arma según el estado del animalito es exactamente lo que
/// una prueba de widget puede revisar sola, sin emulador y sin dispositivo.
void main() {
  Future<void> abrir(WidgetTester tester, String estado) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MeInteresaSheet(
            nombre: 'Pacolin',
            especie: 'Gato',
            edad: '2 años',
            ubicacion: 'Santiago',
            rescatistaId: 'refugio',
            rescatista: 'La Perla',
            rescateId: 'r1',
            tags: const [],
            estadoAdopcion: estado,
            creadoPor: 'albergue',
            tamano: 'Mediano',
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('las tres formas de ayudar', () {
    testWidgets('un animalito disponible ofrece LAS TRES', (tester) async {
      await abrir(tester, 'Rescatado');
      expect(find.text('Adoptar'), findsOneWidget);
      expect(find.text('Ser hogar de paso'), findsOneWidget);
      expect(find.text('Hacer una pregunta'), findsOneWidget);
    });

    testWidgets('y Adoptar va PRIMERO, que es la acción principal', (
      tester,
    ) async {
      await abrir(tester, 'Rescatado');
      final adoptar = tester.getTopLeft(find.text('Adoptar')).dy;
      final hogar = tester.getTopLeft(find.text('Ser hogar de paso')).dy;
      final pregunta = tester.getTopLeft(find.text('Hacer una pregunta')).dy;
      expect(adoptar, lessThan(hogar));
      expect(hogar, lessThan(pregunta));
    });

    // El matiz que la comparación escrita a mano escondía: quien ya lo tiene
    // en hogar de paso puede querer quedárselo, así que Adoptar sigue. Pero
    // ofrecerle otro hogar de paso encima no tiene sentido.
    testWidgets('ya en hogar de paso: se adopta, no se le da otro hogar', (
      tester,
    ) async {
      await abrir(tester, 'Hogar de paso');
      expect(find.text('Adoptar'), findsOneWidget);
      expect(find.text('Ser hogar de paso'), findsNothing);
      expect(find.text('Hacer una pregunta'), findsOneWidget);
    });

    testWidgets('regresado vuelve a ofrecer las tres', (tester) async {
      await abrir(tester, 'Regresado');
      expect(find.text('Adoptar'), findsOneWidget);
      expect(find.text('Ser hogar de paso'), findsOneWidget);
    });

    // Escribir siempre se puede: preguntar por un animalito que ya no está
    // disponible es legítimo, y es la única forma de enterarse de qué pasó.
    testWidgets('si ya no está disponible, solo queda preguntar', (
      tester,
    ) async {
      for (final estado in [
        'En proceso de adopción',
        'Adoptado',
        'Fallecido',
      ]) {
        await abrir(tester, estado);
        expect(find.text('Adoptar'), findsNothing, reason: estado);
        expect(find.text('Ser hogar de paso'), findsNothing, reason: estado);
        expect(find.text('Hacer una pregunta'), findsOneWidget, reason: estado);
      }
    });

    testWidgets('el título nombra al animalito', (tester) async {
      await abrir(tester, 'Rescatado');
      expect(find.text('¿Cómo querés ayudar a Pacolin?'), findsOneWidget);
    });
  });
}
