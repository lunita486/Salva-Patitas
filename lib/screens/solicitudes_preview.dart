import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import '../compatibilidad.dart';
import '../data/creator_role.dart';
import '../data/solicitudes_repository.dart';
import 'solicitudes_rescatista_screen.dart' show aprobarSolicitud, rechazarSolicitud;

/// Vista previa de las últimas 3 solicitudes pendientes, para el panel del
/// rescatista y el del albergue — antes esto solo existía en el panel del
/// rescatista (home_screen.dart); el del albergue apenas mostraba un
/// contador sin ninguna tarjeta, sin ninguna razón de diseño detrás, solo
/// porque nunca se construyó ahí. Se comparte acá para que ambos paneles se
/// comporten igual y un arreglo futuro (como el de aprobar/rechazar) no
/// tenga que aplicarse dos veces.
class SolicitudesPreview extends StatelessWidget {
  final CreatorRole role;
  const SolicitudesPreview({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: SolicitudesRepository().paraOwner(
        uid: FirebaseAuth.instance.currentUser?.uid ?? '',
        role: role,
        estado: 'pendiente',
      ),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: appTeal));
        }
        final docs = [...(snap.data?.docs ?? [])]
          ..sort((a, b) {
            final ta = a.data()['creadoEn'] as Timestamp?;
            final tb = b.data()['creadoEn'] as Timestamp?;
            if (ta == null || tb == null) return 0;
            return tb.compareTo(ta);
          });
        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Center(child: Text('No hay solicitudes por ahora.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500))),
          );
        }
        final limited = docs.take(3).toList();
        return Column(
          children: List.generate(limited.length, (i) {
            final d = limited[i].data();
            final animal      = d['animalNombre'] as String? ?? 'Animal';
            final nombre      = d['nombre']      as String? ?? '';
            final apellido    = d['apellido']    as String? ?? '';
            final integrantes = d['integrantes'] as String? ?? '';
            final vivienda    = d['vivienda']    as String? ?? '';
            final mascotas    = (d['tieneMascotas'] as bool? ?? false) ? 'con mascotas' : 'sin mascotas';
            final ninos       = (d['tieneNinos']    as bool? ?? false) ? 'con niños' : 'sin niños';
            final nombreCompleto = nombre.isNotEmpty ? '$nombre $apellido' : 'Adoptante ${i + 1}';
            final detalle     = '$vivienda · $integrantes personas · $ninos · $mascotas';
            final ts          = d['creadoEn'] as Timestamp?;
            final tiempo      = ts != null ? _tiempoRelativo(ts.toDate()) : '';
            final ini         = nombreCompleto.isNotEmpty ? nombreCompleto[0].toUpperCase() : 'A';
            final col         = i.isEven ? appTeal : appOrange;
            return Padding(
              padding: EdgeInsets.only(bottom: i < limited.length - 1 ? 10 : 0),
              child: _solicitudDetalle(ini, col, nombreCompleto, detalle, tiempo, animal,
                  docId: limited[i].id, data: d),
            );
          }),
        );
      },
    );
  }

  String _tiempoRelativo(DateTime fecha) {
    final diff = DateTime.now().difference(fecha);
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}min';
    if (diff.inHours < 24)   return 'hace ${diff.inHours}h';
    return 'hace ${diff.inDays}d';
  }
}

/// Avatar del ADOPTANTE que mandó la solicitud. Antes esta tarjeta usaba el
/// mismo helper `_avatar()` del encabezado, que muestra la foto de la
/// cuenta ACTUALMENTE logueada (el rescatista/albergue viendo su propio
/// panel) — así que cada tarjeta de solicitud mostraba la foto de quien la
/// estaba mirando, no la del adoptante real. Mismo patrón de bug que el
/// encabezado del chat (ver chat_screen.dart) — se arregla igual, leyendo
/// usuarios/{adoptanteId}.foto.
class _AvatarAdoptante extends StatefulWidget {
  final String? adoptanteId;
  final String inicial;
  final Color color;
  final double radius;
  const _AvatarAdoptante({required this.adoptanteId, required this.inicial, required this.color, required this.radius});

  @override
  State<_AvatarAdoptante> createState() => _AvatarAdoptanteState();
}

class _AvatarAdoptanteState extends State<_AvatarAdoptante> {
  late final Future<String?> _foto = _cargar();

