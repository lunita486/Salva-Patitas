import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/usuarios_repository.dart';
import '../theme.dart';

// ─── Selector de rol (solo debug) ──────────────────────────────────────────
// Un mismo copy-paste de este diálogo vivía en 5 pantallas distintas
// (home_screen.dart, aliado_home_screen.dart, albergue_home_screen.dart,
// albergue_perfil_screen.dart, aliado_perfil_screen.dart), cada una gateada
// por su propio `if (kDebugMode)` — cero riesgo en producción (nunca
// compila en release), pero cualquier cambio futuro (agregar un rol, por
// ejemplo) necesitaba acordarse de tocar las 5 por separado. Hallazgo de
// auditoría de código.
Future<void> mostrarCambiarRolDebug(BuildContext context) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  const opciones = <String, List<String>>{
    'Solo Adoptante': ['adoptante'],
    'Solo Rescatista': ['rescatista'],
    'Adoptante + Rescatista': ['adoptante', 'rescatista'],
    'Albergue': ['albergue'],
    'Aliado': ['aliado'],
  };
  final sel = await showDialog<List<String>>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('🛠 Cambiar rol (DEBUG)'),
      children: opciones.entries
          .map(
            (e) => SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, e.value),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(e.key),
              ),
            ),
          )
          .toList(),
    ),
  );
  if (sel == null || !context.mounted) return;
  try {
    await UsuariosRepository().actualizarRoles(uid, sel);
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'No se pudo cambiar el rol. Revisá tu conexión e intentá de nuevo.',
        ),
        backgroundColor: msgError,
      ),
    );
  }
}
