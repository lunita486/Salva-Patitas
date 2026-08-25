import 'package:flutter/material.dart';
import '../data/auth_helper.dart';
import '../theme.dart';

/// El diálogo de "¿Seguro que quieres cerrar sesión?" — vivía copiado en
/// las 4 pantallas de Perfil (adoptante, rescatista, albergue, aliado),
/// con 2 de las 4 copias sin el `popUntil` que vuelve al inicio después de
/// salir (quedaban mostrando la pantalla vieja hasta que algo más
/// disparara una navegación). Hallazgo de auditoría de código.
Future<void> mostrarDialogoCerrarSesion(BuildContext context) => showDialog<void>(
  context: context,
  builder: (dlgCtx) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: const Text('Cerrar sesión'),
    content: const Text('¿Seguro que quieres cerrar sesión?'),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dlgCtx),
        child: const Text('Cancelar'),
      ),
      TextButton(
        onPressed: () async {
          Navigator.pop(dlgCtx);
          final ok = await cerrarSesion();
          if (!context.mounted) return;
          if (ok) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: msgError,
                content: Text('Esperá unos segundos e intentá de nuevo.'),
              ),
            );
          }
        },
        child: const Text('Cerrar sesión', style: TextStyle(color: Colors.red)),
      ),
    ],
  ),
);
