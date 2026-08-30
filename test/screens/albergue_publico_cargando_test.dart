import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El perfil público del albergue no puede decir "0" mientras no sabe.
///
/// **El problema.** Los dos contadores mostraban `0` antes de que llegara la
/// consulta, y el grid decía "No hay animales disponibles por ahora". Los
/// tres son afirmaciones falsas: el dato todavía no había llegado. Eliza:
/// "el 0 inicial es especialmente molesto porque no significa que haya 0
/// animales: significa que todavía no terminó de cargar el dato".
///
/// Se comprueba leyendo el código porque montar esta pantalla necesita
/// Firebase, y lo que hay que custodiar es que nadie vuelva a poner un
/// `?? 0` en un contador que puede estar cargando.
void main() {
  final fuente = File(
    'lib/screens/albergue_publico_screen.dart',
  ).readAsStringSync();

  test('los contadores distinguen "cargando" de "cero"', () {
    expect(
      fuente,
      contains('final cargando = !rSnap.hasData;'),
      reason: 'sin esta distinción no se puede saber si el 0 es real',
    );
  });

  test('el contador de disponibles no cae a 0 mientras carga', () {
    expect(
      fuente,
      contains("cargando ? _cargandoValor : '\${disponibles.length}'"),
    );
  });

  test('el de adoptados tampoco', () {
    expect(fuente, contains("s.hasData ? '\${s.data}' : _cargandoValor"));
    expect(
      fuente,
      isNot(contains("'\${s.data ?? 0}'")),
      reason: 'volvió el ?? 0: muestra un cero que no es un dato',
    );
  });

  test('mientras carga no se afirma que no hay animales', () {
    // El "No hay animales" tiene que estar detrás del else de `cargando`,
    // no colgado solo de que la lista esté vacía.
    final iCargando = fuente.indexOf('if (cargando)');
    final iVacio = fuente.indexOf('else if (disponibles.isEmpty)');
    expect(iCargando, isNot(-1), reason: 'no hay estado de carga en el grid');
    expect(
      iVacio,
      greaterThan(iCargando),
      reason: 'el mensaje de vacío no está protegido por el estado de carga',
    );
  });

  test('el marcador de carga no es un número', () {
    final m = RegExp(r"static const _cargandoValor = '(.*)';").firstMatch(fuente);
    expect(m, isNotNull, reason: 'no existe el marcador de carga');
    expect(
      int.tryParse(m!.group(1)!),
      isNull,
      reason: 'el marcador se lee como un dato real si es un número',
    );
  });
}
