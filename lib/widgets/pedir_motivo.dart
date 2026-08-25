import 'package:flutter/material.dart';

import '../theme.dart';

/// Pide un texto libre (un motivo, una nota) en un diálogo. Devuelve lo
/// escrito —que puede ser vacío, el motivo nunca es obligatorio— o `null`
/// si se canceló.
///
/// **Existe por un bug, no por prolijidad.** Este diálogo estaba escrito a
/// mano TRES veces (cambiar estado a Regresado/Fallecido en
/// `cambiar_estado_sheet.dart`, y rechazar una solicitud en
/// `solicitudes_preview.dart` y
/// `solicitudes_rescatista_screen.dart`), y las tres tenían exactamente la
/// misma falla: creaban el `TextEditingController` afuera y lo liberaban
/// con `.then((_) => ctrl.dispose())` sobre el `showDialog`.
///
/// Ese Future se completa apenas alguien llama `Navigator.pop`, **no**
/// cuando el diálogo termina de cerrarse. Así que el controller se destruía
/// mientras el `TextField` seguía en pantalla animándose hacia afuera, y al
/// desmontarse ese campo intentaba soltar su listener sobre un controller ya
/// destruido: `A TextEditingController was used after being disposed`, con
/// la pantalla roja de error de Flutter por lo que durara la animación.
/// Hallazgo real de Eliza marcando un animal como 'Regresado': "salió un
/// mensaje rojo feo con letras amarillas así súper rápido y luego cambió el
/// estado". Las tres copias tenían además un comentario explicando por qué
/// `.then()` era necesario — ninguno se dio cuenta de que tampoco alcanzaba.
///
/// La regla que esto hace cumplir por construcción: **un controller se
/// libera en el `dispose()` del State que lo creó**, nunca desde afuera
/// adivinando cuándo dejó de usarse.
Future<String?> pedirMotivo(
  BuildContext context, {
  required String titulo,
  String textoInicial = '',
  String hint = '',
  String etiquetaConfirmar = 'Confirmar',
  Color colorConfirmar = const Color(0xFFD32F2F),
  // true = botón relleno (ElevatedButton), false = de texto — para que cada
  // pantalla conserve el aspecto que ya tenía.
  bool confirmarRelleno = false,
  int maxLines = 3,
  // 500: bastante para una explicación real (motivo de rechazo, nota de
  // regresado/fallecido) sin llegar al tope técnico del mensaje de chat
  // (2000, ver ChatsRepository.registrarMensaje) donde termina viajando
  // este texto — ese es el límite del SERVIDOR, no el que tiene sentido
  // pedirle a la persona que llene acá. Antes este diálogo no tenía NINGÚN
  // tope ni contador, a diferencia de cualquier otro campo de texto libre
  // de la app. Hallazgo real de Eliza. `maxLength` sin overridear
  // `counterText` a propósito: acá SÍ conviene que se vea el contador (es
  // un diálogo dedicado a escribir una explicación, no la barra chica de
  // chat_screen.dart, que lo oculta por espacio).
  int maxLength = 500,
  bool autofocus = false,
  double radioDialogo = 0,
  double radioCampo = 0,
}) => showDialog<String>(
  context: context,
  builder: (_) => _MotivoDialog(
    titulo: titulo,
    textoInicial: textoInicial,
    hint: hint,
    etiquetaConfirmar: etiquetaConfirmar,
    colorConfirmar: colorConfirmar,
    confirmarRelleno: confirmarRelleno,
    maxLines: maxLines,
    maxLength: maxLength,
    autofocus: autofocus,
    radioDialogo: radioDialogo,
    radioCampo: radioCampo,
  ),
);

class _MotivoDialog extends StatefulWidget {
  final String titulo;
  final String textoInicial;
  final String hint;
  final String etiquetaConfirmar;
  final Color colorConfirmar;
  final bool confirmarRelleno;
  final int maxLines;
  final int maxLength;
  final bool autofocus;
  final double radioDialogo;
  final double radioCampo;
  const _MotivoDialog({
    required this.titulo,
    required this.textoInicial,
    required this.hint,
    required this.etiquetaConfirmar,
    required this.colorConfirmar,
    required this.confirmarRelleno,
    required this.maxLines,
    required this.maxLength,
    required this.autofocus,
    required this.radioDialogo,
    required this.radioCampo,
  });

  @override
  State<_MotivoDialog> createState() => _MotivoDialogState();
}

class _MotivoDialogState extends State<_MotivoDialog> {
  late final _ctrl = TextEditingController(text: widget.textoInicial);

  // Acá está el arreglo: el State es dueño del controller, así que Flutter
  // lo libera exactamente cuando este widget se desmonta — ni antes (el bug
  // de la pantalla roja) ni nunca (la fuga que el `.then()` intentaba
  // evitar).
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bordeCampo = widget.radioCampo > 0
        ? OutlineInputBorder(
            borderRadius: BorderRadius.circular(widget.radioCampo),
          )
        : const OutlineInputBorder();
    return AlertDialog(
      shape: widget.radioDialogo > 0
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(widget.radioDialogo),
            )
          : null,
      title: Text(widget.titulo),
      content: TextField(
        controller: _ctrl,
        maxLines: widget.maxLines,
        maxLength: widget.maxLength,
        autofocus: widget.autofocus,
        decoration: InputDecoration(
          hintText: widget.hint,
          border: bordeCampo,
          focusedBorder: widget.radioCampo > 0
              ? OutlineInputBorder(
                  borderRadius: BorderRadius.circular(widget.radioCampo),
                  borderSide: const BorderSide(color: appTeal, width: 2),
                )
              : null,
        ),
      ),
      actions: [
        TextButton(
          // null, no '': cancelar no es "sin motivo", es "no hagas nada".
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        if (widget.confirmarRelleno)
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.colorConfirmar,
            ),
            onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
            child: Text(
              widget.etiquetaConfirmar,
              style: const TextStyle(color: Colors.white),
            ),
          )
        else
          TextButton(
            onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
            child: Text(
              widget.etiquetaConfirmar,
              style: TextStyle(color: widget.colorConfirmar),
            ),
          ),
      ],
    );
  }
}
