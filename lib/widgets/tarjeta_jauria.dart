// La tarjeta de un animalito en La Jauría / Mis rescates
// (mis_rescates_screen.dart). Vive en su propio archivo para poder verla
// sola, con cualquier estado, sin pasar por la consulta de la pantalla.
// Lo que depende de la pantalla (borrar, el umbral de "estancado") llega
// por parámetro.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/creator_role.dart';
import '../domain/reglas_negocio.dart';
import '../routing/app_router.dart';
import '../screens/compartir_animal.dart';
import '../screens/solicitudes_rescatista_screen.dart'
    show contactarPersonaEnProceso;
import '../theme/salva_patitas_theme.dart';
import 'cambiar_estado_sheet.dart';
import 'fotos.dart';
import 'sp_widgets.dart';
import 'texto_sin_desborde.dart';

class TarjetaJauria extends StatelessWidget {
  const TarjetaJauria({
    super.key,
    required this.docId,
    required this.d,
    required this.esAlbergue,
    required this.umbralEstancado,
    required this.onEliminar,
  });
  final String docId;
  final Map<String, dynamic> d;
  final bool esAlbergue;
  final int umbralEstancado;

  /// Recibe el nombre ya resuelto del animalito.
  final ValueChanged<String> onEliminar;

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    final nombre = nombreDeAnimal(d['nombre'] as String?);
    final especie = d['especie'] ?? '';
    final estado = d['estado'] ?? '';
    final urgencia = d['urgencia'] ?? '';
    final ubicacion = d['ubicacion'] ?? '';
    // Todos los animales de un mismo albergue comparten la ubicación del
    // perfil del albergue (ver creator_role.dart:esRescateDeAlbergue) — el
    // albergue ya sabe dónde queda su propio refugio, mostrarla repetida en
    // cada tarjeta de "Mis animales" no aporta nada. Pedido real de Eliza.
    final esDeAlbergue = esRescateDeAlbergue(d);
    final fotoUrl = d['fotoUrl'] as String?;
    final fotoUrl2 = d['fotoUrl2'] as String?;
    final estadoAdopcion = d['estadoAdopcion'] as String? ?? 'Rescatado';
    final motivoRegreso = d['motivoRegreso'] as String?;
    final creadoEnTs = d['creadoEn'] as Timestamp?;
    final diasEsperando = creadoEnTs == null
        ? null
        : DateTime.now().difference(creadoEnTs.toDate()).inDays;
    final creadoEnFecha = (d['creadoEn'] as Timestamp?)?.toDate();
    // esEstancado/esEstancadoGrave (domain/reglas_negocio.dart) — mismo criterio que el
    // filtro "Estancados" de arriba, única fuente para las dos.
    final estancado = esEstancado(
      diasEsperando: diasEsperando,
      estadoAdopcion: estadoAdopcion,
      umbral: umbralEstancado,
    );
    final grave = esEstancadoGrave(
      diasEsperando: diasEsperando,
      umbral: umbralEstancado,
    );
    // Pregunta real de Eliza: "tengo 3 animalitos en hogar de paso, ¿cómo
    // veo las fechas en que me los regresan?" — esa fecha va acá en la
    // tarjeta del animal, que es donde de verdad se busca de un vistazo.
    final fechaInicioHogar = (d['fechaInicioHogar'] as Timestamp?)?.toDate();
    final fechaFinHogar = (d['fechaFinHogar'] as Timestamp?)?.toDate();
    final hoySinHora = DateTime.now();
    final diasRestantesHogar = fechaFinHogar != null
        ? DateTime(fechaFinHogar.year, fechaFinHogar.month, fechaFinHogar.day)
              .difference(
                DateTime(hoySinHora.year, hoySinHora.month, hoySinHora.day),
              )
              .inDays
        : null;
    final hogarNombre = (d['hogarDePasoNombre'] as String?) ?? '';
    final hogarContacto = (d['hogarDePasoContacto'] as String?) ?? '';
    final terminado =
        estadoAdopcion == 'Adoptado' || estadoAdopcion == 'Fallecido';
    // "Contactar" solo si hay alguien realmente en proceso con este animal —
    // antes esta pantalla no tenía NINGUNA forma de escribirle a esa persona
    // (el bug real: Eliza aprobó un hogar de paso y no encontró cómo
    // contactarla).
    final puedeContactar =
        (estadoAdopcion == 'Hogar de paso' ||
            estadoAdopcion == 'En proceso de adopción') &&
        (d['adoptanteIdEnProceso'] as String? ?? '').isNotEmpty;
    void compartir() => compartirAnimal(
      context: context,
      nombre: nombre,
      especie: especie,
      edad: d['edad'] as String? ?? '',
      ubicacion: ubicacion,
      tags: <String>[
        if (d['okConNinos'] == true) 'Amigable con niños',
        if (d['okConMascotas'] == true) 'Es sociable',
        if ((d['energia'] as String?)?.isNotEmpty == true)
          d['energia'] as String,
      ],
      fotoUrl: fotoUrl,
      paisCodigo: d['paisCodigo'] as String?,
    );
    void contactar() => contactarPersonaEnProceso(
      context,
      docId: docId,
      nombre: nombre,
      especie: especie,
      fotoUrl: fotoUrl,
      creadoPor: d['creadoPor'] as String?,
      adoptanteIdEnProceso: d['adoptanteIdEnProceso'] as String? ?? '',
    );
    // Blanco dentro de la caja amarilla de hogar de paso; verde cuando va
    // solo sobre la tarjeta blanca (si no, casi no se ve).
    Widget botonContactar({required bool suave}) => Semantics(
      button: true,
      label: 'Contactar a quien está en proceso con $nombre',
      child: SizedBox(
        width: double.infinity,
        child: SpButton(
          label: 'Contactar',
          icon: Icons.chat_bubble_outline_rounded,
          suave: suave,
          onTap: contactar,
        ),
      ),
    );

