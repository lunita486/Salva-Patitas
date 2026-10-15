import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInputFormatter;

import '../theme/salva_patitas_theme.dart';

// ─── Campos de las pantallas "Configura tu albergue"/"Configura tu negocio" ──
// Antes cada pantalla tenía su propia versión: albergue con label gris
// arriba del campo, aliado con ícono + label flotante adentro. Un solo
// estilo para las dos (Eliza las comparó una al lado de la otra y pidió
// que se vean igual) — texto oscuro en vez del gris apagado que tenía
// albergue, que es lo que a ella más le gustó de las dos.
// Sin color propio: toma el texto principal del tema.
Widget perfilLabel(String texto) => Text(
  texto,
  style: const TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.1,
  ),
);

// maxLength opcional (sin tope antes): un pegado gigante en nombre/ciudad/
// dirección se guardaba entero, sin ningún aviso — el bug real que reportó
// Eliza (nombre de negocio de más de 80 caracteres, desbordando el header
// del perfil). Sin `counterText` propio a propósito: se deja que el
// contador "12/40" de Flutter aparezca solo, mismo criterio que ya usan
// subir_rescate_screen.dart/editar_rescate_screen.dart/subir_lote_screen.
// dart para sus campos de nombre/descripción — antes acá no se mostraba
// ninguno (ni límite ni contador), inconsistente con esas otras pantallas.
Widget perfilCampo(
  TextEditingController ctl,
  String hint, {
  TextInputType tipo = TextInputType.text,
  List<TextInputFormatter> formato = const [],
  bool autofocus = false,
  int? maxLength,
  void Function(String)? onChanged,
}) => TextField(
  controller: ctl,
  keyboardType: tipo,
  inputFormatters: formato,
  autofocus: autofocus,
  maxLength: maxLength,
  onChanged: onChanged,
  // Fondo, bordes y colores vienen del tema (inputDecorationTheme de
  // SpTheme): así este campo se ve igual que todos los demás de la app.
  decoration: InputDecoration(hintText: hint),
);

/// Una fila de contacto (teléfono, dirección, email, web) de los perfiles
/// PÚBLICOS de albergue y de negocio aliado: ícono + texto, y opcionalmente
/// tocable (para abrir WhatsApp, el mail o el sitio).
///
/// Estaba duplicada byte a byte en albergue_publico_screen.dart y
/// aliado_publico_screen.dart. No estaba mal en ninguna de las dos — ese es
/// justamente el riesgo: dos copias idénticas envejecen distinto, y el
/// primer arreglo que se aplique en una y no en la otra deja las dos
/// pantallas mostrando el mismo tipo de dato con estilos o comportamientos
/// diferentes, sin que nadie lo note hasta verlas una al lado de la otra
/// (que es exactamente cómo Eliza encontró la divergencia anterior entre
/// estas dos mismas pantallas, ver perfilLabel arriba).
Widget filaContacto(IconData icono, String texto, {VoidCallback? onTap}) =>
    Builder(
      builder: (context) {
        final c = context.sp;
        final fila = Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: c.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icono, size: 16, color: c.primaryStrong),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    texto,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: onTap != null ? c.primaryStrong : c.ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
        return onTap == null
            ? fila
            : GestureDetector(onTap: onTap, child: fila);
      },
    );
