import 'package:flutter/material.dart';

/// Un texto de largo variable dentro de un `Row`, con algo opcional [antes]
/// (un ícono) y/o [despues] (un puntito de estado), que **nunca desborda**.
///
/// Existe porque el mismo bug apareció una y otra vez, en dos formas que son
/// en realidad la misma: un `Text` con contenido que escribe la persona
/// (nombre de negocio, de persona, o una ciudad geocodificada) puesto en un
/// `Row` junto a algo de ancho fijo, sin envolverlo en `Flexible`. Apenas el
/// texto no entra en una línea, empuja a su vecino fuera de la pantalla y
/// desborda toda la fila.
///
/// Historial real, que es lo que justifica que esto sea UN widget:
///
///  · Encabezado del chat: se arregló primero acá, a mano.
///  · Panel del aliado: volvió a aparecer, sin conexión con ese arreglo —
///    "Veterinario Huellitas..." desbordado ~1029px (hallazgo de Eliza).
///  · Línea de ciudad (ícono 📍 + nombre): de SEIS copias, dos tenían
///    `Flexible`/`Expanded` y cuatro no. Arreglado en algunas, olvidado en
///    otras, sin que nada lo delatara (hallazgo de auditoría).
///
/// Nada en el tipo de datos avisa en tiempo de compilación que un
/// `Row(Icono, Text(variable))` es peligroso. Con un solo widget, la
/// protección deja de depender de que alguien se acuerde de repetirla.
class TextoSinDesborde extends StatelessWidget {
  final String texto;
  final TextStyle style;

  /// Qué va ANTES del texto (típicamente un ícono de ancho fijo).
  final Widget? antes;

  /// Qué va DESPUÉS del texto (típicamente un puntito de estado).
  final Widget? despues;

  final MainAxisAlignment mainAxisAlignment;
  final MainAxisSize mainAxisSize;
  final TextAlign textAlign;
  final int maxLines;

  /// Espacio entre el texto y sus vecinos.
  final double separacion;

  const TextoSinDesborde({
    super.key,
    required this.texto,
    required this.style,
    this.antes,
    this.despues,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.mainAxisSize = MainAxisSize.max,
    this.textAlign = TextAlign.start,
    this.maxLines = 1,
    this.separacion = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: mainAxisAlignment,
      mainAxisSize: mainAxisSize,
      children: [
        if (antes != null) ...[antes!, SizedBox(width: separacion)],
        Flexible(
          child: Text(
            texto,
            overflow: TextOverflow.ellipsis,
            maxLines: maxLines,
            textAlign: textAlign,
            style: style,
          ),
        ),
        if (despues != null) ...[SizedBox(width: separacion), despues!],
      ],
    );
  }
}
