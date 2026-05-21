import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import '../theme.dart';
import 'chat_screen.dart';

class MisSolicitudesScreen extends StatelessWidget {
  const MisSolicitudesScreen({super.key});

  String _formatFecha(DateTime d) {
    const meses = ['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'];
    return '${d.day} ${meses[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
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
              const Expanded(child: Text('Mis solicitudes',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)))),
            ]),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('solicitudes')
                  .where('adoptanteId', isEqualTo: uid)
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
                      Icon(Icons.assignment_outlined, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      const Text('Aún no has enviado solicitudes',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                      const SizedBox(height: 8),
                      Text('Cuando solicites adoptar un animal\naparecerá aquí con su estado.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade500, height: 1.5)),
                    ]),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                  itemCount: docs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final d          = docs[i].data() as Map<String, dynamic>;
                    final animal     = d['animalNombre'] as String? ?? 'Animal';
                    final estado     = d['estado']       as String? ?? 'pendiente';
                    final motivo     = d['motivoRechazo'] as String?;
                    final ts         = d['creadoEn'] as Timestamp?;
                    final fecha      = ts != null ? _formatFecha(ts.toDate()) : '';
                    final fotoBase64    = d['fotoBase64']      as String?;
                    final tipo          = d['tipoSolicitud']   as String? ?? 'adopcion';
                    final fechaFinTs    = d['fechaFinHogar']   as Timestamp?;
                    final fechaInicioTs = d['fechaInicioHogar'] as Timestamp?;
                    final fechaFin      = fechaFinTs?.toDate();
                    final fechaInicio   = fechaInicioTs?.toDate();
                    final hoy           = DateTime.now();
                    final diasRestantes = fechaFin != null
                        ? DateTime(fechaFin.year, fechaFin.month, fechaFin.day)
                            .difference(DateTime(hoy.year, hoy.month, hoy.day))
                            .inDays
                        : null;

                    final estadoColor = estado == 'aprobada'
                        ? const Color(0xFF1F8A62)
                        : estado == 'rechazada'
                        ? const Color(0xFFB71C1C)
                        : const Color(0xFFE65100);
                    final estadoLabel = estado == 'aprobada'  ? '✅  Aprobada'
                        : estado == 'rechazada' ? '❌  Rechazada'
                        : '⏳  Pendiente';

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 8, offset: const Offset(0, 2))],
                      ),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: fotoBase64 != null
                              ? Image.memory(base64Decode(fotoBase64),
                                  width: 56, height: 56, fit: BoxFit.cover)
                              : Container(
                                  width: 56, height: 56,
                                  color: appTeal.withValues(alpha: 0.12),
                                  child: const Center(child: Text('🐾', style: TextStyle(fontSize: 26))),
                                ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(animal, style: const TextStyle(fontSize: 15,
                              fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                          const SizedBox(height: 2),
                          Text(
                            tipo == 'hogar_de_paso' ? '🏡 Hogar de paso' : '🏠 Adopción',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500,
                                fontWeight: FontWeight.w600),
                          ),
                          if (fecha.isNotEmpty) ...[
                            const SizedBox(height: 1),
                            Text('Enviada el $fecha',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                          ],
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: estadoColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: estadoColor.withValues(alpha: 0.4)),
                            ),
                            child: Text(estadoLabel, style: TextStyle(fontSize: 12,
                                fontWeight: FontWeight.w700, color: estadoColor)),
                          ),
                          if (estado == 'aprobada' && tipo == 'hogar_de_paso' && fechaFin != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: appTeal.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: appTeal.withValues(alpha: 0.3)),
                              ),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                if (fechaInicio != null)
                                  Text('📅 ${_formatFecha(fechaInicio)} → ${_formatFecha(fechaFin)}',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                Text(
                                  diasRestantes! < 0
                                      ? '⚠️ Período vencido hace ${diasRestantes.abs()} días'
                                      : diasRestantes == 0
                                          ? '⚠️ El período vence hoy'
                                          : '🕐 $diasRestantes días restantes',
                                  style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700,
                                    color: diasRestantes < 3 ? const Color(0xFFE65100) : appTeal,
                                  ),
                                ),
                              ]),
                            ),
                          ],
                          if (estado == 'aprobada') ...[
                            const SizedBox(height: 10),
                            GestureDetector(
                              onTap: () async {
                                final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                                final snap = await FirebaseFirestore.instance
                                    .collection('chats')
                                    .where('adoptanteId', isEqualTo: uid)
                                    .where('animalNombre', isEqualTo: animal)
                                    .limit(1)
                                    .get();
                                if (!context.mounted) return;
                                final chatId = snap.docs.isNotEmpty ? snap.docs.first.id : null;
                                final animalMap = {
                                  'nombre':      animal,
                                  'rescatista':  d['rescatistaNombre'] as String? ?? d['rescatista'] as String? ?? 'Rescatista',
                                  'rescatistaId': d['rescatistaId'] as String? ?? '',
                                  'especie':     d['especie'] as String? ?? 'Perro',
                                  'fotoBase64':  fotoBase64,
                                  'edad':        '',
                                  'ubicacion':   '',
                                  'descripcion': '',
                                  'tags':        <String>[],
                                };
                                Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => ChatScreen(animal: animalMap, chatId: chatId),
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
                                motivo != null && motivo.isNotEmpty
                                    ? motivo
                                    : 'Hola, gracias por tu interés en adoptar a $animal. '
                                      'Luego de revisar tu solicitud, en esta ocasión no podemos continuar con el proceso. '
                                      '¡Esperamos que pronto encuentres a tu compañero perfecto! 🐾',
                                style: TextStyle(fontSize: 12,
                                    color: Colors.grey.shade700, height: 1.5),
                              ),
                            ),
                          ],
                        ])),
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
