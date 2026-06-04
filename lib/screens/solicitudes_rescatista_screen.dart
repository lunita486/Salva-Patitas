import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import 'chat_screen.dart';

int calcularCompatibilidad(Map<String, dynamic> solicitud) {
  int score = 0;

  final energia    = solicitud['animalEnergia']  as String? ?? 'Tranquilo';
  final horas      = int.tryParse(solicitud['horasFuera']?.toString() ?? '0') ?? 0;
  final vivienda   = solicitud['vivienda']       as String? ?? '';
  final tienePatio = vivienda == 'Casa con jardín';

  if (energia == 'Tranquilo') {
    score += 20;
  } else if (energia == 'Activo') {
    score += horas <= 8 ? 20 : 10;
  } else {
    if (tienePatio && horas <= 6) score += 20;
    else if (tienePatio || horas <= 6) score += 10;
  }

  final tamano = solicitud['animalTamano'] as String? ?? 'Mediano';
  if (tamano == 'Pequeño') {
    score += 20;
  } else if (tamano == 'Mediano') {
    score += vivienda != 'Apartamento sin área exterior' ? 20 : 10;
  } else {
    score += tienePatio ? 20 : (vivienda == 'Apartamento con balcón' ? 10 : 0);
  }

  final okNinos    = solicitud['animalOkConNinos']   as bool? ?? true;
  final tieneNinos = solicitud['tieneNinos']         as bool? ?? false;
  score += (!tieneNinos || okNinos) ? 20 : 0;

  final okMascotas    = solicitud['animalOkConMascotas'] as bool? ?? true;
  final tieneMascotas = solicitud['tieneMascotas']       as bool? ?? false;
  score += (!tieneMascotas || okMascotas) ? 20 : 0;

  final requiereExp = solicitud['animalRequiereExp']   as bool? ?? false;
  final tieneExp    = solicitud['experienciaPrevia']   as bool? ?? false;
  score += (!requiereExp || tieneExp) ? 20 : 0;

  return score;
}

List<(String, bool)> explicarCompatibilidad(Map<String, dynamic> sol) {
  final reasons = <(String, bool)>[];

  final energia    = sol['animalEnergia']  as String? ?? 'Tranquilo';
  final horas      = int.tryParse(sol['horasFuera']?.toString() ?? '0') ?? 0;
  final vivienda   = sol['vivienda']       as String? ?? '';
  final tienePatio = vivienda == 'Casa con jardín';
  final tamano     = sol['animalTamano']       as String? ?? 'Mediano';
  final okNinos    = sol['animalOkConNinos']   as bool?   ?? true;
  final tieneNinos = sol['tieneNinos']         as bool?   ?? false;
  final okMascotas    = sol['animalOkConMascotas'] as bool? ?? true;
  final tieneMascotas = sol['tieneMascotas']       as bool? ?? false;
  final requiereExp   = sol['animalRequiereExp']   as bool? ?? false;
  final tieneExp      = sol['experienciaPrevia']   as bool? ?? false;

  // Energía
  if (energia == 'Tranquilo') {
    reasons.add(('Animal tranquilo, se adapta bien al hogar', true));
  } else if (energia == 'Activo') {
    reasons.add(horas <= 8
        ? ('Animal activo, horas fuera son aceptables', true)
        : ('Animal activo pero pasa demasiadas horas solo ($horas h/día)', false));
  } else {
    if (tienePatio && horas <= 6)  reasons.add(('Animal muy activo — tiene jardín y poco tiempo solo', true));
    else if (tienePatio)           reasons.add(('Animal muy activo — tiene jardín pero $horas h solo', false));
    else if (horas <= 6)           reasons.add(('Animal muy activo — necesita jardín', false));
    else                           reasons.add(('Animal muy activo — necesita jardín y menos horas solo', false));
  }

  // Tamaño
  if (tamano == 'Pequeño') {
    reasons.add(('Animal pequeño, se adapta a cualquier espacio', true));
  } else if (tamano == 'Mediano') {
    reasons.add(vivienda != 'Apartamento sin área exterior'
        ? ('Animal mediano, el espacio es adecuado', true)
        : ('Animal mediano en apartamento sin área exterior', false));
  } else {
    if (tienePatio)                              reasons.add(('Animal grande, tiene jardín suficiente', true));
    else if (vivienda == 'Apartamento con balcón') reasons.add(('Animal grande, el espacio es limitado', false));
    else                                          reasons.add(('Animal grande, necesita más espacio', false));
  }

  // Niños
  if (!tieneNinos)      reasons.add(('Sin niños en casa', true));
  else if (okNinos)     reasons.add(('Hay niños y el animal los acepta bien', true));
  else                  reasons.add(('Hay niños pero el animal no es apto con ellos', false));

  // Mascotas
  if (!tieneMascotas)   reasons.add(('Sin otras mascotas en casa', true));
  else if (okMascotas)  reasons.add(('Hay mascotas y el animal convive bien', true));
  else                  reasons.add(('Hay mascotas pero el animal no convive con ellas', false));

  // Experiencia
  if (!requiereExp)     reasons.add(('No se requiere experiencia previa', true));
  else if (tieneExp)    reasons.add(('El animal requiere experiencia — adoptante la tiene', true));
  else                  reasons.add(('El animal requiere experiencia previa', false));

  return reasons;
}

