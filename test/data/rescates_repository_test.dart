import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patitas_medellin/data/creator_role.dart';
import 'package:patitas_medellin/data/rescates_repository.dart';

void main() {
  group('RescatesRepository', () {
    late FakeFirebaseFirestore firestore;
    late RescatesRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = RescatesRepository(db: firestore);
    });

    test('misRescates solo devuelve los del uid y del CreatorRole pedidos', () async {
      const uid = 'user-1';
      await firestore.collection('rescates').add({
        'nombre': 'Henry', 'rescatistaId': uid, 'creadoPor': 'rescatista',
      });
      await firestore.collection('rescates').add({
        'nombre': 'Amy', 'rescatistaId': uid, 'creadoPor': 'albergue',
      });
      await firestore.collection('rescates').add({
        'nombre': 'Otro', 'rescatistaId': 'otro-uid', 'creadoPor': 'rescatista',
      });

      final soloRescatista = await repo
          .misRescates(uid: uid, role: CreatorRole.rescatista)
          .first;
      expect(soloRescatista.docs.length, 1);
      expect(soloRescatista.docs.first['nombre'], 'Henry');

      final soloAlbergue = await repo
          .misRescates(uid: uid, role: CreatorRole.albergue)
          .first;
      expect(soloAlbergue.docs.length, 1);
      expect(soloAlbergue.docs.first['nombre'], 'Amy');
    });

    test('crear() guarda rescatistaId y creadoPor a partir de los parámetros, no de los datos', () async {
      final ref = await repo.crear(
        uid: 'user-2',
        role: CreatorRole.albergue,
        datos: {'nombre': 'Toby'},
      );
      final doc = await ref.get();
      expect(doc['rescatistaId'], 'user-2');
      expect(doc['creadoPor'], 'albergue');
      expect(doc['nombre'], 'Toby');
    });

    test('eliminar() borra el documento', () async {
      final ref = await firestore.collection('rescates').add({'nombre': 'X'});
      await repo.eliminar(ref.id);
      final doc = await ref.get();
      expect(doc.exists, false);
    });

    test('misRescatesPorEstado filtra por uid, CreatorRole y estado a la vez', () async {
      const uid = 'user-3';
      await firestore.collection('rescates').add({
        'nombre': 'Henry', 'rescatistaId': uid, 'creadoPor': 'rescatista',
        'estadoAdopcion': 'Hogar de paso',
      });
      await firestore.collection('rescates').add({
        'nombre': 'Amy', 'rescatistaId': uid, 'creadoPor': 'albergue',
        'estadoAdopcion': 'Hogar de paso',
      });
      await firestore.collection('rescates').add({
        'nombre': 'Toby', 'rescatistaId': uid, 'creadoPor': 'rescatista',
        'estadoAdopcion': 'Rescatado',
      });

      final result = await repo.misRescatesPorEstado(
        uid: uid, role: CreatorRole.rescatista, estadoAdopcion: 'Hogar de paso',
      );
      expect(result.docs.length, 1);
      expect(result.docs.first['nombre'], 'Henry');
    });
  });
}
