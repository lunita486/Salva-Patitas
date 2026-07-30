import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:patitas_medellin/data/creator_role.dart';
import 'package:patitas_medellin/data/rescates_repository.dart';

// fake_cloud_firestore no simula fallas transitorias de red — para probar
// la tolerancia de existeNombre() hace falta controlar a mano cuándo falla
// get() (mismo patrón que solicitudes_repository_test.dart).
class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class MockCollectionReference extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class MockQuery extends Mock implements Query<Map<String, dynamic>> {}

class MockQuerySnapshot extends Mock
    implements QuerySnapshot<Map<String, dynamic>> {}

class MockDocumentReference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUser extends Mock implements User {}

void main() {
  setUpAll(() => registerFallbackValue(const GetOptions()));

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

    test('existeNombre() true si el mismo uid y el mismo rol ya tienen un animal con ese '
        'nombre (sin importar mayúsculas ni espacios)', () async {
      await repo.crear(uid: 'user-4', role: CreatorRole.rescatista, datos: {'nombre': 'Blanquito'});
      expect(await repo.existeNombre(uid: 'user-4', nombre: 'blanquito', role: CreatorRole.rescatista), true);
      expect(await repo.existeNombre(uid: 'user-4', nombre: '  Blanquito  ', role: CreatorRole.rescatista), true);
    });

    test('existeNombre() NO cruza CreatorRole a propósito — una cuenta con rol de '
        'rescatista Y de albergue son "dos negocios" distintos para este aviso; publicar '
        'el mismo nombre en cada uno por separado no es necesariamente un error (decisión '
        'de producto, ver comentario en existeNombre)', () async {
      await repo.crear(uid: 'user-5', role: CreatorRole.rescatista, datos: {'nombre': 'Richard'});
      expect(await repo.existeNombre(uid: 'user-5', nombre: 'Richard', role: CreatorRole.albergue), false);
      expect(await repo.existeNombre(uid: 'user-5', nombre: 'Richard', role: CreatorRole.rescatista), true);
    });

    test('existeNombre() false para otro uid o un nombre distinto', () async {
      await repo.crear(uid: 'user-6', role: CreatorRole.rescatista, datos: {'nombre': 'Blanquito'});
      expect(await repo.existeNombre(uid: 'otro-uid', nombre: 'Blanquito', role: CreatorRole.rescatista), false);
      expect(await repo.existeNombre(uid: 'user-6', nombre: 'Firulais', role: CreatorRole.rescatista), false);
    });

    test('existeNombre() false para nombre vacío — no cuenta como duplicado entre '
        'animales sin nombre', () async {
      await repo.crear(uid: 'user-7', role: CreatorRole.rescatista, datos: {'nombre': ''});
      expect(await repo.existeNombre(uid: 'user-7', nombre: '', role: CreatorRole.rescatista), false);
      expect(await repo.existeNombre(uid: 'user-7', nombre: '   ', role: CreatorRole.rescatista), false);
    });

    test('existeNombre() con especie: false si el nombre y el rol coinciden pero la especie '
        'no — un "Richard" perro no debería chocar con un "Richard" gato del mismo rol', () async {
      await repo.crear(uid: 'user-8', role: CreatorRole.rescatista,
          datos: {'nombre': 'Richard', 'especie': 'Perro'});
      expect(await repo.existeNombre(uid: 'user-8', nombre: 'Richard', role: CreatorRole.rescatista, especie: 'Gato'), false);
      expect(await repo.existeNombre(uid: 'user-8', nombre: 'Richard', role: CreatorRole.rescatista, especie: 'Perro'), true);
    });

    test('existeNombre() sin especie (null) sigue comparando solo por nombre + rol, '
        'para no romper a los llamadores que todavía no la pasan', () async {
      await repo.crear(uid: 'user-9', role: CreatorRole.rescatista,
          datos: {'nombre': 'Richard', 'especie': 'Perro'});
      expect(await repo.existeNombre(uid: 'user-9', nombre: 'Richard', role: CreatorRole.rescatista), true);
    });

    test('buscarDuplicado() devuelve el DOCUMENTO (no solo bool) del animal '
        'existente — para poder ofrecer "Ver ficha existente" en vez de '
        'solo cancelar/continuar a ciegas sobre cuál es el otro animal', () async {
      final ref = await repo.crear(uid: 'user-10', role: CreatorRole.rescatista,
          datos: {'nombre': 'Firulais', 'especie': 'Perro'});
      final encontrado = await repo.buscarDuplicado(
          uid: 'user-10', nombre: 'firulais', role: CreatorRole.rescatista, especie: 'Perro');
      expect(encontrado, isNotNull);
      expect(encontrado!.id, ref.id);
      expect(encontrado.data()['nombre'], 'Firulais');
    });

    test('buscarDuplicado() null si no hay ningún cruce', () async {
      expect(
        await repo.buscarDuplicado(uid: 'user-11', nombre: 'Nadie', role: CreatorRole.rescatista),
        isNull,
      );
    });

    test('existeNombre() si el servidor falla (canal reconectando tras modo '
        'avión) cae a la copia LOCAL y responde con lo que el teléfono ya '
        'sabe — sin esto, la excepción escapaba de _publicar() en las dos '
        'pantallas de subir y el botón "Publicar" moría en silencio, sin '
        'mensaje (mismo bug de raíz que el "no pudimos verificar si se '
        'puede eliminar")', () async {
      final db = MockFirebaseFirestore();
      final col = MockCollectionReference();
      final query = MockQuery();
      final snapshotCache = MockQuerySnapshot();
      when(() => db.collection('rescates')).thenReturn(col);
      when(() => col.where(any(), isEqualTo: any(named: 'isEqualTo')))
          .thenReturn(query);
      when(() => query.where(any(), isEqualTo: any(named: 'isEqualTo')))
          .thenReturn(query);
      when(() => query.get()).thenThrow(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));
      // Solo el pedido explícito a la caché local responde.
      when(() => query.get(any(
              that: isA<GetOptions>()
                  .having((o) => o.source, 'source', Source.cache))))
          .thenAnswer((_) async => snapshotCache);
      when(() => snapshotCache.docs).thenReturn([]);

      final repoConMock = RescatesRepository(db: db);
      expect(
        await repoConMock.existeNombre(
            uid: 'u1', nombre: 'Richard', role: CreatorRole.rescatista),
        false,
      );
    });

    test('existeNombre() si hasta la caché local falla devuelve false en vez '
        'de propagar — es un aviso de cortesía, no una barrera: mejor '
        'publicar sin el aviso de duplicados que bloquear la publicación', () async {
      final db = MockFirebaseFirestore();
      final col = MockCollectionReference();
      final query = MockQuery();
      when(() => db.collection('rescates')).thenReturn(col);
      when(() => col.where(any(), isEqualTo: any(named: 'isEqualTo')))
          .thenReturn(query);
      when(() => query.where(any(), isEqualTo: any(named: 'isEqualTo')))
          .thenReturn(query);
      when(() => query.get()).thenThrow(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));
      when(() => query.get(any())).thenThrow(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));

      final repoConMock = RescatesRepository(db: db);
      expect(
        await repoConMock.existeNombre(
            uid: 'u1', nombre: 'Richard', role: CreatorRole.rescatista),
        false,
      );
    });

    test('nuevoRef() genera un id sin escribir nada todavía', () async {
      final ref = repo.nuevoRef();
      expect(ref.id, isNotEmpty);
      final doc = await ref.get();
      expect(doc.exists, false);
    });

    test('crear() con ref: usa exactamente ese id en vez de generar uno nuevo — '
        'así el llamador conoce el id ANTES de que la escritura termine, y puede '
        'hacer rollback aunque un timeout se dispare antes de que el create '
        'realmente resuelva (Future.timeout no cancela la escritura original)', () async {
      final miRef = repo.nuevoRef();
      final ref = await repo.crear(
        ref: miRef,
        uid: 'user-3',
        role: CreatorRole.rescatista,
        datos: {'nombre': 'Amy'},
      );
      expect(ref.id, miRef.id);
      final doc = await miRef.get();
      expect(doc['nombre'], 'Amy');
      expect(doc['rescatistaId'], 'user-3');
    });

    test('eliminar() borra el documento', () async {
      final ref = await firestore.collection('rescates').add({'nombre': 'X'});
      await repo.eliminar(ref.id);
      final doc = await ref.get();
      expect(doc.exists, false);
    });

    group('eliminar() — permission-denied casi siempre es un token vencido, '
        'no falta de permiso real (la regla solo compara rescatistaId '
        'contra el uid actual, y si se ve el botón de eliminar ya se sabe '
        'que la cuenta es la dueña) — el bug real: probar mucho rato '
        'alternando modo avión/señal dejaba el token desactualizado y el '
        'borrado fallaba con un mensaje técnico en inglés sin ninguna '
        'acción clara', () {
      test('en permission-denied, renueva el token y reintenta UNA vez — '
          'si con el token nuevo funciona, no se entera nadie', () async {
        final db = MockFirebaseFirestore();
        final col = MockCollectionReference();
        final ref = MockDocumentReference();
        final auth = MockFirebaseAuth();
        final user = MockUser();
        when(() => db.collection('rescates')).thenReturn(col);
        when(() => col.doc('r1')).thenReturn(ref);
        when(() => auth.currentUser).thenReturn(user);
        when(() => user.getIdToken(true)).thenAnswer((_) async => 'token-nuevo');
        var intentos = 0;
        when(() => ref.delete()).thenAnswer((_) {
          intentos++;
          if (intentos == 1) {
            throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
          }
          return Future.value();
        });

        final repoConMock = RescatesRepository(db: db, auth: auth);
        await repoConMock.eliminar('r1');

        expect(intentos, 2);
        verify(() => user.getIdToken(true)).called(1);
      });

      test('si sigue fallando con permission-denied incluso con el token '
          'renovado, propaga la excepción — no es un reintento infinito', () async {
        final db = MockFirebaseFirestore();
        final col = MockCollectionReference();
        final ref = MockDocumentReference();
        final auth = MockFirebaseAuth();
        final user = MockUser();
        when(() => db.collection('rescates')).thenReturn(col);
        when(() => col.doc('r1')).thenReturn(ref);
        when(() => auth.currentUser).thenReturn(user);
        when(() => user.getIdToken(true)).thenAnswer((_) async => 'token-nuevo');
        when(() => ref.delete()).thenThrow(
            FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));

        final repoConMock = RescatesRepository(db: db, auth: auth);
        await expectLater(
          repoConMock.eliminar('r1'),
          throwsA(isA<FirebaseException>()),
        );
      });

      test('en cualquier OTRO error (ej. sin conexión) NO reintenta ni '
          'toca el token — el refresh forzado es específico del caso '
          'permission-denied', () async {
        final db = MockFirebaseFirestore();
        final col = MockCollectionReference();
        final ref = MockDocumentReference();
        final auth = MockFirebaseAuth();
        when(() => db.collection('rescates')).thenReturn(col);
        when(() => col.doc('r1')).thenReturn(ref);
        when(() => ref.delete()).thenThrow(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));

        final repoConMock = RescatesRepository(db: db, auth: auth);
        await expectLater(
          repoConMock.eliminar('r1'),
          throwsA(isA<FirebaseException>()),
        );
        verifyNever(() => auth.currentUser);
      });
    });

    group('eliminar() también limpia favoritos huérfanos — sin esto, un '
        'animal borrado seguía viéndose en Favoritos del adoptante como si '
        'siguiera disponible, con un botón "Adoptar" apuntando a un rescate '
        'que ya no existe (el bug real que reportó Eliza)', () {
      test('borra los favoritos que apuntan a ese rescate y son de este '
          'rescatista, y deja intactos los de otros animales', () async {
        final auth = MockFirebaseAuth();
        final user = MockUser();
        when(() => auth.currentUser).thenReturn(user);
        when(() => user.uid).thenReturn('rescatista-1');
        final repoConAuth = RescatesRepository(db: firestore, auth: auth);

        final ref = await firestore.collection('rescates').add({'nombre': 'Firulais'});
        await firestore.collection('favoritos').add({
          'rescateId': ref.id, 'adoptanteId': 'adoptante-1', 'rescatistaId': 'rescatista-1',
        });
        final otroRef = await firestore.collection('rescates').add({'nombre': 'Otro'});
        await firestore.collection('favoritos').add({
          'rescateId': otroRef.id, 'adoptanteId': 'adoptante-2', 'rescatistaId': 'rescatista-1',
        });

        await repoConAuth.eliminar(ref.id);
        // eliminar() no espera esta limpieza (fire-and-forget a propósito
        // — ver comentario en el repositorio: no tiene sentido que quien
        // borra SU animal espere por una limpieza que ni es su acción).
        // pumpEventQueue() le da tiempo a esa tarea de fondo a terminar
        // antes de verificar.
        await pumpEventQueue();

        final restantes = await firestore.collection('favoritos').get();
        expect(restantes.docs.length, 1);
        expect(restantes.docs.first['rescateId'], otroRef.id);
      });

      test('no toca favoritos de otro rescatista que por algún motivo '
          'apunten al mismo rescateId', () async {
        final auth = MockFirebaseAuth();
        final user = MockUser();
        when(() => auth.currentUser).thenReturn(user);
        when(() => user.uid).thenReturn('rescatista-1');
        final repoConAuth = RescatesRepository(db: firestore, auth: auth);

        final ref = await firestore.collection('rescates').add({'nombre': 'Firulais'});
        await firestore.collection('favoritos').add({
          'rescateId': ref.id, 'adoptanteId': 'adoptante-1', 'rescatistaId': 'otro-rescatista',
        });

        await repoConAuth.eliminar(ref.id);
        await pumpEventQueue();

        final restantes = await firestore.collection('favoritos').get();
        expect(restantes.docs.length, 1);
      });

      test('si falla la limpieza de favoritos (ej. sin auth), no revienta '
          'eliminar() — el borrado del rescate ya pedido no debe bloquearse '
          'por una limpieza secundaria', () async {
        final ref = await firestore.collection('rescates').add({'nombre': 'X'});
        await expectLater(repo.eliminar(ref.id), completes);
      });

      test('eliminar() NO espera a que termine la limpieza de favoritos — '
          'antes sí lo hacía (con `await`), y eso sumaba los timeouts de '
          '_borrarFavoritos (hasta 10s) DENTRO de eliminar(), sosteniendo '
          'de más el guard `_eliminando` de las pantallas: el bug real que '
          'reportó Eliza fue "borro un animalito bien, y al borrar el '
          'siguiente dice que hay una eliminación en curso" — la tarjeta '
          'ya había desaparecido pero el guard seguía trabado esperando '
          'esta limpieza silenciosa de fondo', () async {
        final db = MockFirebaseFirestore();
        final rescatesCol = MockCollectionReference();
        final ref = MockDocumentReference();
        final favoritosCol = MockCollectionReference();
        final query1 = MockQuery();
        final query2 = MockQuery();
        final auth = MockFirebaseAuth();
        final user = MockUser();
        when(() => db.collection('rescates')).thenReturn(rescatesCol);
        when(() => rescatesCol.doc('r1')).thenReturn(ref);
        when(() => ref.delete()).thenAnswer((_) async {});
        when(() => auth.currentUser).thenReturn(user);
        when(() => user.uid).thenReturn('rescatista-1');
        when(() => db.collection('favoritos')).thenReturn(favoritosCol);
        when(() => favoritosCol.where('rescateId', isEqualTo: 'r1')).thenReturn(query1);
        when(() => query1.where('rescatistaId', isEqualTo: 'rescatista-1')).thenReturn(query2);
        // La consulta de favoritos nunca resuelve — simula una limpieza de
        // fondo lenta/colgada. Si eliminar() todavía la esperara, este test
        // se colgaría hasta el timeout de 2s de acá abajo.
        when(() => query2.get()).thenAnswer((_) => Completer<QuerySnapshot<Map<String, dynamic>>>().future);

        final repoConMock = RescatesRepository(db: db, auth: auth);
        await expectLater(
          repoConMock.eliminar('r1').timeout(const Duration(seconds: 2)),
          completes,
        );
      });
    });

    group('mensajeErrorEliminar() — el texto que ve la usuaria si eliminar() '
        'termina fallando de verdad', () {
      test('permission-denied → sugiere renovar sesión, no jerga técnica', () {
        final msg = RescatesRepository.mensajeErrorEliminar(
            FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
        expect(msg, contains('sesión'));
        expect(msg, isNot(contains('cloud_firestore')));
      });

      test('cualquier otro error → mensaje genérico de conexión', () {
        expect(
          RescatesRepository.mensajeErrorEliminar(
              FirebaseException(plugin: 'cloud_firestore', code: 'unavailable')),
          contains('conexión'),
        );
        expect(RescatesRepository.mensajeErrorEliminar(Exception('cualquier cosa')),
            contains('conexión'));
      });

      // Nota histórica: acá hubo un test para un mensaje especial de
      // TimeoutException ("estamos sin señal", después "está tardando").
      // Se quitó la rama entera a propósito: timeout ≠ error (el borrado
      // encolado se aplica solo al reconectar, y la Cloud Function
      // onRescateEliminado limpia fotos/favoritos en el servidor), así
      // que las pantallas atrapan TimeoutException ANTES de llamar acá y
      // muestran el mismo "Publicación eliminada" del camino feliz — dos
      // mensajes especiales distintos confundieron en las pruebas reales
      // (reporte de Eliza: "si borra el animalito, ¿para qué saca ese
      // mensaje?").
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

    group('obtener() — lectura puntual usada para chequear el estado real '
        'de un animal justo antes de eliminarlo', () {
      test('devuelve el documento con sus datos actuales', () async {
        final ref = await firestore.collection('rescates').add({
          'nombre': 'Sarita', 'estadoAdopcion': 'Hogar de paso',
        });

        final doc = await repo.obtener(ref.id);

        expect(doc.exists, isTrue);
        expect(doc.data()?['nombre'], 'Sarita');
        expect(doc.data()?['estadoAdopcion'], 'Hogar de paso');
      });

      test('un id que no existe devuelve un doc sin datos, no una excepción — '
          'el llamador decide qué hacer (bloquear el borrado por las dudas)', () async {
        final doc = await repo.obtener('no-existe');

        expect(doc.exists, isFalse);
        expect(doc.data(), isNull);
      });
    });

    group('porId() — stream de un rescate, para pantallas que reaccionan en '
        'vivo a cambios de estado (chat_screen.dart)', () {
      test('emite el documento con sus datos actuales', () async {
        final ref = await firestore.collection('rescates').add({
          'nombre': 'Toby', 'estadoAdopcion': 'Rescatado',
        });

        final doc = await repo.porId(ref.id).first;

        expect(doc.exists, isTrue);
        expect(doc.data()?['nombre'], 'Toby');
      });

      test('vuelve a emitir cuando el documento cambia', () async {
        final ref = await firestore.collection('rescates').add({
          'nombre': 'Toby', 'estadoAdopcion': 'Rescatado',
        });

        final emisiones = <String?>[];
        final sub = repo.porId(ref.id).listen((doc) =>
            emisiones.add(doc.data()?['estadoAdopcion'] as String?));

        await Future.delayed(Duration.zero);
        await ref.update({'estadoAdopcion': 'Adoptado'});
        await Future.delayed(Duration.zero);
        await sub.cancel();

        expect(emisiones, containsAllInOrder(['Rescatado', 'Adoptado']));
      });
    });

    group('porNombreYDueno() — fallback para chats/solicitudes viejos sin '
        'rescateId guardado (mismo criterio que actualizarPorNombre)', () {
      test('encuentra el rescate por nombre + rescatistaId', () async {
        await firestore.collection('rescates').add({
          'nombre': 'Rocky', 'rescatistaId': 'user-9', 'estadoAdopcion': 'Rescatado',
        });
        await firestore.collection('rescates').add({
          'nombre': 'Rocky', 'rescatistaId': 'otro-uid', 'estadoAdopcion': 'Adoptado',
        });

        final snap = await repo.porNombreYDueno(
            rescatistaId: 'user-9', nombre: 'Rocky').first;

        expect(snap.docs.length, 1);
        expect(snap.docs.first['rescatistaId'], 'user-9');
      });

      test('vacío si no hay ningún rescate con ese nombre+dueño', () async {
        final snap = await repo.porNombreYDueno(
            rescatistaId: 'user-9', nombre: 'Sin publicar').first;

        expect(snap.docs, isEmpty);
      });
    });

    group('bloqueoParaEliminar() — centraliza los 3 chequeos que antes '
        'estaban duplicados en mis_rescates_screen.dart y '
        'editar_rescate_screen.dart', () {
      test('null (se puede eliminar) si está Rescatado, sin pendientes y sin aprobada previa', () async {
        final ref = await firestore.collection('rescates').add({
          'nombre': 'Toby', 'estadoAdopcion': 'Rescatado',
        });

        final bloqueo = await repo.bloqueoParaEliminar(rescateId: ref.id, nombre: 'Toby');

        expect(bloqueo, isNull);
      });

      test('bloquea con el mensaje de solicitud pendiente, incluso si el estado ya es Rescatado', () async {
        final ref = await firestore.collection('rescates').add({
          'nombre': 'Toby', 'estadoAdopcion': 'Rescatado',
        });
        await firestore.collection('solicitudes').add({
          'rescateId': ref.id, 'estado': 'pendiente',
        });

        final bloqueo = await repo.bloqueoParaEliminar(rescateId: ref.id, nombre: 'Toby');

        expect(bloqueo?.$1, 'No se puede eliminar todavía');
        expect(bloqueo?.$2, contains('solicitud esperando respuesta'));
      });

      test('bloquea con el mensaje del estado actual si no está Rescatado', () async {
        final ref = await firestore.collection('rescates').add({
          'nombre': 'Toby', 'estadoAdopcion': 'Hogar de paso',
        });

        final bloqueo = await repo.bloqueoParaEliminar(rescateId: ref.id, nombre: 'Toby');

        expect(bloqueo, RescatesRepository.mensajeBloqueoEliminar('Hogar de paso', 'Toby'));
      });

      test('bloquea como registro permanente si tuvo una solicitud aprobada alguna vez, '
          'aunque el estado ACTUAL ya esté de vuelta en Rescatado (revertido a mano)', () async {
        final ref = await firestore.collection('rescates').add({
          'nombre': 'Toby', 'estadoAdopcion': 'Rescatado',
        });
        await firestore.collection('solicitudes').add({
          'rescateId': ref.id, 'estado': 'aprobada',
        });

        final bloqueo = await repo.bloqueoParaEliminar(rescateId: ref.id, nombre: 'Toby');

        expect(bloqueo?.$1, 'No se puede eliminar');
        expect(bloqueo?.$2, contains('registro permanente'));
      });

      test('la solicitud pendiente gana sobre "tuvo aprobada" cuando las dos aplican — '
          'mismo orden de prioridad que la versión secuencial que reemplaza', () async {
        final ref = await firestore.collection('rescates').add({
          'nombre': 'Toby', 'estadoAdopcion': 'Rescatado',
        });
        await firestore.collection('solicitudes').add({
          'rescateId': ref.id, 'estado': 'aprobada',
        });
        await firestore.collection('solicitudes').add({
          'rescateId': ref.id, 'estado': 'pendiente',
        });

        final bloqueo = await repo.bloqueoParaEliminar(rescateId: ref.id, nombre: 'Toby');

        expect(bloqueo?.$2, contains('solicitud esperando respuesta'));
      });
    });
  });
}
