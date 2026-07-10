import 'package:cloud_firestore/cloud_firestore.dart';

/// Único lugar que genera el id de un chat y asegura que el documento tenga
/// los campos correctos (sobre todo `tipoSolicitud` y `creadoPor`). Antes esta
/// lógica vivía repetida en varias pantallas y alguna se olvidaba de uno de
/// estos campos — causa de más de un bug de cruce entre chats. Ver
/// ARCHITECTURE.md.
class ChatsRepository {
  ChatsRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  /// Id determinístico para un chat sobre un animal puntual: el mismo par
  /// (animal, adoptante) siempre da el mismo id, sin importar qué pantalla
  /// lo abra ni quién escriba primero.
  String idAnimal({required String rescateId, required String adoptanteId}) =>
      '${rescateId}_$adoptanteId';

  /// Crea el chat si no existe, o solo actualiza sus datos si ya existe
  /// (merge). Es seguro llamarla siempre, exista o no el chat.
  ///
  /// `extra` permite sumar otros campos (ej. `ultimoMensaje`) a esta MISMA
  /// escritura en vez de hacer un `.update()` aparte — si se hicieran dos
  /// escrituras separadas y la app se cerrara justo entre una y otra, el
  /// chat quedaría creado pero sin vista previa de mensaje.
  ///
  /// `fotoUrl` es la foto del ANIMAL (vive en Storage). Ojo: la colección
  /// `chats` tiene esquema mixto — [asegurarChatNegocio] guarda la foto del
  /// negocio en `fotoBase64` (sigue en base64, fuera de alcance del cambio
  /// a Storage). El lado de lectura tiene que revisar los dos campos.
  Future<String> asegurarChatAnimal({
    required String adoptanteId,
    required String adoptanteNombre,
    required String rescateId,
    required String rescatistaId,
    required String rescatista,
    required String creadoPor,
    String? animalNombre,
    String? especie,
    String? fotoUrl,
    Map<String, dynamic>? extra,
  }) async {
    final chatId = idAnimal(rescateId: rescateId, adoptanteId: adoptanteId);
    await _db.collection('chats').doc(chatId).set({
      if (animalNombre != null) 'animalNombre': animalNombre,
      'rescateId':       rescateId,
      'creadoPor':       creadoPor,
      'rescatista':      rescatista,
      'rescatistaId':    rescatistaId,
      'adoptanteId':     adoptanteId,
      'adoptanteNombre': adoptanteNombre,
      if (especie != null) 'especie': especie,
      if (fotoUrl != null) 'fotoUrl': fotoUrl,
      if (extra != null) ...extra,
    }, SetOptions(merge: true));
    return chatId;
  }

  /// Id determinístico para un chat de consulta con un negocio aliado (no es
  /// sobre un animal puntual, así que usa un esquema separado). `contexto`
  /// distingue si la cuenta contactó como rescatista o como adoptante — son
  /// conversaciones separadas a propósito.
  String idNegocio({required String aliadoId, required String adoptanteId, String contexto = 'general'}) =>
      '${aliadoId}_${adoptanteId}_negocio_$contexto';

  /// Crea el chat de consulta a un negocio si no existe todavía. A diferencia
  /// de un chat de animal, acá no se pisa nada si ya existe (no hace falta
  /// refrescar el nombre/foto del negocio en cada apertura).
  Future<String> asegurarChatNegocio({
    required String adoptanteId,
    required String adoptanteNombre,
    required String aliadoId,
    required String aliadoNombre,
    String contexto = 'general',
    String? fotoBase64,
  }) async {
    final chatId = idNegocio(aliadoId: aliadoId, adoptanteId: adoptanteId, contexto: contexto);
    final ref = _db.collection('chats').doc(chatId);
    if (!(await ref.get()).exists) {
      await ref.set({
        'adoptanteId':        adoptanteId,
        'adoptanteNombre':    adoptanteNombre,
        'animalNombre':       aliadoNombre,
        'rescatista':         aliadoNombre,
        'rescatistaId':       aliadoId,
        if (fotoBase64 != null) 'fotoBase64': fotoBase64,
        'tipoSolicitud':      'consulta_aliado',
        'ultimoMensaje':      '',
        'ultimaHora':         '',
        'ultimoMensajeEn':    FieldValue.serverTimestamp(),
        'noLeidosAdoptante':  0,
        'noLeidosRescatista': 0,
      });
    }
    return chatId;
  }
}
