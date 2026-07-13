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
