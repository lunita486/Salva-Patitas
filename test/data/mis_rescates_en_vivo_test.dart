import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/data/creator_role.dart';
import 'package:salva_patitas/data/rescates_repository.dart';

/// La lista de "Mis rescates" / "Gestionar la jauría" volvió a ser en vivo.
///
/// **Por qué.** Al paginarla la pasé a `.get()`, que usa
/// `Source.serverAndCache`: va al servidor y solo cae a la caché si no hay
/// conexión. Antes era `snapshots()`, que entrega la caché local AL INSTANTE
/// y después actualiza. Eso se notaba como una demora al abrir la pantalla —
/// hallazgo real de Eliza, y una regresión que introduje yo con la
/// paginación.
///
/// Ahora cada página es un stream con cursor, igual que el feed: se recupera
/// el pintado inmediato y el tiempo real, SIN volver a traer la colección
/// entera.
void main() {
  group('ancla temporal T0', anclaTemporal);

  late FakeFirebaseFirestore db;
  late RescatesRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = RescatesRepository(db: db);
  });

  Future<void> sembrar(
    int cuantos, {
    int desde = 0,
    String estado = 'Rescatado',
    String especie = 'Perro',
  }) async {
    for (var i = desde; i < desde + cuantos; i++) {
      await db.collection('rescates').doc('r${i.toString().padLeft(3, '0')}').set({
        'nombre': 'Animal $i',
        'especie': especie,
        'estadoAdopcion': estado,
        'rescatistaId': 'refugio',
        'creadoPor': 'albergue',
        'creadoEn': Timestamp.fromDate(
          DateTime(2026, 1, 1).add(Duration(seconds: i)),
        ),
      });
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> pagina({
    List<String>? estados,
    String? especie,
    DocumentSnapshot<Map<String, dynamic>>? despuesDe,
    int porPagina = 20,
  }) => repo.misRescatesEnVivo(
    uid: 'refugio',
    role: CreatorRole.albergue,
    estados: estados,
    especie: especie,
    despuesDe: despuesDe,
    porPagina: porPagina,
  );

  test('1. la primera página es un STREAM, no una lectura de una vez', () async {
    await sembrar(3);
    final s = pagina();
    expect(s, isA<Stream<QuerySnapshot<Map<String, dynamic>>>>());
    final primero = await s.first;
    expect(primero.docs.length, 3);
  });

  test('2. entrega un primer valor sin que nadie escriba nada', () async {
    await sembrar(5);
    // Que emita SOLO por suscribirse es lo que devuelve el pintado
    // inmediato: con `.get()` había que esperar el viaje al servidor.
    final primero = await pagina().first.timeout(const Duration(seconds: 5));
    expect(primero.docs.length, 5);
  });

  test('3. un cambio posterior en un animalito se refleja', () async {
    await sembrar(3);
    final s = pagina();
    await s.first;
    await db.collection('rescates').doc('r001').update({
      'estadoAdopcion': 'Adoptado',
    });
    final despues = await s
        .firstWhere(
          (q) =>
              q.docs.any((d) => d.data()['estadoAdopcion'] == 'Adoptado'),
        )
        .timeout(const Duration(seconds: 5));
    expect(
      despues.docs.firstWhere((d) => d.id == 'r001').data()['estadoAdopcion'],
      'Adoptado',
    );
  });

  test('4. la segunda página sigue usando cursor', () async {
    await sembrar(50);
    final p1 = await pagina(porPagina: 20).first;
    // Se piden 21 para saber si hay más; la pantalla muestra 20.
    expect(p1.docs.length, 21);
    final visibles1 = p1.docs.take(20).toList();
    final p2 = await pagina(porPagina: 20, despuesDe: visibles1.last).first;
    expect(p2.docs.length, 21);
    expect(p2.docs.first.id, isNot(visibles1.last.id));
  });

  test('5. no hay repetidos entre la primera y la segunda página', () async {
    await sembrar(50);
    final p1 = await pagina(porPagina: 20).first;
    final visibles1 = p1.docs.take(20).toList();
    final p2 = await pagina(porPagina: 20, despuesDe: visibles1.last).first;
    final ids1 = visibles1.map((d) => d.id).toSet();
    final ids2 = p2.docs.take(20).map((d) => d.id).toSet();
    expect(ids1.intersection(ids2), isEmpty);
  });

  // El bug del orden en initState: la consulta se arma sincrónicamente, así
  // que si el filtro se asignaba DESPUÉS de recargar, la primera página
  // salía sin filtrar mientras el chip aparecía seleccionado.
  test('6. el filtro se aplica desde la PRIMERA consulta', () async {
    await sembrar(10, estado: 'Rescatado');
    await sembrar(4, desde: 100, estado: 'Adoptado');
    final primero = await pagina(estados: const ['Adoptado']).first;
    expect(primero.docs.length, 4);
    for (final d in primero.docs) {
      expect(d.data()['estadoAdopcion'], 'Adoptado');
    }
  });

  test('6.(bis) también filtrando por especie desde el principio', () async {
    await sembrar(6, especie: 'Perro');
    await sembrar(3, desde: 100, especie: 'Gato');
    final primero = await pagina(especie: 'Gato').first;
    expect(primero.docs.length, 3);
  });

  // 7 y 8: cerrar las suscripciones. Se comprueba que después de cancelar,
  // escribir en la colección ya no llega a nadie.
  test('7. y 8. cancelar la suscripción deja de recibir', () async {
    await sembrar(2);
    var recibidos = 0;
    final sub = pagina().listen((_) => recibidos++);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final tras1 = recibidos;
    expect(tras1, greaterThan(0), reason: 'nunca llegó el primer valor');

    await sub.cancel();
    await sembrar(1, desde: 50);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(
      recibidos,
      tras1,
      reason: 'siguió llegando después de cancelar: listener huérfano',
    );
  });

  test('la página pide uno de más para saber si hay continuación', () async {
    await sembrar(21);
    final p = await pagina(porPagina: 20).first;
    expect(p.docs.length, 21, reason: '20 para mostrar + 1 de sondeo');
    await db.collection('rescates').doc('r020').delete();
    final despues = await pagina(porPagina: 20).first;
    expect(despues.docs.length, 20, reason: 'ya no hay página siguiente');
  });
}

/// El ancla temporal T0, que es lo que impide que un animalito nuevo tape a
/// otro.
///
/// **El defecto.** El orden es descendente, así que uno nuevo entra ARRIBA.
/// Sin corte, corría la ventana de la página 1 hacia abajo y su último
/// documento se caía por el borde: no quedaba ni en la página 1 (se corrió)
/// ni en la 2 (que empieza después de él). Desaparecía de la lista.
///
/// Con el ancla, las páginas históricas piden `creadoEn <= T0` y los nuevos
/// `creadoEn > T0`. Ninguna ventana ya cargada se puede mover.
void anclaTemporal() {
  late FakeFirebaseFirestore db;
  late RescatesRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = RescatesRepository(db: db);
  });

  /// Siembra con fechas controladas: [i] segundos después de la base.
  Future<void> sembrar(int cuantos, {int desde = 0, String estado = 'Rescatado'}) async {
    for (var i = desde; i < desde + cuantos; i++) {
      await db.collection('rescates').doc('h${i.toString().padLeft(3, '0')}').set({
        'nombre': 'Animal $i',
        'especie': 'Perro',
        'estadoAdopcion': estado,
        'rescatistaId': 'refugio',
        'creadoPor': 'albergue',
        'creadoEn': Timestamp.fromDate(
          DateTime(2026, 1, 1).add(Duration(seconds: i)),
        ),
      });
    }
  }

  /// El T0 del test: todo lo sembrado hasta acá es "histórico".
  final t0 = DateTime(2026, 1, 1, 1);

  Stream<QuerySnapshot<Map<String, dynamic>>> historicas({
    DocumentSnapshot<Map<String, dynamic>>? despuesDe,
    int porPagina = 20,
  }) => repo.misRescatesEnVivo(
    uid: 'refugio',
    role: CreatorRole.albergue,
    creadoAntesDe: t0,
    despuesDe: despuesDe,
    porPagina: porPagina,
  );

  Stream<QuerySnapshot<Map<String, dynamic>>> nuevos({int porPagina = 20}) =>
      repo.misRescatesEnVivo(
        uid: 'refugio',
        role: CreatorRole.albergue,
        creadoDespuesDe: t0,
        porPagina: porPagina,
      );

  /// Lo mismo que hace la pantalla: nuevos arriba, después las páginas, sin
  /// repetidos por id.
  List<String> juntar(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> arriba,
    List<List<QueryDocumentSnapshot<Map<String, dynamic>>>> paginas,
  ) {
    final vistos = <String>{};
    final ids = <String>[];
    for (final d in arriba) {
      if (vistos.add(d.id)) ids.add(d.id);
    }
    for (final p in paginas) {
      for (final d in p) {
        if (vistos.add(d.id)) ids.add(d.id);
      }
    }
    return ids;
  }

  // ── EL escenario de la consigna ──────────────────────────────────────
  test('1-3. 20 + 20, entra uno nuevo, y siguen estando los 41 sin repetidos',
      () async {
    await sembrar(40);

    final p1 = (await historicas().first).docs.take(20).toList();
    final p2 = (await historicas(despuesDe: p1.last).first).docs.take(20).toList();
    expect(p1.length, 20);
    expect(p2.length, 20);

    // Entra el nuevo, DESPUÉS de T0.
    await db.collection('rescates').doc('nuevo').set({
      'nombre': 'Recién llegado',
      'especie': 'Perro',
      'estadoAdopcion': 'Rescatado',
      'rescatistaId': 'refugio',
      'creadoPor': 'albergue',
      'creadoEn': Timestamp.fromDate(t0.add(const Duration(minutes: 1))),
    });

    // Las páginas históricas NO se movieron.
    final p1b = (await historicas().first).docs.take(20).toList();
    expect(
      p1b.map((d) => d.id).toList(),
      p1.map((d) => d.id).toList(),
      reason: 'la ventana histórica se corrió: eso es el defecto',
    );

    final arriba = (await nuevos().first).docs;
    final todos = juntar(arriba, [p1b, p2]);
    expect(todos.length, 41, reason: 'se perdió alguno');
    expect(todos.toSet().length, 41, reason: 'hay repetidos');
    expect(todos.first, 'nuevo', reason: 'el nuevo va arriba');
  });

  test('8. un animalito nuevo NO entra en las páginas históricas', () async {
    await sembrar(5);
    await db.collection('rescates').doc('nuevo').set({
      'nombre': 'Recién llegado',
      'especie': 'Perro',
      'estadoAdopcion': 'Rescatado',
      'rescatistaId': 'refugio',
      'creadoPor': 'albergue',
      'creadoEn': Timestamp.fromDate(t0.add(const Duration(minutes: 1))),
    });
    final hist = (await historicas().first).docs.map((d) => d.id).toList();
    expect(hist, isNot(contains('nuevo')));
    expect(hist.length, 5);
  });

  test('9. las consultas > T0 y <= T0 nunca se pisan', () async {
    await sembrar(6);
    for (var i = 0; i < 3; i++) {
      await db.collection('rescates').doc('n$i').set({
        'nombre': 'Nuevo $i',
        'especie': 'Perro',
        'estadoAdopcion': 'Rescatado',
        'rescatistaId': 'refugio',
        'creadoPor': 'albergue',
        'creadoEn': Timestamp.fromDate(t0.add(Duration(minutes: i + 1))),
      });
    }
    final hist = (await historicas().first).docs.map((d) => d.id).toSet();
    final arriba = (await nuevos().first).docs.map((d) => d.id).toSet();
    expect(hist.intersection(arriba), isEmpty);
    expect(hist.length + arriba.length, 9, reason: 'entre las dos, todos');
  });

  test('4-6. se elimina uno de la página 1: se completa y sin repetidos',
      () async {
    await sembrar(40);
    final p1 = (await historicas().first).docs.take(20).toList();
    final p2 = (await historicas(despuesDe: p1.last).first).docs.take(20).toList();

    await db.collection('rescates').doc(p1[3].id).delete();

    final p1b = (await historicas().first).docs.take(20).toList();
    expect(p1b.length, 20, reason: 'la página se completó sola');
    expect(p1b.map((d) => d.id), isNot(contains(p1[3].id)));

    final todos = juntar(const [], [p1b, p2]);
    expect(todos.toSet().length, todos.length, reason: 'hay repetidos');
    expect(todos.length, 39, reason: 'quedan 39 de los 40');
  });

  test('7. uno que deja de cumplir el filtro desaparece', () async {
    await sembrar(5, estado: 'Rescatado');
    final conFiltro = repo.misRescatesEnVivo(
      uid: 'refugio',
      role: CreatorRole.albergue,
      estados: const ['Rescatado'],
      creadoAntesDe: t0,
    );
    expect((await conFiltro.first).docs.length, 5);
    await db.collection('rescates').doc('h002').update({
      'estadoAdopcion': 'Adoptado',
    });
    final despues = await conFiltro
        .firstWhere((q) => q.docs.length == 4)
        .timeout(const Duration(seconds: 5));
    expect(despues.docs.map((d) => d.id), isNot(contains('h002')));
  });

  // El tope de la consulta de nuevos, y qué pasa al alcanzarlo.
  test('con más nuevos que el tope, se muestran los MÁS RECIENTES', () async {
    await sembrar(3);
    for (var i = 0; i < 25; i++) {
      await db.collection('rescates').doc('n${i.toString().padLeft(2, '0')}').set({
        'nombre': 'Nuevo $i',
        'especie': 'Perro',
        'estadoAdopcion': 'Rescatado',
        'rescatistaId': 'refugio',
        'creadoPor': 'albergue',
        'creadoEn': Timestamp.fromDate(t0.add(Duration(minutes: i + 1))),
      });
    }
    // La pantalla pide tope+1 y recorta a tope.
    final traidos = (await nuevos(porPagina: 20).first).docs;
    expect(traidos.length, 21, reason: 'pide uno de más para saber que hay tope');
    final mostrados = traidos.take(20).map((d) => d.id).toList();
    expect(mostrados.length, 20);
    // Los más recientes son los de índice más alto.
    expect(mostrados.first, 'n24');
    expect(
      mostrados,
      isNot(contains('n00')),
      reason: 'los que sobran del tope aparecen recién al rearmar la lista',
    );
  });
}
