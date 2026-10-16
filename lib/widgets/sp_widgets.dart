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
            // scaleDown: un nombre largo ("Mis rescates") se achica un poco
            // en vez de cortarse con "…".
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10.5,
                  color: active ? c.ink : c.inkMuted,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                ),
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

/// Tono pastel y animalito según la especie: perros durazno, gatos lila,
/// el resto cielo (DISENO.md).
(SpTone, SpAnimalKind) spEspecie(String? especie) => switch (especie) {
  'Gato' => (SpTone.lilac, SpAnimalKind.gato),
  'Perro' || null => (SpTone.peach, SpAnimalKind.perro),
  _ => (SpTone.sky, SpAnimalKind.conejo),
};

/// Tono de la píldora de estado de un animalito. Mismos grupos que
/// `cicloColor` (theme.dart), pero con los colores del tema.
SpTone? spToneEstado(String estado) => switch (estado) {
  'Hogar de paso' => SpTone.butter,
  'En proceso de adopción' => SpTone.lilac,
  'Adoptado' => SpTone.sky,
  'Regresado' || 'Estancados' => SpTone.peach,
  'Fallecido' => null,
  _ => SpTone.mint,
};

/// Ícono de cada estado de un animalito (hoja de cambiar estado).
IconData spIconoEstado(String estado) => switch (estado) {
  'Rescatado' => Icons.pets_rounded,
  'Hogar de paso' => Icons.night_shelter_outlined,
  'En proceso de adopción' => Icons.hourglass_top_rounded,
  'Adoptado' => Icons.home_rounded,
  'Regresado' => Icons.undo_rounded,
  _ => Icons.favorite_border_rounded,
};

/// Lugar de la foto cuando el animalito no tiene foto (o no cargó): baldosa
/// pastel con el animalito 3D de su especie.
class SpFotoVacia extends StatelessWidget {
  const SpFotoVacia({super.key, required this.especie, this.size = 72});
  final String? especie;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (tone, animal) = spEspecie(especie);
    return Container(
      width: double.infinity,
      height: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: SpDeco.tone(context.sp, tone).gradient,
      ),
      child: SpAnimal(animal, size: size),
    );
  }
}

/// Insignia coral (`.sp-badge`): "Nuevo", "Urgente".
class SpBadge extends StatelessWidget {
  const SpBadge(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.accent,
        borderRadius: BorderRadius.circular(SpRadius.full),
        boxShadow: [
          BoxShadow(
            color: c.accentInk.withValues(alpha: .5),
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: c.onAccent,
        ),
      ),
    );
  }
}

/// Píldora de estado con chevron (`.sp-status`). Sin [onTap] (Fallecido) se
/// ve igual pero sin flecha.
class SpStatus extends StatelessWidget {
  const SpStatus(this.estado, {super.key, this.onTap, this.height = 32});
  final String estado;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    final tone = spToneEstado(estado);
    final k = tone == null ? null : SpToneColors.of(c, tone);
    final box = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: SpSpace.s3),
      decoration: BoxDecoration(
        color: k?.fill ?? c.surfaceSunken,
        borderRadius: BorderRadius.circular(SpRadius.full),
        boxShadow: [
          BoxShadow(color: k?.deep ?? c.edge, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              estado,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SpText.caption.copyWith(
                color: k?.ink ?? c.inkMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (onTap != null)
            Icon(
              Icons.expand_more_rounded,
              size: 16,
              color: k?.ink ?? c.inkMuted,
            ),
        ],
      ),
    );
    return onTap == null ? box : GestureDetector(onTap: onTap, child: box);
  }
}

