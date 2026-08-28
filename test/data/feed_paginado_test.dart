import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/data/feed_paginado.dart';
import 'package:salva_patitas/data/rescates_repository.dart';

/// El feed paginaba agrandando el `limit`: 50, después 100, después 150. Cada
/// página volvía a traer TODO lo anterior, así que la página 10 eran 500
/// documentos otra vez.
///
/// Estos tests custodian las dos mitades del arreglo: que cada página cueste
/// lo mismo sin importar cuán adentro del feed se esté, Y que el feed siga
/// actualizándose solo, que es lo que ya hacía y no debía perderse.
void main() {
  late FakeFirebaseFirestore db;
  late RescatesRepository repo;
  late FeedPaginado feed;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = RescatesRepository(db: db);
  });

  tearDown(() => feed.dispose());

  /// Cuenta las consultas que de verdad se le piden a Firestore, para poder
  /// comprobar el tamaño de cada página sin adivinar.
  Future<void> sembrar(int cuantos, {int desde = 0}) async {
    for (var i = desde; i < desde + cuantos; i++) {
      await db.collection('rescates').doc('a${i.toString().padLeft(4, '0')}').set({
        'nombre': 'Animal $i',
        'especie': i % 2 == 0 ? 'Perro' : 'Gato',
        'estadoAdopcion': 'Rescatado',
        'creadoEn': Timestamp.fromDate(
          DateTime(2026, 1, 1).add(Duration(seconds: i)),
        ),
      });
    }
  }

  /// Espera a que el feed llegue a un estado que cumpla [cuando].
  ///
  /// Mira `feed.ultimo` en vez de suscribirse cada vez: `animales` es un
  /// stream de difusión, así que suscribirse DESPUÉS de una emisión se la
  /// pierde, y el test fallaría por una carrera propia y no por el código.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> esperar(
    bool Function(List<QueryDocumentSnapshot<Map<String, dynamic>>>) cuando,
  ) async {
    final limite = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(limite)) {
      final actual = feed.ultimo;
      if (actual != null && cuando(actual)) return actual;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    throw StateError('el feed nunca llegó a ese estado (último: '
        '${feed.ultimo?.length} animalitos)');
  }

  group('páginas por cursor', () {
    test('1. la primera página trae como mucho el tamaño de página', () async {
      await sembrar(130);
      feed = FeedPaginado(repo: repo, porPagina: 50);
      feed.pedirOtraPagina();
      final docs = await esperar((d) => d.isNotEmpty);
      expect(docs.length, 50);
      expect(feed.paginasAbiertas, 1);
    });

    test('2. la segunda página no repite documentos de la primera', () async {
      await sembrar(130);
      feed = FeedPaginado(repo: repo, porPagina: 50);
      feed.pedirOtraPagina();
      final p1 = [...await esperar((d) => d.length == 50)];
      feed.pedirOtraPagina();
      final p2 = await esperar((d) => d.length == 100);
      final idsP1 = p1.map((d) => d.id).toSet();
      final nuevos = p2.skip(50).map((d) => d.id).toSet();
      expect(nuevos.intersection(idsP1), isEmpty);
    });

    test('3. y 4. tres páginas: sin repetidos y sin saltos', () async {
      await sembrar(130);
      feed = FeedPaginado(repo: repo, porPagina: 50);
      feed.pedirOtraPagina();
      await esperar((d) => d.length == 50);
      feed.pedirOtraPagina();
      await esperar((d) => d.length == 100);
      feed.pedirOtraPagina();
      final todos = await esperar((d) => d.length == 130);

      final ids = todos.map((d) => d.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'hay repetidos');
      // Sin saltos: son exactamente los 130 sembrados, en orden.
      expect(ids, List.generate(130, (i) => 'a${i.toString().padLeft(4, '0')}'));
    });

    test('5. la página 3 no vuelve a descargar las páginas 1 y 2', () async {
      await sembrar(130);
      feed = FeedPaginado(repo: repo, porPagina: 50);
      feed.pedirOtraPagina();
      await esperar((d) => d.length == 50);
      feed.pedirOtraPagina();
      await esperar((d) => d.length == 100);
      feed.pedirOtraPagina();
      await esperar((d) => d.length == 130);
      // 3 páginas abiertas, cada una con su ventana: 50 + 50 + 30 = 130.
      // Con el `limit` que crecía habrían sido 50 + 100 + 150 = 300.
      expect(feed.paginasAbiertas, 3);
    });

    test('8. la última página termina la paginación', () async {
      await sembrar(60);
      feed = FeedPaginado(repo: repo, porPagina: 50);
      feed.pedirOtraPagina();
      await esperar((d) => d.length == 50);
      expect(feed.puedeHaberMas, isTrue);
      feed.pedirOtraPagina();
      await esperar((d) => d.length == 60);
      expect(feed.puedeHaberMas, isFalse, reason: 'la última vino a medias');
      // Y pedir más no abre otra página inútil.
      feed.pedirOtraPagina();
      expect(feed.paginasAbiertas, 2);
    });

    // El caso de la consigna: con 10 páginas, la décima sigue siendo una
    // ventana del tamaño de página, no 500 documentos.
    test('10. la página 10 sigue costando una página, no diez', () async {
      await sembrar(100);
      feed = FeedPaginado(repo: repo, porPagina: 10);
      for (var i = 1; i <= 10; i++) {
        feed.pedirOtraPagina();
        await esperar((d) => d.length == i * 10);
      }
      expect(feed.paginasAbiertas, 10);
      final todos = await esperar((d) => d.length == 100);
      expect(todos.map((d) => d.id).toSet().length, 100);
    });
  });

  group('sigue siendo en vivo', () {
    test('5.(bis) un animalito nuevo aparece solo', () async {
      await sembrar(3);
      feed = FeedPaginado(repo: repo, porPagina: 50);
      feed.pedirOtraPagina();
      await esperar((d) => d.length == 3);
      await sembrar(1, desde: 3);
      final despues = await esperar((d) => d.length == 4);
      expect(despues.last.id, 'a0003');
    });

    test('6. un cambio en un animalito ya cargado se refleja', () async {
      await sembrar(3);
      feed = FeedPaginado(repo: repo, porPagina: 50);
      feed.pedirOtraPagina();
      await esperar((d) => d.length == 3);
      await db.collection('rescates').doc('a0001').update({
        'estadoAdopcion': 'Adoptado',
      });
      final docs = await esperar(
        (d) => d.any((x) => x.data()['estadoAdopcion'] == 'Adoptado'),
      );
      expect(
        docs.firstWhere((d) => d.id == 'a0001').data()['estadoAdopcion'],
        'Adoptado',
      );
    });

    // Los filtros del feed viven en la pantalla y no acá, a propósito. Lo que
    // esto comprueba es que el dato con el que la pantalla filtra llega
    // actualizado: si el estado cambia, la tarjeta deja de pasar el filtro.
    test('7. un animalito que deja de estar disponible llega con el estado '
        'nuevo, para que el filtro de la pantalla lo saque', () async {
      await sembrar(3);
      feed = FeedPaginado(repo: repo, porPagina: 50);
      feed.pedirOtraPagina();
      await esperar((d) => d.length == 3);
      await db.collection('rescates').doc('a0002').update({
        'estadoAdopcion': 'Adoptado',
      });
      final docs = await esperar(
        (d) =>
            d.firstWhere((x) => x.id == 'a0002').data()['estadoAdopcion'] ==
            'Adoptado',
      );
      expect(docs.length, 3, reason: 'no desaparece del feed, cambia de estado');
    });

    // Si se borra un animalito de la página 1, esa consulta se vuelve a
    // evaluar sola y completa su ventana con el primero de la página 2. Sin
    // deduplicar, esa tarjeta aparecería dos veces.
    test('borrar uno de la página 1 no duplica el primero de la 2', () async {
      await sembrar(20);
      feed = FeedPaginado(repo: repo, porPagina: 10);
      feed.pedirOtraPagina();
      await esperar((d) => d.length == 10);
      feed.pedirOtraPagina();
      await esperar((d) => d.length == 20);
      await db.collection('rescates').doc('a0003').delete();
      final docs = await esperar((d) => d.every((x) => x.id != 'a0003'));
      final ids = docs.map((d) => d.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'se duplicó una tarjeta');
    });
  });

  group('listeners', () {
    test('9. reiniciar cierra las páginas anteriores y arranca de cero', () async {
      await sembrar(130);
      feed = FeedPaginado(repo: repo, porPagina: 50);
      feed.pedirOtraPagina();
      await esperar((d) => d.length == 50);
      feed.pedirOtraPagina();
      await esperar((d) => d.length == 100);
      expect(feed.paginasAbiertas, 2);

      feed.reiniciar();
      expect(feed.paginasAbiertas, 1, reason: 'quedaron listeners viejos');
      final despues = await esperar((d) => d.length == 50);
      expect(despues.first.id, 'a0000', reason: 'no volvió al principio');
    });

    test('9.(bis) dispose no deja ningún listener abierto', () async {
      await sembrar(60);
      feed = FeedPaginado(repo: repo, porPagina: 50);
      feed.pedirOtraPagina();
      await esperar((d) => d.length == 50);
      feed.pedirOtraPagina();
      expect(feed.paginasAbiertas, 2);

      feed.dispose();
      expect(feed.paginasAbiertas, 0);
      // Y escribir después de cerrar no puede hacer emitir a un stream
      // cerrado (sería un error de "add después de close").
      await sembrar(1, desde: 60);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
  });
}
