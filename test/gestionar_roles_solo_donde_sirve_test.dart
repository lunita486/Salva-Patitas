import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// "Gestionar mis roles" solo donde de verdad hace algo.
///
/// **Por qué existe este centinela.** La hoja de roles
/// (widgets/roles_sheet.dart) solo ofrece Adoptante y Rescatista: no tiene
/// casilla para Albergue ni para Aliado, y arranca copiando los roles que ya
/// están, así que desde una cuenta de negocio solo se pueden AGREGAR roles,
/// nunca salir del de negocio.
///
/// Y agregarlos no cambia nada: `resolverPantallaPerfil` manda a albergue y
/// a aliado antes que a cualquier otro rol, así que después de guardar se
/// vuelve a aterrizar en la misma pantalla.
///
/// El botón estuvo un rato en los dos home de negocio, puesto justamente
/// para dar esa salida, y hubo que sacarlo porque no la daba. Eliza:
/// "¿por qué el albergue tiene la opción de gestionar mis roles? Esto no
/// está bien".
///
/// **Si este test falla porque agregaste el botón:** no alcanza con
/// agregarlo. Primero hay que hacer que la hoja o el enrutado permitan
/// salir del rol de negocio, o vuelve a ser un botón que no hace nada.
void main() {
  String leer(String ruta) => File(ruta).readAsStringSync();

  const ofrece = 'gestionarRoles';

  test('el perfil de Adoptante sigue ofreciéndolo', () {
    expect(
      leer('lib/screens/perfil_adoptante_screen.dart'),
      contains("$ofrece(context, rolFallback: 'adoptante')"),
    );
  });

  test('el perfil de Rescatista sigue ofreciéndolo', () {
    expect(
      leer('lib/screens/perfil_rescatista_screen.dart'),
      contains("$ofrece(context, rolFallback: 'rescatista')"),
    );
  });

  test('el home de Albergue NO lo ofrece', () {
    expect(
      leer('lib/screens/albergue_home_screen.dart'),
      isNot(contains('$ofrece(')),
      reason: 'desde el albergue ese flujo no puede sacar el rol de albergue',
    );
  });

  test('el home de Aliado NO lo ofrece', () {
    expect(
      leer('lib/screens/aliado_home_screen.dart'),
      isNot(contains('$ofrece(')),
      reason: 'desde el aliado ese flujo no puede sacar el rol de aliado',
    );
  });

  // La razón de fondo, escrita como test: mientras la hoja no ofrezca las
  // casillas de negocio, ofrecerla desde esas pantallas es engañoso.
  test('la hoja de roles sigue sin ofrecer albergue ni aliado', () {
    final hoja = leer('lib/widgets/roles_sheet.dart');
    final tiles = RegExp(r"_rolTile\(\s*'(\w+)'").allMatches(hoja)
        .map((m) => m.group(1))
        .toSet();
    expect(
      tiles,
      {'adoptante', 'rescatista'},
      reason:
          'si la hoja YA ofrece albergue/aliado, revisá si conviene volver a '
          'mostrar el botón en esas pantallas: el motivo para sacarlo era '
          'justamente que no estaban',
    );
  });
}
