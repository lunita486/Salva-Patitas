import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import '../data/chats_repository.dart';
import '../data/rescates_repository.dart';
import '../data/solicitudes_repository.dart';
import 'animal_detalle_screen.dart';
import 'chat_screen.dart';

class MisSolicitudesScreen extends StatelessWidget {
  const MisSolicitudesScreen({super.key});


  // "Registro del acuerdo de adopción", versión simple: sin firma dibujada
  // ni PDF — un texto genérico de compromiso que el adoptante lee y acepta,
  // guardado con la fecha del servidor dentro de la misma solicitud. Solo
  // para adopción definitiva (no hogar de paso, que ya tiene su propio
  // acuerdo de fechas de inicio/fin).
  Future<void> _mostrarAcuerdo(BuildContext context, String solicitudId, String animal) async {
    final aceptar = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Compromiso de adopción'),
        content: SingleChildScrollView(
          child: Text(
            'Al confirmar, te comprometés a:\n\n'
            '• No revenderlo, regalarlo ni cederlo a otra persona sin avisarle a quien te lo entregó.\n\n'
            '• Si en algún momento no podés seguir teniéndolo, devolverlo a quien te lo dio en adopción, nunca abandonarlo.\n\n'
            '• Darle buen trato, alimentación y atención veterinaria.\n\n'
            'Este es un compromiso de buena fe entre vos y quien te lo entregó, para que $animal tenga un hogar responsable.',
            style: const TextStyle(fontSize: 13.5, height: 1.5),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('Cerrar')),
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: const Text('Acepto estos compromisos', style: TextStyle(color: appTeal, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (aceptar != true) return;
    try {
      await SolicitudesRepository().aceptarAcuerdo(solicitudId);
    } catch (_) {
      // Sin esto, si la escritura fallaba (sin señal, token vencido) la
      // persona no se enteraba: el botón "Ver compromiso de adopción"
      // seguía ahí como si nunca hubiera tocado "Acepto", sin ningún
      // aviso de que hay que reintentar (hallazgo de auditoría de código).
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            backgroundColor: msgError,
            content: Text('No se pudo registrar tu aceptación. Revisá tu conexión e intentá de nuevo.')));
      }
    }
  }

