import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import 'chat_screen.dart';

class AdoptanteChatsScreen extends StatelessWidget {
  final bool esRescatista;
  final bool soloConsultas;
  final bool esAlbergue;
  const AdoptanteChatsScreen({super.key, this.esRescatista = false, this.soloConsultas = false, this.esAlbergue = false});

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
                  if (snap.hasError) return errorFeedState();
                  // Un rescatista/albergue que le escribe a un aliado queda
                  // como adoptanteId en ESE chat (rescatistaId siempre es el
                  // aliado, sin importar quién lo contactó) — así que su
                  // propia pantalla de chats, que filtra por rescatistaId,
                  // nunca encontraba las consultas que él mismo mandó. Se
                  // trae esa segunda tanda acá. El aliado viendo lo que
                  // recibió (soloConsultas) no lo necesita: a él sí lo
                  // encuentra bien la consulta de arriba, siempre es
                  // rescatistaId en sus propios chats.
                  if (esRescatista && !soloConsultas) {
                    return StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('chats')
                          .where('adoptanteId', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
                          .where('tipoSolicitud', isEqualTo: 'consulta_aliado')
                          .snapshots(),
                      builder: (context, snapEnviadas) {
                        // Un chat de consulta a un aliado puede aparecer en
                        // LAS DOS queries a la vez si la propia cuenta es el
                        // aliado (rescatistaId) y también quien lo contactó
                        // (adoptanteId) — pasa de verdad probando con la
                        // misma cuenta en varios roles. Se deduplica por id.
                        final vistos = <String>{};
                        final combinados = <QueryDocumentSnapshot>[
                          for (final d in [...(snap.data?.docs ?? <QueryDocumentSnapshot>[]),
                                            ...(snapEnviadas.data?.docs ?? <QueryDocumentSnapshot>[])])
                            if (vistos.add(d.id)) d,
                        ];
                        return _listaChats(context, combinados);
                      },
                    );
                  }
                  return _listaChats(context, snap.data?.docs ?? []);
                },
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _listaChats(BuildContext context, List<QueryDocumentSnapshot> docsSinFiltrar) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final docs = docsSinFiltrar
        .where((d) {
          final data = d.data() as Map;
          if (((data['ultimoMensaje'] as String?) ?? '').isEmpty) return false;
          final tipo = data['tipoSolicitud'] as String? ?? '';
          if (soloConsultas) {
            return tipo == 'consulta_aliado';
          }
          // 'consulta' (pregunta de un adoptante antes de postular) es un
          // chat normal para el rescatista; 'consulta_aliado' tiene su
          // propia pestaña (soloConsultas) — PERO solo cuando el que mira
          // es el aliado que la recibió. Si en cambio soy quien la mandó
          // (soy adoptanteId en este chat), la quiero ver en mi lista
          // general, porque no tengo otra pantalla donde aparezca.
          if (tipo == 'consulta_aliado') {
            if (data['adoptanteId'] != uid) return false;
            // creadoPor solo se guarda cuando contacté como rescatista o
            // albergue (ver ChatsRepository.asegurarChatNegocio) — si lo
            // contacté como ADOPTANTE, el campo no existe. Antes esto caía
            // en el `?? 'rescatista'` de más abajo (pensado para chats de
            // animal, donde el campo SIEMPRE debería estar) y una consulta
            // mandada como adoptante terminaba mostrándose en la bandeja
            // del rescatista — el bug real que esto arregla.
            final creadoPorConsulta = data['creadoPor'] as String?;
            if (!esRescatista) {
              // Viendo como adoptante: acá van las que mandé CON ESE
              // sombrero (sin creadoPor) — las que mandé como
              // rescatista/albergue pertenecen a esas otras pestañas.
              return creadoPorConsulta == null;
            }
            if (creadoPorConsulta == null) return false;
            return esAlbergue ? creadoPorConsulta == 'albergue' : creadoPorConsulta == 'rescatista';
          }
          // Una misma cuenta puede tener rol rescatista y albergue a la vez;
          // esto evita que se mezclen las conversaciones de un rol con el otro.
          if (esRescatista) {
            final creadoPor = data['creadoPor'] as String? ?? 'rescatista';
            if (esAlbergue) return creadoPor == 'albergue';
            return creadoPor != 'albergue';
          }
          return true;
        })
        .toList()
      ..sort((a, b) {
        final ta = (a.data() as Map)['ultimoMensajeEn'] as Timestamp?;
        final tb = (b.data() as Map)['ultimoMensajeEn'] as Timestamp?;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });
    // Backfill de fotoUrl para chats de animal creados antes de
    // que se guardara (o antes de la migración a Storage — las
    // solicitudes viejas guardaban fotoBase64, así que además
    // se salta si ya tiene cualquiera de los dos campos). Los
    // chats de consulta a un aliado no tienen solicitud
    // asociada, así que este backfill nunca les aplica.
    for (final doc in docs) {
      final dd = doc.data() as Map<String, dynamic>;
      if (dd['fotoUrl'] != null || dd['fotoBase64'] != null) continue;
      final nombre     = dd['animalNombre'] as String? ?? '';
      final adoptanteId = dd['adoptanteId'] as String? ?? '';
      if (nombre.isEmpty || adoptanteId.isEmpty) continue;
      FirebaseFirestore.instance
          .collection('solicitudes')
          .where('adoptanteId', isEqualTo: adoptanteId)
          .where('animalNombre', isEqualTo: nombre)
          .limit(1)
          .get()
          .then((snap) {
        if (snap.docs.isEmpty) return;
        final foto = (snap.docs.first.data())['fotoUrl'] as String?;
        if (foto != null) doc.reference.update({'fotoUrl': foto});
      }).catchError((_) {});
    }

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
        final animalNombre  = d['animalNombre']    as String? ?? 'Animal';
        final rescatista    = d['rescatista']      as String? ?? 'Rescatista';
        // "Soy adoptanteId en ESTE chat" en vez de confiar en el flag de
        // pantalla `esRescatista`: una consulta que YO le mandé a un
        // aliado me deja como adoptanteId aunque esté mirando la lista en
        // modo rescatista (ver comentario más arriba) — si acá se siguiera
        // usando el flag de pantalla, se mostraría mi propio nombre en vez
        // del nombre del aliado, y el chat abriría con el rol invertido.
        final soyAdoptanteAqui = d['adoptanteId'] == uid;
        final nombreMostrar = soyAdoptanteAqui
            ? rescatista
            : (d['adoptanteNombre'] as String? ?? 'Adoptante');
        final ultimoMensaje = d['ultimoMensaje'] as String? ?? '';
        final ultimaHora    = d['ultimaHora']    as String? ?? '';
        final especie        = d['especie']        as String? ?? 'Perro';
        // Un chat de animal tiene fotoUrl (Storage); uno de
        // consulta a un aliado tiene fotoBase64 (su logo,
        // fuera de esta migración) — se revisan los dos.
        final fotoUrl       = d['fotoUrl']       as String?;
        final fotoBase64    = d['fotoBase64']    as String?;
        final tipoSolicitud = d['tipoSolicitud'] as String? ?? 'adopcion';
        final campoBadge    = soyAdoptanteAqui ? 'noLeidosAdoptante' : 'noLeidosRescatista';
        final noLeidos      = (d[campoBadge]    as int?) ?? 0;
        final emoji         = especie == 'Gato' ? '🐱' : '🐶';
        final inicial       = nombreMostrar.isNotEmpty ? nombreMostrar[0].toUpperCase() : 'A';
        final avatarColors  = [appOrange, appTeal, const Color(0xFF7C6FCD), const Color(0xFF4CAF50)];
        final avatarColor   = avatarColors[nombreMostrar.length % avatarColors.length];

        final fotoBytes = bytesFotoSegura(fotoBase64);
        final ImageProvider? fotoProvider = fotoBytes != null
            ? MemoryImage(fotoBytes)
            : fotoUrl != null
                ? NetworkImage(fotoUrl)
                : null;
        // Un negocio aliado sin logo no es un animal — antes caía en el
        // mismo emoji 🐶/🐱 que un chat de animal sin foto, que no tiene
        // sentido para una cafetería o veterinaria.
        final esConsultaRow = tipoSolicitud.startsWith('consulta');
        Widget animalAvatar = fotoProvider != null
            ? CircleAvatar(
                backgroundImage: fotoProvider,
                onBackgroundImageError: (_, _) {},
                radius: 28)
            : CircleAvatar(backgroundColor: appTeal.withOpacity(0.15), radius: 28,
                child: esConsultaRow
                    ? Text(inicial, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: appTeal))
                    : Text(emoji, style: const TextStyle(fontSize: 26)));

        return GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => ChatScreen(
              esRescatista: !soyAdoptanteAqui,
              chatId: docs[i].id,
              animal: {
                'nombre':        animalNombre,
                'rescatista':    rescatista,
                'adoptanteNombre': d['adoptanteNombre'],
                'especie':       especie,
                'tipoSolicitud': tipoSolicitud,
                'rescatistaId':  d['rescatistaId'] as String? ?? '',
                'ubicacion':     '',
                'descripcion':   '',
                'tags':          <String>[],
                'edad':          '',
                'fotoUrl':       fotoUrl,
                'fotoBase64':    fotoBase64,
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
                  Text(nombreMostrar, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(width: 6),
                  Container(width: 8, height: 8,
                      decoration: const BoxDecoration(color: Color(0xFF4CAF50), shape: BoxShape.circle)),
                  const Spacer(),
                  Text(ultimaHora, style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                ]),
                const SizedBox(height: 2),
                Row(children: [
                  Text(tipoSolicitud == 'consulta_aliado' ? 'Con ' : 'Sobre ',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
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
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                      decoration: const BoxDecoration(color: appOrange, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Text(noLeidos > 99 ? '99+' : '$noLeidos',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
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
  }
}
