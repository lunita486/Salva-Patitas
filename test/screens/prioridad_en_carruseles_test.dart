import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/data/creator_role.dart';
import 'package:salva_patitas/data/rescates_repository.dart';
import 'package:salva_patitas/domain/reglas_negocio.dart';

/// Los carruseles de vista previa muestran primero lo que necesita atención.
///
/// **La regresión.** Al paginar, la Jauría del albergue y "Tus rescates
/// activos" del rescatista pasaron a pedir UNA página de 10 ordenada por
/// `creadoEn` descendente, y recién después ordenaban por prioridad en Dart
/// sobre esos 10. O sea que un animalito en proceso de adopción publicado
/// hace meses no entraba en la página y no se veía NUNCA, aunque fuera justo
/// el que hay que mirar. Eliza: "en la Jauría ahora solo aparecen animales
/// en estado Rescatado".
///
/// El arreglo pide los prioritarios en su propia consulta y solo rellena con
/// el resto si sobra lugar.
void main() {
  late FakeFirebaseFirestore db;
  late RescatesRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = RescatesRepository(db: db);
  });

  /// [i] mayor = más reciente.
  Future<void> sembrar(int i, String estado, {String rol = 'albergue'}) =>
      db.collection('rescates').doc('a${i.toString().padLeft(3, '0')}').set({
        'nombre': 'Animal $i',
        'especie': 'Perro',
        'estadoAdopcion': estado,
        'rescatistaId': 'refugio',
        'creadoPor': rol,
        'creadoEn': Timestamp.fromDate(
          DateTime(2026, 1, 1).add(Duration(seconds: i)),
        ),
      });

  /// La misma mecánica de _cargarJauria: prioritarios primero, relleno
  /// después, y ordenado entre grupos.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> jauria({
    int cuantos = 10,
  }) async {
    final prio = await repo.paginaDeMisRescates(
      uid: 'refugio',
      role: CreatorRole.albergue,
      estados: estadosQueNecesitanAtencion,
      porPagina: cuantos,
    );
    final docs = [...prio.docs];
    if (docs.length < cuantos) {
      final resto = await repo.paginaDeMisRescates(
        uid: 'refugio',
        role: CreatorRole.albergue,
        estados: const ['Rescatado', 'Regresado', 'Fallecido'],
        porPagina: cuantos - docs.length,
      );
      docs.addAll(resto.docs);
    }
    docs.sort((a, b) {
      final pa = prioridadEstado(a.data()['estadoAdopcion'] as String?);
      final pb = prioridadEstado(b.data()['estadoAdopcion'] as String?);
      if (pa != pb) return pa.compareTo(pb);
      final ta = a.data()['creadoEn'] as Timestamp?;
      final tb = b.data()['creadoEn'] as Timestamp?;
      if (ta == null || tb == null) return 0;
      return tb.compareTo(ta);
    });
    return docs;
  }

  // EL caso de Eliza: 20 rescatados nuevos tapaban a los en proceso viejos.
  test('un "en proceso" viejo aparece igual, con 20 rescatados más nuevos',
      () async {
    await sembrar(0, 'En proceso de adopción'); // el más VIEJO de todos
    for (var i = 1; i <= 20; i++) {
      await sembrar(i, 'Rescatado');
    }
    final docs = await jauria();
    expect(docs.length, 10);
    expect(
      docs.first.id,
      'a000',
      reason: 'el que necesita atención tiene que ir primero, aunque sea viejo',
    );
  });

  test('los prioritarios van antes que el resto, siempre', () async {
    await sembrar(0, 'Hogar de paso');
    await sembrar(1, 'En proceso de adopción');
    for (var i = 2; i <= 12; i++) {
      await sembrar(i, 'Rescatado');
    }
    final docs = await jauria();
    final estados =
        docs.map((d) => d.data()['estadoAdopcion'] as String).toList();
    expect(estados[0], 'En proceso de adopción', reason: 'prioridad 0');
    expect(estados[1], 'Hogar de paso', reason: 'prioridad 1');
    expect(estados.skip(2).toSet(), {'Rescatado'});
  });

  test('con más prioritarios que lugares, no entra ningún relleno', () async {
    for (var i = 0; i < 12; i++) {
      await sembrar(i, 'En proceso de adopción');
    }
    for (var i = 20; i < 30; i++) {
      await sembrar(i, 'Rescatado');
    }
    final docs = await jauria();
    expect(docs.length, 10);
    expect(
      docs.map((d) => d.data()['estadoAdopcion']).toSet(),
      {'En proceso de adopción'},
    );
  });

  test('sin prioritarios, se llena entero con el resto', () async {
    for (var i = 0; i < 15; i++) {
      await sembrar(i, 'Rescatado');
    }
    final docs = await jauria();
    expect(docs.length, 10);
    // Y entre iguales, los más nuevos primero.
    expect(docs.first.id, 'a014');
  });

  test('fallecido va al final, pero no desaparece', () async {
    await sembrar(0, 'Fallecido');
    await sembrar(1, 'Rescatado');
    await sembrar(2, 'En proceso de adopción');
    final docs = await jauria();
    expect(docs.map((d) => d.id).toList(), ['a002', 'a001', 'a000']);
  });

  test('adoptado NUNCA entra: vive en su propia sección', () async {
    await sembrar(0, 'Rescatado');
    await sembrar(1, 'Adoptado');
    final docs = await jauria();
    expect(docs.map((d) => d.id), isNot(contains('a001')));
  });

  test('sin animalitos, no explota', () async {
    expect(await jauria(), isEmpty);
  });

  // La lista y el switch no pueden divergir: si alguien agrega un estado a
  // prioridad 0/1 y se olvida de la lista, el carrusel deja de mostrarlo
  // primero y nadie se entera.
  test('estadosQueNecesitanAtencion son exactamente los de prioridad < 2', () {
    for (final e in estadosQueNecesitanAtencion) {
      expect(prioridadEstado(e), lessThan(2), reason: '$e no es prioritario');
    }
    const todos = [
      'Rescatado',
      'Regresado',
      'En proceso de adopción',
      'Hogar de paso',
      'Adoptado',
      'Fallecido',
    ];
    for (final e in todos) {
      expect(
        prioridadEstado(e) < 2,
        estadosQueNecesitanAtencion.contains(e),
        reason: 'la lista y prioridadEstado discrepan en "$e"',
      );
    }
  });

  group('las dos pantallas piden por prioridad, no por fecha', () {
    String leer(String r) => File(r).readAsStringSync();

    test('la Jauría del albergue', () {
      final f = leer('lib/screens/albergue_home_screen.dart');
      expect(f, contains('estados: estadosQueNecesitanAtencion'));
      expect(f, contains('_cargarJauria()'));
    });

    test('y el carrusel del rescatista', () {
      final f = leer('lib/screens/home_screen.dart');
      expect(f, contains('estados: estadosQueNecesitanAtencion'));
      expect(f, contains('_cargarActivos()'));
    });

    // "Encontraron hogar" sale de _adoptadosCache, y lo unico que lo llena
    // es la consulta de adoptados. Si esa consulta viviera solo en
    // initState, marcar un animalito como Adoptado no lo haria aparecer
    // hasta recrear la pantalla — y como el panel del albergue es la
    // pantalla raiz de ese rol, initState no vuelve a correr al cambiar de
    // pestaña: hacia falta CERRAR SESION. Hallazgo real de Eliza con
    // Koreananchis.
    test('la consulta de adoptados vive dentro del refresco, no solo al abrir',
        () {
      final f = leer('lib/screens/albergue_home_screen.dart');
      final refresco = f.substring(
        f.indexOf('void _refrescarNumeros()'),
        f.indexOf('Widget build(BuildContext context)'),
      );
      expect(
        refresco,
        contains("estados: const ['Adoptado']"),
        reason: 'sin esto, "Encontraron hogar" no se actualiza al cambiar '
            'un animalito a Adoptado',
      );
      expect(
        refresco,
        contains('_adoptadosCache = p.docs'),
        reason: 'la consulta corre pero nadie usa el resultado',
      );
    });

    // Esa consulta se dispara y no se espera. Sin manejo de error, un
    // fallo de red deja una excepcion asincrona sin capturar: no rompe la
    // pantalla, pero se reporta a Crashlytics como error no manejado.
    test('la consulta de adoptados maneja su propio error', () {
      final f = leer('lib/screens/albergue_home_screen.dart');
      final refresco = f.substring(
        f.indexOf('void _refrescarNumeros()'),
        f.indexOf('Widget build(BuildContext context)'),
      );
      expect(
        refresco,
        contains('onError:'),
        reason: 'si falla la consulta, la excepcion queda sin capturar',
      );
    });

    // Los contadores se piden una sola vez al abrir; sin esto, cambiar un
    // estado desde el panel no movia ningun numero hasta salir y volver.
    test('cambiar el estado desde el panel refresca los contadores', () {
      final f = leer('lib/screens/albergue_home_screen.dart');
      // Los dos sheets que el panel abre por su cuenta.
      for (final i in 'CambiarEstadoSheet('.allMatches(f)) {
        expect(
          f.substring(i.end, i.end + 900),
          contains('.then((_) => _refrescarNumeros())'),
          reason: 'un sheet de cambiar estado que no refresca al cerrarse',
        );
      }
      expect('CambiarEstadoSheet('.allMatches(f).length, 2);
    });

    // El MISMO problema por la otra puerta, y este si llego a produccion.
    //
    // "Ver todas" lleva a mis_rescates_screen, que abre su propia
    // CambiarEstadoSheet. Al volver, el panel no se reconstruye: su State
    // sigue vivo debajo, con _jauria, _adoptadosCache y _numeros congelados
    // en lo que cargo initState. Eliza adoptaba desde ahi y el animalito no
    // aparecia en "Encontraron hogar", ni se movia el cuadrito azul de
    // Adoptados, por el resto de la sesion.
    //
    // Se recorren TODOS los push en vez de contar cuantos hay: asi, agregar
    // un quinto acceso a "Ver todas" sin el refresco rompe este test en vez
    // de pasar desapercibido.
    test('volver de "Ver todas" tambien refresca', () {
      final f = leer('lib/screens/albergue_home_screen.dart');
      final destinos = 'AppRoutes.misRescates'.allMatches(f).toList();
      expect(destinos, isNotEmpty, reason: 'no hay ningun acceso a Ver todas');
      for (final d in destinos) {
        expect(
          f.substring(d.end, d.end + 300),
          contains('.then((_) => _refrescarNumeros())'),
          reason: 'un acceso a "Ver todas" que no refresca al volver: el '
              'panel se queda con la lista y los numeros viejos',
        );
      }
    });

    // La MISMA puerta, por el otro lado, y esta llego a produccion.
    //
    // Desde Solicitudes se APRUEBA, y aprobar cambia el estado del
    // animalito: 'Hogar de paso' o 'En proceso de adopcion'. Sin el
    // refresco al volver, el panel se quedaba con el estado anterior.
    // Hallazgo de Eliza probando el flujo de hogar de paso: el adoptante lo
    // veia como Hogar de paso (el feed es un stream en vivo) y el
    // rescatista lo seguia viendo como Rescatado (su carrusel es un .get()
    // pedido una sola vez, al abrir).
    //
    // Cuando se agrego el `.then` a los cuatro accesos a "Ver todas", estos
    // seis quedaron afuera. Por eso se recorren TODOS en vez de contarlos.
    test('volver de Solicitudes tambien refresca, en los dos paneles', () {
      for (final (ruta, refresco) in [
        ('lib/screens/home_screen.dart', '_refrescarRescates'),
        ('lib/screens/albergue_home_screen.dart', '_refrescarNumeros'),
      ]) {
        final f = leer(ruta);
        final destinos = 'AppRoutes.solicitudesRescatista'.allMatches(f).toList();
        expect(destinos, isNotEmpty, reason: 'no hay accesos a Solicitudes en $ruta');
        for (final d in destinos) {
          expect(
            f.substring(d.end, d.end + 300),
            contains('.then((_) => $refresco())'),
            reason: 'un acceso a Solicitudes que no refresca al volver, en '
                '$ruta: el panel se queda con el estado anterior del '
                'animalito que se acaba de aprobar',
          );
        }
      }
    });

    // El panel del rescatista nunca tuvo el problema, y es de donde salio
    // el patron. Si alguien se lo saca, que se entere aca.
    test('el panel del rescatista sigue haciendo lo mismo', () {
      final f = leer('lib/screens/home_screen.dart');
      final d = 'AppRoutes.misRescates'.allMatches(f).toList();
      expect(d, isNotEmpty);
      expect(
        f.substring(d.first.end, d.first.end + 300),
        contains('.then((_) => _refrescarRescates())'),
      );
    });
  });

  // ── Que el patrón de arriba de verdad contenga el error ────────────────
  //
  // El test anterior mira que `onError:` esté escrito. Este comprueba que
  // esa forma HACE lo que se espera: una consulta que falla y se dispara sin
  // esperar no debe dejar una excepción suelta en la zona.
  group('un .then que se dispara sin esperar', () {
    Future<int> consultaQueFalla() async => throw StateError('sin señal');

    test('SIN onError, el error se escapa a la zona', () async {
      final escapados = <Object>[];
      await runZonedGuarded(() async {
        // ignore: unawaited_futures
        consultaQueFalla().then((_) {});
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }, (e, _) => escapados.add(e));
      expect(escapados, hasLength(1), reason: 'así estaba antes del arreglo');
    });

    test('CON onError, no se escapa nada', () async {
      final escapados = <Object>[];
      await runZonedGuarded(() async {
        // ignore: unawaited_futures
        consultaQueFalla().then((_) {}, onError: (Object _) {});
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }, (e, _) => escapados.add(e));
      expect(escapados, isEmpty);
    });
  });
}