import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// La guarda de reentrada al pedir páginas.
///
/// **El defecto.** `_alDesplazar` se dispara en CADA evento de scroll, muchos
/// por segundo. La única guarda era `!_hayMas`, así que estando cerca del
/// final cada evento abría una página. Y peor: `_abrirPagina` agrega la
/// página vacía sincrónicamente, así que la llamada siguiente veía esa vacía,
/// no encontraba cursor, y volvía a abrir la ventana de la PÁGINA 1. El
/// deduplicado tapaba las tarjetas repetidas, así que no se veía: se pagaba
/// en lecturas de Firestore y en listeners.
///
/// Este test reproduce la máquina de estados de `_abrirPagina` sin Firebase
/// ni widgets: lo que importa es cuántas suscripciones se abren ante N
/// llamadas seguidas, y que la guarda se libere por los dos caminos (el
/// snapshot que llega bien, y el error).
void main() {
  late int aperturas;
  late bool pidiendo;
  late bool hayMas;
  late List<List<int>> paginas;

  setUp(() {
    aperturas = 0;
    pidiendo = false;
    hayMas = true;
    paginas = [];
  });

  /// La misma forma que `_abrirPagina`: guarda, agregar la página vacía,
  /// abrir la suscripción.
  void abrirPagina() {
    if (pidiendo) return;
    if (!hayMas && paginas.isNotEmpty) return;
    pidiendo = true;
    paginas.add(const []);
    aperturas++;
  }

  /// Lo que hace el `listen` cuando llega el primer snapshot.
  void llegaSnapshot({bool llena = true}) {
    pidiendo = false;
    paginas[paginas.length - 1] = List.filled(llena ? 20 : 5, 0);
    hayMas = llena;
  }

  void llegaError() => pidiendo = false;

  test('20 eventos de scroll seguidos abren UNA sola página', () {
    for (var i = 0; i < 20; i++) {
      abrirPagina();
    }
    expect(aperturas, 1, reason: 'se abrió una página por evento de scroll');
    expect(paginas.length, 1);
  });

  test('recién cuando llega el snapshot se puede abrir la siguiente', () {
    abrirPagina();
    for (var i = 0; i < 10; i++) {
      abrirPagina();
    }
    expect(aperturas, 1);

    llegaSnapshot();
    abrirPagina();
    expect(aperturas, 2, reason: 'con la guarda liberada sí abre la siguiente');
  });

  test('un error también libera la guarda: la lista no queda trabada', () {
    abrirPagina();
    llegaError();
    abrirPagina();
    expect(
      aperturas,
      2,
      reason: 'si el error no liberara, no se podría pedir nada más nunca',
    );
  });

  test('cuando ya no hay más, deja de abrir', () {
    abrirPagina();
    llegaSnapshot(llena: false); // página a medias = última
    for (var i = 0; i < 5; i++) {
      abrirPagina();
    }
    expect(aperturas, 1);
  });

  // El corazón del defecto: sin guarda, la segunda llamada veía la página
  // vacía recién agregada, no encontraba cursor y reabría la página 1.
  test('ninguna página se abre con cursor nulo salvo la primera', () {
    List<int>? cursorDe() {
      final anterior = paginas.isEmpty ? null : paginas.last;
      return (anterior == null || anterior.isEmpty) ? null : anterior;
    }

    final cursores = <List<int>?>[];
    void abrirRegistrando() {
      if (pidiendo) return;
      if (!hayMas && paginas.isNotEmpty) return;
      pidiendo = true;
      cursores.add(cursorDe());
      paginas.add(const []);
    }

    for (var i = 0; i < 5; i++) {
      abrirRegistrando();
    }
    llegaSnapshot();
    for (var i = 0; i < 5; i++) {
      abrirRegistrando();
    }

    expect(cursores.length, 2, reason: 'se abrieron páginas de más');
    expect(cursores[0], isNull, reason: 'la primera no lleva cursor');
    expect(
      cursores[1],
      isNotNull,
      reason: 'sin guarda, esta reabría la página 1 con cursor nulo',
    );
  });

  test('cancelar las suscripciones no deja la guarda trabada', () async {
    final ctl = StreamController<int>();
    var recibidos = 0;
    final sub = ctl.stream.listen((_) => recibidos++);
    abrirPagina();
    await sub.cancel();
    // Lo que hacen _recargar() y dispose(): cerrar y dejar la guarda limpia.
    pidiendo = false;
    ctl.add(1);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(recibidos, 0, reason: 'llegó algo después de cancelar');
    abrirPagina();
    expect(aperturas, 2, reason: 'la guarda quedó trabada tras cancelar');
    await ctl.close();
  });
}
