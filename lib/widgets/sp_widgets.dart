// Piezas visuales del rediseño 3D "plastilina" (ver DISENO.md y
// lib/theme/salva_patitas_theme.dart). Solo dibujan: ninguna lee datos ni
// navega por su cuenta, cada pantalla les pasa el texto y el onTap que ya
// tenía. Así el rediseño cambia cómo se ve la app sin tocar su lógica.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/salva_patitas_theme.dart';

/// Los cinco animalitos 3D de assets/animales/.
enum SpAnimalKind { perro, gato, conejo, huella, casa }

class SpAnimal extends StatelessWidget {
  const SpAnimal(this.kind, {super.key, this.size = 48});
  final SpAnimalKind kind;
  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/animales/${kind.name}.svg',
    width: size,
    height: size,
  );
}

/// Huellita dibujada (la misma forma del prototipo, en una caja de 24x24).
class SpPaw extends StatelessWidget {
  const SpPaw({super.key, this.size = 18, this.color, this.angle = 0});
  final double size;
  final Color? color;

  /// Giro en grados.
  final double angle;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: angle * math.pi / 180,
    child: CustomPaint(
      size: Size.square(size),
      painter: _PawPainter(color ?? context.sp.primary),
    ),
  );
}

class _PawPainter extends CustomPainter {
  _PawPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    final p = Paint()..color = color;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(12 * k, 16.2 * k),
        width: 9.2 * k,
        height: 7.6 * k,
      ),
      p,
    );
    for (final (x, y, r) in const [
      (5.6, 10.6, 2.0),
      (9.4, 6.4, 2.1),
      (14.6, 6.4, 2.1),
      (18.4, 10.6, 2.0),
    ]) {
      canvas.drawCircle(Offset(x * k, y * k), r * k, p);
    }
  }

  @override
  bool shouldRepaint(_PawPainter old) => old.color != color;
}

/// Las cuatro huellas grandes de fondo, fijas detrás del contenido
/// (`.phone__deco` del prototipo). Va en un Stack, debajo de todo.
class SpPawBackground extends StatelessWidget {
  const SpPawBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.sp.mint.withValues(alpha: .55);
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (_, box) {
          final w = box.maxWidth, h = box.maxHeight;
          Widget paw(double x, double y, double s, double a) => Positioned(
            left: x * w - s / 2,
            top: y * h - s / 2,
            child: SpPaw(size: s, color: c, angle: a),
          );
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              paw(.92, .20, 106, 24),
              paw(.06, .56, 100, -18),
              paw(.18, .92, 110, 14),
              paw(.94, .84, 116, -24),
            ],
          );
        },
      ),
    );
  }
}

/// Fondo pastel 3D (`.sp-tone`). Con [onTap] se comporta como botón.
class SpToneBox extends StatelessWidget {
  const SpToneBox({
    super.key,
    required this.tone,
    required this.child,
    this.radius = SpRadius.lg,
    this.padding = const EdgeInsets.all(SpSpace.s3),
    this.onTap,
    this.height,
  });
  final SpTone tone;
  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      height: height,
      padding: padding,
      decoration: SpDeco.tone(context.sp, tone, radius: radius),
      child: child,
    );
    return onTap == null ? box : SpPressable(onTap: onTap!, child: box);
  }
}

/// Tarjeta blanca 3D (`.sp-card`).
class SpCard extends StatelessWidget {
  const SpCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(SpSpace.s4),
    this.radius = SpRadius.lg,
    this.onTap,
  });
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: double.infinity,
      padding: padding,
      decoration: SpDeco.card(context.sp, radius: radius),
      child: child,
    );
    return onTap == null ? box : SpPressable(onTap: onTap!, child: box);
  }
}

/// Efecto "tecla": al presionar baja 4px. Envuelve cualquier pieza 3D.
class SpPressable extends StatefulWidget {
  const SpPressable({super.key, required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  State<SpPressable> createState() => _SpPressableState();
}

class _SpPressableState extends State<SpPressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapDown: (_) => setState(() => _down = true),
    onTapCancel: () => setState(() => _down = false),
    onTapUp: (_) => setState(() => _down = false),
    onTap: widget.onTap,
    child: AnimatedSlide(
      duration: const Duration(milliseconds: 80),
      offset: Offset(0, _down ? .02 : 0),
      child: widget.child,
    ),
  );
}

