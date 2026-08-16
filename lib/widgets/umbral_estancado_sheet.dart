import 'package:flutter/material.dart';

import '../domain/reglas_negocio.dart';
import '../theme.dart';

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
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Aviso de animal sin adoptar',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Después de cuánto tiempo sin encontrar hogar querés que te avisemos',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: umbralEstancadoOpciones.map((o) {
              final sel = o.$1 == _umbral;
              return GestureDetector(
                onTap: () => setState(() => _umbral = o.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: sel ? appOrange : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: sel ? appOrange : Colors.grey.shade200,
                    ),
                  ),
                  child: Text(
                    o.$2,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : appInk,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, _umbral),
              style: ElevatedButton.styleFrom(
                backgroundColor: appTeal,
                foregroundColor: Colors.white,
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
