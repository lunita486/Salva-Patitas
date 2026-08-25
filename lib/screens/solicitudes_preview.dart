import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import '../widgets/avatares.dart';
import '../widgets/estado_error_feed.dart';
import '../widgets/fotos.dart';
import '../widgets/pedir_motivo.dart';
import '../domain/compatibilidad.dart';
import '../domain/reglas_negocio.dart';
import '../data/creator_role.dart';
import '../data/solicitudes_repository.dart';
import 'solicitudes_rescatista_screen.dart'
    show aprobarSolicitud, rechazarSolicitud;

/// Vista previa de las últimas 3 solicitudes pendientes, para el panel del
/// rescatista y el del albergue — antes esto solo existía en el panel del
/// rescatista (home_screen.dart); el del albergue apenas mostraba un
/// contador sin ninguna tarjeta, sin ninguna razón de diseño detrás, solo
/// porque nunca se construyó ahí. Se comparte acá para que ambos paneles se
/// comporten igual y un arreglo futuro (como el de aprobar/rechazar) no
/// tenga que aplicarse dos veces.
class SolicitudesPreview extends StatefulWidget {
  final CreatorRole role;
  const SolicitudesPreview({super.key, required this.role});
  @override
  State<SolicitudesPreview> createState() => _SolicitudesPreviewState();
}

class _SolicitudesPreviewState extends State<SolicitudesPreview> {
  // `late final`, no un `.snapshots()` armado dentro de build() — mismo
  // patrón, y mismo síntoma, que el arreglo de mis_rescates_screen.dart:
  // esta tarjeta vive en el panel principal (home_screen.dart), que se
  // redibuja seguido por motivos que no tienen nada que ver con esta
  // tarjeta (otros StreamBuilder del mismo panel emitiendo). Cada
  // redibujado recreaba la consulta, y la nueva suscripción podía mostrar
  // un instante de caché local vieja antes de que llegara el dato fresco
  // — la foto/nombre del animal en "Para [animal]" quedaba pegada a la
  // versión de cuando se mandó la solicitud. Hallazgo real de Eliza:
  // cambió la foto de "Cosita" y la tarjeta de esta vista previa la
  // siguió mostrando vieja (y con el nombre de otro animal, "Hermoso").
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream =
      SolicitudesRepository().paraOwner(
        uid: FirebaseAuth.instance.currentUser?.uid ?? '',
        role: widget.role,
        estado: 'pendiente',
      );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: appTeal));
        }
        // Sin esto, un error real se veía igual que "No hay solicitudes
        // por ahora" — mismo patrón ya arreglado en favoritos_screen.dart
        // y otras pantallas (errorFeedState, widgets/estado_error_feed.dart), acá en la vista
        // previa que comparten los paneles de rescatista y albergue
        // (hallazgo de auditoría de código).
        if (snap.hasError) return errorFeedState();
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
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                'No hay solicitudes por ahora.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
            ),
          );
        }
        final limited = docs.take(3).toList();
        return Column(
          children: List.generate(limited.length, (i) {
            final d = limited[i].data();
            // "Sin nombre" es el texto de relleno que usan las pantallas
            // que MUESTRAN un animal sin nombre propio — pero ese mismo
            // texto quedó guardado tal cual en algunas solicitudes viejas
            // (se copiaba el nombre ya resuelto para mostrar, no el dato
            // real). Acá se trata igual que si no hubiera nombre, así no
            // sale "Para Sin nombre" (caso real reportado por Eliza).
            final animal = nombreDeAnimal(
              d['animalNombre'] as String?,
              enFrase: true,
            );
            final nombre = d['nombre'] as String? ?? '';
            final integrantes = d['integrantes'] as String? ?? '';
            final vivienda = d['vivienda'] as String? ?? '';
            final mascotas = (d['tieneMascotas'] as bool? ?? false)
                ? 'con mascotas'
                : 'sin mascotas';
            final ninos = (d['tieneNinos'] as bool? ?? false)
                ? 'con niños'
                : 'sin niños';
            // `apellido` no se escribe NUNCA en `solicitudes` — no existe
            // el campo. Concatenarlo solo dejaba un espacio colgando al
            // final de cada nombre.
            final nombreCompleto = nombre.isNotEmpty
                ? nombre
                : 'Adoptante ${i + 1}';
            final detalle =
                '$vivienda · $integrantes personas · $ninos · $mascotas';
            final ts = d['creadoEn'] as Timestamp?;
            final tiempo = ts != null ? tiempoRelativo(ts.toDate()) : '';
            final ini = nombreCompleto.isNotEmpty
                ? nombreCompleto[0].toUpperCase()
                : 'A';
            final col = i.isEven ? appTeal : appOrange;
            return Padding(
              // Key por doc.id: sin esto, si la lista de pendientes cambia
              // de orden (nueva solicitud, o una se aprueba/rechaza y sale
              // de acá), Flutter puede reusar el State de AvatarUsuario de
              // OTRA solicitud para esta posición, mostrando la foto de un
              // adoptante equivocado (el `late final` de ese Future no se
              // recalcula solo porque cambió el userId de afuera).
              key: ValueKey(limited[i].id),
              padding: EdgeInsets.only(bottom: i < limited.length - 1 ? 10 : 0),
              child: _solicitudDetalle(
                ini,
                col,
                nombreCompleto,
                detalle,
                tiempo,
                animal,
                docId: limited[i].id,
                data: d,
              ),
            );
          }),
        );
      },
    );
  }
}

