import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patitas_medellin/data/creator_role.dart';
import 'package:patitas_medellin/data/solicitudes_repository.dart';

void main() {
  group('SolicitudesRepository', () {
    late FakeFirebaseFirestore firestore;
    late SolicitudesRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = SolicitudesRepository(db: firestore);
    });

    test('paraOwner distingue por CreatorRole aunque el uid sea el mismo '
        '(este era exactamente el bug de hoy)', () async {
      const uid = 'dueño-1';
      await firestore.collection('solicitudes').add({
        'rescatistaId': uid, 'creadoPor': 'rescatista', 'estado': 'pendiente',
        'animalNombre': 'Henry',
      });
      await firestore.collection('solicitudes').add({
        'rescatistaId': uid, 'creadoPor': 'albergue', 'estado': 'pendiente',
        'animalNombre': 'Amy',
      });

      final comoRescatista = await repo
          .paraOwner(uid: uid, role: CreatorRole.rescatista)
          .first;
      expect(comoRescatista.docs.length, 1);
      expect(comoRescatista.docs.first['animalNombre'], 'Henry');

      final comoAlbergue = await repo
          .paraOwner(uid: uid, role: CreatorRole.albergue)
          .first;
      expect(comoAlbergue.docs.length, 1);
      expect(comoAlbergue.docs.first['animalNombre'], 'Amy');
    });

    test('misSolicitudes no depende de CreatorRole, solo de adoptanteId', () async {
      const uid = 'adoptante-1';
      await firestore.collection('solicitudes').add({'adoptanteId': uid, 'animalNombre': 'Olafo'});
      await firestore.collection('solicitudes').add({'adoptanteId': 'otro', 'animalNombre': 'Otro'});

      final mias = await repo.misSolicitudes(uid).first;
      expect(mias.docs.length, 1);
      expect(mias.docs.first['animalNombre'], 'Olafo');
    });

    test('crear() denormaliza creadoPor a partir del CreatorRole recibido', () async {
      final ref = await repo.crear(
        adoptanteUid: 'a1',
        rescatistaId: 'r1',
        creadoPor: CreatorRole.albergue,
        datos: {'animalNombre': 'Toby'},
      );
      final doc = await ref.get();
      expect(doc['creadoPor'], 'albergue');
      expect(doc['estado'], 'pendiente');
    });

    test('estadoExistente devuelve el estado de una solicitud pendiente/aprobada, o null', () async {
      expect(await repo.estadoExistente(uid: 'a1', animalNombre: 'Henry'), null);

      await firestore.collection('solicitudes').add({
        'adoptanteId': 'a1', 'animalNombre': 'Henry', 'estado': 'aprobada',
      });
      expect(await repo.estadoExistente(uid: 'a1', animalNombre: 'Henry'), 'aprobada');
    });

    test('estadoExistente con rescateId distingue dos animales con el mismo '
        'nombre (antes aplicar a uno bloqueaba aplicar al otro)', () async {
      await firestore.collection('solicitudes').add({
        'adoptanteId': 'a1', 'animalNombre': 'Luna', 'rescateId': 'luna-1', 'estado': 'aprobada',
      });

      // Misma persona, mismo nombre de animal, pero rescateId distinto:
      // no debería contar como "ya aplicó" a este segundo animal.
      expect(
        await repo.estadoExistente(uid: 'a1', animalNombre: 'Luna', rescateId: 'luna-2'),
        null,
      );
      // Al animal correcto (mismo rescateId) sí lo detecta.
      expect(
        await repo.estadoExistente(uid: 'a1', animalNombre: 'Luna', rescateId: 'luna-1'),
        'aprobada',
      );
    });

    test('cambiarEstado actualiza el campo estado', () async {
      final ref = await firestore.collection('solicitudes').add({'estado': 'pendiente'});
      await repo.cambiarEstado(ref.id, 'aprobada');
      final doc = await ref.get();
      expect(doc['estado'], 'aprobada');
    });

    test('rechazar() guarda estado y motivoRechazo juntos (a diferencia de cambiarEstado)', () async {
      final ref = await firestore.collection('solicitudes').add({'estado': 'pendiente'});
      await repo.rechazar(ref.id, 'No cumple con los requisitos');
      final doc = await ref.get();
      expect(doc['estado'], 'rechazada');
      expect(doc['motivoRechazo'], 'No cumple con los requisitos');
    });

    test('rechazarCompetidoras rechaza las demás solicitudes PENDIENTES por el mismo animal, '
        'sin tocar la aprobada ni las de otro animal', () async {
      final aprobada = await firestore.collection('solicitudes').add({
        'animalNombre': 'Rocky', 'rescatistaId': 'r1', 'estado': 'pendiente', 'adoptanteId': 'ganador',
      });
      final competidora = await firestore.collection('solicitudes').add({
        'animalNombre': 'Rocky', 'rescatistaId': 'r1', 'estado': 'pendiente', 'adoptanteId': 'perdedor',
      });
      final yaRechazadaAntes = await firestore.collection('solicitudes').add({
        'animalNombre': 'Rocky', 'rescatistaId': 'r1', 'estado': 'rechazada', 'adoptanteId': 'viejo',
      });
      final otroAnimal = await firestore.collection('solicitudes').add({
        'animalNombre': 'Otro', 'rescatistaId': 'r1', 'estado': 'pendiente', 'adoptanteId': 'x',
      });

      final rechazadas = await repo.rechazarCompetidoras(
        animalNombre: 'Rocky', rescatistaId: 'r1', excluirDocId: aprobada.id,
      );

      expect(rechazadas.length, 1);
      expect(rechazadas.first['adoptanteId'], 'perdedor');
      expect((await competidora.get())['estado'], 'rechazada');
      expect((await aprobada.get())['estado'], 'pendiente');
      expect((await yaRechazadaAntes.get())['estado'], 'rechazada');
      expect((await otroAnimal.get())['estado'], 'pendiente');
    });

    test('rechazarCompetidoras con rescateId no confunde dos animales con el mismo nombre', () async {
      final ganadorRocky1 = await firestore.collection('solicitudes').add({
        'animalNombre': 'Rocky', 'rescatistaId': 'r1', 'rescateId': 'rocky-1',
        'estado': 'pendiente', 'adoptanteId': 'ganador',
      });
      final otroRocky2 = await firestore.collection('solicitudes').add({
        'animalNombre': 'Rocky', 'rescatistaId': 'r1', 'rescateId': 'rocky-2',
        'estado': 'pendiente', 'adoptanteId': 'no-deberia-tocarse',
      });

      final rechazadas = await repo.rechazarCompetidoras(
        animalNombre: 'Rocky', rescatistaId: 'r1', excluirDocId: ganadorRocky1.id,
        rescateId: 'rocky-1',
      );

      expect(rechazadas, isEmpty);
      expect((await otroRocky2.get())['estado'], 'pendiente');
    });

    group('aprobarSiDisponible', () {
      test('aprueba y actualiza el rescate cuando el animal está disponible', () async {
        final sol = await firestore.collection('solicitudes').add({'estado': 'pendiente'});
        final rescate = await firestore.collection('rescates').add({'estadoAdopcion': 'Rescatado'});

        final resultado = await repo.aprobarSiDisponible(
          solicitudId: sol.id,
          rescateId: rescate.id,
          adoptanteId: 'ganador',
          nuevoEstadoAdopcion: 'En proceso de adopción',
          camposExtra: {'vencimientoAvisado': false},
        );

        expect(resultado, true);
        expect((await sol.get())['estado'], 'aprobada');
        final rescateData = (await rescate.get()).data()!;
        expect(rescateData['estadoAdopcion'], 'En proceso de adopción');
        expect(rescateData['adoptanteIdEnProceso'], 'ganador');
        expect(rescateData['vencimientoAvisado'], false);
      });

      test('se autorrechaza en vez de aprobar cuando otro adoptante ya ganó la carrera '
          '(el bug real que esto arregla: dos solicitudes del mismo animal aprobadas a la vez)', () async {
        final sol = await firestore.collection('solicitudes').add({'estado': 'pendiente'});
        // El rescate ya quedó tomado por otra aprobación que llegó primero.
        final rescate = await firestore.collection('rescates').add({
          'estadoAdopcion': 'En proceso de adopción',
          'adoptanteIdEnProceso': 'el-que-ganó',
        });

        final resultado = await repo.aprobarSiDisponible(
          solicitudId: sol.id,
          rescateId: rescate.id,
          adoptanteId: 'el-que-perdió',
          nuevoEstadoAdopcion: 'En proceso de adopción',
        );

        expect(resultado, false);
        final solData = (await sol.get()).data()!;
        expect(solData['estado'], 'rechazada');
        expect(solData['motivoRechazo'], isNotEmpty);
        // El rescate no se toca: sigue siendo del ganador original.
        final rescateData = (await rescate.get()).data()!;
        expect(rescateData['adoptanteIdEnProceso'], 'el-que-ganó');
        expect(rescateData['estadoAdopcion'], 'En proceso de adopción');
      });

      test('si adoptanteIdEnProceso ya es del MISMO adoptante, igual aprueba '
          '(no es una carrera, es la misma persona)', () async {
        final sol = await firestore.collection('solicitudes').add({'estado': 'pendiente'});
        final rescate = await firestore.collection('rescates').add({
          'estadoAdopcion': 'Hogar de paso',
          'adoptanteIdEnProceso': 'misma-persona',
        });

        final resultado = await repo.aprobarSiDisponible(
          solicitudId: sol.id,
          rescateId: rescate.id,
          adoptanteId: 'misma-persona',
          nuevoEstadoAdopcion: 'En proceso de adopción',
        );

        expect(resultado, true);
        expect((await sol.get())['estado'], 'aprobada');
      });
    });
  });
}
