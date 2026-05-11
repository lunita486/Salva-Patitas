import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import 'configuracion_screens.dart';

class UbicacionAlcanceScreen extends StatefulWidget {
  const UbicacionAlcanceScreen({super.key});
  @override
  State<UbicacionAlcanceScreen> createState() => _UbicacionAlcanceScreenState();
}

class _UbicacionAlcanceScreenState extends State<UbicacionAlcanceScreen> {
  String _radio = '10 km';
  final _radios = ['2 km', '5 km', '10 km', '20 km', 'Toda Medellín'];

  @override
  void initState() {
    super.initState();
    prefDoc.get().then((doc) {
      if (doc.exists && mounted) {
        setState(() => _radio = doc.data()!['radio'] ?? '10 km');
      }
    });
  }

  @override
  Widget build(BuildContext context) => SettingsPageScaffold(
    title: 'Ubicación y alcance',
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Text('Muéstrame animales a menos de:',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
      ),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.8),
            borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: _radios.asMap().entries.map((e) {
            final last = e.key == _radios.length - 1;
            final sel  = e.value == _radio;
            return GestureDetector(
              onTap: () {
                setState(() => _radio = e.value);
                prefDoc.set({'radio': e.value}, SetOptions(merge: true));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                decoration: BoxDecoration(
                  border: last ? null : Border(bottom: BorderSide(color: Colors.grey.shade100)),
                ),
                child: Row(children: [
                  Expanded(child: Text(e.value,
                      style: TextStyle(fontSize: 15,
                          fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                          color: sel ? appTeal : const Color(0xFF1A1A1A)))),
                  if (sel) const Icon(Icons.check, color: appTeal, size: 20),
                ]),
              ),
            );
          }).toList(),
        ),
      ),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text('Los animales fuera de este radio no aparecerán en tu feed.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      ),
    ]),
  );
}
