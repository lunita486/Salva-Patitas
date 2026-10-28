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
  rechazan campos que no sean los suyos. Sin tope de personas (ver
  decisión 5); el contador `equipos/{albergueId}` se mantiene exacto con
  transacciones.
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
- **App:** "Equipo del albergue" en el Perfil de la responsable (debajo de
  "Editar perfil del albergue") (invitar,
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

## Fase 2: "modo Albergue" para el equipo (diseño, 2026-10-24, sin programar)

Idea de Eliza al probar la v1 en el emulador: la miembro no "mira" el
albergue desde su perfil, **trabaja** en él. Reemplaza las vistas de solo
lectura de la v1. **No se publica la v1 sola**: v1 + fase 2 salen juntas.

### Ya hecho (2026-10-24, aprobado)

- "Mi equipo de albergue" muestra solo la tarjeta "Sos parte del equipo
  desde el …" y "Salir del equipo". Sin "Chats del albergue" ni "Hogares de
  paso compartidos". Al salir, `salirDelEquipo` ya avisa a la responsable
  (push) y su lista de Miembros se actualiza sola.

### Cómo se ve (aprobado por Eliza)

1. Ana (adoptante + rescatista + miembro de Refugio La Perla) ve **tres
   opciones** en el selector de rol: Adoptante, Rescatista y **Albergue**.
   "Albergue" no es un rol de su cuenta (no se guarda en `usuarios.roles`,
   y la regla `rolesCompatiblesConEquipo` ya impide que una miembro tenga
   albergue propio): es el albergue de Perla, mientras la membresía esté
   activa.
2. Con "Albergue" entra al **mismo panel** que Perla (`AlbergueHomeScreen`)
   con los datos de Refugio La Perla: Jauría, chats, solicitudes y hogares
   de paso. Arriba, un rótulo "Ayudás en Refugio La Perla".
3. Lo que Ana no puede hacer **no aparece** (no botones grises con error).

| | Perla (responsable) | Ana (equipo) |
|---|---|---|
| Cargar animalitos (uno o en lote) y editarlos | ✅ | ✅ |
| Cambiar el estado de un animalito | ✅ | ✅ |
| Borrar animalitos | ✅ | Solo los que cargó ella, con los mismos frenos |
| Responder chats del albergue | ✅ | ✅ |
| Aprobar solicitudes de adopción | ✅ | ❌ |
| Rechazar solicitudes | ✅ | ❌ |
| Ver todos los hogares de paso, agregar, editar y **borrar** | ✅ | ✅ |
| Editar el perfil del albergue | ✅ | ❌ |
| Invitar o quitar personas | ✅ | ❌ |
| Eliminar el albergue | ✅ | ❌ |
| Ver consultas a negocios aliados o chats personales de Perla | ✅ | ❌ |

Cambio respecto de la v1: **desaparece la elección "Equipo: lo ve / no lo
ve"** de cada hogar de paso. El equipo ve todos. Se borran el campo
`visibleEquipo`/`revisionEquipo`, la Function `revisarHogarEquipo` y su
control. Nada de esto llegó a producción, así que no hay datos que migrar.

### Cómo funciona por dentro

**Regla de oro:** todo lo que Ana hace en modo Albergue queda **a nombre
del albergue**: `rescatistaId = uid de Perla`, `creadoPor = 'albergue'`.
Además se guarda quién lo hizo de verdad (`autorUid`, `autorNombre`) para
que Perla lo sepa. El adoptante ve siempre "Refugio La Perla", nunca a Ana.
Lo personal de Ana (sus animales de rescatista, sus chats de adoptante)
sigue con su propio uid y no se mezcla.

**Reglas de Firestore** (una función nueva `actuaPorAlbergue(id)`: es la
responsable, o es miembro activa de ese albergue):

- `rescates`: crear y editar con `creadoPor == 'albergue'` y
  `rescatistaId` de un albergue del que es miembro, con `autorUid == uid()`.
  Borrar: la responsable, o la miembro activa si `autorUid == uid()`.
- `solicitudes` (de animales del albergue): leer sí; aprobar no.
- `chats` del albergue (los de tipo adopción, hogar de paso, consulta, ya
  definidos en la v1): leer, mandar mensajes con `emisor: 'rescatista'` y
  `autorUid`, y poner en cero el "sin leer" compartido. Crear el chat de un
  aviso automático (por ejemplo "este animalito falleció" al cambiar el
  estado), igual que hoy lo hace la responsable.
- `hogaresDePaso`: leer, crear, editar y borrar los del albergue.
- `usuarios` de Perla: nada nuevo (el perfil del albergue ya se lee; no se
  edita).
- **Storage** (fotos de animales): subir y borrar fotos de un animal del
  albergue si es miembro activa (la regla cruza con `membresias`).
- Cada regla nueva lleva su prueba **negativa**: una miembro revocada, una
  de otro albergue, o una persona sin equipo no puede nada de lo anterior; y
  Ana no puede aprobar, borrar animales, ni tocar lo personal de Perla.

**Functions:**

- `onNuevoMensaje` y `onNuevaSolicitud`: sin cambios en a quién avisan
  (las miembros no reciben avisos del albergue, ver respuestas). Solo hay
  que cuidar que un mensaje escrito por una miembro (emisor 'rescatista')
  le siga avisando al adoptante y no a la responsable.
- `revisarHogarEquipo` se elimina.

**App:**

- `AlbergueHomeScreen` y las pantallas que abre (subir uno, subir en lote,
  editar, cambiar estado, Jauría completa, solicitudes, chats, hogares de
  paso) dejan de usar "el uid de la sesión" y reciben **el id del
  albergue**. Para Perla es su propio uid, así que para ella no cambia nada.
  Son unos 12 archivos y 4 repositorios (rescates, solicitudes, chats,
  hogares).
- Selector de rol con la tercera opción, y que recuerde la última
  (`ultimoRolActivo = 'equipo'`).
- Si a Ana la quitan del equipo mientras está en modo Albergue, la app la
  saca sola al modo Adoptante o Rescatista con un aviso.
- En el modo Albergue, la pestaña Perfil de Ana muestra: el albergue en el
  que ayuda, cambiar de rol, salir del equipo y cerrar sesión. No muestra
  "Editar perfil del albergue", "Equipo del albergue" ni "Eliminar cuenta".
- El diálogo de aceptar invitación cambia: "Vas a poder cargar y editar
  animalitos, responder chats y manejar los hogares de paso. Aprobar
  adopciones sigue siendo de la responsable."
- Se borran las vistas de solo lectura (`equipo_lectura_screens.dart`, sus
  rutas y pruebas).

**Pruebas antes de dar por terminado:** reglas (positivas y negativas),
Functions en el emulador, pruebas de pantallas, y una vuelta completa en el
emulador con Perla y Ana: Ana carga un animalito, Rita lo pide en adopción,
Ana responde el chat, Ana no ve "Aprobar", Perla aprueba.

**Tamaño:** grande, varias sesiones. Orden propuesto: 1) reglas + Storage +
sus pruebas, 2) Functions, 3) repositorios con id de albergue, 4) panel y
selector de rol, 5) vuelta completa en el emulador.

