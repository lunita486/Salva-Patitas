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

    test('yaAplico detecta solicitudes pendientes/aprobadas existentes', () async {
      await firestore.collection('solicitudes').add({
        'adoptanteId': 'a1', 'animalNombre': 'Henry', 'estado': 'pendiente',
      });
      expect(await repo.yaAplico(uid: 'a1', animalNombre: 'Henry'), true);
      expect(await repo.yaAplico(uid: 'a1', animalNombre: 'OtroAnimal'), false);
    });

    test('estadoExistente devuelve el estado de una solicitud pendiente/aprobada, o null', () async {
      expect(await repo.estadoExistente(uid: 'a1', animalNombre: 'Henry'), null);

      await firestore.collection('solicitudes').add({
        'adoptanteId': 'a1', 'animalNombre': 'Henry', 'estado': 'aprobada',
      });
      expect(await repo.estadoExistente(uid: 'a1', animalNombre: 'Henry'), 'aprobada');
    });

    test('cambiarEstado actualiza el campo estado', () async {
      final ref = await firestore.collection('solicitudes').add({'estado': 'pendiente'});
      await repo.cambiarEstado(ref.id, 'aprobada');
      final doc = await ref.get();
      expect(doc['estado'], 'aprobada');
    });
  });
}
