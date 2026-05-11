import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─── Constantes de color ──────────────────────────────────────────────────────

const appBg     = Color(0xFFDFFBEC);
const appDark   = Color(0xFF162416);
const appTeal   = Color(0xFF1F8A62);
const appOrange = Color(0xFFD84E18);

// ─── Monstera Leaf Painter ────────────────────────────────────────────────────

class LeafPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const c1 = Color(0xFF2E7D32);
    const c2 = Color(0xFF1B5E20);

    // TL: punta sale por esquina, lóbulos hacia adentro
    _leaf(canvas, x:  85, y:  85, s: 120, a: -pi*.25, c: c1, op: 0.87);
    _leaf(canvas, x:  55, y:  55, s:  78, a: -pi*.20, c: c2, op: 0.67);
    // TR
    _leaf(canvas, x: w- 85, y:  85, s: 120, a:  pi*.25, c: c1, op: 0.87);
    _leaf(canvas, x: w- 55, y:  55, s:  78, a:  pi*.20, c: c2, op: 0.67);
    // BL
    _leaf(canvas, x:  85, y: h- 85, s: 120, a: -pi*.75, c: c1, op: 0.87);
    _leaf(canvas, x:  55, y: h- 55, s:  78, a: -pi*.80, c: c2, op: 0.67);
    // BR
    _leaf(canvas, x: w- 85, y: h- 85, s: 120, a:  pi*.75, c: c1, op: 0.87);
    _leaf(canvas, x: w- 55, y: h- 55, s:  78, a:  pi*.80, c: c2, op: 0.67);
  }

  void _leaf(Canvas canvas, {
    required double x, required double y,
    required double s, required double a,
    required Color c, double op = 1.0,
  }) {
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(a);

    canvas.drawPath(_monsteraPath(s),
        Paint()..color = c.withOpacity(op)..style = PaintingStyle.fill);

    final hp = Paint()..color = appBg..style = PaintingStyle.fill;
    for (final xs in [-1.0, 1.0]) {
      canvas.drawOval(Rect.fromCenter(center: Offset(xs*s*.52,  s*.03), width: s*.38, height: s*.20), hp);
      canvas.drawOval(Rect.fromCenter(center: Offset(xs*s*.46, -s*.52), width: s*.30, height: s*.16), hp);
    }

    canvas.drawPath(
      Path()..moveTo(0, s*.50)..cubicTo(s*.02, s*.20, 0, -s*.50, 0, -s*.96),
      Paint()..color = Colors.white.withOpacity(0.28)..strokeWidth = 2.6..style = PaintingStyle.stroke,
    );

    final vp = Paint()..color = Colors.white.withOpacity(0.20)
        ..strokeWidth = 1.4..style = PaintingStyle.stroke;
    for (final yF in [s*.03, -s*.52]) {
      canvas.drawPath(Path()..moveTo(0, yF)
          ..cubicTo( s*.20, yF+s*.02,  s*.60, yF-s*.04,  s*.76, yF), vp);
      canvas.drawPath(Path()..moveTo(0, yF)
          ..cubicTo(-s*.20, yF+s*.02, -s*.60, yF-s*.04, -s*.76, yF), vp);
    }

    canvas.restore();
  }

  Path _monsteraPath(double s) {
    final p = Path();
    p.moveTo(0, s * 0.50);
    // DERECHO — lóbulo 1: ancho, punta redondeada
    p.cubicTo( s*.40,  s*.50,  s*.98,  s*.36,  s*.98,  s*.14);  // barrer hacia afuera
    p.cubicTo( s*.98, -s*.04,  s*.56, -s*.08,  s*.10, -s*.08);  // punta redonda → hacia nervio
    p.lineTo(  s*.10, -s*.20);                                    // corte 1
    // DERECHO — lóbulo 2
    p.cubicTo( s*.10, -s*.26,  s*.88, -s*.38,  s*.88, -s*.56);
    p.cubicTo( s*.88, -s*.72,  s*.52, -s*.76,  s*.10, -s*.76);
    p.lineTo(  s*.10, -s*.84);                                    // corte 2
    // DERECHO — lóbulo 3 pequeño + punta
    p.cubicTo( s*.10, -s*.90,  s*.46, -s*.92,  s*.40, -s*.97);
    p.cubicTo( s*.22, -s*.99,  s*.04, -s*.99,  0,     -s*.99);
    // IZQUIERDO (espejo inverso)
    p.cubicTo(-s*.04, -s*.99, -s*.22, -s*.99, -s*.40, -s*.97);
    p.cubicTo(-s*.46, -s*.92, -s*.10, -s*.90, -s*.10, -s*.84);
    p.lineTo( -s*.10, -s*.76);
    p.cubicTo(-s*.52, -s*.76, -s*.88, -s*.72, -s*.88, -s*.56);
    p.cubicTo(-s*.88, -s*.38, -s*.10, -s*.26, -s*.10, -s*.20);
    p.lineTo( -s*.10, -s*.08);
    p.cubicTo(-s*.56, -s*.08, -s*.98, -s*.04, -s*.98,  s*.14);
    p.cubicTo(-s*.98,  s*.36, -s*.40,  s*.50,  0,      s*.50);
    p.close();
    return p;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Widget leafBackground({required Widget child}) {
  return Stack(
    children: [
      Positioned.fill(child: Container(color: appBg)),
      Positioned.fill(child: CustomPaint(painter: LeafPainter())),
      child,
    ],
  );
}

// ─── Helpers globales ─────────────────────────────────────────────────────────

Color cicloColor(String s) => switch (s) {
  'Rescatado'              => appTeal,
  'Hogar de paso'          => const Color(0xFF7C6FCD),
  'En proceso de adopción' => const Color(0xFFE65100),
  'Adoptado'               => const Color(0xFF2196F3),
  'Regresado'              => const Color(0xFFD32F2F),
  _                        => Colors.grey,
};

// ─── Cambiar Estado Adopción Sheet ────────────────────────────────────────────

class CambiarEstadoSheet extends StatelessWidget {
  final String docId;
  final String estadoActual;
  const CambiarEstadoSheet({super.key, required this.docId, required this.estadoActual});

  static const _estados = [
    ('Rescatado',              '🟢', 'Disponible para adopción'),
    ('Hogar de paso',          '🟣', 'Temporalmente con un cuidador'),
    ('En proceso de adopción', '🟠', 'Tiene una solicitud activa'),
    ('Adoptado',               '🔵', 'Ya encontró su hogar'),
    ('Regresado',              '🔴', 'Fue devuelto, disponible de nuevo'),
  ];

  Color _color(String s) => switch (s) {
    'Rescatado'              => appTeal,
    'Hogar de paso'          => const Color(0xFF7C6FCD),
    'En proceso de adopción' => const Color(0xFFE65100),
    'Adoptado'               => const Color(0xFF2196F3),
    'Regresado'              => const Color(0xFFD32F2F),
    _                        => Colors.grey,
  };

  @override
  Widget build(BuildContext context) => Container(
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
            if (e.$1 != 'Regresado') {
              FirebaseFirestore.instance.collection('rescates').doc(docId)
                  .update({'estadoAdopcion': e.$1});
              Navigator.pop(context);
              return;
            }
            final ctrl = TextEditingController();
            final sheetCtx = context;
            showDialog(
              context: context,
              builder: (dlgCtx) => AlertDialog(
                title: const Text('¿Por qué fue regresado?'),
                content: TextField(
                  controller: ctrl,
                  maxLines: 3,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Ej: Incompatibilidad con otros animales, mudanza...',
                    border: OutlineInputBorder(),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dlgCtx),
                    child: const Text('Cancelar'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD32F2F)),
                    onPressed: () {
                      FirebaseFirestore.instance.collection('rescates').doc(docId).update({
                        'estadoAdopcion': 'Regresado',
                        'motivoRegreso': ctrl.text.trim(),
                      });
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
              color: sel ? _color(e.$1).withOpacity(0.1) : Colors.grey.shade50,
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
