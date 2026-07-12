import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import '../compatibilidad.dart';
import '../data/creator_role.dart';
import '../data/solicitudes_repository.dart';
import '../data/rescates_repository.dart';
import '../data/chats_repository.dart';
import 'chat_screen.dart';

// ── Funciones top-level reutilizables por home_screen y solicitudes_screen ──

Future<bool> enviarMensajeChat(String adoptanteId, String animalNombre, String texto,
    {String? fotoUrl, String? adoptanteNombre, String? tipoSolicitud, String? rescateId,
     String? creadoPor, String? especie}) async {
  try {
    final rescatistaId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final n    = DateTime.now();
    final hora = '${n.hour}:${n.minute.toString().padLeft(2, '0')}';

    // Con rescateId se apunta directo al chat de ese animal puntual (id determinístico
    // animal+adoptante); sin él (dato legado) se cae al viejo match por nombre.
    DocumentReference<Map<String, dynamic>> chatRef;
    DocumentSnapshot<Map<String, dynamic>>? existing;
    if (rescateId != null && rescateId.isNotEmpty) {
      chatRef = FirebaseFirestore.instance.collection('chats')
          .doc(ChatsRepository().idAnimal(rescateId: rescateId, adoptanteId: adoptanteId));
      final snap = await chatRef.get();
      if (snap.exists) existing = snap;
    } else {
      final chats = await FirebaseFirestore.instance.collection('chats')
          .where('adoptanteId', isEqualTo: adoptanteId)
          .where('animalNombre', isEqualTo: animalNombre)
          .limit(1).get();
      if (chats.docs.isNotEmpty) {
        existing = chats.docs.first;
        chatRef = existing.reference;
      } else {
        chatRef = FirebaseFirestore.instance.collection('chats').doc();
      }
    }

    final userDoc = await FirebaseFirestore.instance.collection('usuarios').doc(rescatistaId).get();
    final userData = userDoc.data() ?? {};
    final rescatistaNombre =
        (userData['albergueNombre'] as String?)?.isNotEmpty == true
            ? userData['albergueNombre'] as String
            : (userData['nombre'] as String?)?.isNotEmpty == true
                ? userData['nombre'] as String
                : FirebaseAuth.instance.currentUser?.displayName ?? 'Rescatista';

    if (existing == null) {
      if (rescateId != null && rescateId.isNotEmpty) {
        // Mismo método que usa el resto de la app para crear un chat de
        // animal, así los campos (creadoPor, especie, etc.) no divergen
        // entre quién crea el chat primero. Todo en una sola escritura
        // (via `extra`) para que no pueda quedar un chat a medio crear si
        // la app se cierra justo entre pasos.
        await ChatsRepository().asegurarChatAnimal(
          adoptanteId: adoptanteId,
          adoptanteNombre: adoptanteNombre ?? 'Adoptante',
          rescateId: rescateId,
          rescatistaId: rescatistaId,
          rescatista: rescatistaNombre,
          creadoPor: creadoPor ?? 'rescatista',
          animalNombre: animalNombre,
          especie: especie,
          fotoUrl: fotoUrl,
          extra: {
            'ultimoMensaje': texto, 'ultimaHora': hora,
            'ultimoMensajeEn': FieldValue.serverTimestamp(),
            'noLeidosAdoptante': 1,
            if (tipoSolicitud != null) 'tipoSolicitud': tipoSolicitud,
          },
        );
      } else {
        await chatRef.set({
          'adoptanteId':     adoptanteId,
          'adoptanteNombre': adoptanteNombre ?? 'Adoptante',
          'animalNombre':    animalNombre,
          'creadoPor':       creadoPor ?? 'rescatista',
          'rescatistaId':    rescatistaId,
          'rescatista':      rescatistaNombre,
          if (fotoUrl        != null) 'fotoUrl':        fotoUrl,
          if (tipoSolicitud  != null) 'tipoSolicitud':  tipoSolicitud,
          if (especie        != null) 'especie':        especie,
          'ultimoMensaje': texto, 'ultimaHora': hora,
          'ultimoMensajeEn': FieldValue.serverTimestamp(),
          'noLeidosAdoptante': 1,
        });
      }
    } else {
      final existingData = existing.data() ?? {};
      await chatRef.update({
        'ultimoMensaje': texto, 'ultimaHora': hora,
        'ultimoMensajeEn': FieldValue.serverTimestamp(),
        'noLeidosAdoptante': FieldValue.increment(1),
        if (fotoUrl != null && existingData['fotoUrl'] == null)
          'fotoUrl': fotoUrl,
      });
    }
    await chatRef.collection('mensajes').add({
      'texto': texto, 'emisor': 'rescatista', 'hora': hora,
      'creadoEn': FieldValue.serverTimestamp(),
    });
    return true;
  } catch (_) {
    return false;
  }
}

