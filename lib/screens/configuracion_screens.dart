import 'package:flutter/material.dart';
import '../widgets/sp_widgets.dart';
import '../theme/salva_patitas_theme.dart';

class SettingsPageScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  const SettingsPageScaffold({
    super.key,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.sp.bg,
    body: Stack(
      fit: StackFit.expand,
      children: [
        const SpPawBackground(),
        SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SpScreenHeader(title: title),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final bool last;
  final ValueChanged<bool> onChanged;
  const SettingsSwitchTile({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    return Semantics(
      // Sin esto, un lector de pantalla anunciaba el ícono, el label, el
      // subtítulo y el interruptor como 4 piezas sueltas en vez de un solo
      // control con su estado (activado/desactivado). Hallazgo de auditoría
      // de código.
      label: '$label. $subtitle',
      toggled: value,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(last ? 0 : 16),
            topRight: Radius.circular(last ? 0 : 16),
            bottomLeft: Radius.circular(last ? 16 : 0),
            bottomRight: Radius.circular(last ? 16 : 0),
          ),
          border: last ? null : Border(bottom: BorderSide(color: c.line)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: c.primaryStrong),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: c.inkMuted),
                  ),
                ],
              ),
            ),
            // activeThumbColor, no el activeColor deprecado desde Flutter 3.31.
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: c.onPrimary,
              activeTrackColor: c.primary,
            ),
          ],
        ),
      ),
    );
  }
}
