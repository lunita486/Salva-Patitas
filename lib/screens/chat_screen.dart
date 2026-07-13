import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import '../data/chats_repository.dart';

class ChatScreen extends StatefulWidget {
  final Map<String, dynamic> animal;
  final bool esRescatista;
  final String? chatId;
  const ChatScreen({super.key, required this.animal, this.esRescatista = false, this.chatId});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgCtl    = TextEditingController();
  final _scrollCtl = ScrollController();
  late final String _chatId;
  late final CollectionReference _mensajesRef;
  // Se completa cuando el doc del chat ya existe en Firestore. El listener
  // de mensajes recién se conecta después de esto: las reglas de mensajes
  // verifican participante contra el doc del chat, y si el listener se
  // conecta ANTES de que el doc exista, Firestore lo rechaza y lo mata para
  // siempre (no reintenta) — los mensajes no aparecían hasta salir y volver
  // a entrar al chat.
  late final Future<void> _chatListo;
  // Foto de perfil de la CONTRAPARTE (no la propia). Se resuelve leyendo el
  // doc del chat (que siempre tiene adoptanteId/rescatistaId, sin importar
  // qué pantalla haya abierto este ChatScreen) y de ahí el campo `foto` de
  // usuarios/{id} — así no depende de que cada sitio de navegación pase la
  // foto de la otra persona en el mapa `animal`.
  late final Future<String?> _fotoContraparte;

  Future<String?> _cargarFotoContraparte() async {
    final esConsulta = (widget.animal['tipoSolicitud'] as String? ?? '').startsWith('consulta');
    if (esConsulta) return null;
    try {
      await _chatListo;
      final chatDoc = await FirebaseFirestore.instance.collection('chats').doc(_chatId).get();
      final d = chatDoc.data();
      if (d == null) return null;
      final contraparteId = widget.esRescatista
          ? (d['adoptanteId'] as String? ?? '')
          : (d['rescatistaId'] as String? ?? '');
      if (contraparteId.isEmpty) return null;
      final userDoc = await FirebaseFirestore.instance.collection('usuarios').doc(contraparteId).get();
      return userDoc.data()?['foto'] as String?;
    } catch (_) {
      return null;
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
      if (rescateId != null && rescateId.isNotEmpty && adoptanteUid.isNotEmpty) {
        // Mismo esquema de id que usan todas las pantallas (ChatsRepository),
        // así dos animales con el mismo nombre nunca comparten conversación.
        _chatId = ChatsRepository().idAnimal(rescateId: rescateId, adoptanteId: adoptanteUid);
        // Se asegura el documento exista sin importar qué lado lo abre
        // primero. Antes solo lo creaba el adoptante: si el rescatista
        // entraba primero a un chat que todavía no existía y escribía, el
        // mensaje se guardaba pero la actualización del chat fallaba (el
        // documento no existía) — la app avisaba "no se pudo enviar" pero el
        // mensaje ya había quedado guardado, y si reintentaba quedaba duplicado.
        _chatListo = ChatsRepository().asegurarChatAnimal(
          adoptanteId: adoptanteUid,
          adoptanteNombre: widget.esRescatista
              ? (widget.animal['adoptanteNombre'] as String? ?? 'Adoptante')
              : (FirebaseAuth.instance.currentUser?.displayName ?? 'Adoptante'),
          rescateId: rescateId,
          rescatistaId: widget.animal['rescatistaId'] as String? ?? '',
          rescatista: widget.animal['rescatista'] as String? ?? 'Rescatista',
          creadoPor: widget.animal['creadoPor'] as String? ?? 'rescatista',
          animalNombre: widget.animal['nombre'] as String?,
          especie: widget.animal['especie'] as String?,
          fotoUrl: widget.animal['fotoUrl'] as String?,
        ).catchError((_) => '');
      } else {
        // Animal sin rescateId, o sin saber quién es el adoptante (dato
        // legado): se mantiene el esquema anterior.
        final nombre     = (widget.animal['nombre'] as String? ?? '')
            .toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
        final rescatista = ((widget.animal['rescatista'] as String?) ?? 'rescatista')
            .toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
        _chatId = '${nombre}_$rescatista';
        // Solo el adoptante crea/actualiza el doc del chat en este esquema
        // legado, porque es el único lado del que tenemos datos confiables.
        if (!widget.esRescatista) {
          _chatListo = FirebaseFirestore.instance.collection('chats').doc(_chatId).set({
            'animalNombre':  widget.animal['nombre'],
            'rescateId':     rescateId ?? '',
            'creadoPor':     widget.animal['creadoPor'] ?? 'rescatista',
            'rescatista':    widget.animal['rescatista'] ?? 'Rescatista',
            'rescatistaId':  widget.animal['rescatistaId'] ?? '',
            'adoptanteId':     propioUid,
            'adoptanteNombre': FirebaseAuth.instance.currentUser?.displayName ?? 'Adoptante',
            'especie':         widget.animal['especie'] ?? 'Perro',
            'fotoUrl':       widget.animal['fotoUrl'],
            'ultimoMensaje': '',
            'creadoEn':      FieldValue.serverTimestamp(),
          }, SetOptions(merge: true)).catchError((_) {});
        } else {
          _chatListo = Future.value();
        }
      }
    }
    _mensajesRef = FirebaseFirestore.instance
        .collection('chats').doc(_chatId).collection('mensajes');
    _fotoContraparte = _cargarFotoContraparte();
    // Resetea los no leídos del rol que abre el chat — después de que el
    // doc exista, para no hacer un update sobre un doc que todavía no está.
    _chatListo.whenComplete(() {
      final campo = widget.esRescatista ? 'noLeidosRescatista' : 'noLeidosAdoptante';
      FirebaseFirestore.instance.collection('chats').doc(_chatId)
          .update({campo: 0}).catchError((_) {});
    });
  }

