import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/salva_patitas_theme.dart';
import '../widgets/sp_widgets.dart';
import '../widgets/chips_seleccionables.dart';
import '../widgets/especie_chip.dart';
import '../data/firestore_resiliencia.dart';
import 'configuracion_screens.dart';

class TipoAnimalScreen extends StatefulWidget {
  const TipoAnimalScreen({super.key});
  @override
  State<TipoAnimalScreen> createState() => _TipoAnimalScreenState();
}

class _TipoAnimalScreenState extends State<TipoAnimalScreen> {
  String _especie = 'Ambos';
  String _tamano = 'Cualquiera';
  String _edad = 'Cualquiera';
  bool _errorCarga = false;

  DocumentReference get _userDoc => FirebaseFirestore.instance
      .collection('usuarios')
      .doc(FirebaseAuth.instance.currentUser?.uid ?? 'anon');

  @override
  void initState() {
    super.initState();
    _userDoc
        .get()
        .then((doc) {
          if (doc.exists && mounted) {
            final d = doc.data() as Map<String, dynamic>;
            setState(() {
              _especie = d['prefEspecie'] ?? 'Ambos';
              _tamano = d['prefTamano'] ?? 'Cualquiera';
              _edad = d['prefEdad'] ?? 'Cualquiera';
            });
          }
        })
        .catchError((_) {
          // Antes esto no tenía ningún manejo de error: si la carga inicial
          // fallaba (ej. sin señal al abrir esta pantalla), la excepción
          // quedaba sin atrapar y la pantalla mostraba los valores por
          // defecto (Ambos/Cualquiera) como si fueran tus preferencias reales
          // guardadas, sin ningún aviso de que en realidad no se pudieron
          // leer. Hallazgo de auditoría de código.
          if (mounted) setState(() => _errorCarga = true);
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
      () => _userDoc.set({campo: valorNuevo}, SetOptions(merge: true)),
    );
    if (resultado == ResultadoGuardado.fallo && mounted) {
      setState(() => aplicarLocal(valorAnterior));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'No se pudo guardar tu preferencia. Probá de nuevo.',
          ),
          backgroundColor: context.sp.msgError,
        ),
      );
    }
  }

  /// Etiqueta de cada grupo, dentro de la tarjeta.
  Widget _etiqueta(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      t,
      style: SpText.label.copyWith(
        color: context.sp.inkMuted,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  // ChipsSeleccionables (widgets/chips_seleccionables.dart) hace la grilla
  // en sí (Wrap, nunca scroll oculto). Antes esto tenía su propia copia
  // entera de la lógica, con un scroll horizontal sin ninguna señal de que
  // había más opciones fuera de vista — bug real reportado por Eliza.
  Widget _grupo(
    String label,
    List<String> opciones,
    String sel,
    ValueChanged<String> onSeleccionar,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _etiqueta(label),
      ChipsSeleccionables(
        opciones: opciones,
        seleccion: sel,
        onSeleccionar: onSeleccionar,
        paddingChip: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      ),
    ],
  );

  // ESPECIE usa especieChip + especieOpciones (widgets/especie_chip.dart):
  // el mismo chip con animalito y el mismo orden (Todos primero) que el feed
  // del adoptante (sugerencia real de Eliza: "lindos en el feed, feos en el
  // perfil"). Wrap, para que no quede ninguno escondido.
  Widget _grupoEspecie() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _etiqueta('Especie'),
      Wrap(
        spacing: especieChipGap + 2,
        runSpacing: 10,
        children: [
          for (int i = 0; i < especieOpciones.length; i++)
            especieChip(
              valor: especieOpciones[i].$1,
              label: especieOpciones[i].$2,
              active: _especie == especieOpciones[i].$1,
              onTap: () => _actualizarPreferencia(
                campo: 'prefEspecie',
                valorNuevo: especieOpciones[i].$1,
                valorAnterior: _especie,
                aplicarLocal: (v) => _especie = v,
              ),
            ),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    return SettingsPageScaffold(
      title: 'Animal preferido',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_errorCarga)
              SpNotice(
                fondo: c.accentSoft,
                tinta: c.accentInk,
                child: const Text(
                  'No pudimos cargar tus preferencias guardadas: esto que ves '
                  'abajo son los valores por defecto, no necesariamente lo que '
                  'ya tenías elegido. Revisá tu conexión y volvé a entrar.',
                ),
              ),
            const SpSectionTitle('¿Qué animal buscas?'),
            const SizedBox(height: SpSpace.s3),
            SpCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _grupoEspecie(),
                  const SizedBox(height: 20),
                  _grupo(
                    'Tamaño',
                    ['Pequeño', 'Mediano', 'Grande', 'Cualquiera'],
                    _tamano,
                    (v) => _actualizarPreferencia(
                      campo: 'prefTamano',
                      valorNuevo: v,
                      valorAnterior: _tamano,
                      aplicarLocal: (x) => _tamano = x,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _grupo(
                    'Edad',
                    ['Cachorro', 'Adulto', 'Senior', 'Cualquiera'],
                    _edad,
                    (v) => _actualizarPreferencia(
                      campo: 'prefEdad',
                      valorNuevo: v,
                      valorAnterior: _edad,
                      aplicarLocal: (x) => _edad = x,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: SpSpace.s4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.notifications_active_outlined,
                  size: 18,
                  color: c.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Te notificaremos cuando llegue un animal que encaje con estas preferencias.',
                    style: SpText.caption.copyWith(color: c.inkMuted),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
