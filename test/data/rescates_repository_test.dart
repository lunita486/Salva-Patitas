import 'package:cloud_firestore/cloud_firestore.dart';
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

    test('actualizarPorNombre encuentra el rescate por nombre+dueño y lo actualiza '
        '(fallback para solicitudes viejas sin rescateId guardado)', () async {
      final ref = await firestore.collection('rescates').add({
        'nombre': 'Firulais', 'rescatistaId': 'r1', 'estadoAdopcion': 'Rescatado',
      });
      await repo.actualizarPorNombre(
        nombre: 'Firulais', rescatistaId: 'r1', cambios: {'estadoAdopcion': 'Adoptado'},
      );
      expect((await ref.get())['estadoAdopcion'], 'Adoptado');
    });

    test('actualizarPorNombre no confunde animales con el mismo nombre de otro dueño', () async {
      final deOtro = await firestore.collection('rescates').add({
        'nombre': 'Firulais', 'rescatistaId': 'otro-uid', 'estadoAdopcion': 'Rescatado',
      });
      await repo.actualizarPorNombre(
        nombre: 'Firulais', rescatistaId: 'r1', cambios: {'estadoAdopcion': 'Adoptado'},
      );
      expect((await deOtro.get())['estadoAdopcion'], 'Rescatado');
    });

    test('actualizarPorNombre no rompe si no encuentra ningún rescate', () async {
      await expectLater(
        repo.actualizarPorNombre(
          nombre: 'NoExiste', rescatistaId: 'r1', cambios: {'estadoAdopcion': 'Adoptado'},
        ),
        completes,
      );
    });

    test('feedPublico no excluye rescates sin creadoEn (bug: orderBy los desaparecía del feed)', () async {
      await firestore.collection('rescates').add({'nombre': 'ConFecha', 'creadoEn': Timestamp.now()});
      await firestore.collection('rescates').add({'nombre': 'SinFecha'});

      final docs = await repo.feedPublico().first;
      expect(docs.docs.length, 2);
      expect(docs.docs.map((d) => d['nombre']), containsAll(['ConFecha', 'SinFecha']));
    });

    group('cambiarEstadoAdopcion', () {
      test('guarda el nuevo estado y los campos extra juntos', () async {
        final ref = await firestore.collection('rescates').add({
          'nombre': 'Henry', 'estadoAdopcion': 'Rescatado',
        });
        await repo.cambiarEstadoAdopcion(ref.id, 'Adoptado', extra: {'fechaAdopcion': Timestamp.now()});
        final doc = await ref.get();
        expect(doc['estadoAdopcion'], 'Adoptado');
        expect(doc['fechaAdopcion'], isNotNull);
      });

      test('vuelve a "Rescatado" limpia adoptanteIdEnProceso (bug real: quedaba pegado y la '
          'próxima solicitud aprobada se autorrechazaba para siempre, creyendo que el animal '
          'seguía en proceso con el adoptante viejo)', () async {
        final ref = await firestore.collection('rescates').add({
          'nombre': 'Henry', 'estadoAdopcion': 'En proceso de adopción',
          'adoptanteIdEnProceso': 'adoptante-viejo',
        });
        await repo.cambiarEstadoAdopcion(ref.id, 'Rescatado');
        final doc = await ref.get();
        expect(doc['estadoAdopcion'], 'Rescatado');
        expect(doc.data()!.containsKey('adoptanteIdEnProceso'), false);
      });

      test('"Regresado" también limpia adoptanteIdEnProceso', () async {
        final ref = await firestore.collection('rescates').add({
          'nombre': 'Henry', 'estadoAdopcion': 'Hogar de paso',
          'adoptanteIdEnProceso': 'adoptante-viejo',
        });
        await repo.cambiarEstadoAdopcion(ref.id, 'Regresado', extra: {'motivoRegreso': 'Mudanza'});
        final doc = await ref.get();
        expect(doc['estadoAdopcion'], 'Regresado');
        expect(doc['motivoRegreso'], 'Mudanza');
        expect(doc.data()!.containsKey('adoptanteIdEnProceso'), false);
      });

      test('"Adoptado" NO limpia adoptanteIdEnProceso (es el adoptante real, se conserva)', () async {
        final ref = await firestore.collection('rescates').add({
          'nombre': 'Henry', 'estadoAdopcion': 'En proceso de adopción',
          'adoptanteIdEnProceso': 'el-adoptante',
        });
        await repo.cambiarEstadoAdopcion(ref.id, 'Adoptado');
        final doc = await ref.get();
        expect(doc['adoptanteIdEnProceso'], 'el-adoptante');
      });
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
