import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:go_router/go_router.dart';
import '../theme.dart';
import '../domain/reglas_negocio.dart';
import '../routing/app_router.dart';
import '../widgets/avatares.dart';
import '../widgets/fotos.dart';
import '../widgets/texto_sin_desborde.dart';
import '../data/chats_repository.dart';
import '../data/creator_role.dart';
import '../data/firestore_resiliencia.dart';
import '../data/rescates_repository.dart';

class ChatScreen extends StatefulWidget {
  final Map<String, dynamic> animal;
  final bool esRescatista;
  final String? chatId;
  const ChatScreen({
    super.key,
    required this.animal,
    this.esRescatista = false,
    this.chatId,
  });
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgCtl = TextEditingController();
  final _scrollCtl = ScrollController();
  late final String _chatId;
  final _chatsRepo = ChatsRepository();
  // Se completa cuando el doc del chat ya existe en Firestore. El listener
  // de mensajes recién se conecta después de esto: las reglas de mensajes
  // verifican participante contra el doc del chat, y si el listener se
  // conecta ANTES de que el doc exista, Firestore lo rechaza y lo mata para
  // siempre (no reintenta) — los mensajes no aparecían hasta salir y volver
  // a entrar al chat.
  late final Future<void> _chatListo;
  // Foto de perfil de la CONTRAPARTE (no la propia). Se resuelve leyendo el
  // doc del chat (que siempre tiene adoptanteId/rescatistaId, sin importar
  // qué pantalla haya abierto este ChatScreen) y de ahí usuarios/{id} — así
  // no depende de que cada sitio de navegación pase la foto de la otra
  // persona en el mapa `animal`.
  //
  // Devuelve (fotoBase64, foto): fotoBase64 (el logo que un albergue sube a
  // propósito desde su perfil) solo se completa cuando la contraparte se
  // muestra en su capacidad de negocio — la misma cuenta puede tener rol de
  // albergue Y de adoptante a la vez (ver ARCHITECTURE.md), y ese mismo doc
  // usuarios/{id} es compartido: si siempre se mirara fotoBase64, un chat
  // donde la contraparte actúa como ADOPTANTE mostraría el logo de SU
  // PROPIO albergue en vez de su foto personal — mismo bug que ya se
  // arregló en AvatarUsuario (widgets/avatares.dart), acá vive aparte porque este
  // encabezado tiene su propia lógica de carga, no reutiliza ese widget.
  // Ver el detalle completo (chat de animal vs. consulta a un negocio,
  // y quién mira cada uno) en los comentarios de _cargarFotoContraparte.
  late final Future<(String?, String?)> _fotoContraparte;

  // La insignia de estado del animal ("Adoptado", "Hogar de paso"...) del
  // encabezado. `late final`, no armada dentro de build(): esta pantalla se
  // redibuja con CADA mensaje nuevo (el stream de mensajes emite), y un
  // `.snapshots()` creado en build() es un objeto nuevo cada vez — el
  // StreamBuilder se desuscribe y se resuscribe, y la insignia parpadea o
  // muestra un instante de caché vieja. Mismo patrón, y mismo arreglo, que
  // el resto de las pantallas de esta sesión (mis_rescates, solicitudes,
  // el carrusel del panel...). Los dos datos salen de `widget.animal`, que
  // no cambia mientras el chat está abierto, así que se resuelven una sola
  // vez acá.
  //
  // Con rescateId se busca el documento exacto; sin él (chats viejos) se
  // cae a buscar por nombre + dueño, que puede confundirse si hay dos
  // animales con el mismo nombre bajo la misma cuenta en distinto rol.
  late final String _rescateIdAnimal =
      widget.animal['rescateId'] as String? ?? '';
  late final String _rescatistaIdAnimal =
      widget.animal['rescatistaId'] as String? ?? '';
  late final Stream<DocumentSnapshot<Map<String, dynamic>>>?
  _estadoAnimalPorId = _rescateIdAnimal.isEmpty
      ? null
      : RescatesRepository().porId(_rescateIdAnimal);
  late final Stream<QuerySnapshot<Map<String, dynamic>>>?
  _estadoAnimalPorNombre =
      (_rescateIdAnimal.isNotEmpty || _rescatistaIdAnimal.isEmpty)
      ? null
      : RescatesRepository().porNombreYDueno(
          rescatistaId: _rescatistaIdAnimal,
          nombre: widget.animal['nombre'] as String? ?? '',
        );

