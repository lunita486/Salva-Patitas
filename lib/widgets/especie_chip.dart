import 'package:flutter/material.dart';

import 'sp_widgets.dart';

// ─── Chip de especie (Todos/Perros/Gatos/Otros) ──────────────────────────────
// Un solo widget y una sola lista de opciones, reutilizados en el feed
// (adoptante_feed_screen.dart) y en el perfil (tipo_animal_screen.dart) para
// la misma preferencia (`prefEspecie`) — antes el perfil tenía su propio
// estilo (pastillas negro/blanco, sin íconos) y su propio orden distinto al
// del feed, dos versiones visualmente distintas de lo mismo (lo que notó
// Eliza: "lindos en un lado, feos en el perfil").
//
// El valor real (lo que se guarda y se compara) va primero en cada tupla;
// el label (con su emoji) es solo lo que se muestra — así "Ambos" se sigue
// guardando igual que siempre aunque en pantalla diga "Todos".
// Los emojis del label se cambiaron por el animalito 3D de cada especie
// (rediseño), que va dibujado al lado del texto.
const especieOpciones = [
  ('Ambos', 'Todos'),
  ('Perro', 'Perros'),
  ('Gato', 'Gatos'),
  ('Otro', 'Otros'),
];

// Espacio entre chips — un solo número compartido por el feed y el perfil,
// para que los 4 (Todos/Perros/Gatos/Otros) entren sin deslizar en la
// mayoría de los teléfonos (sugerencia real de Eliza).
const especieChipGap = 6.0;

/// Chip 3D (`SpChip`) con el animalito de la especie al lado. "Todos"
/// ('Ambos') va sin animalito.
Widget especieChip({
  required String valor,
  required String label,
  required bool active,
  required VoidCallback onTap,
}) => SpChip(
  label: label,
  selected: active,
  animal: valor == 'Ambos' ? null : spEspecie(valor).$2,
  onTap: onTap,
);