### Respuestas de Eliza (2026-10-24)

- Rechazar solicitudes: **no**. Ana chatea; decidir es de Perla.
- Rotulito con el nombre de quien escribió, solo para el lado del
  albergue: **sí**.
- "Cargado por Ana" en la ficha, solo para el lado del albergue: **sí**.
- Editar información del albergue: **no**, nada.
- Orden por partes (reglas, avisos, datos, pantallas, prueba): **sí**.

- Borrar (2026-10-25): Ana borra **solo los animalitos que cargó ella**
  (`autorUid == Ana`), con los mismos frenos que la responsable (no si
  tiene solicitudes pendientes o una adopción aprobada). Los demás, solo
  Perla. Regla: `delete` para miembro activa si `autorUid == uid()`; los
  frenos siguen en la app (`bloqueoParaEliminar`), igual que hoy.
- Avisos (2026-10-25): **las miembros no reciben avisos del albergue.**
  Ana ve los mensajes y solicitudes del albergue solo cuando entra en modo
  Albergue (chats sin leer), igual que hoy ve los de rescatista solo en
  modo Rescatista. `onNuevoMensaje` y `onNuevaSolicitud` siguen avisando
  solo a la responsable; no se tocan.

**Diseño cerrado.**

### Avance

- **Parte 1, reglas (2026-10-25, en local, sin desplegar):**
  `firestore.rules` y `storage.rules` con las escrituras de la miembro
  (funciones nuevas `miembroDeAlbergueVigente`, `autorPropio`,
  `autorNombreValido`, `miembroEscribeEn`, `puedeTocarFotos`). Además,
  `solicitudes.create` ahora exige que el `creadoPor` de la solicitud sea
  el del animal (si viene), para que una solicitud sobre un animal
  personal de la responsable no pueda quedar a la vista del equipo.
  Pruebas: `test_rules/equipo_fase2.test.mjs` (nuevo, Firestore + Storage)
  y `equipo.test.mjs` ajustado a hogares sin `visibleEquipo`. El corredor
  levanta Firestore y Storage con el proyecto `demo-patitas-reglas`.
  Resultado: 216/216.
  Notas para las partes siguientes: la app tiene que mandar `autorUid`
  (y `autorNombre`) en todo lo que una miembro crea o escribe, y no
  pisarlos al editar; las listas de la miembro tienen que pedir los filtros
  que las reglas pueden probar (solicitudes: `rescatistaId` + `creadoPor
  == 'albergue'`; chats: además `tipoSolicitud in [...]`; hogares:
  `albergueId`). `visibleEquipo` ya no decide nada en las reglas; la
  Function `revisarHogarEquipo` y su control se quitan en la parte 2.
