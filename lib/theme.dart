import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'data/chats_repository.dart';
import 'data/rescates_repository.dart';

// ─── Constantes de color ──────────────────────────────────────────────────────

const appBg     = Color(0xFFDFFBEC);
const appDark   = Color(0xFF162416);
const appTeal   = Color(0xFF1F8A62);
const appOrange = Color(0xFFD84E18);

// ─── Paw print painter ───────────────────────────────────────────────────────

class _PawPrintPainter extends CustomPainter {
  final Color color;
  const _PawPrintPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..style = PaintingStyle.fill;
    double x(double v) => v * size.width  / 100;
    double y(double v) => v * size.height / 100;

    // Main pad — large rounded oval at the bottom
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x(50), y(72)), width: x(54), height: y(46)),
      p,
    );
    // Four toe pads arranged in an arc above the main pad
    canvas.drawOval(Rect.fromCenter(center: Offset(x(16), y(42)), width: x(22), height: y(26)), p);
    canvas.drawOval(Rect.fromCenter(center: Offset(x(37), y(26)), width: x(25), height: y(29)), p);
    canvas.drawOval(Rect.fromCenter(center: Offset(x(63), y(26)), width: x(25), height: y(29)), p);
    canvas.drawOval(Rect.fromCenter(center: Offset(x(84), y(42)), width: x(22), height: y(26)), p);
  }

  @override
  bool shouldRepaint(covariant _PawPrintPainter old) => old.color != color;
}

// ─── Fondo con patitas ────────────────────────────────────────────────────────

Widget _hoja(double w, double op, {bool fx = false, bool fy = false}) =>
  Transform(
    alignment: Alignment.center,
    transform: Matrix4.diagonal3Values(fx ? -1.0 : 1.0, fy ? -1.0 : 1.0, 1.0),
    child: CustomPaint(
      size: Size(w, w),
      painter: _PawPrintPainter(appTeal.withValues(alpha: op * 0.38)),
    ),
  );

class LeafOverlay extends StatelessWidget {
  const LeafOverlay({super.key});
  @override
  Widget build(BuildContext context) => Stack(children: [
    Positioned(top: -28, left: -28,  child: _hoja(170, 0.82)),
    Positioned(top: -28, right: -28, child: _hoja(170, 0.82, fx: true)),
    Positioned(bottom: -28, left: -28,  child: _hoja(140, 0.60, fy: true)),
    Positioned(bottom: -28, right: -28, child: _hoja(140, 0.60, fx: true, fy: true)),
  ]);
}

Widget leafBackground({required Widget child}) => Stack(
  children: [
    Positioned.fill(child: Container(color: appBg)),
    Positioned(top: -28, left: -28,  child: _hoja(170, 0.82)),
    Positioned(top: -28, right: -28, child: _hoja(170, 0.82, fx: true)),
    Positioned(bottom: -28, left: -28,  child: _hoja(140, 0.60, fy: true)),
    Positioned(bottom: -28, right: -28, child: _hoja(140, 0.60, fx: true, fy: true)),
    child,
  ],
);

// ─── Helpers globales ─────────────────────────────────────────────────────────

/// Para cuando un StreamBuilder falla (sin conexión, permiso denegado, etc.)
/// — sin esto, `snap.data?.docs ?? []` hace que la pantalla se vea igual que
/// "no hay nada todavía", confundiendo un error real con una lista vacía.
Widget errorFeedState({String mensaje = 'No se pudo cargar. Revisá tu conexión e intentá de nuevo.'}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        Text(mensaje, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.4)),
      ]),
    ),
  );
}

/// Decodifica un string base64 de forma segura — devuelve `null` en vez de
/// tirar una excepción si el string está corrupto o incompleto (ej. una
/// subida de foto que se cortó a la mitad). Usar antes de armar un
/// `MemoryImage`/`DecorationImage` a mano, para poder caer al fallback
/// (inicial/emoji) en vez de crashear.
Uint8List? bytesFotoSegura(String? base64) {
  if (base64 == null || base64.isEmpty) return null;
  try {
    return base64Decode(base64);
  } catch (_) {
    return null;
  }
}

/// Muestra una foto guardada en base64 de forma segura: si el string está
/// corrupto, o los bytes no son una imagen válida, muestra [fallback] en vez
/// de crashear la pantalla que la contiene. Antes cada pantalla decodificaba
/// `base64Decode(...)` a mano sin ninguna protección — un solo dato corrupto
/// (una subida interrumpida, por ejemplo) tumbaba toda la pantalla.
class FotoSegura extends StatelessWidget {
  final String base64;
  final Widget fallback;
  final double? width;
  final double? height;
  final BoxFit fit;
  const FotoSegura({
    super.key,
    required this.base64,
    required this.fallback,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final bytes = bytesFotoSegura(base64);
    if (bytes == null) return fallback;
    return Image.memory(
      bytes,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

/// Muestra una foto alojada en Firebase Storage (`url`) de forma segura:
/// mientras carga, un indicador liviano; si la red falla o la URL ya no es
/// válida, [fallback] en vez de crashear. Mismo contrato que [FotoSegura]
/// (base64) para minimizar el diff en cada pantalla — se usa para fotos de
/// animales (`rescates`), que viven en Storage y no embebidas en Firestore.
class FotoUrl extends StatelessWidget {
  final String url;
  final Widget fallback;
  final double? width;
  final double? height;
  final BoxFit fit;
  const FotoUrl({
    super.key,
    required this.url,
    required this.fallback,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) => fallback,
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return SizedBox(
          width: width,
          height: height,
          child: const Center(
            child: SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: appTeal),
            ),
          ),
        );
      },
    );
  }
}

