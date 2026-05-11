import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';

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

class SolicitudesRescatistaScreen extends StatefulWidget {
  const SolicitudesRescatistaScreen({super.key});
  @override
  State<SolicitudesRescatistaScreen> createState() => _SolicitudesRescatistaScreenState();
}

class _SolicitudesRescatistaScreenState extends State<SolicitudesRescatistaScreen> {
  String _filtro = 'pendiente';

  static const _filtros = [
    ('pendiente',  'Pendientes'),
    ('aprobada',   'Aprobadas'),
    ('rechazada',  'Rechazadas'),
  ];

  String _nowTime() {
    final n = DateTime.now();
    return '${n.hour}:${n.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _enviarMensajeChat(String adoptanteId, String animalNombre, String texto) async {
    try {
      final chats = await FirebaseFirestore.instance.collection('chats')
          .where('adoptanteId', isEqualTo: adoptanteId)
          .where('animalNombre', isEqualTo: animalNombre)
          .limit(1).get();
      if (chats.docs.isEmpty) return;
      final chatId = chats.docs.first.id;
      final hora = _nowTime();
      await FirebaseFirestore.instance
          .collection('chats').doc(chatId).collection('mensajes').add({
        'texto': texto, 'emisor': 'rescatista', 'hora': hora,
        'creadoEn': FieldValue.serverTimestamp(),
      });
      await FirebaseFirestore.instance.collection('chats').doc(chatId).update({
        'ultimoMensaje': texto, 'ultimaHora': hora,
        'ultimoMensajeEn': FieldValue.serverTimestamp(),
        'noLeidosAdoptante': FieldValue.increment(1),
      });
    } catch (_) {}
  }

  Future<void> _aprobar(String docId, Map<String, dynamic> d) async {
    await FirebaseFirestore.instance.collection('solicitudes').doc(docId)
        .update({'estado': 'aprobada'});
    final adoptanteId  = d['adoptanteId']  as String? ?? '';
    final animalNombre = d['animalNombre'] as String? ?? '';
    if (adoptanteId.isNotEmpty && animalNombre.isNotEmpty) {
      await _enviarMensajeChat(adoptanteId, animalNombre,
          '✅ ¡Tu solicitud de adopción fue aprobada! Pronto me pongo en contacto contigo para coordinar el encuentro. 🐾');
    }
  }

  Future<void> _rechazar(String docId, Map<String, dynamic> d, String motivo) async {
    final texto = motivo.isEmpty ? 'Sin motivo especificado' : motivo;
    await FirebaseFirestore.instance.collection('solicitudes').doc(docId).update({
      'estado': 'rechazada', 'motivoRechazo': texto,
    });
    final adoptanteId  = d['adoptanteId']  as String? ?? '';
    final animalNombre = d['animalNombre'] as String? ?? '';
    if (adoptanteId.isNotEmpty && animalNombre.isNotEmpty) {
      final msg = motivo.isEmpty
          ? '❌ Tu solicitud de adopción no fue aprobada esta vez. ¡Sigue intentando, hay más amigos esperándote! 🐾'
          : '❌ Tu solicitud de adopción no fue aprobada. Motivo: $motivo';
      await _enviarMensajeChat(adoptanteId, animalNombre, msg);
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
              const Expanded(child: Text('Solicitudes de adopción',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)))),
            ]),
          ),
          // Filtros
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: _filtros.map((f) {
              final activo = _filtro == f.$1;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _filtro = f.$1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: activo ? appTeal : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: activo ? appTeal : Colors.grey.shade300),
                    ),
                    child: Text(f.$2, style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: activo ? Colors.white : Colors.grey.shade600,
                    )),
                  ),
                ),
              );
            }).toList()),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('solicitudes')
                  .where('rescatistaId', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
                  .where('estado', isEqualTo: _filtro)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: appTeal));
                }
                final docs = [...(snap.data?.docs ?? [])]..sort((a, b) {
                    final ta = (a.data() as Map)['creadoEn'] as Timestamp?;
                    final tb = (b.data() as Map)['creadoEn'] as Timestamp?;
                    if (ta == null || tb == null) return 0;
                    return tb.compareTo(ta);
                  });
                if (docs.isEmpty) {
                  return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('No hay solicitudes ${_filtro == 'pendiente' ? 'pendientes' : _filtro == 'aprobada' ? 'aprobadas' : 'rechazadas'}',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 15, fontWeight: FontWeight.w600)),
                    ]),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
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
                    final score       = calcularCompatibilidad(d);
                    final scoreColor  = score >= 80 ? const Color(0xFF1F8A62) : score >= 60 ? const Color(0xFFE65100) : const Color(0xFFB71C1C);
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
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          CircleAvatar(backgroundColor: col, radius: 20,
                              child: Text(ini, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            const SizedBox(height: 2),
                            Text(detalle, style: TextStyle(fontSize: 11, color: Colors.grey.shade600), maxLines: 2),
                          ])),
                          Text(tiempo, style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                        ]),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: const Color(0xFFD8F0E4), borderRadius: BorderRadius.circular(12)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(width: 32, height: 32,
                              decoration: BoxDecoration(color: Colors.brown.shade300, borderRadius: BorderRadius.circular(6)),
                              child: const Icon(Icons.pets, size: 18, color: Colors.white)),
                            const SizedBox(width: 8),
                            Text('Para $animal', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          ]),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: scoreColor.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: scoreColor.withOpacity(0.35)),
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
                            ])),
                          ]),
                        ),
                        if (_filtro == 'rechazada' && d['motivoRechazo'] != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Motivo del rechazo',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.red.shade400)),
                              const SizedBox(height: 4),
                              Text(d['motivoRechazo'], style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                            ]),
                          ),
                        ],
                        if (_filtro == 'pendiente') ...[
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _aprobar(docs[i].id, d),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(color: appTeal, borderRadius: BorderRadius.circular(10)),
                                  child: const Text('Aprobar', textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  final motivoCtl = TextEditingController();
                                  showDialog(context: context, builder: (dlg) => AlertDialog(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    title: const Text('¿Por qué rechazas?'),
                                    content: TextField(
                                      controller: motivoCtl,
                                      maxLines: 3,
                                      decoration: InputDecoration(
                                        hintText: 'ej. El espacio no es suficiente...',
                                        hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