// ── Funciones top-level reutilizables por home_screen y solicitudes_screen ──

Future<void> enviarMensajeChat(String adoptanteId, String animalNombre, String texto, {String? fotoBase64, String? adoptanteNombre, String? tipoSolicitud}) async {
  try {
    final rescatistaId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final n    = DateTime.now();
    final hora = '${n.hour}:${n.minute.toString().padLeft(2, '0')}';
    final chats = await FirebaseFirestore.instance.collection('chats')
        .where('adoptanteId', isEqualTo: adoptanteId)
        .where('animalNombre', isEqualTo: animalNombre)
        .limit(1).get();
    String chatId;
    final userDoc = await FirebaseFirestore.instance.collection('usuarios').doc(rescatistaId).get();
    final userData = userDoc.data() ?? {};
    final rescatistaNombre =
        (userData['albergueNombre'] as String?)?.isNotEmpty == true
            ? userData['albergueNombre'] as String
            : (userData['nombre'] as String?)?.isNotEmpty == true
                ? userData['nombre'] as String
                : FirebaseAuth.instance.currentUser?.displayName ?? 'Rescatista';
    if (chats.docs.isEmpty) {
      final ref = await FirebaseFirestore.instance.collection('chats').add({
        'adoptanteId':     adoptanteId,
        'adoptanteNombre': adoptanteNombre ?? 'Adoptante',
        'animalNombre':    animalNombre,
        'rescatistaId':    rescatistaId,
        'rescatista':      rescatistaNombre,
        if (fotoBase64     != null) 'fotoBase64':     fotoBase64,
        if (tipoSolicitud  != null) 'tipoSolicitud':  tipoSolicitud,
        'ultimoMensaje': texto, 'ultimaHora': hora,
        'ultimoMensajeEn': FieldValue.serverTimestamp(),
        'noLeidosAdoptante': 1,
      });
      chatId = ref.id;
    } else {
      chatId = chats.docs.first.id;
      final existingData = chats.docs.first.data();
      await FirebaseFirestore.instance.collection('chats').doc(chatId).update({
        'ultimoMensaje': texto, 'ultimaHora': hora,
        'ultimoMensajeEn': FieldValue.serverTimestamp(),
        'noLeidosAdoptante': FieldValue.increment(1),
        if (fotoBase64 != null && existingData['fotoBase64'] == null)
          'fotoBase64': fotoBase64,
      });
    }
    await FirebaseFirestore.instance
        .collection('chats').doc(chatId).collection('mensajes').add({
      'texto': texto, 'emisor': 'rescatista', 'hora': hora,
      'creadoEn': FieldValue.serverTimestamp(),
    });
  } catch (_) {}
}

Future<void> aprobarSolicitud(String docId, Map<String, dynamic> d) async {
  final rescateId     = d['rescateId']     as String? ?? '';
  final adoptanteId   = d['adoptanteId']   as String? ?? '';
  final animalNombre  = d['animalNombre']  as String? ?? '';
  final rescatistaId  = d['rescatistaId']  as String? ?? '';
  final tipoSolicitud = d['tipoSolicitud'] as String? ?? 'adopcion';
  final nuevoEstado   = tipoSolicitud == 'hogar_de_paso'
      ? 'Hogar de paso'
      : 'En proceso de adopción';

  await FirebaseFirestore.instance.collection('solicitudes').doc(docId)
      .update({'estado': 'aprobada'});

  final fechaInicio = d['fechaInicioHogar'] as Timestamp?;
  final fechaFin    = d['fechaFinHogar']    as Timestamp?;
  final extraHogar  = tipoSolicitud == 'hogar_de_paso'
      ? <String, dynamic>{
          if (fechaInicio != null) 'fechaInicioHogar':   fechaInicio,
          if (fechaFin    != null) 'fechaFinHogar':      fechaFin,
          'adoptanteIdEnProceso': adoptanteId,
          'vencimientoAvisado':   false,
        }
      : <String, dynamic>{};

  if (rescateId.isNotEmpty) {
    await FirebaseFirestore.instance.collection('rescates').doc(rescateId)
        .update({'estadoAdopcion': nuevoEstado, ...extraHogar});
  } else if (animalNombre.isNotEmpty && rescatistaId.isNotEmpty) {
    final q = await FirebaseFirestore.instance.collection('rescates')
        .where('nombre',       isEqualTo: animalNombre)
        .where('rescatistaId', isEqualTo: rescatistaId)
        .limit(1).get();
    if (q.docs.isNotEmpty) {
      await q.docs.first.reference.update({'estadoAdopcion': nuevoEstado, ...extraHogar});
    }
  }

  if (animalNombre.isNotEmpty) {
    final otros = await FirebaseFirestore.instance
        .collection('solicitudes')
        .where('animalNombre', isEqualTo: animalNombre)
        .where('rescatistaId', isEqualTo: rescatistaId)
        .where('estado',       isEqualTo: 'pendiente')
        .get();
    for (final doc in otros.docs) {
      if (doc.id == docId) continue;
      final otroAdoptanteId = (doc.data())['adoptanteId'] as String? ?? '';
      await doc.reference.update({
        'estado':        'rechazada',
        'motivoRechazo': 'El proceso de adopción ya fue iniciado con otro adoptante.',
      });
      if (otroAdoptanteId.isNotEmpty) {
        await enviarMensajeChat(otroAdoptanteId, animalNombre,
            '🐾 $animalNombre ya tiene un proceso de adopción activo. ¡No te desanimes, hay más amiguitos esperándote!',
            fotoBase64: d['fotoBase64'] as String?);
      }
    }
  }

  if (adoptanteId.isNotEmpty && animalNombre.isNotEmpty) {
    final msg = tipoSolicitud == 'hogar_de_paso'
        ? '✅ ¡Tu solicitud de hogar de paso fue aprobada! Pronto me pongo en contacto contigo para coordinar los detalles. 🐾'
        : '✅ ¡Tu solicitud de adopción fue aprobada! Pronto me pongo en contacto contigo para coordinar el encuentro. 🐾';
    await enviarMensajeChat(adoptanteId, animalNombre, msg,
        fotoBase64: d['fotoBase64'] as String?,
        adoptanteNombre: d['nombre'] as String?,
        tipoSolicitud: tipoSolicitud);
  }
}

