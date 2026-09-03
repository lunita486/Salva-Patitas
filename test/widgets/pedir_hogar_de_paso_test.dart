import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/domain/reglas_negocio.dart';
import 'package:salva_patitas/widgets/pedir_hogar_de_paso.dart';

/// El email del ALBERGUE es obligatorio; el contacto del RESCATISTA no.
///
/// **Por qué.** Las dos puertas que alimentan la red de hogares de paso
/// pedían cosas distintas: el formulario de "Agregar"
/// (hogares_de_paso_screen.dart) exigía el email, y este diálogo lo pedía
/// como "(opcional)". Sin email, buscarDuplicado() no tiene con qué
/// comparar y crea una fila nueva cada vez que la misma persona cuida a
/// otro animalito. Medido en producción el 2026-09-02: 5 de 13 filas de la
/// red sin email.
///
/// Del lado del rescatista el campo sigue siendo opcional y sigue diciendo
/// "Teléfono o email": no alimenta ninguna red, solo se muestra en la
/// tarjeta del animalito.
void main() {
  /// Abre el diálogo y devuelve lo que eligió, o null si se canceló.
  Future<DatosHogarDePaso?> abrir(
    WidgetTester tester, {
    required bool pedirEmail,
  }) async {
    DatosHogarDePaso? resultado;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                resultado = await pedirHogarDePaso(ctx, pedirEmail: pedirEmail);
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return resultado;
  }

  /// Completa las dos fechas con el día de hoy, que es el mínimo que el
  /// calendario deja elegir en los dos campos.
  Future<void> ponerFechas(WidgetTester tester) async {
    for (final campo in ['Desde', 'Hasta']) {
      await tester.tap(find.text(campo));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }
  }

  /// El botón Guardar, para preguntarle si está habilitado.
  TextButton guardar(WidgetTester tester) =>
      tester.widget<TextButton>(find.widgetWithText(TextButton, 'Guardar'));

  group('pedirHogarDePaso() — lado ALBERGUE (pedirEmail: true)', () {
    testWidgets('la etiqueta ya no dice "opcional"', (tester) async {
      await abrir(tester, pedirEmail: true);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Email (opcional)'), findsNothing);
    });

    testWidgets('con nombre y fechas pero SIN email, Guardar sigue apagado', (
      tester,
    ) async {
      await abrir(tester, pedirEmail: true);
      await tester.enterText(find.byType(TextField).first, 'Luna');
      await ponerFechas(tester);

      expect(
        guardar(tester).onPressed,
        isNull,
        reason: 'sin email la red no puede identificar a esta persona',
      );
    });

    testWidgets('con el email puesto, Guardar se habilita', (tester) async {
      await abrir(tester, pedirEmail: true);
      await tester.enterText(find.byType(TextField).first, 'Luna');
      await tester.enterText(
        find.byType(TextField).last,
        'lunita486@gmail.com',
      );
      await ponerFechas(tester);

      expect(guardar(tester).onPressed, isNotNull);
    });

    testWidgets('un email inválido no deja guardar: avisa y el diálogo sigue '
        'abierto', (tester) async {
      await abrir(tester, pedirEmail: true);
      await tester.enterText(find.byType(TextField).first, 'Luna');
      await tester.enterText(find.byType(TextField).last, 'lunita486@gmail');
      await ponerFechas(tester);

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(
        find.text('Guardar'),
        findsOneWidget,
        reason: 'no se cerró: el dato mal escrito no llegó a la red',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('pedirHogarDePaso() — lado RESCATISTA (pedirEmail: false)', () {
    testWidgets('su campo sigue siendo "Teléfono o email (opcional)"', (
      tester,
    ) async {
      await abrir(tester, pedirEmail: false);
      expect(find.text('Teléfono o email (opcional)'), findsOneWidget);
    });

    testWidgets('con nombre y fechas, sin contacto, Guardar se habilita', (
      tester,
    ) async {
      await abrir(tester, pedirEmail: false);
      await tester.enterText(find.byType(TextField).first, 'La vecina');
      await ponerFechas(tester);

      expect(
        guardar(tester).onPressed,
        isNotNull,
        reason: 'el rescatista no tiene red: su contacto no es identidad',
      );
    });

    testWidgets('un texto que no es email tampoco lo bloquea', (tester) async {
      await abrir(tester, pedirEmail: false);
      await tester.enterText(find.byType(TextField).first, 'La vecina');
      await tester.enterText(find.byType(TextField).last, '3001234567');
      await ponerFechas(tester);

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(
        find.text('Guardar'),
        findsNothing,
        reason: 'se cerró: un teléfono es válido en este campo',
      );
    });
  });

  // ── El campo del RESCATISTA: teléfono O email, pero algo que sirva ────
  //
  // Sigue siendo opcional, pero aceptaba cualquier cosa. En producción los
  // 3 valores que había en `hogarDePasoContacto` escritos por un rescatista
  // eran "jdhshsbdbdbdbdn", "vwhw" y "vdhs"; los 3 del albergue, que sí
  // validaba, eran emails de verdad. El campo existe para poder pedirle el
  // animalito de vuelta a esa persona: un texto que no sirve para
  // contactarla no cumple ninguna función.
  //
  // Estos tests manejan el diálogo REAL y miran si se cerró o no, que es lo
  // único que importa: si se cierra, ese valor se guardó.
  group('pedirHogarDePaso() — "Teléfono o email" del rescatista', () {
    /// Escribe [contacto], completa lo obligatorio, toca Guardar y dice si
    /// el diálogo aceptó el valor.
    Future<bool> guardaCon(WidgetTester tester, String contacto) async {
      await abrir(tester, pedirEmail: false);
      await tester.enterText(find.byType(TextField).first, 'La vecina');
      if (contacto.isNotEmpty) {
        await tester.enterText(find.byType(TextField).last, contacto);
      }
      await ponerFechas(tester);
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Si el diálogo se cerró, acepto el valor. Si sigue abierto, lo
      // rechazo.
      return find.text('Guardar').evaluate().isEmpty;
    }

    testWidgets('vacío se acepta: el campo sigue siendo opcional', (
      tester,
    ) async {
      expect(await guardaCon(tester, ''), isTrue);
    });

    testWidgets('un email válido se acepta', (tester) async {
      expect(await guardaCon(tester, 'ana@mail.com'), isTrue);
    });

    testWidgets('un email a medio escribir se rechaza', (tester) async {
      expect(await guardaCon(tester, 'ana@mail'), isFalse);
      expect(
        find.text(avisoEmailInvalido),
        findsOneWidget,
        reason: 'escribió una @, así que el aviso es el de email',
      );
    });

    testWidgets('un teléfono se acepta', (tester) async {
      expect(await guardaCon(tester, '300 123 4567'), isTrue);
    });

    testWidgets('con indicativo también', (tester) async {
      expect(await guardaCon(tester, '+57 300 123 4567'), isTrue);
    });

    testWidgets('con paréntesis y guiones también', (tester) async {
      expect(await guardaCon(tester, '(300) 123-4567'), isTrue);
    });

    testWidgets('menos de 7 dígitos se rechaza', (tester) async {
      expect(await guardaCon(tester, '123'), isFalse);
    });

    testWidgets('justo 7 dígitos alcanza: un fijo local', (tester) async {
      expect(await guardaCon(tester, '2345678'), isTrue);
    });

    testWidgets('texto sin ninguna forma se rechaza', (tester) async {
      expect(await guardaCon(tester, 'verdura'), isFalse);
    });

    testWidgets('y el otro caso real de producción tampoco pasa', (
      tester,
    ) async {
      expect(await guardaCon(tester, 'vdhs'), isFalse);
    });

    testWidgets('el aviso del rechazo dice que acepta las DOS cosas, no solo '
        'email', (tester) async {
      await guardaCon(tester, 'verdura');
      final aviso = tester
          .widget<TextField>(find.byType(TextField).last)
          .decoration!
          .errorText!;
      expect(aviso, contains('teléfono'));
      expect(aviso, contains('email'));
    });
  });
}
