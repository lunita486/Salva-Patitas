import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/data/servicios_repository.dart';

void main() {
  group('ServiciosRepository', () {
    late FakeFirebaseFirestore firestore;
    late ServiciosRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = ServiciosRepository(db: firestore);
    });

    Future<void> sembrar(List<Map<String, dynamic>> servicios) async {
      for (final s in servicios) {
        await firestore.collection('servicios').add(s);
      }
    }

    test('deAliado trae TODOS sus servicios, activos y apagados — es la '
        'lista propia del negocio, donde ver los apagados es el punto '
        '(están ahí para poder volver a encenderlos)', () async {
      await sembrar([
        {'aliadoId': 'a1', 'nombre': 'Baño', 'activo': true},
        {'aliadoId': 'a1', 'nombre': 'Corte', 'activo': false},
        {'aliadoId': 'otro', 'nombre': 'De otro negocio', 'activo': true},
      ]);

      final snap = await repo.deAliado('a1').first;

      expect(snap.docs.length, 2);
      expect(
        snap.docs.map((d) => d['nombre']),
        containsAll(['Baño', 'Corte']),
      );
    });

    group(
      'activosDeAliado — lo que ve un CLIENTE en el perfil público. El '
      'filtro se aplica en memoria a propósito: hacerlo en la consulta '
      '(como hacía el aviso de borrar cuenta) esconde los servicios sin '
      'el campo `activo`, que sí están activos.',
      () {
        test('deja fuera los apagados a propósito', () async {
          await sembrar([
            {'aliadoId': 'a1', 'nombre': 'Baño', 'activo': true},
            {'aliadoId': 'a1', 'nombre': 'Corte', 'activo': false},
          ]);

          final activos = await repo.activosDeAliado('a1').first;

          expect(activos.length, 1);
          expect(activos.first['nombre'], 'Baño');
        });

        // EL caso que divergía entre las 4 copias: un servicio creado
        // antes de que el campo existiera. Su dueño lo veía encendido,
        // pero acá era invisible.
        test('un servicio SIN el campo `activo` SÍ aparece (es activo)',
            () async {
          await sembrar([
            {'aliadoId': 'a1', 'nombre': 'Servicio viejo'},
          ]);

          final activos = await repo.activosDeAliado('a1').first;

          expect(activos.length, 1);
          expect(activos.first['nombre'], 'Servicio viejo');
        });

        test('no mezcla servicios de otro negocio', () async {
          await sembrar([
            {'aliadoId': 'a1', 'nombre': 'Mío', 'activo': true},
            {'aliadoId': 'otro', 'nombre': 'Ajeno', 'activo': true},
          ]);

          final activos = await repo.activosDeAliado('a1').first;

          expect(activos.length, 1);
          expect(activos.first['nombre'], 'Mío');
        });
      },
    );

    group(
      'tieneServiciosActivos — el aviso antes de borrar la cuenta. Acá '
      'vivía el peor de los 4 criterios: filtraba `activo == true` DENTRO '
      'de la consulta, así que Firestore descartaba los servicios sin ese '
      'campo antes de que el código los viera, y la app dejaba borrar la '
      'cuenta diciendo que no había ninguno activo.',
      () {
        test('con un servicio activo, avisa', () async {
          await sembrar([
            {'aliadoId': 'a1', 'nombre': 'Baño', 'activo': true},
          ]);
          expect(await repo.tieneServiciosActivos('a1'), true);
        });

        test('con todos apagados, no avisa', () async {
          await sembrar([
            {'aliadoId': 'a1', 'nombre': 'Baño', 'activo': false},
            {'aliadoId': 'a1', 'nombre': 'Corte', 'activo': false},
          ]);
          expect(await repo.tieneServiciosActivos('a1'), false);
        });

        // La regresión concreta del bug.
        test('un servicio viejo SIN el campo cuenta como activo y avisa',
            () async {
          await sembrar([
            {'aliadoId': 'a1', 'nombre': 'Servicio viejo'},
          ]);
          expect(await repo.tieneServiciosActivos('a1'), true);
        });

        // Sin `.limit(1)` a propósito: como el filtro ya no lo hace
        // Firestore sino el código, cortar en el primer documento podía
        // traer justo uno apagado y contestar "ninguno activo".
        test('encuentra el activo aunque no sea el primero de la lista',
            () async {
          await sembrar([
            {'aliadoId': 'a1', 'nombre': 'Apagado 1', 'activo': false},
            {'aliadoId': 'a1', 'nombre': 'Apagado 2', 'activo': false},
            {'aliadoId': 'a1', 'nombre': 'Encendido', 'activo': true},
          ]);
          expect(await repo.tieneServiciosActivos('a1'), true);
        });

        test('sin ningún servicio, no avisa', () async {
          expect(await repo.tieneServiciosActivos('a1'), false);
        });
      },
    );

    test('crear() escribe aliadoId, activo:true y creadoEn — un servicio '
        'nace activo por definición, no porque la pantalla se acuerde de '
        'ponerlo', () async {
      final ref = await repo.crear(
        aliadoId: 'a1',
        datos: {'nombre': 'Baño', 'precio': 30000},
      );

      final doc = await ref.get();
      expect(doc['aliadoId'], 'a1');
      expect(doc['activo'], true);
      expect(doc['nombre'], 'Baño');
      expect(doc.data()!.containsKey('creadoEn'), true);
    });

    test('alternarActivo() invierte el estado recibido — quien llama no '
        'calcula la negación por su cuenta', () async {
      final ref = await repo.crear(aliadoId: 'a1', datos: {'nombre': 'Baño'});

      await repo.alternarActivo(servicioId: ref.id, activoAhora: true);
      expect((await ref.get())['activo'], false);

      await repo.alternarActivo(servicioId: ref.id, activoAhora: false);
      expect((await ref.get())['activo'], true);
    });

    test('actualizar() cambia solo lo que se le pasa, sin pisar el resto',
        () async {
      final ref = await repo.crear(
        aliadoId: 'a1',
        datos: {'nombre': 'Baño', 'precio': 30000},
      );

      await repo.actualizar(ref.id, {'precio': 35000});

      final doc = await ref.get();
      expect(doc['precio'], 35000);
      expect(doc['nombre'], 'Baño');
      expect(doc['activo'], true);
    });

    test('eliminar() borra el servicio', () async {
      final ref = await repo.crear(aliadoId: 'a1', datos: {'nombre': 'Baño'});
      await repo.eliminar(ref.id);
      expect((await ref.get()).exists, false);
    });
  });
}
