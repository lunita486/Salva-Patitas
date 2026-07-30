import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart' show especieChip, especieOpciones, especieChipGap, appInk;
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

  DocumentReference get _userDoc => FirebaseFirestore.instance
      .collection('usuarios')
      .doc(FirebaseAuth.instance.currentUser?.uid ?? 'anon');

  @override
  void initState() {
    super.initState();
    _userDoc.get().then((doc) {
      if (doc.exists && mounted) {
        final d = doc.data() as Map<String, dynamic>;
        setState(() {
          _especie = d['prefEspecie'] ?? 'Ambos';
          _tamano  = d['prefTamano']  ?? 'Cualquiera';
          _edad    = d['prefEdad']    ?? 'Cualquiera';
        });
      }
    });
  }

  void _guardar() {
    _userDoc.set({
      'prefEspecie': _especie,
      'prefTamano':  _tamano,
      'prefEdad':    _edad,
    }, SetOptions(merge: true));
  }

  Widget _grupo(String label, List<String> opciones, String sel, ValueChanged<String> onChange) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
            letterSpacing: 1.1, color: Colors.grey.shade700)),
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
                color: active ? appInk : Colors.white.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: active ? appInk : Colors.grey.shade300),
              ),
              child: Text(o, style: TextStyle(
                  color: active ? Colors.white : Colors.grey.shade700,
                  fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          );
        }).toList()),
      ),
    ]);

  // ESPECIE usa un widget y un orden distintos a TAMAÑO/EDAD (especieChip +
  // especieOpciones, de theme.dart) — el mismo chip con ícono y el mismo
  // orden (Todos primero) que ya se ve en el feed del adoptante, en vez de
  // la pastilla negro/blanco genérica de acá que antes no combinaba
  // (sugerencia real de Eliza: "lindos en el feed, feos en el perfil").
  Widget _grupoEspecie() =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        child: Text('ESPECIE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
            letterSpacing: 1.1, color: Colors.grey.shade700)),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          for (int i = 0; i < especieOpciones.length; i++) ...[
            if (i > 0) const SizedBox(width: especieChipGap),
            especieChip(
              label: especieOpciones[i].$2,
              active: _especie == especieOpciones[i].$1,
              onTap: () { setState(() => _especie = especieOpciones[i].$1); _guardar(); },
            ),
          ],
        ]),
      ),
    ]);

  @override
  Widget build(BuildContext context) => SettingsPageScaffold(
    title: 'Tipo de animal preferido',
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 4),
      _grupoEspecie(),
      const SizedBox(height: 20),
      _grupo('TAMAÑO', ['Pequeño', 'Mediano', 'Grande', 'Cualquiera'], _tamano, (v) => setState(() => _tamano = v)),
      const SizedBox(height: 20),
      _grupo('EDAD', ['Cachorro', 'Adulto', 'Senior', 'Cualquiera'], _edad, (v) => setState(() => _edad = v)),
      const SizedBox(height: 24),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text('Te notificaremos cuando llegue un animal que encaje con estas preferencias.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
      ),
    ]),
  );
}
