import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/chats_repository.dart';
import '../data/rescates_repository.dart';
import '../data/solicitudes_repository.dart';
import '../theme.dart';
import 'pedir_motivo.dart';

// ─── Cambiar Estado Adopción Sheet ────────────────────────────────────────────

class CambiarEstadoSheet extends StatelessWidget {
  final String docId;
  final String estadoActual;
  final String nombre;
  final String? adoptanteIdEnProceso;
  const CambiarEstadoSheet({
    super.key,
    required this.docId,
    required this.estadoActual,
    this.nombre = '',
    this.adoptanteIdEnProceso,
  });

  /// Único punto de escritura del estado — pasa por
  /// [RescatesRepository.cambiarEstadoAdopcion] (ver ARCHITECTURE.md) y
  /// avisa si falla, en vez del `.update()` suelto y sin manejar de antes
  /// (si fallaba, el sheet ya se había cerrado como si hubiera funcionado,
  /// sin ningún aviso).
  Future<bool> _actualizarEstado(
    BuildContext context,
    String nuevoEstado, {
    Map<String, dynamic> extra = const {},
  }) async {
    try {
      await RescatesRepository().cambiarEstadoAdopcion(
        docId,
        nuevoEstado,
        extra: extra,
      );
      return true;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: msgError,
            content: Text('No se pudo actualizar el estado. Intentá de nuevo.'),
          ),
        );
      }
      return false;
    }
  }

  /// Avisa que el animal falleció — al adoptante EN PROCESO (solicitud ya
  /// aprobada) si hay uno, y a TODOS los que todavía tengan una solicitud
  /// PENDIENTE para este animal. Devuelve `false` si algún aviso no se
  /// pudo dejar (el cambio de estado en sí ya se guardó aparte y no se
  /// deshace por esto), para que quien lo llama pueda decirlo en pantalla
  /// en vez de que se pierda en silencio.
  ///
  /// **Antes solo avisaba al adoptante en proceso — hallazgo real de
  /// Eliza.** `adoptanteIdEnProceso` solo se completa cuando una solicitud
  /// se APRUEBA (ver `solicitudes_rescatista_screen.dart`); un animal
  /// marcado fallecido con solicitudes todavía pendientes (nunca
  /// aprobadas, el caso más común con un animal recién publicado) dejaba a
  /// esas personas sin ningún aviso — no porque algo fallara, sino porque
  /// nadie llegaba a estar registrado como destinatario.
  ///
  /// Todo el trabajo real (buscar el chat, crearlo si hace falta, escribir
  /// el mensaje) lo hace `ChatsRepository.avisarSobreAnimal` — única fuente
  /// para toda la app, ver su doc para el detalle completo de por qué
  /// también hacía falta poder CREAR el chat acá (antes esta función solo
  /// buscaba uno existente, y una solicitud recién mandada muchas veces
  /// todavía no tiene ningún chat abierto).
  Future<bool> _avisarAdoptanteFallecido(String nota) async {
    if (nombre.isEmpty) return true;
    final miUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (miUid.isEmpty) return true;

    // A quién avisar: el adoptante ya aprobado (si hay) + todos los que
    // todavía esperan respuesta. Un Map por adoptanteId, no una lista, para
    // no mandarle el aviso dos veces a la misma persona si por algún motivo
    // aparece en los dos grupos.
    final porAvisar = <String, String>{}; // adoptanteId -> su nombre
    if ((adoptanteIdEnProceso ?? '').isNotEmpty) {
      porAvisar[adoptanteIdEnProceso!] = 'Adoptante';
    }
    try {
      final pendientes = await SolicitudesRepository().pendientesPara(
        rescateId: docId,
        rescatistaId: miUid,
      );
      for (final s in pendientes) {
        final id = s['adoptanteId'] as String? ?? '';
        if (id.isEmpty) continue;
        porAvisar.putIfAbsent(
          id,
          () => (s['nombre'] as String?)?.isNotEmpty == true
              ? s['nombre'] as String
              : 'Adoptante',
        );
      }
    } catch (_) {
      // Sin señal no se puede saber quién más está esperando — se sigue
      // igual con quien ya se tenía (el adoptante en proceso, si hay), en
      // vez de bloquear TODO el aviso por no poder completar la lista.
    }
    if (porAvisar.isEmpty) return true;

    final texto =
        'Lamentamos informarte que $nombre falleció. '
        'Gracias por tu interés en darle un hogar. 🌈'
        '${nota.isNotEmpty ? '\n\n$nota' : ''}';
    // Nombre propio del rescatista/albergue — solo hace falta si alguno de
    // los avisos de abajo termina creando un chat nuevo. try/catch propio:
    // si esta lectura falla, se sigue con un nombre de respaldo en vez de
    // no avisarle a nadie por no poder resolver este dato secundario.
    var miNombre =
        FirebaseAuth.instance.currentUser?.displayName ?? 'Rescatista';
    try {
      final miDoc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(miUid)
          .get();
      final d = miDoc.data() ?? {};
      if ((d['albergueNombre'] as String?)?.isNotEmpty == true) {
        miNombre = d['albergueNombre'] as String;
      } else if ((d['nombre'] as String?)?.isNotEmpty == true) {
        miNombre = d['nombre'] as String;
      }
    } catch (_) {}

    var todoOk = true;
    for (final entry in porAvisar.entries) {
      final ok = await ChatsRepository().avisarSobreAnimal(
        adoptanteId: entry.key,
        adoptanteNombre: entry.value,
        rescatistaId: miUid,
        rescatista: miNombre,
        texto: texto,
        rescateId: docId,
        animalNombre: nombre,
      );
      if (!ok) todoOk = false;
    }
    return todoOk;
  }

  static const _estados = [
    ('Rescatado', '🟢', 'Disponible para adopción'),
    ('Hogar de paso', '🟣', 'Temporalmente con un cuidador'),
    ('En proceso de adopción', '🟠', 'Tiene una solicitud activa'),
    ('Adoptado', '🔵', 'Ya encontró su hogar'),
    ('Regresado', '🔴', 'Fue devuelto, disponible de nuevo'),
    ('Fallecido', '🌈', 'Ya no está con nosotros'),
  ];

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Estado del animal',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Toca para cambiar el estado',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 16),
        ..._estados.map((e) {
          final sel = e.$1 == estadoActual;
          return GestureDetector(
            onTap: () async {
              if (e.$1 != 'Regresado' && e.$1 != 'Fallecido') {
                final ok = await _actualizarEstado(
                  context,
                  e.$1,
                  extra: {
                    if (e.$1 == 'Adoptado')
                      'fechaAdopcion': FieldValue.serverTimestamp(),
                  },
                );
                if (ok && context.mounted) Navigator.pop(context);
                return;
              }
              final esFallecido = e.$1 == 'Fallecido';
              final sheetCtx = context;
              // El diálogo es dueño de su propio TextEditingController (ver
              // _MotivoDialog) y devuelve el texto ya escrito. Antes el
              // controller se creaba acá y se liberaba con
              // `.then((_) => ctrl.dispose())` sobre el showDialog — y ese
              // Future se completa apenas se llama Navigator.pop, NO cuando
              // el diálogo termina de cerrarse. O sea que el controller se
              // destruía mientras el TextField todavía estaba en pantalla
              // animándose hacia afuera; al desmontarse, ese TextField
              // intentaba soltar su listener sobre un controller ya
              // destruido y Flutter lanzaba "A TextEditingController was
              // used after being disposed", pintando su pantalla roja de
              // error por lo que durara la animación de cierre. Hallazgo
              // real de Eliza cambiando un animal a 'Regresado': "salió un
              // mensaje rojo feo con letras amarillas así súper rápido y
              // luego cambió el estado".
              //
              // Con el controller adentro de un State, Flutter lo libera
              // exactamente cuando corresponde (al desmontarse el widget que
              // lo usa), sin que nadie tenga que adivinar el momento.
              final motivo = await pedirMotivo(
                context,
                titulo: esFallecido
                    ? 'Lo sentimos mucho 🌈'
                    : '¿Por qué fue regresado?',
                hint: esFallecido
                    ? 'Puedes dejar una nota sobre este angelito...'
                    : 'Ej: Incompatibilidad con otros animales, mudanza...',
                etiquetaConfirmar: 'Guardar',
                colorConfirmar: esFallecido
                    ? const Color(0xFF78909C)
                    : const Color(0xFFD32F2F),
                confirmarRelleno: true,
                autofocus: true,
              );
              // null = cerró con Cancelar (o tocando afuera): no se cambia
              // nada. Un texto vacío SÍ es una respuesta válida — el motivo
              // nunca fue obligatorio.
              if (motivo == null) return;
              final ok = await _actualizarEstado(
                sheetCtx,
                e.$1,
                extra: {
                  if (esFallecido && motivo.isNotEmpty)
                    'notaFallecido': motivo
                  else if (!esFallecido)
                    'motivoRegreso': motivo,
                },
              );
              // await, no fire-and-forget: antes esta llamada salía sin
              // await y sin catch, así que si el aviso fallaba (sin señal, o
              // el chat no existía) la excepción quedaba suelta y nadie se
              // enteraba de que el adoptante nunca recibió la noticia.
              // Hallazgo de auditoría de código.
              var avisoOk = true;
              if (esFallecido && ok) {
                avisoOk = await _avisarAdoptanteFallecido(motivo);
              }
              if (!avisoOk && sheetCtx.mounted) {
                ScaffoldMessenger.of(sheetCtx).showSnackBar(
                  const SnackBar(
                    backgroundColor: msgAdvertencia,
                    content: Text(
                      'El estado se guardó, pero no pudimos avisarle '
                      'al adoptante. Escribile por el chat.',
                    ),
                  ),
                );
              }
              if (ok && sheetCtx.mounted) Navigator.pop(sheetCtx);
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: sel
                    ? cicloColor(e.$1).withValues(alpha: 0.1)
                    : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: sel ? cicloColor(e.$1) : Colors.grey.shade200,
                  width: sel ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Text(e.$2, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.$1,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: sel ? cicloColor(e.$1) : appInk,
                          ),
                        ),
                        Text(
                          e.$3,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (sel)
                    Icon(Icons.check_circle, color: cicloColor(e.$1), size: 20),
                ],
              ),
            ),
          );
        }),
      ],
    ),
  );
}
