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
