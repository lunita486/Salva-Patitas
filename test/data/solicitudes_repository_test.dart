import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:patitas_medellin/data/creator_role.dart';
import 'package:patitas_medellin/data/solicitudes_repository.dart';

// fake_cloud_firestore no simula fallas transitorias de red — para probar
// el reintento de tienePendientesPara() hace falta controlar a mano cuándo
// falla get() (mismo patrón que rescate_fotos_repository_test.dart).
class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class MockCollectionReference extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class MockQuery extends Mock implements Query<Map<String, dynamic>> {}

class MockQuerySnapshot extends Mock
    implements QuerySnapshot<Map<String, dynamic>> {}

class MockQueryDocumentSnapshot extends Mock
    implements QueryDocumentSnapshot<Map<String, dynamic>> {}

void main() {
  // Para poder stubear query.get(any()) — mocktail necesita un valor de
  // respaldo registrado para tipos propios como GetOptions.
  setUpAll(() => registerFallbackValue(const GetOptions()));

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

    test('aceptarAcuerdo marca acuerdoAceptado=true y guarda la fecha del servidor '
        '("registro del acuerdo de adopción", versión simple sin firma ni PDF)', () async {
      final ref = await firestore.collection('solicitudes').add({'estado': 'aprobada'});
      await repo.aceptarAcuerdo(ref.id);
      final doc = await ref.get();
      expect(doc['acuerdoAceptado'], true);
      expect(doc['acuerdoAceptadoEn'], isNotNull);
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

        expect(resultado.aprobada, true);
        expect(resultado.animalEliminado, false);
        expect((await sol.get())['estado'], 'aprobada');
        final rescateData = (await rescate.get()).data()!;
        expect(rescateData['estadoAdopcion'], 'En proceso de adopción');
        expect(rescateData['adoptanteIdEnProceso'], 'ganador');
        expect(rescateData['vencimientoAvisado'], false);
      });

      test('rechaza con animalEliminado=true cuando el rescate ya no existe '
          '(se borró mientras la solicitud seguía pendiente — antes esto tiraba '
          'invalid-argument al intentar tx.update sobre un doc borrado)', () async {
        final sol = await firestore.collection('solicitudes').add({'estado': 'pendiente'});

        final resultado = await repo.aprobarSiDisponible(
          solicitudId: sol.id,
          rescateId: 'rescate-que-ya-no-existe',
          adoptanteId: 'ganador',
          nuevoEstadoAdopcion: 'En proceso de adopción',
        );

        expect(resultado.aprobada, false);
        expect(resultado.animalEliminado, true);
        final solData = (await sol.get()).data()!;
        expect(solData['estado'], 'rechazada');
        expect(solData['motivoRechazo'], isNotEmpty);
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

        expect(resultado.aprobada, false);
        expect(resultado.animalEliminado, false);
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

        expect(resultado.aprobada, true);
        expect((await sol.get())['estado'], 'aprobada');
      });
    });

    group('tienePendientesPara', () {
      test('true si hay una solicitud pendiente para ese rescateId', () async {
        await firestore.collection('solicitudes').add({
          'rescateId': 'eddy-1', 'rescatistaId': 'alb-1', 'estado': 'pendiente',
        });
        expect(await repo.tienePendientesPara('eddy-1', rescatistaId: 'alb-1'), true);
      });

      test('false si la única solicitud ya fue aprobada/rechazada', () async {
        await firestore.collection('solicitudes').add({
          'rescateId': 'eddy-1', 'rescatistaId': 'alb-1', 'estado': 'aprobada',
        });
        expect(await repo.tienePendientesPara('eddy-1', rescatistaId: 'alb-1'), false);
      });

      test('false si no hay ninguna solicitud para ese rescateId', () async {
        expect(await repo.tienePendientesPara('sin-solicitudes', rescatistaId: 'alb-1'), false);
      });

      test('si la consulta falla una vez (ej. señal recién recuperada de '
          'modo avión, el canal de Firestore todavía reconectando) '
          'reintenta sola y no hace falta salir y volver a entrar — el bug '
          'real: "vuelvo a tener señal y quiero borrar, y sigue diciendo '
          'que no puede verificar la conexión"', () async {
        final db = MockFirebaseFirestore();
        final col = MockCollectionReference();
        final query = MockQuery();
        final snapshot = MockQuerySnapshot();
        when(() => db.collection('solicitudes')).thenReturn(col);
        when(() => col.where(any(), isEqualTo: any(named: 'isEqualTo')))
            .thenReturn(query);
        when(() => query.where(any(), isEqualTo: any(named: 'isEqualTo')))
            .thenReturn(query);
        when(() => query.limit(any())).thenReturn(query);
        when(() => snapshot.docs).thenReturn([]);
        var intentos = 0;
        when(() => query.get()).thenAnswer((_) {
          intentos++;
          if (intentos == 1) {
            throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
          }
          return Future.value(snapshot);
        });

        final repoConMock = SolicitudesRepository(db: db);
        expect(await repoConMock.tienePendientesPara('rescate-1', rescatistaId: 'alb-1'), false);
        expect(intentos, 2);
      });

      test('si el servidor sigue sin responder tras el reintento (la '
          'reconexión tras modo avión puede tardar hasta ~1 minuto de '
          'backoff), cae a la copia LOCAL: caché sin pendientes → deja '
          'borrar — el bug real: internet ya puesto y "no pudimos verificar '
          'si se puede eliminar" en cada tap, canequita y editar → eliminar', () async {
        final db = MockFirebaseFirestore();
        final col = MockCollectionReference();
        final query = MockQuery();
        final snapshotCache = MockQuerySnapshot();
        when(() => db.collection('solicitudes')).thenReturn(col);
        when(() => col.where(any(), isEqualTo: any(named: 'isEqualTo')))
            .thenReturn(query);
        when(() => query.where(any(), isEqualTo: any(named: 'isEqualTo')))
            .thenReturn(query);
        when(() => query.limit(any())).thenReturn(query);
        when(() => query.get()).thenThrow(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));
        // Solo el pedido explícito a la caché local responde — si el código
        // pidiera otra fuente, no matchea ningún stub y el test falla.
        when(() => query.get(any(
                that: isA<GetOptions>()
                    .having((o) => o.source, 'source', Source.cache))))
            .thenAnswer((_) async => snapshotCache);
        when(() => snapshotCache.docs).thenReturn([]);

        final repoConMock = SolicitudesRepository(db: db);
        expect(await repoConMock.tienePendientesPara('rescate-1', rescatistaId: 'alb-1'), false);
      });

      test('la caída a caché también BLOQUEA el borrado si la copia local '
          'sí conoce una solicitud pendiente — tolerar la falla de red no '
          'significa ignorar lo que el teléfono ya sabe', () async {
        final db = MockFirebaseFirestore();
        final col = MockCollectionReference();
        final query = MockQuery();
        final snapshotCache = MockQuerySnapshot();
        final docPendiente = MockQueryDocumentSnapshot();
        when(() => db.collection('solicitudes')).thenReturn(col);
        when(() => col.where(any(), isEqualTo: any(named: 'isEqualTo')))
            .thenReturn(query);
        when(() => query.where(any(), isEqualTo: any(named: 'isEqualTo')))
            .thenReturn(query);
        when(() => query.limit(any())).thenReturn(query);
        when(() => query.get()).thenThrow(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));
        when(() => query.get(any())).thenAnswer((_) async => snapshotCache);
        when(() => snapshotCache.docs).thenReturn([docPendiente]);

        final repoConMock = SolicitudesRepository(db: db);
        expect(await repoConMock.tienePendientesPara('rescate-1', rescatistaId: 'alb-1'), true);
      });

      test('si el servidor falla dos veces Y hasta la caché local falla '
          '(rarísimo) propaga el error — el llamador (mis_rescates_screen.dart, '
          'editar_rescate_screen.dart) necesita la excepción para avisar '
          '"revisá tu conexión"', () async {
        final db = MockFirebaseFirestore();
        final col = MockCollectionReference();
        final query = MockQuery();
        when(() => db.collection('solicitudes')).thenReturn(col);
        when(() => col.where(any(), isEqualTo: any(named: 'isEqualTo')))
            .thenReturn(query);
        when(() => query.where(any(), isEqualTo: any(named: 'isEqualTo')))
            .thenReturn(query);
        when(() => query.limit(any())).thenReturn(query);
        when(() => query.get()).thenThrow(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));
        when(() => query.get(any())).thenThrow(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));

        final repoConMock = SolicitudesRepository(db: db);
        await expectLater(
          repoConMock.tienePendientesPara('rescate-1', rescatistaId: 'alb-1'),
          throwsA(isA<FirebaseException>()),
        );
      });

      test('un permission-denied NO cae a la caché — significa que la '
          'consulta no está acotada a lo que las reglas dejan leer (un error '
          'de programación), no que falte señal. Taparlo con la caché fue '
          'justo lo que escondió que este chequeo nunca llegaba a consultar '
          'al servidor', () async {
        final db = MockFirebaseFirestore();
        final col = MockCollectionReference();
        final query = MockQuery();
        when(() => db.collection('solicitudes')).thenReturn(col);
        when(() => col.where(any(), isEqualTo: any(named: 'isEqualTo')))
            .thenReturn(query);
        when(() => query.where(any(), isEqualTo: any(named: 'isEqualTo')))
            .thenReturn(query);
        when(() => query.limit(any())).thenReturn(query);
        when(() => query.get()).thenThrow(FirebaseException(
            plugin: 'cloud_firestore', code: 'permission-denied'));

        final repoConMock = SolicitudesRepository(db: db);
        await expectLater(
          repoConMock.tienePendientesPara('rescate-1', rescatistaId: 'alb-1'),
          throwsA(isA<FirebaseException>()
              .having((e) => e.code, 'code', 'permission-denied')),
        );
        // Y ni siquiera se le preguntó a la caché. (No alcanza con
        // `get(any())`: una llamada sin argumentos queda registrada como
        // `get(null)` y `any()` también la matchea — hay que apuntar
        // explícitamente al pedido con Source.cache.)
        verifyNever(() => query.get(any(
            that: isA<GetOptions>()
                .having((o) => o.source, 'source', Source.cache))));
      });

      test('no cuenta la solicitud de OTRO rescatista aunque apunte al mismo '
          'rescateId — el filtro por dueño no es cosmético, es lo que hace '
          'que el servidor acepte la consulta en vez de rechazarla', () async {
        await firestore.collection('solicitudes').add({
          'rescateId': 'eddy-1', 'rescatistaId': 'otro-albergue',
          'estado': 'pendiente',
        });
        expect(await repo.tienePendientesPara('eddy-1', rescatistaId: 'alb-1'), false);
      });
    });

    group('tuvoSolicitudAprobada', () {
      test('true si hay una solicitud aprobada para ese rescateId', () async {
        await firestore.collection('solicitudes').add({
          'rescateId': 'eddy-1', 'rescatistaId': 'alb-1', 'estado': 'aprobada',
        });
        expect(await repo.tuvoSolicitudAprobada('eddy-1', rescatistaId: 'alb-1'), true);
      });

      test('false si la única solicitud está pendiente o fue rechazada — '
          'a diferencia de tienePendientesPara, acá solo importa "aprobada"', () async {
        await firestore.collection('solicitudes').add({
          'rescateId': 'eddy-1', 'rescatistaId': 'alb-1', 'estado': 'pendiente',
        });
        expect(await repo.tuvoSolicitudAprobada('eddy-1', rescatistaId: 'alb-1'), false);
      });

      test('false si no hay ninguna solicitud para ese rescateId', () async {
        expect(await repo.tuvoSolicitudAprobada('sin-solicitudes', rescatistaId: 'alb-1'), false);
      });

      test('sigue el mismo criterio de tolerancia a fallas que '
          'tienePendientesPara: reintenta una vez antes de rendirse', () async {
        final db = MockFirebaseFirestore();
        final col = MockCollectionReference();
        final query = MockQuery();
        final snapshot = MockQuerySnapshot();
        when(() => db.collection('solicitudes')).thenReturn(col);
        when(() => col.where(any(), isEqualTo: any(named: 'isEqualTo')))
            .thenReturn(query);
        when(() => query.where(any(), isEqualTo: any(named: 'isEqualTo')))
            .thenReturn(query);
        when(() => query.limit(any())).thenReturn(query);
        when(() => snapshot.docs).thenReturn([]);
        var intentos = 0;
        when(() => query.get()).thenAnswer((_) {
          intentos++;
          if (intentos == 1) {
            throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
          }
          return Future.value(snapshot);
        });

        final repoConMock = SolicitudesRepository(db: db);
        expect(await repoConMock.tuvoSolicitudAprobada('rescate-1', rescatistaId: 'alb-1'), false);
        expect(intentos, 2);
      });
    });
  });
}
