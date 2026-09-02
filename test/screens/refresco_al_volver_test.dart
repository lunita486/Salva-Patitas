import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Volver de otra pantalla NO reconstruye la de abajo.
///
/// **El bug.** El panel del albergue carga la Jauría, "Encontraron hogar" y
/// los tres números en `initState`, y los guarda en su `State`. Desde ahí,
/// "Ver todas" lleva a `mis_rescates_screen`, que abre su propia
/// `CambiarEstadoSheet`. Al volver, el panel sigue vivo debajo: su
/// `initState` no corre de nuevo y nadie le avisa que algo cambió. Eliza
/// adoptaba un animalito desde ahí y el animalito no aparecía en
/// "Encontraron hogar", ni se movía el cuadrito azul de Adoptados, por el
/// resto de la sesión.
///
/// El panel del rescatista nunca lo tuvo, porque su push a esa misma ruta ya
/// llevaba `.then((_) => _refrescarRescates())`.
///
/// **Qué prueba esto y qué no.** Montar el panel real necesita Firebase, así
/// que acá se reproduce la ESTRUCTURA con un Navigator de verdad: una
/// pantalla que carga un número al montarse, otra que lo cambia, y la vuelta.
/// La diferencia entre las dos versiones es exactamente la que separa el bug
/// del arreglo. Que las pantallas reales sigan escritas así lo custodian los
/// tests de `prioridad_en_carruseles_test.dart`.
void main() {
  testWidgets('el bug: sin refrescar al volver, queda el número viejo', (
    tester,
  ) async {
    final fuente = _Fuente();
    await tester.pumpWidget(_app(fuente, refrescaAlVolver: false));

    expect(find.text('54'), findsOneWidget);
    expect(fuente.lecturas, 1, reason: 'lo cargó al montarse');

    // "Ver todas" -> adoptar uno -> volver.
    await tester.tap(find.text('Ver todas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adoptar uno'));
    await tester.pumpAndSettle();

    expect(
      find.text('54'),
      findsOneWidget,
      reason: 'el panel se quedó con el número de cuando se abrió',
    );
    expect(
      fuente.lecturas,
      1,
      reason: 'nunca volvió a preguntar: initState no corre al volver',
    );
  });

  testWidgets('el arreglo: con .then vuelve a pedir al volver', (tester) async {
    final fuente = _Fuente();
    await tester.pumpWidget(_app(fuente, refrescaAlVolver: true));

    expect(find.text('54'), findsOneWidget);

    await tester.tap(find.text('Ver todas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adoptar uno'));
    await tester.pumpAndSettle();

    expect(find.text('53'), findsOneWidget, reason: 'el número se movió');
    expect(find.text('54'), findsNothing);
    expect(fuente.lecturas, 2, reason: 'preguntó de nuevo al volver');
  });

  // Volver sin haber cambiado nada igual re-pregunta. Es barato (son los
  // mismos contadores que ya se piden al abrir) y evita tener que adivinar
  // desde el panel si la otra pantalla tocó algo.
  testWidgets('volver sin cambiar nada no rompe ni muestra otra cosa', (
    tester,
  ) async {
    final fuente = _Fuente();
    await tester.pumpWidget(_app(fuente, refrescaAlVolver: true));

    await tester.tap(find.text('Ver todas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Volver sin tocar nada'));
    await tester.pumpAndSettle();

    expect(find.text('54'), findsOneWidget);
    expect(fuente.lecturas, 2);
  });
}

Widget _app(_Fuente fuente, {required bool refrescaAlVolver}) => MaterialApp(
  home: _Panel(fuente: fuente, refrescaAlVolver: refrescaAlVolver),
);

/// De dónde sale el número del panel. Anota cuántas veces se lo preguntaron,
/// que es lo que distingue "se refrescó" de "quedó el valor viejo".
class _Fuente {
  int valor = 54;
  int lecturas = 0;

  int leer() {
    lecturas++;
    return valor;
  }
}

/// El panel: carga el número al montarse y lo guarda en su State, como hace
/// `_refrescarNumeros()` con `_numeros`, `_jauria` y `_adoptadosCache`.
class _Panel extends StatefulWidget {
  const _Panel({required this.fuente, required this.refrescaAlVolver});
  final _Fuente fuente;
  final bool refrescaAlVolver;

  @override
  State<_Panel> createState() => _PanelState();
}

class _PanelState extends State<_Panel> {
  late int _numero;

  @override
  void initState() {
    super.initState();
    _numero = widget.fuente.leer();
  }

  void _refrescar() {
    if (!mounted) return;
    setState(() => _numero = widget.fuente.leer());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Text('$_numero'),
          TextButton(
            onPressed: () {
              final ida = Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => _VerTodas(widget.fuente)),
              );
              // La única diferencia entre las dos versiones.
              if (widget.refrescaAlVolver) ida.then((_) => _refrescar());
            },
            child: const Text('Ver todas'),
          ),
        ],
      ),
    );
  }
}

/// La otra pantalla, que sí puede cambiar el dato: es `mis_rescates_screen`,
/// que abre su propia hoja de cambiar estado.
class _VerTodas extends StatelessWidget {
  const _VerTodas(this.fuente);
  final _Fuente fuente;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        TextButton(
          onPressed: () {
            fuente.valor = 53;
            Navigator.of(context).pop();
          },
          child: const Text('Adoptar uno'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Volver sin tocar nada'),
        ),
      ],
    ),
  );
}
