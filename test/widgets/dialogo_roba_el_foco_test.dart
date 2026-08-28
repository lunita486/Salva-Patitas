import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// ¿Abrir un diálogo le quita el foco al campo de texto que estaba abajo?
///
/// Es la hipótesis del bucle que reportó Eliza al editar la ubicación de un
/// animalito: elegía la ciudad, veía "Tocá Guardar para confirmar", tocaba
/// Guardar y le volvía a salir "¿Cuál es tu ciudad?". Sin fin.
///
/// Importa porque editar_rescate_screen.dart tiene DOS caminos que resuelven
/// la ciudad y no se conocen entre sí:
///
///   · `_guardar()`, cuando se toca Guardar con la ciudad sin confirmar;
///   · `_resolverCiudadAlSalir()`, colgado del FocusNode del campo.
///
/// Si abrir el diálogo del primero apaga el foco, dispara al segundo, y
/// quedan dos diálogos pidiendo lo mismo, uno encima del otro. Contestás uno
/// y aparece el otro.
void main() {
  testWidgets('abrir un diálogo dispara el listener de foco del campo', (
    tester,
  ) async {
    final foco = FocusNode();
    var vecesQuePerdioElFoco = 0;
    foco.addListener(() {
      if (!foco.hasFocus) vecesQuePerdioElFoco++;
    });

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return TextField(focusNode: foco);
            },
          ),
        ),
      ),
    );

    foco.requestFocus();
    await tester.pump();
    expect(foco.hasFocus, isTrue, reason: 'el campo arranca con el foco');
    vecesQuePerdioElFoco = 0;

    // Lo mismo que hace _guardar(): abrir el diálogo de confirmar la ciudad.
    showDialog<void>(
      context: ctx,
      builder: (_) => const AlertDialog(title: Text('¿Cuál es tu ciudad?')),
    );
    await tester.pumpAndSettle();

    expect(
      vecesQuePerdioElFoco,
      greaterThan(0),
      reason:
          'si esto es 0 la hipótesis es falsa; si es >0, abrir el diálogo '
          'dispara _resolverCiudadAlSalir() y se abre un SEGUNDO diálogo',
    );

    foco.dispose();
  });
}