Widget _solicitudDetalle(

  String ini,
  Color col,
  String nombre,
  String detalle,
  String tiempo,
  String animal, {
  String? docId,
  Map<String, dynamic>? data,
}) {
  final tipo = data?['tipoSolicitud'] as String? ?? 'adopcion';
  final esHogar = tipo == 'hogar_de_paso';
  final adoptanteId = data?['adoptanteId'] as String?;
  final fechaInicio = (data?['fechaInicioHogar'] as Timestamp?)?.toDate();
  final fechaFin = (data?['fechaFinHogar'] as Timestamp?)?.toDate();
  // +1: rango INCLUSIVO de ambas puntas — elegir el mismo día como inicio y
  // fin significa "un día de hogar de paso", no cero. Con la resta sola
  // (exclusiva, cuenta noches entre fechas) ese caso mostraba "0 días",
  // que se lee como un error aunque la persona haya elegido bien. Hallazgo
  // real de Eliza.
  final diasHogar = (fechaInicio != null && fechaFin != null)
      ? fechaFin.difference(fechaInicio).inDays + 1
      : null;
  final fotoUrl = data?['fotoUrl'] as String?;
  final score = data != null ? calcularCompatibilidad(data) : -1;
  final scoreColor = score >= 80
      ? appTeal
      : score >= 60
      ? const Color(0xFFE65100)
      : const Color(0xFFB71C1C);

  Widget infoFila(String emoji, String label, String valor) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 15)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
        ),
        Text(
          valor,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: appInk,
          ),
        ),
      ],
    ),
  );

  return Builder(
    builder: (ctx) => GestureDetector(
      onTap: docId == null
          ? null
          : () => showModalBottomSheet(
              context: ctx,
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              builder: (_) => DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.7,
                maxChildSize: 0.92,
                minChildSize: 0.4,
                builder: (_, scrollCtl) => SingleChildScrollView(
                  controller: scrollCtl,
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          AvatarUsuario(
                            userId: adoptanteId,
                            inicial: ini,
                            backgroundColor: col,
                            radius: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nombre,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    // Flexible + ellipsis: mismo motivo que
                                    // la tarjeta de la vista previa — un
                                    // nombre de animal largo no debe
                                    // empujar el chip de al lado fuera del
                                    // ancho disponible.
                                    Flexible(
                                      child: Text(
                                        'Para $animal',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: esHogar
                                            ? appTeal.withValues(alpha: 0.12)
                                            : appOrange.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: esHogar
                                              ? appTeal.withValues(alpha: 0.4)
                                              : appOrange.withValues(
                                                  alpha: 0.4,
                                                ),
                                        ),
                                      ),
                                      child: Text(
                                        esHogar
                                            ? '🏡 Hogar de paso'
                                            : '🏠 Adopción',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: esHogar ? appTeal : appOrange,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (esHogar &&
                          fechaInicio != null &&
                          fechaFin != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: appTeal.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: appTeal.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_today,
                                size: 13,
                                color: appTeal,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${fechaInicio.day}/${fechaInicio.month}/${fechaInicio.year} → ${fechaFin.day}/${fechaFin.month}/${fechaFin.year}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: appTeal,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '$diasHogar días',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: appTeal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (score >= 0)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: scoreColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: scoreColor.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                score >= 80
                                    ? '✅'
                                    : score >= 60
                                    ? '⚠️'
                                    : '❌',
                                style: const TextStyle(fontSize: 18),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      score >= 80
                                          ? 'Perfil ideal ($score%)'
                                          : score >= 60
                                          ? 'Perfil aceptable ($score%)'
                                          : 'No recomendado ($score%)',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: scoreColor,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    if (data != null)
                                      ...explicarCompatibilidad(data).map(
                                        (r) => Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 3,
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                r.$2 ? '✓' : '✗',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: r.$2
                                                      ? appTeal
                                                      : Colors.red.shade400,
                                                ),
                                              ),
                                              const SizedBox(width: 5),
                                              Expanded(
                                                child: Text(
                                                  r.$1,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: r.$2
                                                        ? Colors.grey.shade700
                                                        : Colors.red.shade600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 20),
                      Text(
                        'Perfil del adoptante',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      infoFila('🏠', 'Vivienda', data?['vivienda'] ?? '-'),
                      infoFila(
                        '⏰',
                        'Horas fuera al día',
                        data?['horasFuera'] ?? '-',
                      ),
                      infoFila(
                        '👥',
                        'Personas en casa',
                        data?['integrantes'] ?? '-',
                      ),
                      infoFila(
                        '👶',
                        'Niños menores de 8 años',
                        (data?['tieneNinos'] as bool? ?? false) ? 'Sí' : 'No',
                      ),
                      infoFila(
                        '🐾',
                        'Otras mascotas',
                        (data?['tieneMascotas'] as bool? ?? false)
                            ? 'Sí'
                            : 'No',
                      ),
                      infoFila(
                        '📚',
                        'Experiencia previa',
                        (data?['experienciaPrevia'] as bool? ?? false)
                            ? 'Sí'
                            : 'No, primera mascota',
                      ),
                      if (data?['motivacion'] != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Motivación',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${data!['motivacion']}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () async {
                                Navigator.pop(ctx);
                                if (data == null) return;
                                try {
                                  final resultado = await aprobarSolicitud(
                                    docId,
                                    data,
                                  );
                                  if (!ctx.mounted) return;
                                  // null = ya se estaba procesando esta misma solicitud
                                  // desde la lista completa (u otra vista previa) al
                                  // mismo tiempo — candado compartido, ver
                                  // aprobarSolicitud en solicitudes_rescatista_screen.dart.
                                  if (resultado == null) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      const SnackBar(
                                        backgroundColor: msgAdvertencia,
                                        content: Text(
                                          'Ya se está procesando esta solicitud.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  if (!resultado.aprobada) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                        backgroundColor: msgError,
                                        content: Text(
                                          resultado.animalEliminado
                                              ? 'Este animal ya no existe (fue eliminado). La solicitud se rechazó automáticamente.'
                                              : 'Este animal ya tenía un proceso aprobado con otro adoptante. '
                                                    'Esta solicitud se rechazó automáticamente.',
                                        ),
                                      ),
                                    );
                                  } else if (!resultado.avisoOk) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      const SnackBar(
                                        backgroundColor: msgAdvertencia,
                                        content: Text(
                                          'Solicitud aprobada, pero no pudimos avisarle al adoptante por chat. Escribile manualmente.',
                                        ),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                        backgroundColor: msgError,
                                        content: Text(
                                          'No se pudo aprobar la solicitud: $e',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: appTeal,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Aprobar',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GestureDetector(
                              // pedirMotivo (widgets/pedir_motivo.dart) es dueño de su propio
                              // TextEditingController. Antes se creaba acá y se liberaba
                              // con .then() sobre el showDialog, que se completa ANTES
                              // de que el diálogo termine de cerrarse — el campo se
                              // desmontaba sobre un controller ya destruido y Flutter
                              // pintaba su pantalla roja de error. Ver el detalle
                              // completo en pedirMotivo.
                              onTap: () async {
                                final motivo = await pedirMotivo(
                                  ctx,
                                  titulo: 'Mensaje de rechazo',
                                  textoInicial:
                                      'Hola, gracias por tu interés en adoptar a $animal. '
                                      'Luego de revisar tu solicitud, en esta ocasión no podemos continuar con el proceso. '
                                      '¡Esperamos que pronto encuentres a tu compañero perfecto! 🐾',
                                  maxLines: 5,
                                  colorConfirmar: Colors.red,
                                  radioDialogo: 16,
                                  radioCampo: 10,
                                );
                                if (motivo == null || !ctx.mounted) return;
                                Navigator.pop(ctx);
                                if (data == null) return;
                                try {
                                  final avisoOk = await rechazarSolicitud(
                                    docId,
                                    data,
                                    motivo,
                                  );
                                  if (!ctx.mounted) return;
                                  if (avisoOk == null) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      const SnackBar(
                                        backgroundColor: msgAdvertencia,
                                        content: Text(
                                          'Ya se está procesando esta solicitud.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  if (!avisoOk) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      const SnackBar(
                                        backgroundColor: msgAdvertencia,
                                        content: Text(
                                          'Solicitud rechazada, pero no pudimos avisarle al adoptante por chat.',
                                        ),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                        backgroundColor: msgError,
                                        content: Text(
                                          'No se pudo rechazar la solicitud: $e',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.red.shade300,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Rechazar',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.red.shade400,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AvatarUsuario(
                  userId: adoptanteId,
                  inicial: ini,
                  backgroundColor: col,
                  radius: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detalle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  tiempo,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // Flexible (no Expanded): un nombre de animal corto sigue
                // ocupando solo lo que necesita, pero uno largo se achica
                // en vez de empujar el chip "Adopción"/"Hogar de paso" (el
                // hermano de al lado) fuera del ancho de la tarjeta —
                // hallazgo real de Eliza, "right overflow" con un nombre
                // largo al pedir adopción.
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD8F0E4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: fotoUrl != null
                              ? FotoUrl(
                                  url: fotoUrl,
                                  width: 32,
                                  height: 32,
                                  fit: BoxFit.cover,
                                  alignment: Alignment.topCenter,
                                  fallback: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: Colors.brown.shade300,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Icon(
                                      Icons.pets,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                  ),
                                )
                              : Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: Colors.brown.shade300,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(
                                    Icons.pets,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Para $animal',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: esHogar
                        ? appTeal.withValues(alpha: 0.12)
                        : appOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: esHogar
                          ? appTeal.withValues(alpha: 0.4)
                          : appOrange.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    esHogar ? '🏡 Hogar de paso' : '🏠 Adopción',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: esHogar ? appTeal : appOrange,
                    ),
                  ),
                ),
              ],
            ),
            if (docId != null) ...[
              const SizedBox(height: 12),
              const Text(
                'Revisar →',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: appTeal,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
