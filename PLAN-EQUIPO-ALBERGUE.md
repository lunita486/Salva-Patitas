# Plan: equipo del albergue (varias personas en un mismo albergue)

Estado: **diseño aprobado por Eliza el 2026-10-16. Nada implementado todavía.**
Se hace en 2 partes, después de terminar el proyecto de n8n.

## El problema

Hoy un albergue **es** una sola cuenta de Google. Animalitos (`rescates`),
solicitudes, chats y la red de hogares de paso se guardan con el uid de esa
cuenta en `rescatistaId` (o `albergueId`), y `firestore.rules` permite editar
solo si `rescatistaId == uid()`. Para que otra persona ayude tendría que
compartir el mismo correo y contraseña.

## Decisiones (Eliza, 2026-10-16)

1. **Dos niveles: Dueña y Equipo.** Sin "voluntario" por ahora; se puede
   agregar después.
2. **Una cuenta del equipo es solo de albergue.** No mezcla adoptante ni
   rescatista. Si la persona ya usaba la app como adoptante, al aceptar la
   invitación su cuenta pasa a ser solo del equipo: mostrar un aviso claro
   antes de aceptar ("Tu cuenta pasará a ser del equipo de X"). Lo ideal es
   que use otro correo si también quiere adoptar. Cambiar entre "Mi albergue"
   y "Yo" queda para más adelante.
3. **Una persona, un solo albergue.** Si se va, la dueña la quita.
4. **Al quitar a alguien**, todo lo que hizo (animalitos, chats, cambios) se
   queda en el albergue y la persona pierde el acceso.

## Permisos

| | Dueña | Equipo |
|---|---|---|
| Subir, editar y cambiar estado de animalitos | ✅ | ✅ |
| Responder chats | ✅ | ✅ |
| Aprobar o rechazar solicitudes | ✅ | ✅ |
| Red de hogares de paso | ✅ | ✅ |
| Editar el perfil del albergue | ✅ | ❌ |
| Invitar o quitar personas del equipo | ✅ | ❌ |
| Eliminar el albergue | ✅ | ❌ |

## Cómo se guarda (idea)

- **El albergue se sigue identificando con el uid de la dueña.** Así no hay
  que migrar ni copiar nada: todo lo que ya existe con `rescatistaId = dueña`
  sigue funcionando igual.
- Equipo: `usuarios/{dueñaUid}/equipo/{miembroUid}` con nombre, email y fecha.
  Una subcolección (y no un array en el doc de la dueña) para que las reglas
  puedan preguntar `exists(...)` sin leer todo el perfil.
- En el perfil del miembro: `usuarios/{miembroUid}.trabajaEn = dueñaUid`. La
  app lo usa para abrir el Panel del albergue con el uid de la dueña en todas
  las consultas.
- Invitaciones: `invitaciones/{id}` con `albergueId`, `email` (en minúsculas)
  y estado. La persona invitada la ve al entrar con ese correo.
- Para saber quién hizo qué: `actualizadoPor` en los animalitos y el autor
  (uid + nombre) en cada mensaje de chat. El adoptante ve "Ana · La Perla".

## Parte 1: la base (no cambia nada visible)

1. Helper en `firestore.rules`: `esDelEquipo(dueña)` = `uid() == dueña ||
   exists(/usuarios/dueña/equipo/uid())`.
2. Usarlo en lugar de `rescatistaId == uid()` **solo para lo del albergue**
   (`creadoPor == 'albergue'`): rescates, solicitudes, chats, hogaresDePaso.
   Lo del rescatista individual y lo del aliado no cambia.
3. Reglas de `equipo` e `invitaciones`: solo la dueña crea o borra; el
   miembro solo puede aceptar una invitación dirigida a su propio email.
   Nadie puede agregarse solo a un equipo.
4. **Tests negativos en `test_rules/`** (obligatorio, ver CLAUDE.md):
   - alguien del equipo de A no puede tocar animalitos, solicitudes ni chats
     de B;
   - un miembro no puede invitar, quitar ni editar el perfil del albergue;
   - nadie puede escribirse a sí mismo en un `equipo`;
   - un miembro quitado pierde el acceso al instante.
5. Revisar las Cloud Functions que usan el uid del albergue (contadores,
   avisos, `eliminar_cuenta.js`) y decidir qué pasa con el equipo si la
   dueña elimina su cuenta (propuesta: el equipo pierde el acceso).
6. **No publicar las reglas (`firebase deploy`) sin preguntarle a Eliza.**

## Parte 2: las pantallas

1. Perfil del albergue (solo la dueña): sección **"Equipo"** con la lista,
   "Invitar" (por correo) y "Quitar".
2. Al entrar con un correo invitado: hoja "X te invitó a su equipo" con el
   aviso de la decisión 2, y Aceptar / Rechazar.
3. Panel del albergue para el miembro, sin "Editar perfil", "Equipo" ni
   "Eliminar albergue".
4. Chats: "Ana · La Perla" en los mensajes del equipo.
5. Notificaciones de solicitudes y mensajes a todos los del equipo.
6. Diseño 3D como el resto de la app (SpCard, SpFilaCuenta, SpButton...).

## Tamaño

Parte 1: mediana tirando a grande (las reglas son unas 460 líneas, y cada
permiso nuevo lleva su test negativo). Parte 2: mediana.