/// [aprobada]: false si perdió la carrera contra otra solicitud del mismo
/// animal (ver [SolicitudesRepository.aprobarSiDisponible]) — en ese caso
/// esta solicitud quedó auto-rechazada, no aprobada.
/// [avisoOk]: si el mensaje de chat correspondiente (aprobación, o el aviso
/// de "ya no disponible" si perdió la carrera) se pudo enviar. La
/// aprobación/rechazo en sí ya quedó guardada aunque el aviso falle; el
/// llamador decide cómo informarle al rescatista que el chat no salió.
Future<({bool aprobada, bool avisoOk})> aprobarSolicitud(String docId, Map<String, dynamic> d) async {
  final rescateId     = d['rescateId']     as String? ?? '';
  final adoptanteId   = d['adoptanteId']   as String? ?? '';
  final animalNombre  = d['animalNombre']  as String? ?? '';
  final rescatistaId  = d['rescatistaId']  as String? ?? '';
  final creadoPor     = d['creadoPor']     as String? ?? 'rescatista';
  final tipoSolicitud = d['tipoSolicitud'] as String? ?? 'adopcion';
  final nuevoEstado   = tipoSolicitud == 'hogar_de_paso'
      ? 'Hogar de paso'
      : 'En proceso de adopción';

  final fechaInicio = d['fechaInicioHogar'] as Timestamp?;
  final fechaFin    = d['fechaFinHogar']    as Timestamp?;
  final camposExtra = <String, dynamic>{
    if (tipoSolicitud == 'hogar_de_paso') ...{
      if (fechaInicio != null) 'fechaInicioHogar': fechaInicio,
      if (fechaFin    != null) 'fechaFinHogar':    fechaFin,
      'vencimientoAvisado': false,
    },
  };

  bool aprobada;
  if (rescateId.isNotEmpty) {
    // Camino atómico (todas las solicitudes nuevas tienen rescateId): la
    // transacción verifica que el animal siga disponible antes de aprobar.
    aprobada = await SolicitudesRepository().aprobarSiDisponible(
      solicitudId: docId,
      rescateId: rescateId,
      adoptanteId: adoptanteId,
      nuevoEstadoAdopcion: nuevoEstado,
      camposExtra: camposExtra,
    );
  } else {
    // Dato legado sin rescateId: no hay documento puntual contra el cual
    // transaccionar (la búsqueda por nombre es una query, y las queries no
    // son transaccionales del lado del cliente). Best-effort, como antes —
    // caso cada vez más raro, son solicitudes de antes de que este campo
    // existiera.
    await SolicitudesRepository().cambiarEstado(docId, 'aprobada');
    if (animalNombre.isNotEmpty && rescatistaId.isNotEmpty) {
      await RescatesRepository().actualizarPorNombre(
        nombre: animalNombre,
        rescatistaId: rescatistaId,
        cambios: {
          'estadoAdopcion': nuevoEstado,
          'adoptanteIdEnProceso': adoptanteId,
          ...camposExtra,
        },
      );
    }
    aprobada = true;
  }

  if (!aprobada) {
    // Perdió la carrera: se le avisa a ESTE adoptante que ya no pudo ser,
    // igual que se les avisa a las competidoras más abajo.
    if (adoptanteId.isEmpty || animalNombre.isEmpty) return (aprobada: false, avisoOk: true);
    final avisoOk = await enviarMensajeChat(adoptanteId, animalNombre,
        '🐾 $animalNombre ya tiene un proceso de adopción activo. ¡No te desanimes, hay más amiguitos esperándote!',
        fotoUrl: d['fotoUrl'] as String?,
        rescateId: rescateId,
        creadoPor: creadoPor,
        especie: d['especie'] as String?);
    return (aprobada: false, avisoOk: avisoOk);
  }

  if (animalNombre.isNotEmpty) {
    // Se agrega rescateId cuando está disponible para no confundir animales
    // con el mismo nombre publicados por la misma cuenta bajo distinto rol
    // (ej. un "Rocky" como rescatista y otro "Rocky" como albergue).
    final rechazadas = await SolicitudesRepository().rechazarCompetidoras(
      animalNombre: animalNombre,
      rescatistaId: rescatistaId,
      excluirDocId: docId,
      rescateId: rescateId.isNotEmpty ? rescateId : null,
    );
    for (final otra in rechazadas) {
      final otroAdoptanteId = otra['adoptanteId'] as String? ?? '';
      if (otroAdoptanteId.isNotEmpty) {
        await enviarMensajeChat(otroAdoptanteId, animalNombre,
            '🐾 $animalNombre ya tiene un proceso de adopción activo. ¡No te desanimes, hay más amiguitos esperándote!',
            fotoUrl: otra['fotoUrl'] as String?,
            rescateId: otra['rescateId'] as String? ?? rescateId,
            creadoPor: otra['creadoPor'] as String? ?? creadoPor,
            especie: otra['especie'] as String? ?? d['especie'] as String?);
      }
    }
  }

  if (adoptanteId.isNotEmpty && animalNombre.isNotEmpty) {
    final msg = tipoSolicitud == 'hogar_de_paso'
        ? '✅ ¡Tu solicitud de hogar de paso fue aprobada! Pronto me pongo en contacto contigo para coordinar los detalles. 🐾'
        : '✅ ¡Tu solicitud de adopción fue aprobada! Pronto me pongo en contacto contigo para coordinar el encuentro. 🐾';
    final avisoOk = await enviarMensajeChat(adoptanteId, animalNombre, msg,
        fotoUrl: d['fotoUrl'] as String?,
        adoptanteNombre: d['nombre'] as String?,
        tipoSolicitud: tipoSolicitud,
        rescateId: rescateId,
        creadoPor: creadoPor,
        especie: d['especie'] as String?);
    return (aprobada: true, avisoOk: avisoOk);
  }
  return (aprobada: true, avisoOk: true);
}

