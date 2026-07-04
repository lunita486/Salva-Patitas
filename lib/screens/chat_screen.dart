import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import '../theme.dart';

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

  @override
  void initState() {
    super.initState();
    if (widget.chatId != null) {
      // Chat existente: usa el ID real del documento de Firestore
      _chatId = widget.chatId!;
    } else {
      // Chat nuevo iniciado desde el feed: ID derivado de nombre + rescatista
      final nombre     = (widget.animal['nombre'] as String)
          .toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
      final rescatista = ((widget.animal['rescatista'] as String?) ?? 'rescatista')
          .toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
      _chatId = '${nombre}_$rescatista';
      // Solo el adoptante crea/actualiza el doc del chat al iniciar desde el feed
      if (!widget.esRescatista) {
        FirebaseFirestore.instance.collection('chats').doc(_chatId).set({
          'animalNombre':  widget.animal['nombre'],
          'rescatista':    widget.animal['rescatista'] ?? 'Rescatista',
          'rescatistaId':  widget.animal['rescatistaId'] ?? '',
          'adoptanteId':     FirebaseAuth.instance.currentUser?.uid ?? '',
          'adoptanteNombre': FirebaseAuth.instance.currentUser?.displayName ?? 'Adoptante',
          'especie':         widget.animal['especie'] ?? 'Perro',
          'fotoBase64':    widget.animal['fotoBase64'],
          'ultimoMensaje': '',
          'creadoEn':      FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }
    _mensajesRef = FirebaseFirestore.instance
        .collection('chats').doc(_chatId).collection('mensajes');
    // Resetea los no leídos del rol que abre el chat
    final campo = widget.esRescatista ? 'noLeidosRescatista' : 'noLeidosAdoptante';
    FirebaseFirestore.instance.collection('chats').doc(_chatId)
        .update({campo: 0}).catchError((_) {});
  }

  String _nowTime() {
    final n = DateTime.now();
    return '${n.hour}:${n.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _msgCtl.clear();
    await _mensajesRef.add({
      'texto':    trimmed,
      'emisor':   widget.esRescatista ? 'rescatista' : 'adoptante',
      'hora':     _nowTime(),
      'creadoEn': FieldValue.serverTimestamp(),
    });
    final campoDestinatario = widget.esRescatista ? 'noLeidosAdoptante' : 'noLeidosRescatista';
    await FirebaseFirestore.instance.collection('chats').doc(_chatId).update({
      'ultimoMensaje':    trimmed,
      'ultimaHora':       _nowTime(),
      'ultimoMensajeEn':  FieldValue.serverTimestamp(),
      campoDestinatario:  FieldValue.increment(1),
    });
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

  @override
  Widget build(BuildContext context) {
    final nombre      = widget.animal['nombre']     as String;
    final edad        = (widget.animal['edad'] as String?) ?? '';
    final fotoBase64  = widget.animal['fotoBase64'] as String?;
    final rescatista  = (widget.animal['rescatista'] as String?) ?? 'Rescatista';
    final emoji       = widget.animal['especie'] == 'Gato' ? '🐱' : '🐶';

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
              CircleAvatar(
                radius: 20, backgroundColor: appOrange,
                child: Text(rescatista.isNotEmpty ? rescatista[0].toUpperCase() : 'R',
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(rescatista,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                  const SizedBox(width: 6),
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(color: Color(0xFF34C759), shape: BoxShape.circle),
                  ),
                ]),
                const SizedBox(height: 1),
                Text(
                  (widget.animal['tipoSolicitud'] as String? ?? '').startsWith('consulta')
                      ? 'Negocio aliado'
                      : 'Rescatista',
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
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: fotoBase64 != null
                  ? Image.memory(base64Decode(fotoBase64), width: 48, height: 48, fit: BoxFit.cover)
                  : Container(
                      width: 48, height: 48, color: const Color(0xFFD8F0E4),
                      child: Center(child: Text(emoji, style: const TextStyle(fontSize: 26)))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  'Conversando sobre $nombre${edad.isNotEmpty ? " · $edad" : ""}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A)),
                ),
                const SizedBox(height: 4),
                Builder(builder: (_) {
                  final tipo = widget.animal['tipoSolicitud'] as String? ?? 'adopcion';
                  if (tipo.startsWith('consulta')) return const SizedBox.shrink();
                  final esHogar = tipo == 'hogar_de_paso';
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: esHogar ? const Color(0xFFD8F0E4) : const Color(0xFFF9DDD5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      esHogar ? '🏡 Hogar de paso' : '🏠 En adopción',
                      style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600,
                        color: esHogar ? const Color(0xFF1F8A62) : const Color(0xFF8B3A1F),
                      ),
                    ),
                  );
                }),
              ])),
              const Icon(Icons.chevron_right, color: Color(0xFFCCCCCC), size: 20),
            ]),
          ),

          // ── Date separator ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              const SizedBox(width: 16),
              Expanded(child: Divider(color: Colors.grey.shade300, thickness: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('Hoy', style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
              ),
              Expanded(child: Divider(color: Colors.grey.shade300, thickness: 1)),
              const SizedBox(width: 16),
            ]),
          ),

          // ── Messages ────────────────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _mensajesRef.orderBy('creadoEn').snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: appTeal));
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
                return ListView.builder(
                  controller: _scrollCtl,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final d      = docs[i].data() as Map<String, dynamic>;
                    final isMine = widget.esRescatista
                        ? d['emisor'] == 'rescatista'
                        : d['emisor'] == 'adoptante';
                    final text   = d['texto'] as String? ?? '';
                    final time   = d['hora']  as String? ?? '';
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
