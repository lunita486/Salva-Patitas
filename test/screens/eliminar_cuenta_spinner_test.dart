import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// El spinner de "Eliminando tu cuenta…" tiene que cerrarse SIEMPRE, incluso
/// cuando la pantalla que lo abrió deja de existir mientras espera.
///
/// **El bug.** El borrado del servidor incluye `usuarios/{uid}`. Esa baja le
/// llega al cliente por el stream que escucha AuthWrapper, que cambia de
/// pantalla sola — o sea que la pantalla desde la que se tocó "Eliminar mi
/// cuenta" se desmonta mientras seguimos esperando la respuesta. Cada rama
/// del flujo hacía `if (!context.mounted) return;` y se iba sin cerrar el
/// spinner, que además no se puede descartar (`barrierDismissible: false` +
/// `PopScope(canPop: false)`). Quedaba tapando la pantalla nueva para
/// siempre; la única salida era matar la app.
///
/// Lo reportó Eliza borrando un aliado: "sale eliminando tu cuenta y no pasa
/// nada, se queda ahí... y al fondo se ve Hola, Carmen, ¿cómo vas a entrar?".
/// Ese fondo era la pantalla nueva: la prueba de que el borrado avanzó y de
/// que quien esperaba la respuesta ya no existía.
///
/// **Qué prueba esto y qué no.** No corre el flujo real (necesita Firebase).
/// Reproduce la ESTRUCTURA que lo rompía: abrir un diálogo modal, cambiar de
/// pantalla mientras se espera, y después intentar cerrarlo. La diferencia
/// entre cerrarlo con el contexto de origen (lo que había) y con el navegador
/// raíz (lo que hay ahora) es exactamente lo que separa el bug del arreglo.
void main() {
  /// Cambia la pantalla de abajo, como hace AuthWrapper al desaparecer el
  /// documento de usuario.
  Future<void> montar(WidgetTester tester, ValueNotifier<bool> borrada) =>
      tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: borrada,
            // Los dos lados son de tipos DISTINTOS a propósito: si fueran
            // el mismo widget, Flutter reusaría el mismo Element y no se
            // desmontaría nada, que es justo lo que este test necesita
            // reproducir. En la app pasa solo: aliado_home_screen y
            // seleccion_rol_screen no se parecen en nada.
            builder: (_, yaNoExiste, __) => yaNoExiste
                ? const Center(child: Text('¿Cómo vas a entrar?'))
                : const Scaffold(body: Text('Perfil del aliado')),
          ),
        ),
      );

  testWidgets(
    'cerrar con el contexto de la pantalla vieja NO alcanza (el bug)',
    (tester) async {
      final borrada = ValueNotifier(false);
      await montar(tester, borrada);
      final ctxViejo = tester.element(find.text('Perfil del aliado'));

      showDialog<void>(
        context: ctxViejo,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(content: Text('Eliminando tu cuenta…')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Eliminando tu cuenta…'), findsOneWidget);

      // Llega la baja del documento y la pantalla de abajo cambia.
      borrada.value = true;
      await tester.pumpAndSettle();

      // Así se veía: el spinner encima de la pantalla nueva.
      expect(find.text('Eliminando tu cuenta…'), findsOneWidget);
      expect(find.text('¿Cómo vas a entrar?'), findsOneWidget);

      // Y el guard que dejaba el spinner abierto para siempre.
      expect(
        ctxViejo.mounted,
        isFalse,
        reason: 'por esto `if (!context.mounted) return;` se iba sin cerrarlo',
      );
    },
  );

  testWidgets('con el navegador raíz guardado antes, sí cierra (el arreglo)', (
    tester,
  ) async {
    final borrada = ValueNotifier(false);
    await montar(tester, borrada);
    final ctxViejo = tester.element(find.text('Perfil del aliado'));

    // Lo que hace ahora el flujo: se queda con el navegador ANTES de esperar.
    final navegador = Navigator.of(ctxViejo, rootNavigator: true);

    showDialog<void>(
      context: ctxViejo,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(content: Text('Eliminando tu cuenta…')),
    );
    await tester.pumpAndSettle();

    borrada.value = true;
    await tester.pumpAndSettle();
    expect(ctxViejo.mounted, isFalse, reason: 'la pantalla vieja ya no está');

    navegador.pop();
    await tester.pumpAndSettle();

    expect(
      find.text('Eliminando tu cuenta…'),
      findsNothing,
      reason: 'el navegador raíz sobrevive al cambio de pantalla',
    );
    expect(find.text('¿Cómo vas a entrar?'), findsOneWidget);
  });
}
