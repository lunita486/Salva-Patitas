# Plan: equipo del albergue (varias personas en un mismo albergue)

Estado (2026-10-23): **implementado en local, con pruebas, sin desplegar ni
commitear.** Versión 1: la responsable gestiona su equipo y las miembros
**consultan** (solo lectura) los chats del albergue y los hogares de paso que
ella comparta. Ver "Qué hay en la v1" y "Cómo publicar".

Diseño técnico completo: https://claude.ai/artifact/9r5eepp5uo7ZKqcGUEM456
(auditoría de fase 1: https://claude.ai/artifact/DJQ6DjtH4gUD5gA7tuEKqC).

## Qué hay en la v1

- **Functions** (functions/equipo.js, exportadas en index.js, europe-west1):
  `invitarMiembro`, `aceptarInvitacion`, `rechazarInvitacion`,
  `cancelarInvitacion`, `revocarMiembro`, `salirDelEquipo`,
  `revisarHogarEquipo`. Todas exigen sesión con correo verificado y
  rechazan campos que no sean los suyos. El cupo de 10 se cuida en
  transacciones sobre `equipos/{albergueId}`.
- **Avisos push** (best effort, nunca hacen fallar la operación): a la
  persona invitada si ya tiene cuenta con ese correo, a la responsable
  cuando alguien acepta o sale, a la miembro cuando la quitan.
- **Eliminar cuenta:** la responsable no puede mientras tenga miembros o
  invitaciones vigentes. Una miembro sí: se borra su membresía (nombre y
  correo), baja el contador y se borran las invitaciones a su correo.
- **Reglas:** cada persona lee su membresía; la responsable, las de su
  albergue y sus invitaciones; cada persona, las invitaciones a su correo
  verificado; el contador, la responsable y su equipo activo. Nadie escribe
  esas colecciones desde la app. Las miembros leen chats del albergue con
  tipo del equipo y hogares con `visibleEquipo == true`.
- **App:** "Equipo del albergue" en el panel de la responsable (invitar,
  quitar, cancelar, cupo), un control por hogar en "Hogares de paso"
  ("Equipo: lo ve / no lo ve / sin decidir"), y "Mi equipo de albergue" en
  los perfiles de adoptante y rescatista (solo aparece con una invitación o
  un equipo): aceptar, rechazar, salir, y las vistas de solo lectura.

## Fuera de la v1 (siguiente fase)

Las **escrituras de las miembros** de la tabla de permisos de abajo
(publicar y editar animales del albergue, responder sus chats, aprobar o
rechazar solicitudes, crear y editar hogares de paso) **no están
implementadas**: en la v1 una miembro solo consulta. Hacen falta reglas de
escritura (rescates, solicitudes, chats/mensajes, hogaresDePaso y Storage),
mensajes con `autorUid`/`autorNombre`, y que las pantallas del albergue
operen "en nombre del albergue" en lugar de con el uid de la sesión.
También quedan para esa fase los avisos push de chats y solicitudes a las
miembros.

**Chats viejos sin `tipoSolicitud`:** quedan fuera del equipo, sin
modificarlos (incluye los que crea `asegurarChatLegado`, el camino de
animales sin `rescateId`). La responsable los sigue viendo como siempre.

## Terminología

- **Negocios aliados:** los negocios que colaboran con Salva Patitas
  (veterinarias, peluquerías, tiendas). Rol técnico en Firestore: `aliado`.
- **Responsable del albergue:** la persona propietaria que administra el
  albergue. Su uid es el `rescatistaId` de los recursos del albergue.
- **Miembros del equipo:** personas invitadas por la responsable para
  colaborar en la gestión del albergue.
- **Rescatistas y sus cuentas personales:** sus datos quedan siempre
  separados de los del albergue.

## Requisito innegociable

Se distinguen de forma absoluta: **rescatista independiente (cuenta
personal), responsable del albergue, miembro del equipo, adoptante y
negocio aliado.**

- La membresía **no cambia la propiedad** de ningún recurso ni da acceso a
  recursos personales (de la responsable, de otros miembros del equipo ni
  del propio miembro en otro rol).
- Un animal publicado por un miembro del equipo queda con
  `rescatistaId = responsable` y
  `creadoPor = 'albergue'`. El adoptante ve el albergue, no a la persona.
- Los mensajes distinguen el lado (`emisor: 'rescatista'`, el albergue) de la
  persona real que escribió (`autorUid`, `autorNombre`). La propiedad del
  chat no cambia.
- Las notificaciones respetan el mismo aislamiento.

## Decisiones (2026-10-21; reemplazan las del 2026-10-16)

1. **Fuente de verdad:** `membresias/{uidMiembro}` (un documento por
   persona; solo lo escriben Cloud Functions). Ya no la subcolección
   `usuarios/{responsable}/equipo`.
2. **Historial personal permitido.** Una persona que ya es adoptante o
   rescatista independiente puede aceptar una invitación. No se migra ni
   reasigna nada suyo. La membresía **no es un rol** en `usuarios.roles`:
   es un contexto aparte en la app ("Mi albergue"). Reemplaza la decisión
   anterior de "cuenta solo de albergue".
   - No se permite: miembro del equipo + responsable de otro albergue,
     miembro del equipo + negocio aliado, miembro de dos albergues,
     responsable con equipo + negocio aliado. Se impone en el servidor.
     (En Firestore, "negocio aliado" es el rol técnico `aliado`; el nombre
     del campo no cambia.)
3. **La cuenta de la responsable no se puede eliminar** mientras tenga miembros activos
   o invitaciones pendientes. Sin transferencia de propiedad en la v1.
4. **Invitaciones vencen a los 7 días.**
5. **Máximo 10 miembros activos** por albergue, con un contador
   `equipos/{albergueId}` leído y escrito en la misma transacción (seguro
   ante aceptaciones o invitaciones simultáneas).
6. **Correo verificado obligatorio** para aceptar, también en sandbox.
7. **Borrar animales: solo la responsable** en la v1. Los miembros del
   equipo crean y editan. Caminos revisados: la regla `rescates.delete` no
   cambia; ninguna Function borra animales por id; `eliminarCuenta` de un
   miembro solo toca lo que tiene su propio uid. Borrar *fotos* en Storage
   sí se permite a los miembros
   porque editar lo necesita (quitar la única foto, mover la 2 a la 1); el
   animal no se borra.
8. **Las consultas a negocios aliados no se comparten** con el equipo.
   Tampoco los chats personales de la responsable (como rescatista o
   adoptante) ni los de los miembros del equipo.
   - Qué son (según el código): chats con `tipoSolicitud == 'consulta_aliado'`
     que alguien abre desde el perfil de un negocio aliado ("Contactar").
     `adoptanteId` es quien pregunta y `rescatistaId` es el negocio aliado.
     Hoy solo los leen esos dos participantes.
   - Ojo: en estos chats `creadoPor` dice con qué perfil preguntó quien
     pregunta (ausente si preguntó como adoptante), NO a quién pertenece el
     chat. Significa algo distinto que en los chats de un animal.
9. **Filtrado de chats del equipo.**
   - **Requisito aprobado (2026-10-22):** las consultas a negocios aliados
     (`tipoSolicitud == 'consulta_aliado'`) nunca se comparten con los
     miembros del equipo por el hecho de pertenecer a él. No se bloquean
     invitaciones por el historial de roles de la responsable.
   - **Implementación propuesta, pendiente:** la regla de miembro exige
     `creadoPor == 'albergue'`, `tipoSolicitud` en `adopcion`,
     `hogar_de_paso` o `consulta`, y membresía activa en el albergue de
     `rescatistaId`. La app consulta con esos mismos filtros (`in`).
     Verificado el 2026-10-22 en un prototipo de reglas en el emulador
     (22 pruebas, incluida la responsable con el rol técnico `aliado` antes
     y después de crear el equipo). Todavía no está en `firestore.rules`.
     En producción la consulta probablemente necesite un índice compuesto.
   - **Chats viejos sin `tipoSolicitud`:** el equipo no los ve (la regla
     los rechaza) y la responsable sí. No se les da acceso automático:
     cualquier cambio de esos datos necesita una propuesta y una
     aprobación aparte.
   - La exclusividad "responsable con equipo + negocio aliado" de la
     decisión 2 queda como segunda barrera. Esta implementación
     reemplazaría a la opción (b) del 2026-10-21, que no miraba
     `tipoSolicitud`.
10. **"Sin leer" compartido** por el equipo en la v1 (`noLeidosRescatista`
    de los chats del albergue). Separado de los contadores personales.

## Permisos

| | Responsable | Miembro del equipo |
|---|---|---|
| Subir, editar y cambiar estado de animalitos del albergue | ✅ | ✅ |
| Borrar animalitos | ✅ | ❌ |
| Responder chats del albergue | ✅ | ✅ |
| Aprobar o rechazar solicitudes del albergue | ✅ | ✅ |
| Red de hogares de paso (leer, crear, editar) | ✅ | ✅ |
| Borrar hogares de paso | ✅ | ❌ |
| Editar el perfil del albergue | ✅ | ❌ |
| Invitar o quitar personas del equipo | ✅ | ❌ |
| Eliminar el albergue | ✅ | ❌ |
| Ver consultas a negocios aliados o chats personales de otros | ❌ | ❌ |

## Diagnóstico de solo lectura

`functions/_diagnostico_equipo.js`. No escribe nunca (bloquea las
escrituras del SDK) y sin bandera se niega a correr.

- `--emulador`: corrido el 2026-10-21 con datos de prueba (escenario limpio
  y escenario con conflictos). Detectó todos los casos sembrados.
- `--produccion`: **no corrido.** Necesita autorización explícita de Eliza
  (paso 2 de "Cómo publicar").

Qué revisa: A1 cuentas que son responsable y negocio aliado a la vez,
A2 consultas a negocios aliados recibidas por una responsable, A3 colecciones nuevas con datos, A4 campo `trabajaEn` ya usado
(bloqueantes); B1 a B3 datos viejos que el equipo no vería (a revisar);
C1 a C3 informativos (chats sin `tipoSolicitud`, entre otros).

## Pruebas (cómo correrlas)

```
export PATH=/opt/homebrew/opt/node@22/bin:$PATH   # el node de Homebrew está roto
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"

npm --prefix test_rules test                                   # reglas
firebase emulators:exec --only firestore --project demo-equipo-test \
  "cd functions && npm test"                                   # Functions
flutter test && flutter analyze                                # app
```

## Cómo publicar (nada de esto está hecho)

Orden pensado para que nunca haya una app que llame a algo que todavía no
existe. **Cada paso necesita el OK de Eliza.**

1. Commit en la rama de trabajo (`fix/copias-y-duplicacion`).
2. Opcional, recomendado: correr el diagnóstico de solo lectura contra
   producción (`node functions/_diagnostico_equipo.js --produccion`), con
   autorización explícita. Revisa A1 a A4 (bloqueantes) antes de abrir el
   equipo a albergues reales.
3. Índices: `firebase deploy --only firestore:indexes` y esperar a que
   terminen de construirse en la consola (chats rescatistaId+creadoPor+
   tipoSolicitud; hogaresDePaso albergueId+visibleEquipo; membresias e
   invitaciones albergueId+estado; invitaciones emailDestino+estado).
4. Reglas: `firebase deploy --only firestore:rules` (el predeploy corre
   `test_rules` y no publica si falla).
5. Functions: `firebase deploy --only functions` (despliega las 7 nuevas y
   la versión nueva de `eliminarCuenta` y de `avisarVencimientosHogarDePaso`).
6. App: nueva versión con las pantallas del equipo (Google Play). Las
   versiones viejas de la app no se rompen: no conocen las colecciones
   nuevas.
7. Probar con dos cuentas reales: invitar, aceptar, ver chats y hogares
   compartidos, quitar, salir.