/// Devuelve `true` si el aviso por chat al adoptante se pudo enviar.
Future<bool> rechazarSolicitud(String docId, Map<String, dynamic> d, String motivo) async {
  final animalNombre = d['animalNombre'] as String? ?? '';
  final texto = motivo.trim().isNotEmpty ? motivo.trim()
      : 'Hola, gracias por tu interés en adoptar a $animalNombre. '
        'Luego de revisar tu solicitud, en esta ocasión no podemos continuar con el proceso. '
        '¡Esperamos que pronto encuentres a tu compañero perfecto! 🐾';
  await SolicitudesRepository().rechazar(docId, texto);
  final adoptanteId = d['adoptanteId'] as String? ?? '';
  final fotoUrl     = d['fotoUrl']     as String?;
  final rescateId   = d['rescateId']   as String? ?? '';
  if (adoptanteId.isNotEmpty && animalNombre.isNotEmpty) {
    return enviarMensajeChat(adoptanteId, animalNombre, texto,
        fotoUrl: fotoUrl, adoptanteNombre: d['nombre'] as String?,
        rescateId: rescateId, creadoPor: d['creadoPor'] as String?,
        especie: d['especie'] as String?);
  }
  return true;
}

// ─────────────────────────────────────────────────────────────────────────────

class SolicitudesRescatistaScreen extends StatefulWidget {
  final bool esAlbergue;
  const SolicitudesRescatistaScreen({super.key, this.esAlbergue = false});
  @override
  State<SolicitudesRescatistaScreen> createState() => _SolicitudesRescatistaScreenState();
}

class _SolicitudesRescatistaScreenState extends State<SolicitudesRescatistaScreen> {
  final Set<String> _procesando = {};
  final _solicitudesRepo = SolicitudesRepository();

