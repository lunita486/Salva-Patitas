import 'package:cloud_firestore/cloud_firestore.dart';

/// Único lugar que genera el id de un chat y asegura que el documento tenga
/// los campos correctos (sobre todo `tipoSolicitud` y `creadoPor`). Antes esta
/// lógica vivía repetida en varias pantallas y alguna se olvidaba de uno de
/// estos campos — causa de más de un bug de cruce entre chats. Ver
/// ARCHITECTURE.md.
class ChatsRepository {
  ChatsRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  /// Qué campo de usuarios/{uid} contiene el logo de negocio del lado
  /// `rescatistaId` de este chat — o null si ese lado no actúa como negocio
  /// (se muestra su foto personal).
  ///
  /// ÚNICA fuente de esta decisión para toda la app, junto con
  /// [campoLogoAdoptante]. Antes cada pantalla (lista de chats, bandeja del
  /// aliado, encabezado del chat) la re-derivaba por su cuenta a partir de
  /// `creadoPor`/`tipoSolicitud`, cada una a su manera — y cada combinación
  /// nueva de roles encontraba alguna pantalla cuya derivación no la cubría.
  /// Tres bugs distintos de "muestra la foto equivocada" en una sola sesión
  /// salieron de esa duplicación.
  ///
  /// Funciona por derivación pura sobre campos que todos los chats tienen
  /// desde siempre (`tipoSolicitud`, `creadoPor`), a propósito: así cubre
  /// también los chats viejos, sin necesitar migrar/backfillear documentos.
  ///
  /// La regla: en una consulta a un negocio, `rescatistaId` es el ALIADO —
  /// siempre contactado en su capacidad de negocio, así que su logo vive
  /// SIEMPRE en 'aliadoFotoBase64' (campo separado del logo de albergue
  /// 'fotoBase64', porque una misma cuenta puede tener ambos roles a la
  /// vez; si no subió logo, la pantalla cae sola a su foto personal). En un
  /// chat de animal, `rescatistaId` es quien publicó, y `creadoPor` dice con
  /// qué rol: 'albergue' tiene logo, 'rescatista' es una persona.
  static String? campoLogoRescatista(Map<String, dynamic> chat) {
    if ((chat['tipoSolicitud'] as String?) == 'consulta_aliado') {
      return 'aliadoFotoBase64';
    }
    return (chat['creadoPor'] as String?) == 'albergue' ? 'fotoBase64' : null;
  }

  /// Análogo de [campoLogoRescatista] para el lado `adoptanteId` del chat.
  ///
  /// En una consulta a un negocio, `adoptanteId` es quien contactó y
  /// `creadoPor` dice con qué sombrero lo hizo ('albergue' → su logo,
  /// 'rescatista' o ausente/adoptante → su foto personal). En un chat de
  /// animal, `adoptanteId` es siempre alguien interesado en adoptar — nunca
  /// actúa como negocio ahí.
  static String? campoLogoAdoptante(Map<String, dynamic> chat) {
    if ((chat['tipoSolicitud'] as String?) == 'consulta_aliado') {
      return (chat['creadoPor'] as String?) == 'albergue' ? 'fotoBase64' : null;
    }
    return null;
  }

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
  ///
  /// Con timeout de 15s: sin señal, este `.set()` no falla, se queda
  /// esperando al servidor para siempre — y los dos llamadores reales
  /// (`chat_screen.dart`, `solicitudes_rescatista_screen.dart`) ya
  /// atrapan el error, pero nunca llegaban a recibirlo. Hallazgo de
  /// auditoría de código.
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
    Duration timeout = const Duration(seconds: 15),
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
    }, SetOptions(merge: true)).timeout(timeout);
    return chatId;
  }

  /// Id determinístico para un chat de consulta con un negocio aliado (no es
  /// sobre un animal puntual, así que usa un esquema separado). `contexto`
  /// distingue si la cuenta contactó como adoptante, rescatista o albergue —
  /// son conversaciones separadas a propósito, igual que una cuenta con
  /// doble rol nunca mezcla los chats de sus animales entre uno y otro.
  String idNegocio({required String aliadoId, required String adoptanteId, String contexto = 'general'}) =>
      '${aliadoId}_${adoptanteId}_negocio_$contexto';

  /// Crea el chat de consulta a un negocio si no existe todavía. A diferencia
  /// de un chat de animal, acá no se pisa nada si ya existe (no hace falta
  /// refrescar el nombre/foto del negocio en cada apertura, y así tampoco se
  /// resetean ultimoMensaje/noLeidos de una conversación que ya tiene
  /// historial).
  ///
  /// Las dos escrituras tienen timeout de 15s — sin señal, ni el `.get()`
  /// ni el `.set()` de más abajo fallan solos, se quedan esperando al
  /// servidor para siempre. El único llamador real (`aliado_publico_screen.dart`,
  /// botón "Contactar") ya atrapa el error y avisa, pero sin este límite
  /// nunca llegaba a recibirlo — el botón quedaba girando de por vida.
  /// Hallazgo de auditoría de código.
  Future<String> asegurarChatNegocio({
    required String adoptanteId,
    required String adoptanteNombre,
    required String aliadoId,
    required String aliadoNombre,
    String contexto = 'general',
    String? fotoBase64,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final chatId = idNegocio(aliadoId: aliadoId, adoptanteId: adoptanteId, contexto: contexto);
    final ref = _db.collection('chats').doc(chatId);
    // La primera vez que se contacta a un aliado el doc todavía no existe, y
    // las reglas de Firestore no pueden confirmar "sos participante" sobre
    // un documento que no está — el get() de abajo tira permission-denied
    // (no es que falte permiso de verdad). Sin este try/catch esa excepción
    // mataba el botón "Contactar" en silencio, para adoptante, rescatista Y
    // albergue por igual (los tres pasan por el mismo código).
    //
    // El catch acota a `permission-denied` a propósito (antes atrapaba
    // CUALQUIER error) — un chat que SÍ existe pero cuyo get() falla por
    // otro motivo (ej. el timeout de acá arriba, en una reconexión lenta)
    // no puede tratarse como "no existe": el `if (!existe)` de abajo hace
    // un `.set()` SIN merge, así que un falso "no existe" reseteaba
    // ultimoMensaje/noLeidos de una conversación real con historial.
    // Hallazgo de auditoría de código.
    bool existe;
    try {
      existe = (await ref.get().timeout(timeout)).exists;
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
      existe = false;
    }
    if (!existe) {
      await ref.set({
        'adoptanteId':        adoptanteId,
        'adoptanteNombre':    adoptanteNombre,
        'animalNombre':       aliadoNombre,
        'rescatista':         aliadoNombre,
        'rescatistaId':       aliadoId,
        if (fotoBase64 != null) 'fotoBase64': fotoBase64,
        'tipoSolicitud':      'consulta_aliado',
        // Mismo campo que usan los chats de animal para separar bandejas de
        // una cuenta con doble rol (ver AdoptanteChatsScreen) — sin esto,
        // una consulta enviada como albergue quedaba indistinguible de una
        // enviada como rescatista al filtrar la propia lista de chats.
        if (contexto == 'rescatista' || contexto == 'albergue') 'creadoPor': contexto,
        'ultimoMensaje':      '',
        'ultimaHora':         '',
        'ultimoMensajeEn':    FieldValue.serverTimestamp(),
        'noLeidosAdoptante':  0,
        'noLeidosRescatista': 0,
      }).timeout(timeout);
    }
    return chatId;
  }
}
