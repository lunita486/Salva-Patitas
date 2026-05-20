import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import '../theme.dart';
import 'chat_screen.dart';

class AdoptanteChatsScreen extends StatelessWidget {
  final bool esRescatista;
  const AdoptanteChatsScreen({super.key, this.esRescatista = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appBg,
      body: Stack(fit: StackFit.expand, children: [
        const LeafOverlay(),
        SafeArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.arrow_back_ios_new, size: 20, color: Color(0xFF1A1A1A)),
                ),
                const SizedBox(width: 12),
                const Text('Conversaciones', style: TextStyle(fontSize: 20,
                    fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
              ]),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('chats')
                    .where(esRescatista ? 'rescatistaId' : 'adoptanteId',
                           isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: appTeal));
                  }
                  final docs = (snap.data?.docs ?? [])
                      .where((d) => ((d.data() as Map)['ultimoMensaje'] as String? ?? '').isNotEmpty)
                      .toList()
                      ..sort((a, b) {
                        final ta = (a.data() as Map)['ultimoMensajeEn'] as Timestamp?;
                        final tb = (b.data() as Map)['ultimoMensajeEn'] as Timestamp?;
                        if (ta == null && tb == null) return 0;
                        if (ta == null) return 1;
                        if (tb == null) return -1;
                        return tb.compareTo(ta);
                      });
                  if (docs.isEmpty) {
                    return Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text('Aún no tienes conversaciones',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            esRescatista
                                ? 'Cuando un adoptante inicie un chat sobre uno de tus animales, aparecerá aquí'
                                : 'Cuando te interese un animal, toca "Chatear" para iniciar una conversación',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ]),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      final d             = docs[i].data() as Map<String, dynamic>;
                      final animalNombre  = d['animalNombre']  as String? ?? 'Animal';
                      final rescatista    = d['rescatista']    as String? ?? 'Rescatista';
                      final ultimoMensaje = d['ultimoMensaje'] as String? ?? '';
                      final ultimaHora    = d['ultimaHora']    as String? ?? '';
                      final especie       = d['especie']       as String? ?? 'Perro';
                      final fotoBase64    = d['fotoBase64']    as String?;
                      final campoBadge    = esRescatista ? 'noLeidosRescatista' : 'noLeidosAdoptante';
                      final noLeidos      = (d[campoBadge]    as int?) ?? 0;
                      final emoji         = especie == 'Gato' ? '🐱' : '🐶';
                      final inicial       = rescatista.isNotEmpty ? rescatista[0].toUpperCase() : 'R';
                      final avatarColors  = [appOrange, appTeal, const Color(0xFF7C6FCD), const Color(0xFF4CAF50)];
                      final avatarColor   = avatarColors[rescatista.length % avatarColors.length];

                      Widget animalAvatar = fotoBase64 != null
                          ? CircleAvatar(backgroundImage: MemoryImage(base64Decode(fotoBase64)), radius: 28)
                          : CircleAvatar(backgroundColor: appTeal.withOpacity(0.15), radius: 28,
                              child: Text(emoji, style: const TextStyle(fontSize: 26)));

                      return GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            esRescatista: esRescatista,
                            chatId: docs[i].id,
                            animal: {
                              'nombre':      animalNombre,
                              'rescatista':  rescatista,
                              'especie':     especie,
                              'ubicacion':   '',
                              'descripcion': '',
                              'tags':        <String>[],
                              'edad':        '',
                              'fotoBase64':  fotoBase64,
                            }),
                        )),
                        child: Container(
                          color: Colors.white.withOpacity(noLeidos > 0 ? 0.7 : 0.4),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          child: Row(children: [
                            Stack(clipBehavior: Clip.none, children: [
                              animalAvatar,
                              Positioned(
                                bottom: -2, left: -4,
                                child: CircleAvatar(
                                  radius: 12, backgroundColor: avatarColor,
                                  child: Text(inicial, style: const TextStyle(fontSize: 10,
                                      color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ]),
                            const SizedBox(width: 14),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Text(rescatista, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                const SizedBox(width: 6),
                                Container(width: 8, height: 8,
                                    decoration: const BoxDecoration(color: Color(0xFF4CAF50), shape: BoxShape.circle)),
                                const Spacer(),
                                Text(ultimaHora, style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                              ]),
                              const SizedBox(height: 2),
                              Row(children: [
                                Text('Sobre ', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                                Text(animalNombre, style: TextStyle(fontSize: 13,
                                    fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                              ]),
                              const SizedBox(height: 3),
                              Row(children: [
                                Expanded(
                                  child: Text(ultimoMensaje.isNotEmpty ? ultimoMensaje : 'Inicia la conversación',
                                      style: TextStyle(fontSize: 13,
                                          color: noLeidos > 0 ? const Color(0xFF1A1A1A) : Colors.grey.shade500,
                                          fontWeight: noLeidos > 0 ? FontWeight.w600 : FontWeight.normal),
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                ),
                                if (noLeidos > 0) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 20, height: 20,
                                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                    alignment: Alignment.center,
                                    child: Text('$noLeidos', style: const TextStyle(
                                        fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ]),
                            ])),
                          ]),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
