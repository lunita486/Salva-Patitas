import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/data/chats_repository.dart';

/// El orden entre el chat y su primer mensaje.
///
/// **Por qué esto se prueba aparte y con listeners.** Las reglas de
/// Firestore exigen que el chat EXISTA antes de que se escriba un mensaje
/// adentro: `mensajes/create` hace un `get()` sobre el chat, y ese `get()`
/// no ve las escrituras pendientes de un mismo batch. Crear los dos juntos
/// se rechaza entero.
///
/// Eso ya está probado del lado de las reglas (test_rules/reglas.test.mjs,
/// "crear un chat y su primer mensaje"). Lo que faltaba era la otra mitad:
/// que el código Dart produzca de verdad esa secuencia. Sin esto, alguien
/// puede volver a juntar las dos escrituras en un batch —ya pasó una vez,
/// buscando arreglar el contador de "sin leer"— y ninguna prueba se entera.
/// El síntoma en producción es silencio: aprobás una solicitud y al
/// adoptante no le llega nada.
///
/// `fake_cloud_firestore` no aplica reglas, así que no puede rechazar la
/// forma incorrecta. Pero sí puede decir en QUÉ ORDEN aparecieron los
/// documentos, y eso alcanza: si el chat aparece primero, la forma es la
/// que las reglas aceptan.
void main() {
  late FakeFirebaseFirestore db;
  late ChatsRepository repo;
  late List<String> estados;

  /// Anota cada estado por el que pasa el documento del chat.
  ///
  /// La señal que distingue las dos formas: si el chat se crea PRIMERO (con
  /// su identidad y nada más) y la vista previa llega en una segunda
  /// escritura, existe un instante en que el chat está creado y todavía no
  /// tiene `ultimoMensaje`. Si las dos cosas van en un solo batch, ese
  /// instante no existe nunca — el chat aparece ya completo.
  ///
  /// Mirar el ORDEN entre chat y mensaje NO sirve para esto:
  /// `fake_cloud_firestore` los entrega en el mismo orden en las dos formas.
  /// Probado: el test escrito así pasaba igual con el bug puesto.
  Future<void> observar(String chatId) async {
    estados = [];
    db.collection('chats').doc(chatId).snapshots().listen((s) {
      if (!s.exists) return;
      estados.add(
        (s.data()?['ultimoMensaje'] as String?)?.isNotEmpty == true
            ? 'con vista previa'
            : 'solo identidad',
      );
    });
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = ChatsRepository(db: db);
  });

  test('el aviso sobre un animal crea el chat ANTES de escribirle adentro', () async {
    final chatId = repo.idAnimal(rescateId: 'r1', adoptanteId: 'ana');
    await observar(chatId);

    await repo.avisarSobreAnimal(
      adoptanteId: 'ana',
      adoptanteNombre: 'Ana',
      rescatistaId: 'refugio',
      rescatista: 'La Perla',
      texto: '✅ ¡Tu solicitud fue aprobada!',
      rescateId: 'r1',
      animalNombre: 'Pacolin',
      creadoPor: 'albergue',
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      estados.first,
      'solo identidad',
      reason:
          'el chat tiene que nacer en su propia escritura, sin vista previa. '
          'Si nace ya completo, es que fue en el mismo batch que el mensaje, '
          'y contra las reglas reales eso se rechaza entero: el aviso no le '
          'llega a nadie y no hay ningún error visible.',
    );
    expect(estados.last, 'con vista previa');

    final msgs = await db
        .collection('chats')
        .doc(chatId)
        .collection('mensajes')
        .get();
    expect(msgs.docs, hasLength(1), reason: 'y el mensaje quedó adentro');
  });

  // El otro camino del mismo método: una solicitud vieja sin rescateId, que
  // se ancla a la solicitud. Pasa por registrarMensaje en vez de por
  // _escribirChatYMensaje directo, así que es una secuencia distinta.
  test('y el aviso sin rescateId también, anclado a la solicitud', () async {
    await repo.avisarSobreAnimal(
      adoptanteId: 'ana',
      adoptanteNombre: 'Ana',
      rescatistaId: 'refugio',
      rescatista: 'La Perla',
      texto: 'Este animalito ya no está disponible',
      animalNombre: 'Viejito',
      solicitudId: 'sol_vieja',
    );
    final chats = await db.collection('chats').get();
    expect(chats.docs, hasLength(1));

    // El chat quedó creado y con su mensaje adentro: si la secuencia fuera
    // la incorrecta, contra reglas reales no existiría ninguno de los dos.
    final msgs = await db
        .collection('chats')
        .doc(chats.docs.first.id)
        .collection('mensajes')
        .get();
    expect(msgs.docs, hasLength(1));
    expect(chats.docs.first.data()['solicitudId'], 'sol_vieja');
  });

  // Un chat que YA existe no necesita el paso extra, y es el caso de todos
  // los días: si esto empezara a hacer dos escrituras, sería una regresión
  // de costo en cada mensaje que se manda.
  test('sobre un chat que ya existe, el mensaje va directo', () async {
    final chatId = repo.idAnimal(rescateId: 'r1', adoptanteId: 'ana');
    await repo.asegurarChatAnimal(
      adoptanteId: 'ana',
      adoptanteNombre: 'Ana',
      rescateId: 'r1',
      rescatistaId: 'refugio',
      rescatista: 'La Perla',
      creadoPor: 'albergue',
    );
    await observar(chatId);
    estados.clear();

    await repo.registrarMensaje(
      chatId: chatId,
      texto: 'hola',
      emisor: 'adoptante',
      paraAdoptante: false,
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      estados,
      ['con vista previa'],
      reason: 'un solo cambio: no hay escritura de más en el caso normal',
    );
  });
}
