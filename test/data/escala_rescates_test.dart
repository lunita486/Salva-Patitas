import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/data/creator_role.dart';
import 'package:salva_patitas/data/rescates_repository.dart';

/// La regla que estos tests custodian:
///
///   **la cantidad total de animales de una cuenta no debe cambiar cuánto
///   trabajo hace el teléfono para mostrar una pantalla.**
///
/// Antes no era así. `misRescates` devolvía la consulta COMPLETA sin
/// `limit`, y tres pantallas la usaban solo para hacer `docs.length`: abrir
/// el inicio con 1.000 animales descargaba los 1.000 para pintar un número.
///
/// Por eso varios de estos tests siembran 250 animales y comprueban que lo
/// que vuelve NO depende de ese 250. Si alguien vuelve a poner una consulta
/// sin tope, se cae acá y no en el teléfono de alguien.
void main() {
  late FakeFirebaseFirestore db;
  late RescatesRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = RescatesRepository(db: db);
  });

  Future<void> sembrar(
    int cuantos, {
    String uid = 'refugio',
    String creadoPor = 'albergue',
    String estado = 'Rescatado',
    String especie = 'Perro',
  }) async {
    for (var i = 0; i < cuantos; i++) {
      await db.collection('rescates').add({
        'nombre': 'Animal $i',
        'especie': especie,
        'estadoAdopcion': estado,
        'rescatistaId': uid,
        'creadoPor': creadoPor,
        // Segundos distintos: el orden de la paginación tiene que ser
        // estable, si no una página podría repetir o saltear documentos.
        'creadoEn': Timestamp.fromDate(DateTime(2026, 1, 1).add(Duration(seconds: i))),
      });
    }
  }

  group('contar() — sin descargar documentos', () {
    test('cuenta todos los de la cuenta y el rol', () async {
      await sembrar(250);
      await sembrar(7, uid: 'otra-persona');
      expect(
        await repo.contar(uid: 'refugio', role: CreatorRole.albergue),
        250,
      );
    });

    test('no mezcla roles de la misma cuenta', () async {
      await sembrar(5, creadoPor: 'albergue');
      await sembrar(3, creadoPor: 'rescatista');
      expect(await repo.contar(uid: 'refugio', role: CreatorRole.albergue), 5);
      expect(
        await repo.contar(uid: 'refugio', role: CreatorRole.rescatista),
        3,
      );
    });

    test('filtra por un estado', () async {
      await sembrar(4, estado: 'Adoptado');
      await sembrar(6, estado: 'Rescatado');
      expect(
        await repo.contar(
          uid: 'refugio',
          role: CreatorRole.albergue,
          estados: ['Adoptado'],
        ),
        4,
      );
    });

    // "En cuidado" del panel de albergue son DOS estados.
    test('filtra por varios estados a la vez', () async {
      await sembrar(4, estado: 'Rescatado');
      await sembrar(3, estado: 'Regresado');
      await sembrar(9, estado: 'Adoptado');
      expect(
        await repo.contar(
          uid: 'refugio',
          role: CreatorRole.albergue,
          estados: ['Rescatado', 'Regresado'],
        ),
        7,
      );
    });

    test('una cuenta sin animales da 0, no explota', () async {
      expect(await repo.contar(uid: 'nadie', role: CreatorRole.albergue), 0);
    });
  });

  group('paginaDeMisRescates() — cursor, no offset', () {
    test('la primera página trae exactamente el tamaño pedido', () async {
      await sembrar(250);
      final p = await repo.paginaDeMisRescates(
        uid: 'refugio',
        role: CreatorRole.albergue,
        porPagina: 20,
      );
      expect(p.docs.length, 20, reason: 'no puede depender de los 250');
      expect(p.hayMas, isTrue);
      expect(p.ultimo, isNotNull);
    });

    // EL test de escala: el trabajo de mostrar la primera pantalla tiene que
    // ser el mismo con 25 animales que con 250.
    test('el tamaño de la página no crece con la colección', () async {
      await sembrar(25);
      final chica = await repo.paginaDeMisRescates(
        uid: 'refugio',
        role: CreatorRole.albergue,
        porPagina: 20,
      );
      await sembrar(225, uid: 'refugio');
      final grande = await repo.paginaDeMisRescates(
        uid: 'refugio',
        role: CreatorRole.albergue,
        porPagina: 20,
      );
      expect(grande.docs.length, chica.docs.length);
    });

    test('recorriendo con el cursor se ve cada animal una sola vez', () async {
      await sembrar(55);
      final vistos = <String>{};
      DocumentSnapshot<Map<String, dynamic>>? cursor;
      var paginas = 0;
      while (true) {
        final p = await repo.paginaDeMisRescates(
          uid: 'refugio',
          role: CreatorRole.albergue,
          porPagina: 20,
          despuesDe: cursor,
        );
        for (final d in p.docs) {
          expect(vistos.add(d.id), isTrue, reason: 'documento repetido');
        }
        paginas++;
        if (!p.hayMas) break;
        cursor = p.ultimo;
        expect(paginas, lessThan(10), reason: 'no termina de paginar');
      }
      expect(vistos.length, 55, reason: 'no se salteó ninguno');
      expect(paginas, 3);
    });

    test('la última página avisa que no hay más', () async {
      await sembrar(20);
      final p = await repo.paginaDeMisRescates(
        uid: 'refugio',
        role: CreatorRole.albergue,
        porPagina: 20,
      );
      expect(p.docs.length, 20);
      expect(p.hayMas, isFalse, reason: 'justo 20, no hay una página 2 vacía');
    });

    // Filtrar en Dart sobre una página ya traída daría resultados falsos: si
    // la primera página no tuviera ningún gato, "Gatos" se vería vacío
    // aunque hubiera cientos más abajo.
    test('los filtros van en la consulta, no sobre la página', () async {
      await sembrar(30, especie: 'Perro');
      await sembrar(4, especie: 'Gato');
      final p = await repo.paginaDeMisRescates(
        uid: 'refugio',
        role: CreatorRole.albergue,
        especie: 'Gato',
        porPagina: 20,
      );
      expect(p.docs.length, 4);
      expect(p.hayMas, isFalse);
    });

    test('estado y especie se combinan', () async {
      await sembrar(10, especie: 'Gato', estado: 'Adoptado');
      await sembrar(6, especie: 'Gato', estado: 'Rescatado');
      await sembrar(8, especie: 'Perro', estado: 'Adoptado');
      final p = await repo.paginaDeMisRescates(
        uid: 'refugio',
        role: CreatorRole.albergue,
        especie: 'Gato',
        estados: const ['Adoptado'],
        porPagina: 20,
      );
      expect(p.docs.length, 10);
    });

    test('una cuenta sin animales devuelve una página vacía', () async {
      final p = await repo.paginaDeMisRescates(
        uid: 'nadie',
        role: CreatorRole.albergue,
      );
      expect(p.docs, isEmpty);
      expect(p.hayMas, isFalse);
      expect(p.ultimo, isNull);
    });

    test('también pagina filtrando por varios estados', () async {
      await sembrar(12, estado: 'Rescatado');
      await sembrar(9, estado: 'Regresado');
      await sembrar(30, estado: 'Adoptado');
      final p = await repo.paginaDeMisRescates(
        uid: 'refugio',
        role: CreatorRole.albergue,
        estados: const ['Rescatado', 'Regresado'],
        porPagina: 20,
      );
      expect(p.docs.length, 20);
      expect(p.hayMas, isTrue);
      for (final d in p.docs) {
        expect(d.data()['estadoAdopcion'], isNot('Adoptado'));
      }
    });

    // El filtro "Estancados" es un cálculo, no un estado guardado: lleva
    // más de N días esperando y todavía se puede adoptar. Antes se resolvía
    // en Dart sobre la colección entera.
    test('corta por fecha sin traer los más nuevos', () async {
      await sembrar(40);
      final corte = DateTime(2026, 1, 1).add(const Duration(seconds: 20));
      final p = await repo.paginaDeMisRescates(
        uid: 'refugio',
        role: CreatorRole.albergue,
        creadoAntesDe: corte,
        porPagina: 50,
      );
      expect(p.docs.length, 21, reason: 'los sembrados 0..20 inclusive');
      for (final d in p.docs) {
        final f = (d.data()['creadoEn'] as Timestamp).toDate();
        expect(f.isAfter(corte), isFalse);
      }
    });

    test('el más nuevo va primero', () async {
      await sembrar(5);
      final p = await repo.paginaDeMisRescates(
        uid: 'refugio',
        role: CreatorRole.albergue,
        porPagina: 20,
      );
      final fechas = p.docs
          .map((d) => (d.data()['creadoEn'] as Timestamp).toDate())
          .toList();
      for (var i = 1; i < fechas.length; i++) {
        expect(fechas[i].isBefore(fechas[i - 1]), isTrue);
      }
    });
  });
}
