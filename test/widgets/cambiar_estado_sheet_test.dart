import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/widgets/cambiar_estado_sheet.dart';

/// Qué estados ofrece el desplegable de "Cambiar estado".
///
/// **El bug.** Ofrecía los 6 siempre, sin mirar de dónde venía el
/// animalito. Con eso se podía pasar de 'En proceso de adopción' directo a
/// 'Hogar de paso': la adopción quedaba a medias y el
/// `adoptanteIdEnProceso` del adoptante colgando de un hogar de paso que es
/// de otra persona. Hallazgo de Eliza en el APK109.
///
/// La forma correcta de terminar una adopción es RECHAZAR la solicitud, que
/// devuelve el animalito a 'Rescatado'; desde ahí sí se puede pedir hogar
/// de paso. No se inventa ninguna transición especial ni se borra el claim.
///
/// La regla no es nueva: es `sePuedeSerHogarDePaso`, la misma que ya usa el
/// panel "¿cómo querés ayudar?" del adoptante (me_interesa_sheet).
///
/// La hoja se puede montar sin Firebase: solo lo toca en los `onTap`, no al
/// construirse. Por eso esto puede ser un test de verdad y no una guarda
/// sobre el fuente.
void main() {
  Future<void> abrirCon(WidgetTester tester, String estadoActual) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CambiarEstadoSheet(
            docId: 'r1',
            estadoActual: estadoActual,
            nombre: 'Firulais',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('CambiarEstadoSheet — cuándo se ofrece "Hogar de paso"', () {
    testWidgets('desde Rescatado sí', (tester) async {
      await abrirCon(tester, 'Rescatado');
      expect(find.text('Hogar de paso'), findsOneWidget);
    });

    testWidgets('desde Regresado sí', (tester) async {
      await abrirCon(tester, 'Regresado');
      expect(find.text('Hogar de paso'), findsOneWidget);
    });

    // EL caso del bug.
    testWidgets('desde En proceso de adopción NO', (tester) async {
      await abrirCon(tester, 'En proceso de adopción');
      expect(
        find.text('Hogar de paso'),
        findsNothing,
        reason:
            'hay una adopción en curso: primero hay que rechazar la '
            'solicitud, que devuelve el animalito a Rescatado',
      );
    });

    // Lo que NO cambia: 'Adoptado' podía elegir hogar de paso y lo sigue
    // pudiendo. Se evaluó reutilizar sePuedeSerHogarDePaso (que también
    // diría que no acá) y se descartó justamente por esto: habría sido un
    // cambio de comportamiento que nadie pidió. Solo se bloquea el estado
    // que reportó Eliza.
    testWidgets('desde Adoptado se sigue pudiendo, como antes', (tester) async {
      await abrirCon(tester, 'Adoptado');
      expect(find.text('Hogar de paso'), findsOneWidget);
    });

    testWidgets('y desde Fallecido también, sin cambios', (tester) async {
      await abrirCon(tester, 'Fallecido');
      expect(find.text('Hogar de paso'), findsOneWidget);
    });

    // Y el resto de la hoja sigue igual: lo único que se saca es esa
    // opción, no se rompe el desplegable.
    testWidgets('los demás estados se siguen ofreciendo igual', (tester) async {
      await abrirCon(tester, 'En proceso de adopción');
      for (final estado in [
        'Rescatado',
        'En proceso de adopción',
        'Adoptado',
        'Regresado',
        'Fallecido',
      ]) {
        expect(find.text(estado), findsOneWidget, reason: estado);
      }
    });

    // Un animalito que YA está en hogar de paso tiene que ver su propio
    // estado marcado. La regla lo excluye (no tiene sentido ofrecerle otro
    // hogar de paso encima), pero esconderlo dejaría la hoja sin indicar
    // en qué estado está.
    testWidgets('el estado actual se muestra aunque la regla lo excluya', (
      tester,
    ) async {
      await abrirCon(tester, 'Hogar de paso');
      expect(find.text('Hogar de paso'), findsOneWidget);
    });

    // El camino que reemplaza a la transición directa: rechazar la
    // solicitud devuelve el animalito a 'Rescatado', y desde ahí la opción
    // vuelve a estar.
    testWidgets('después de rechazar la adopción, desde Rescatado vuelve a '
        'estar', (tester) async {
      await abrirCon(tester, 'En proceso de adopción');
      expect(find.text('Hogar de paso'), findsNothing);

      await abrirCon(tester, 'Rescatado');
      expect(find.text('Hogar de paso'), findsOneWidget);
    });
  });
}
