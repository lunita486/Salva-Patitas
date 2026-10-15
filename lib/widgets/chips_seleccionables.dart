import 'package:flutter/material.dart';

import '../theme/salva_patitas_theme.dart';

/// Una grilla de opciones tipo "chip" (Wrap, nunca scroll horizontal
/// oculto) donde tocar una la marca como elegida.
///
/// Consolida la lógica que vivía copiada TRES veces, cada copia con su
/// propio nombre — `_grupo` en tipo_animal_screen.dart, `_chips` en
/// subir_rescate_screen.dart, `_selector` en editar_rescate_screen.dart.
/// Dos de esas tres ya usaban `Wrap`; la tercera (tipo_animal_screen.dart,
/// las preferencias del adoptante) se había quedado con un scroll
/// horizontal sin ninguna señal de que había más opciones fuera de
/// vista — exactamente el riesgo de tener el mismo patrón repetido en vez
/// de un solo lugar: se corrige una copia y las otras se quedan atrás.
/// Pedido real de Eliza: "no copiar la logica miles de veces".
///
/// A propósito NO decide layout de etiqueta ni padding exterior — cada
/// pantalla los sigue manejando como antes (con estilos e indentación
/// distintos entre sí), así esta consolidación no le cambia el aspecto a
/// ninguna. Lo único que deja de poder divergir es CÓMO se arma la grilla
/// y CÓMO se resalta la opción elegida.
class ChipsSeleccionables extends StatelessWidget {
  final List<String> opciones;
  final String seleccion;
  final ValueChanged<String> onSeleccionar;

  /// Color de la opción elegida. Sin él, el verde 3D del tema (`SpDeco.primary`).
  final Color? colorActivo;

  /// Fondo de las opciones no elegidas. Sin él, blanco con canto 3D.
  final Color? colorInactivo;
  final EdgeInsets paddingChip;
  final double spacing;
  final double runSpacing;
  final Duration duracion;
  const ChipsSeleccionables({
    super.key,
    required this.opciones,
    required this.seleccion,
    required this.onSeleccionar,
    this.colorActivo,
    this.colorInactivo,
    this.paddingChip = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.spacing = 8,
    this.runSpacing = 8,
    this.duracion = const Duration(milliseconds: 150),
  });

  /// Las opciones a dibujar, más el valor ya guardado si NO está entre
  /// ellas.
  ///
  /// Sin esto, un valor que la lista no contempla se vuelve INVISIBLE: no
  /// hay ningún chip marcado, parece que el dato se perdió, y tocar
  /// cualquier otra opción lo pisa sin que nadie se entere de que había
  /// algo. Pasó de verdad — publicar y editar tenían listas de estado de
  /// salud distintas, así que un animal publicado como 'Herido' se abría
  /// en Editar sin nada seleccionado (hallazgo de auditoría; las listas ya
  /// se unificaron en RescatesRepository).
  ///
  /// Se deja como red de seguridad permanente porque la causa de fondo no
  /// desaparece con haber unificado las listas: un animal guardado por una
  /// versión vieja de la app, o un valor que alguien saque de la lista más
  /// adelante sin migrar los documentos que lo usan, caen exactamente en
  /// el mismo caso. Mostrarlo (aunque sea un valor "raro") siempre es
  /// mejor que esconder lo que la persona tiene guardado.
  List<String> get _opcionesVisibles =>
      (seleccion.isEmpty || opciones.contains(seleccion))
      ? opciones
      : [...opciones, seleccion];

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    // Texto legible sobre el color elegido: oscuro sobre colores claros.
    final activo = colorActivo;
    final tintaActiva = activo == null
        ? c.onPrimary
        : ThemeData.estimateBrightnessForColor(activo) == Brightness.dark
        ? c.surface
        : c.ink;
    return Wrap(
      spacing: spacing,
      runSpacing: runSpacing + 2,
      children: _opcionesVisibles.map((o) {
        final sel = o == seleccion;
        // Chips 3D del rediseño (`.sp-chip`): blanco con canto, y la elegida
        // en verde (o en el color que pida la pantalla, ej. la urgencia).
        final deco = !sel
            ? SpDeco.soft(
                c,
                radius: SpRadius.full,
              ).copyWith(color: colorInactivo ?? c.surface)
            : activo == null
            ? SpDeco.primary(c, radius: SpRadius.full)
            : BoxDecoration(
                color: activo,
                borderRadius: BorderRadius.circular(SpRadius.full),
                boxShadow: [
                  BoxShadow(
                    color: Color.lerp(activo, c.ink, .35)!,
                    offset: const Offset(0, 4),
                  ),
                ],
              );
        return GestureDetector(
          onTap: () => onSeleccionar(o),
          child: AnimatedContainer(
            duration: duracion,
            padding: paddingChip,
            decoration: deco,
            child: Text(
              o,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: sel ? tintaActiva : c.inkMuted,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
