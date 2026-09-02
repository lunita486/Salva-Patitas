import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Que el filtro con el que se abre "Mis rescates" llegue de verdad a la
/// primera consulta.
///
/// **Por qué existe.** El panel del albergue tiene dos botones "Gestionar"
/// que llevan a la MISMA pantalla y tienen que mostrar cosas distintas:
///
///   · "LA JAURÍA"          → la lista sin filtro
///   · "ENCONTRARON HOGAR"  → la lista filtrada por Adoptado
///
/// Los dos pasaban lo correcto desde siempre. Lo que estaba roto era el
/// orden en `initState` de la pantalla: `_recargar()` corría ANTES de
/// asignar `_filtroEstado`, y como la consulta se arma sincrónicamente
/// adentro, la primera página salía SIN filtrar mientras el chip aparecía
/// seleccionado. Asignarlo después no recargaba nada.
///
/// Resultado: los dos botones se veían iguales. Eliza lo notó como
/// redundancia entre las dos secciones, y la causa era esta.
///
/// Se comprueba leyendo el código porque las dos mitades viven en pantallas
/// que necesitan Firebase para montarse, y lo que hay que custodiar es una
/// relación entre dos líneas, no un comportamiento de widget.
void main() {
  String leer(String ruta) => File(ruta).readAsStringSync();

  /// El archivo sin NINGÚN espacio. Lo que se custodia acá es qué `extra`
  /// lleva cada acceso, no cómo lo parte el formateador: cuando esos push
  /// pasaron a encadenar un `.then` para refrescar al volver, `dart format`
  /// repartió el `extra:` en varias líneas y estos dos tests se rompieron
  /// sin que el comportamiento hubiera cambiado en nada.
  String leerApretado(String ruta) =>
      leer(ruta).replaceAll(RegExp(r'\s'), '');

  test('"Encontraron hogar" abre la lista filtrada por Adoptado', () {
    final fuente = leerApretado('lib/screens/albergue_home_screen.dart');
    expect(
      fuente,
      contains("extra:(filtroInicial:'Adoptado',esAlbergue:true"),
      reason:
          'sin esto, "Encontraron hogar" y "La Jauría" abren exactamente lo '
          'mismo y la sección de adoptados no lleva a ningún lado propio',
    );
  });

  test('"La Jauría" sigue abriendo la lista sin filtro', () {
    final fuente = leerApretado('lib/screens/albergue_home_screen.dart');
    expect(
      fuente,
      contains('extra:(filtroInicial:null,esAlbergue:true'),
      reason: 'la Jauría muestra todo, no un estado en particular',
    );
  });

  // La mitad que de verdad estaba rota.
  test('el filtro inicial se asigna ANTES de la primera consulta', () {
    final fuente = leer('lib/screens/mis_rescates_screen.dart');
    // Sin los comentarios: el de arriba de esas dos líneas NOMBRA a
    // _recargar() para explicar por qué el orden importa, y buscarlo en el
    // texto crudo encontraba esa mención en vez de la llamada. Lo aprendí
    // porque este test falló con el código ya correcto.
    final initState = fuente
        .substring(
          fuente.indexOf('void initState()'),
          fuente.indexOf('void dispose()'),
        )
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    final asignacion = initState.indexOf('_filtroEstado = widget.filtroInicial');
    final recarga = initState.indexOf('_recargar();');

    expect(asignacion, isNot(-1), reason: 'ya no se asigna el filtro inicial');
    expect(recarga, isNot(-1), reason: 'ya no se recarga al abrir');
    expect(
      asignacion,
      lessThan(recarga),
      reason:
          'la consulta se arma sincrónicamente dentro de _recargar(): si el '
          'filtro se asigna después, la primera página sale sin filtrar y '
          'nada la vuelve a pedir',
    );
  });
}
