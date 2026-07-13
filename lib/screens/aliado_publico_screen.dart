import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import '../data/chats_repository.dart';
import 'chat_screen.dart';

class AliadoPublicoScreen extends StatelessWidget {
  final String aliadoId;
  final bool esRescatista;
  final bool esAlbergue;
  const AliadoPublicoScreen({super.key, required this.aliadoId, this.esRescatista = false, this.esAlbergue = false});

  static const _categoriaEmoji = {
    'Baño y peluquería': '🛁',
    'Veterinaria':       '🩺',
    'Tienda':            '🛍️',
    'Adiestramiento':    '🎓',
    'Transporte':        '🚗',
    'Otro':              '🐾',
  };

  Future<void> _contactar(BuildContext context, String nombre, String? fotoBase64) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    String chatId;
    try {
      chatId = await ChatsRepository().asegurarChatNegocio(
        adoptanteId: uid,
        adoptanteNombre: FirebaseAuth.instance.currentUser?.displayName ?? 'Usuario',
        aliadoId: aliadoId,
        aliadoNombre: nombre,
        contexto: !esRescatista ? 'general' : (esAlbergue ? 'albergue' : 'rescatista'),
        fotoBase64: fotoBase64,
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo abrir el chat. Intentá de nuevo.')));
      }
      return;
    }

    if (!context.mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ChatScreen(
        esRescatista: false,
        chatId: chatId,
        animal: {
          'nombre':       nombre,
          'rescatista':   nombre,
          'rescatistaId': aliadoId,
          'fotoBase64':   fotoBase64,
          'tipoSolicitud': 'consulta_aliado',
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('usuarios').doc(aliadoId).snapshots(),
      builder: (context, userSnap) {
        final data     = userSnap.data?.data() as Map<String, dynamic>? ?? {};
        final nombre   = data['aliadoNombre'] as String? ?? 'Aliado';
        final tipo     = data['aliadoTipo']   as String? ?? '';
        final foto     = data['aliadoFotoBase64'] as String?;
        final iniciales = nombre.trim().split(' ')
            .take(2).map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();

        return Scaffold(
          backgroundColor: appBg,
          body: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('servicios')
                .where('aliadoId', isEqualTo: aliadoId)
                .snapshots(),
            builder: (context, svcSnap) {
              final servicios = (svcSnap.data?.docs ?? [])
                  .where((d) => (d.data() as Map)['activo'] == true)
                  .toList();

              return CustomScrollView(
                slivers: [
                  // Header
                  SliverToBoxAdapter(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(20, 56, 20, 28),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF0A5C40), Color(0xFF1F8A62)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Column(children: [
                        Builder(builder: (_) {
                          final fotoBytes = bytesFotoSegura(foto);
                          return CircleAvatar(
                            radius: 44,
                            backgroundColor: Colors.white.withValues(alpha: 0.2),
                            backgroundImage: fotoBytes != null ? MemoryImage(fotoBytes) : null,
                            onBackgroundImageError: fotoBytes != null ? (_, __) {} : null,
                            child: fotoBytes == null
                                ? Text(iniciales, style: const TextStyle(
                                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24))
                                : null,
                          );
                        }),
                        const SizedBox(height: 12),
                        Text(nombre, style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                        if (tipo.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(tipo, style: TextStyle(
                              fontSize: 13, color: Colors.white.withValues(alpha: 0.8))),
                        ],
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _contactar(context, nombre, foto),
                            icon: const Icon(Icons.chat_bubble_outline, size: 18),
                            label: const Text('Contactar',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: appTeal,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),

                  // Back button overlay
                  SliverToBoxAdapter(child: const SizedBox.shrink()),

                  // Servicios
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                      child: Text(
                        servicios.isEmpty ? 'Sin servicios publicados' : 'SERVICIOS DISPONIBLES',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                            letterSpacing: 1.2, color: Colors.grey.shade500),
                      ),
                    ),
                  ),

                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) {
                          final d      = servicios[i].data() as Map<String, dynamic>;
                          final sNombre = d['nombre']      as String? ?? '';
                          final precio  = d['precio']      as int?    ?? 0;
                          final desc    = d['descripcion'] as String? ?? '';
                          final cat     = d['categoria']   as String? ?? '';
                          final emoji   = _categoriaEmoji[cat] ?? '🐾';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 8, offset: const Offset(0, 2))],
                            ),
                            child: Row(children: [
                              Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  color: appTeal.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(child: Text(emoji,
                                    style: const TextStyle(fontSize: 22))),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(sNombre, style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700,
                                    color: Color(0xFF1A1A1A))),
                                if (desc.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(desc, style: TextStyle(fontSize: 12,
                                      color: Colors.grey.shade500),
                                      maxLines: 2, overflow: TextOverflow.ellipsis),
                                ],
                              ])),
                              const SizedBox(width: 8),
                              Text('\$${_fmt(precio)}',
                                  style: const TextStyle(fontSize: 16,
                                      fontWeight: FontWeight.bold, color: appTeal)),
                            ]),
                          );
                        },
                        childCount: servicios.length,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          // Back button
          floatingActionButtonLocation: FloatingActionButtonLocation.miniStartTop,
          floatingActionButton: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: FloatingActionButton.small(
                heroTag: 'back',
                onPressed: () => Navigator.pop(context),
                backgroundColor: Colors.white,
                foregroundColor: appTeal,
                elevation: 2,
                child: const Icon(Icons.arrow_back_ios_new, size: 16),
              ),
            ),
          ),
        );
      },
    );
  }

  String _fmt(int precio) {
    final s = precio.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