/// Botón 3D. Verde por defecto; [suave] lo hace blanco con canto
/// (secundario) y [peligro] blanco con texto rojo (Rechazar). Con
/// [cargando] muestra un spinner y no se puede tocar; con [onTap] null se
/// ve apagado.
class SpButton extends StatelessWidget {
  const SpButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.suave = false,
    this.peligro = false,
    this.compacto = false,
    this.cargando = false,
  });
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool suave;
  final bool peligro;
  final bool compacto;
  final bool cargando;

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    final blanco = suave || peligro;
    final fg = peligro ? c.danger : (suave ? c.ink : c.onPrimary);
    final activo = onTap != null && !cargando;
    final radio = compacto ? 12.0 : SpRadius.md;
    final caja = Container(
      height: compacto ? 34 : 48,
      padding: EdgeInsets.symmetric(horizontal: compacto ? 12 : 18),
      decoration: blanco
          ? SpDeco.soft(c, radius: radio)
          : SpDeco.primary(c, radius: radio),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (cargando)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: fg),
            )
          else ...[
            if (icon != null) ...[
              Icon(icon, size: compacto ? 15 : 18, color: fg),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compacto ? 12 : 15,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
            ),
          ],
        ],
      ),
    );
    if (!activo) {
      return Opacity(opacity: cargando ? 1 : .5, child: caja);
    }
    return SpPressable(onTap: onTap!, child: caja);
  }
}

/// Píldora chica con ícono (`.pill`): tipo y estado de una solicitud, etc.
class SpPill extends StatelessWidget {
  const SpPill(
    this.label, {
    super.key,
    required this.fondo,
    required this.tinta,
    this.icon,
  });
  final String label;
  final Color fondo;
  final Color tinta;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: fondo,
      borderRadius: BorderRadius.circular(SpRadius.full),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: tinta),
          const SizedBox(width: 5),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: tinta,
          ),
        ),
      ],
    ),
  );
}

