import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// El panel del albergue no espera a los contadores para mostrarse.
///
/// **El bug.** El `body` entero estaba envuelto en un
/// `FutureBuilder<List<int>>` sobre `_numeros`, con un
/// `CircularProgressIndicator` a pantalla completa mientras esperaba. Y
/// `_numeros` son tres `count()`, que es una agregación: su única fuente
/// posible es el servidor (`AggregateSource` tiene un solo valor), así que
/// no hay caché y en cada inicio de sesión se paga el viaje entero, en
/// frío. Hasta que no volvían las tres no se pintaba NADA: ni el nombre del
/// albergue, ni la barra de capacidad, ni la Jauría.
///
/// Eliza: "cada vez que entro como albergue la Jauría tarda bastante en
/// aparecer". La Jauría no tenía nada que ver: no podía ni empezar a
/// mostrarse.
///
/// El panel del rescatista nunca lo tuvo, porque ahí ese mismo
/// FutureBuilder envuelve UN cuadrito y el carrusel tiene su propio spinner
/// en su lugar.
///
/// **Qué prueba esto y qué no.** Montar el panel real necesita Firebase,
/// así que los tests de widget reproducen la ESTRUCTURA: un encabezado, unos
/// números que tardan y una lista que tarda por su cuenta. La diferencia
/// entre las dos versiones es exactamente la que separa el bug del arreglo.
/// Los tests del final custodian que la pantalla real siga escrita así.
void main() {
  group('la estructura que bloqueaba', () {
    testWidgets('el bug: con todo adentro del FutureBuilder, no se ve nada', (
      tester,
    ) async {
      final numeros = Completer<List<int>>();
      final jauria = Completer<List<String>>();

      await tester.pumpWidget(
        _Bloqueante(numeros: numeros.future, jauria: jauria.future),
      );
      // pump y no pumpAndSettle: el spinner anima para siempre, asi que
      // settle nunca terminaria. Que ese spinner exista es justo el bug.
      await tester.pump();

      expect(find.text('Alberguito domingo'), findsNothing,
          reason: 'ni el encabezado, que no depende de ningún contador');
      expect(find.text('Naranjita'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    // 1. La pantalla NO queda bloqueada esperando los contadores.
    testWidgets('el arreglo: el encabezado se ve aunque los números tarden', (
      tester,
    ) async {
      final numeros = Completer<List<int>>();
      final jauria = Completer<List<String>>();

      await tester.pumpWidget(
        _Panel(numeros: numeros.future, jauria: jauria.future),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alberguito domingo'), findsOneWidget);
      expect(
        find.text('—'),
        findsNWidgets(2),
        reason: 'los dos cuadritos esperan, pero solo ellos',
      );
      expect(
        find.text('0'),
        findsNothing,
        reason: 'un cero mientras carga se lee como un dato ya traído',
      );
    });

    // 3. La Jauría se puede pintar sin que los contadores hayan vuelto.
    testWidgets('la Jauría aparece con los contadores todavía en camino', (
      tester,
    ) async {
      final numeros = Completer<List<int>>();
      final jauria = Completer<List<String>>();

      await tester.pumpWidget(
        _Panel(numeros: numeros.future, jauria: jauria.future),
      );
      jauria.complete(['Naranjita', 'Tigrito']);
      await tester.pumpAndSettle();

      expect(find.text('Naranjita'), findsOneWidget);
      expect(find.text('Tigrito'), findsOneWidget);
      expect(
        find.text('—'),
        findsNWidgets(2),
        reason: 'los contadores siguen esperando, y la lista no los esperó',
      );
    });

    // 2. Los números aparecen cuando el Future termina.
    testWidgets('cuando vuelven los contadores, los números se muestran', (
      tester,
    ) async {
      final numeros = Completer<List<int>>();
      final jauria = Completer<List<String>>();

      await tester.pumpWidget(
        _Panel(numeros: numeros.future, jauria: jauria.future),
      );
      numeros.complete([52, 1, 5]);
      await tester.pumpAndSettle();

      expect(find.text('52'), findsOneWidget, reason: 'en cuidado');
      expect(find.text('5'), findsOneWidget, reason: 'adoptados');
      expect(find.text('—'), findsNothing);
      // Y el encabezado nunca dejó de estar.
      expect(find.text('Alberguito domingo'), findsOneWidget);
    });

    testWidgets('el orden de llegada no importa: cada parte va por su lado', (
      tester,
    ) async {
      final numeros = Completer<List<int>>();
      final jauria = Completer<List<String>>();

      await tester.pumpWidget(
        _Panel(numeros: numeros.future, jauria: jauria.future),
      );
      numeros.complete([52, 1, 5]);
      await tester.pumpAndSettle();
      expect(find.text('52'), findsOneWidget);
      expect(find.text('Naranjita'), findsNothing);

      jauria.complete(['Naranjita']);
      await tester.pumpAndSettle();
      expect(find.text('52'), findsOneWidget);
      expect(find.text('Naranjita'), findsOneWidget);
    });
  });

  // ── Que la pantalla real siga escrita así ───────────────────────────────
  group('el panel real', () {
    final codigo = File('lib/screens/albergue_home_screen.dart')
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('el FutureBuilder de los contadores ya no muestra un spinner', () {
      final desde = codigo.indexOf('future: _numeros,');
      final hasta = codigo.indexOf('return Stack(', desde);
      expect(desde, isNot(-1), reason: 'no está el FutureBuilder de números');
      expect(hasta, greaterThan(desde));
      expect(
        codigo.substring(desde, hasta),
        isNot(contains('CircularProgressIndicator')),
        reason: 'volvió el spinner a pantalla completa: el panel entero '
            'espera otra vez a tres count() que no pueden usar caché',
      );
    });

    test('y tampoco corta el build antes de armar el panel', () {
      final desde = codigo.indexOf('future: _numeros,');
      final hasta = codigo.indexOf('return Stack(', desde);
      expect(
        codigo.substring(desde, hasta),
        isNot(contains('return ')),
        reason: 'cualquier salida temprana ahí vuelve a bloquear la pantalla',
      );
    });

    test('los tres contadores viajan como int?, no como int', () {
      expect(codigo, contains('int? enCuidado'));
      expect(codigo, contains('int? enAdopcion'));
      expect(codigo, contains('int? adoptados'));
      expect(
        codigo,
        isNot(contains('rSnap.data?.elementAtOrNull(0) ?? 0')),
        reason: 'volvió el 0 que se lee como un dato ya traído',
      );
    });

    test('los cuadritos muestran el marcador mientras no saben', () {
      expect(codigo, contains("static const _cargandoValor = '—';"));
      expect(codigo, contains('enCuidado == null ? _cargandoValor'));
      expect(codigo, contains('adoptados == null ? _cargandoValor'));
    });

    test('la barra de capacidad espera su número, no lo inventa', () {
      expect(
        codigo,
        contains('if (capacidad > 0 && totalActivos != null)'),
        reason: 'sin el guard, la barra se dibujaría en 0 de 5',
      );
    });

    // Lo que hay que proteger de verdad: que la Jauría tenga su propio
    // FutureBuilder y no dependa del de los contadores.
    test('la Jauría se pinta desde su propio Future', () {
      expect(codigo, contains('future: _jauria'));
      final jauria = codigo.indexOf('future: _jauria');
      final numeros = codigo.indexOf('future: _numeros,');
      expect(
        jauria,
        greaterThan(numeros),
        reason: 'la Jauría vive adentro del panel, no encima de los números',
      );
    });

    // El patrón salió de acá; si alguien se lo saca, que se entere.
    test('el panel del rescatista sigue sin bloquear por su contador', () {
      final r = File('lib/screens/home_screen.dart').readAsStringSync();
      final i = r.indexOf('future: _totalRescates');
      expect(i, isNot(-1));
      expect(
        r.substring(i, i + 400),
        isNot(contains('CircularProgressIndicator')),
        reason: 'ese contador envuelve un cuadrito, no la pantalla',
      );
    });
  });
}

/// Como estaba: TODO adentro del FutureBuilder de los contadores.
class _Bloqueante extends StatelessWidget {
  const _Bloqueante({required this.numeros, required this.jauria});
  final Future<List<int>> numeros;
  final Future<List<String>> jauria;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: FutureBuilder<List<int>>(
        future: numeros,
        builder: (_, s) {
          if (s.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          return _cuerpo(s.data, jauria);
        },
      ),
    ),
  );
}

/// Como quedó: el cuerpo se arma siempre, y cada pieza que depende de un
/// número espera sola.
class _Panel extends StatelessWidget {
  const _Panel({required this.numeros, required this.jauria});
  final Future<List<int>> numeros;
  final Future<List<String>> jauria;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: FutureBuilder<List<int>>(
        future: numeros,
        // Sin salida temprana: el cuerpo se arma con lo que haya.
        builder: (_, s) => _cuerpo(s.data, jauria),
      ),
    ),
  );
}

/// El panel, reducido: un encabezado que no depende de nada, dos cuadritos
/// que dependen de los contadores, y una lista con su propio Future.
Widget _cuerpo(List<int>? numeros, Future<List<String>> jauria) {
  final enCuidado = numeros?.elementAtOrNull(0);
  final adoptados = numeros?.elementAtOrNull(2);
  return Column(
    children: [
      const Text('Alberguito domingo'),
      Text(enCuidado == null ? '—' : '$enCuidado'),
      Text(adoptados == null ? '—' : '$adoptados'),
      Expanded(
        child: FutureBuilder<List<String>>(
          future: jauria,
          builder: (_, s) => Column(
            children: [for (final n in s.data ?? const <String>[]) Text(n)],
          ),
        ),
      ),
    ],
  );
}
