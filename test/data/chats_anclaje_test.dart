import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/data/chats_repository.dart';

/// La red que evita que el agujero de `chats.create` vuelva por otra puerta.
///
/// **El hallazgo.** La regla de Firestore aceptaba crear un chat sin nada
/// contra lo cual validarlo, y con eso cualquier cuenta podía abrirle
/// conversación a cualquier otra y dispararle una notificación push con
/// título y texto elegidos por quien atacaba. Se cerró exigiendo que todo
/// chat traiga UNA de estas tres cosas:
///
///  · `rescateId`  → el animal existe y es de quien dice ser
///  · `tipoSolicitud: 'consulta_aliado'` → el destinatario es un negocio real
///  · `solicitudId` → hay una solicitud que une a esas dos personas
///
/// **Por qué este archivo y no solo los tests de reglas.** Los de
/// `test_rules/` prueban que la REGLA acepta o rechaza cada forma, pero las
/// formas están escritas a mano ahí. Si mañana alguien agrega un camino
/// nuevo que cree un chat sin ancla, la regla lo va a rechazar en
/// producción y ningún test lo habría avisado antes: el síntoma sería "no
/// se puede abrir el chat", en el teléfono de alguien, sin pista de por qué.
///
/// Esto corre los caminos REALES y exige la invariante sobre lo que
/// escriben de verdad. Al agregar una forma nueva de crear un chat, sumala
/// acá: si no tiene ancla, este test falla antes de llegar al teléfono.
void main() {
  late FakeFirebaseFirestore db;
  late ChatsRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = ChatsRepository(db: db);
  });

  /// Lo que exige `firestore.rules`, chats.create.
  void exigirAncla(Map<String, dynamic> chat, String camino) {
    final rescateId = chat['rescateId'] as String? ?? '';
    final solicitudId = chat['solicitudId'] as String? ?? '';
    final esConsulta = chat['tipoSolicitud'] == 'consulta_aliado';
    expect(
      rescateId.isNotEmpty || solicitudId.isNotEmpty || esConsulta,
      isTrue,
      reason:
          'El camino "$camino" crea un chat SIN ancla. Las reglas lo van a '
          'rechazar en producción. Ver firestore.rules, chats.create.',
    );
  }

  Future<void> revisarTodos(String camino) async {
    final chats = await db.collection('chats').get();
    expect(chats.docs, isNotEmpty, reason: '"$camino" no creó ningún chat');
    for (final d in chats.docs) {
      exigirAncla(d.data(), camino);
    }
  }

  test('asegurarChatAnimal deja el chat anclado al animal', () async {
    await repo.asegurarChatAnimal(
      adoptanteId: 'ana',
      adoptanteNombre: 'Ana',
      rescateId: 'r1',
      rescatistaId: 'refugio',
      rescatista: 'La Perla',
      creadoPor: 'albergue',
    );
    await revisarTodos('asegurarChatAnimal');
  });

  test('asegurarChatNegocio queda anclado por ser consulta a un aliado',
      () async {
    await repo.asegurarChatNegocio(
      adoptanteId: 'ana',
      adoptanteNombre: 'Ana',
      aliadoId: 'vet',
      aliadoNombre: 'Veterinaria 30',
      contexto: 'general',
    );
    await revisarTodos('asegurarChatNegocio (adoptante)');
  });

  test('asegurarChatNegocio como albergue, idem', () async {
    await repo.asegurarChatNegocio(
      adoptanteId: 'refugio',
      adoptanteNombre: 'La Perla',
      aliadoId: 'vet',
      aliadoNombre: 'Veterinaria 30',
      contexto: 'albergue',
    );
    await revisarTodos('asegurarChatNegocio (albergue)');
  });

  test('avisarSobreAnimal con rescateId queda anclado al animal', () async {
    await repo.avisarSobreAnimal(
      adoptanteId: 'ana',
      adoptanteNombre: 'Ana',
      rescatistaId: 'refugio',
      rescatista: 'La Perla',
      texto: 'Tu solicitud fue aprobada',
      rescateId: 'r1',
      animalNombre: 'Pacolin',
      creadoPor: 'albergue',
    );
    await revisarTodos('avisarSobreAnimal (con rescateId)');
  });

  // El camino que rompió el primer intento de arreglo: el aviso automático
  // de una solicitud vieja crea el chat desde el lado del RESCATISTA, no
  // del adoptante. Sin el ancla de la solicitud, el "tu solicitud fue
  // rechazada" no le llegaba nunca al adoptante.
  test('avisarSobreAnimal sin rescateId queda anclado a la solicitud',
      () async {
    await repo.avisarSobreAnimal(
      adoptanteId: 'ana',
      adoptanteNombre: 'Ana',
      rescatistaId: 'refugio',
      rescatista: 'La Perla',
      texto: 'Este animalito ya no está disponible',
      animalNombre: 'Viejito',
      solicitudId: 'sol_vieja',
    );
    await revisarTodos('avisarSobreAnimal (sin rescateId)');
  });

  test('asegurarChatLegado queda anclado a la solicitud', () async {
    await repo.asegurarChatLegado(
      chatId: 'viejito_la_perla',
      adoptanteId: 'ana',
      adoptanteNombre: 'Ana',
      rescatistaId: 'refugio',
      rescatista: 'La Perla',
      creadoPor: 'albergue',
      solicitudId: 'sol_vieja',
      animalNombre: 'Viejito',
    );
    await revisarTodos('asegurarChatLegado');
  });

  // Y la contraprueba: que el guard de arriba sirva de algo. Si
  // asegurarChatLegado se llama SIN solicitudId, el chat sale sin ancla y
  // este test lo tiene que ver. Sin esta contraprueba, `exigirAncla` podría
  // estar rota y los 6 tests de arriba pasarían igual.
  test('un chat sin ancla SÍ es detectado por esta red', () async {
    await repo.asegurarChatLegado(
      chatId: 'sin_ancla',
      adoptanteId: 'ana',
      adoptanteNombre: 'Ana',
      rescatistaId: 'refugio',
      rescatista: 'La Perla',
      creadoPor: 'albergue',
      animalNombre: 'Viejito',
    );
    final chat = (await db.collection('chats').doc('sin_ancla').get()).data()!;
    expect(
      () => exigirAncla(chat, 'contraprueba'),
      throwsA(isA<TestFailure>()),
      reason: 'si esto no falla, la red no está atrapando nada',
    );
  });
}
