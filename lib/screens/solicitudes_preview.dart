import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/salva_patitas_theme.dart';
import '../widgets/sp_widgets.dart';
import '../widgets/solicitud_piezas.dart';
import '../widgets/avatares.dart';
import '../widgets/estado_error_feed.dart';
import '../widgets/fotos.dart';
import '../widgets/pedir_motivo.dart';
import '../domain/reglas_negocio.dart';
import '../data/contexto_albergue.dart';
import '../data/creator_role.dart';
import '../data/solicitudes_repository.dart';
import 'solicitudes_rescatista_screen.dart'
    show aprobarSolicitud, rechazarSolicitud, textoInicialRechazo;

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
  late final bool _esAlbergue = widget.role == CreatorRole.albergue;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream =
      SolicitudesRepository().paraOwner(
        uid: uidDueno(esAlbergue: _esAlbergue),
        role: widget.role,
        estado: 'pendiente',
      );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: context.sp.primary),
          );
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
          return const SpEmpty(
            title: 'No hay solicitudes por ahora',
            subtitle: 'Cuando alguien quiera adoptar, aparecerá aquí.',
            animal: SpAnimalKind.gato,
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
            final col = colorInicialAdoptante(context.sp, i);
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
                esAlbergue: widget.role == CreatorRole.albergue,
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
  (Color, Color) col,
  String nombre,
  String detalle,
  String tiempo,
  String animal, {
  String? docId,
  Map<String, dynamic>? data,
  bool esAlbergue = false,
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
  Widget infoFila(
    BuildContext ctx,
    IconData icono,
    String label,
    String valor,
  ) {
    final c = ctx.sp;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: c.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icono, size: 16, color: c.primaryStrong),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: c.inkMuted),
            ),
          ),
          Text(
            valor,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c.ink,
            ),
          ),
        ],
      ),
    );
  }

  return Builder(
    builder: (ctx) => GestureDetector(
      onTap: docId == null
          ? null
          : () => showModalBottomSheet(
              context: ctx,
              isScrollControlled: true,
              backgroundColor: ctx.sp.surface,
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
                            color: ctx.sp.line,
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
                            backgroundColor: col.$1,
                            textColor: col.$2,
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
                                          color: ctx.sp.inkMuted,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    SolicitudTipoPill(esHogar: esHogar),
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
                        SolicitudFechasHogar(
                          inicio: fechaInicio,
                          fin: fechaFin,
                          dias: diasHogar,
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (data != null)
                        SolicitudCompatibilidad(solicitud: data),
                      const SizedBox(height: 20),
                      Text(
                        'Perfil del adoptante',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: ctx.sp.inkMuted,
                        ),
                      ),
                      const SizedBox(height: 10),
                      infoFila(
                        ctx,
                        Icons.home_outlined,
                        'Vivienda',
                        data?['vivienda'] ?? '-',
                      ),
                      infoFila(
                        ctx,
                        Icons.schedule_rounded,
                        'Horas fuera al día',
                        data?['horasFuera'] ?? '-',
                      ),
                      infoFila(
                        ctx,
                        Icons.group_outlined,
                        'Personas en casa',
                        data?['integrantes'] ?? '-',
                      ),
                      infoFila(
                        ctx,
                        Icons.child_care_outlined,
                        'Niños menores de 8 años',
                        (data?['tieneNinos'] as bool? ?? false) ? 'Sí' : 'No',
                      ),
                      infoFila(
                        ctx,
                        Icons.pets_rounded,
                        'Otras mascotas',
                        (data?['tieneMascotas'] as bool? ?? false)
                            ? 'Sí'
                            : 'No',
                      ),
                      infoFila(
                        ctx,
                        Icons.school_outlined,
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
                            color: ctx.sp.inkMuted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: ctx.sp.surfaceSunken,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${data!['motivacion']}',
                            style: TextStyle(
                              fontSize: 13,
                              color: ctx.sp.inkMuted,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      // Modo equipo (fase 2): aprobar y rechazar es de la
                      // responsable; las reglas tampoco lo dejan.
                      if (esAlbergue && SesionEquipo.activa)
                        Text(
                          'Aprobar o rechazar lo decide la responsable del albergue.',
                          style: TextStyle(fontSize: 13, color: ctx.sp.inkMuted, fontWeight: FontWeight.w600),
                        )
                      else
                      Row(
                        children: [
                          Expanded(
                            child: SpButton(
                              label: 'Aprobar',
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
                                      SnackBar(
                                        backgroundColor: ctx.sp.msgAdvertencia,
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
                                        backgroundColor: ctx.sp.msgError,
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
                                      SnackBar(
                                        backgroundColor: ctx.sp.msgAdvertencia,
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
                                        backgroundColor: ctx.sp.msgError,
                                        content: Text(
                                          'No se pudo aprobar la solicitud: $e',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SpButton(
                              label: 'Rechazar',
                              peligro: true,
                              // pedirMotivo (widgets/pedir_motivo.dart) es dueño de su propio
                              // TextEditingController. Antes se creaba acá y se liberaba
                              // con .then() sobre el showDialog, que se completa ANTES
                              // de que el diálogo termine de cerrarse — el campo se
                              // desmontaba sobre un controller ya destruido y Flutter
                              // pintaba su pantalla roja de error. Ver el detalle
                              // completo en pedirMotivo.
                              onTap: () async {
                                final inicial = await textoInicialRechazo(
                                  animal,
                                  esAlbergue: esAlbergue,
                                );
                                if (!ctx.mounted) return;
                                final motivo = await pedirMotivo(
                                  ctx,
                                  titulo: 'Mensaje de rechazo',
                                  textoInicial: inicial,
                                  maxLines: 5,
                                  colorConfirmar: ctx.sp.danger,
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
                                      SnackBar(
                                        backgroundColor: ctx.sp.msgAdvertencia,
                                        content: Text(
                                          'Ya se está procesando esta solicitud.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  if (!avisoOk) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                        backgroundColor: ctx.sp.msgAdvertencia,
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
                                        backgroundColor: ctx.sp.msgError,
                                        content: Text(
                                          'No se pudo rechazar la solicitud: $e',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
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
        padding: const EdgeInsets.all(14),
        decoration: SpDeco.card(ctx.sp),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AvatarUsuario(
                  userId: adoptanteId,
                  inicial: ini,
                  backgroundColor: col.$1,
                  textColor: col.$2,
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
                        style: TextStyle(fontSize: 12, color: ctx.sp.inkMuted),
                      ),
                    ],
                  ),
                ),
                Text(
                  tiempo,
                  style: TextStyle(fontSize: 12, color: ctx.sp.inkMuted),
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
                      color: ctx.sp.surfaceSunken,
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
                                      color: ctx.sp.peach,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Icon(
                                      Icons.pets,
                                      size: 18,
                                      color: ctx.sp.peachInk,
                                    ),
                                  ),
                                )
                              : Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: ctx.sp.peach,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(
                                    Icons.pets,
                                    size: 18,
                                    color: ctx.sp.peachInk,
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
                SolicitudTipoPill(esHogar: esHogar),
              ],
            ),
            if (docId != null) ...[
              const SizedBox(height: 12),
              Text(
                'Revisar →',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: ctx.sp.primaryStrong,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
