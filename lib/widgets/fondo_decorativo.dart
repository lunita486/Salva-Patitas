import 'package:flutter/material.dart';

import '../theme.dart';

// ─── Paw print painter ───────────────────────────────────────────────────────

class _PawPrintPainter extends CustomPainter {
  final Color color;
  const _PawPrintPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    double x(double v) => v * size.width / 100;
    double y(double v) => v * size.height / 100;

    // Main pad — large rounded oval at the bottom
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(x(50), y(72)),
        width: x(54),
        height: y(46),
      ),
      p,
    );
    // Four toe pads arranged in an arc above the main pad
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(x(16), y(42)),
        width: x(22),
        height: y(26),
      ),
      p,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(x(37), y(26)),
        width: x(25),
        height: y(29),
      ),
      p,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(x(63), y(26)),
        width: x(25),
        height: y(29),
      ),
      p,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(x(84), y(42)),
        width: x(22),
        height: y(26),
      ),
      p,
    );
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
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(top: -28, left: -28, child: _hoja(170, 0.82)),
      Positioned(top: -28, right: -28, child: _hoja(170, 0.82, fx: true)),
      Positioned(bottom: -28, left: -28, child: _hoja(140, 0.60, fy: true)),
      Positioned(
        bottom: -28,
        right: -28,
        child: _hoja(140, 0.60, fx: true, fy: true),
      ),
    ],
  );
}

Widget leafBackground({required Widget child}) => Stack(
  children: [
    Positioned.fill(child: Container(color: appBg)),
    Positioned(top: -28, left: -28, child: _hoja(170, 0.82)),
    Positioned(top: -28, right: -28, child: _hoja(170, 0.82, fx: true)),
    Positioned(bottom: -28, left: -28, child: _hoja(140, 0.60, fy: true)),
    Positioned(
      bottom: -28,
      right: -28,
      child: _hoja(140, 0.60, fx: true, fy: true),
    ),
    child,
  ],
);