/// Avatar de una persona (foto de perfil en base64 o URL). Si la foto falla
/// al cargar, cae a la inicial en vez de romper con una excepción sin
/// manejar o quedar en blanco. Antes esta lógica vivía duplicada como
/// `_AvatarPublicador` solo en el feed del adoptante — el mismo problema
/// (foto que no carga = pantalla rota) aplica a cualquier avatar de foto
/// real, así que se promovió acá para reutilizarla (ej. en el chat).
class AvatarPersona extends StatefulWidget {
  final String? fotoBase64;
  final String? fotoUrl;
  final String inicial;
  final double radius;
  final Color backgroundColor;
  final Color textColor;
  const AvatarPersona({
    super.key,
    this.fotoBase64,
    this.fotoUrl,
    required this.inicial,
    this.radius = 20,
    this.backgroundColor = appTeal,
    this.textColor = Colors.white,
  });

  @override
  State<AvatarPersona> createState() => _AvatarPersonaState();
}

class _AvatarPersonaState extends State<AvatarPersona> {
  bool _falloCarga = false;

  @override
  Widget build(BuildContext context) {
    final fotoBytes = bytesFotoSegura(widget.fotoBase64);
    final ImageProvider? foto = fotoBytes != null
        ? MemoryImage(fotoBytes)
        : widget.fotoUrl != null
            ? NetworkImage(widget.fotoUrl!)
            : null;
    final mostrarFoto = foto != null && !_falloCarga;
    return CircleAvatar(
      backgroundColor: widget.backgroundColor,
      radius: widget.radius,
      backgroundImage: mostrarFoto ? foto : null,
      onBackgroundImageError: mostrarFoto
          ? (_, _) {
              if (mounted) setState(() => _falloCarga = true);
            }
          : null,
      child: !mostrarFoto
          ? Text(widget.inicial,
              style: TextStyle(color: widget.textColor, fontSize: widget.radius * 0.65, fontWeight: FontWeight.bold))
          : null,
    );
  }
}

/// Avatar de OTRO usuario de la app, identificado por su uid — busca su foto
/// en usuarios/{userId}.foto (Google Auth photoURL, sincronizado en
/// main.dart) y cae a la inicial mientras carga o si no tiene. Antes cada
/// pantalla que necesitaba mostrar la foto de una contraparte (encabezado
/// del chat, tarjeta de solicitud, fila de la lista de conversaciones)
/// usaba la foto de la cuenta ACTUALMENTE logueada por error — se centraliza
/// acá para no repetir el mismo bug en cada pantalla nueva.
class AvatarUsuario extends StatefulWidget {
  final String? userId;
  final String inicial;
  final double radius;
  final Color backgroundColor;
  final Color textColor;
  const AvatarUsuario({
    super.key,
    required this.userId,
    required this.inicial,
    this.radius = 20,
    this.backgroundColor = appTeal,
    this.textColor = Colors.white,
  });

  @override
  State<AvatarUsuario> createState() => _AvatarUsuarioState();
}

class _AvatarUsuarioState extends State<AvatarUsuario> {
  late final Future<String?> _foto = _cargar();

  Future<String?> _cargar() async {
    final id = widget.userId;
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
      backgroundColor: widget.backgroundColor,
      textColor: widget.textColor,
    ),
  );
}

