import 'package:flutter/material.dart';

import '../theme.dart';

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
const especieOpciones = [
  ('Ambos', 'Todos'),
  ('Perro', '🐕 Perros'),
  ('Gato', '🐈 Gatos'),
  ('Otro', '🐾 Otros'),
];

// Espacio entre chips — un solo número compartido por el feed y el perfil,
// junto con el padding/letra de acá abajo, para que los 4 (Todos/Perros/
// Gatos/Otros) entren sin deslizar en la mayoría de los teléfonos (antes
// con padding 14/letra 12.5 el cuarto chip quedaba cortado y había que
// deslizar — sugerencia real de Eliza).
const especieChipGap = 6.0;

Widget especieChip({
  required String label,
  required bool active,
  required VoidCallback onTap,
}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? appTeal : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? appTeal : Colors.grey.shade300),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: active ? Colors.white : appInk,
        ),
      ),
    ),
  );
}
