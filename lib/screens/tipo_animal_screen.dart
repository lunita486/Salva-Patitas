import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import 'configuracion_screens.dart';

class TipoAnimalScreen extends StatefulWidget {
  const TipoAnimalScreen({super.key});
  @override
  State<TipoAnimalScreen> createState() => _TipoAnimalScreenState();
}

class _TipoAnimalScreenState extends State<TipoAnimalScreen> {
  String _especie = 'Ambos';
  String _tamano  = 'Cualquiera';
  String _edad    = 'Cualquiera';

  @override
  void initState() {
    super.initState();
    prefDoc.get().then((doc) {
      if (doc.exists && mounted) {
        final d = doc.data()!;
        setState(() {
          _especie = d['especie'] ?? 'Ambos';
          _tamano  = d['tamano']  ?? 'Cualquiera';
          _edad    = d['edad']    ?? 'Cualquiera';
        });
      }
    });
  }

  void _guardar() {
    prefDoc.set({'especie': _especie, 'tamano': _tamano, 'edad': _edad}, SetOptions(merge: true));
  }

  Widget _grupo(String label, List<String> opciones, String sel, ValueChanged<String> onChange) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
            letterSpacing: 1.1, color: Colors.grey.shade500)),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: opciones.map((o) {
          final active = o == sel;
          return GestureDetector(
            onTap: () { onChange(o); _guardar(); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                color: active ? const Color(0xFF1A1A1A) : Colors.white.withOpacity(0.88),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: active ? const Color(0xFF1A1A1A) : Colors.grey.shade300),
              ),
              child: Text(o, style: TextStyle(
                  color: active ? Colors.white : Colors.grey.shade700,
                  fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          );
        }).toList()),
      ),
    ]);

  @override
  Widget build(BuildContext context) => SettingsPageScaffold(
    title: 'Tipo de animal preferido',
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 4),
      _grupo('ESPECIE', ['Perro', 'Gato', 'Ambos'], _especie, (v) => setState(() => _especie = v)),
      const SizedBox(height: 20),
      _grupo('TAMAÑO', ['Pequeño', 'Mediano', 'Grande', 'Cualquiera'], _tamano, (v) => setState(() => _tamano = v)),
      const SizedBox(height: 20),
      _grupo('EDAD', ['Cachorro', 'Adulto', 'Senior', 'Cualquiera'], _edad, (v) => setState(() => _edad = v)),
      const SizedBox(height: 24),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text('Te notificaremos cuando llegue un animal que encaje con estas preferencias.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      ),
    ]),
  );
}
