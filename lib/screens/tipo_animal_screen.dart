import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart' show especieChip, especieOpciones, especieChipGap, appInk, msgError;
import '../data/firestore_resiliencia.dart';
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

  /// Antes esto era un `.set()` de Firestore sin `await` ni try/catch —
  /// si fallaba (ej. token de sesión vencido), la pantalla ya mostraba el
  /// filtro nuevo como elegido pero nada se guardaba de verdad: al volver
  /// a entrar, `initState()` releía el valor viejo del servidor y la
  /// preferencia "se olvidaba" sin ningún aviso de por medio (hallazgo de
  /// auditoría de código). Ahora espera la confirmación con
  /// [guardarConAviso] y, si de verdad falla (no si solo está lenta:
  /// [ResultadoGuardado.siguePendiente] significa que Firestore ya la
  /// encoló y la va a aplicar sola), revierte el chip a lo que tenía antes
  /// y avisa — para que la elección que se ve en pantalla sea siempre la
  /// que de verdad está guardada.
  Future<void> _actualizarPreferencia({
    required String campo,
    required String valorNuevo,
    required String valorAnterior,
    required void Function(String) aplicarLocal,
  }) async {
    if (valorNuevo == valorAnterior) return;
    setState(() => aplicarLocal(valorNuevo));
    final resultado = await guardarConAviso(
        () => _userDoc.set({campo: valorNuevo}, SetOptions(merge: true)));
    if (resultado == ResultadoGuardado.fallo && mounted) {
      setState(() => aplicarLocal(valorAnterior));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo guardar tu preferencia. Probá de nuevo.'),
          backgroundColor: msgError));
    }
  }

  Widget _grupo(String label, List<String> opciones, String sel, ValueChanged<String> onSeleccionar) =>
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
            onTap: () => onSeleccionar(o),
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
              onTap: () => _actualizarPreferencia(
                  campo: 'prefEspecie',
                  valorNuevo: especieOpciones[i].$1,
                  valorAnterior: _especie,
                  aplicarLocal: (v) => _especie = v),
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
      _grupo('TAMAÑO', ['Pequeño', 'Mediano', 'Grande', 'Cualquiera'], _tamano, (v) => _actualizarPreferencia(
          campo: 'prefTamano', valorNuevo: v, valorAnterior: _tamano, aplicarLocal: (x) => _tamano = x)),
      const SizedBox(height: 20),
      _grupo('EDAD', ['Cachorro', 'Adulto', 'Senior', 'Cualquiera'], _edad, (v) => _actualizarPreferencia(
          campo: 'prefEdad', valorNuevo: v, valorAnterior: _edad, aplicarLocal: (x) => _edad = x)),
      const SizedBox(height: 24),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text('Te notificaremos cuando llegue un animal que encaje con estas preferencias.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
      ),
    ]),
  );
}
