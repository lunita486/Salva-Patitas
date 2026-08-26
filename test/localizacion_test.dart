import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// La app está escrita entera en español, pero los widgets que Material
/// trae con texto propio (el calendario, el selector de hora, el menú de
/// copiar/pegar) salían en INGLÉS: "Select date", "August 2026", y los días
/// como "S M T W T F S".
///
/// Se veía en el selector de fechas del hogar de paso y en el de la
/// solicitud de adopción, adentro de un formulario que dice "Desde" y
/// "Hasta" en español.
void main() {
  testWidgets('el calendario de Material sale en español', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('es')],
        localeResolutionCallback: (_, __) => const Locale('es'),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDatePicker(
              context: context,
              initialDate: DateTime(2026, 8, 26),
              firstDate: DateTime(2026, 8, 1),
              lastDate: DateTime(2027, 8, 1),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Select date'), findsNothing, reason: 'estaba en inglés');
    expect(find.textContaining('Seleccionar'), findsWidgets);
    expect(find.textContaining('agosto'), findsWidgets, reason: 'August');
  });

  // Y que un teléfono configurado en otro idioma vea igual el español: la
  // app no está traducida, así que media en inglés y media en español sería
  // peor que toda en español.
  testWidgets('un teléfono en inglés igual ve español', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('es')],
        localeResolutionCallback: (_, __) => const Locale('es'),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDatePicker(
              context: context,
              initialDate: DateTime(2026, 8, 26),
              firstDate: DateTime(2026, 8, 1),
              lastDate: DateTime(2027, 8, 1),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Select date'), findsNothing);
  });
}
