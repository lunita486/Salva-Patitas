import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/domain/tareas_en_paralelo.dart';

/// Que subir un lote no deje lugares vacíos esperando al más lento.
///
/// Antes se publicaba en tandas fijas de 3: se esperaba a que terminaran los
/// tres antes de empezar los tres siguientes. Con fotos de tamaños distintos
/// —lo normal— un animal pesado dejaba los otros dos lugares ociosos.
///
/// Los tests usan Completer y no esperas de tiempo a propósito: el orden
/// queda decidido por el test, no por el reloj, así que no puede fallar de
/// vez en cuando por ir lento la máquina.
void main() {
  test('todas las tareas se corren, una sola vez cada una', () async {
    final corridas = <int>[];
    await correrConLimite(
      cuantas: 7,
      limite: 3,
      tarea: (i) async => corridas.add(i),
    );
    corridas.sort();
    expect(corridas, [0, 1, 2, 3, 4, 5, 6]);
  });

  test('nunca hay más de `limite` en curso a la vez', () async {
    var enCurso = 0;
    var pico = 0;
    await correrConLimite(
      cuantas: 20,
      limite: 3,
      tarea: (_) async {
        enCurso++;
        if (enCurso > pico) pico = enCurso;
        await Future<void>.delayed(Duration.zero);
        enCurso--;
      },
    );
    expect(pico, lessThanOrEqualTo(3), reason: 'el techo de memoria es esto');
  });

  // EL test de este cambio. Con tandas fijas, la tarea 3 no podía arrancar
  // hasta que terminaran 0, 1 y 2. Acá 0 se queda colgada (la foto pesada) y
  // 1 y 2 terminan: la 3 TIENE que entrar igual.
  test('un lugar que se libera se ocupa aunque el más lento siga', () async {
    final frenos = List.generate(4, (_) => Completer<void>());
    final arrancaron = <int>[];

    final todo = correrConLimite(
      cuantas: 4,
      limite: 3,
      tarea: (i) async {
        arrancaron.add(i);
        await frenos[i].future;
      },
    );

    await Future<void>.delayed(Duration.zero);
    expect(arrancaron, [0, 1, 2], reason: 'arrancan 3, que es el límite');

    // Terminan las dos rápidas. La 0 sigue trabada, como la foto pesada.
    frenos[1].complete();
    frenos[2].complete();
    await Future<void>.delayed(Duration.zero);

    expect(
      arrancaron,
      contains(3),
      reason: 'con tandas fijas la 4ª esperaba a que la 0 terminara',
    );

    frenos[0].complete();
    frenos[3].complete();
    await todo;
  });

  test('una lista vacía no explota', () async {
    await correrConLimite(cuantas: 0, limite: 3, tarea: (_) async {});
  });

  test('menos tareas que el límite: no se abren trabajadores de más', () async {
    var trabajos = 0;
    await correrConLimite(
      cuantas: 2,
      limite: 5,
      tarea: (_) async => trabajos++,
    );
    expect(trabajos, 2);
  });

  test('un límite absurdo no deja el lote sin correr', () async {
    final corridas = <int>[];
    await correrConLimite(
      cuantas: 3,
      limite: 0,
      tarea: (i) async => corridas.add(i),
    );
    expect(corridas, [0, 1, 2]);
  });
}
