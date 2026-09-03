import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salva_patitas/data/creator_role.dart';
import 'package:salva_patitas/domain/reglas_negocio.dart';
import 'package:salva_patitas/data/solicitudes_repository.dart';

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
        'rescatistaId': uid,
        'creadoPor': 'rescatista',
        'estado': 'pendiente',
        'animalNombre': 'Henry',
      });
      await firestore.collection('solicitudes').add({
        'rescatistaId': uid,
        'creadoPor': 'albergue',
        'estado': 'pendiente',
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

    test(
      'misSolicitudes no depende de CreatorRole, solo de adoptanteId',
      () async {
        const uid = 'adoptante-1';
        await firestore.collection('solicitudes').add({
          'adoptanteId': uid,
          'animalNombre': 'Olafo',
        });
        await firestore.collection('solicitudes').add({
          'adoptanteId': 'otro',
          'animalNombre': 'Otro',
        });

        final mias = await repo.misSolicitudes(uid).first;
        expect(mias.docs.length, 1);
        expect(mias.docs.first['animalNombre'], 'Olafo');
      },
    );

    group('fotoUrlPorAnimalNombre (backfill de foto en la lista de Chats)', () {
      test(
        'devuelve la fotoUrl de la solicitud de ese adoptante para ese animal',
        () async {
          await firestore.collection('solicitudes').add({
            'adoptanteId': 'a1',
            'animalNombre': 'Toby',
            'fotoUrl': 'https://x/toby.jpg',
          });

          final foto = await repo.fotoUrlPorAnimalNombre(
            adoptanteId: 'a1',
            animalNombre: 'Toby',
          );

          expect(foto, 'https://x/toby.jpg');
        },
      );

      test(
        'null si no hay ninguna solicitud de ese adoptante para ese animal',
        () async {
          await firestore.collection('solicitudes').add({
            'adoptanteId': 'otro',
            'animalNombre': 'Toby',
            'fotoUrl': 'https://x/toby.jpg',
          });

          final foto = await repo.fotoUrlPorAnimalNombre(
            adoptanteId: 'a1',
            animalNombre: 'Toby',
          );

          expect(foto, isNull);
        },
      );

      test(
        'null (no revienta) si la solicitud encontrada no tiene fotoUrl',
        () async {
          await firestore.collection('solicitudes').add({
            'adoptanteId': 'a1',
            'animalNombre': 'Toby',
          });

          final foto = await repo.fotoUrlPorAnimalNombre(
            adoptanteId: 'a1',
            animalNombre: 'Toby',
          );

          expect(foto, isNull);
        },
      );
    });

    test(
      'crear() denormaliza creadoPor a partir del CreatorRole recibido',
      () async {
        final ref = await repo.crear(
          adoptanteUid: 'a1',
          rescatistaId: 'r1',
          creadoPor: CreatorRole.albergue,
          datos: {'animalNombre': 'Toby'},
        );
        final doc = await ref.get();
        expect(doc['creadoPor'], 'albergue');
        expect(doc['estado'], 'pendiente');
      },
    );

    test(
      'estadoExistente devuelve el estado de una solicitud pendiente/aprobada, o null',
      () async {
        expect(
          await repo.estadoExistente(uid: 'a1', animalNombre: 'Henry'),
          null,
        );

        await firestore.collection('solicitudes').add({
          'adoptanteId': 'a1',
          'animalNombre': 'Henry',
          'estado': 'aprobada',
        });
        expect(
          await repo.estadoExistente(uid: 'a1', animalNombre: 'Henry'),
          'aprobada',
        );
      },
    );

    test('estadoExistente con rescateId distingue dos animales con el mismo '
        'nombre (antes aplicar a uno bloqueaba aplicar al otro)', () async {
      await firestore.collection('solicitudes').add({
        'adoptanteId': 'a1',
        'animalNombre': 'Luna',
        'rescateId': 'luna-1',
        'estado': 'aprobada',
      });

      // Misma persona, mismo nombre de animal, pero rescateId distinto:
      // no debería contar como "ya aplicó" a este segundo animal.
      expect(
        await repo.estadoExistente(
          uid: 'a1',
          animalNombre: 'Luna',
          rescateId: 'luna-2',
        ),
        null,
      );
      // Al animal correcto (mismo rescateId) sí lo detecta.
      expect(
        await repo.estadoExistente(
          uid: 'a1',
          animalNombre: 'Luna',
          rescateId: 'luna-1',
        ),
        'aprobada',
      );
    });

    test('cambiarEstado actualiza el campo estado', () async {
      final ref = await firestore.collection('solicitudes').add({
        'estado': 'pendiente',
      });
      await repo.cambiarEstado(ref.id, 'aprobada');
      final doc = await ref.get();
      expect(doc['estado'], 'aprobada');
    });

    test(
      'rechazar() guarda estado y motivoRechazo juntos (a diferencia de cambiarEstado)',
      () async {
        final ref = await firestore.collection('solicitudes').add({
          'estado': 'pendiente',
        });
        await repo.rechazar(ref.id, 'No cumple con los requisitos');
        final doc = await ref.get();
        expect(doc['estado'], 'rechazada');
        expect(doc['motivoRechazo'], 'No cumple con los requisitos');
      },
    );

    test(
      'aceptarAcuerdo marca acuerdoAceptado=true y guarda la fecha del servidor '
      '("registro del acuerdo de adopción", versión simple sin firma ni PDF)',
      () async {
        final ref = await firestore.collection('solicitudes').add({
          'estado': 'aprobada',
        });
        await repo.aceptarAcuerdo(ref.id);
        final doc = await ref.get();
        expect(doc['acuerdoAceptado'], true);
        expect(doc['acuerdoAceptadoEn'], isNotNull);
      },
    );

    test(
      'rechazarCompetidoras rechaza las demás solicitudes PENDIENTES por el mismo animal, '
      'sin tocar la aprobada ni las de otro animal',
      () async {
        final aprobada = await firestore.collection('solicitudes').add({
          'animalNombre': 'Rocky',
          'rescatistaId': 'r1',
          'estado': 'pendiente',
          'adoptanteId': 'ganador',
        });
        final competidora = await firestore.collection('solicitudes').add({
          'animalNombre': 'Rocky',
          'rescatistaId': 'r1',
          'estado': 'pendiente',
          'adoptanteId': 'perdedor',
        });
        final yaRechazadaAntes = await firestore.collection('solicitudes').add({
          'animalNombre': 'Rocky',
          'rescatistaId': 'r1',
          'estado': 'rechazada',
          'adoptanteId': 'viejo',
        });
        final otroAnimal = await firestore.collection('solicitudes').add({
          'animalNombre': 'Otro',
          'rescatistaId': 'r1',
          'estado': 'pendiente',
          'adoptanteId': 'x',
        });

        final rechazadas = await repo.rechazarCompetidoras(
          animalNombre: 'Rocky',
          rescatistaId: 'r1',
          excluirDocId: aprobada.id,
        );

        expect(rechazadas.length, 1);
        expect(rechazadas.first['adoptanteId'], 'perdedor');
        expect((await competidora.get())['estado'], 'rechazada');
        expect((await aprobada.get())['estado'], 'pendiente');
        expect((await yaRechazadaAntes.get())['estado'], 'rechazada');
        expect((await otroAnimal.get())['estado'], 'pendiente');
      },
    );

    test(
      'rechazarCompetidoras con rescateId no confunde dos animales con el mismo nombre',
      () async {
        final ganadorRocky1 = await firestore.collection('solicitudes').add({
          'animalNombre': 'Rocky',
          'rescatistaId': 'r1',
          'rescateId': 'rocky-1',
          'estado': 'pendiente',
          'adoptanteId': 'ganador',
        });
        final otroRocky2 = await firestore.collection('solicitudes').add({
          'animalNombre': 'Rocky',
          'rescatistaId': 'r1',
          'rescateId': 'rocky-2',
          'estado': 'pendiente',
          'adoptanteId': 'no-deberia-tocarse',
        });

        final rechazadas = await repo.rechazarCompetidoras(
          animalNombre: 'Rocky',
          rescatistaId: 'r1',
          excluirDocId: ganadorRocky1.id,
          rescateId: 'rocky-1',
        );

        expect(rechazadas, isEmpty);
        expect((await otroRocky2.get())['estado'], 'pendiente');
      },
    );

    // ── Cerrar las pendientes cuando el animalito fallece ────────────────
    //
    // El hueco: marcar Fallecido avisaba bien a todo el mundo, pero las
    // solicitudes `pendiente` se quedaban asi. Con dos o mas adoptantes,
    // habia que rechazarlas a mano una por una. Y la app ya sabia que no
    // podian seguir vivas: aprobarSiDisponible las rechaza con este mismo
    // motivo si alguien toca Aprobar; solo esperaba a que alguien lo
    // tocara.
    group('rechazarPendientesPorFallecimiento', () {
      /// Siembra el caso completo: dos pendientes del animal, una aprobada,
      /// una rechazada, una de otro animal y una de otro dueño.
      Future<Map<String, DocumentReference>> sembrarTodo() async {
        final col = firestore.collection('solicitudes');
        return {
          'ana': await col.add({
            'rescateId': 'r1', 'rescatistaId': 'refugio1',
            'estado': 'pendiente', 'adoptanteId': 'ana', 'nombre': 'Ana',
          }),
          'beto': await col.add({
            'rescateId': 'r1', 'rescatistaId': 'refugio1',
            'estado': 'pendiente', 'adoptanteId': 'beto', 'nombre': 'Beto',
          }),
          'aprobada': await col.add({
            'rescateId': 'r1', 'rescatistaId': 'refugio1',
            'estado': 'aprobada', 'adoptanteId': 'cami',
          }),
          'rechazada': await col.add({
            'rescateId': 'r1', 'rescatistaId': 'refugio1',
            'estado': 'rechazada', 'adoptanteId': 'dani',
            'motivoRechazo': 'motivo viejo',
          }),
          'otroAnimal': await col.add({
            'rescateId': 'otro-animal', 'rescatistaId': 'refugio1',
            'estado': 'pendiente', 'adoptanteId': 'eva',
          }),
          'otroDueno': await col.add({
            'rescateId': 'r1', 'rescatistaId': 'otro-refugio',
            'estado': 'pendiente', 'adoptanteId': 'fabi',
          }),
        };
      }

      test('cierra las pendientes de ESE rescate y devuelve las afectadas',
          () async {
        final docs = await sembrarTodo();

        final cerradas = await repo.rechazarPendientesPorFallecimiento(
          rescateId: 'r1',
          rescatistaId: 'refugio1',
        );

        expect(cerradas.length, 2);
        expect(cerradas.map((c) => c['adoptanteId']), containsAll(['ana', 'beto']));
        for (final k in ['ana', 'beto']) {
          final d = await docs[k]!.get();
          expect(d['estado'], 'rechazada', reason: k);
          expect(d['motivoRechazo'], SolicitudesRepository.motivoFallecido);
        }
      });

      test('NO toca las aprobadas', () async {
        final docs = await sembrarTodo();
        await repo.rechazarPendientesPorFallecimiento(
          rescateId: 'r1', rescatistaId: 'refugio1');

        final d = await docs['aprobada']!.get();
        expect(d['estado'], 'aprobada');
        expect((d.data() as Map).containsKey('motivoRechazo'), isFalse);
      });

      test('NO toca las ya rechazadas, ni les pisa su motivo', () async {
        final docs = await sembrarTodo();
        await repo.rechazarPendientesPorFallecimiento(
          rescateId: 'r1', rescatistaId: 'refugio1');

        final d = await docs['rechazada']!.get();
        expect(d['estado'], 'rechazada');
        expect(d['motivoRechazo'], 'motivo viejo');
      });

      test('NO toca las pendientes de otro animal ni de otro dueño', () async {
        final docs = await sembrarTodo();
        await repo.rechazarPendientesPorFallecimiento(
          rescateId: 'r1', rescatistaId: 'refugio1');

        expect((await docs['otroAnimal']!.get())['estado'], 'pendiente');
        expect((await docs['otroDueno']!.get())['estado'], 'pendiente');
      });

      test('sin pendientes, devuelve vacío y no escribe nada', () async {
        final col = firestore.collection('solicitudes');
        final aprobada = await col.add({
          'rescateId': 'r1', 'rescatistaId': 'refugio1',
          'estado': 'aprobada', 'adoptanteId': 'cami',
        });

        final cerradas = await repo.rechazarPendientesPorFallecimiento(
          rescateId: 'r1', rescatistaId: 'refugio1');

        expect(cerradas, isEmpty);
        expect((await aprobada.get())['estado'], 'aprobada');
      });

      // EL test que protege contra la trampa del orden. La lista devuelta es
      // la que se usa para avisar: si cerrara mas de lo que devuelve, alguien
      // se quedaria sin enterarse de que su animalito fallecio.
      test('devuelve EXACTAMENTE a quienes hay que avisar', () async {
        await sembrarTodo();

        // A quienes hay que avisar, leido de la base DIRECTAMENTE y antes
        // de cerrar. A proposito no pasa por el repositorio: un oraculo que
        // usara el mismo codigo que se esta probando no probaria nada.
        final aAvisarAntes = (await firestore
                .collection('solicitudes')
                .where('rescateId', isEqualTo: 'r1')
                .where('rescatistaId', isEqualTo: 'refugio1')
                .where('estado', isEqualTo: 'pendiente')
                .get())
            .docs
            .map((d) => d['adoptanteId'])
            .toSet();

        final cerradas = await repo.rechazarPendientesPorFallecimiento(
          rescateId: 'r1', rescatistaId: 'refugio1');

        expect(
          cerradas.map((c) => c['adoptanteId']).toSet(),
          aAvisarAntes,
          reason: 'cerrar y saber a quien avisar tienen que dar lo mismo, o '
              'alguien se queda sin aviso',
        );
      });

      test('el motivo es el MISMO que usa aprobarSiDisponible', () async {
        // Dos caminos para el mismo hecho: marcar Fallecido, e intentar
        // aprobar un animal ya fallecido. Con el texto escrito dos veces, la
        // misma persona podia recibir dos redacciones distintas.
        await firestore.collection('rescates').doc('r1').set({
          'estadoAdopcion': 'Fallecido',
          'rescatistaId': 'refugio1',
          'creadoPor': 'albergue',
        });
        final sol = await firestore.collection('solicitudes').add({
          'rescateId': 'r1', 'rescatistaId': 'refugio1',
          'estado': 'pendiente', 'adoptanteId': 'ana',
        });

        await repo.aprobarSiDisponible(
          solicitudId: sol.id,
          rescateId: 'r1',
          adoptanteId: 'ana',
          nuevoEstadoAdopcion: 'En proceso de adopción',
        );

        expect(
          (await sol.get())['motivoRechazo'],
          SolicitudesRepository.motivoFallecido,
        );
      });

      // Sirve igual para los dos roles: rescatistaId es el uid del dueño en
      // ambos casos, el mismo campo que filtran las demas consultas.
      test('funciona igual para rescatista y para albergue', () async {
        final col = firestore.collection('solicitudes');
        final delRescatista = await col.add({
          'rescateId': 'r-resc', 'rescatistaId': 'rita',
          'estado': 'pendiente', 'adoptanteId': 'ana', 'creadoPor': 'rescatista',
        });
        final delAlbergue = await col.add({
          'rescateId': 'r-alb', 'rescatistaId': 'refugio1',
          'estado': 'pendiente', 'adoptanteId': 'beto', 'creadoPor': 'albergue',
        });

        expect(
          (await repo.rechazarPendientesPorFallecimiento(
            rescateId: 'r-resc', rescatistaId: 'rita')).length,
          1,
        );
        expect(
          (await repo.rechazarPendientesPorFallecimiento(
            rescateId: 'r-alb', rescatistaId: 'refugio1')).length,
          1,
        );
        expect((await delRescatista.get())['estado'], 'rechazada');
        expect((await delAlbergue.get())['estado'], 'rechazada');
      });
    });

    // El flujo de Fallecido tiene que CERRAR y avisar con UNA sola llamada.
    // Hubo un metodo de solo lectura (pendientesPara) que se uso para eso y
    // ya no existe; si alguien vuelve a partir esto en dos pasos —leer a
    // quien avisar por un lado, cerrar por el otro— el orden entre los dos
    // vuelve a poder equivocarse, y cerrar primero deja a todos sin aviso.
    // Es el bug que Eliza ya reporto una vez.
    group('el flujo de Fallecido usa una sola operacion', () {
      final sheet = File('lib/widgets/cambiar_estado_sheet.dart')
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');

      test('llama a rechazarPendientesPorFallecimiento', () {
        expect(sheet, contains('rechazarPendientesPorFallecimiento('));
      });

      test('una sola vez, y sin una consulta aparte de pendientes', () {
        expect(
          'rechazarPendientesPorFallecimiento('.allMatches(sheet).length,
          1,
          reason: 'dos llamadas serian dos listas y dos cierres',
        );
        expect(
          sheet,
          isNot(contains('.pendientesPara(')),
          reason: 'volvio a existir una lectura aparte de las pendientes: el '
              'orden entre cerrar y avisar vuelve a poder equivocarse',
        );
      });

      // El chat guarda su PROPIA copia de la foto y la especie del
      // animalito, y la lista de conversaciones lee esa copia, nunca el
      // animal. Si el aviso no las manda, el chat nace sin las dos: emoji
      // en vez de la foto, y 🐶 para un gato, porque la especie ausente cae
      // al default 'Perro'. Caso real visto en produccion el 2026-09-02.
      test('le pasa la foto y la especie del animalito al aviso', () {
        expect(
          sheet,
          contains('fotoUrl: fotoUrlReal'),
          reason: 'el chat nuevo vuelve a nacer sin foto: emoji en la lista',
        );
        expect(
          sheet,
          contains('especie: especieReal'),
          reason: 'sin especie, la lista le pone 🐶 a un gato',
        );
        // Y que las dos salgan del ANIMAL, no de un dato de la pantalla: el
        // nombre que ve la hoja puede ser el placeholder "Sin nombre", que
        // es justo lo que hacia confundibles a dos animalitos distintos.
        expect(sheet, contains("datos?['fotoUrl']"));
        expect(sheet, contains("datos?['especie']"));
      });

      // Las tres salen del MISMO get. Un segundo obtener(docId) seria una
      // lectura de mas por cada animalito que muere, para un dato que ya
      // estaba en la mano.
      test('sin una lectura extra del rescate', () {
        expect(
          'obtener(docId)'.allMatches(sheet).length,
          1,
          reason: 'creadoPor, fotoUrl y especie salen de la misma lectura',
        );
      });
    });

    // 'Hogar de paso' no puede ofrecerse mientras hay una adopcion en
    // curso. La forma correcta de terminar esa adopcion es RECHAZAR la
    // solicitud, que devuelve el animalito a 'Rescatado'; recien desde ahi
    // se puede pedir hogar de paso. Sin esto, pasar de 'En proceso de
    // adopcion' a 'Hogar de paso' dejaba la adopcion a medias y el
    // adoptanteIdEnProceso del adoptante colgando de un hogar de paso que
    // es de otra persona. Hallazgo de Eliza en el APK109.
    //
    // La regla NO es nueva: es sePuedeSerHogarDePaso, la misma que ya usa
    // el panel "¿como queres ayudar?" del adoptante. Este grupo custodia
    // que la hoja la reutilice en vez de escribir otra lista de estados.
    group('la hoja no ofrece Hogar de paso cuando no corresponde', () {
      final sheet = File('lib/widgets/cambiar_estado_sheet.dart')
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');

      test('usa una regla con nombre, no una lista propia', () {
        expect(sheet, contains('hayAdopcionEnCurso(estadoActual)'));
        // Las 4 veces que el literal aparece legitimamente:
        //   1. la entrada de la lista _estados
        //   2. el filtro de _estadosOfrecidos
        //   3. el destino, en el onTap
        //   4. el estado ACTUAL, para no volver a pedir el formulario
        // Una quinta seria una condicion escrita a mano en vez de una regla
        // con nombre, que es lo que este test existe para impedir.
        expect(
          "'Hogar de paso'".allMatches(sheet).length,
          lessThanOrEqualTo(4),
          reason: 'aparecio una lista de estados escrita a mano en la hoja',
        );
      });

      test('el estado ACTUAL se sigue mostrando', () {
        expect(sheet, contains('e.\$1 == estadoActual'));
      });

      // La regla en si, con los estados reales. Es sePuedeSerHogarDePaso,
      // que ya tiene sus tests propios en reglas_negocio_test; aca se
      // comprueban los casos que pidio Eliza para ESTA pantalla.
      test('la regla bloquea SOLO la adopcion en curso', () {
        expect(hayAdopcionEnCurso('En proceso de adopción'), isTrue);
        for (final estado in [
          'Rescatado',
          'Regresado',
          'Hogar de paso',
          'Adoptado',
          'Fallecido',
          null,
        ]) {
          expect(hayAdopcionEnCurso(estado), isFalse, reason: '\$estado');
        }
      });

      // Rechazar la adopcion devuelve el animalito a 'Rescatado', y desde
      // ahi la opcion vuelve a estar. Es el camino que reemplaza a la
      // transicion directa.
      test('despues de rechazar, desde Rescatado vuelve a poder', () {
        const despuesDeRechazar = 'Rescatado';
        expect(hayAdopcionEnCurso(despuesDeRechazar), isFalse);
      });

      // Lo que NO se hizo: ningun parche que borre el claim para que la
      // transicion entre.
      test('no se toca adoptanteIdEnProceso para permitir la transicion', () {
        expect(
          sheet,
          isNot(contains("'adoptanteIdEnProceso': FieldValue.delete()")),
          reason: 'la hoja no puede limpiar el claim por su cuenta',
        );
      });
    });

    group('aprobarSiDisponible', () {
      test(
        'aprueba y actualiza el rescate cuando el animal está disponible',
        () async {
          final sol = await firestore.collection('solicitudes').add({
            'estado': 'pendiente',
          });
          final rescate = await firestore.collection('rescates').add({
            'estadoAdopcion': 'Rescatado',
          });

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
        },
      );

      test(
        'rechaza con animalEliminado=true cuando el rescate ya no existe '
        '(se borró mientras la solicitud seguía pendiente — antes esto tiraba '
        'invalid-argument al intentar tx.update sobre un doc borrado)',
        () async {
          final sol = await firestore.collection('solicitudes').add({
            'estado': 'pendiente',
          });

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
        },
      );

      test(
        'se autorrechaza en vez de aprobar cuando otro adoptante ya ganó la carrera '
        '(el bug real que esto arregla: dos solicitudes del mismo animal aprobadas a la vez)',
        () async {
          final sol = await firestore.collection('solicitudes').add({
            'estado': 'pendiente',
          });
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
        },
      );

      test('si adoptanteIdEnProceso ya es del MISMO adoptante, igual aprueba '
          '(no es una carrera, es la misma persona)', () async {
        final sol = await firestore.collection('solicitudes').add({
          'estado': 'pendiente',
        });
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
          'rescateId': 'eddy-1',
          'rescatistaId': 'alb-1',
          'estado': 'pendiente',
        });
        expect(
          await repo.tienePendientesPara('eddy-1', rescatistaId: 'alb-1'),
          true,
        );
      });

      test('false si la única solicitud ya fue aprobada/rechazada', () async {
        await firestore.collection('solicitudes').add({
          'rescateId': 'eddy-1',
          'rescatistaId': 'alb-1',
          'estado': 'aprobada',
        });
        expect(
          await repo.tienePendientesPara('eddy-1', rescatistaId: 'alb-1'),
          false,
        );
      });

      test('false si no hay ninguna solicitud para ese rescateId', () async {
        expect(
          await repo.tienePendientesPara(
            'sin-solicitudes',
            rescatistaId: 'alb-1',
          ),
          false,
        );
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
        when(
          () => col.where(any(), isEqualTo: any(named: 'isEqualTo')),
        ).thenReturn(query);
        when(
          () => query.where(any(), isEqualTo: any(named: 'isEqualTo')),
        ).thenReturn(query);
        when(() => query.limit(any())).thenReturn(query);
        when(() => snapshot.docs).thenReturn([]);
        var intentos = 0;
        when(() => query.get()).thenAnswer((_) {
          intentos++;
          if (intentos == 1) {
            throw FirebaseException(
              plugin: 'cloud_firestore',
              code: 'unavailable',
            );
          }
          return Future.value(snapshot);
        });

        final repoConMock = SolicitudesRepository(db: db);
        expect(
          await repoConMock.tienePendientesPara(
            'rescate-1',
            rescatistaId: 'alb-1',
          ),
          false,
        );
        expect(intentos, 2);
      });

      test(
        'si el servidor sigue sin responder tras el reintento (la '
        'reconexión tras modo avión puede tardar hasta ~1 minuto de '
        'backoff), cae a la copia LOCAL: caché sin pendientes → deja '
        'borrar — el bug real: internet ya puesto y "no pudimos verificar '
        'si se puede eliminar" en cada tap, canequita y editar → eliminar',
        () async {
          final db = MockFirebaseFirestore();
          final col = MockCollectionReference();
          final query = MockQuery();
          final snapshotCache = MockQuerySnapshot();
          when(() => db.collection('solicitudes')).thenReturn(col);
          when(
            () => col.where(any(), isEqualTo: any(named: 'isEqualTo')),
          ).thenReturn(query);
          when(
            () => query.where(any(), isEqualTo: any(named: 'isEqualTo')),
          ).thenReturn(query);
          when(() => query.limit(any())).thenReturn(query);
          when(() => query.get()).thenThrow(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
          );
          // Solo el pedido explícito a la caché local responde — si el código
          // pidiera otra fuente, no matchea ningún stub y el test falla.
          when(
            () => query.get(
              any(
                that: isA<GetOptions>().having(
                  (o) => o.source,
                  'source',
                  Source.cache,
                ),
              ),
            ),
          ).thenAnswer((_) async => snapshotCache);
          when(() => snapshotCache.docs).thenReturn([]);

          final repoConMock = SolicitudesRepository(db: db);
          expect(
            await repoConMock.tienePendientesPara(
              'rescate-1',
              rescatistaId: 'alb-1',
            ),
            false,
          );
        },
      );

      test('la caída a caché también BLOQUEA el borrado si la copia local '
          'sí conoce una solicitud pendiente — tolerar la falla de red no '
          'significa ignorar lo que el teléfono ya sabe', () async {
        final db = MockFirebaseFirestore();
        final col = MockCollectionReference();
        final query = MockQuery();
        final snapshotCache = MockQuerySnapshot();
        final docPendiente = MockQueryDocumentSnapshot();
        when(() => db.collection('solicitudes')).thenReturn(col);
        when(
          () => col.where(any(), isEqualTo: any(named: 'isEqualTo')),
        ).thenReturn(query);
        when(
          () => query.where(any(), isEqualTo: any(named: 'isEqualTo')),
        ).thenReturn(query);
        when(() => query.limit(any())).thenReturn(query);
        when(() => query.get()).thenThrow(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        );
        when(() => query.get(any())).thenAnswer((_) async => snapshotCache);
        when(() => snapshotCache.docs).thenReturn([docPendiente]);

        final repoConMock = SolicitudesRepository(db: db);
        expect(
          await repoConMock.tienePendientesPara(
            'rescate-1',
            rescatistaId: 'alb-1',
          ),
          true,
        );
      });

      test('si el servidor falla dos veces Y hasta la caché local falla '
          '(rarísimo) propaga el error — el llamador (mis_rescates_screen.dart, '
          'editar_rescate_screen.dart) necesita la excepción para avisar '
          '"revisá tu conexión"', () async {
        final db = MockFirebaseFirestore();
        final col = MockCollectionReference();
        final query = MockQuery();
        when(() => db.collection('solicitudes')).thenReturn(col);
        when(
          () => col.where(any(), isEqualTo: any(named: 'isEqualTo')),
        ).thenReturn(query);
        when(
          () => query.where(any(), isEqualTo: any(named: 'isEqualTo')),
        ).thenReturn(query);
        when(() => query.limit(any())).thenReturn(query);
        when(() => query.get()).thenThrow(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        );
        when(() => query.get(any())).thenThrow(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        );

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
        when(
          () => col.where(any(), isEqualTo: any(named: 'isEqualTo')),
        ).thenReturn(query);
        when(
          () => query.where(any(), isEqualTo: any(named: 'isEqualTo')),
        ).thenReturn(query);
        when(() => query.limit(any())).thenReturn(query);
        when(() => query.get()).thenThrow(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          ),
        );

        final repoConMock = SolicitudesRepository(db: db);
        await expectLater(
          repoConMock.tienePendientesPara('rescate-1', rescatistaId: 'alb-1'),
          throwsA(
            isA<FirebaseException>().having(
              (e) => e.code,
              'code',
              'permission-denied',
            ),
          ),
        );
        // Y ni siquiera se le preguntó a la caché. (No alcanza con
        // `get(any())`: una llamada sin argumentos queda registrada como
        // `get(null)` y `any()` también la matchea — hay que apuntar
        // explícitamente al pedido con Source.cache.)
        verifyNever(
          () => query.get(
            any(
              that: isA<GetOptions>().having(
                (o) => o.source,
                'source',
                Source.cache,
              ),
            ),
          ),
        );
      });

      test('no cuenta la solicitud de OTRO rescatista aunque apunte al mismo '
          'rescateId — el filtro por dueño no es cosmético, es lo que hace '
          'que el servidor acepte la consulta en vez de rechazarla', () async {
        await firestore.collection('solicitudes').add({
          'rescateId': 'eddy-1',
          'rescatistaId': 'otro-albergue',
          'estado': 'pendiente',
        });
        expect(
          await repo.tienePendientesPara('eddy-1', rescatistaId: 'alb-1'),
          false,
        );
      });
    });

    group('tuvoSolicitudAprobada', () {
      test('true si hay una solicitud aprobada para ese rescateId', () async {
        await firestore.collection('solicitudes').add({
          'rescateId': 'eddy-1',
          'rescatistaId': 'alb-1',
          'estado': 'aprobada',
        });
        expect(
          await repo.tuvoSolicitudAprobada('eddy-1', rescatistaId: 'alb-1'),
          true,
        );
      });

      test(
        'false si la única solicitud está pendiente o fue rechazada — '
        'a diferencia de tienePendientesPara, acá solo importa "aprobada"',
        () async {
          await firestore.collection('solicitudes').add({
            'rescateId': 'eddy-1',
            'rescatistaId': 'alb-1',
            'estado': 'pendiente',
          });
          expect(
            await repo.tuvoSolicitudAprobada('eddy-1', rescatistaId: 'alb-1'),
            false,
          );
        },
      );

      test('false si no hay ninguna solicitud para ese rescateId', () async {
        expect(
          await repo.tuvoSolicitudAprobada(
            'sin-solicitudes',
            rescatistaId: 'alb-1',
          ),
          false,
        );
      });

      test('sigue el mismo criterio de tolerancia a fallas que '
          'tienePendientesPara: reintenta una vez antes de rendirse', () async {
        final db = MockFirebaseFirestore();
        final col = MockCollectionReference();
        final query = MockQuery();
        final snapshot = MockQuerySnapshot();
        when(() => db.collection('solicitudes')).thenReturn(col);
        when(
          () => col.where(any(), isEqualTo: any(named: 'isEqualTo')),
        ).thenReturn(query);
        when(
          () => query.where(any(), isEqualTo: any(named: 'isEqualTo')),
        ).thenReturn(query);
        when(() => query.limit(any())).thenReturn(query);
        when(() => snapshot.docs).thenReturn([]);
        var intentos = 0;
        when(() => query.get()).thenAnswer((_) {
          intentos++;
          if (intentos == 1) {
            throw FirebaseException(
              plugin: 'cloud_firestore',
              code: 'unavailable',
            );
          }
          return Future.value(snapshot);
        });

        final repoConMock = SolicitudesRepository(db: db);
        expect(
          await repoConMock.tuvoSolicitudAprobada(
            'rescate-1',
            rescatistaId: 'alb-1',
          ),
          false,
        );
        expect(intentos, 2);
      });
    });
  });

  group(
    'crear() no deja duplicar una solicitud — el chequeo estaba solo en la '
    'pantalla, y solo al abrirla. Verificado usando la app: quedaron dos '
    'solicitudes idénticas de la misma persona por el mismo animalito.',
    () {
      late FakeFirebaseFirestore db;
      late SolicitudesRepository repo;

      setUp(() {
        db = FakeFirebaseFirestore();
        repo = SolicitudesRepository(db: db);
      });

      Future<DocumentReference<Map<String, dynamic>>> pedir() => repo.crear(
        adoptanteUid: 'ana',
        rescatistaId: 'refugio',
        creadoPor: CreatorRole.albergue,
        datos: {'rescateId': 'r1', 'animalNombre': 'Pacolin'},
      );

      test('la primera pasa', () async {
        await pedir();
        expect((await db.collection('solicitudes').get()).docs, hasLength(1));
      });

      test('la segunda por el MISMO animalito se frena', () async {
        await pedir();
        await expectLater(pedir(), throwsA(isA<YaAplicoException>()));
        expect(
          (await db.collection('solicitudes').get()).docs,
          hasLength(1),
          reason: 'no se escribió una segunda',
        );
      });

      test('y también si la primera ya fue aprobada', () async {
        final ref = await pedir();
        await ref.update({'estado': 'aprobada'});
        await expectLater(pedir(), throwsA(isA<YaAplicoException>()));
      });

      // Lo que NO debe frenar: una solicitud RECHAZADA no bloquea volver a
      // intentarlo. Si esto se rompiera, alguien a quien le dijeron que no
      // una vez no podría volver a pedir nunca más.
      test('una rechazada NO bloquea volver a pedir', () async {
        final ref = await pedir();
        await ref.update({'estado': 'rechazada'});
        await expectLater(pedir(), completes);
        expect((await db.collection('solicitudes').get()).docs, hasLength(2));
      });

      test('otro animalito distinto sí se puede pedir', () async {
        await pedir();
        await expectLater(
          repo.crear(
            adoptanteUid: 'ana',
            rescatistaId: 'refugio',
            creadoPor: CreatorRole.albergue,
            datos: {'rescateId': 'r2', 'animalNombre': 'Firulais'},
          ),
          completes,
        );
      });

      test('y otra persona por el mismo animalito también', () async {
        await pedir();
        await expectLater(
          repo.crear(
            adoptanteUid: 'otra',
            rescatistaId: 'refugio',
            creadoPor: CreatorRole.albergue,
            datos: {'rescateId': 'r1', 'animalNombre': 'Pacolin'},
          ),
          completes,
        );
      });
    },
  );
}
