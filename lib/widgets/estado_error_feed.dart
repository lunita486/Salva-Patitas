import 'package:flutter/material.dart';

// ─── Helpers globales ─────────────────────────────────────────────────────────

/// Para cuando un StreamBuilder falla (sin conexión, permiso denegado, etc.)
/// — sin esto, `snap.data?.docs ?? []` hace que la pantalla se vea igual que
/// "no hay nada todavía", confundiendo un error real con una lista vacía.
Widget errorFeedState({
  String mensaje = 'No se pudo cargar. Revisá tu conexión e intentá de nuevo.',
}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            mensaje,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
              height: 1.4,
            ),
          ),
        ],
      ),
    ),
  );
}