Future<void> rechazarSolicitud(String docId, Map<String, dynamic> d, String motivo) async {
  final animalNombre = d['animalNombre'] as String? ?? '';
  final texto = motivo.trim().isNotEmpty ? motivo.trim()
      : 'Hola, gracias por tu interés en adoptar a $animalNombre. '
        'Luego de revisar tu solicitud, en esta ocasión no podemos continuar con el proceso. '
        '¡Esperamos que pronto encuentres a tu compañero perfecto! 🐾';
  await FirebaseFirestore.instance.collection('solicitudes').doc(docId).update({
    'estado': 'rechazada', 'motivoRechazo': texto,
  });
  final adoptanteId = d['adoptanteId'] as String? ?? '';
  final fotoBase64  = d['fotoBase64']  as String?;
  if (adoptanteId.isNotEmpty && animalNombre.isNotEmpty) {
    await enviarMensajeChat(adoptanteId, animalNombre, texto,
        fotoBase64: fotoBase64, adoptanteNombre: d['nombre'] as String?);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class SolicitudesRescatistaScreen extends StatefulWidget {
  const SolicitudesRescatistaScreen({super.key});
  @override
  State<SolicitudesRescatistaScreen> createState() => _SolicitudesRescatistaScreenState();
}

class _SolicitudesRescatistaScreenState extends State<SolicitudesRescatistaScreen> {
  final Set<String> _procesando = {};

  Future<void> _aprobar(String docId, Map<String, dynamic> d) async {
    if (_procesando.contains(docId)) return;
    setState(() => _procesando.add(docId));
    try {
      await aprobarSolicitud(docId, d);
    } finally {
      if (mounted) setState(() => _procesando.remove(docId));
    }
  }

  Future<void> _rechazar(String docId, Map<String, dynamic> d, String motivo) => rechazarSolicitud(docId, d, motivo);

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
              const Expanded(child: Text('Solicitudes de adopción',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)))),
            ]),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('solicitudes')
                  .where('rescatistaId', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: appTeal));
                }
                final docs = [...(snap.data?.docs ?? [])]..sort((a, b) {
                    final ta = (a.data() as Map)['creadoEn'] as Timestamp?;
                    final tb = (b.data() as Map)['creadoEn'] as Timestamp?;
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
                    final d           = docs[i].data() as Map<String, dynamic>;
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
                    final fotoBase64  = d['fotoBase64'] as String?;
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
                            child: fotoBase64 != null
                              ? Image.memory(base64Decode(fotoBase64),
                                  width: 64, height: 64, fit: BoxFit.cover)
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
                              final snap = await FirebaseFirestore.instance
                                  .collection('chats')
                                  .where('adoptanteId', isEqualTo: adoptanteId)
                                  .where('animalNombre', isEqualTo: animal)
                                  .limit(1)
                                  .get();
                              if (!context.mounted) return;
                              final chatId = snap.docs.isNotEmpty ? snap.docs.first.id : null;
                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  esRescatista: true,
                                  chatId: chatId,
                                  animal: {
                                    'nombre':         animal,
                                    'rescatista':     FirebaseAuth.instance.currentUser?.displayName ?? 'Rescatista',
                                    'especie':        d['especie'] as String? ?? 'Perro',
                                    'fotoBase64':     d['fotoBase64'] as String?,
                                    'tipoSolicitud':  d['tipoSolicitud'] as String? ?? 'adopcion',
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
