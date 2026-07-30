import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patitas_medellin/data/chats_repository.dart';

void main() {
  group('ChatsRepository', () {
    late FakeFirebaseFirestore firestore;
    late ChatsRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = ChatsRepository(db: firestore);
    });

    test('idAnimal es el mismo sin importar quién lo pida (rescateId+adoptanteId)', () {
      final id1 = repo.idAnimal(rescateId: 'animal-1', adoptanteId: 'user-1');
      final id2 = repo.idAnimal(rescateId: 'animal-1', adoptanteId: 'user-1');
      expect(id1, id2);
    });

    test('idAnimal distingue animales aunque tengan el mismo nombre (este era el bug real)', () async {
      // Dos animales llamados "Eduardo" con distinto rescateId nunca deben
      // compartir chat, aunque los publique la misma cuenta.
      final idEduardo1 = repo.idAnimal(rescateId: 'rescate-eduardo-1', adoptanteId: 'adoptante-1');
      final idEduardo2 = repo.idAnimal(rescateId: 'rescate-eduardo-2', adoptanteId: 'adoptante-1');
      expect(idEduardo1, isNot(idEduardo2));
    });

    test('asegurarChatAnimal crea el chat con creadoPor y no lo duplica si se llama de nuevo', () async {
      final id1 = await repo.asegurarChatAnimal(
        adoptanteId: 'adoptante-1',
        adoptanteNombre: 'Ana',
        rescateId: 'rescate-1',
        rescatistaId: 'rescatista-1',
        rescatista: 'Refugio Norte',
        creadoPor: 'albergue',
        animalNombre: 'Eduardo',
      );
      final id2 = await repo.asegurarChatAnimal(
        adoptanteId: 'adoptante-1',
        adoptanteNombre: 'Ana',
        rescateId: 'rescate-1',
        rescatistaId: 'rescatista-1',
        rescatista: 'Refugio Norte',
        creadoPor: 'albergue',
        animalNombre: 'Eduardo',
      );

      expect(id1, id2);
      final docs = await firestore.collection('chats').get();
      expect(docs.docs.length, 1);
      expect(docs.docs.first['creadoPor'], 'albergue');
    });

    test('asegurarChatAnimal guarda la foto como fotoUrl (Storage), no fotoBase64 — '
        'a diferencia de asegurarChatNegocio, que sigue en base64 (logo del aliado)', () async {
      final chatId = await repo.asegurarChatAnimal(
        adoptanteId: 'adoptante-2',
        adoptanteNombre: 'Bea',
        rescateId: 'rescate-2',
        rescatistaId: 'rescatista-2',
        rescatista: 'Refugio Sur',
        creadoPor: 'rescatista',
        fotoUrl: 'https://firebasestorage.googleapis.com/foto.jpg',
      );
      final doc = await firestore.collection('chats').doc(chatId).get();
      expect(doc['fotoUrl'], 'https://firebasestorage.googleapis.com/foto.jpg');
      expect(doc.data()!.containsKey('fotoBase64'), false);
    });

    // campoLogoRescatista / campoLogoAdoptante son LA única fuente de "qué
    // campo de usuarios/{uid} mirar para el logo de negocio de cada lado de
    // un chat". Antes cada pantalla derivaba esto por su cuenta y cada
    // combinación de roles nueva encontraba una pantalla equivocada — tres
    // bugs de "foto equivocada en el chat" en una sola sesión. Derivan de
    // campos que todos los chats tienen desde siempre, así que también
    // cubren los documentos viejos sin migración.
    group('campoLogo* (única fuente del logo por lado, los 4 roles)', () {
      test('chat de animal publicado como albergue: lado dueño → logo de '
          'albergue; lado adoptante → foto personal', () {
        final chat = {'creadoPor': 'albergue'};
        expect(ChatsRepository.campoLogoRescatista(chat), 'fotoBase64');
        expect(ChatsRepository.campoLogoAdoptante(chat), null);
      });

      test('chat de animal publicado como rescatista: ambos lados son '
          'personas, sin logo', () {
        final chat = {'creadoPor': 'rescatista'};
        expect(ChatsRepository.campoLogoRescatista(chat), null);
        expect(ChatsRepository.campoLogoAdoptante(chat), null);
      });

      test('chat de animal legado sin creadoPor ni tipoSolicitud: foto '
          'personal en ambos lados, nunca crashea', () {
        expect(ChatsRepository.campoLogoRescatista({}), null);
        expect(ChatsRepository.campoLogoAdoptante({}), null);
      });

      test('consulta a un aliado: el lado del aliado usa SIEMPRE su logo de '
          'negocio (aliadoFotoBase64), sin importar con qué sombrero lo '
          'contactaron — el bug real: pedía el campo del logo de albergue, '
          'que el aliado no tiene, y caía a la foto personal de la cuenta', () {
        for (final creadoPor in ['albergue', 'rescatista', null]) {
          final chat = <String, dynamic>{
            'tipoSolicitud': 'consulta_aliado',
            'creadoPor': ?creadoPor,
          };
          expect(ChatsRepository.campoLogoRescatista(chat), 'aliadoFotoBase64',
              reason: 'contactado con sombrero: ${creadoPor ?? "adoptante"}');
        }
      });

      test('consulta a un aliado: el lado de quien contactó depende de su '
          'sombrero — albergue muestra su logo, rescatista y adoptante su '
          'foto personal', () {
        expect(
          ChatsRepository.campoLogoAdoptante(
              {'tipoSolicitud': 'consulta_aliado', 'creadoPor': 'albergue'}),
          'fotoBase64',
        );
        expect(
          ChatsRepository.campoLogoAdoptante(
              {'tipoSolicitud': 'consulta_aliado', 'creadoPor': 'rescatista'}),
          null,
        );
        expect(
          ChatsRepository.campoLogoAdoptante({'tipoSolicitud': 'consulta_aliado'}),
          null,
        );
      });
    });

    test('asegurarChatNegocio guarda tipoSolicitud consulta_aliado (el campo que faltaba)', () async {
      final chatId = await repo.asegurarChatNegocio(
        adoptanteId: 'adoptante-1',
        adoptanteNombre: 'Ana',
        aliadoId: 'aliado-1',
        aliadoNombre: 'Veterinaria la 30',
      );
      final doc = await firestore.collection('chats').doc(chatId).get();
      expect(doc['tipoSolicitud'], 'consulta_aliado');
      expect(doc['rescatistaId'], 'aliado-1');
    });

    test('idNegocio distingue contexto rescatista vs adoptante para el mismo par de cuentas', () {
      final idComoRescatista = repo.idNegocio(
          aliadoId: 'aliado-1', adoptanteId: 'user-1', contexto: 'rescatista');
      final idComoAdoptante = repo.idNegocio(
          aliadoId: 'aliado-1', adoptanteId: 'user-1', contexto: 'general');
      expect(idComoRescatista, isNot(idComoAdoptante));
    });

    test('idNegocio también distingue rescatista de albergue (el bug real: se mezclaban '
        'en una sola conversación porque contexto solo distinguía 2 casos, no 3)', () {
      final idComoRescatista = repo.idNegocio(
          aliadoId: 'aliado-1', adoptanteId: 'user-1', contexto: 'rescatista');
      final idComoAlbergue = repo.idNegocio(
          aliadoId: 'aliado-1', adoptanteId: 'user-1', contexto: 'albergue');
      expect(idComoRescatista, isNot(idComoAlbergue));
    });

    test('asegurarChatNegocio guarda creadoPor cuando contexto es rescatista o albergue, '
        'para que cada uno pueda filtrar su propia bandeja de chats enviados', () async {
      final idRescatista = await repo.asegurarChatNegocio(
        adoptanteId: 'user-1', adoptanteNombre: 'Ana',
        aliadoId: 'aliado-1', aliadoNombre: 'Veterinaria la 30',
        contexto: 'rescatista',
      );
      final idAlbergue = await repo.asegurarChatNegocio(
        adoptanteId: 'user-1', adoptanteNombre: 'Ana',
        aliadoId: 'aliado-1', aliadoNombre: 'Veterinaria la 30',
        contexto: 'albergue',
      );
      expect((await firestore.collection('chats').doc(idRescatista).get())['creadoPor'], 'rescatista');
      expect((await firestore.collection('chats').doc(idAlbergue).get())['creadoPor'], 'albergue');
    });

    test('asegurarChatNegocio NO guarda creadoPor cuando contexto es general (adoptante)', () async {
      final chatId = await repo.asegurarChatNegocio(
        adoptanteId: 'adoptante-1', adoptanteNombre: 'Ana',
        aliadoId: 'aliado-1', aliadoNombre: 'Veterinaria la 30',
      );
      final doc = await firestore.collection('chats').doc(chatId).get();
      expect(doc.data()!.containsKey('creadoPor'), false);
    });

    test('un chat de consulta recién creado por asegurarChatNegocio produce, '
        'vía campoLogo*, el logo del aliado de un lado y el sombrero real de '
        'quien contactó del otro (integración creación → lectura)', () async {
      final chatId = await repo.asegurarChatNegocio(
        adoptanteId: 'user-1', adoptanteNombre: 'Ana',
        aliadoId: 'aliado-1', aliadoNombre: 'Veterinaria la 30',
        contexto: 'albergue',
      );
      final d = (await firestore.collection('chats').doc(chatId).get()).data()!;
      expect(ChatsRepository.campoLogoRescatista(d), 'aliadoFotoBase64');
      expect(ChatsRepository.campoLogoAdoptante(d), 'fotoBase64');
    });

    test('asegurarChatNegocio no pisa datos si ya existe el chat', () async {
      final id1 = await repo.asegurarChatNegocio(
        adoptanteId: 'adoptante-1',
        adoptanteNombre: 'Ana',
        aliadoId: 'aliado-1',
        aliadoNombre: 'Veterinaria la 30',
      );
      await firestore.collection('chats').doc(id1).update({'ultimoMensaje': 'Hola'});

      final id2 = await repo.asegurarChatNegocio(
        adoptanteId: 'adoptante-1',
        adoptanteNombre: 'Ana',
        aliadoId: 'aliado-1',
        aliadoNombre: 'Veterinaria la 30',
      );

      expect(id1, id2);
      final doc = await firestore.collection('chats').doc(id1).get();
      expect(doc['ultimoMensaje'], 'Hola');
    });
  });
}
