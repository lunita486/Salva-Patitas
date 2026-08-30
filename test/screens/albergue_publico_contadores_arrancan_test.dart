import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Los contadores del perfil público del albergue no tienen que esperar al
/// documento del perfil para empezar a viajar.
///
/// **El problema.** Estaban declarados así:
///
/// ```dart
/// late final Future<int> _totalDisponibles = RescatesRepository().contar(...);
/// ```
///
/// `late` con inicializador quiere decir "esto se calcula la primera vez que
/// alguien lo lea". Y la primera lectura estaba adentro del `StreamBuilder`
/// de `usuarios/{uid}`, o sea que la consulta de conteo no salía al abrir la
/// pantalla: salía cuando ya había llegado el perfil. Dos viajes al servidor
/// encadenados, uno atrás del otro, cuando los dos pedidos son
/// independientes: para contar alcanza con el `rescatistaId`, que ya viene
/// por parámetro desde el feed.
///
/// Eliza lo reportó como lentitud de los contadores del perfil público.
///
/// **Qué prueba esto y qué no.** Montar la pantalla real necesita Firebase,
/// así que los tests de widget de acá abajo reproducen la ESTRUCTURA que
/// causaba la demora: un contador leído adentro del builder de un stream que
/// todavía no emitió. La diferencia entre las dos versiones es exactamente
/// la que separa el bug del arreglo. Los tests del final custodian que la
/// pantalla real siga escrita de la forma buena.
///
/// No se mide tiempo en ningún lado a propósito: el orden lo decide el test
/// con completers, así que no puede fallar de vez en cuando por ir lenta la
/// máquina.
void main() {
  group('la estructura que causaba la demora', () {
    testWidgets('el bug: el conteo no sale hasta que llega el perfil', (
      tester,
    ) async {
      final conteo = _ConteoFalso();
      final perfil = StreamController<String>();
      addTearDown(perfil.close);

      await tester.pumpWidget(
        _Perezoso(conteo: conteo, perfil: perfil.stream),
      );
      await tester.pumpAndSettle();

      expect(find.text('cargando el perfil'), findsOneWidget);
      expect(
        conteo.llamadas,
        0,
        reason: 'la consulta de conteo quedó esperando al documento del perfil',
      );

      // Recién cuando llega el perfil, el árbol lee la variable y ahí sale la
      // consulta. Ese es el segundo viaje encadenado.
      perfil.add('albergue');
      await tester.pumpAndSettle();
      expect(conteo.llamadas, 1);
    });

    testWidgets('el arreglo: en initState el conteo sale de entrada', (
      tester,
    ) async {
      final conteo = _ConteoFalso();
      final perfil = StreamController<String>();
      addTearDown(perfil.close);

      await tester.pumpWidget(
        _EnInitState(conteo: conteo, perfil: perfil.stream),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('cargando el perfil'),
        findsOneWidget,
        reason: 'el perfil sigue viajando, como antes',
      );
      expect(
        conteo.llamadas,
        1,
        reason: 'el conteo tiene que haber salido sin esperar al perfil',
      );
    });

    // El test que mide lo que de verdad cambia para quien mira la pantalla:
    // que los dos viajes se solapen en vez de hacer fila.
    testWidgets('el arreglo: el conteo se contesta mientras el perfil viaja', (
      tester,
    ) async {
      final conteo = _ConteoFalso();
      final perfil = StreamController<String>();
      addTearDown(perfil.close);

      await tester.pumpWidget(
        _EnInitState(conteo: conteo, perfil: perfil.stream),
      );
      await tester.pumpAndSettle();

      expect(
        conteo.responde(53),
        isTrue,
        reason: 'el pedido ya estaba en vuelo, así que se puede contestar',
      );

      perfil.add('albergue');
      await tester.pumpAndSettle();

      expect(
        find.text('53'),
        findsOneWidget,
        reason: 'el número ya estaba listo cuando llegó el perfil',
      );
    });

    // El mismo guion contra la versión vieja. Acá el servidor no puede
    // contestar porque todavía nadie preguntó, y cuando por fin se pregunta
    // hay que esperar un viaje entero más.
    testWidgets('el bug: no se puede contestar algo que no se preguntó', (
      tester,
    ) async {
      final conteo = _ConteoFalso();
      final perfil = StreamController<String>();
      addTearDown(perfil.close);

      await tester.pumpWidget(
        _Perezoso(conteo: conteo, perfil: perfil.stream),
      );
      await tester.pumpAndSettle();

      expect(
        conteo.responde(53),
        isFalse,
        reason: 'no hay ningún pedido en vuelo: la consulta ni salió',
      );

      perfil.add('albergue');
      await tester.pumpAndSettle();
      expect(
        find.text('—'),
        findsOneWidget,
        reason: 'llegó el perfil y el número todavía no: segundo viaje',
      );

      expect(conteo.responde(53), isTrue, reason: 'ahora sí está en vuelo');
      await tester.pumpAndSettle();
      expect(find.text('53'), findsOneWidget);
    });

    testWidgets('el arreglo no adelanta números: mientras no sabe, no dice', (
      tester,
    ) async {
      final conteo = _ConteoFalso();
      final perfil = StreamController<String>();
      addTearDown(perfil.close);

      await tester.pumpWidget(
        _EnInitState(conteo: conteo, perfil: perfil.stream),
      );
      perfil.add('albergue');
      await tester.pumpAndSettle();

      expect(find.text('—'), findsOneWidget);
      expect(
        find.text('0'),
        findsNothing,
        reason: 'un cero mientras carga se lee como "este albergue no tiene"',
      );

      // Y un cero de verdad sí se muestra.
      conteo.responde(0);
      await tester.pumpAndSettle();
      expect(find.text('0'), findsOneWidget);
    });
  });

  // ── Que la pantalla real siga escrita así ───────────────────────────────
  group('la pantalla real', () {
    final fuente = File(
      'lib/screens/albergue_publico_screen.dart',
    ).readAsStringSync();

    /// El cuerpo de `initState`, que termina donde arranca el `@override`
    /// siguiente (`dispose`).
    String cuerpoDeInitState() {
      final desde = fuente.indexOf('void initState()');
      expect(desde, isNot(-1), reason: 'no hay initState');
      final hasta = fuente.indexOf('@override', desde);
      expect(hasta, greaterThan(desde));
      return fuente.substring(desde, hasta);
    }

    test('los dos contadores se lanzan en initState', () {
      final cuerpo = cuerpoDeInitState();
      expect(
        cuerpo,
        contains('_totalDisponibles = '),
        reason: 'si no arranca acá, vuelve a hacer fila detrás del perfil',
      );
      expect(cuerpo, contains('_totalAdoptados = '));
    });

    test('y no vuelven a quedar con inicializador perezoso', () {
      expect(fuente, contains('late final Future<int> _totalDisponibles;'));
      expect(fuente, contains('late final Future<int> _totalAdoptados;'));
      expect(
        fuente,
        isNot(contains('late final Future<int> _totalDisponibles =')),
        reason: 'con inicializador sale recién cuando el árbol lo lee',
      );
      expect(
        fuente,
        isNot(contains('late final Future<int> _totalAdoptados =')),
      );
    });

    // El cambio es de CUÁNDO, no de QUÉ. Estos tres custodian que no se haya
    // colado nada más en el camino.
    test('no cambió qué cuentan', () {
      expect(fuente, contains('estados: estadosEnCuidado'));
      expect(fuente, contains("estados: const ['Adoptado']"));
      expect(
        'RescatesRepository().contar('.allMatches(fuente).length,
        2,
        reason: 'siguen siendo exactamente dos conteos, ni uno más',
      );
    });

    test('no se tocó la paginación', () {
      expect(fuente, contains('porPagina: 30'));
      expect(fuente, contains('despuesDe: _cursor'));
      expect(fuente, contains('if (_pidiendo || !_hayMas) return;'));
    });

    test('no se tocó el marcador de carga', () {
      expect(fuente, contains("static const _cargandoValor = '—';"));
      expect(fuente, contains("s.hasData ? '\${s.data}' : _cargandoValor"));
    });
  });
}

