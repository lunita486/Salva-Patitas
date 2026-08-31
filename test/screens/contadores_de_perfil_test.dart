import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/data/usuarios_repository.dart';

/// Los números de los dos perfiles salen de contadores guardados en
/// `usuarios/{uid}`, no de `count()`.
///
/// **Por qué.** Hasta el APK96 salían de un stream de la consulta completa:
/// instantáneos, porque un stream de Firestore entrega primero lo que hay
/// en el caché local, pero descargando TODOS los documentos para pintar dos
/// números. El APK97 los pasó a `count()`, que no descarga nada, y ahí se
/// perdió el caché sin querer: `count()` es una agregación y su única
/// fuente posible es el servidor (`AggregateSource` tiene un solo valor).
/// Cada apertura pasó a pagar un viaje de red completo.
///
/// La prueba más limpia la trajo Eliza sin buscarla: en el perfil del
/// albergue la CAPACIDAD aparece al instante y los otros dos números
/// tardan. Misma pantalla, mismo momento. La capacidad es un campo de
/// `usuarios/{uid}` y se sirve del caché; los otros dos no podían.
///
/// Los mantiene al día el trigger `onRescateContado`
/// (functions/contadores.js), que tiene sus propios tests en
/// `functions/test/`. Un solo trigger y una sola tabla de definiciones para
/// los dos roles: por eso este archivo también es uno solo.
void main() {
  final logicaServidor = File(
    'functions/contadores_logica.js',
  ).readAsStringSync();
  final reglas = File('firestore.rules').readAsStringSync();

  /// Un archivo sin sus líneas de comentario. Hace falta: los comentarios
  /// de estas pantallas citan textualmente el código viejo para explicar
  /// por qué se fue, así que buscar el defecto en el archivo entero lo
  /// encontraría en la explicación de por qué ya no está.
  String soloCodigo(String ruta) => File(ruta)
      .readAsStringSync()
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///'))
      .join('\n');

  final pantallas = [
    (
      nombre: 'perfil del rescatista',
      ruta: 'lib/screens/perfil_rescatista_screen.dart',
      lector: 'contadoresRescatistaDe(',
      campos: [campoContadorRescatistaTotal, campoContadorRescatistaAdoptados],
      // El plan B es inalcanzable si hay contador guardado: primero se sale
      // por ahí, y solo se cuenta si además el documento YA llegó.
      guardas: [
        'if (guardados != null) {',
        'if (perfilSnap.hasData || perfilSnap.hasError) {',
      ],
    ),
    (
      nombre: 'perfil público del albergue',
      ruta: 'lib/screens/albergue_publico_screen.dart',
      lector: 'contadoresAlbergueDe(',
      campos: [campoContadorAlbergueEnCuidado, campoContadorAlbergueAdoptados],
      guardas: [
        'if (contadores == null && (userSnap.hasData || userSnap.hasError)) {',
      ],
    ),
  ];

  final todosLosCampos = [
    campoContadorRescatistaTotal,
    campoContadorRescatistaAdoptados,
    campoContadorAlbergueEnCuidado,
    campoContadorAlbergueAdoptados,
  ];

  // ── Lo que más fácil se rompe: los tres lados del cable ───────────────
  //
  // El nombre de cada campo está escrito en Dart, en JavaScript y en las
  // reglas. Nada los ata: si alguien renombra uno, todo compila, los tests
  // de cada lado pasan, y la app se queda mostrando el marcador de carga
  // para siempre mientras el servidor escribe un campo que nadie lee. O
  // peor: el campo queda fuera de la regla y pasa a ser falsificable.
  group('los nombres de campo coinciden en los tres lados', () {
    for (final campo in [
      campoContadorRescatistaTotal,
      campoContadorRescatistaAdoptados,
      campoContadorAlbergueEnCuidado,
      campoContadorAlbergueAdoptados,
    ]) {
      test('$campo lo escribe el servidor', () {
        expect(
          logicaServidor,
          contains("campo: '$campo'"),
          reason: 'la app lee un campo que el trigger no escribe',
        );
      });

      test('$campo está protegido por las reglas', () {
        expect(
          reglas,
          contains("'$campo'"),
          reason: 'sin la regla, cualquiera puede inventarse ese número',
        );
      });
    }

    test('son cuatro, y todos dicen de qué rol hablan', () {
      expect(todosLosCampos.toSet().length, 4);
      expect(campoContadorRescatistaTotal.toLowerCase(), contains('rescatista'));
      expect(campoContadorRescatistaAdoptados.toLowerCase(), contains('rescatista'));
      expect(campoContadorAlbergueEnCuidado.toLowerCase(), contains('albergue'));
      expect(campoContadorAlbergueAdoptados.toLowerCase(), contains('albergue'));
    });

    test('las definiciones del servidor no cambiaron', () {
      // "Animales rescatados" son TODOS los estados (estados: null).
      expect(logicaServidor, contains("campo: 'contadorRescatistaTotal', estados: null"));
      // "En cuidado" del albergue es Rescatado + Regresado, sin Hogar de paso.
      expect(
        logicaServidor,
        contains("campo: 'contadorAlbergueEnCuidado', estados: ['Rescatado', 'Regresado']"),
      );
      expect(logicaServidor, isNot(contains("'contadorAlbergueEnCuidado', estados: ['Rescatado', 'Regresado', 'Hogar de paso']")));
    });
  });

  // ── La decisión que se quiere custodiar, una sola para los dos ────────
  group('contadoresGuardadosDe', () {
    ({int principal, int adoptados})? leer(Map<String, dynamic>? datos) =>
        contadoresGuardadosDe(
          datos,
          campoPrincipal: 'a',
          campoAdoptados: 'b',
        );

    test('con los dos campos guardados, los devuelve', () {
      final r = leer({'a': 54, 'b': 3, 'nombre': 'Refugio'});
      expect(r, isNotNull);
      expect(r!.principal, 54);
      expect(r.adoptados, 3);
    });

    test('un cero guardado es un dato, no una ausencia', () {
      final r = leer({'a': 0, 'b': 0});
      expect(r, isNotNull, reason: 'un albergue sin animalitos tiene 0, y 0 es la respuesta');
      expect(r!.principal, 0);
    });

    test('sin los campos devuelve null, que NO es cero', () {
      expect(leer({'nombre': 'Refugio'}), isNull);
      expect(leer(null), isNull);
    });

    test('con uno solo de los dos, tampoco alcanza', () {
      expect(
        leer({'a': 54}),
        isNull,
        reason: 'mostrar uno real y otro inventado sería peor que esperar',
      );
    });

    test('un valor de otro tipo cae al conteo real en vez de reventar', () {
      expect(leer({'a': '54', 'b': 3}), isNull);
    });

    test('cada perfil lee SUS campos, no los del otro rol', () {
      // Una cuenta con los dos sombreros no puede cruzar los números.
      final cuenta = {
        campoContadorRescatistaTotal: 7,
        campoContadorRescatistaAdoptados: 2,
        campoContadorAlbergueEnCuidado: 54,
        campoContadorAlbergueAdoptados: 3,
      };
      expect(contadoresRescatistaDe(cuenta)!.principal, 7);
      expect(contadoresAlbergueDe(cuenta)!.principal, 54);
    });

    test('una cuenta con un solo sombrero no ve los contadores del otro', () {
      final soloAlbergue = {
        campoContadorAlbergueEnCuidado: 54,
        campoContadorAlbergueAdoptados: 3,
      };
      expect(contadoresAlbergueDe(soloAlbergue), isNotNull);
      expect(
        contadoresRescatistaDe(soloAlbergue),
        isNull,
        reason: 'tiene que caer al conteo real, no mostrar los del albergue',
      );
    });
  });

  // ── Que el perfil NO cuente cuando ya tiene el número ─────────────────
  //
  // Montar las pantallas reales necesita Firebase, así que estos tests usan
  // un árbol reducido. Pero la rama que deciden es la de verdad: el `if`
  // sale de contadoresGuardadosDe, la misma función que llaman las dos
  // pantallas.
  group('el perfil lee el contador guardado y no cuenta', () {
    testWidgets('con contadores en el documento, count() no se ejecuta', (
      tester,
    ) async {
      final conteo = _ConteoFalso();
      final perfil = StreamController<Map<String, dynamic>?>();
      addTearDown(perfil.close);

      await tester.pumpWidget(_Contadores(conteo: conteo, perfil: perfil.stream));
      perfil.add({
        campoContadorAlbergueEnCuidado: 54,
        campoContadorAlbergueAdoptados: 3,
      });
      await tester.pumpAndSettle();

      expect(find.text('54'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(
        conteo.llamadas,
        0,
        reason: 'volvió a pagar el viaje de count() teniendo el número al lado',
      );
    });

    testWidgets('sin contadores, cae al conteo real UNA vez', (tester) async {
      final conteo = _ConteoFalso();
      final perfil = StreamController<Map<String, dynamic>?>();
      addTearDown(perfil.close);

      await tester.pumpWidget(_Contadores(conteo: conteo, perfil: perfil.stream));
      perfil.add({'albergueNombre': 'Alberguito domingo'});
      await tester.pumpAndSettle();

      expect(conteo.llamadas, 1, reason: 'sin esto una cuenta nueva vería un guion para siempre');
      expect(find.text('—'), findsNWidgets(2), reason: 'todavía no volvió');

      conteo.responde([54, 3]);
      await tester.pumpAndSettle();
      expect(find.text('54'), findsOneWidget);

      // Y si el perfil se vuelve a emitir, no se cuenta de nuevo.
      perfil.add({'albergueNombre': 'Alberguito domingo', 'ciudad': 'Medellín'});
      await tester.pumpAndSettle();
      expect(conteo.llamadas, 1);
    });

    testWidgets('cuando el trigger siembra el contador, deja de contar', (
      tester,
    ) async {
      final conteo = _ConteoFalso();
      final perfil = StreamController<Map<String, dynamic>?>();
      addTearDown(perfil.close);

      await tester.pumpWidget(_Contadores(conteo: conteo, perfil: perfil.stream));
      perfil.add({'albergueNombre': 'Alberguito domingo'});
      await tester.pumpAndSettle();
      conteo.responde([54, 3]);
      await tester.pumpAndSettle();

      // Llega la escritura del servidor.
      perfil.add({
        campoContadorAlbergueEnCuidado: 55,
        campoContadorAlbergueAdoptados: 3,
      });
      await tester.pumpAndSettle();

      expect(find.text('55'), findsOneWidget, reason: 'gana el contador guardado');
      expect(conteo.llamadas, 1);
    });

    testWidgets('mientras no llegó el perfil se ve el marcador, no un cero', (
      tester,
    ) async {
      final conteo = _ConteoFalso();
      final perfil = StreamController<Map<String, dynamic>?>();
      addTearDown(perfil.close);

      await tester.pumpWidget(_Contadores(conteo: conteo, perfil: perfil.stream));
      await tester.pumpAndSettle();

      expect(find.text('—'), findsNWidgets(2));
      expect(
        find.text('0'),
        findsNothing,
        reason: 'un cero mientras carga se lee como "este refugio no tiene ninguno"',
      );
      expect(
        conteo.llamadas,
        0,
        reason: 'ni siquiera se sabe todavía si hace falta contar',
      );
    });
  });

  // ── Que las pantallas reales sigan escritas así ───────────────────────
  for (final p in pantallas) {
    group(p.nombre, () {
      final codigo = soloCodigo(p.ruta);

      test('lee el documento del perfil en vivo', () {
        expect(codigo, contains("collection('usuarios')"));
        expect(
          codigo,
          contains('.snapshots()'),
          reason: 'con .get() se pierde el caché, que es todo el punto',
        );
      });

      test('decide con el lector compartido, no leyendo los campos a mano', () {
        expect(codigo, contains(p.lector));
        for (final campo in todosLosCampos) {
          expect(
            codigo,
            isNot(contains("'$campo'")),
            reason: 'el nombre del campo tiene que venir de la constante',
          );
        }
      });

      test('el conteo a mano queda DESPUÉS de la salida por contador guardado', () {
        final iGuardado = codigo.indexOf(p.lector);
        final iConteo = codigo.indexOf('_plazoB ??=');
        expect(iGuardado, isNot(-1), reason: 'no hay camino de contador guardado');
        expect(iConteo, isNot(-1), reason: 'no hay plan B');
        expect(
          iConteo,
          greaterThan(iGuardado),
          reason: 'si el conteo va primero, se paga el viaje siempre',
        );
      });

      // La posición no alcanza: el plan B puede estar más abajo y correr
      // igual siempre. Lo que lo hace inalcanzable con contador guardado es
      // la GUARDA, y eso es lo que se custodia acá. Sin este test, cambiar
      // la condición por `if (true)` pasaba desapercibido: lo encontré
      // haciendo justamente esa contraprueba.
      test('y solo se ejecuta si no hay contador guardado', () {
        for (final guarda in p.guardas) {
          expect(
            codigo,
            contains(guarda),
            reason: 'sin esta guarda el count() vuelve a correr siempre',
          );
        }
      });

      test('el conteo a mano se hace una sola vez', () {
        expect(
          codigo,
          contains('_plazoB ??= _contarAMano();'),
          reason: 'sin el ??= se relanza en cada rebuild de la pantalla',
        );
        // Dos: la declaración del método y ese único lugar donde se llama.
        expect('_contarAMano'.allMatches(codigo).length, 2);
      });

      test('no volvió el cero mientras carga', () {
        expect(codigo, contains("static const _cargandoValor = '—';"));
        // El plan B pinta el marcador mientras no tiene el número, nunca
        // un cero. El `?? 0` de `capacidadTotal` en el albergue es otra
        // cosa y es de antes: ese cero significa "sin capacidad declarada"
        // y es lo que decide si ese chip se muestra.
        expect(
          RegExp(r"hasData \? '\$\{\w+\.data!\[\w+\]\}' : _cargandoValor")
              .hasMatch(codigo),
          isTrue,
          reason: 'el plan B ya no distingue "no llegó" de un número real',
        );
        for (final linea in codigo.split('\n')) {
          if (!linea.contains('?? 0')) continue;
          expect(
            linea.contains('data!') || linea.contains('_plazoB'),
            isFalse,
            reason: 'un cero en el camino del contador: $linea',
          );
        }
      });

      test('el plan B cuenta lo mismo de siempre', () {
        expect(
          'RescatesRepository().contar('.allMatches(codigo).length,
          2,
          reason: 'siguen siendo los mismos dos conteos, ni uno más',
        );
        expect(codigo, contains("estados: const ['Adoptado']"));
      });

      test('siguen siendo conteos del servidor, no la colección entera', () {
        expect(
          codigo,
          isNot(contains('.docs.length')),
          reason: 'volvió a descargar documentos para pintar un número',
        );
      });
    });
  }

  // ── Lo que Eliza pidió confirmar explícitamente ───────────────────────
  group('el albergue los recibe en el MISMO documento que capacidadTotal', () {
    final codigo = soloCodigo('lib/screens/albergue_publico_screen.dart');

    test('capacidad y contadores salen de la misma variable `data`', () {
      expect(codigo, contains("data['capacidadTotal']"));
      expect(
        codigo,
        contains('contadoresAlbergueDe(data)'),
        reason: 'si leyera de otro lado, no viajarían en el mismo snapshot',
      );
    });

    test('no hay una segunda lectura de usuarios en esa pantalla', () {
      expect(
        "collection('usuarios')".allMatches(codigo).length,
        1,
        reason: 'los contadores no deben costar una consulta nueva',
      );
    });

    test('el plan B ya no arranca en initState', () {
      final iInit = codigo.indexOf('void initState()');
      final iDispose = codigo.indexOf('void dispose()');
      final cuerpo = codigo.substring(iInit, iDispose);
      expect(
        cuerpo,
        isNot(contains('contar(')),
        reason: 'arrancarlo siempre sería pagar el viaje que estamos sacando',
      );
      // La grilla SÍ sigue arrancando ahí: eso no cambió.
      expect(cuerpo, contains('_pedirPagina();'));
    });

    test('la grilla y su paginación no se tocaron', () {
      expect(codigo, contains('porPagina: 30'));
      expect(codigo, contains('despuesDe: _cursor'));
      expect(codigo, contains('estados: estadosEnCuidado'));
      expect(codigo, contains('if (_pidiendo || !_hayMas) return;'));
    });
  });
}

/// Un conteo falso que anota cuántas veces lo llamaron y contesta cuando el
/// test quiere. Sin esperas de reloj: el orden lo decide el test.
class _ConteoFalso {
  int llamadas = 0;
  Completer<List<int>>? _enVuelo;

  Future<List<int>> contar() {
    llamadas++;
    return (_enVuelo = Completer<List<int>>()).future;
  }

  void responde(List<int> numeros) => _enVuelo?.complete(numeros);
}

/// El árbol de un perfil, reducido a la rama que importa. La decisión de si
/// hay contador guardado la toma `contadoresAlbergueDe`, la misma función de
/// producción que usan las pantallas.
class _Contadores extends StatefulWidget {
  const _Contadores({required this.conteo, required this.perfil});
  final _ConteoFalso conteo;
  final Stream<Map<String, dynamic>?> perfil;

  @override
  State<_Contadores> createState() => _ContadoresState();
}

class _ContadoresState extends State<_Contadores> {
  Future<List<int>>? _plazoB;

  Widget _fila(String principal, String adoptados) =>
      Row(children: [Text(principal), Text(adoptados)]);

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: StreamBuilder<Map<String, dynamic>?>(
      stream: widget.perfil,
      builder: (context, perfilSnap) {
        final guardados = contadoresAlbergueDe(perfilSnap.data);
        if (guardados != null) {
          return _fila('${guardados.principal}', '${guardados.adoptados}');
        }
        if (perfilSnap.hasData || perfilSnap.hasError) {
          _plazoB ??= widget.conteo.contar();
          return FutureBuilder<List<int>>(
            future: _plazoB,
            builder: (context, snap) => _fila(
              snap.hasData ? '${snap.data![0]}' : '—',
              snap.hasData ? '${snap.data![1]}' : '—',
            ),
          );
        }
        return _fila('—', '—');
      },
    ),
  );
}
