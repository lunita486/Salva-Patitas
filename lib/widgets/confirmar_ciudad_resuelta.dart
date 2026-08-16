import 'package:flutter/material.dart';

import 'campo_pais_telefono.dart';

// ─── Confirmar ciudad resuelta ─────────────────────────────────────────────
// Existe porque un texto mal escrito ("Nedellin") no siempre da `null` en
// UbicacionService.desdeTexto() — puede coincidir con OTRO lugar real en
// cualquier parte del mundo, y el servicio contesta con total confianza.
// No hay forma de detectar eso solo con código (no existe una lista de
// "todas las ciudades del mundo, bien escritas" contra la cual comparar);
// lo único realista es mostrarle a la persona QUÉ se resolvió antes de
// guardar, para que sea ELLA quien note el error, como con cualquier
// buscador de direcciones. Compartido entre los 4 lugares que llaman
// `desdeTexto()` al guardar — antes cada uno hubiera necesitado repetir
// este mismo diálogo por su cuenta.
//
// Devuelve `true` si la persona confirma, `false`/`null` si prefiere
// corregir el texto en vez de guardar lo que se resolvió.
Future<bool> confirmarCiudadResuelta(
  BuildContext context, {
  required String escribiste,
  required String resuelta,
  required String paisCodigo,
  String region = '',
}) async {
  // Sin nombre resuelto (el reverse geocoding falló, best-effort) no hay
  // nada que mostrar para comparar — se deja pasar como antes, no se
  // bloquea un guardado por un dato que es solo un extra informativo.
  if (resuelta.isEmpty) return true;
  final bandera = banderaPais(paisCodigo);
  // La provincia/estado, cuando se conoce, es lo que distingue dos
  // ciudades con el MISMO nombre en el MISMO país ("San José" se repite en
  // decenas de departamentos) — sin esto, dos lugares homónimos pero
  // distintos se ven exactamente igual en este diálogo y la persona no
  // tendría cómo notar que el geocoder eligió el equivocado.
  final nombreCompleto = region.isNotEmpty ? '$resuelta, $region' : resuelta;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('¿Es esta tu ciudad?'),
      content: Text(
        'Escribiste "$escribiste" y encontramos:\n\n'
        '$nombreCompleto${bandera.isNotEmpty ? ' $bandera' : ''}\n\n'
        'Si no es donde queda tu animal/negocio, volvé a escribirla.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text(
            'No, corregir',
            style: TextStyle(color: Colors.grey),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Sí, es correcta'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
