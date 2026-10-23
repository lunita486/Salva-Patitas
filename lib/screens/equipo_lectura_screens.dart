import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/chats_repository.dart';
import '../data/hogares_de_paso_repository.dart';
import '../domain/reglas_negocio.dart';
import '../routing/app_router.dart';
import '../theme/salva_patitas_theme.dart';
import '../widgets/estado_error_feed.dart';
import '../widgets/sp_widgets.dart';

// Vistas de SOLO LECTURA para una miembro del equipo del albergue. Piden
// exactamente lo que firestore.rules le deja leer:
// - chats: ChatsRepository.delEquipo (del albergue, con sombrero de
//   albergue y tipo del equipo; nunca consultas a negocios aliados, chats
//   personales ni chats viejos sin tipo);
// - mensajes de esos chats;
// - hogares: HogaresDePasoRepository.visiblesParaEquipo (visibleEquipo ==
//   true, que solo pone la responsable con revisarHogarEquipo).
// Ninguna de estas pantallas escribe nada: tampoco marca mensajes como
// leídos, porque el contador "sin leer" es del albergue.

typedef EquipoAlbergueArgs = ({String albergueId, String albergueNombre});
typedef ConversacionEquipoArgs = ({String chatId, String titulo, String adoptanteNombre});

class ChatsDelEquipoScreen extends StatelessWidget {
  const ChatsDelEquipoScreen({super.key, required this.albergueId, required this.albergueNombre, this.repo});
  final String albergueId;
  final String albergueNombre;
  final ChatsRepository? repo;

