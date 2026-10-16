import 'package:flutter/material.dart';
import '../theme/salva_patitas_theme.dart';

// ─── Helpers globales ─────────────────────────────────────────────────────────

/// Para cuando un StreamBuilder falla (sin conexión, permiso denegado, etc.)
/// — sin esto, `snap.data?.docs ?? []` hace que la pantalla se vea igual que
/// "no hay nada todavía", confundiendo un error real con una lista vacía.
Widget errorFeedState({
  String mensaje = 'No se pudo cargar. Revisá tu conexión e intentá de nuevo.',
}) {
  return Builder(
    builder: (context) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: context.sp.surfaceSunken,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.wifi_off_rounded,
                size: 34,
                color: context.sp.inkMuted,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.sp.inkMuted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