- **Parte 2, Functions (2026-10-25, en local, sin desplegar):** se quitó
  `revisarHogarEquipo` (equipo.js, index.js) y la barrera de "hogares
  dudosos" al invitar y aceptar, con su lógica (`hogarDudoso`,
  `revisionValida`, `hogaresPendientesDeRevision`, `errorHogaresPendientes`,
  `comprobarPuedeRevisarHogar`, `leerHogaresPendientes`). Motivo: la
  pantalla de hogares nació el 2026-07-30 y siempre estuvo solo en el panel
  del albergue, así que no hay hogares personales mezclados. Pruebas de
  Functions: 342/342 con emulador. `onNuevoMensaje` y `onNuevaSolicitud` no
  cambian: verificado de punta a punta en el emulador (Functions reales)
  que un mensaje de una miembro avisa al adoptante, y uno del adoptante
  avisa solo a la responsable. `_diagnostico_equipo.js` queda como está
  (sus datos de hogares pasan a ser solo informativos).
  Pendiente para la parte 3 (app): quitar el control "Equipo: lo ve / no lo
  ve" de `hogares_de_paso_screen.dart`, `EquipoRepository.revisarHogar`, el
  aviso de "revisá tus hogares" de `equipo_albergue_screen.dart`, las vistas
  de solo lectura y el índice `hogaresDePaso (albergueId, visibleEquipo)` de
  `firestore.indexes.json` (lo usa todavía `visiblesParaEquipo`).
