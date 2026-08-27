import 'package:flutter/material.dart';

import '../theme.dart';

/// Qué decidió la persona frente al aviso de "ya tenés otro con este nombre".
enum AccionDuplicado {
  /// Volver atrás sin guardar nada.
  cancelar,

  /// Abrir la ficha del animal que ya existía, para comparar.
  verFicha,

  /// Son dos animales distintos que se llaman igual. Seguir.
  seguir,
}

/// El aviso de posible animal duplicado, uno solo para toda la app.
///
/// **Por qué es un widget y no está escrito en cada pantalla.** Este aviso
/// existía solo al publicar de a uno. Editar no avisaba nada: se podía
/// renombrar un animal y dejarlo duplicado en silencio (pregunta de Eliza:
/// "¿y qué pasa con el editar? debería validar también"). Copiar el diálogo
/// a la pantalla de editar habría dejado dos textos que hay que acordarse de
/// cambiar juntos, que es exactamente cómo el aviso de duplicados terminó
/// con dos reglas de comparación distintas y una de las dos rota.
///
/// [etiquetaSeguir] es lo único que cambia entre las dos pantallas: al
/// publicar dice "Publicar igual" y al editar "Guardar igual".
Future<AccionDuplicado?> avisarAnimalDuplicado(
  BuildContext context, {
  required String nombre,
  required String especie,
  required String etiquetaSeguir,
}) => showDialog<AccionDuplicado>(
  context: context,
  builder: (dlgCtx) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: const Text('Posible animal duplicado'),
    content: Text(
      'Ya tenés otro animal llamado "$nombre" ($especie). Si es a propósito '
      '(dos animales distintos con el mismo nombre, uno que volvió, etc.) '
      'podés seguir. Si fue sin querer, revisá la ficha existente primero.',
    ),
    // 3 salidas en vez de 2: "Ver ficha existente" además de
    // cancelar/continuar, para no dejar a la usuaria adivinando cuál es el
    // otro animal — antes solo podía cancelar y buscarlo ella misma en
    // "Mis animales".
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dlgCtx, AccionDuplicado.cancelar),
        child: const Text('Cancelar'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(dlgCtx, AccionDuplicado.verFicha),
        child: const Text('Ver ficha existente'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(dlgCtx, AccionDuplicado.seguir),
        child: Text(etiquetaSeguir, style: const TextStyle(color: appTeal)),
      ),
    ],
  ),
);