  Future<String?> _cargar() async {
    final id = widget.adoptanteId;
    if (id == null || id.isEmpty) return null;
    try {
      final doc = await FirebaseFirestore.instance.collection('usuarios').doc(id).get();
      return doc.data()?['foto'] as String?;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: _foto,
    builder: (context, snap) => AvatarPersona(
      fotoUrl: snap.data,
      inicial: widget.inicial,
      radius: widget.radius,
      backgroundColor: widget.color,
      textColor: Colors.white,
    ),
  );
}

Widget _solicitudDetalle(String ini, Color col, String nombre, String detalle,
    String tiempo, String animal, {String? docId, Map<String, dynamic>? data}) {
  final tipo        = data?['tipoSolicitud']    as String? ?? 'adopcion';
  final esHogar     = tipo == 'hogar_de_paso';
  final adoptanteId = data?['adoptanteId']      as String?;
  final fechaInicio = (data?['fechaInicioHogar'] as Timestamp?)?.toDate();
  final fechaFin    = (data?['fechaFinHogar']    as Timestamp?)?.toDate();
  final diasHogar   = (fechaInicio != null && fechaFin != null)
      ? fechaFin.difference(fechaInicio).inDays
      : null;
  final score      = data != null ? calcularCompatibilidad(data) : -1;
  final scoreColor = score >= 80 ? const Color(0xFF1F8A62) : score >= 60 ? const Color(0xFFE65100) : const Color(0xFFB71C1C);

  Widget infoFila(String emoji, String label, String valor) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 15)),
      const SizedBox(width: 8),
      Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600))),
      Text(valor, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
    ]),
  );

  return Builder(builder: (ctx) => GestureDetector(
      onTap: docId == null ? null : () => showModalBottomSheet(
        context: ctx,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.92,
          minChildSize: 0.4,
          builder: (_, scrollCtl) => SingleChildScrollView(
            controller: scrollCtl,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Row(children: [
              _AvatarAdoptante(adoptanteId: adoptanteId, inicial: ini, color: col, radius: 22),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nombre, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Row(children: [
                  Text('Para $animal', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: esHogar ? appTeal.withValues(alpha: 0.12) : appOrange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: esHogar ? appTeal.withValues(alpha: 0.4) : appOrange.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      esHogar ? '🏡 Hogar de paso' : '🏠 Adopción',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                          color: esHogar ? appTeal : appOrange),
                    ),
                  ),
                ]),
              ])),
            ]),
            if (esHogar && fechaInicio != null && fechaFin != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            const SizedBox(height: 16),
            if (score >= 0) Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: scoreColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scoreColor.withValues(alpha: 0.35))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(score >= 80 ? '✅' : score >= 60 ? '⚠️' : '❌', style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(score >= 80 ? 'Perfil ideal ($score%)' : score >= 60 ? 'Perfil aceptable ($score%)' : 'No recomendado ($score%)',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scoreColor)),
                  const SizedBox(height: 8),
                  if (data != null) ...explicarCompatibilidad(data).map((r) => Padding(
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
            const SizedBox(height: 20),
            Text('Perfil del adoptante', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade500)),
            const SizedBox(height: 10),
            infoFila('🏠', 'Vivienda', data?['vivienda'] ?? '-'),
            infoFila('⏰', 'Horas fuera al día', data?['horasFuera'] ?? '-'),
            infoFila('👥', 'Personas en casa', data?['integrantes'] ?? '-'),
            infoFila('👶', 'Niños menores de 8 años', (data?['tieneNinos'] as bool? ?? false) ? 'Sí' : 'No'),
            infoFila('🐾', 'Otras mascotas', (data?['tieneMascotas'] as bool? ?? false) ? 'Sí' : 'No'),
            infoFila('📚', 'Experiencia previa', (data?['experienciaPrevia'] as bool? ?? false) ? 'Sí' : 'No, primera mascota'),
            if (data?['motivacion'] != null) ...[
              const SizedBox(height: 16),
              Text('Motivación', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade500)),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
                child: Text('${data!['motivacion']}', style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.5)),
              ),
            ],
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    Navigator.pop(ctx);
                    if (data == null) return;
                    try {
                      final resultado = await aprobarSolicitud(docId, data);
                      if (!ctx.mounted) return;
                      if (!resultado.aprobada) {
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                            content: Text(resultado.animalEliminado
                                ? 'Este animal ya no existe (fue eliminado) — la solicitud se rechazó automáticamente.'
                                : 'Este animal ya tenía un proceso aprobado con otro adoptante — '
                                    'esta solicitud se rechazó automáticamente.')));
                      } else if (!resultado.avisoOk) {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                            content: Text('Solicitud aprobada, pero no pudimos avisarle al adoptante por chat. Escribile manualmente.')));
                      }
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('No se pudo aprobar la solicitud: $e')));
                      }
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(color: appTeal, borderRadius: BorderRadius.circular(12)),
                    child: const Text('Aprobar', textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    final motivoCtl = TextEditingController(
                      text: 'Hola, gracias por tu interés en adoptar a $animal. '
                          'Luego de revisar tu solicitud, en esta ocasión no podemos continuar con el proceso. '
                          '¡Esperamos que pronto encuentres a tu compañero perfecto! 🐾',
                    );
                    showDialog(context: ctx, builder: (dlg) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: const Text('Mensaje de rechazo'),
                      content: TextField(
                        controller: motivoCtl,
                        maxLines: 5,
                        decoration: InputDecoration(
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
                          onPressed: () async {
                            Navigator.pop(dlg);
                            Navigator.pop(ctx);
                            if (data == null) return;
                            try {
                              final avisoOk = await rechazarSolicitud(docId, data, motivoCtl.text.trim());
                              if (ctx.mounted && !avisoOk) {
                                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                                    content: Text('Solicitud rechazada, pero no pudimos avisarle al adoptante por chat.')));
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(content: Text('No se pudo rechazar la solicitud: $e')));
                              }
                            }
                          },
                          child: const Text('Confirmar', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ));
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(border: Border.all(color: Colors.red.shade300), borderRadius: BorderRadius.circular(12)),
                    child: Text('Rechazar', textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
              ),
            ]),
          ]),
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _AvatarAdoptante(adoptanteId: adoptanteId, inicial: ini, color: col, radius: 20),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 2),
              Text(detalle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ])),
            Text(tiempo, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
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
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: esHogar ? appTeal.withValues(alpha: 0.12) : appOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: esHogar ? appTeal.withValues(alpha: 0.4) : appOrange.withValues(alpha: 0.4)),
              ),
              child: Text(
                esHogar ? '🏡 Hogar de paso' : '🏠 Adopción',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    color: esHogar ? appTeal : appOrange),
              ),
            ),
          ]),
          if (docId != null) ...[
            const SizedBox(height: 12),
            const Text('Revisar →', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: appTeal)),
          ],
        ]),
      ),
    ));
}
