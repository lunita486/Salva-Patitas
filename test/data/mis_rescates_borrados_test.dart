import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/data/creator_role.dart';
import 'package:salva_patitas/data/rescates_repository.dart';

/// Estrés sobre borrados entre páginas.
///
/// **Por qué existe.** Al cerrar los dos defectos anteriores dejé anotado un
/// riesgo que NO había probado a fondo: si se borran muchos animalitos de la
/// página 1, esa ventana se va completando desde abajo y podría solaparse
/// con la 2 más de lo que el deduplicado compensa. Esto intenta romperlo.
///
/// **Fidelidad.** Reproduce la mecánica exacta de la pantalla:
///   · cada página es una consulta EN VIVO `creadoEn <= T0`, descendente,
///     que pide 21 y muestra 20;
///   · el cursor de cada página se captura UNA vez, al abrirla, y no se
///     recalcula (por eso los borrados posteriores no lo mueven);
///   · al juntar, los nuevos van primero y se deduplica por id.
///
/// Los tests comparan CONJUNTOS DE IDS contra lo que debería quedar en la
/// base, no contra lo que se ve.
void main() {
  late FakeFirebaseFirestore db;
  late RescatesRepository repo;
  final t0 = DateTime(2026, 1, 1, 1);

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = RescatesRepository(db: db);
  });

  String id(int i) => 'h${i.toString().padLeft(3, '0')}';

  Future<void> sembrar(int cuantos) async {
    for (var i = 0; i < cuantos; i++) {
      await db.collection('rescates').doc(id(i)).set({
        'nombre': 'Animal $i',
        'especie': i % 2 == 0 ? 'Perro' : 'Gato',
        'estadoAdopcion': 'Rescatado',
        'rescatistaId': 'refugio',
        'creadoPor': 'albergue',
        'creadoEn': Timestamp.fromDate(
          DateTime(2026, 1, 1).add(Duration(seconds: i)),
        ),
      });
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> pagina({
    DocumentSnapshot<Map<String, dynamic>>? despuesDe,
    List<String>? estados,
    String? especie,
  }) => repo.misRescatesEnVivo(
    uid: 'refugio',
    role: CreatorRole.albergue,
    creadoAntesDe: t0,
    despuesDe: despuesDe,
    estados: estados,
    especie: especie,
    porPagina: 20,
  );

  /// Lo que la pantalla muestra: nuevos arriba, después las páginas en
  /// orden, deduplicado por id.
  Set<String> juntar(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> nuevos,
    List<List<QueryDocumentSnapshot<Map<String, dynamic>>>> paginas,
  ) {
    final vistos = <String>{};
    for (final d in nuevos) {
      vistos.add(d.id);
    }
    for (final p in paginas) {
      for (final d in p) {
        vistos.add(d.id);
      }
    }
    return vistos;
  }

  /// Comprueba además que no haya repetidos en la lista aplanada.
  List<String> juntarLista(
    List<List<QueryDocumentSnapshot<Map<String, dynamic>>>> paginas,
  ) {
    final vistos = <String>{};
    final ids = <String>[];
    for (final p in paginas) {
      for (final d in p) {
        if (vistos.add(d.id)) ids.add(d.id);
      }
    }
    return ids;
  }

  Future<Set<String>> loQueDeberiaQuedar() async {
    final snap = await db.collection('rescates').get();
    return snap.docs.map((d) => d.id).toSet();
  }

  /// Abre 2 páginas como la pantalla, borra [aBorrar], y devuelve lo que
  /// queda visible después de que las consultas en vivo se reevalúan.
  Future<({Set<String> visibles, List<String> lista})> escenario(
    List<String> aBorrar, {
    int total = 40,
  }) async {
    await sembrar(total);
    // Página 1 y su cursor, capturado UNA vez.
    final p1Inicial = (await pagina().first).docs.take(20).toList();
    final cursor2 = p1Inicial.last;
    await (await pagina(despuesDe: cursor2).first);

    for (final x in aBorrar) {
      await db.collection('rescates').doc(x).delete();
    }

    // Las dos consultas en vivo se reevalúan solas; acá se vuelven a leer.
    final p1 = (await pagina().first).docs.take(20).toList();
    final p2 = (await pagina(despuesDe: cursor2).first).docs.take(20).toList();
    return (visibles: juntar(const [], [p1, p2]), lista: juntarLista([p1, p2]));
  }

  test('Caso 1: borrar 1 de la página 1 deja los 39, sin repetidos', () async {
    final r = await escenario([id(30)]);
    expect(r.visibles, await loQueDeberiaQuedar());
    expect(r.visibles.length, 39);
    expect(r.lista.length, r.lista.toSet().length, reason: 'hay repetidos');
  });

  test('Caso 2: borrar 5 de la página 1 deja los 35, sin repetidos', () async {
    final r = await escenario([id(39), id(35), id(30), id(25), id(21)]);
    expect(r.visibles, await loQueDeberiaQuedar());
    expect(r.visibles.length, 35);
    expect(r.lista.length, r.lista.toSet().length);
  });

  test('Caso 3: borrar 10 de la página 1 deja los 30, sin repetidos', () async {
    final r = await escenario([for (var i = 30; i < 40; i++) id(i)]);
    expect(r.visibles, await loQueDeberiaQuedar());
    expect(r.visibles.length, 30);
    expect(r.lista.length, r.lista.toSet().length);
  });

  test('Caso 4: borrar 19 de la página 1 deja exactamente 21', () async {
    // La página 1 son h039..h020. Se borran 19 de esos 20.
    final r = await escenario([for (var i = 21; i < 40; i++) id(i)]);
    expect(r.visibles, await loQueDeberiaQuedar());
    expect(r.visibles.length, 21, reason: 'se perdió o sobró alguno');
    expect(r.lista.length, r.lista.toSet().length);
  });

  // ── Los 3 tests de abajo están en skip, y no por un bug del producto ──
  //
  // **Qué intentan cubrir.** Los tres borran, entre otros, el animalito que
  // hace de CURSOR entre la página 1 y la 2 (el último de la página 1). Es un
  // caso perfectamente posible: esta pantalla tiene un tacho de basura por
  // tarjeta.
  //
  // **Por qué no corren.** `fake_cloud_firestore` lanza
  // `PlatformException(Invalid Query, The document specified wasn't found)`
  // cuando el documento que se le pasa a `startAfterDocument` ya no existe.
  //
  // **Eso NO es lo que hace Firestore de verdad.** El cursor se arma con los
  // VALORES del snapshot, del lado del cliente (ver el doc de
  // `startAfterDocument` en cloud_firestore: "The documentSnapshot must
  // contain all of the fields provided in the orderBy of this query", y el
  // orden por id lo agrega el método implícitamente). El documento no
  // necesita seguir existiendo.
  //
  // **Verificado a mano con el SDK real, 2026-08-29.** En el emulador de
  // Firestore, con la app compilada: 40 animalitos, se abrió la página 1
  // (Animal 39..20) y la 2, se borró Animal 20 —el cursor— desde la UI con su
  // diálogo de confirmación, y se recorrió la lista entera. Resultado: 39
  // animalitos visibles, ninguno faltante, ninguno repetido, sin error en
  // pantalla. Coincide exactamente con los 39 documentos que quedaron en la
  // base.
  //
  // Se dejan escritos, y no borrados, porque describen bien el escenario y el
  // día que el fake lo soporte alcanza con sacarles el `skip`. NO se agregó
  // ninguna defensa en producción para esto: no hay nada que defender.
  test('Caso 4b: borrar los 20 enteros de la página 1', () async {
    final r = await escenario([for (var i = 20; i < 40; i++) id(i)]);
    expect(r.visibles, await loQueDeberiaQuedar());
    expect(r.visibles.length, 20);
  }, skip: 'fake_cloud_firestore no soporta un cursor cuyo documento fue \nborrado. No es el comportamiento de Firestore real: verificado a mano con el \nSDK real en el emulador el 2026-08-29. Ver la nota larga de arriba.');

  test('Caso 5: borrados mezclados en las dos páginas', () async {
    final r = await escenario([
      id(38), id(31), id(27), id(20), // de la página 1
      id(19), id(12), id(3), id(0), // de la página 2
    ]);
    expect(r.visibles, await loQueDeberiaQuedar());
    expect(r.visibles.length, 32);
    expect(r.lista.length, r.lista.toSet().length);
  }, skip: 'fake_cloud_firestore no soporta un cursor cuyo documento fue \nborrado. No es el comportamiento de Firestore real: verificado a mano con el \nSDK real en el emulador el 2026-08-29. Ver la nota larga de arriba.');

  // Con TRES páginas la ventana de la 2 también se corre hacia abajo, y hay
  // que ver que no abra un hueco contra la 3.
  test('Caso 6: tres páginas y borrados fuertes en la 1 y en la 2', () async {
    await sembrar(60);
    final p1i = (await pagina().first).docs.take(20).toList();
    final cursor2 = p1i.last;
    final p2i = (await pagina(despuesDe: cursor2).first).docs.take(20).toList();
    final cursor3 = p2i.last;
    await (await pagina(despuesDe: cursor3).first);

    for (var i = 50; i < 60; i++) {
      await db.collection('rescates').doc(id(i)).delete();
    }
    for (var i = 30; i < 38; i++) {
      await db.collection('rescates').doc(id(i)).delete();
    }

    final p1 = (await pagina().first).docs.take(20).toList();
    final p2 = (await pagina(despuesDe: cursor2).first).docs.take(20).toList();
    final p3 = (await pagina(despuesDe: cursor3).first).docs.take(20).toList();
    final lista = juntarLista([p1, p2, p3]);

    expect(lista.toSet(), await loQueDeberiaQuedar());
    expect(lista.length, 42);
    expect(lista.length, lista.toSet().length, reason: 'hay repetidos');
  });

  test('Caso 7: borrar TODO deja la lista vacía, sin explotar', () async {
    final r = await escenario([for (var i = 0; i < 40; i++) id(i)]);
    expect(r.visibles, isEmpty);
  }, skip: 'fake_cloud_firestore no soporta un cursor cuyo documento fue \nborrado. No es el comportamiento de Firestore real: verificado a mano con el \nSDK real en el emulador el 2026-08-29. Ver la nota larga de arriba.');

  // ── C2 con filtros ──────────────────────────────────────────────────
  group('el ancla T0 junto con los filtros', () {
    Stream<QuerySnapshot<Map<String, dynamic>>> nuevos({
      List<String>? estados,
      String? especie,
    }) => repo.misRescatesEnVivo(
      uid: 'refugio',
      role: CreatorRole.albergue,
      creadoDespuesDe: t0,
      estados: estados,
      especie: especie,
      porPagina: 20,
    );

    Future<void> agregarNuevo(
      String docId, {
      String estado = 'Rescatado',
      String especie = 'Perro',
    }) => db.collection('rescates').doc(docId).set({
      'nombre': docId,
      'especie': especie,
      'estadoAdopcion': estado,
      'rescatistaId': 'refugio',
      'creadoPor': 'albergue',
      'creadoEn': Timestamp.fromDate(t0.add(const Duration(minutes: 1))),
    });

    test('uno nuevo que NO cumple el filtro no aparece', () async {
      await sembrar(5);
      await agregarNuevo('nuevo_gato', especie: 'Gato');
      final arriba = (await nuevos(especie: 'Perro').first).docs;
      expect(arriba.map((d) => d.id), isNot(contains('nuevo_gato')));
      expect(arriba, isEmpty);
    });

    test('uno nuevo que SÍ cumple el filtro aparece', () async {
      await sembrar(5);
      await agregarNuevo('nuevo_perro', especie: 'Perro');
      final arriba = (await nuevos(especie: 'Perro').first).docs;
      expect(arriba.map((d) => d.id), contains('nuevo_perro'));
    });

    test('lo mismo filtrando por estado', () async {
      await sembrar(5);
      await agregarNuevo('nuevo_adoptado', estado: 'Adoptado');
      await agregarNuevo('nuevo_rescatado', estado: 'Rescatado');
      final soloAdoptados = (await nuevos(estados: const ['Adoptado']).first).docs;
      expect(soloAdoptados.map((d) => d.id), ['nuevo_adoptado']);
    });

    test('los nuevos no se mezclan con las páginas históricas', () async {
      await sembrar(25);
      await agregarNuevo('nuevo_a');
      await agregarNuevo('nuevo_b');
      final hist = (await pagina().first).docs.map((d) => d.id).toSet();
      final arriba = (await nuevos().first).docs.map((d) => d.id).toSet();
      expect(hist.intersection(arriba), isEmpty, reason: 'se pisan');
      expect(arriba, {'nuevo_a', 'nuevo_b'});
    });

    test('sin duplicados entre nuevos e históricos, con filtro puesto',
        () async {
      await sembrar(30);
      await agregarNuevo('nuevo_perro', especie: 'Perro');
      final p1 = (await pagina(especie: 'Perro').first).docs.take(20).toList();
      final arriba = (await nuevos(especie: 'Perro').first).docs;
      final todos = juntar(arriba, [p1]);
      final crudos = [...arriba.map((d) => d.id), ...p1.map((d) => d.id)];
      expect(todos.length, crudos.length, reason: 'hubo un duplicado');
      expect(todos, contains('nuevo_perro'));
    });
  });
}