/// Estado vacío (`.sp-empty`): siempre con un animalito 3D.
class SpEmpty extends StatelessWidget {
  const SpEmpty({
    super.key,
    required this.title,
    this.subtitle,
    this.animal = SpAnimalKind.perro,
    this.action,
  });
  final String title;
  final String? subtitle;
  final SpAnimalKind animal;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    return SpCard(
      child: Row(
        children: [
          SpAnimal(animal, size: 72),
          const SizedBox(width: SpSpace.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: c.ink,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: SpText.label.copyWith(
                      color: c.inkMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (action != null) ...[
                  const SizedBox(height: SpSpace.s3),
                  action!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip de filtro (`.sp-chip`): blanco con canto; elegido, verde.
class SpChip extends StatelessWidget {
  const SpChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.animal,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final SpAnimalKind? animal;

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 38,
        padding: EdgeInsets.only(left: animal == null ? 14 : 8, right: 14),
        decoration: selected
            ? SpDeco.primary(c, radius: SpRadius.full)
            : SpDeco.soft(c, radius: SpRadius.full),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (animal != null) ...[
              SpAnimal(animal!, size: 24),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: SpText.label.copyWith(
                fontWeight: FontWeight.w700,
                color: selected ? c.onPrimary : c.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Botoncito cuadrado 3D de acción (`.mini3d`): compartir, editar, borrar.
class SpMiniButton extends StatelessWidget {
  const SpMiniButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
    this.destacado = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;

  /// Coral, para llamar la atención (p. ej. compartir a un animalito que
  /// lleva mucho esperando).
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    return Tooltip(
      message: tooltip,
      child: SpPressable(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: destacado
                ? c.accent
                : danger
                ? c.dangerSoft
                : c.surfaceSunken,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: destacado ? c.accentInk : c.edge,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(
            icon,
            size: 17,
            color: destacado
                ? c.onAccent
                : danger
                ? c.danger
                : c.inkMuted,
          ),
        ),
      ),
    );
  }
}

/// Botón redondo blanco con canto (`.sp-iconbtn`), p. ej. volver.
class SpRoundButton extends StatelessWidget {
  const SpRoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    return Tooltip(
      message: tooltip,
      child: SpPressable(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: SpDeco.soft(c, radius: SpRadius.full),
          child: Icon(icon, size: 20, color: c.ink),
        ),
      ),
    );
  }
}

/// Recuadro de aviso dentro de una tarjeta (fondo suave + texto del tono).
class SpNotice extends StatelessWidget {
  const SpNotice({
    super.key,
    required this.fondo,
    required this.tinta,
    required this.child,
  });
  final Color fondo;
  final Color tinta;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: fondo,
      borderRadius: BorderRadius.circular(14),
    ),
    child: IconTheme(
      data: IconThemeData(color: tinta, size: 15),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: tinta,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        child: child,
      ),
    ),
  );
}

/// Encabezado de pantalla (`.screenhead`): volver, título grande, una línea
/// opcional debajo y huellitas a la derecha.
class SpScreenHeader extends StatelessWidget {
  const SpScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.onBack,
    this.conVolver = true,
  });
  final String title;
  final String? subtitle;
  final Color? subtitleColor;

  /// Sin esto, el botón hace `Navigator.pop`.
  final VoidCallback? onBack;

  /// false en las pestañas (Perfil), que no tienen a dónde volver.
  final bool conVolver;

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Row(
        children: [
          if (conVolver) ...[
            SpRoundButton(
              icon: Icons.arrow_back_ios_new_rounded,
              tooltip: 'Volver',
              onTap: onBack ?? () => Navigator.pop(context),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SpText.screen.copyWith(color: c.ink),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: SpText.label.copyWith(
                      color: subtitleColor ?? c.inkMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          SpPaw(size: 16, angle: 20, color: c.mintDeep),
          const SizedBox(width: 4),
          SpPaw(size: 20, angle: 30, color: c.mint),
        ],
      ),
    );
  }
}

/// Tono pastel por tipo de negocio aliado. Mismos grupos que
/// `aliadoTipoColorPastel` (theme.dart), con los colores del tema.
/// Tono pastel por categoría de un servicio de un negocio aliado (Baño y
/// peluquería, Veterinaria...). Es el color de su baldosa y de su precio.
SpTone spToneCategoriaServicio(String categoria) => switch (categoria) {
  'Baño y peluquería' => SpTone.sky,
  'Veterinaria' => SpTone.mint,
  'Tienda' => SpTone.lilac,
  'Adiestramiento' => SpTone.butter,
  'Transporte' => SpTone.peach,
  _ => SpTone.mint,
};

SpTone spToneAliado(String tipo) => switch (tipo) {
  'Veterinaria' => SpTone.mint,
  'Tienda de mascotas' => SpTone.peach,
  'Spa canino' => SpTone.lilac,
  'Peluquería canina' => SpTone.butter,
  _ => SpTone.sky,
};

/// Color de la opción de urgencia elegida: Alta coral, Media durazno, Baja
/// el verde de siempre (null = verde 3D del tema). Lo usan "Subir uno" y
/// "Subir lote".
Color? spColorUrgencia(SpColors c, String urgencia) => switch (urgencia) {
  'Alta' => c.accent,
  'Media' => c.peachDeep,
  _ => null,
};

/// Las especies como baldosas con su animalito 3D (`.species`); la elegida
/// lleva borde verde y ✓. Lo usan "Subir uno" y "Subir lote".
class SpSelectorEspecie extends StatelessWidget {
  const SpSelectorEspecie({
    super.key,
    required this.especies,
    required this.seleccion,
    required this.onSeleccionar,
  });
  final List<String> especies;
  final String seleccion;
  final ValueChanged<String> onSeleccionar;

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    return Row(
      children: [
        for (final (i, e) in especies.indexed) ...[
          if (i > 0) const SizedBox(width: SpSpace.s3),
          Expanded(
            child: Builder(
              builder: (_) {
                final (tono, animal) = spEspecie(e);
                final sel = e == seleccion;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    SpToneBox(
                      tone: tono,
                      radius: 22,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      onTap: () => onSeleccionar(e),
                      child: SizedBox(
                        width: double.infinity,
                        child: Column(
                          children: [
                            SpAnimal(animal, size: 56),
                            const SizedBox(height: 6),
                            Text(
                              e,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: c.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (sel)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: c.primary, width: 3),
                            ),
                          ),
                        ),
                      ),
                    if (sel)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: SpDeco.primary(c, radius: SpRadius.full),
                          child: Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: c.onPrimary,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// Borde punteado redondeado (recuadros de "Agregar fotos").
class SpBordePunteado extends CustomPainter {
  SpBordePunteado(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(24),
    ).deflate(1);
    final path = Path()..addRRect(rect);
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 8), paint);
        d += 14;
      }
    }
  }

  @override
  bool shouldRepaint(SpBordePunteado old) => old.color != color;
}

/// Una fila de una tarjeta de opciones de Perfil (`.sp-row`): baldosa pastel
/// con ícono, título, línea opcional arriba ([etiqueta]) o abajo ([sub]) y
/// chevron si se puede tocar. La usan el Perfil del albergue y el del
/// adoptante.
class SpFilaCuenta extends StatelessWidget {
  const SpFilaCuenta({
    super.key,
    required this.icono,
    required this.texto,
    this.etiqueta,
    this.sub,
    this.tono = SpTone.mint,
    this.onTap,
  });
  final IconData icono;
  final String texto;
  final String? etiqueta;
  final String? sub;
  final SpTone tono;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    final k = SpToneColors.of(c, tono);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: k.fill,
                borderRadius: BorderRadius.circular(SpRadius.sm),
              ),
              child: Icon(icono, size: 20, color: k.ink),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (etiqueta != null)
                    Text(
                      etiqueta!,
                      style: TextStyle(fontSize: 12, color: c.inkMuted),
                    ),
                  Text(
                    texto,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                  if (sub != null)
                    Text(
                      sub!,
                      style: TextStyle(fontSize: 13, color: c.inkMuted),
                    ),
                ],
              ),
            ),
            if (onTap != null)
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: c.surfaceSunken,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: c.inkMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Separador entre filas de una tarjeta de opciones.
class SpDivisorFilas extends StatelessWidget {
  const SpDivisorFilas({super.key});

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    thickness: 1,
    indent: 16,
    endIndent: 16,
    color: context.sp.line,
  );
}

/// Barrita de arriba de una hoja que sube desde abajo (`.sheet__grab`).
class SpAgarradera extends StatelessWidget {
  const SpAgarradera({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 44,
      height: 5,
      decoration: BoxDecoration(
        color: context.sp.line,
        borderRadius: BorderRadius.circular(3),
      ),
    ),
  );
}

/// Título y subtítulo de una hoja (`.sheet__title` / `.sheet__sub`).
class SpHojaTitulo extends StatelessWidget {
  const SpHojaTitulo(
    this.titulo, {
    super.key,
    this.subtitulo,
    this.centrado = false,
  });
  final String titulo;
  final String? subtitulo;
  final bool centrado;

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    final align = centrado ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment: centrado
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          textAlign: align,
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            color: c.ink,
          ),
        ),
        if (subtitulo != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitulo!,
            textAlign: align,
            style: TextStyle(fontSize: 14, color: c.inkMuted),
          ),
        ],
      ],
    );
  }
}