  String _nowTime() {
    final n = DateTime.now();
    return '${n.hour}:${n.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _msgCtl.clear();
    try {
      // El doc del chat se actualiza ANTES de agregar el mensaje, y con
      // set(merge:true) en vez de update() — así, si el chat todavía no
      // existía (por ejemplo el otro lado nunca llegó a crearlo), esta
      // escritura lo crea en vez de fallar con "no encontrado". Si el
      // mensaje se agregara primero y esta escritura fallara después, el
      // mensaje quedaría guardado igual aunque la app avisara error, y un
      // reintento lo duplicaría.
      final campoDestinatario = widget.esRescatista ? 'noLeidosAdoptante' : 'noLeidosRescatista';
      await FirebaseFirestore.instance.collection('chats').doc(_chatId).set({
        'ultimoMensaje':    trimmed,
        'ultimaHora':       _nowTime(),
        'ultimoMensajeEn':  FieldValue.serverTimestamp(),
        campoDestinatario:  FieldValue.increment(1),
      }, SetOptions(merge: true));
      await _mensajesRef.add({
        'texto':    trimmed,
        'emisor':   widget.esRescatista ? 'rescatista' : 'adoptante',
        'hora':     _nowTime(),
        'creadoEn': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (!mounted) return;
      _msgCtl.text = trimmed;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo enviar el mensaje. Intentá de nuevo.')));
      return;
    }
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtl.hasClients) {
        _scrollCtl.animateTo(_scrollCtl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    _msgCtl.dispose();
    _scrollCtl.dispose();
    super.dispose();
  }

  // 'Hoy'/'Ayer'/'3 jul' según qué tan lejos esté [d] de hoy. Antes el
  // separador de fecha era un texto fijo ("Hoy") sin importar cuándo eran
  // los mensajes reales — una conversación de la semana pasada mostraba
  // "Hoy" igual.
  String _etiquetaFecha(DateTime d) {
    final ahora = DateTime.now();
    final hoy   = DateTime(ahora.year, ahora.month, ahora.day);
    final dia   = DateTime(d.year, d.month, d.day);
    final diff  = hoy.difference(dia).inDays;
    if (diff == 0) return 'Hoy';
    if (diff == 1) return 'Ayer';
    const meses = ['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'];
    final anio = d.year != ahora.year ? ' ${d.year}' : '';
    return '${d.day} ${meses[d.month - 1]}$anio';
  }

  Widget _separadorFecha(String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          const SizedBox(width: 16),
          Expanded(child: Divider(color: Colors.grey.shade300, thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
          ),
          Expanded(child: Divider(color: Colors.grey.shade300, thickness: 1)),
          const SizedBox(width: 16),
        ]),
      );

  Widget _burbujaMensaje(Map<String, dynamic> d) {
    final isMine = widget.esRescatista
        ? d['emisor'] == 'rescatista'
        : d['emisor'] == 'adoptante';
    final text = d['texto'] as String? ?? '';
    final time = d['hora'] as String? ?? '';
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMine ? appOrange : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft:     const Radius.circular(18),
            topRight:    const Radius.circular(18),
            bottomLeft:  Radius.circular(isMine ? 18 : 4),
            bottomRight: Radius.circular(isMine ? 4  : 18),
          ),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(text,
                style: TextStyle(
                    fontSize: 14,
                    color: isMine ? Colors.white : const Color(0xFF1A1A1A),
                    height: 1.4)),
            const SizedBox(height: 4),
            Text(time,
                style: TextStyle(
                    fontSize: 10,
                    color: isMine ? Colors.white.withOpacity(0.7) : Colors.grey.shade400)),
          ],
        ),
      ),
    );
  }

  Widget _estadoBadge(String label, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
      );

  Widget _estadoBadgeTipo(String tipo) {
    final esHogar = tipo == 'hogar_de_paso';
    return _estadoBadge(
      esHogar ? '🏡 Hogar de paso' : '🏠 En adopción',
      esHogar ? const Color(0xFFD8F0E4) : const Color(0xFFF9DDD5),
      esHogar ? const Color(0xFF1F8A62) : const Color(0xFF8B3A1F),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nombre      = widget.animal['nombre']     as String;
    final edad        = (widget.animal['edad'] as String?) ?? '';
    // El chat puede ser sobre un animal (fotoUrl, en Storage) o una consulta
    // a un negocio aliado (fotoBase64, el logo propio del aliado — fuera de
    // alcance de esta migración). Se revisan los dos, el que haya presente.
    final fotoUrl     = widget.animal['fotoUrl']    as String?;
    final fotoBase64  = widget.animal['fotoBase64'] as String?;
    final rescatista  = (widget.animal['rescatista'] as String?) ?? 'Rescatista';
    final emoji       = widget.animal['especie'] == 'Gato' ? '🐱' : '🐶';
    // El encabezado muestra a la CONTRAPARTE: el rescatista chatea con el
    // adoptante y viceversa. Antes mostraba siempre al rescatista, así que
    // el propio rescatista veía su nombre y rótulo en el encabezado, como
    // si hablara consigo mismo.
    final esConsulta  = (widget.animal['tipoSolicitud'] as String? ?? '').startsWith('consulta');
    final esAlbergue  = (widget.animal['creadoPor'] as String? ?? '') == 'albergue';
    final contraparte = widget.esRescatista
        ? (widget.animal['adoptanteNombre'] as String? ?? 'Adoptante')
        : rescatista;
    final rotuloContraparte = esConsulta
        ? 'Negocio aliado'
        : widget.esRescatista ? 'Adoptante' : (esAlbergue ? 'Albergue' : 'Rescatista');

    return Scaffold(
      backgroundColor: appBg,
      body: SafeArea(
        child: Column(children: [
          // ── Header ─────────────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(8, 10, 16, 10),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              FutureBuilder<String?>(
                future: _fotoContraparte,
                builder: (context, snap) => AvatarPersona(
                  fotoBase64: esConsulta ? fotoBase64 : null,
                  fotoUrl: esConsulta ? null : snap.data,
                  inicial: contraparte.isNotEmpty ? contraparte[0].toUpperCase() : '?',
                  radius: 20,
                  backgroundColor: appOrange,
                  textColor: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(contraparte,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                  const SizedBox(width: 6),
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(color: Color(0xFF34C759), shape: BoxShape.circle),
                  ),
                ]),
                const SizedBox(height: 1),
                Text(
                  rotuloContraparte,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ])),
              const SizedBox(width: 36),
            ]),
          ),

          // ── Context card ────────────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Row(children: [
              Builder(builder: (_) {
                // Un negocio aliado sin logo no es un animal — antes caía en
                // el mismo fallback que un chat de animal (emoji 🐶/🐱), que
                // no tiene sentido para una cafetería o veterinaria. Muestra
                // la inicial del negocio en su lugar, como el resto de las
                // pantallas de aliado (ver aliado_home_screen.dart).
                final inicial = nombre.isNotEmpty ? nombre[0].toUpperCase() : '?';
                final fallback = Container(
                    width: 48, height: 48, color: const Color(0xFFD8F0E4),
                    child: Center(child: esConsulta
                        ? Text(inicial, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: appTeal))
                        : Text(emoji, style: const TextStyle(fontSize: 26))));
                return ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: fotoUrl != null
                    ? FotoUrl(url: fotoUrl, width: 48, height: 48, fallback: fallback)
                    : fotoBase64 != null
                      ? FotoSegura(base64: fotoBase64, width: 48, height: 48, fallback: fallback)
                      : fallback,
                );
              }),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  (widget.animal['tipoSolicitud'] as String? ?? '') == 'consulta_aliado'
                      ? 'Conversando con $nombre'
                      : 'Conversando sobre $nombre${edad.isNotEmpty ? " · $edad" : ""}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A)),
                ),
                const SizedBox(height: 4),
                Builder(builder: (_) {
                  final tipo = widget.animal['tipoSolicitud'] as String? ?? 'adopcion';
                  if (tipo.startsWith('consulta')) return const SizedBox.shrink();
                  final rescatistaId = widget.animal['rescatistaId'] as String? ?? '';
                  final rescateId = widget.animal['rescateId'] as String? ?? '';
                  if (rescatistaId.isEmpty) return _estadoBadgeTipo(tipo);

                  Widget badgeFor(String? estadoReal) {
                    if (estadoReal == 'Fallecido') {
                      return _estadoBadge('🌈 Falleció',
                          cicloColor('Fallecido').withValues(alpha: 0.12), cicloColor('Fallecido'));
                    }
                    if (estadoReal == 'Adoptado') {
                      return _estadoBadge('✅ Adoptado',
                          cicloColor('Adoptado').withValues(alpha: 0.12), cicloColor('Adoptado'));
                    }
                    return _estadoBadgeTipo(tipo);
                  }

                  // Con rescateId se busca el documento exacto (sin ambigüedad
                  // posible); sin él, se cae al buscar por nombre + rescatistaId
                  // como antes (puede confundirse si hay 2 animales con el
                  // mismo nombre bajo la misma cuenta en distinto rol).
                  if (rescateId.isNotEmpty) {
                    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance.collection('rescates')
                          .doc(rescateId).snapshots(),
                      builder: (_, snap) => badgeFor(snap.data?.data()?['estadoAdopcion'] as String?),
                    );
                  }
                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('rescates')
                        .where('rescatistaId', isEqualTo: rescatistaId)
                        .where('nombre', isEqualTo: nombre)
                        .limit(1).snapshots(),
                    builder: (_, snap) {
                      final docs = snap.data?.docs ?? [];
                      final estadoReal = docs.isNotEmpty
                          ? (docs.first.data() as Map<String, dynamic>)['estadoAdopcion'] as String?
                          : null;
                      return badgeFor(estadoReal);
                    },
                  );
                }),
              ])),
              const Icon(Icons.chevron_right, color: Color(0xFFCCCCCC), size: 20),
            ]),
          ),

          // ── Messages (con separador por día real, no fijo en "Hoy") ─────────
          // El FutureBuilder de afuera espera a que el doc del chat exista
          // antes de conectar el listener de mensajes (ver _chatListo).
          Expanded(
            child: FutureBuilder<void>(
              future: _chatListo,
              builder: (context, listo) {
                if (listo.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator(color: appTeal));
                }
                return StreamBuilder<QuerySnapshot>(
              stream: _mensajesRef.orderBy('creadoEn').snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: appTeal));
                }
                if (snap.hasError) {
                  // Antes un error del listener se veía igual que un chat
                  // vacío ("Sé el primero en escribir") y nadie se enteraba.
                  return Center(
                    child: Text('No se pudieron cargar los mensajes.\nSalí y volvé a entrar al chat.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                  );
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Text('Sé el primero en escribir 🐾',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                  );
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollCtl.hasClients) {
                    _scrollCtl.jumpTo(_scrollCtl.position.maxScrollExtent);
                  }
                });
                final items = <Widget>[];
                DateTime? ultimoDia;
                for (final doc in docs) {
                  final d = doc.data() as Map<String, dynamic>;
                  // Mientras el serverTimestamp no confirma (recién enviado,
                  // offline), creadoEn llega null del lado del cliente: se
                  // asume "ahora" para no romper el agrupado.
                  final creadoEn = (d['creadoEn'] as Timestamp?)?.toDate() ?? DateTime.now();
                  final dia = DateTime(creadoEn.year, creadoEn.month, creadoEn.day);
                  if (ultimoDia == null || dia != ultimoDia) {
                    items.add(_separadorFecha(_etiquetaFecha(creadoEn)));
                    ultimoDia = dia;
                  }
                  items.add(_burbujaMensaje(d));
                }
                return ListView(
                  controller: _scrollCtl,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  children: items,
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
            child: Row(children: [
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
                    decoration: InputDecoration(
                      hintText: 'Escribe un mensaje...',
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _send(_msgCtl.text),
                child: Container(
                  width: 44, height: 44,
                  decoration: const BoxDecoration(color: appOrange, shape: BoxShape.circle),
                  child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

}
