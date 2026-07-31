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

Si tocás `firestore.rules`, agregá su caso NEGATIVO en `test_rules/`
(qué no se debe poder hacer) además del positivo. `firebase deploy` corre
esa suite sola y no publica si falla (`predeploy` en `firebase.json`).

Razón: que las reglas compilen no dice nada sobre si hacen lo que dicen.
Así llegó a producción el agujero de `solicitudes/create` — la rama de
`update` prohibía con cuidado que un adoptante se auto-aprobara una
solicitud, pero `create` no miraba `estado`, así que bastaba con saltarse
el update y crear el documento ya aprobado. Con eso, cualquiera podía
dejar el animal de cualquier albergue imposible de borrar, para siempre.
La asimetría entre dos ramas de la misma regla no se ve leyendo el
archivo; se ve al probarla.

## Antes de dar por terminado un cambio

- `flutter analyze` sin errores nuevos (los "info" preexistentes de
  `withOpacity` deprecado no son parte de este trabajo, no hace falta
  arreglarlos salvo que se toque esa línea igual).
- Si tocaste algo en `lib/data/`, agregá o actualizá su test en
  `test/data/` con `fake_cloud_firestore`.
- No generar el APK/AAB salvo que el usuario lo pida explícitamente.
