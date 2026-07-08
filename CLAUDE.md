# Salva Patitas

App de Flutter + Firebase para conectar animales rescatados con adoptantes,
hogares de paso, y negocios aliados (veterinarias, peluquerías, etc).

## Acceso a datos — leer antes de tocar Firestore

El acceso a `rescates`, `solicitudes` y `preferencias`, y la escritura de
`usuarios.roles`, pasa **siempre** por `lib/data/` (repositorios) — nunca
`FirebaseFirestore.instance.collection(...)` directo en una pantalla de
`lib/screens/` para esas colecciones.

Razón: una misma cuenta puede tener varios roles a la vez (`rescatista` +
`albergue`, por ejemplo), y ese doble rol causó 3 bugs de datos cruzados en
una sola sesión antes de que existiera esta capa. Ver **[ARCHITECTURE.md](ARCHITECTURE.md)**
para la explicación completa y el checklist de qué hacer al agregar una
pantalla nueva.

Las Reglas de Seguridad de Firestore (`firestore.rules`) son la barrera
real — el filtrado del lado del cliente es solo para no traer datos de más,
nunca asumas que un filtro en Dart alcanza para seguridad.

## Antes de dar por terminado un cambio

- `flutter analyze` sin errores nuevos (los "info" preexistentes de
  `withOpacity` deprecado no son parte de este trabajo, no hace falta
  arreglarlos salvo que se toque esa línea igual).
- Si tocaste algo en `lib/data/`, agregá o actualizá su test en
  `test/data/` con `fake_cloud_firestore`.
- No generar el APK/AAB salvo que el usuario lo pida explícitamente.
