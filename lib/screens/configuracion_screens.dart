import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';

// Documento compartido de preferencias del adoptante
final prefDoc = FirebaseFirestore.instance.collection('preferencias').doc('adoptante');

class SettingsPageScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  const SettingsPageScaffold({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: appBg,
    body: Stack(fit: StackFit.expand, children: [
      CustomPaint(painter: LeafPainter()),
      SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Icon(Icons.arrow_back_ios_new, size: 20, color: Color(0xFF1A1A1A)),
            ),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(fontSize: 18,
                fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
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
  const SettingsSwitchTile({required this.icon, required this.label, required this.subtitle,
      required this.value, required this.onChanged, this.last = false});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 20),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.8),
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
        Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      ])),
      Switch(value: value, onChanged: onChanged, activeColor: appTeal),
    ]),
  );
}