  static String _tipo(String? t) => switch (t) {
    'hogar_de_paso' => 'Hogar de paso',
    'consulta' => 'Consulta',
    _ => 'Adopción',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    final chats = (repo ?? ChatsRepository()).delEquipo(albergueId).snapshots();
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const SpPawBackground(),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SpScreenHeader(title: 'Chats del albergue', subtitle: albergueNombre),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: chats,
                    builder: (context, snap) {
                      if (snap.hasError) return errorFeedState();
                      if (!snap.hasData) return Center(child: CircularProgressIndicator(color: c.primary));
                      // Sin orderBy en la consulta (pediría un índice
                      // compuesto): se ordena acá, lo más reciente primero.
                      final docs = snap.data!.docs.toList()
                        ..sort((a, b) {
                          final ta = a.data()['ultimoMensajeEn'] as Timestamp?;
                          final tb = b.data()['ultimoMensajeEn'] as Timestamp?;
                          if (ta == null && tb == null) return 0;
                          if (ta == null) return 1;
                          if (tb == null) return -1;
                          return tb.compareTo(ta);
                        });
                      if (docs.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: SpEmpty(
                              title: 'Todavía no hay chats para mostrar',
                              subtitle: 'Acá aparecen los chats de adopción, hogar de paso y consultas del albergue.',
                              animal: SpAnimalKind.gato,
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                        itemCount: docs.length,
                        separatorBuilder: (_, _) => const SizedBox(height: SpSpace.s3),
                        itemBuilder: (_, i) {
                          final d = docs[i].data();
                          final animal = d['animalNombre'] as String? ?? 'Animal';
                          final persona = d['adoptanteNombre'] as String? ?? '';
                          final ultimo = d['ultimoMensaje'] as String? ?? '';
                          return SpCard(
                            key: ValueKey(docs[i].id),
                            padding: const EdgeInsets.all(SpSpace.s3),
                            onTap: () => context.push(
                              AppRoutes.conversacionEquipo,
                              extra: (chatId: docs[i].id, titulo: animal, adoptanteNombre: persona),
                            ),
                            child: Row(
                              children: [
                                const SpBigTile(tone: SpTone.lilac, animal: SpAnimalKind.perro),
                                const SizedBox(width: SpSpace.s3),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        persona.isEmpty ? animal : '$animal · $persona',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: c.ink),
                                      ),
                                      Text(
                                        ultimo.isEmpty ? _tipo(d['tipoSolicitud'] as String?) : ultimo,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: SpText.caption.copyWith(color: c.inkMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SpPill(_tipo(d['tipoSolicitud'] as String?), fondo: c.lilac, tinta: c.lilacInk),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ConversacionEquipoScreen extends StatelessWidget {
  const ConversacionEquipoScreen({
    super.key,
    required this.chatId,
    required this.titulo,
    required this.adoptanteNombre,
    this.repo,
  });
  final String chatId;
  final String titulo;
  final String adoptanteNombre;
  final ChatsRepository? repo;

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    final mensajes = (repo ?? ChatsRepository()).mensajes(chatId);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            SpScreenHeader(title: titulo, subtitle: adoptanteNombre.isEmpty ? null : 'Con $adoptanteNombre'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SpNotice(
                fondo: c.sky,
                tinta: c.skyInk,
                child: const Text('Vista de solo lectura del equipo. Las respuestas las manda la cuenta del albergue.'),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: mensajes,
                builder: (context, snap) {
                  if (snap.hasError) return errorFeedState();
                  if (!snap.hasData) return Center(child: CircularProgressIndicator(color: c.primary));
                  final docs = snap.data!.docs;
                  if (docs.isEmpty) {
                    return Center(
                      child: Text('Todavía no hay mensajes.', style: SpText.label.copyWith(color: c.inkMuted)),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      final m = docs[i].data();
                      // El equipo mira desde el lado del albergue. Misma regla
                      // de "de qué lado va la burbuja" que el chat normal.
                      final delAlbergue = ChatsRepository.esMiBurbuja(
                        m,
                        miEmisor: 'rescatista',
                        esRescatista: true,
                        esAutoconsulta: false,
                      );
                      return _Burbuja(
                        texto: m['texto'] as String? ?? '',
                        hora: m['hora'] as String? ?? '',
                        delAlbergue: delAlbergue,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Burbuja extends StatelessWidget {
  const _Burbuja({required this.texto, required this.hora, required this.delAlbergue});
  final String texto;
  final String hora;
  final bool delAlbergue;

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    return Align(
      alignment: delAlbergue ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
        decoration: BoxDecoration(
          color: delAlbergue ? c.primarySoft : c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(texto, style: TextStyle(fontSize: 15, color: c.ink)),
            if (hora.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(hora, style: SpText.caption.copyWith(color: c.inkMuted)),
            ],
          ],
        ),
      ),
    );
  }
}

class HogaresDelEquipoScreen extends StatelessWidget {
  const HogaresDelEquipoScreen({super.key, required this.albergueId, required this.albergueNombre, this.repo});
  final String albergueId;
  final String albergueNombre;
  final HogaresDePasoRepository? repo;

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    final hogares = (repo ?? HogaresDePasoRepository()).visiblesParaEquipo(albergueId).snapshots();
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const SpPawBackground(),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SpScreenHeader(title: 'Hogares de paso', subtitle: 'Compartidos por $albergueNombre'),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: hogares,
                    builder: (context, snap) {
                      if (snap.hasError) return errorFeedState();
                      if (!snap.hasData) return Center(child: CircularProgressIndicator(color: c.primary));
                      final docs = snap.data!.docs.toList()
                        ..sort((a, b) => ((b.data()['vecesAyudo'] as int?) ?? 0)
                            .compareTo((a.data()['vecesAyudo'] as int?) ?? 0));
                      if (docs.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: SpEmpty(
                              title: 'Todavía no hay hogares compartidos',
                              subtitle: 'La responsable del albergue elige cuáles ve el equipo.',
                              animal: SpAnimalKind.casa,
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                        itemCount: docs.length,
                        separatorBuilder: (_, _) => const SizedBox(height: SpSpace.s3),
                        itemBuilder: (_, i) {
                          final d = docs[i].data();
                          final nombre = d['nombre'] as String? ?? 'Persona sin nombre';
                          final veces = d['vecesAyudo'] as int? ?? 0;
                          final telefono = d['telefono'] as String? ?? '';
                          final notas = d['notas'] as String? ?? '';
                          final link = whatsappUrl(telefono);
                          return SpCard(
                            key: ValueKey(docs[i].id),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(nombre, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: c.ink)),
                                Text(veces == 1 ? 'Ayudó 1 vez' : 'Ayudó $veces veces',
                                    style: SpText.caption.copyWith(color: c.inkMuted, fontWeight: FontWeight.w600)),
                                if (notas.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(notas, style: SpText.label.copyWith(color: c.inkMuted, fontWeight: FontWeight.w500)),
                                ],
                                if (link != null) ...[
                                  const SizedBox(height: 10),
                                  GestureDetector(
                                    onTap: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
                                    child: SpPill('WhatsApp', fondo: c.primarySoft, tinta: c.primaryStrong, icon: Icons.chat_rounded),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
