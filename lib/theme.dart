// Tokens de diseño — colores y mapeos visuales reutilizados en toda la
// app. Nada de layout ni de widgets acá, solo valores; ver lib/widgets/
// y lib/domain/ para todo lo que se separó de este archivo (antes 2350
// líneas mezclando tokens, widgets y funciones utilitarias — ver
// ARCHITECTURE.md, sección "Capa 4").
import 'package:flutter/material.dart';

// ─── Constantes de color ──────────────────────────────────────────────────────

const appBg = Color(0xFFDFFBEC);
const appDark = Color(0xFF162416);
const appTeal = Color(0xFF1F8A62);
const appOrange = Color(0xFFD84E18);
// El negro casi puro que en la práctica se usa para casi todo el texto de
// la app (0xFF1A1A1A) — antes escrito a mano en decenas de lugares, sin
// ningún token que lo agrupara (a diferencia de appDark, que existía pero
// casi no se usaba). Mismo valor exacto, solo con nombre — no cambia
// ningún color en pantalla, unifica cómo se referencia.
const appInk = Color(0xFF1A1A1A);

// ─── Colores semánticos para SnackBars ───────────────────────────────────────
// Antes, de 72 SnackBars en toda la app, solo 6 tenían un color puesto a
// propósito (appTeal para éxito, naranja suelto para "pasó pero a medias")
// — el resto caía en el gris casi negro por default de Flutter, sin ningún
// criterio: un error de conexión, un campo faltante y "publicación
// eliminada" se veían todos igual (lo que notó Eliza probando: "sale el
// mensaje negro ese feo"). Estos 3 nombres son el criterio único de acá en
// más — msgError para lo que bloqueó la acción, msgAdvertencia para lo que
// pasó pero quedó a medias, msgExito para confirmaciones. Reusan colores
// que la app ya tenía (el rojo de Eliminar/urgente, el naranja de marca, y
// el verde de siempre) — no son colores nuevos.
const msgError = Color(0xFFD32F2F);
const msgAdvertencia = appOrange;
const msgExito = appTeal;

// ─── Ícono/color por tipo de negocio aliado ──────────────────────────────────
// Un solo mapeo, reutilizado en la grilla de "Negocios aliados"
// (adoptante_feed_screen.dart) y en el encabezado del perfil público del
// aliado — así el mismo tipo (ej. "Veterinaria") se ve siempre con el mismo
// ícono en toda la app, en vez de repetir un switch en cada pantalla.
// Colores pastel (no los saturados de un mockup de referencia) para que
// combinen con el resto de la paleta de la app en vez de competir con ella.
IconData aliadoTipoIcono(String tipo) => switch (tipo) {
  'Veterinaria' => Icons.medical_services_outlined,
  'Tienda de mascotas' => Icons.shopping_bag_outlined,
  'Spa canino' => Icons.self_improvement,
  'Peluquería canina' => Icons.content_cut,
  _ => Icons.pets,
};

Color aliadoTipoColorPastel(String tipo) => switch (tipo) {
  'Veterinaria' => const Color(0xFFD8ECE6),
  'Tienda de mascotas' => const Color(0xFFFBE3D3),
  'Spa canino' => const Color(0xFFE6DFF4),
  'Peluquería canina' => const Color(0xFFFAE0E7),
  _ => const Color(0xFFE7EFEA),
};

Color aliadoTipoColorTexto(String tipo) => switch (tipo) {
  'Veterinaria' => appTeal,
  'Tienda de mascotas' => const Color(0xFFB0501C),
  'Spa canino' => const Color(0xFF6C4FA0),
  'Peluquería canina' => const Color(0xFFC2447A),
  _ => const Color(0xFF5F6F68),
};

Color cicloColor(String s) => switch (s) {
  'En cuidado' => appTeal,
  'Rescatado' => appTeal,
  'Hogar de paso' => const Color(0xFF7C6FCD),
  'En proceso de adopción' => const Color(0xFFE65100),
  'Adoptado' => const Color(0xFF2196F3),
  'Regresado' => const Color(0xFFD32F2F),
  'Fallecido' => const Color(0xFF78909C),
  'Estancados' => appOrange,
  _ => Colors.grey,
};
