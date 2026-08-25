import 'package:flutter/material.dart';

/// Los dos diálogos del flujo de "eliminar un animal" — vivían copiados
/// byte a byte en mis_rescates_screen.dart y editar_rescate_screen.dart
/// (las dos pantallas que tienen el botón de borrar). Hallazgo de
/// auditoría de código.

/// El aviso de "no se puede eliminar todavía" (animal Adoptado/Fallecido,
/// o con una solicitud pendiente) — solo informa, un único botón.
/// [bloqueo] es el (título, mensaje) que ya devuelve
/// `RescatesRepository.bloqueoParaEliminar`.
Future<void> mostrarBloqueoEliminarRescate(
  BuildContext context,
  (String, String) bloqueo,
) => showDialog<void>(
  context: context,
  builder: (dlgCtx) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: Text(bloqueo.$1),
    content: Text(bloqueo.$2),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dlgCtx),
        child: const Text('Entendido'),
      ),
    ],
  ),
);

/// El "¿seguro que querés eliminar?" — true si confirmó.
Future<bool> confirmarEliminarRescate(BuildContext context, String nombre) async {
  final confirmar = await showDialog<bool>(
    context: context,
    builder: (dlgCtx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Eliminar publicación'),
      content: Text(
        '¿Seguro que quieres eliminar a $nombre? Esta acción no se puede deshacer.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dlgCtx, false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dlgCtx, true),
          child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
  return confirmar == true;
}
