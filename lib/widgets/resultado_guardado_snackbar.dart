import 'package:flutter/material.dart';
import '../data/firestore_resiliencia.dart';
import '../theme.dart';

/// Muestra el SnackBar que corresponde a un [ResultadoGuardado] —
/// `guardarConAviso()` (firestore_resiliencia.dart) ya centralizó CÓMO
/// decidir el resultado, pero la traducción de ese resultado a un aviso en
/// pantalla se seguía escribiendo a mano en cada pantalla que lo usaba: 10
/// copias del mismo switch de 3 ramas, con 4 redacciones distintas para el
/// mismo estado "todavía no confirmó" ("se va a guardar solo", "tu perfil
/// se va a actualizar solo", "se va a eliminar solo"…). Hallazgo de
/// auditoría de código.
///
/// Consolida SOLO la construcción del aviso — el llamador sigue siendo
/// dueño de qué hacer DESPUÉS (cerrar la pantalla, no hacer nada, etc.),
/// porque eso sí varía genuinamente de una pantalla a otra.
///
/// [exito]: `null` (el default) si esa pantalla no muestra nada en el
/// camino feliz — ej. togglear un switch o borrar una tarjeta, donde el
/// cambio ya se ve solo en la lista y un SnackBar sería redundante.
void mostrarResultadoGuardado(
  BuildContext context,
  ResultadoGuardado resultado, {
  String? exito,
  String pendiente =
      'Esto está tardando. Se va a guardar solo apenas vuelva la señal.',
  String fallo = 'No se pudo guardar. Revisá tu conexión e intentá de nuevo.',
}) {
  if (!context.mounted) return;
  final String? mensaje;
  final Color color;
  switch (resultado) {
    case ResultadoGuardado.confirmado:
      mensaje = exito;
      color = msgExito;
    case ResultadoGuardado.siguePendiente:
      mensaje = pendiente;
      color = msgAdvertencia;
    case ResultadoGuardado.fallo:
      mensaje = fallo;
      color = msgError;
  }
  if (mensaje == null) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(mensaje), backgroundColor: color));
}