  Future<(String?, String?)> _cargarFotoContraparte() async {
    final esConsulta = (widget.animal['tipoSolicitud'] as String? ?? '')
        .startsWith('consulta');
    // Consulta a un negocio Y yo soy quien contactó (no el negocio): la
    // contraparte es el aliado, y su logo ya viene fijo en
    // widget.animal['fotoBase64'] (denormalizado al crear el chat) — no
    // hace falta ir a buscarlo de nuevo acá.
    //
    // Pero si soy EL ALIADO viendo mi propio chat, la contraparte es quien
    // me escribió — antes esta función cortaba acá para CUALQUIER consulta
    // sin importar quién mira, así que el aliado veía SU PROPIO logo
    // reflejado en el encabezado en vez de la foto de quien le escribió.
    if (esConsulta && !widget.esRescatista) return (null, null);
    try {
      await _chatListo;
      final chatDoc = await FirebaseFirestore.instance
          .collection('chats')
          .doc(_chatId)
          .get();
      final d = chatDoc.data();
      if (d == null) return (null, null);
      final contraparteId = widget.esRescatista
          ? (d['adoptanteId'] as String? ?? '')
          : (d['rescatistaId'] as String? ?? '');
      if (contraparteId.isEmpty) return (null, null);
      final userDoc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(contraparteId)
          .get();
      final data = userDoc.data();
      // ChatsRepository.campoLogo* dice exactamente qué campo de
      // usuarios/{uid} mirar para el logo de negocio de la contraparte (o
      // ninguno) — única fuente de esa regla en toda la app. Antes esta
      // pantalla re-adivinaba la misma pregunta con su propia lectura de
      // creadoPor, en paralelo a como lo hacía (distinto) la lista de
      // chats — dos adivinanzas separadas para el mismo dato terminaban
      // desincronizadas para algunas combinaciones de roles.
      final campoLogo = widget.esRescatista
          ? ChatsRepository.campoLogoAdoptante(d)
          : ChatsRepository.campoLogoRescatista(d);
      final fotoBase64 = campoLogo != null
          ? (data?[campoLogo] as String?)
          : null;
      return (fotoBase64, data?['foto'] as String?);
    } catch (_) {
      return (null, null);
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.chatId != null) {
      // Chat existente: usa el ID real del documento de Firestore
      _chatId = widget.chatId!;
      _chatListo = Future.value();
    } else {
      // El uid propio solo es el del adoptante cuando quien abre la pantalla
      // ES el adoptante; si abre el rescatista/albergue, el adoptante es la
      // otra persona y tiene que venir en el mapa (si no vino, no podemos
      // armar el id correcto y caemos al esquema legado más abajo).
      final propioUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final adoptanteUid = widget.esRescatista
          ? (widget.animal['adoptanteId'] as String? ?? '')
          : propioUid;
      final rescateId = widget.animal['rescateId'] as String?;
      if (rescateId != null &&
          rescateId.isNotEmpty &&
          adoptanteUid.isNotEmpty) {
        // Mismo esquema de id que usan todas las pantallas (ChatsRepository),
        // así dos animales con el mismo nombre nunca comparten conversación.
        _chatId = ChatsRepository().idAnimal(
          rescateId: rescateId,
          adoptanteId: adoptanteUid,
        );
        // Se asegura el documento exista sin importar qué lado lo abre
        // primero. Antes solo lo creaba el adoptante: si el rescatista
        // entraba primero a un chat que todavía no existía y escribía, el
        // mensaje se guardaba pero la actualización del chat fallaba (el
        // documento no existía) — la app avisaba "no se pudo enviar" pero el
        // mensaje ya había quedado guardado, y si reintentaba quedaba duplicado.
        _chatListo = ChatsRepository()
            .asegurarChatAnimal(
              adoptanteId: adoptanteUid,
              adoptanteNombre: widget.esRescatista
                  ? (widget.animal['adoptanteNombre'] as String? ?? 'Adoptante')
                  : (FirebaseAuth.instance.currentUser?.displayName ??
                        'Adoptante'),
              rescateId: rescateId,
              rescatistaId: widget.animal['rescatistaId'] as String? ?? '',
              rescatista:
                  widget.animal['rescatista'] as String? ?? 'Rescatista',
              creadoPor: widget.animal['creadoPor'] as String? ?? 'rescatista',
              animalNombre: widget.animal['nombre'] as String?,
              especie: widget.animal['especie'] as String?,
              fotoUrl: widget.animal['fotoUrl'] as String?,
            )
            .catchError((_) => '');
      } else {
        // Animal sin rescateId, o sin saber quién es el adoptante (dato
        // legado): se mantiene el esquema anterior.
        final nombre = (widget.animal['nombre'] as String? ?? '')
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '_');
        final rescatista =
            ((widget.animal['rescatista'] as String?) ?? 'rescatista')
                .toLowerCase()
                .replaceAll(RegExp(r'[^a-z0-9]'), '_');
        _chatId = '${nombre}_$rescatista';
        // Solo el adoptante crea/actualiza el doc del chat en este esquema
        // legado, porque es el único lado del que tenemos datos confiables.
        if (!widget.esRescatista) {
          // ChatsRepository.asegurarChatLegado — antes esto era un `set()`
          // escrito a mano acá, el único camino de la app que creaba un
          // chat sin pasar por el repositorio. Ver su doc para el porqué.
          _chatListo = _chatsRepo
              .asegurarChatLegado(
                chatId: _chatId,
                adoptanteId: propioUid,
                adoptanteNombre:
                    FirebaseAuth.instance.currentUser?.displayName ??
                    'Adoptante',
                rescatistaId: widget.animal['rescatistaId'] as String? ?? '',
                rescatista:
                    widget.animal['rescatista'] as String? ?? 'Rescatista',
                creadoPor: widget.animal['creadoPor'] as String? ?? 'rescatista',
                solicitudId: widget.animal['solicitudId'] as String?,
                animalNombre: widget.animal['nombre'] as String?,
                especie: widget.animal['especie'] as String?,
                fotoUrl: widget.animal['fotoUrl'] as String?,
              )
              .catchError((_) {});
        } else {
          _chatListo = Future.value();
        }
      }
    }
    _fotoContraparte = _cargarFotoContraparte();
    // Resetea los no leídos del rol que abre el chat — después de que el
    // doc exista, para no hacer un update sobre un doc que todavía no está.
    _chatListo.whenComplete(
      () => _chatsRepo.marcarLeido(
        chatId: _chatId,
        esRescatista: widget.esRescatista,
      ),
    );
  }

  // Autoconsulta: la misma cuenta es adoptanteId Y rescatistaId de este chat
  // (por ejemplo, una cuenta con rol de albergue que pidió hogar de paso
  // para su propio animal). La regla de Firestore (firestore.rules, ver
  // comentario junto a mensajes/create) prioriza adoptanteId para resolver
  // esa ambigüedad y exige emisor 'adoptante' sin importar desde qué lado
  // se abra la pantalla — sin este chequeo, entrar como rescatista/albergue
  // a un chat así mandaba emisor 'rescatista' y la regla rechazaba la
  // escritura entera ("No se pudo enviar el mensaje"). Mismo hallazgo que
  // ya se arregló para consulta_aliado, ahora en un chat de animal normal.
  bool get _autoChat {
    final propioUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return widget.esRescatista &&
        propioUid.isNotEmpty &&
        (widget.animal['adoptanteId'] as String? ?? '') == propioUid;
  }

  /// Igual que [_autoChat] pero visto desde CUALQUIERA de los dos lados: la
  /// cuenta que mira es también la contraparte de este chat.
  ///
  /// [_autoChat] solo lo detecta entrando como rescatista (es lo único que
  /// necesita para elegir el `emisor` que la regla exige). Para DIBUJAR
  /// hace falta reconocerlo también desde el lado adoptante, que es donde
  /// Eliza vio todas las burbujas del mismo lado.
  bool get _esAutoconsulta {
    final propioUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (propioUid.isEmpty) return false;
    final otroLado = widget.esRescatista
        ? (widget.animal['adoptanteId'] as String? ?? '')
        : (widget.animal['rescatistaId'] as String? ?? '');
    return otroLado == propioUid;
  }

  String get _miEmisor =>
      (widget.esRescatista && !_autoChat) ? 'rescatista' : 'adoptante';

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _msgCtl.clear();
    try {
      // Espera a que el documento del chat EXISTA antes de mandar nada.
      //
      // initState lo asegura (asegurarChatAnimal / asegurarChatLegado) pero
      // no esperaba a que terminara: escribir rápido, apenas se abre la
      // pantalla, podía mandar el mensaje antes. Y un mensaje sobre un chat
      // que todavía no existe se rechaza — la regla de mensajes/create hace
      // get() sobre el chat. Ver el comentario largo en
      // ChatsRepository._escribirChatYMensaje: es el mismo silencio que
      // dejaba sin avisar al adoptante, por una tercera puerta.
      //
      // _chatListo ya se traga sus propios errores, así que esperar acá no
      // agrega un modo de falla nuevo.
      await _chatListo;
      // registrarMensaje es dueño del orden (vista previa del chat primero,
      // mensaje después) y del set(merge:true) que crea el chat si el otro
      // lado nunca llegó a crearlo — ver su doc en chats_repository.dart
      // para el porqué completo de las dos cosas.
      await _chatsRepo.registrarMensaje(
        chatId: _chatId,
        texto: trimmed,
        emisor: _miEmisor,
        paraAdoptante: widget.esRescatista,
        // El sombrero real con el que se escribió, que en autoconsulta es
        // lo único que distingue los dos lados (`emisor` ahí vale siempre
        // 'adoptante' porque la regla lo exige) — ver agregarMensaje.
        escritoPorRescatista: widget.esRescatista,
      );
      // Se registra CADA mensaje, no solo "el primero" — distinguir el
      // primero de una conversación requeriría otra lectura extra (contar
      // mensajes previos) solo para este dato. Alcanza para el embudo: si
      // el evento existe al menos una vez para un chat, hubo conversación.
      FirebaseAnalytics.instance
          .logEvent(
            name: 'mensaje_enviado',
            parameters: {
              'emisor': _miEmisor,
              'tipo_solicitud':
                  widget.animal['tipoSolicitud'] as String? ?? 'adopcion',
            },
          )
          .catchError((_) {});
    } catch (e) {
      if (!mounted) return;
      // Un timeout NO es un mensaje perdido: Firestore lo tiene guardado y
      // lo manda al reconectar. Devolver el texto al campo y pedir que se
      // reintente era lo que producía el mensaje duplicado — ver
      // sePerdioLaEscritura() en data/firestore_resiliencia.dart.
      if (!sePerdioLaEscritura(e)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: msgAdvertencia,
            content: Text('Sin conexión. Se enviará cuando vuelva.'),
          ),
        );
        return;
      }
      _msgCtl.text = trimmed;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: msgError,
          content: Text('No se pudo enviar el mensaje. Intentá de nuevo.'),
        ),
      );
      return;
    }
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtl.hasClients) {
        _scrollCtl.animateTo(
          _scrollCtl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _msgCtl.dispose();
    _scrollCtl.dispose();
    super.dispose();
  }

  // La tarjeta "Conversando sobre X" tenía un "›" — en el resto de la app
  // esa flechita siempre significa "esto se puede tocar" — pero acá no
  // navegaba a ningún lado: un botón muerto. Hallazgo de auditoría de
  // código.
  //
  // Para el caso de un animal, se pide el documento fresco en vez de
  // reusar widget.animal tal cual: ese mapa puede venir incompleto según
  // quién abrió el chat (mis_solicitudes_screen.dart/
  // solicitudes_rescatista_screen.dart no siempre mandan raza/ubicación/
  // descripción/tags), y AnimalDetalleScreen los castea sin `?? ...` —
  // pasarle un mapa a medias la haría crashear en vez de solo abrir.
  Future<void> _abrirFicha(BuildContext context) async {
    final tipo = widget.animal['tipoSolicitud'] as String? ?? 'adopcion';
    if (tipo == 'consulta_aliado') {
      final aliadoId = widget.animal['rescatistaId'] as String? ?? '';
      if (aliadoId.isEmpty) return;
      // ChatsRepository.rolParaRecontactar — sin esto, AliadoPublicoScreen
      // recibía esRescatista/esAlbergue en false por defecto, así que
      // volver a tocar "Contactar" desde acá armaba el chat con contexto
      // "general" en vez del original ('rescatista'/'albergue'),
      // fragmentando la conversación en un documento aparte. Hallazgo de
      // auditoría de código.
      final rol = ChatsRepository.rolParaRecontactar(
        esRescatistaEnEsteChat: widget.esRescatista,
        creadoPor: widget.animal['creadoPor'] as String?,
      );
      context.push(
        AppRoutes.aliadoPublico,
        extra: (
          aliadoId: aliadoId,
          esRescatista: rol.esRescatista,
          esAlbergue: rol.esAlbergue,
        ),
      );
      return;
    }
    final rescateId = widget.animal['rescateId'] as String? ?? '';
    if (rescateId.isEmpty) return;
    final doc = await RescatesRepository().obtener(rescateId);
    if (!doc.exists || !context.mounted) return;
    final d = doc.data() as Map<String, dynamic>;
    context.push(
      AppRoutes.animalDetalle,
      extra: {
        ...d,
        // `rescateId` es el NOMBRE del documento, no un campo adentro, así
        // que `...d` no lo trae. Sin esta línea el mapa salía sin él, y
        // volver al chat desde la ficha (ficha -> "Hacer una pregunta")
        // caía en el esquema viejo de id por nombre: abría una
        // conversación NUEVA en vez de reabrir esta misma, y creaba un
        // chat sin nada contra lo cual anclarlo. Ver firestore.rules,
        // chats.create.
        'rescateId': rescateId,
        'nombre': (d['nombre'] as String?) ?? 'Sin nombre',
        'raza': (d['raza'] as String?) ?? 'Criolla',
        'ubicacion': (d['ubicacion'] as String?) ?? '',
        'descripcion': (d['descripcion'] as String?) ?? '',
        'tags': <String>[
          if (d['okConNinos'] == true) 'Amigable con niños',
          if (d['okConMascotas'] == true) 'Es sociable',
          if ((d['energia'] as String?)?.isNotEmpty == true)
            d['energia'] as String,
          if (d['estado'] != null && d['estado'] != 'Sano')
            d['estado'] as String,
        ],
      },
    );
  }

  // 'Hoy'/'Ayer'/'3 jul' según qué tan lejos esté [d] de hoy. Antes el
  // separador de fecha era un texto fijo ("Hoy") sin importar cuándo eran
  // los mensajes reales — una conversación de la semana pasada mostraba
  // "Hoy" igual.
  String _etiquetaFecha(DateTime d) {
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final dia = DateTime(d.year, d.month, d.day);
    final diff = hoy.difference(dia).inDays;
    if (diff == 0) return 'Hoy';
    if (diff == 1) return 'Ayer';
    return formatearFecha(d, conAnio: d.year != ahora.year);
  }

  Widget _separadorFecha(String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        const SizedBox(width: 16),
        Expanded(child: Divider(color: Colors.grey.shade300, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(child: Divider(color: Colors.grey.shade300, thickness: 1)),
        const SizedBox(width: 16),
      ],
    ),
  );

  Widget _burbujaMensaje(Map<String, dynamic> d) {
    // La regla de qué lado va cada burbuja (y por qué son dos caminos según
    // sea o no autoconsulta) vive en ChatsRepository.esMiBurbuja, con sus
    // tests — acá estaba inline y sin forma de probarla, que es parte de por
    // qué se rompió más de una vez sin que nadie se enterara hasta verlo en
    // el teléfono.
    final isMine = ChatsRepository.esMiBurbuja(
      d,
      miEmisor: _miEmisor,
      esRescatista: widget.esRescatista,
      esAutoconsulta: _esAutoconsulta,
    );
    final text = d['texto'] as String? ?? '';
    final time = d['hora'] as String? ?? '';
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMine ? appOrange : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMine ? 18 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: isMine ? Colors.white : appInk,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              time,
              style: TextStyle(
                fontSize: 10,
                color: isMine
                    ? Colors.white.withValues(alpha: 0.7)
                    : Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _estadoBadge(String label, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
    ),
  );

  Widget _estadoBadgeTipo(String tipo) {
    final esHogar = tipo == 'hogar_de_paso';
    return _estadoBadge(
      esHogar ? '🏡 Hogar de paso' : '🏠 En adopción',
      esHogar ? const Color(0xFFD8F0E4) : const Color(0xFFF9DDD5),
      esHogar ? appTeal : const Color(0xFF8B3A1F),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nombre = widget.animal['nombre'] as String;
    final edad = (widget.animal['edad'] as String?) ?? '';
    // Qué foto va en la tarjeta de arriba la decide el TIPO de chat, no
    // "cuál de los dos campos está presente" — mismo criterio, y mismo
    // motivo, que en adoptante_chats_screen.dart (ver el comentario largo
    // ahí): un `fotoBase64` colado en un chat de animal no debe poder
    // tapar la foto del animalito.
    final esConsultaDeNegocio =
        (widget.animal['tipoSolicitud'] as String? ?? '') == 'consulta_aliado';
    final fotoUrl = esConsultaDeNegocio
        ? null
        : widget.animal['fotoUrl'] as String?;
    final fotoBase64 = esConsultaDeNegocio
        ? widget.animal['fotoBase64'] as String?
        : null;
    final rescatista = (widget.animal['rescatista'] as String?) ?? 'Rescatista';
    final emoji = widget.animal['especie'] == 'Gato' ? '🐱' : '🐶';
    // El encabezado muestra a la CONTRAPARTE: el rescatista chatea con el
    // adoptante y viceversa. Antes mostraba siempre al rescatista, así que
    // el propio rescatista veía su nombre y rótulo en el encabezado, como
    // si hablara consigo mismo.
    final esConsulta = (widget.animal['tipoSolicitud'] as String? ?? '')
        .startsWith('consulta');
    final esAlbergue = esCreadoPorAlbergue(
      widget.animal['creadoPor'] as String?,
    );
    final contraparte = widget.esRescatista
        ? (widget.animal['adoptanteNombre'] as String? ?? 'Adoptante')
        : rescatista;
    // En una consulta, "Negocio aliado" solo es la contraparte para quien
    // CONTACTÓ al negocio. Si quien mira es EL ALIADO (esRescatista: los
    // aliados ocupan el lado rescatistaId, ver ChatsRepository), la
    // contraparte es quien le escribió — y `creadoPor` dice con qué sombrero
    // lo hizo (misma regla que ya usa la bandeja del aliado para su rótulo).
    // Antes decía "Negocio aliado" para los dos lados, así que el aliado veía
    // su propio rol bajo el nombre de su cliente.
    final creadoPor = widget.animal['creadoPor'] as String? ?? '';
    final rotuloContraparte = esConsulta
        ? (widget.esRescatista
              // rotuloDeQuienContacto (data/creator_role.dart) es la única
              // fuente de este rótulo — antes esta misma cadena de
              // condiciones vivía copiada acá Y en aliado_home_screen.dart,
              // las dos pantallas donde el aliado ve la MISMA conversación.
              ? rotuloDeQuienContacto(creadoPor)
              : 'Negocio aliado')
        : widget.esRescatista
        ? 'Adoptante'
        : (esAlbergue ? 'Albergue' : 'Rescatista');

    return Scaffold(
      backgroundColor: appBg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(8, 10, 16, 10),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                    tooltip: 'Volver',
                    onPressed: () => Navigator.pop(context),
                  ),
                  FutureBuilder<(String?, String?)>(
                    future: _fotoContraparte,
                    // esConsulta && !esRescatista: yo contacté al negocio, la
                    // contraparte es el aliado — su logo fijo (widget.animal).
                    // En cualquier otro caso (incluyendo esConsulta && soy el
                    // aliado) se usa lo recién buscado por _cargarFotoContraparte.
                    builder: (context, snap) => AvatarPersona(
                      fotoBase64: (esConsulta && !widget.esRescatista)
                          ? fotoBase64
                          : snap.data?.$1,
                      fotoUrl: (esConsulta && !widget.esRescatista)
                          ? null
                          : snap.data?.$2,
                      inicial: contraparte.isNotEmpty
                          ? contraparte[0].toUpperCase()
                          : '?',
                      radius: 20,
                      backgroundColor: appOrange,
                      textColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // NombreConIndicador (widgets/texto_sin_desborde.dart): esta fila es donde se
                        // encontró el bug la primera vez — un nombre largo empujaba
                        // el puntito de "en línea" fuera de la pantalla. Ahora la
                        // protección vive en el widget compartido, no acá.
                        TextoSinDesborde(
                          texto: contraparte,
                          separacion: 6,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: appInk,
                          ),
                          despues: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF34C759),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          rotuloContraparte,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 36),
                ],
              ),
            ),

            // ── Context card ────────────────────────────────────────────────────
            GestureDetector(
              onTap: () => _abrirFicha(context),
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Builder(
                      builder: (_) {
                        // Un negocio aliado sin logo no es un animal — antes caía en
                        // el mismo fallback que un chat de animal (emoji 🐶/🐱), que
                        // no tiene sentido para una cafetería o veterinaria. Muestra
                        // la inicial del negocio en su lugar, como el resto de las
                        // pantallas de aliado (ver aliado_home_screen.dart).
                        final inicial = nombre.isNotEmpty
                            ? nombre[0].toUpperCase()
                            : '?';
                        final fallback = Container(
                          width: 48,
                          height: 48,
                          color: const Color(0xFFD8F0E4),
                          child: Center(
                            child: esConsulta
                                ? Text(
                                    inicial,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: appTeal,
                                    ),
                                  )
                                : Text(
                                    emoji,
                                    style: const TextStyle(fontSize: 26),
                                  ),
                          ),
                        );
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: fotoUrl != null
                              ? FotoUrl(
                                  url: fotoUrl,
                                  width: 48,
                                  height: 48,
                                  alignment: Alignment.topCenter,
                                  fallback: fallback,
                                )
                              : fotoBase64 != null
                              ? FotoSegura(
                                  base64: fotoBase64,
                                  width: 48,
                                  height: 48,
                                  fallback: fallback,
                                )
                              : fallback,
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (widget.animal['tipoSolicitud'] as String? ?? '') ==
                                    'consulta_aliado'
                                ? 'Conversando con $nombre'
                                : 'Conversando sobre $nombre${edad.isNotEmpty ? " · $edad" : ""}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: appInk,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Builder(
                            builder: (_) {
                              final tipo =
                                  widget.animal['tipoSolicitud'] as String? ??
                                  'adopcion';
                              if (tipo.startsWith('consulta'))
                                return const SizedBox.shrink();
                              if (_rescatistaIdAnimal.isEmpty)
                                return _estadoBadgeTipo(tipo);

                              Widget badgeFor(String? estadoReal) {
                                if (estadoReal == 'Fallecido') {
                                  return _estadoBadge(
                                    '🌈 Falleció',
                                    cicloColor(
                                      'Fallecido',
                                    ).withValues(alpha: 0.12),
                                    cicloColor('Fallecido'),
                                  );
                                }
                                if (estadoReal == 'Adoptado') {
                                  return _estadoBadge(
                                    '✅ Adoptado',
                                    cicloColor(
                                      'Adoptado',
                                    ).withValues(alpha: 0.12),
                                    cicloColor('Adoptado'),
                                  );
                                }
                                return _estadoBadgeTipo(tipo);
                              }

                              // Los dos streams se arman una sola vez en el
                              // State (ver _estadoAnimalPorId/_PorNombre) —
                              // acá solo se elige cuál corresponde.
                              if (_estadoAnimalPorId != null) {
                                return StreamBuilder<
                                  DocumentSnapshot<Map<String, dynamic>>
                                >(
                                  stream: _estadoAnimalPorId,
                                  builder: (_, snap) => badgeFor(
                                    snap.data?.data()?['estadoAdopcion']
                                        as String?,
                                  ),
                                );
                              }
                              return StreamBuilder<QuerySnapshot>(
                                stream: _estadoAnimalPorNombre,
                                builder: (_, snap) {
                                  final docs = snap.data?.docs ?? [];
                                  final estadoReal = docs.isNotEmpty
                                      ? (docs.first.data()
                                                as Map<
                                                  String,
                                                  dynamic
                                                >)['estadoAdopcion']
                                            as String?
                                      : null;
                                  return badgeFor(estadoReal);
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: Color(0xFFCCCCCC),
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),

            // ── Messages (con separador por día real, no fijo en "Hoy") ─────────
            // El FutureBuilder de afuera espera a que el doc del chat exista
            // antes de conectar el listener de mensajes (ver _chatListo).
            Expanded(
              child: FutureBuilder<void>(
                future: _chatListo,
                builder: (context, listo) {
                  if (listo.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(color: appTeal),
                    );
                  }
                  return StreamBuilder<QuerySnapshot>(
                    stream: _chatsRepo.mensajes(_chatId),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(color: appTeal),
                        );
                      }
                      if (snap.hasError) {
                        // Antes un error del listener se veía igual que un chat
                        // vacío ("Sé el primero en escribir") y nadie se enteraba.
                        return Center(
                          child: Text(
                            'No se pudieron cargar los mensajes.\nSalí y volvé a entrar al chat.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        );
                      }
                      final docs = snap.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return Center(
                          child: Text(
                            'Sé el primero en escribir 🐾',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        );
                      }
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!_scrollCtl.hasClients) return;
                        _scrollCtl.jumpTo(_scrollCtl.position.maxScrollExtent);
                        // Segundo salto, un frame después: con burbujas de altura
                        // muy distinta (mensajes cortos mezclados con mensajes
                        // larguísimos), ListView.builder todavía no terminó de
                        // medir todos los items en este primer layout —
                        // maxScrollExtent quedaba corto y el chat abría con el
                        // último mensaje apenas arriba del borde, no visible del
                        // todo, sin scrollear manualmente. Hallazgo real de
                        // Eliza probando el checklist (ítem c6).
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_scrollCtl.hasClients) {
                            _scrollCtl.jumpTo(
                              _scrollCtl.position.maxScrollExtent,
                            );
                          }
                        });
                      });
                      // Etiqueta de separador por índice (o null si va pegado al
                      // mensaje anterior) — solo compara fechas, no construye
                      // ningún widget todavía. Antes esto armaba la lista
                      // COMPLETA de burbujas de una (ListView con `children`), así
                      // que cada mensaje nuevo reconstruía TODA la conversación
                      // desde el principio. Con ListView.builder + este arreglo
                      // liviano, cada burbuja se construye solo cuando entra en
                      // pantalla — importa en chats largos de negociación de
                      // adopción con muchos mensajes de ida y vuelta.
                      final etiquetas = List<String?>.filled(docs.length, null);
                      DateTime? ultimoDia;
                      for (var i = 0; i < docs.length; i++) {
                        final d = docs[i].data() as Map<String, dynamic>;
                        // Mientras el serverTimestamp no confirma (recién enviado,
                        // offline), creadoEn llega null del lado del cliente: se
                        // asume "ahora" para no romper el agrupado.
                        final creadoEn =
                            (d['creadoEn'] as Timestamp?)?.toDate() ??
                            DateTime.now();
                        final dia = DateTime(
                          creadoEn.year,
                          creadoEn.month,
                          creadoEn.day,
                        );
                        if (ultimoDia == null || dia != ultimoDia) {
                          etiquetas[i] = _etiquetaFecha(creadoEn);
                          ultimoDia = dia;
                        }
                      }
                      return ListView.builder(
                        controller: _scrollCtl,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        itemCount: docs.length,
                        itemBuilder: (context, i) {
                          final d = docs[i].data() as Map<String, dynamic>;
                          final etiqueta = etiquetas[i];
                          if (etiqueta == null) return _burbujaMensaje(d);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _separadorFecha(etiqueta),
                              _burbujaMensaje(d),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),

            const SizedBox(height: 8),

            // ── Input bar ───────────────────────────────────────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F4F4),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _msgCtl,
                        textInputAction: TextInputAction.send,
                        onSubmitted: _send,
                        // Ni la app ni la regla de Firestore ponían un tope al
                        // largo de un mensaje — un pegado gigante inflaba el
                        // costo de guardado y rompía el diseño de la burbuja.
                        // maxLength sin counterText visible: no hace falta
                        // mostrar el contador en un chat normal, solo frenarlo
                        // antes de un extremo irreal. Hallazgo de auditoría de
                        // código.
                        maxLength: 2000,
                        decoration: InputDecoration(
                          hintText: 'Escribe un mensaje...',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          counterText: '',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Enviar mensaje',
                    child: GestureDetector(
                      onTap: () => _send(_msgCtl.text),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: appOrange,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
