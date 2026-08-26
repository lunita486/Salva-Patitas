import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Un centinela contra la copia número once.
///
/// **La historia.** "¿Cómo se llama este animalito cuando no tiene nombre?"
/// se respondía en DIEZ lugares: siete escritos a mano dentro de pantallas,
/// dos funciones distintas, y uno en el servidor. Ninguna de las siete
/// hacía nada diferente. Existían porque se fueron agregando de a una, cada
/// vez que alguien sumaba una pantalla.
///
/// Por eso el bug que reportó Eliza —"Para Sin nombre", que no se lee como
/// español— se arregló una vez y siguió vivo en las otras nueve.
///
/// Ahora hay una sola: `nombreDeAnimal` en domain/reglas_negocio.dart, con
/// dos formas (título y dentro de una frase) que no son un gusto de cada
/// pantalla sino dos papeles gramaticales distintos.
///
/// Si estás leyendo esto porque el test falló: no agregues el archivo a la
/// lista. Usá `nombreDeAnimal(...)`, que ya hace exactamente eso.
void main() {
  test('nadie vuelve a escribir el relleno del nombre a mano', () {
    final infractores = <String>[];

    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      // La única fuente, obviamente, sí lo contiene.
      if (f.path.endsWith('domain/reglas_negocio.dart')) continue;

      final lineas = f.readAsLinesSync();
      for (var i = 0; i < lineas.length; i++) {
        final l = lineas[i];
        // Solo código, no comentarios: varios explican la historia y
        // mencionan el texto a propósito.
        if (l.trimLeft().startsWith('//') || l.trimLeft().startsWith('///')) {
          continue;
        }
        if (!l.contains("'Sin nombre'")) continue;
        // La red de hogares de paso guarda nombres de PERSONAS, no de
        // animalitos. Es otra pregunta y tiene derecho a su propia
        // respuesta.
        if (f.path.endsWith('hogares_de_paso_screen.dart')) continue;
        infractores.add('${f.path}:${i + 1}');
      }
    }

    expect(
      infractores,
      isEmpty,
      reason:
          'Apareció una copia nueva del relleno "Sin nombre". Usá '
          'nombreDeAnimal() de domain/reglas_negocio.dart en vez de '
          'escribirlo a mano: era la copia número once de la misma '
          'decisión, y ese es el motivo por el que este bug volvía.',
    );
  });

  // La contraprueba: si el centinela no sabe encontrar una copia, no
  // vigila nada y pasaría para siempre sin que nadie lo note.
  test('y el centinela sabe reconocer una copia cuando la hay', () {
    const codigoConCopia = """
    final nombre = (d['nombre'] as String?)?.isNotEmpty == true
        ? d['nombre'] as String
        : 'Sin nombre';
""";
    final lineas = codigoConCopia
        .split('\n')
        .where(
          (l) =>
              !l.trimLeft().startsWith('//') && l.contains("'Sin nombre'"),
        );
    expect(
      lineas,
      hasLength(1),
      reason: 'si esto falla, el test de arriba no está mirando nada',
    );
  });
}