  // Sugerencia real de una tester (Edith): adoptó por la app y no
  // encontraba forma de volver a ver las fotos/ficha del animal desde
  // "Mis solicitudes" — solo se veía la miniatura chiquita de la lista.
  // Funciona igual sin importar el estado (pendiente/aprobada/rechazada):
  // se busca el rescate por su id y se abre la misma ficha completa que
  // usa el resto de la app, no una versión reducida.
  Future<void> _verFicha(BuildContext context, String? rescateId) async {
    if (rescateId == null || rescateId.isEmpty) return;
    final doc = await RescatesRepository().obtener(rescateId);
    if (!context.mounted) return;
    if (!doc.exists) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: msgError,
          content: Text('Este animalito ya no está disponible en la plataforma.')));
      return;
    }
    final d = doc.data()!;
    final nombre = (d['nombre'] as String?)?.isNotEmpty == true ? d['nombre'] as String : 'Sin nombre';
    final animalMap = {
      'nombre':              nombre,
      'especie':             d['especie']        ?? 'Perro',
      'edad':                d['edad']           ?? '',
      'raza':                d['raza']           ?? 'Criolla',
      'tamano':              d['tamano']         ?? 'Mediano',
      'ubicacion':           d['ubicacion']      ?? '',
      'descripcion':         d['descripcion']    ?? '',
      'tags': <String>[
        if (d['okConNinos']    == true) 'Amigable con niños',
        if (d['okConMascotas'] == true) 'Es sociable',
        if ((d['energia'] as String?)?.isNotEmpty == true) d['energia'] as String,
      ],
      'rescatista':          d['rescatistaNombre'] ?? '',
      'rescatistaId':        d['rescatistaId']     ?? '',
      'rescateId':           doc.id,
      'estadoAdopcion':      d['estadoAdopcion']   ?? 'Rescatado',
      'fotoUrl':             d['fotoUrl'],
      'fotoUrl2':            d['fotoUrl2'],
      'latitud':             d['latitud'],
      'longitud':            d['longitud'],
      'energia':             d['energia'],
      'okConNinos':          d['okConNinos'],
      'okConMascotas':       d['okConMascotas'],
      'requiereExperiencia': d['requiereExperiencia'],
      'vacunado':            d['vacunado'],
      'desparasitado':       d['desparasitado'],
      'urgencia':            d['urgencia'] ?? '',
      'creadoPor':           d['creadoPor'] ?? 'rescatista',
    };
    if (!context.mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => AnimalDetalleScreen(animal: animalMap)));
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
                tooltip: 'Volver',
                onPressed: () => Navigator.pop(context),
              ),
              const Expanded(child: Text('Mis solicitudes',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: appInk,
                      fontFamily: 'Baloo2'))),
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
                // Sin esto, un error real se veía igual que "todavía no
                // enviaste solicitudes" — mismo patrón ya arreglado en
                // favoritos_screen.dart y otras pantallas (errorFeedState,
                // theme.dart), acá (hallazgo de auditoría de código).
                if (snap.hasError) return errorFeedState();
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
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: appInk)),
                      const SizedBox(height: 8),
                      Text('Cuando solicites adoptar un animal\naparecerá aquí con su estado.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.5)),
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
                    final fecha      = ts != null ? formatearFecha(ts.toDate()) : '';
                    final fotoUrl       = d['fotoUrl']         as String?;
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
                        ? appTeal
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
                        GestureDetector(
                          onTap: () => _verFicha(context, d['rescateId'] as String?),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            // FotoAnimal en vez de recorte — mismo arreglo
                            // que mis_rescates_screen.dart: el recorte fijo
                            // (topCenter) cortaba animales que no quedan
                            // cerca del borde superior de la foto.
                            child: fotoUrl != null
                                ? FotoAnimal(
                                    url: fotoUrl,
                                    width: 56, height: 56,
                                    fallback: Container(
                                      width: 56, height: 56,
                                      color: appTeal.withValues(alpha: 0.12),
                                      child: const Center(child: Text('🐾', style: TextStyle(fontSize: 26))),
                                    ),
                                  )
                                : Container(
                                    width: 56, height: 56,
                                    color: appTeal.withValues(alpha: 0.12),
                                    child: const Center(child: Text('🐾', style: TextStyle(fontSize: 26))),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(animal, style: const TextStyle(fontSize: 15,
                              fontWeight: FontWeight.bold, color: appInk)),
                          const SizedBox(height: 2),
                          Text(
                            tipo == 'hogar_de_paso' ? '🏡 Hogar de paso' : '🏠 Adopción',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade700,
                                fontWeight: FontWeight.w600),
                          ),
                          if (fecha.isNotEmpty) ...[
                            const SizedBox(height: 1),
                            Text('Enviada el $fecha',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
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
                          if (estado == 'aprobada' && tipo == 'adopcion') ...[
                            const SizedBox(height: 10),
                            (d['acuerdoAceptado'] == true)
                                ? Builder(builder: (_) {
                                    final ts = d['acuerdoAceptadoEn'] as Timestamp?;
                                    return Row(children: [
                                      const Icon(Icons.check_circle, size: 14, color: appTeal),
                                      const SizedBox(width: 5),
                                      Expanded(child: Text(
                                          ts != null
                                              ? 'Compromiso de adopción aceptado el ${formatearFecha(ts.toDate())}'
                                              : 'Compromiso de adopción aceptado',
                                          style: const TextStyle(fontSize: 12, color: appTeal, fontWeight: FontWeight.w600))),
                                    ]);
                                  })
                                : GestureDetector(
                                    onTap: () => _mostrarAcuerdo(context, docs[i].id, animal),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      decoration: BoxDecoration(
                                        color: appOrange.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: appOrange.withValues(alpha: 0.35)),
                                      ),
                                      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                        Icon(Icons.assignment_outlined, size: 15, color: appOrange),
                                        SizedBox(width: 6),
                                        Text('Ver compromiso de adopción', style: TextStyle(fontSize: 12.5,
                                            fontWeight: FontWeight.w700, color: appOrange)),
                                      ]),
                                    ),
                                  ),
                          ],
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
                                  Text('📅 ${formatearFecha(fechaInicio)} → ${formatearFecha(fechaFin)}',
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
                                final rescateIdChat = d['rescateId'] as String? ?? '';
                                String? chatId;
                                // try/catch: leer un chat que NO existe da
                                // permission-denied con nuestras reglas — sin
                                // esto la excepción mataba el onTap y el botón
                                // del chat no hacía nada. Con chatId null,
                                // ChatScreen crea el chat al abrirse.
                                try {
                                  if (rescateIdChat.isNotEmpty) {
                                    final doc = await FirebaseFirestore.instance
                                        .collection('chats').doc(ChatsRepository()
                                            .idAnimal(rescateId: rescateIdChat, adoptanteId: uid)).get();
                                    if (doc.exists) chatId = doc.id;
                                  } else {
                                    final snap = await FirebaseFirestore.instance
                                        .collection('chats')
                                        .where('adoptanteId', isEqualTo: uid)
                                        .where('animalNombre', isEqualTo: animal)
                                        .limit(1)
                                        .get();
                                    if (snap.docs.isNotEmpty) chatId = snap.docs.first.id;
                                  }
                                } catch (_) {
                                  chatId = null;
                                }
                                if (!context.mounted) return;
                                final animalMap = {
                                  'nombre':        animal,
                                  'rescatista':    d['rescatistaNombre'] as String? ?? d['rescatista'] as String? ?? 'Rescatista',
                                  'rescatistaId':  d['rescatistaId'] as String? ?? '',
                                  'rescateId':     d['rescateId'] as String? ?? '',
                                  'especie':       d['especie'] as String? ?? 'Perro',
                                  'fotoUrl':       fotoUrl,
                                  'tipoSolicitud': tipo,
                                  'creadoPor':     d['creadoPor'] as String?,
                                  'edad':          '',
                                  'ubicacion':     '',
                                  'descripcion':   '',
                                  'tags':          <String>[],
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
