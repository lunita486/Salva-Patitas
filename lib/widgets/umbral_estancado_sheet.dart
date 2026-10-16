import 'package:flutter/material.dart';

import '../domain/reglas_negocio.dart';
import 'sp_widgets.dart';
import 'chips_seleccionables.dart';

// Hoja para elegir el umbral — compartida entre perfil_rescatista_screen.dart
// y albergue_home_screen.dart (antes vivía privada en la de rescatista, y
// albergue tenía la opción metida adentro de "Editar perfil" en vez de en su
// propia pantalla de Perfil, como el resto de los ajustes de cuenta —
// pedido real de Eliza: estandarizar las dos para que vivan en el mismo
// lugar y se vean igual).
class UmbralEstancadoSheet extends StatefulWidget {
  final int actual;
  const UmbralEstancadoSheet({super.key, required this.actual});
  @override
  State<UmbralEstancadoSheet> createState() => _UmbralEstancadoSheetState();
}

class _UmbralEstancadoSheetState extends State<UmbralEstancadoSheet> {
  late int _umbral;

  @override
  void initState() {
    super.initState();
    _umbral = widget.actual;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SpAgarradera(),
          const SizedBox(height: 14),
          const SpHojaTitulo(
            'Aviso de animal sin adoptar',
            subtitulo:
                'Después de cuánto tiempo sin encontrar hogar querés que te avisemos',
            centrado: true,
          ),
          const SizedBox(height: 20),
          ChipsSeleccionables(
            opciones: [for (final o in umbralEstancadoOpciones) o.$2],
            seleccion: umbralEstancadoOpciones
                .firstWhere(
                  (o) => o.$1 == _umbral,
                  orElse: () => umbralEstancadoOpciones.first,
                )
                .$2,
            onSeleccionar: (etiqueta) => setState(
              () => _umbral = umbralEstancadoOpciones
                  .firstWhere((o) => o.$2 == etiqueta)
                  .$1,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, _umbral),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Guardar',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
