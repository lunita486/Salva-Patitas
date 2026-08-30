import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Los dos números del perfil del rescatista ("Animales rescatados" y
/// "Adopciones aprobadas") se piden al montar, no cuando el árbol los lee.
///
/// **Ojo con lo que prueba esto.** A diferencia del perfil público del
/// albergue, acá el cambio NO arregla una demora que existiera: el widget de
/// las cifras no está anidado adentro de ningún builder que espere otra
/// cosa, así que su `build` corre en el primer cuadro y las dos consultas ya
/// salían enseguida. Esto es una defensa.
///
/// Lo que defiende: `late final _x = consulta(...)` quiere decir "sale la
/// primera vez que alguien lo lea". Con eso, alcanza con que mañana alguien
/// envuelva estas cifras en un StreamBuilder para que las consultas pasen a
/// hacer fila detrás de ese stream, y el diff no lo deja ver. En
/// `albergue_publico_screen.dart` pasó exactamente eso y terminó en una
/// demora que reportó Eliza. Con la asignación en `initState` esa regresión
/// no se puede colar sin tocar estos tests.
///
/// El mecanismo, con widgets de verdad, está probado en
/// `albergue_publico_contadores_arrancan_test.dart`. Acá se custodia la
/// forma del código, porque montar esta pantalla necesita Firebase.
void main() {
  final fuente = File(
    'lib/screens/perfil_rescatista_screen.dart',
  ).readAsStringSync();

  /// El archivo sin las líneas de comentario. Hace falta: los comentarios de
  /// esta pantalla citan textualmente el código viejo para explicar por qué
  /// se fue, así que buscar el defecto en el archivo entero lo encuentra en
  /// la explicación de por qué ya no está.
  final codigo = fuente
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  /// El cuerpo de `initState`, que termina donde arranca el `@override`
  /// siguiente (`build`).
  String cuerpoDeInitState() {
    final desde = fuente.indexOf('void initState()');
    expect(desde, isNot(-1), reason: 'no hay initState');
    final hasta = fuente.indexOf('@override', desde);
    expect(hasta, greaterThan(desde));
    return fuente.substring(desde, hasta);
  }

  test('los números se piden en initState', () {
    expect(
      cuerpoDeInitState(),
      contains('_numeros = Future.wait('),
      reason: 'si no arranca acá, vuelve a salir recién cuando el árbol lo lea',
    );
  });

  test('y no vuelven a quedar con inicializador perezoso', () {
    expect(codigo, contains('late final Future<List<int>> _numeros;'));
    expect(
      codigo,
      isNot(contains('late final Future<List<int>> _numeros =')),
      reason: 'con inicializador la consulta depende de cuándo se lea',
    );
  });

  // El cambio es de CUÁNDO, no de QUÉ. Estos custodian que no se haya colado
  // nada más en el camino.
  test('no cambió qué cuentan', () {
    expect(
      'RescatesRepository().contar('.allMatches(codigo).length,
      2,
      reason: 'siguen siendo exactamente dos conteos, ni uno más',
    );
    expect(
      'role: CreatorRole.rescatista'.allMatches(codigo).length,
      2,
      reason: 'los dos son del rescatista, no de otro rol',
    );
    expect(
      "estados: const ['Adoptado']".allMatches(codigo).length,
      1,
      reason: 'solo el segundo filtra por estado, como antes',
    );
  });

  // El defecto anterior de esta pantalla, que no hay que reintroducir: los
  // números salían de `snapshot.docs.length` sobre la consulta COMPLETA, o
  // sea que pintar "12 animales rescatados" descargaba los 12 documentos, y
  // con 100.000 habría descargado 100.000.
  test('siguen siendo conteos del servidor, no la colección entera', () {
    expect(
      codigo,
      isNot(contains('.docs.length')),
      reason: 'volvió a contar documentos descargados en vez de usar contar()',
    );
  });
}