Color cicloColor(String s) => switch (s) {
  'En cuidado'             => appTeal,
  'Rescatado'              => appTeal,
  'Hogar de paso'          => const Color(0xFF7C6FCD),
  'En proceso de adopción' => const Color(0xFFE65100),
  'Adoptado'               => const Color(0xFF2196F3),
  'Regresado'              => const Color(0xFFD32F2F),
  'Fallecido'              => const Color(0xFF78909C),
  _                        => Colors.grey,
};

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
  Future<bool> _actualizarEstado(BuildContext context, String nuevoEstado, {
    Map<String, dynamic> extra = const {},
  }) async {
    try {
      await RescatesRepository().cambiarEstadoAdopcion(docId, nuevoEstado, extra: extra);
      return true;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo actualizar el estado. Intentá de nuevo.')));
      }
      return false;
    }
  }

  Future<void> _avisarAdoptanteFallecido(String nota) async {
    final adoptanteId = adoptanteIdEnProceso;
    if (adoptanteId == null || adoptanteId.isEmpty || nombre.isEmpty) return;
    // docId es el id único del rescate (el mismo animal), así que el chat se
    // ubica directo por id en vez de buscarlo por nombre (que puede repetirse).
    final chatDoc = await FirebaseFirestore.instance.collection('chats')
        .doc(ChatsRepository().idAnimal(rescateId: docId, adoptanteId: adoptanteId)).get();
    String? chatId = chatDoc.exists ? chatDoc.id : null;
    if (chatId == null) {
      final chats = await FirebaseFirestore.instance.collection('chats')
          .where('adoptanteId', isEqualTo: adoptanteId)
          .where('animalNombre', isEqualTo: nombre)
          .limit(1).get();
      if (chats.docs.isEmpty) return;
      chatId = chats.docs.first.id;
    }
    final n = DateTime.now();
    final hora = '${n.hour}:${n.minute.toString().padLeft(2, '0')}';
    final texto = 'Lamentamos informarte que $nombre falleció. '
        'Gracias por tu interés en darle un hogar. 🌈'
        '${nota.isNotEmpty ? '\n\n$nota' : ''}';
    await FirebaseFirestore.instance.collection('chats').doc(chatId)
        .collection('mensajes').add({
      'texto': texto, 'emisor': 'rescatista', 'hora': hora,
      'creadoEn': FieldValue.serverTimestamp(),
    });
    await FirebaseFirestore.instance.collection('chats').doc(chatId).update({
      'ultimoMensaje': texto, 'ultimaHora': hora,
      'ultimoMensajeEn': FieldValue.serverTimestamp(),
      'noLeidosAdoptante': FieldValue.increment(1),
    });
  }

  static const _estados = [
    ('Rescatado',              '🟢', 'Disponible para adopción'),
    ('Hogar de paso',          '🟣', 'Temporalmente con un cuidador'),
    ('En proceso de adopción', '🟠', 'Tiene una solicitud activa'),
    ('Adoptado',               '🔵', 'Ya encontró su hogar'),
    ('Regresado',              '🔴', 'Fue devuelto, disponible de nuevo'),
    ('Fallecido',              '🌈', 'Ya no está con nosotros'),
  ];

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Center(child: Container(width: 36, height: 4,
          decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
      const SizedBox(height: 16),
      const Text('Estado del animal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text('Toca para cambiar el estado', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
      const SizedBox(height: 16),
      ..._estados.map((e) {
        final sel = e.$1 == estadoActual;
        return GestureDetector(
          onTap: () async {
            if (e.$1 != 'Regresado' && e.$1 != 'Fallecido') {
              final ok = await _actualizarEstado(context, e.$1, extra: {
                if (e.$1 == 'Adoptado') 'fechaAdopcion': FieldValue.serverTimestamp(),
              });
              if (ok && context.mounted) Navigator.pop(context);
              return;
            }
            final esFallecido = e.$1 == 'Fallecido';
            final ctrl = TextEditingController();
            final sheetCtx = context;
            showDialog(
              context: context,
              builder: (dlgCtx) => AlertDialog(
                title: Text(esFallecido ? 'Lo sentimos mucho 🌈' : '¿Por qué fue regresado?'),
                content: TextField(
                  controller: ctrl,
                  maxLines: 3,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: esFallecido
                        ? 'Puedes dejar una nota sobre este angelito...'
                        : 'Ej: Incompatibilidad con otros animales, mudanza...',
                    border: const OutlineInputBorder(),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dlgCtx),
                    child: const Text('Cancelar'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: esFallecido
                            ? const Color(0xFF78909C)
                            : const Color(0xFFD32F2F)),
                    onPressed: () async {
                      final motivo = ctrl.text.trim();
                      Navigator.pop(dlgCtx);
                      final ok = await _actualizarEstado(sheetCtx, e.$1, extra: {
                        if (esFallecido && motivo.isNotEmpty)
                          'notaFallecido': motivo
                        else if (!esFallecido)
                          'motivoRegreso': motivo,
                      });
                      if (esFallecido && ok) _avisarAdoptanteFallecido(motivo);
                      if (ok && sheetCtx.mounted) Navigator.pop(sheetCtx);
                    },
                    child: const Text('Guardar', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: sel ? cicloColor(e.$1).withValues(alpha: 0.1) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sel ? cicloColor(e.$1) : Colors.grey.shade200, width: sel ? 2 : 1),
            ),
            child: Row(children: [
              Text(e.$2, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.$1, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                    color: sel ? cicloColor(e.$1) : const Color(0xFF1A1A1A))),
                Text(e.$3, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ])),
              if (sel) Icon(Icons.check_circle, color: cicloColor(e.$1), size: 20),
            ]),
          ),
        );
      }),
    ]),
  );
}
