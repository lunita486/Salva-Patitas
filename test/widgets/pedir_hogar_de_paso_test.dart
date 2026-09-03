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
    testWidgets('la etiqueta es "Email", sin "opcional"', (tester) async {
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
    // La etiqueta es la MISMA que la del albergue: los dos son un campo
    // Email. Lo único que sigue distinto entre los dos lados es la
    // obligatoriedad, que es otra regla y no se anuncia en la etiqueta.
    testWidgets('su campo se llama "Email", igual que el del albergue', (
      tester,
    ) async {
      await abrir(tester, pedirEmail: false);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Email (opcional)'), findsNothing);
      expect(find.text('Teléfono o email (opcional)'), findsNothing);
    });

    testWidgets('con nombre y fechas, sin email, Guardar se habilita', (
      tester,
    ) async {
      await abrir(tester, pedirEmail: false);
      await tester.enterText(find.byType(TextField).first, 'La vecina');
      await ponerFechas(tester);

      expect(
        guardar(tester).onPressed,
        isNotNull,
        reason: 'para el rescatista el email sigue siendo OPCIONAL',
      );
    });
  });

  // ── El email del rescatista, con el criterio de siempre ───────────────
  //
  // El campo decía "Teléfono o email (opcional)" y no validaba nada: en
  // producción los 3 valores que había en `hogarDePasoContacto` escritos
  // por un rescatista eran "jdhshsbdbdbdbdn", "vwhw" y "vdhs"; los 3 del
  // albergue, que sí validaba, eran emails de verdad.
  //
  // Se estandarizó con el del albergue: los dos son un campo Email y los
  // dos usan esEmailValido. Lo único distinto entre los lados es la
  // obligatoriedad, que es otra regla.
  //
  // Estos tests manejan el diálogo REAL y miran si se cerró o no, que es lo
  // único que decide si el valor se guarda.
  group('pedirHogarDePaso() — el email del rescatista', () {
    /// Escribe [email], completa lo obligatorio, toca Guardar y dice si el
    /// diálogo aceptó el valor.
    Future<bool> guardaCon(WidgetTester tester, String email) async {
      await abrir(tester, pedirEmail: false);
      await tester.enterText(find.byType(TextField).first, 'La vecina');
      if (email.isNotEmpty) {
        await tester.enterText(find.byType(TextField).last, email);
      }
      await ponerFechas(tester);
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Si el diálogo se cerró, aceptó el valor. Si sigue abierto, lo
      // rechazó.
      return find.text('Guardar').evaluate().isEmpty;
    }

    testWidgets('vacío se acepta: el campo es opcional', (tester) async {
      expect(await guardaCon(tester, ''), isTrue);
    });

    testWidgets('un email válido se acepta', (tester) async {
      expect(await guardaCon(tester, 'ana@mail.com'), isTrue);
    });

    testWidgets('un email a medio escribir se rechaza', (tester) async {
      expect(await guardaCon(tester, 'ana@mail'), isFalse);
    });

    testWidgets('un dominio sin punto tampoco: "lunita486@gmail"', (
      tester,
    ) async {
      expect(await guardaCon(tester, 'lunita486@gmail'), isFalse);
    });

    testWidgets('texto sin ninguna forma se rechaza', (tester) async {
      expect(await guardaCon(tester, 'verdura'), isFalse);
    });

    testWidgets('y el otro caso real de producción tampoco pasa', (
      tester,
    ) async {
      expect(await guardaCon(tester, 'vdhs'), isFalse);
    });

    // Ya no es un campo de teléfono: se estandarizó como Email.
    testWidgets('un teléfono ya no se acepta', (tester) async {
      expect(await guardaCon(tester, '300 123 4567'), isFalse);
    });

    // Que el email se decida con esEmailValido y no con una copia: los dos
    // valores tienen la MISMA forma para cualquier regla del tipo "tiene
    // arroba y algo después", y solo esEmailValido los separa.
    testWidgets('la frontera es exactamente la de esEmailValido', (
      tester,
    ) async {
      expect(esEmailValido('ana@mail.co'), isTrue);
      expect(esEmailValido('ana@mailco'), isFalse);
      expect(await guardaCon(tester, 'ana@mail.co'), isTrue);
      expect(await guardaCon(tester, 'ana@mailco'), isFalse);
    });

    testWidgets('el aviso es exactamente "Email inválido"', (tester) async {
      await guardaCon(tester, 'verdura');
      expect(
        tester
            .widget<TextField>(find.byType(TextField).last)
            .decoration!
            .errorText,
        avisoEmailCorto,
      );
    });

    // El aviso largo de reglas_negocio sigue existiendo para los perfiles y
    // la Red de hogares; en ESTE diálogo no se usa más.
    testWidgets('y no el largo que usan los perfiles', (tester) async {
      await guardaCon(tester, 'verdura');
      expect(find.text(avisoEmailInvalido), findsNothing);
    });

    testWidgets('el albergue muestra el MISMO aviso corto', (tester) async {
      await abrir(tester, pedirEmail: true);
      await tester.enterText(find.byType(TextField).first, 'La vecina');
      await tester.enterText(find.byType(TextField).last, 'verdura');
      await ponerFechas(tester);
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(find.byType(TextField).last)
            .decoration!
            .errorText,
        avisoEmailCorto,
        reason:
            'el mismo error no puede explicarse de dos formas en la '
            'misma pantalla',
      );
    });
  });
}
