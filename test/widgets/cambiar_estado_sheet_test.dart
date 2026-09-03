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
  Future<void> abrirCon(
    WidgetTester tester,
    String estadoActual, {
    String? adoptanteIdEnProceso,
    bool esAlbergue = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CambiarEstadoSheet(
            docId: 'r1',
            estadoActual: estadoActual,
            nombre: 'Firulais',
            adoptanteIdEnProceso: adoptanteIdEnProceso,
            esAlbergue: esAlbergue,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Toca la opción "Hogar de paso" y dice si apareció el formulario.
  ///
  /// El formulario (pedirHogarDePaso) se abre ANTES de tocar Firestore, así
  /// que este camino no necesita Firebase. El camino contrario sí llega a
  /// la escritura, pero _actualizarEstado atrapa su propio error y solo
  /// muestra un aviso: no se escapa nada.
  Future<bool> abreElFormulario(WidgetTester tester) async {
    await tester.tap(find.text('Hogar de paso'));
    await tester.pumpAndSettle();
    return find.text('Nombre de la persona').evaluate().isNotEmpty;
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

    // ── Cuándo se abre el formulario "¿Quién lo va a cuidar?" ─────────
    //
    // El desplegable sirve para CAMBIAR de estado. Elegir el estado en el
    // que el animalito ya está no es un cambio, así que no tiene que
    // preguntar nada.
    //
    // Antes dependía de si había un cuidador CON CUENTA: el que venía de
    // una solicitud aprobada no preguntaba, y el cargado a mano sí. Ese
    // segundo caso volvía a mostrar el formulario en blanco, y completarlo
    // pisaba nombre y fechas, reiniciaba los avisos y le sumaba otra ayuda
    // en la red al albergue. Hallazgo de Eliza.

    testWidgets('ya en Hogar de paso por una solicitud aprobada: no pregunta '
        'nada', (tester) async {
      await abrirCon(
        tester,
        'Hogar de paso',
        adoptanteIdEnProceso: 'una-persona-con-cuenta',
      );
      expect(await abreElFormulario(tester), isFalse);
    });

    // EL caso nuevo: mismo estado de origen, pero cargado a mano. Tiene que
    // dar lo MISMO que el de arriba.
    testWidgets('ya en Hogar de paso cargado a mano: tampoco', (tester) async {
      await abrirCon(tester, 'Hogar de paso');
      expect(
        await abreElFormulario(tester),
        isFalse,
        reason:
            'volvió a preguntar quién lo cuida y pisaría los datos que '
            'ya tiene',
      );
    });

    // Y lo mismo del lado del albergue, que además le sumaría otra ayuda a
    // su red si el formulario se abriera.
    testWidgets('ni siquiera como albergue', (tester) async {
      await abrirCon(tester, 'Hogar de paso', esAlbergue: true);
      expect(await abreElFormulario(tester), isFalse);
    });

    // Lo que NO puede romperse: empezar un hogar de paso sigue preguntando.
    testWidgets('desde Rescatado sí pregunta', (tester) async {
      await abrirCon(tester, 'Rescatado');
      expect(await abreElFormulario(tester), isTrue);
    });

    testWidgets('desde Regresado sí pregunta', (tester) async {
      await abrirCon(tester, 'Regresado');
      expect(await abreElFormulario(tester), isTrue);
    });

    // 'Adoptado' no cambia, y lo que hace depende de si quedó un cuidador
    // con cuenta: `cambiarEstadoAdopcion` solo limpia `adoptanteIdEnProceso`
    // para Rescatado, Regresado y Fallecido, asi que un animalito adoptado
    // normalmente lo conserva. Los dos casos, tal como estaban.
    testWidgets('desde Adoptado sin cuidador con cuenta: pregunta, igual que '
        'antes', (tester) async {
      await abrirCon(tester, 'Adoptado');
      expect(await abreElFormulario(tester), isTrue);
    });

    testWidgets('desde Adoptado CON cuidador con cuenta: no pregunta, igual '
        'que antes', (tester) async {
      await abrirCon(tester, 'Adoptado', adoptanteIdEnProceso: 'alguien');
      expect(await abreElFormulario(tester), isFalse);
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