/// Un conteo falso que anota cuándo lo llamaron y contesta cuando el test
/// quiere.
///
/// [responde] devuelve `false` si no hay ningún pedido en vuelo, que es
/// justo lo que pasa cuando la consulta todavía no salió: el servidor no
/// puede contestar una pregunta que nadie hizo.
class _ConteoFalso {
  int llamadas = 0;
  Completer<int>? _enVuelo;

  Future<int> contar() {
    llamadas++;
    return (_enVuelo = Completer<int>()).future;
  }

  bool responde(int n) {
    final pendiente = _enVuelo;
    if (pendiente == null || pendiente.isCompleted) return false;
    pendiente.complete(n);
    return true;
  }
}

/// El árbol de la pantalla, reducido a lo que importa: el perfil por fuera,
/// el contador adentro. Esa anidación es la que decide si los dos viajes se
/// solapan o hacen fila.
///
/// [total] es una función y no un `Future` ya evaluado a propósito: si el
/// árbol leyera la variable al principio de `build`, la versión perezosa
/// dispararía la consulta igual y el test no probaría nada. La lectura tiene
/// que pasar adentro del builder del stream, como en la pantalla real.
Widget _arbol(Stream<String> perfil, Future<int> Function() total) =>
    MaterialApp(
      home: StreamBuilder<String>(
        stream: perfil,
        builder: (_, perfilSnap) {
          if (!perfilSnap.hasData) return const Text('cargando el perfil');
          return FutureBuilder<int>(
            future: total(),
            // El mismo marcador que `_cargandoValor` en la pantalla real.
            builder: (_, s) => Text(s.hasData ? '${s.data}' : '—'),
          );
        },
      ),
    );

/// Como estaba: la consulta se dispara la primera vez que el árbol lee la
/// variable, y esa lectura pasa adentro del builder del perfil.
class _Perezoso extends StatefulWidget {
  const _Perezoso({required this.conteo, required this.perfil});
  final _ConteoFalso conteo;
  final Stream<String> perfil;

  @override
  State<_Perezoso> createState() => _PerezosoState();
}

class _PerezosoState extends State<_Perezoso> {
  late final Future<int> _total = widget.conteo.contar();

  @override
  Widget build(BuildContext context) => _arbol(widget.perfil, () => _total);
}

/// Como quedó: la consulta sale al abrir la pantalla, en paralelo con el
/// pedido del perfil.
class _EnInitState extends StatefulWidget {
  const _EnInitState({required this.conteo, required this.perfil});
  final _ConteoFalso conteo;
  final Stream<String> perfil;

  @override
  State<_EnInitState> createState() => _EnInitStateState();
}

class _EnInitStateState extends State<_EnInitState> {
  late final Future<int> _total;

  @override
  void initState() {
    super.initState();
    _total = widget.conteo.contar();
  }

  @override
  Widget build(BuildContext context) => _arbol(widget.perfil, () => _total);
}
