import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  Future<void> _avisarAdoptanteFallecido(String nota) async {
    final adoptanteId = adoptanteIdEnProceso;
    if (adoptanteId == null || adoptanteId.isEmpty || nombre.isEmpty) return;
    final chats = await FirebaseFirestore.instance.collection('chats')
        .where('adoptanteId', isEqualTo: adoptanteId)
        .where('animalNombre', isEqualTo: nombre)
        .limit(1).get();
    if (chats.docs.isEmpty) return;
    final chatId = chats.docs.first.id;
    final n = DateTime.now();
    final hora = '${n.hour}:${n.minute.toString().padLeft(2, '0')}';
    final texto = 'Lamentamos informarte que $nombre falleció. '
        'Gracias por tu interés en darle un hogar. 🌈'
        '${nota.isNotEmpty ? '\n\n"$nota"' : ''}';
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

  Color _color(String s) => switch (s) {
    'Rescatado'              => appTeal,
    'Hogar de paso'          => const Color(0xFF7C6FCD),
    'En proceso de adopción' => const Color(0xFFE65100),
    'Adoptado'               => const Color(0xFF2196F3),
    'Regresado'              => const Color(0xFFD32F2F),
    'Fallecido'              => const Color(0xFF78909C),
    _                        => Colors.grey,
  };

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
          onTap: () {
            if (e.$1 != 'Regresado' && e.$1 != 'Fallecido') {
              FirebaseFirestore.instance.collection('rescates').doc(docId)
                  .update({
                    'estadoAdopcion': e.$1,
                    if (e.$1 == 'Adoptado')
                      'fechaAdopcion': FieldValue.serverTimestamp(),
                  });
              Navigator.pop(context);
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
                    onPressed: () {
                      FirebaseFirestore.instance.collection('rescates').doc(docId).update({
                        'estadoAdopcion': e.$1,
                        if (esFallecido && ctrl.text.trim().isNotEmpty)
                          'notaFallecido': ctrl.text.trim()
                        else if (!esFallecido)
                          'motivoRegreso': ctrl.text.trim(),
                      });
                      if (esFallecido) _avisarAdoptanteFallecido(ctrl.text.trim());
                      Navigator.pop(dlgCtx);
                      Navigator.pop(sheetCtx);
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
              color: sel ? _color(e.$1).withValues(alpha: 0.1) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sel ? _color(e.$1) : Colors.grey.shade200, width: sel ? 2 : 1),
            ),
            child: Row(children: [
              Text(e.$2, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.$1, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                    color: sel ? _color(e.$1) : const Color(0xFF1A1A1A))),
                Text(e.$3, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ])),
              if (sel) Icon(Icons.check_circle, color: _color(e.$1), size: 20),
            ]),
          ),
        );
      }),
    ]),
  );
}