/// Una opción elegible en una hoja (cambiar estado, roles): baldosa pastel
/// con ícono, título y detalle; la elegida con borde verde y ✓.
class SpOpcionHoja extends StatelessWidget {
  const SpOpcionHoja({
    super.key,
    required this.titulo,
    required this.detalle,
    required this.icono,
    required this.tono,
    required this.elegida,
    this.onTap,
  });
  final String titulo;
  final String detalle;
  final IconData icono;

  /// null = gris (Fallecido).
  final SpTone? tono;
  final bool elegida;

  /// null: el toque lo maneja quien la envuelve.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    final k = tono == null ? null : SpToneColors.of(c, tono!);
    final caja = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: SpDeco.soft(c, radius: 18).copyWith(
        border: elegida ? Border.all(color: c.primary, width: 2.5) : null,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: k?.fill ?? c.surfaceSunken,
              borderRadius: BorderRadius.circular(SpRadius.sm),
            ),
            child: Icon(icono, size: 20, color: k?.ink ?? c.inkMuted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: c.ink,
                  ),
                ),
                Text(
                  detalle,
                  style: TextStyle(fontSize: 12.5, color: c.inkMuted),
                ),
              ],
            ),
          ),
          if (elegida)
            Container(
              width: 24,
              height: 24,
              decoration: SpDeco.primary(c, radius: SpRadius.full),
              child: Icon(Icons.check_rounded, size: 15, color: c.onPrimary),
            ),
        ],
      ),
    );
    return onTap == null ? caja : GestureDetector(onTap: onTap, child: caja);
  }
}