  Future<void> _aprobar(String docId, Map<String, dynamic> d) async {
    if (_procesando.contains(docId)) return;
    setState(() => _procesando.add(docId));
    try {
      final resultado = await aprobarSolicitud(docId, d);
      if (!mounted) return;
      if (!resultado.aprobada) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Este animal ya tenía un proceso aprobado con otro adoptante — '
                'esta solicitud se rechazó automáticamente.')));
      } else if (!resultado.avisoOk) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Solicitud aprobada, pero no pudimos avisarle al adoptante por chat. Escribile manualmente.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo aprobar la solicitud: $e')));
      }
    } finally {
      if (mounted) setState(() => _procesando.remove(docId));
    }
  }

  Future<void> _rechazar(String docId, Map<String, dynamic> d, String motivo) async {
    try {
      final avisoOk = await rechazarSolicitud(docId, d, motivo);
      if (!mounted) return;
      if (!avisoOk) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Solicitud rechazada, pero no pudimos avisarle al adoptante por chat.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo rechazar la solicitud: $e')));
      }
    }
  }

  String _tiempoRelativo(DateTime fecha) {
    final diff = DateTime.now().difference(fecha);
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}min';
    if (diff.inHours < 24)   return 'hace ${diff.inHours}h';
    return 'hace ${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appBg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 20, 12),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              const Expanded(child: Text('Solicitudes',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)))),
            ]),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _solicitudesRepo.paraOwner(
                uid: FirebaseAuth.instance.currentUser?.uid ?? '',
                role: widget.esAlbergue ? CreatorRole.albergue : CreatorRole.rescatista,
              ),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: appTeal));
                }
                if (snap.hasError) return errorFeedState();
                final docs = [...(snap.data?.docs ?? [])]..sort((a, b) {
                    final ta = a.data()['creadoEn'] as Timestamp?;
                    final tb = b.data()['creadoEn'] as Timestamp?;
                    if (ta == null) return 1;
                    if (tb == null) return -1;
                    return tb.compareTo(ta);
                  });
                if (docs.isEmpty) {
                  return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('Aún no tienes solicitudes',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 15, fontWeight: FontWeight.w600)),
                    ]),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                  itemCount: docs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final d           = docs[i].data();
                    final animal      = d['animalNombre'] as String? ?? 'Animal';
                    final nombre      = d['nombre']      as String? ?? 'Adoptante';
                    final integrantes = d['integrantes'] as String? ?? '';
                    final vivienda    = d['vivienda']    as String? ?? '';
                    final mascotas    = (d['tieneMascotas'] as bool? ?? false) ? 'con mascotas' : 'sin mascotas';
                    final ninos       = (d['tieneNinos']    as bool? ?? false) ? 'con niños' : 'sin niños';
                    final exp         = (d['experienciaPrevia'] as bool? ?? false) ? 'con experiencia' : 'sin experiencia';
                    final horas       = d['horasFuera'] as String? ?? '';
                    final ts          = d['creadoEn'] as Timestamp?;
                    final tiempo      = ts != null ? _tiempoRelativo(ts.toDate()) : '';
                    final ini         = nombre.isNotEmpty ? nombre[0].toUpperCase() : 'A';
                    final col         = i.isEven ? appTeal : appOrange;
                    final fotoUrl     = d['fotoUrl'] as String?;
                    final estado          = d['estado'] as String? ?? 'pendiente';
                    final tipo            = d['tipoSolicitud']    as String? ?? 'adopcion';
                    final esHogar         = tipo == 'hogar_de_paso';
                    final fechaInicioTs   = d['fechaInicioHogar'] as Timestamp?;
                    final fechaFinTs      = d['fechaFinHogar']    as Timestamp?;
                    final fechaInicio     = fechaInicioTs?.toDate();
                    final fechaFin        = fechaFinTs?.toDate();
                    final diasHogar       = (fechaInicio != null && fechaFin != null)
                        ? fechaFin.difference(fechaInicio).inDays
                        : null;
                    final score       = calcularCompatibilidad(d);
                    final scoreColor  = score >= 80 ? const Color(0xFF1F8A62) : score >= 60 ? const Color(0xFFE65100) : const Color(0xFFB71C1C);
                    final estadoColor = estado == 'aprobada'
                        ? const Color(0xFF1F8A62)
                        : estado == 'rechazada'
                        ? const Color(0xFFB71C1C)
                        : const Color(0xFFE65100);
                    final estadoLabel = estado == 'aprobada'  ? '✅  Aprobada'
                        : estado == 'rechazada' ? '❌  Rechazada'
                        : '⏳  Pendiente';
                    final detalle     = [
                      vivienda, if (integrantes.isNotEmpty) '$integrantes personas',
                      ninos, mascotas, exp,
                      if (horas.isNotEmpty) '$horas h fuera/día',
                    ].join(' · ');

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                        // ── Fila principal: animal ──────────────────────────
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          // Foto del animal
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: fotoUrl != null
                              ? FotoUrl(
                                  url: fotoUrl,
                                  width: 64, height: 64, fit: BoxFit.cover,
                                  fallback: Container(width: 64, height: 64,
                                      color: const Color(0xFFD8F0E4),
                                      child: const Center(child: Icon(Icons.pets, color: appTeal, size: 30))),
                                )
                              : Container(width: 64, height: 64,
                                  color: const Color(0xFFD8F0E4),
                                  child: const Center(child: Icon(Icons.pets, color: appTeal, size: 30))),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(
                                child: Text(animal,
                                    style: const TextStyle(fontWeight: FontWeight.bold,
                                        fontSize: 17, color: Color(0xFF1A1A1A))),
                              ),
                              Text(tiempo, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                            ]),
                            const SizedBox(height: 6),
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: esHogar ? appTeal.withValues(alpha: 0.12) : appOrange.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: esHogar ? appTeal.withValues(alpha: 0.4) : appOrange.withValues(alpha: 0.4)),
                                ),
                                child: Text(esHogar ? '🏡 Hogar de paso' : '🏠 Adopción',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                                        color: esHogar ? appTeal : appOrange)),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: estadoColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: estadoColor.withValues(alpha: 0.4)),
                                ),
                                child: Text(estadoLabel, style: TextStyle(fontSize: 10,
                                    fontWeight: FontWeight.w700, color: estadoColor)),
                              ),
                            ]),
                          ])),
                        ]),

                        // ── Fila adoptante ──────────────────────────────────
                        const SizedBox(height: 12),
                        Row(children: [
                          CircleAvatar(backgroundColor: col, radius: 14,
                            child: Text(ini, style: const TextStyle(color: Colors.white,
                                fontSize: 12, fontWeight: FontWeight.bold))),
                          const SizedBox(width: 8),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(nombre, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            Text(detalle, style: TextStyle(fontSize: 11, color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ])),
                        ]),

                        if (esHogar && fechaInicio != null && fechaFin != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: appTeal.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: appTeal.withValues(alpha: 0.3)),
                            ),
                            child: Row(children: [
                              const Icon(Icons.calendar_today, size: 13, color: appTeal),
                              const SizedBox(width: 8),
                              Text(
                                '${fechaInicio.day}/${fechaInicio.month}/${fechaInicio.year} → ${fechaFin.day}/${fechaFin.month}/${fechaFin.year}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: appTeal),
                              ),
                              const Spacer(),
                              Text('$diasHogar días', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: appTeal)),
                            ]),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: scoreColor.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: scoreColor.withValues(alpha: 0.35)),
                          ),
                          child: Row(children: [
                            Text(score >= 80 ? '✅' : score >= 60 ? '⚠️' : '❌',
                                style: const TextStyle(fontSize: 18)),
                            const SizedBox(width: 10),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(
                                score >= 80 ? 'Perfil ideal ($score%)'
                                    : score >= 60 ? 'Perfil aceptable ($score%)'
                                    : 'No recomendado ($score%)',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scoreColor),
                              ),
                              const SizedBox(height: 8),
                              ...explicarCompatibilidad(d).map((r) => Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(r.$2 ? '✓' : '✗',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                                          color: r.$2 ? appTeal : Colors.red.shade400)),
                                  const SizedBox(width: 5),
                                  Expanded(child: Text(r.$1,
                                      style: TextStyle(fontSize: 11,
                                          color: r.$2 ? Colors.grey.shade700 : Colors.red.shade600))),
                                ]),
                              )),
                            ])),
                          ]),
                        ),
                        if (estado == 'rechazada') ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF8F0),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFE65100).withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              (d['motivoRechazo'] as String?)?.isNotEmpty == true
                                  ? d['motivoRechazo'] as String
                                  : 'Hola, gracias por tu interés en adoptar a $animal. '
                                    'Luego de revisar tu solicitud, en esta ocasión no podemos continuar con el proceso. '
                                    '¡Esperamos que pronto encuentres a tu compañero perfecto! 🐾',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.5),
                            ),
                          ),
                        ],
                        if (estado == 'aprobada') ...[
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: () async {
                              final adoptanteId = d['adoptanteId'] as String? ?? '';
                              final rescateIdChat = d['rescateId'] as String? ?? '';
                              String? chatId;
                              // try/catch: leer un chat que NO existe da
                              // permission-denied con nuestras reglas (no
                              // pueden probar que te corresponde ver un doc
                              // que no está). Pasa cuando el mensaje
                              // automático de la aprobación no llegó a crear
                              // el chat — sin esto, la excepción mataba el
                              // onTap y el botón "Ir al chat" no hacía nada.
                              // Con chatId null, ChatScreen crea el chat.
                              try {
                                if (rescateIdChat.isNotEmpty) {
                                  final doc = await FirebaseFirestore.instance
                                      .collection('chats').doc(ChatsRepository()
                                          .idAnimal(rescateId: rescateIdChat, adoptanteId: adoptanteId)).get();
                                  if (doc.exists) chatId = doc.id;
                                } else {
                                  final snap = await FirebaseFirestore.instance
                                      .collection('chats')
                                      .where('adoptanteId', isEqualTo: adoptanteId)
                                      .where('animalNombre', isEqualTo: animal)
                                      .limit(1)
                                      .get();
                                  if (snap.docs.isNotEmpty) chatId = snap.docs.first.id;
                                }
                              } catch (_) {
                                chatId = null;
                              }
                              if (!context.mounted) return;
                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  esRescatista: true,
                                  chatId: chatId,
                                  animal: {
                                    'nombre':         animal,
                                    'rescatista':     FirebaseAuth.instance.currentUser?.displayName ?? 'Rescatista',
                                    'rescatistaId':   FirebaseAuth.instance.currentUser?.uid ?? '',
                                    'rescateId':      d['rescateId'] as String? ?? '',
                                    'adoptanteId':    adoptanteId,
                                    'adoptanteNombre': d['nombre'] as String? ?? 'Adoptante',
                                    'especie':        d['especie'] as String? ?? 'Perro',
                                    'fotoUrl':        d['fotoUrl'] as String?,
                                    'tipoSolicitud':  d['tipoSolicitud'] as String? ?? 'adopcion',
                                    'creadoPor':      d['creadoPor'] as String? ?? 'rescatista',
                                    'edad':           '',
                                    'ubicacion':      '',
                                    'descripcion':    '',
                                    'tags':           <String>[],
                                  },
                                ),
                              ));
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: appTeal,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(Icons.chat_bubble_outline, size: 15, color: Colors.white),
                                SizedBox(width: 6),
                                Text('Ir al chat', style: TextStyle(fontSize: 13,
                                    fontWeight: FontWeight.w700, color: Colors.white)),
                              ]),
                            ),
                          ),
                        ],
                        if (estado == 'pendiente') ...[
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: _procesando.contains(docs[i].id)
                                    ? null
                                    : () => _aprobar(docs[i].id, d),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: _procesando.contains(docs[i].id)
                                        ? appTeal.withValues(alpha: 0.5)
                                        : appTeal,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: _procesando.contains(docs[i].id)
                                      ? const SizedBox(height: 16, width: 16,
                                          child: Center(child: SizedBox(height: 14, width: 14,
                                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))))
                                      : const Text('Aprobar', textAlign: TextAlign.center,
                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  final motivoCtl = TextEditingController(
                                    text: 'Hola, gracias por tu interés en adoptar a $animal. '
                                        'Luego de revisar tu solicitud, en esta ocasión no podemos continuar con el proceso. '
                                        '¡Esperamos que pronto encuentres a tu compañero perfecto! 🐾',
                                  );
                                  showDialog(context: context, builder: (dlg) => AlertDialog(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    title: const Text('Mensaje de rechazo'),
                                    content: TextField(
                                      controller: motivoCtl,
                                      maxLines: 5,
                                      decoration: InputDecoration(
                                        hintText: '',
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: const BorderSide(color: appTeal, width: 2),
                                        ),
                                      ),
                                    ),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(dlg), child: const Text('Cancelar')),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(dlg);
                                          _rechazar(docs[i].id, d, motivoCtl.text.trim());
                                        },
                                        child: const Text('Confirmar', style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ));
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.red.shade300),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text('Rechazar', textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.bold, fontSize: 13)),
                                ),
                              ),
                            ),
                          ]),
                        ],
                      ]),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