/// Título de sección con huellita verde girada (`.sp-sechead`) y, si hay,
/// un enlace a la derecha (Ver todas, Gestionar) o una píldora de conteo.
class SpSectionTitle extends StatelessWidget {
  const SpSectionTitle(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const SpPaw(size: 18, angle: -12),
      const SizedBox(width: SpSpace.s2),
      Expanded(
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: SpText.section.copyWith(color: context.sp.ink),
        ),
      ),
      if (trailing != null) ...[const SizedBox(width: SpSpace.s2), trailing!],
    ],
  );
}

/// Enlace verde con chevron (`.sp-link`): "Ver todas", "Gestionar".
class SpLink extends StatelessWidget {
  const SpLink(this.label, {super.key, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: SpText.label.copyWith(
                color: c.primaryStrong,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: c.primaryStrong),
          ],
        ),
      ),
    );
  }
}

/// Píldora coral con conteo ("2 pendientes"), con canto.
class SpCountPill extends StatelessWidget {
  const SpCountPill(this.label, {super.key, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: c.accentSoft,
          borderRadius: BorderRadius.circular(SpRadius.full),
        ),
        child: Text(
          label,
          style: SpText.label.copyWith(
            color: c.accentInk,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

/// Mini cifra en baldosa pastel (`.sp-mini`): animalito, número y etiqueta.
class SpMiniStat extends StatelessWidget {
  const SpMiniStat({
    super.key,
    required this.tone,
    required this.animal,
    required this.value,
    required this.label,
    this.onTap,
  });
  final SpTone tone;
  final SpAnimalKind animal;
  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    final ink = SpToneColors.of(c, tone).ink;
    return SpToneBox(
      tone: tone,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Transform.translate(
            offset: const Offset(-4, -2),
            child: SpAnimal(animal, size: 40),
          ),
          const SizedBox(height: 4),
          Text(value, style: SpText.stat.copyWith(color: c.ink)),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SpText.caption.copyWith(
              color: ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Acceso grande cuadrado (`.sp-action`): arte arriba, título abajo y un
/// botoncito blanco con chevron.
class SpActionTile extends StatelessWidget {
  const SpActionTile({
    super.key,
    required this.tone,
    required this.art,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final SpTone tone;
  final Widget art;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    final k = SpToneColors.of(c, tone);
    return SpToneBox(
      tone: tone,
      radius: SpRadius.xl,
      height: 164,
      padding: const EdgeInsets.all(SpSpace.s4),
      onTap: onTap,
      child: Stack(
        children: [
          Positioned(left: -4, top: -4, right: 36, height: 80, child: art),
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: c.surface,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: k.deep, offset: const Offset(0, 3)),
                ],
              ),
              child: Icon(Icons.chevron_right_rounded, size: 18, color: c.ink),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: SpText.headline.copyWith(
                    color: c.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  subtitle,
                  style: SpText.caption.copyWith(
                    color: k.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Baldosa de 56px con un animalito (`.sp-bigtile`), para filas de lista.
class SpBigTile extends StatelessWidget {
  const SpBigTile({super.key, required this.tone, required this.animal});
  final SpTone tone;
  final SpAnimalKind animal;

  @override
  Widget build(BuildContext context) => Container(
    width: 56,
    height: 56,
    alignment: Alignment.center,
    decoration: SpDeco.tone(context.sp, tone, radius: 18),
    child: SpAnimal(animal, size: 44),
  );
}

/// Un ítem de la barra de abajo flotante. La pestaña activa es una burbuja
/// verde elevada.
class SpTabItem extends StatelessWidget {
  const SpTabItem({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badge = 0,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 44,
              height: 36,
              transform: Matrix4.translationValues(0, active ? -3 : 0, 0),
              decoration: active ? SpDeco.primary(c, radius: 14) : null,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Icon(
                    icon,
                    size: 22,
                    color: active ? c.onPrimary : c.inkFaint,
                  ),
                  if (badge > 0)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        decoration: BoxDecoration(
                          color: c.accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: c.surface, width: 1.5),
                        ),
                        child: Text(
                          badge > 9 ? '9+' : '$badge',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 9,
                            color: c.onAccent,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                color: active ? c.ink : c.inkMuted,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Barra de abajo flotante (`.sp-tabbar`): a 12px de los bordes, esquinas
/// de 28px. Recibe los [SpTabItem] ya armados por cada pantalla.
class SpTabBar extends StatelessWidget {
  const SpTabBar({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(
          SpSpace.s3,
          0,
          SpSpace.s3,
          SpSpace.s3,
        ),
        padding: const EdgeInsets.symmetric(
          vertical: SpSpace.s2,
          horizontal: SpSpace.s1,
        ),
        decoration: SpDeco.card(c, radius: 28),
        child: Row(children: children),
      ),
    );
  }
}
