import 'package:flutter/material.dart';
import '../theme.dart';

class SettingsPageScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  const SettingsPageScaffold({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: appBg,
    body: Stack(fit: StackFit.expand, children: [
      const LeafOverlay(),
      SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Row(children: [
            // IconButton en vez de GestureDetector+Icon a mano: antes el
            // área tocable era del tamaño del ícono solo (20px), bastante
            // por debajo del mínimo recomendado (~48dp) — IconButton ya
            // trae ese padding tocable de forma nativa. Hallazgo de
            // auditoría de código.
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: appInk),
              tooltip: 'Volver',
              onPressed: () => Navigator.pop(context),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(fontSize: 18,
                fontWeight: FontWeight.bold, color: appInk)),
          ]),
        ),
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 40),
          child: child,
        )),
      ])),
    ]),
  );
}

class SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final bool last;
  final ValueChanged<bool> onChanged;
  const SettingsSwitchTile({super.key, required this.icon, required this.label, required this.subtitle,
      required this.value, required this.onChanged, this.last = false});

  @override
  Widget build(BuildContext context) => Semantics(
    // Sin esto, un lector de pantalla anunciaba el ícono, el label, el
    // subtítulo y el interruptor como 4 piezas sueltas en vez de un solo
    // control con su estado (activado/desactivado). Hallazgo de auditoría
    // de código.
    label: '$label. $subtitle',
    toggled: value,
    child: Container(
    margin: const EdgeInsets.symmetric(horizontal: 20),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.8),
      borderRadius: BorderRadius.only(
        topLeft:     Radius.circular(last ? 0 : 16),
        topRight:    Radius.circular(last ? 0 : 16),
        bottomLeft:  Radius.circular(last ? 16 : 0),
        bottomRight: Radius.circular(last ? 16 : 0),
      ),
      border: last ? null : Border(bottom: BorderSide(color: Colors.grey.shade100)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(children: [
      Icon(icon, size: 22, color: Colors.grey.shade600),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
      ])),
      // activeThumbColor, no el activeColor deprecado desde Flutter 3.31.
      Switch(value: value, onChanged: onChanged, activeThumbColor: appTeal),
    ]),
    ),
  );
}
