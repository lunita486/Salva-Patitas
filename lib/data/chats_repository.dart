import 'package:cloud_firestore/cloud_firestore.dart';

/// Único lugar que genera el id de un chat y asegura que el documento tenga
/// los campos correctos (sobre todo `tipoSolicitud` y `creadoPor`). Antes esta
/// lógica vivía repetida en varias pantallas y alguna se olvidaba de uno de
/// estos campos — causa de más de un bug de cruce entre chats. Ver
/// ARCHITECTURE.md.
class ChatsRepository {
  ChatsRepository({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;
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

  /// Cuántos mensajes sin leer tiene ESTE chat para quien lo mira, con ESTE
  /// rol — ÚNICA fuente de esta cuenta para toda la app, junto con
  /// [campoLogoRescatista]/[campoLogoAdoptante]. Antes el contador del
  /// panel/badge de "mensajes sin leer" (`contarMensajesSinLeer`,
  /// domain/reglas_negocio.dart)
  /// y la lista de Chats (`AdoptanteChatsScreen`) re-derivaban cada uno por su
  /// lado qué campo (`noLeidosRescatista` vs `noLeidosAdoptante`) mirar —
  /// funcionaba igual casi siempre porque partían de la misma fórmula
  /// copiada a mano en dos archivos, hasta que una de las dos copias sumó
  /// un filtro extra (ocultar chats sin vista previa) que la otra no tenía:
  /// el panel contaba un chat que la lista escondía por completo, así que
  /// ese "sin leer" no podía bajar a cero nunca (no había forma de abrirlo).
  /// Con una sola función, los dos lugares miran exactamente el mismo campo
  /// para exactamente el mismo chat — no pueden volver a divergir en ESTA
  /// pregunta, sin importar qué filtro nuevo aparezca en cualquiera de los
  /// dos lados más adelante.
  ///
  /// Misma regla que ya usan [campoLogoRescatista]/[campoLogoAdoptante]: en
  /// una consulta a un negocio, `adoptanteId` es quien contactó (puede ser
  /// esta cuenta con cualquier sombrero); en un chat de animal lo decide
  /// solo `esRescatista` de quien pregunta, porque la consulta a Firestore
  /// que trajo `chat` ya garantiza de qué lado está esta cuenta.
  static int noLeidosPara(
    Map<String, dynamic> chat, {
    required String uid,
    required bool esRescatista,
    bool soloConsultas = false,
  }) {
    final esConsultaAliado =
        (chat['tipoSolicitud'] as String?) == 'consulta_aliado';
    final soyAdoptanteAqui = esConsultaAliado
        ? (!soloConsultas && chat['adoptanteId'] == uid)
        : !esRescatista;
    final campo = soyAdoptanteAqui ? 'noLeidosAdoptante' : 'noLeidosRescatista';
    return (chat[campo] as int?) ?? 0;
  }

  /// ¿Este [chat] pertenece a la bandeja que se está mirando ahora
  /// (rescatista/albergue/adoptante/soloConsultas del aliado)? Única
  /// fuente de esa pregunta — antes vivía como un closure inline dentro de
  /// AdoptanteChatsScreen._listaChats, sin ningún test directo posible
  /// (dependía de FirebaseAuth.instance en el medio). Es la pieza que
  /// evita que una cuenta con doble rol (rescatista + albergue) vea los
  /// chats del otro rol mezclados en la misma lista — el riesgo real de
  /// "mensajería cruzada" que preocupaba a Eliza.
  ///
  /// Un chat sin vista previa (`ultimoMensaje` vacío) normalmente es una
  /// conversación vacía y no vale la pena mostrarla — EXCEPTO si ya tiene
  /// mensajes sin leer para este lado (ver [noLeidosPara]): eso solo pasa
  /// si hubo un mensaje real, y esconderlo lo volvía imposible de abrir
  /// para marcarlo como leído (hallazgo real de Eliza: el panel decía "2
  /// mensajes sin leer" pero la lista de Chats no mostraba ninguno).
  static bool perteneceALaLista(
    Map<String, dynamic> chat, {
    required String uid,
    required bool esRescatista,
    bool esAlbergue = false,
    bool soloConsultas = false,
  }) {
    if (((chat['ultimoMensaje'] as String?) ?? '').isEmpty &&
        noLeidosPara(
              chat,
              uid: uid,
              esRescatista: esRescatista,
              soloConsultas: soloConsultas,
            ) <=
            0) {
      return false;
    }
    final tipo = chat['tipoSolicitud'] as String? ?? '';
    if (soloConsultas) return tipo == 'consulta_aliado';
    // 'consulta' (pregunta de un adoptante antes de postular) es un chat
    // normal para el rescatista; 'consulta_aliado' tiene su propia
    // pestaña (soloConsultas) — PERO solo cuando el que mira es el aliado
    // que la recibió. Si en cambio soy quien la mandó (soy adoptanteId en
    // este chat), la quiero ver en mi lista general, porque no tengo otra
    // pantalla donde aparezca.
    if (tipo == 'consulta_aliado') {
      if (chat['adoptanteId'] != uid) return false;
      // creadoPor solo se guarda cuando contacté como rescatista o
      // albergue (ver asegurarChatNegocio) — si lo contacté como
      // ADOPTANTE, el campo no existe. Antes esto caía en el
      // `?? 'rescatista'` de más abajo (pensado para chats de animal,
      // donde el campo SIEMPRE debería estar) y una consulta mandada como
      // adoptante terminaba mostrándose en la bandeja del rescatista — el
      // bug real que esto arregla.
      final creadoPorConsulta = chat['creadoPor'] as String?;
      if (!esRescatista) {
        // Viendo como adoptante: acá van las que mandé CON ESE sombrero
        // (sin creadoPor) — las que mandé como rescatista/albergue
        // pertenecen a esas otras pestañas.
        return creadoPorConsulta == null;
      }
      if (creadoPorConsulta == null) return false;
      return esAlbergue
          ? creadoPorConsulta == 'albergue'
          : creadoPorConsulta == 'rescatista';
    }
    // Una misma cuenta puede tener rol rescatista y albergue a la vez;
    // esto evita que se mezclen las conversaciones de un rol con el otro.
    if (esRescatista) {
      final creadoPor = chat['creadoPor'] as String? ?? 'rescatista';
      if (esAlbergue) return creadoPor == 'albergue';
      return creadoPor != 'albergue';
    }
    return true;
  }

  /// El `emisor` de un mensaje tiene que coincidir con el lado REAL de
  /// quien escribe (regla de Firestore, ver `mensajes/create` en
  /// firestore.rules — un mensaje con el emisor equivocado se rechaza
  /// entero) — `'adoptante'` si [miUid] es el `adoptanteId` de este chat,
  /// `'rescatista'` en cualquier otro caso.
  ///
  /// Cubre la autoconsulta (`adoptanteId == rescatistaId`, mismo uid —
  /// ej. un albergue que pidió hogar de paso para su propio animal): ahí
  /// SIEMPRE corresponde `'adoptante'`, sin importar con qué sombrero se
  /// esté actuando. `chat_screen.dart` ya resolvía esto bien para mensajes
  /// escritos a mano (`_autoChat`/`_miEmisor`) — `enviarMensajeChat`
  /// (solicitudes_rescatista_screen.dart, los avisos automáticos de
  /// vencimiento de hogar de paso y seguimiento post-adopción) mandaba
  /// `'rescatista'` fijo, sin este chequeo. En una autoconsulta la regla
  /// rechazaba ese mensaje — pero el chat.update() de `ultimoMensaje`/
  /// `noLeidosAdoptante` es una escritura SEPARADA que ya había pasado
  /// antes de intentar el mensaje, así que no se deshacía sola: el chat
  /// quedaba con una vista previa y un "sin leer" de un mensaje que en
  /// realidad nunca se guardó. Hallazgo real: como adoptante, ver el
  /// aviso de "venció el hogar de paso" en la vista previa del chat, pero
  /// abrirlo y encontrarlo vacío.
  static String emisorPara({
    required String adoptanteId,
    required String miUid,
  }) => adoptanteId == miUid ? 'adoptante' : 'rescatista';

  /// ¿Esta burbuja va del lado de quien mira (derecha) o del otro (izquierda)?
  ///
  /// ÚNICA fuente de esa decisión. Vivía inline dentro de `_burbujaMensaje`
  /// (chat_screen.dart), sin ningún test posible — y es justamente la regla
  /// que más veces se rompió y se volvió a romper: "todos los mensajes se
  /// ven del mismo lado" apareció por separado en chats de animal y en
  /// consultas a un negocio. Acá es una función pura sobre datos, así que
  /// cada caso queda clavado con un test en vez de depender de reproducirlo
  /// a mano en el emulador cambiando de rol.
  ///
  /// [mensaje] es el doc del mensaje; [miEmisor] el emisor que le
  /// corresponde a quien mira (ver [emisorPara]); [esRescatista] el sombrero
  /// con el que tiene abierta la pantalla; [esAutoconsulta] si la misma
  /// cuenta es las DOS partes de este chat.
  ///
  /// La regla, y por qué son dos caminos y no uno:
  ///
  ///  · Chat entre dos personas distintas → manda `emisor`. Es la autoridad
  ///    y es infalsificable: la regla de Firestore lo valida contra el uid
  ///    de quien escribe. Confiar en el otro campo acá reabriría el agujero
  ///    de mandar un mensaje marcado como si lo hubiera escrito el otro.
  ///  · AUTOCONSULTA → `emisor` no sirve para NADA acá: la regla lo resuelve
  ///    con `adoptanteId == uid ? 'adoptante' : 'rescatista'`, y con los dos
  ///    ids iguales da SIEMPRE 'adoptante'. Ahí manda `escritoPorRescatista`,
  ///    que guarda el sombrero real. No es un riesgo de seguridad porque en
  ///    una autoconsulta las dos partes son la misma persona: no hay nadie a
  ///    quien suplantar.
  ///
  /// Un mensaje viejo (anterior a que existiera `escritoPorRescatista`) cae
  /// al camino de `emisor` aunque sea autoconsulta — es lo único que se
  /// puede hacer con el dato que tiene, y por eso esos chats viejos siguen
  /// viéndose mal aunque el arreglo esté puesto.
  static bool esMiBurbuja(
    Map<String, dynamic> mensaje, {
    required String miEmisor,
    required bool esRescatista,
    required bool esAutoconsulta,
  }) {
    final sombrero = mensaje['escritoPorRescatista'] as bool?;
    if (esAutoconsulta && sombrero != null) return sombrero == esRescatista;
    return mensaje['emisor'] == miEmisor;
  }

  /// Con qué rol hay que volver a abrir el perfil público de un aliado
  /// desde un chat de consulta ya existente (botón "Conversando sobre X"
  /// en chat_screen.dart) — para que tocar "Contactar" de nuevo desde ahí
  /// reuse la MISMA conversación en vez de fragmentarla en una nueva.
  ///
  /// [idNegocio] arma un id DISTINTO según el contexto ('general' vs
  /// 'rescatista'/'albergue'), así que pasar el sombrero equivocado (o
  /// ninguno) al volver a contactar arma un chat aparte con contexto
  /// "general" — el original se queda con los mensajes ya leídos, y los
  /// nuevos, sin leer, caen en un documento distinto que ese rol nunca
  /// mira. Hallazgo real: el mensaje sí se mandaba y se veía en la
  /// conversación (el chat original seguía ahí, intacto), pero el badge
  /// de "sin leer" del rol correcto nunca lo contaba, porque en realidad
  /// vivía en OTRO documento.
  ///
  /// Solo aplica cuando quien mira es quien contactó
  /// ([esRescatistaEnEsteChat] es `false`) — si en cambio soy el aliado
  /// viendo mi propio negocio, no hay ningún sombrero previo que preservar.
  static ({bool esRescatista, bool esAlbergue}) rolParaRecontactar({
    required bool esRescatistaEnEsteChat,
    required String? creadoPor,
  }) {
    final soyQuienContacto = !esRescatistaEnEsteChat;
    return (
      esRescatista: soyQuienContacto && creadoPor != null,
      esAlbergue: soyQuienContacto && creadoPor == 'albergue',
    );
  }

  /// Chats de esta cuenta: los RECIBIDOS si [esRescatista] (o sea, donde
  /// esta cuenta es `rescatistaId` — quien publicó el animal, o el aliado
  /// dueño del negocio), o donde es el adoptante si no.
  ///
  /// Antes esta consulta estaba escrita a mano en 4 pantallas (home,
  /// albergue_home, aliado_home, adoptante_chats), una de ellas con un
  /// ternario para elegir el campo. Es la consulta base de todo lo que
  /// muestra chats, así que conviene que exista en un solo lugar: el filtro
  /// de "de qué lado estoy" es exactamente la pregunta que ya centralizan
  /// [perteneceALaLista] y [noLeidosPara].
  Stream<QuerySnapshot<Map<String, dynamic>>> mios({
    required String uid,
    required bool esRescatista,
  }) => _db
      .collection('chats')
      .where(esRescatista ? 'rescatistaId' : 'adoptanteId', isEqualTo: uid)
      .snapshots();

  /// Consultas que ESTA cuenta le mandó a un negocio aliado.
  ///
  /// Va aparte de [mios] a propósito: en una consulta a un negocio el
  /// `rescatistaId` es SIEMPRE el aliado (sin importar quién lo contactó),
  /// así que un rescatista/albergue que escribe a un negocio queda como
  /// `adoptanteId` en ese chat y su propia bandeja —que filtra por
  /// `rescatistaId`— nunca lo encontraba. Ese fue un bug real: el badge de
  /// "mensajes sin leer" no contaba las respuestas a las consultas propias.
  Stream<QuerySnapshot<Map<String, dynamic>>> consultasEnviadas({
    required String uid,
  }) => _db
      .collection('chats')
      .where('adoptanteId', isEqualTo: uid)
      .where('tipoSolicitud', isEqualTo: 'consulta_aliado')
      .snapshots();

  /// Consultas que ESTA cuenta RECIBIÓ como negocio aliado.
  ///
  /// No alcanza con [mios] aunque el aliado sea `rescatistaId` en todas sus
  /// consultas: si la misma cuenta también es rescatista o albergue, [mios]
  /// le traería además los chats de sus animales, y el panel del negocio
  /// mostraría conversaciones que no son de ese sombrero. Es la misma
  /// separación que ya hace `soloConsultas` en [perteneceALaLista].
  Stream<QuerySnapshot<Map<String, dynamic>>> consultasRecibidas({
    required String uid,
  }) => _db
      .collection('chats')
      .where('rescatistaId', isEqualTo: uid)
      .where('tipoSolicitud', isEqualTo: 'consulta_aliado')
      .snapshots();

  /// El chat de un animal puntual, o `null` si todavía no existe.
  ///
  /// Dos caminos, y por eso estaba copiado (con variantes) en 4 lugares:
  /// con [rescateId] y [adoptanteId] se va derecho al id determinístico;
  /// sin eso (chats viejos, de antes de que existiera `rescateId`) se cae al
  /// match por `animalNombre` acotado por el dueño que se conozca —
  /// [adoptanteId] o [rescatistaId].
  ///
  /// **El try/catch no es decorativo:** leer un chat que NO existe da
  /// `permission-denied` con nuestras reglas (no pueden probar "sos
  /// participante" de un documento que no está). Eso no es falta de permiso
  /// real, así que se traduce a "no hay chat" en vez de dejar que la
  /// excepción escape. Sin ese detalle —fácil de olvidar al copiar— tocar
  /// "Contactar" simplemente no hacía nada, que es justo el bug que se
  /// arregló una vez en una copia y siguió vivo en las otras.
  Future<DocumentSnapshot<Map<String, dynamic>>?> buscarDeAnimal({
    String? rescateId,
    String? adoptanteId,
    String? animalNombre,
    String? rescatistaId,
  }) async {
    try {
      if ((rescateId?.isNotEmpty ?? false) &&
          (adoptanteId?.isNotEmpty ?? false)) {
        final doc = await _db
            .collection('chats')
            .doc(idAnimal(rescateId: rescateId!, adoptanteId: adoptanteId!))
            .get();
        return doc.exists ? doc : null;
      }
      if (!(animalNombre?.isNotEmpty ?? false)) return null;
      // Sin ningún dueño con qué acotar, una búsqueda por nombre suelto
      // devolvería el chat de CUALQUIER persona que tenga un animal así —
      // y encima las reglas la rechazarían. Pasa con datos corruptos (una
      // solicitud sin adoptanteId): antes ese caso armaba un id de chat
      // basura tipo "rescateId_", ahora simplemente no encuentra nada, que
      // es lo correcto: mejor crear un chat nuevo que escribir en el de
      // otra persona.
      if (!(adoptanteId?.isNotEmpty ?? false) &&
          !(rescatistaId?.isNotEmpty ?? false)) {
        return null;
      }
      Query<Map<String, dynamic>> q = _db
          .collection('chats')
          .where('animalNombre', isEqualTo: animalNombre);
      // Acotar por dueño no es cosmético: es lo que hace que el servidor
      // acepte la consulta en vez de rechazarla por las reglas, además de
      // no traer el chat de otra persona con un animal del mismo nombre.
      if (adoptanteId?.isNotEmpty ?? false) {
        q = q.where('adoptanteId', isEqualTo: adoptanteId);
      }
      if (rescatistaId?.isNotEmpty ?? false) {
        q = q.where('rescatistaId', isEqualTo: rescatistaId);
      }
      final chats = await q.limit(1).get();
      return chats.docs.isEmpty ? null : chats.docs.first;
    } catch (_) {
      return null;
    }
  }

  /// Id nuevo para un chat que no puede usar ninguno de los dos esquemas
  /// determinísticos ([idAnimal]/[idNegocio]) — solo pasa con datos legados
  /// sin `rescateId`. Se genera local, sin tocar la red.
  String nuevoId() => _db.collection('chats').doc().id;

  /// Hora corta ("14:05") como la guardan todos los mensajes. Estaba
  /// calculada a mano en los 2 lugares que escriben mensajes, con el mismo
  /// padLeft — si una de las dos copias cambiaba de formato, los mensajes
  /// del mismo chat quedaban con dos formatos distintos según quién los
  /// mandó.
  static String horaAhora([DateTime? ahora]) {
    final n = ahora ?? DateTime.now();
    return '${n.hour}:${n.minute.toString().padLeft(2, '0')}';
  }

  /// Los mensajes de un chat, del más viejo al más nuevo.
  Stream<QuerySnapshot<Map<String, dynamic>>> mensajes(String chatId) => _db
      .collection('chats')
      .doc(chatId)
      .collection('mensajes')
      .orderBy('creadoEn')
      .snapshots();

  /// Escribe los campos de vista previa/contador del chat (fusionados, sin
  /// pisar lo que ya había) y el mensaje en la subcolección — como una
  /// única operación atómica.
  ///
  /// **Por qué un `WriteBatch` y no dos escrituras seguidas.** Hasta hace
  /// poco esto eran dos escrituras separadas (`.set()` del chat, después
  /// `.add()` del mensaje), con el orden elegido a propósito: chat primero,
  /// mensaje después, para que un mensaje NUNCA quedara guardado sin que su
  /// vista previa/contador se reflejaran (la alternativa — mensaje primero
  /// — habría hecho que un reintento tras un fallo del chat duplicara el
  /// mensaje). Pero esa elección no cerraba el problema simétrico: si el
  /// proceso moría DESPUÉS de la escritura del chat y ANTES de la del
  /// mensaje, el contador de "sin leer" quedaba incrementado (o el chat
  /// recién creado) sin que el mensaje correspondiente existiera de
  /// verdad — un "sin leer" fantasma para siempre, porque nada en la app
  /// recalcula el contador desde los mensajes reales de la subcolección.
  /// Auditoría de arquitectura, riesgo 🟡 "sin reconciliación".
  ///
  /// Un `WriteBatch` resuelve las dos cosas a la vez: Firestore garantiza
  /// que todas las escrituras del batch se confirman juntas o ninguna lo
  /// hace. Ya no hay dos escrituras que puedan quedar a mitad de camino
  /// una respecto de la otra — el desfasaje deja de ser posible, así que
  /// no hace falta reconciliar nada después. Y un reintento tras un fallo
  /// ya no puede duplicar nada, porque un fallo significa que NINGUNA de
  /// las dos escrituras se aplicó.
  ///
  /// `set(merge: true)` sobre el chat, no `update()`: así sirve aunque el
  /// chat todavía no exista (el otro lado nunca llegó a crearlo), en vez
  /// de fallar con "no encontrado".
  Future<void> _escribirChatYMensaje({
    required String chatId,
    required Map<String, dynamic> camposChat,
    required String texto,
    required String emisor,
    required String hora,
    bool? escritoPorRescatista,
    bool avisoDeEstado = false,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final chatRef = _db.collection('chats').doc(chatId);
    final mensajeRef = chatRef.collection('mensajes').doc();
    final batch = _db.batch();
    batch.set(chatRef, camposChat, SetOptions(merge: true));
    batch.set(mensajeRef, {
      'texto': texto,
      'emisor': emisor,
      'hora': hora,
      'creadoEn': FieldValue.serverTimestamp(),
      if (escritoPorRescatista != null)
        'escritoPorRescatista': escritoPorRescatista,
      if (avisoDeEstado) 'avisoDeEstado': true,
    });
    await batch.commit().timeout(timeout);
  }

  /// Escribe un mensaje: el último-mensaje/hora/contador de no leídos del
  /// chat, y el mensaje en la subcolección, atómicamente (ver
  /// [_escribirChatYMensaje]).
  ///
  /// `FieldValue.increment(1)` sobre un campo que no existe lo deja en 1,
  /// así que el primer mensaje de un chat nuevo no necesita ningún caso
  /// especial.
  ///
  /// [paraAdoptante] dice a QUIÉN se le suma el no leído: al adoptante si
  /// escribe el rescatista/albergue/aliado, y al revés. [camposChat] son
  /// campos extra del documento del chat (ej. los datos de creación de un
  /// chat legado) que se escriben en ESTA misma operación, no en una aparte.
  ///
  /// [avisoParaAmbosLados]: además de [paraAdoptante], suma TAMBIÉN el "sin
  /// leer" del otro lado. Es para avisos que dispara el paso del tiempo —
  /// vencimiento de hogar de paso, seguimiento post-adopción — sin que el
  /// rescatista/albergue haya hecho nada: `escritoPorRescatista: true` los
  /// dibuja de su lado, pero al no sumarle ningún "sin leer" quedaban
  /// guardados en el chat sin ninguna señal visible para él (ni en el badge
  /// azul del panel, ni en el ícono de Chats) — se enteraba solo si abría
  /// esa conversación puntual por otro motivo. Con muchos animales a la vez
  /// eso es no enterarse nunca. Hallazgo real de Eliza. NO se usa para
  /// avisos que sí dispara una acción consciente del rescatista (aprobar,
  /// rechazar una solicitud) — de esos ya sabe, porque los hizo él mismo.
  Future<void> registrarMensaje({
    required String chatId,
    required String texto,
    required String emisor,
    required bool paraAdoptante,
    bool avisoParaAmbosLados = false,
    bool? escritoPorRescatista,
    bool avisoDeEstado = false,
    Map<String, dynamic> camposChat = const {},
    String? hora,
  }) async {
    final h = hora ?? horaAhora();
    await _escribirChatYMensaje(
      chatId: chatId,
      camposChat: {
        ...camposChat,
        'ultimoMensaje': texto,
        'ultimaHora': h,
        'ultimoMensajeEn': FieldValue.serverTimestamp(),
        paraAdoptante ? 'noLeidosAdoptante' : 'noLeidosRescatista':
            FieldValue.increment(1),
        if (avisoParaAmbosLados)
          paraAdoptante ? 'noLeidosRescatista' : 'noLeidosAdoptante':
              FieldValue.increment(1),
      },
      texto: texto,
      emisor: emisor,
      hora: h,
      escritoPorRescatista: escritoPorRescatista,
      avisoDeEstado: avisoDeEstado,
    );
  }

  /// Solo el mensaje, sin tocar la vista previa del chat.
  ///
  /// **Ojo antes de usar esto junto con una escritura aparte del chat**
  /// (ej. [asegurarChatAnimal] con `extra` seguido de esta función): esa
  /// combinación es exactamente el patrón de dos escrituras no atómicas
  /// que [_escribirChatYMensaje] existe para evitar — si el proceso muere
  /// entre una y otra, el contador de "sin leer" queda incrementado sin
  /// que este mensaje llegue a existir. [registrarMensaje] (o, si hace
  /// falta crear el chat en el mismo paso, llamar a
  /// [_escribirChatYMensaje] directo) son las formas seguras de mandar un
  /// mensaje real. Esta función queda para el caso genuino de "el chat ya
  /// tiene su vista previa resuelta de antes, solo hace falta el mensaje".
  ///
  /// [escritoPorRescatista]: con QUÉ SOMBRERO se escribió, aparte de
  /// [emisor]. Parecen lo mismo y no lo son.
  ///
  /// `emisor` lo dicta la regla de Firestore, que resuelve quién escribe con
  /// `adoptanteId == uid ? 'adoptante' : 'rescatista'`. En una AUTOCONSULTA
  /// (la misma cuenta es las dos partes del chat: un albergue que pidió
  /// adopción u hogar de paso para su propio animal) ese ternario da
  /// SIEMPRE 'adoptante', escriba desde el lado que escriba. Y como la
  /// pantalla decidía el lado de la burbuja mirando `emisor`, todos los
  /// mensajes de esos chats se dibujaban del mismo lado, sin poder
  /// distinguir la respuesta del rescatista. Hallazgo real de Eliza
  /// probando con su propia cuenta en los dos roles.
  ///
  /// Este campo guarda el dato que `emisor` no puede: el sombrero real.
  /// **Solo se usa para dibujar, y SOLO en autoconsulta** — en un chat entre
  /// dos personas distintas `emisor` sigue siendo la autoridad, porque ahí
  /// sí es infalsificable (la regla lo valida contra el uid). Confiar en
  /// este campo siempre reabriría el agujero de mandar un mensaje marcado
  /// como del otro (ver el comentario de mensajes/create en firestore.rules).
  ///
  /// Se guarda solo si viene: los mensajes viejos no lo tienen y se siguen
  /// dibujando por `emisor`, como hasta ahora.
  Future<void> agregarMensaje({
    required String chatId,
    required String texto,
    required String emisor,
    String? hora,
    bool? escritoPorRescatista,
  }) => _db.collection('chats').doc(chatId).collection('mensajes').add({
    'texto': texto,
    'emisor': emisor,
    'hora': hora ?? horaAhora(),
    'creadoEn': FieldValue.serverTimestamp(),
    if (escritoPorRescatista != null)
      'escritoPorRescatista': escritoPorRescatista,
  });

  /// Pone en cero los no leídos del lado que acaba de abrir el chat.
  /// Best-effort a propósito: si falla, el peor caso es un badge que sigue
  /// mostrando un número: nunca vale la pena romperle la pantalla a alguien
  /// por eso.
  Future<void> marcarLeido({
    required String chatId,
    required bool esRescatista,
  }) async {
    try {
      await _db.collection('chats').doc(chatId).update({
        esRescatista ? 'noLeidosRescatista' : 'noLeidosAdoptante': 0,
      });
    } catch (_) {}
  }

  /// Id determinístico para un chat sobre un animal puntual: el mismo par
  /// (animal, adoptante) siempre da el mismo id, sin importar qué pantalla
  /// lo abra ni quién escriba primero.
  String idAnimal({required String rescateId, required String adoptanteId}) =>
      '${rescateId}_$adoptanteId';

  /// Avisa automáticamente a alguien sobre un animal puntual, por chat —
  /// crea el chat si todavía no existe. ÚNICA fuente de este flujo para
  /// toda la app: aprobar/rechazar una solicitud, vencimiento de hogar de
  /// paso, seguimiento post-adopción, y el aviso de que el animal falleció
  /// pasan todos por acá.
  ///
  /// **Existía dos veces, con comportamiento DISTINTO, y esa diferencia
  /// era un bug real.** `enviarMensajeChat` (antes en
  /// `solicitudes_rescatista_screen.dart`) sí creaba el chat si hacía
  /// falta. El aviso de "el animal falleció" (antes en `CambiarEstadoSheet`,
  /// ahora `widgets/cambiar_estado_sheet.dart`) NO —
  /// si la persona nunca había abierto un chat con el rescatista, el
  /// aviso se descartaba en silencio ("no hay chat, no hay nada que
  /// reportar"). Una solicitud recién mandada, todavía PENDIENTE (nunca
  /// aprobada), muchas veces no tiene ningún chat abierto todavía — así
  /// que si el animal moría antes de aprobarla, esa persona no se enteraba
  /// nunca. Hallazgo real de Eliza: pidió adoptar, el rescatista marcó el
  /// animal como fallecido, y el aviso nunca le llegó.
  ///
  /// [rescateId] vacío/null cae al esquema legado (sin id determinístico,
  /// se crea o reusa un chat suelto vía [registrarMensaje]) — mismo
  /// comportamiento que ya tenía `enviarMensajeChat` para datos viejos.
  Future<bool> avisarSobreAnimal({
    required String adoptanteId,
    required String adoptanteNombre,
    required String rescatistaId,
    required String rescatista,
    required String texto,
    String? rescateId,
    String? animalNombre,
    String? creadoPor,
    String? especie,
    String? fotoUrl,
    String? tipoSolicitud,
    bool avisoParaAmbosLados = false,
    /// La solicitud que motiva este aviso, cuando la hay.
    ///
    /// Es el ANCLA del chat para las reglas de seguridad: un chat entre un
    /// rescatista y un adoptante es legitimo si hay un animal real
    /// (`rescateId`) o una solicitud real que los una. Sin ninguno de los
    /// dos, la regla no puede distinguir este aviso de alguien que le
    /// escribe a un desconocido, y por eso lo rechaza. Ver firestore.rules,
    /// chats.create, rama (C).
    ///
    /// Solo hace falta en el camino sin `rescateId` (solicitudes viejas,
    /// anteriores a que la regla lo volviera obligatorio). Con `rescateId`
    /// el ancla ya es el animal.
    String? solicitudId,
    /// El mensaje acompana un cambio de estado de la solicitud
    /// (aprobada/rechazada), que YA dispara su propia notificacion push
    /// desde onCambioEstadoSolicitud. Marcarlo asi hace que onNuevoMensaje
    /// no mande la suya encima: eran dos push por un solo hecho, con textos
    /// distintos - "Tu solicitud fue aprobada" y, aparte, "Mensaje sobre
    /// Pacolin". El mensaje se escribe igual y se ve en el chat como
    /// siempre; lo unico que se evita es el aviso repetido.
    bool avisoDeEstado = false,
  }) async {
    try {
      final hora = horaAhora();
      final emisor = emisorPara(adoptanteId: adoptanteId, miUid: rescatistaId);
      final existente = await buscarDeAnimal(
        rescateId: rescateId,
        adoptanteId: adoptanteId,
        animalNombre: animalNombre,
      );

      if (existente == null && (rescateId?.isNotEmpty ?? false)) {
        // Antes: asegurarChatAnimal(extra: {...}) + agregarMensaje() por
        // separado — dos escrituras no atómicas entre sí (aunque
        // asegurarChatAnimal en sí mismo sea una sola escritura). Directo a
        // _escribirChatYMensaje para que la creación del chat Y su primer
        // mensaje se confirmen juntos o ninguno lo haga.
        final chatId = idAnimal(
          rescateId: rescateId!,
          adoptanteId: adoptanteId,
        );
        await _escribirChatYMensaje(
          chatId: chatId,
          camposChat: {
            if (animalNombre != null) 'animalNombre': animalNombre,
            'rescateId': rescateId,
            'creadoPor': creadoPor ?? 'rescatista',
            'rescatista': rescatista,
            'rescatistaId': rescatistaId,
            'adoptanteId': adoptanteId,
            'adoptanteNombre': adoptanteNombre,
            if (especie != null) 'especie': especie,
            if (fotoUrl != null) 'fotoUrl': fotoUrl,
            'ultimoMensaje': texto,
            'ultimaHora': hora,
            'ultimoMensajeEn': FieldValue.serverTimestamp(),
            'noLeidosAdoptante': 1,
            if (avisoParaAmbosLados) 'noLeidosRescatista': 1,
            if (tipoSolicitud != null) 'tipoSolicitud': tipoSolicitud,
          },
          texto: texto,
          emisor: emisor,
          hora: hora,
          avisoDeEstado: avisoDeEstado,
          // Estos avisos los manda siempre el rescatista/albergue. En una
          // autoconsulta `emisor` vale 'adoptante' por la regla, así que
          // sin este dato el aviso se dibujaría del lado equivocado.
          escritoPorRescatista: true,
        );
        return true;
      }

      // Chat que ya existía, o uno legado sin rescateId que hay que crear.
      final datosPrevios = existente?.data() ?? const <String, dynamic>{};
      await registrarMensaje(
        chatId: existente?.id ?? nuevoId(),
        texto: texto,
        emisor: emisor,
        paraAdoptante: true,
        avisoParaAmbosLados: avisoParaAmbosLados,
        avisoDeEstado: avisoDeEstado,
        hora: hora,
        escritoPorRescatista: true,
        camposChat: {
          if (existente == null) ...{
            if (solicitudId != null && solicitudId.isNotEmpty)
              'solicitudId': solicitudId,
            'adoptanteId': adoptanteId,
            'adoptanteNombre': adoptanteNombre,
            'animalNombre': animalNombre,
            'creadoPor': creadoPor ?? 'rescatista',
            'rescatistaId': rescatistaId,
            'rescatista': rescatista,
            if (tipoSolicitud != null) 'tipoSolicitud': tipoSolicitud,
            if (especie != null) 'especie': especie,
          },
          // Solo se completa la foto si el chat todavía no tenía una:
          // nunca se pisa la que ya estaba.
          if (fotoUrl != null && datosPrevios['fotoUrl'] == null)
            'fotoUrl': fotoUrl,
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }

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
    await _db
        .collection('chats')
        .doc(chatId)
        .set({
          if (animalNombre != null) 'animalNombre': animalNombre,
          'rescateId': rescateId,
          'creadoPor': creadoPor,
          'rescatista': rescatista,
          'rescatistaId': rescatistaId,
          'adoptanteId': adoptanteId,
          'adoptanteNombre': adoptanteNombre,
          if (especie != null) 'especie': especie,
          if (fotoUrl != null) 'fotoUrl': fotoUrl,
          if (extra != null) ...extra,
        }, SetOptions(merge: true))
        .timeout(timeout);
    return chatId;
  }

  /// Id determinístico para un chat de consulta con un negocio aliado (no es
  /// sobre un animal puntual, así que usa un esquema separado). `contexto`
  /// distingue si la cuenta contactó como adoptante, rescatista o albergue —
  /// son conversaciones separadas a propósito, igual que una cuenta con
  /// doble rol nunca mezcla los chats de sus animales entre uno y otro.
  String idNegocio({
    required String aliadoId,
    required String adoptanteId,
    String contexto = 'general',
  }) => '${aliadoId}_${adoptanteId}_negocio_$contexto';

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
    final chatId = idNegocio(
      aliadoId: aliadoId,
      adoptanteId: adoptanteId,
      contexto: contexto,
    );
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
      await ref
          .set({
            'adoptanteId': adoptanteId,
            'adoptanteNombre': adoptanteNombre,
            'animalNombre': aliadoNombre,
            'rescatista': aliadoNombre,
            'rescatistaId': aliadoId,
            if (fotoBase64 != null) 'fotoBase64': fotoBase64,
            'tipoSolicitud': 'consulta_aliado',
            // Mismo campo que usan los chats de animal para separar bandejas de
            // una cuenta con doble rol (ver AdoptanteChatsScreen) — sin esto,
            // una consulta enviada como albergue quedaba indistinguible de una
            // enviada como rescatista al filtrar la propia lista de chats.
            if (contexto == 'rescatista' || contexto == 'albergue')
              'creadoPor': contexto,
            'ultimoMensaje': '',
            'ultimaHora': '',
            'ultimoMensajeEn': FieldValue.serverTimestamp(),
            'noLeidosAdoptante': 0,
            'noLeidosRescatista': 0,
          })
          .timeout(timeout);
    }
    return chatId;
  }
}