    return Container(
      key: ValueKey(docId),
      padding: const EdgeInsets.all(12),
      decoration: SpDeco.card(c),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                // Ver ampliada — mismo visor que ya usa el adoptante en el
                // feed (VisorFotoCompleta), pedido de Eliza al notar que acá
                // no existía forma de ver la foto completa.
                onTap: fotoUrl == null
                    ? null
                    : () => context.push(
                        AppRoutes.visorFoto,
                        extra: (
                          fotos: [fotoUrl, if (fotoUrl2 != null) fotoUrl2],
                          indiceInicial: 0,
                        ),
                      ),
                // Foto real cuando hay; si no, el animalito 3D de su especie.
                // FotoAnimal en vez de recorte — el recorte fijo (topCenter)
                // cortaba animales que no quedan cerca del borde superior
                // de la foto (bug real reportado por Eliza con "Chanchis").
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: SpDeco.tone(
                    c,
                    spEspecie(especie as String?).$1,
                    radius: 22,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: fotoUrl != null
                      ? FotoAnimal(
                          url: fotoUrl,
                          width: 96,
                          height: 96,
                          // Miniatura de lista: sin fondo borroso, ver FotoAnimal.
                          fondoBorroso: false,
                          fallback: SpFotoVacia(especie: especie, size: 68),
                        )
                      : SpFotoVacia(especie: especie, size: 68),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 2),
                    Text(
                      nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$especie · $estado',
                      style: SpText.caption.copyWith(
                        color: c.inkMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    // La fecha y no la ciudad: la ubicación se repite tarjeta
                    // tras tarjeta, la fecha es distinta en cada animal
                    // (¿hace cuánto que espera?). Pedido real de Eliza.
                    if (creadoEnFecha != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 13,
                            color: c.primary,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${esDeAlbergue ? 'Ingresó' : 'Rescatado'} el '
                              // El año solo cuando DIFIERE del actual —
                              // mismo criterio que chat_screen.dart.
                              '${formatearFecha(creadoEnFecha, conAnio: creadoEnFecha.year != DateTime.now().year)}',
                              style: SpText.caption.copyWith(
                                color: c.inkMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    // Regresado: el motivo en una línea, sin caja.
                    if (estadoAdopcion == 'Regresado' &&
                        motivoRegreso != null &&
                        motivoRegreso.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Icon(
                              Icons.undo_rounded,
                              size: 14,
                              color: c.inkMuted,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Regresó: $motivoRegreso',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: SpText.caption.copyWith(
                                color: c.inkMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (urgencia != '' || estancado) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (urgencia == 'Alta')
                            const SpBadge('Prioridad alta')
                          else if (urgencia != '')
                            _pildora(
                              context,
                              'Prioridad ${urgencia.toString().toLowerCase()}',
                              urgencia == 'Media' ? SpTone.peach : SpTone.mint,
                            ),
                          // "Estancado": lleva mucho sin encontrar hogar. Antes
                          // era una caja entera con su propio "Compartir en
                          // redes"; ahora es esta píldora y el botón de
                          // compartir de abajo se pinta coral.
                          if (estancado)
                            SpPill(
                              '$diasEsperando días esperando',
                              fondo: grave ? c.dangerSoft : c.accentSoft,
                              tinta: grave ? c.danger : c.accentInk,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          // ── Hogar de paso: con quién, fechas y contactar ───────────────
          if (estadoAdopcion == 'Hogar de paso' && fechaFinHogar != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.butter,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SpAnimal(SpAnimalKind.casa, size: 40),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Quién lo tiene, cuando es un hogar de paso
                            // puesto a mano: esa persona no tiene cuenta en
                            // la app, así que este texto es la única forma
                            // de saber a quién buscar.
                            TextoSinDesborde(
                              texto: hogarNombre.isNotEmpty
                                  ? 'En hogar de paso con $hogarNombre'
                                        '${hogarContacto.isNotEmpty ? ' · $hogarContacto' : ''}'
                                  : 'En hogar de paso',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: c.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text.rich(
                              TextSpan(
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: c.butterInk,
                                ),
                                children: [
                                  if (fechaInicioHogar != null)
                                    TextSpan(
                                      text:
                                          '${formatearFecha(fechaInicioHogar, conAnio: fechaInicioHogar.year != hoySinHora.year)} – ${formatearFecha(fechaFinHogar, conAnio: fechaFinHogar.year != hoySinHora.year)} · ',
                                    ),
                                  TextSpan(
                                    text: diasRestantesHogar! < 0
                                        ? 'vencido hace ${diasRestantesHogar.abs()} días'
                                        : diasRestantesHogar == 0
                                        ? 'vence hoy'
                                        : 'quedan $diasRestantesHogar días',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: diasRestantesHogar < 3
                                          ? c.accentInk
                                          : c.butterInk,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (puedeContactar) ...[
                    const SizedBox(height: 10),
                    botonContactar(suave: true),
                  ],
                ],
              ),
            ),
          ]
          // En proceso de adopción (o hogar de paso sin fechas): Contactar
          // va solo, a todo el ancho.
          else if (puedeContactar) ...[
            const SizedBox(height: 12),
            botonContactar(suave: false),
          ],

          // ── Estado y acciones en una fila ──────────────────────────────
          const SizedBox(height: 12),
          Row(
            children: [
              // Semantics explícito: sin esto, un lector de pantalla
              // anunciaba el texto del estado y la flechita como dos piezas
              // sueltas. Hallazgo de auditoría de código.
              Expanded(
                child: Semantics(
                  button: estadoAdopcion != 'Fallecido',
                  label: estadoAdopcion == 'Fallecido'
                      ? 'Estado: Fallecido'
                      : 'Cambiar estado, actualmente $estadoAdopcion',
                  child: SpStatus(
                    estadoAdopcion,
                    height: 40,
                    onTap: estadoAdopcion == 'Fallecido'
                        ? null
                        : () => showModalBottomSheet(
                            context: context,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(20),
                              ),
                            ),
                            builder: (_) => CambiarEstadoSheet(
                              docId: docId,
                              estadoActual: estadoAdopcion,
                              nombre: nombre,
                              adoptanteIdEnProceso:
                                  d['adoptanteIdEnProceso'] as String?,
                              esAlbergue: esAlbergue,
                            ),
                          ),
                  ),
                ),
              ),
              // 'Adoptado' y 'Fallecido' no comparten, ni se editan ni se
              // eliminan: compartir dice "necesita un hogar" (falso para un
              // adoptado), y son el único registro de ese desenlace (pedido
              // explícito de Eliza). El botón de compartir no depende de que
              // haya foto: sin foto, compartirAnimal() comparte solo el
              // texto (bug real: "el rescatista no tiene forma de
              // compartir").
              //
              // Los demás estados reversibles ('Hogar de paso', 'En proceso
              // de adopción', 'Regresado') sí muestran Eliminar: el chequeo
              // de _eliminarImpl los bloquea con una explicación en vez de
              // escondérselos.
              if (!terminado) ...[
                const SizedBox(width: 8),
                // Mismo ícono que usa el adoptante para compartir
                // (adoptante_feed_screen.dart). En coral si lleva mucho
                // esperando: es la acción que resuelve ese aviso.
                SpMiniButton(
                  icon: Icons.share_outlined,
                  tooltip: 'Compartir',
                  destacado: estancado,
                  onTap: compartir,
                ),
                const SizedBox(width: 6),
                SpMiniButton(
                  icon: Icons.edit_outlined,
                  tooltip: 'Editar',
                  onTap: () => context.push(
                    AppRoutes.editarRescate,
                    extra: (docId: docId, data: d),
                  ),
                ),
                const SizedBox(width: 6),
                SpMiniButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Eliminar',
                  danger: true,
                  onTap: () => onEliminar(nombre),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Píldora pastel chica (`.pill--peach`, etc.).
  Widget _pildora(BuildContext context, String texto, SpTone tono) {
    final k = SpToneColors.of(context.sp, tono);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: k.fill,
        borderRadius: BorderRadius.circular(SpRadius.full),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: k.ink,
        ),
      ),
    );
  }
}