- **Parte 3, datos (2026-10-25, en local, sin desplegar):**
  `lib/data/contexto_albergue.dart` (nuevo): `ContextoAlbergue.responsable`
  / `.equipo`, con `camposAutor` y `autorDe()` para el rotulito.
  `RescatesRepository.crear` y `publicarConFotos`, y `ChatsRepository`
  (`registrarMensaje`, `agregarMensaje`, `avisarSobreAnimal`) aceptan
  `autor`; va en el animal y en el mensaje, nunca en el chat. Editar o
  cambiar el estado no toca `autorUid`. Solicitudes y hogares ya trabajaban
  con el id del albergue (`paraOwner(uid:, role:)`, `deAlbergue`), y la
  lista de chats del equipo es `ChatsRepository.delEquipo`. Quitado: el
  control "Equipo: lo ve / no lo ve" de Hogares de paso,
  `EquipoRepository.revisarHogar` y `esPorHogares`, el atajo "Revisar mis
  hogares de paso" al invitar, las vistas de solo lectura
  (`equipo_lectura_screens.dart`, sus 3 rutas y pruebas),
  `visiblesParaEquipo` y su índice. Pruebas de la app: 1023 + 3 omitidas;
  `flutter analyze` sin errores nuevos.
  Límite conocido: una miembro no puede mandar un aviso automático en un
  chat viejo sin `tipoSolicitud` ni sobre una solicitud vieja sin animal
  (las reglas lo rechazan y `avisarSobreAnimal` devuelve false). Esos
  quedan para la responsable, como ya se decidió con los chats viejos.
- **Parte 4, pantallas (2026-10-25, en local, sin desplegar):**
  `InicioPersonalOEquipo` (nuevo, desde AuthWrapper para cuentas
  personales): con `ultimoRolActivo == 'equipo'` y membresía activa muestra
  `AlbergueHomeScreen` del albergue de la responsable; si la membresía deja
  de estar activa vuelve sola al inicio personal con un aviso y borra la
  elección. `SesionEquipo` (en contexto_albergue.dart) guarda el contexto
  de la sesión; las pantallas del albergue lo leen con `contextoAlbergue()`
  / `uidDueno(esAlbergue:)` solo en sus caminos de albergue. Selector de
  rol de HomeScreen con "Albergue" (y se achica para entrar con tres).
  Panel: sin avisos automáticos en modo equipo (los manda la responsable),
  sin foto de la miembro, Perfil propio (a qué albergue ayuda, volver a la
  cuenta, Mi equipo, apariencia, cerrar sesión). Barra: chats del equipo
  (`delEquipo`), sin consultas a negocios ni pestaña Negocios. Chats:
  mensajes con autor, rotulito con el nombre para el lado del albergue, y
  el nombre del albergue (no el de la miembro) en un chat nuevo.
  Solicitudes y vista previa: sin Aprobar/Rechazar en modo equipo, con
  aviso. Jauría y editar: dueño = albergue, tacho solo en lo que cargó esa
  persona, "Cargado por" para el lado del albergue. Subir uno y en lote:
  a nombre del albergue con `autor`. Cambiar estado: sin "Fallecido" en
  modo equipo (cierra solicitudes rechazándolas, que es de la
  responsable). Hogares de paso: la red del albergue. Diálogo de aceptar
  invitación y aviso de la pantalla "Equipo del albergue" con los permisos
  nuevos. Pruebas: Flutter 1030 + 3 omitidas (`modo_equipo_test.dart`
  nuevo); `flutter analyze` sin nada nuevo. Probado en el emulador con
  Perla, Ana y Rita: Ana entra como Albergue, ve el panel de Refugio La
  Perla, responde el chat de Rita (el mensaje queda con `autorUid` y el
  aviso va a Rita), no ve Aprobar/Rechazar ni "Fallecido" ni tacho en lo de
  Perla, vuelve a su cuenta, y al revocarla sale sola con el aviso. Perla
  ve el rotulito "Ana" en el chat.
  No probado en el emulador (solo con pruebas y reglas): subir un animal
  con foto como miembro, borrar uno propio, editar un hogar de paso.
- Siguiente: commit (con OK de Eliza), diagnóstico de producción (con su
  autorización) y publicar en orden: índices, reglas (Firestore y
  Storage), Functions y app.

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
5. **Sin tope de personas por equipo** (Eliza, 2026-10-24; reemplaza el
   máximo de 10). Un albergue grande puede sumar a toda la gente que lo
   ayuda. El contador `equipos/{albergueId}.miembrosActivos` se mantiene
   exacto en transacciones: lo usan el bloqueo al eliminar la cuenta y la
   regla de roles incompatibles. Contrapartida asumida: cada miembro ve
   chats con adoptantes y los hogares compartidos; la protección es que
   solo la responsable invita y puede quitar a cualquiera.
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
