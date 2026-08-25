# Auditoría — Salva Patitas, 25 de agosto de 2026

Auditoría de seguridad, permisos, estado, concurrencia y chat.
Rama auditada: `fix/copias-y-duplicacion`, commit `36bd11f`.

**No se modificó código.** Lo único que se escribió fue un archivo temporal
de sondeo en `test_rules/`, ya borrado (`git status` limpio). Este informe
es el único artefacto.

## Nota sobre el encuadre

La plantilla de esta auditoría asume un stack que acá no existe. Lo digo
antes que nada para que ninguna sección se lea como un "todo bien" cuando
en realidad es un "no aplica":

| Lo que pedía la plantilla | Lo que hay realmente |
|---|---|
| React, hooks, stores, useEffect | Flutter/Dart. `StatefulWidget` + `StreamBuilder`. Sin Redux/Query/SWR |
| Websockets, reconexión de socket | Firestore `snapshots()`. La reconexión la maneja el SDK |
| API REST, códigos HTTP, endpoints | 1 solo endpoint HTTP (`landingAnimales`) y 1 callable (`eliminarCuenta`). El resto es acceso directo a Firestore desde el cliente |
| SQL, foreign keys, constraints, cascades, índices | Firestore. No hay FK ni constraints. La integridad referencial **no existe a nivel motor**: la sostienen las reglas y los triggers |
| Cookies, localStorage, CSRF, refresh tokens | Firebase Auth con tokens gestionados por el SDK. Sin cookies. CSRF no aplica |
| SQL injection, XSS | No aplica: no hay SQL ni render de HTML. La landing sí renderiza datos públicos (ver PRIV-01) |

**Consecuencia importante:** en esta arquitectura, `firestore.rules` **es**
el backend de autorización. No hay una capa de servidor que revalide. Por
eso la auditoría se concentró ahí y se verificó **ejecutando contra el
emulador**, no leyendo.

---

## RESUMEN EJECUTIVO

**Estado general:** la app está considerablemente más endurecida de lo que
esperaba. Las reglas tienen historia de agujeros ya cerrados y con test de
regresión propio (67 tests contra emulador). Las áreas de `solicitudes`,
`servicios`, `hogaresDePaso`, `storage` y la function de borrado de cuenta
las probé buscando romperlas y aguantaron.

**Pero hay dos agujeros P0 abiertos, y uno de los dos es explotable hoy
contra tus usuarios reales.**

| Prioridad | Cantidad |
|---|---|
| P0 crítico | 2 |
| P1 alto | 2 |
| P2 medio | 5 |
| P3 bajo | 4 |
| **Total** | **13** |

**Zonas de mayor riesgo, en orden:**

1. **`chats.create`** (P0). El anclaje que valida contra qué animal se abre
   un chat se saltea por completo si el campo `creadoPor` simplemente no
   viene. Cualquier cuenta puede abrirle conversación a cualquier otra y
   dispararle una notificación push con título y texto que ella controla.
2. **`usuarios` lectura** (P0). Cualquier cuenta logueada puede listar la
   colección entera y bajarse el nombre, email, teléfono, dirección,
   coordenadas y token de notificaciones de **todos** los usuarios.
3. **Los dos se combinan.** El 2 entrega la lista de blancos que el 1
   necesita. Juntos son spam/phishing push masivo a toda tu base, saliendo
   de tu propio proyecto de Firebase.
4. **Ciclo de sesión.** El token de notificaciones nunca se borra al cerrar
   sesión.
5. **Chat sin conexión.** Un mensaje mandado sin señal puede terminar
   duplicado.

---

## MATRIZ DE ROLES

Los 4 roles viven en `usuarios/{uid}.roles` (un array, una cuenta puede
tener varios a la vez). `CreatorRole` en Dart solo modela 2 de los 4
(`rescatista`, `albergue`), porque son los únicos que publican animales.

| Recurso | adoptante | rescatista | albergue | aliado | Sin sesión |
|---|---|---|---|---|---|
| `rescates` leer | ✅ | ✅ | ✅ | ✅ | ✅ **público** |
| `rescates` crear | ❌ | ✅ propios | ✅ propios | ❌ | ❌ |
| `rescates` editar/borrar | ❌ | ✅ propios | ✅ propios | ❌ | ❌ |
| `solicitudes` crear | ✅ | ✅ | ✅ | ✅ | ❌ |
| `solicitudes` leer | ✅ propias | ✅ recibidas | ✅ recibidas | ✅ propias | ❌ |
| `solicitudes` aprobar | ❌ | ✅ propias | ✅ propias | ❌ | ❌ |
| `servicios` leer | ✅ | ✅ | ✅ | ✅ | ✅ **público** |
| `servicios` crear | ❌ | ❌ | ❌ | ✅ propios | ❌ |
| `hogaresDePaso` | ❌ | ❌ | ✅ propio | ❌ | ❌ |
| `favoritos` | ✅ propios | ✅ propios | ✅ propios | ✅ propios | ❌ |
| `preferencias` | ✅ propias | ✅ propias | ✅ propias | ✅ propias | ❌ |
| `usuarios` leer | ⚠️ **TODOS** | ⚠️ **TODOS** | ⚠️ **TODOS** | ⚠️ **TODOS** | ❌ |
| `usuarios` escribir | ✅ propio | ✅ propio | ✅ propio | ✅ propio | ❌ |
| `chats` | ⚠️ ver CHAT-01 | ⚠️ | ⚠️ | ⚠️ | ❌ |

**Quién puede chatear con quién (intención del diseño):**

| | → adoptante | → rescatista | → albergue | → aliado |
|---|---|---|---|---|
| **adoptante** | no | sobre un animal suyo | sobre un animal suyo | consulta al negocio |
| **rescatista** | sobre un animal propio | no | no | consulta al negocio |
| **albergue** | sobre un animal propio | no | no | consulta al negocio |
| **aliado** | responde consultas | responde consultas | responde consultas | no |

**En la práctica, hoy: cualquiera con cualquiera.** Ver CHAT-01.

**Nota sobre `hasRole()` (ROLE-01):** los roles son **auto-asignables**.
Verificado: un adoptante se pone `roles: ['adoptante','albergue','aliado',
'rescatista']` y publica como albergue en el acto. Asumo que es
intencional (onboarding self-service, no hay verificación de albergues).
Lo señalo porque `servicios.create` y `hogaresDePaso.create` usan
`hasRole()` **como si fuera una barrera de confianza**, y no lo es.

---

## BUGS ENCONTRADOS

### ❌ P0-1 · CHAT-01 · Cualquiera puede abrirle chat y mandarle push a cualquiera

* **ID:** CHAT-01
* **Archivo:** `firestore.rules:210-229` (`match /chats/{chatId}`, `allow create`)
* **Estado:** ❌ **BUG CONFIRMADO** contra emulador
* **Descripción:** la regla de creación valida `creadoPor` contra el
  documento real de `rescates` para impedir que alguien abra un chat sobre
  un animal que no le corresponde. Pero la condición está escrita así:

  ```
  (!('creadoPor' in request.resource.data) || (...todo el anclaje...))
  ```

  Si el campo **no viene**, el primer término es verdadero y **todo el
  anclaje se saltea**. Lo único que queda en pie es "sos una de las dos
  partes", y esa parte la elige el atacante.

* **Pasos para reproducir** (verificado en emulador):
  1. Cuenta cualquiera, autenticada. Consigue el uid de la víctima (trivial
     con AUTH-01, abajo).
  2. `setDoc(chats/loQueSea, { rescatistaId: <yo>, adoptanteId: <víctima>,
     animalNombre: 'URGENTE', ultimoMensaje: '...' })` sin `creadoPor`.
     → **aceptado**.
  3. `addDoc(chats/loQueSea/mensajes, { texto: '...', emisor: 'rescatista' })`.
     → **aceptado**.
  4. `onNuevoMensaje` calcula `recipientId = chat.adoptanteId` (la víctima)
     y llama `notificar(víctima, 'Mensaje sobre ' + chat.animalNombre,
     data.texto)`.
* **Resultado esperado:** rechazo. Solo debería poder abrirse un chat
  anclado a un animal real de esa persona, o una consulta a un aliado real.
* **Resultado actual:** aceptado. A la víctima le aparece una conversación
  nueva y le llega una **notificación push real**, con **título y cuerpo
  controlados por el atacante** (título vía `animalNombre`, cuerpo vía
  `texto`, hasta 2000 caracteres), enviada por tu proyecto de Firebase.
* **Causa probable:** el `!('creadoPor' in ...)` se agregó para tolerar
  chats legados que no tienen el campo. Tolerar el dato viejo abrió la
  puerta a omitirlo a propósito.
* **Impacto:** phishing dirigido con la credibilidad de tu app. Contacto no
  solicitado a cualquier usuario. Con AUTH-01, masivo. También ensucia la
  bandeja de chats de la víctima con conversaciones que ella no puede
  borrar (no hay borrado de chats).
* **Propuesta:** exigir que `creadoPor` **esté siempre presente** en los
  chats nuevos y que el anclaje se evalúe siempre. Los chats legados ya
  existen, no se crean más, así que la tolerancia solo hace falta en
  `update`/`read`, nunca en `create`. La rama de fallback legado
  (`rescateId == ''` y no es `consulta_aliado`) hay que cerrarla también:
  es el mismo agujero con un paso extra.
* **Test de regresión:** en `test_rules/reglas.test.mjs`, caso negativo:
  "crear un chat SIN creadoPor contra un uid con el que no hay relación se
  rechaza", más el positivo de que un chat legítimo sigue funcionando.

---

### ❌ P0-2 · AUTH-01 · Cualquier cuenta logueada lista todos los usuarios

* **ID:** AUTH-01
* **Archivo:** `firestore.rules:43` (`match /usuarios/{userId}`, `allow read: if signedIn();`)
* **Estado:** ❌ **BUG CONFIRMADO** contra emulador
* **Descripción:** en Firestore, `allow read` cubre `get` **y** `list`. Con
  la condición en `signedIn()`, cualquier cuenta puede pedir la colección
  entera sin filtro.
* **Pasos para reproducir:** autenticarse como cualquier usuario y
  `getDocs(collection(db, 'usuarios'))`. Verificado: devolvió los 4
  perfiles sembrados, completos.
* **Resultado esperado:** poder leer el perfil **puntual** de una
  contraparte (eso sí hace falta: las pantallas públicas de albergue y
  aliado lo necesitan, y el chat necesita la foto del otro). Nunca la
  colección entera.
* **Resultado actual:** volcado completo. Los campos que salieron en el
  sondeo: `nombre`, `email`, `foto`, `roles`, `ciudad`, `latitud`,
  `longitud`, `albergueTelefono`, `albergueDireccion`. En producción
  también sale `fcmToken` y `ultimaVezActiva`.
* **Causa probable:** la regla se escribió pensando en `get` (leer el perfil
  de la contraparte) sin considerar que `read` también habilita `list`.
* **Impacto:** exposición de datos personales de toda la base a cualquiera
  que se registre. Email y teléfono son datos de contacto reales.
  `ultimaVezActiva` revela patrones de actividad. Y entrega la lista de
  uids que CHAT-01 necesita para elegir blancos.
* **Propuesta:** separar `allow get` de `allow list`. `allow get: if
  signedIn();` y `allow list: if false;`. Hay que revisar antes si alguna
  pantalla hace una consulta de colección sobre `usuarios` (la fusión por
  email de la red de hogares de paso es candidata; si la hace, mover esa
  búsqueda a una Cloud Function).
* **Test de regresión:** "un usuario cualquiera NO puede listar `usuarios`"
  y "sí puede leer un perfil puntual".

---

### ❌ P1-1 · AUTH-02 · El token de notificaciones no se borra al cerrar sesión

* **ID:** AUTH-02
* **Archivos:** `lib/data/auth_helper.dart:161` (`cerrarSesion`),
  `lib/services/notificaciones_service.dart:105`
* **Estado:** ❌ **CONFIRMADO por lectura de código.** ⚠️ No verificado en
  runtime (haría falta dos cuentas en un teléfono real).
* **Descripción:** `guardarToken()` escribe `usuarios/{uid}.fcmToken` al
  montar cada pantalla principal. **No existe ninguna ruta de código que lo
  borre.** Verificado: `grep -rn "fcmToken" lib/` da 3 resultados y ninguno
  es un borrado. `cerrarSesion()` cierra Google y Firebase Auth, nada más.
* **Pasos para reproducir:**
  1. Cuenta A entra en el teléfono. Se guarda el token del dispositivo en
     el perfil de A.
  2. A cierra sesión. El token **sigue** en `usuarios/A`.
  3. Cuenta B entra en el mismo teléfono. Ahora el mismo token está en A y
     en B.
  4. Alguien le escribe a A por chat.
* **Resultado esperado:** el teléfono de B no recibe nada de A.
* **Resultado actual:** llega al teléfono, que ahora usa B. En la pantalla
  de bloqueo se ve el título y el cuerpo, o sea **el texto del mensaje
  privado dirigido a A**.
* **Impacto:** fuga de contenido privado entre cuentas en un teléfono
  compartido, prestado o vendido. Persiste indefinidamente: el token vive
  hasta que se desinstala la app o FCM lo rota.
* **Propuesta:** borrar `fcmToken` del perfil **antes** del `signOut()`, y
  hacerlo tolerante a fallos (si falla, seguir cerrando sesión igual, nunca
  dejar a alguien atrapado adentro por esto). `eliminarCuenta` ya lo hace
  bien, borra el doc entero.
* **Test de regresión:** en `test/data/`, con `fake_cloud_firestore`:
  "cerrar sesión borra el fcmToken del perfil" y "si el borrado falla, la
  sesión se cierra igual".

---

### ⚠️ P1-2 · CHAT-02 · Mensaje duplicado al recuperar la conexión

* **ID:** CHAT-02
* **Archivos:** `lib/data/chats_repository.dart:448`
  (`_escribirChatYMensaje`, `batch.commit().timeout(timeout)`),
  `lib/screens/chat_screen.dart:305` (el `catch` de `_send`)
* **Estado:** ⚠️ **POSIBLE PROBLEMA con razonamiento fuerte.**
  **NO VERIFICADO en runtime.** Lo digo explícito: no simulé la
  desconexión. Lo que sigue es deducción de dos comportamientos
  documentados, no una observación.
* **Descripción:** el razonamiento tiene dos patas, las dos ciertas por
  separado:
  1. `Future.timeout()` en Dart hace que el future lance, pero **no cancela
     la operación de abajo**.
  2. Firestore en móvil tiene persistencia offline activada por defecto.
     Un `batch.commit()` sin señal queda **encolado en disco** y se manda
     al reconectar. El future no resuelve hasta que el servidor confirma.

  Combinadas: sin señal, `commit()` no resuelve, a los 15s el `.timeout()`
  lanza, `_send` cae al `catch`, **le devuelve el texto al campo** y
  muestra "No se pudo enviar el mensaje. Intentá de nuevo.". Pero la
  escritura sigue encolada. Si la persona hace lo que el mensaje le pide,
  quedan dos escrituras encoladas.
* **Pasos para reproducir:**
  1. Abrir un chat. Modo avión.
  2. Escribir "hola" y enviar. Esperar 15 segundos.
  3. Aparece el error y el texto vuelve al campo.
  4. Enviar de nuevo (el error lo está pidiendo).
  5. Quitar el modo avión.
* **Resultado esperado:** un solo "hola".
* **Resultado actual esperado por el análisis:** dos "hola", y dos push al
  otro lado. `primeraVezQueSeVeEsteEvento` **no protege acá**: son dos
  documentos distintos con dos ids de evento distintos, no un reintento del
  mismo.
* **Impacto:** mensajes duplicados justo en las condiciones donde más se
  usa la app (señal mala en la calle). Coincide con lo que reportaste como
  "me llegó doble mensaje", aunque esa vez la causa era otra (dos push por
  un solo hecho, ya arreglado).
* **Propuesta:** no inventar un id de mensaje nuevo en cada intento. Generar
  el `DocumentReference` **una vez por intento de envío** y reusar el mismo
  id al reintentar, de modo que la segunda escritura pise a la primera en
  vez de sumarse. Alternativa más simple: no restaurar el texto en el campo
  cuando el fallo fue por timeout (distinguirlo de un fallo de permisos),
  y en cambio mostrar "se enviará cuando vuelva la conexión".
* **Test de regresión:** difícil con `fake_cloud_firestore` (no simula cola
  offline). Lo honesto es un test de la función de decisión: "un fallo por
  timeout no restaura el texto; un fallo por permiso sí".
* **Cómo verificarlo de verdad:** modo avión en un teléfono real, o el
  emulador de Firestore con `disableNetwork()`/`enableNetwork()`.

---

### ❌ P2-1 · CHAT-03 · `chats.update` no fija `rescateId`

* **Archivo:** `firestore.rules:230-234`
* **Estado:** ❌ **CONFIRMADO** contra emulador
* **Descripción:** la regla de update fija `adoptanteId`, `rescatistaId` y
  `creadoPor`, pero **no** `rescateId`. Un participante puede reapuntar el
  chat a cualquier otro animal.
* **Repro:** como adoptante de un chat propio,
  `updateDoc(chats/c1, { rescateId: 'animal_de_otro', animalNombre: 'x' })`
  → aceptado.
* **Impacto:** integridad. El chat pasa a mostrar otro animal para las dos
  partes. Además `onRescateActualizado` propaga por `where('rescateId','==')`,
  así que las ediciones del dueño de ese otro animal empiezan a caer en un
  chat ajeno. Los datos que viajan son públicos (nombre y foto del animal),
  así que no es fuga; es corrupción.
* **Propuesta:** agregar `request.resource.data.get('rescateId', null) ==
  resource.data.get('rescateId', null)` a la regla de update, igual que ya
  se hace con `creadoPor`.

### ❌ P2-2 · CHAT-04 · Los contadores de no leídos son escribibles a mano

* **Archivo:** `firestore.rules:230-234`
* **Estado:** ❌ **CONFIRMADO** contra emulador
* **Repro:** `updateDoc(chats/c1, { noLeidosRescatista: 9999 })` desde el
  adoptante → aceptado.
* **Impacto:** cosmético/molesto. Se le puede dejar a la contraparte un
  badge permanente con cualquier número.
* **Propuesta:** bajo. Acotar a que cada lado solo pueda poner en cero el
  contador propio, y que el incremento venga de un trigger. Es un rediseño;
  si no vale la pena, dejarlo documentado y no arreglarlo.

### ❌ P2-3 · CHAT-05 · `creadoEn` lo pone el cliente sin validación

* **Archivo:** `firestore.rules:269-277` (`mensajes`, `allow create`)
* **Estado:** ❌ **CONFIRMADO** contra emulador
* **Repro:** `addDoc(.../mensajes, { texto: 'x', emisor: 'adoptante',
  creadoEn: new Date('2099-01-01'), hora: '99:99' })` → aceptado.
* **Descripción:** la regla valida `emisor` y el largo de `texto`, nada
  más. La app manda `FieldValue.serverTimestamp()`, pero eso es convención
  del cliente. El orden de la conversación es `orderBy('creadoEn')`.
* **Impacto:** un mensaje puede clavarse arriba o abajo de la conversación
  para siempre, descolocando el hilo para las dos partes.
* **Propuesta:** `request.resource.data.creadoEn == request.time`.

### ❌ P2-4 · DATA-01 · La caché local no se limpia al cerrar sesión

* **Archivos:** `lib/data/auth_helper.dart:161`; consumidores en
  `lib/data/solicitudes_repository.dart:129,183,185` y
  `lib/data/rescates_repository.dart:193,243`
* **Estado:** ❌ **CONFIRMADO por lectura.** `grep -rn "clearPersistence"
  lib/` no devuelve nada.
* **Descripción:** la caché en disco de Firestore es por proyecto, no por
  usuario, y sobrevive al `signOut()`. Los documentos de la cuenta anterior
  quedan en el teléfono.
* **Impacto atenuado:** las consultas que caen a `Source.cache` están
  filtradas por uid, así que en la práctica no vi un camino donde B lea
  datos de A. **Pero** los datos siguen físicamente ahí, y eso choca con la
  promesa de borrado de cuenta que exige Google Play: `eliminarCuenta`
  limpia el servidor y no toca el dispositivo.
* **Propuesta:** `FirebaseFirestore.instance.clearPersistence()` después
  del `signOut()` (solo funciona sin listeners activos, así que hay que
  ubicarlo bien). Riesgo de rendimiento: la próxima sesión arranca con
  caché fría.

### ⚠️ P2-5 · CHAT-06 · Orden del mensaje recién enviado

* **Archivo:** `lib/data/chats_repository.dart:393` (`.orderBy('creadoEn')`)
* **Estado:** ⚠️ **POSIBLE PROBLEMA. NO VERIFICADO.**
* **Descripción:** mientras el `serverTimestamp` está pendiente de
  confirmación, el snapshot local lo entrega como `null`, y en un
  `orderBy` ascendente los nulos van **primero**. El mensaje recién enviado
  podría aparecer arriba de todo hasta que el servidor confirma.
* **Por qué no lo confirmo:** depende del `ServerTimestampBehavior` que
  aplique el SDK de Flutter en el `StreamBuilder`, y de si el salto es
  perceptible o dura milisegundos. Con buena señal probablemente no se ve.
  Con señal mala, sí.
* **Cómo verificarlo:** modo avión, mandar un mensaje, mirar dónde aparece.

---

### P3 (bajo)

**ROUTE-01 · 24 rutas y cero `redirect`.** ⚠️ **Riesgo latente, hoy NO
explotable.** `lib/routing/app_router.dart` no define ninguna guarda: nada
comprueba sesión ni rol al entrar a una ruta. Verifiqué si eso es
alcanzable desde afuera: **no**. El `AndroidManifest.xml` solo declara un
`intent-filter` de `MAIN`/`LAUNCHER`; el `VIEW`+`https` que aparece está
dentro de `<queries>` (que es para consultar qué apps pueden abrir un link,
no para recibirlos). **No hay deep links registrados**, así que las rutas
solo se alcanzan desde código propio. Pasa a P1 el día que se habilite un
deep link o la versión web.

**PRIV-01 · `rescates` es de lectura pública e incluye coordenadas
exactas.** Está documentado en las reglas como decisión consciente y no lo
discuto. Señalo la consecuencia: para los animales de un **albergue**, el
trigger copia `latitud`/`longitud` **del perfil del albergue**, o sea su
dirección, y queda legible **sin sesión**. Verificado: leí el documento
completo sin autenticarme. Para un albergue con local es probablemente
aceptable. Para una rescatista particular que publica desde su casa, esas
coordenadas son su domicilio.

**PERF-01 · `onPerfilActualizado` corre 5 consultas por escritura de
perfil.** Tras los cambios de ayer el trigger recorre 5 destinos
(animales de albergue, animales de rescatista, chats de albergue, chats de
negocio, solicitudes y chats como adoptante). `desactualizado` evita
**escribir**, pero las **consultas se hacen igual**. `ultimaVezActiva` se
escribe una vez por proceso de app, así que es una vez por apertura por
usuario. Es costo, no un bug. Vale medirlo antes de crecer.

**ROLE-01 · Roles auto-asignables.** ❌ Confirmado contra emulador. Ver la
nota en la matriz. Casi seguro intencional; lo listo porque dos reglas lo
tratan como barrera de confianza y no lo es.

---

## CHAT (resumen de la zona)

| Aspecto | Estado |
|---|---|
| Permiso para iniciar conversación | ❌ **CHAT-01, P0.** Roto por completo |
| Permiso para leer una conversación | ✅ Verificado. Solo las dos partes |
| Permiso para enviar mensaje | ✅ Verificado. `emisor` anclado al lado real, probado |
| Falsificar el emisor | ✅ Verificado que se rechaza (test propio en la suite) |
| Largo del texto | ✅ Verificado. Tope 2000 en la regla, no solo en la app |
| Mensajes duplicados (reintento del trigger) | ✅ Verificado. `create()` atómico en `_eventosProcesados` |
| Mensajes duplicados (reenvío offline) | ⚠️ **CHAT-02, P1.** No verificado en runtime |
| Orden de mensajes | ⚠️ **CHAT-05 confirmado** (fecha falsificable), **CHAT-06 no verificado** (pendientes) |
| Timestamps | ❌ **CHAT-05.** El cliente los elige |
| Contador de no leídos | ❌ **CHAT-04.** Escribible a mano |
| Editar mensaje | ✅ Imposible. Sin regla de `update`, denegado por defecto |
| Borrar mensaje | ✅ Imposible por la misma razón. **Pero tampoco puede la app**: no hay forma de borrar un chat basura recibido por CHAT-01 |
| Doble submit del botón | ✅ Mitigado. `_msgCtl.clear()` corre antes del `await`, el segundo toque lee vacío |
| Listeners duplicados | ✅ Los streams son `late final`, se construyen una vez |
| Conversaciones duplicadas | ✅ Id determinístico (`idAnimal(rescateId, adoptanteId)`) |
| Múltiples pestañas/dispositivos | ❓ **NO SE PUEDE VERIFICAR** sin dos dispositivos reales |
| Paginación del historial | ❓ **NO VERIFICADO.** El stream trae la subcolección **entera** sin `limit`. Un chat muy largo carga todo. No lo probé con volumen |

---

## SEGURIDAD

**Lo que probé y aguantó** (✅ verificado contra emulador, 67 tests
existentes + mis sondeos):

* `solicitudes`: no se puede crear una ya aprobada, ni contra el animal de
  otro, ni con un `rescatistaId` que no sea el dueño real, ni con un
  `rescateId` inexistente o vacío. No se pueden colar campos de contrabando
  al aprobar. El adoptante no puede auto-aprobarse.
* `rescates`: no se puede editar ni borrar el de otro, ni reescribir
  `rescatistaId`/`creadoPor`.
* `servicios`, `hogaresDePaso`: sin fuga entre cuentas. `aliadoId` y
  `albergueId` no se pueden reescribir.
* `favoritos`: solo el adoptante dueño.
* `preferencias`: solo el dueño.
* `storage.rules`: acotado a `foto1.jpg`/`foto2.jpg`, tope 15MB, tipo
  imagen, dueño verificado cruzando contra Firestore. Cualquier otra ruta
  del bucket queda denegada por defecto.
* `eliminarCuenta`: exige `request.auth` y usa **siempre**
  `request.auth.uid`, nunca un uid del payload. Sin IDOR.
* `_eventosProcesados`: sin regla, denegado a clientes.
* Borrar el propio `usuarios/{uid}`: **denegado**. (Curiosidad: se deniega
  por accidente afortunado. En un `delete`, `request.resource.data` es
  null, y la condición de `roles` revienta al evaluarse. Funciona, pero por
  el motivo equivocado. Si alguien "arregla" esa expresión, se abre.)

**IDOR:** busqué específicamente. No encontré ningún caso donde cambiar un
id dé acceso a un recurso ajeno, salvo lo que ya está en CHAT-01 y CHAT-03.

**Secretos en el cliente:** `google-services.json` y las claves de API de
Firebase son públicas por diseño (no son secretos; la barrera son las
reglas). No encontré claves de servicio ni tokens de admin en `lib/`.

**Logs con información sensible:** ❓ **NO VERIFICADO en profundidad.** Vi
`debugPrint` con mensajes de error, no con datos personales. No hice un
barrido exhaustivo.

**Lo que NO se puede verificar desde acá:**

* Si la política de TTL de `_eventosProcesados` está realmente activada en
  la consola (el código la asume; si no está, esa colección crece sin
  límite).
* Si App Check está activado. **No vi ninguna configuración de App Check.**
  Sin él, cualquiera puede hablarle directo a tu Firestore desde un script
  con una cuenta registrada, que es exactamente lo que hace explotable a
  CHAT-01 a escala.
* Reglas efectivamente desplegadas en producción contra las del repo.

---

## TEST COVERAGE

**Lo que hay** (ejecutado hoy, resultados reales):

| Suite | Comando | Resultado |
|---|---|---|
| Dart | `flutter test` | **571 pasan**, 0 fallan |
| Functions | `npm test` en `functions/` | **61 pasan**, 0 fallan |
| Reglas | `npm test` en `test_rules/` | **67 pasan**, 0 fallan |
| Análisis | `flutter analyze` | **0 errores**, 14 warnings, 74 info |

Los 14 warnings son todos `subtype_of_sealed_class` en `test/data/`, de los
mocks de `fake_cloud_firestore`. Ninguno en `lib/`. Los 74 info son estilo
preexistente (llaves en `if` de una línea, `withOpacity`).

**Lo que cubren bien:** la capa `lib/data/` (14 archivos de test), la
lógica pura de `lib/domain/` y de `functions/*_logica.js`, y las reglas de
Firestore con casos negativos.

**Los huecos, en orden de gravedad:**

1. **Las reglas de `chats` son las menos probadas de todas.** La suite
   tiene casos de `mensajes` (emisor falsificado, largo del texto), pero
   **ningún caso negativo de `chats.create`**. Por eso CHAT-01 sobrevivió:
   el caso positivo lo ejercita la app todos los días, el negativo no lo
   prueba nadie.
2. **`fake_cloud_firestore` no aplica reglas de seguridad.** Ya está
   documentado en el código, pero conviene repetirlo: **ningún test de
   `test/data/` puede detectar un agujero de permisos.** Un test verde ahí
   no dice nada sobre seguridad.
3. **3 de 33 pantallas tienen test.** `lib/screens/` son 26.005 de las
   34.886 líneas del proyecto, o sea el 75% del código, con cobertura casi
   nula. Los bugs de estado, loading, modales y navegación que pide la
   Fase 5 **no están cubiertos por nada**.
4. **Cero tests de integración y cero E2E.** No hay flujo completo
   probado de punta a punta.
5. **Nada prueba el comportamiento sin conexión**, que es justo donde vive
   CHAT-02.

**Lo que NO revisé:** si hay tests que son falsos positivos. Los 571 pasan,
pero no audité si alguno afirma algo trivial. Es un trabajo aparte y no
quiero decir que lo hice si no lo hice.

---

## PLAN DE REPARACIÓN

Orden recomendado. La regla que seguí: primero lo explotable hoy contra
usuarios reales, y dentro de eso, primero lo que se arregla sin tocar la
app (solo reglas, se despliega solo, sirve para todas las versiones
instaladas).

**Tanda 1 — solo `firestore.rules`, sin APK nuevo**

1. **CHAT-01** (P0). Exigir `creadoPor` presente y anclado en `create`.
2. **AUTH-01** (P0). Separar `get` de `list`. Antes hay que confirmar que
   ninguna pantalla liste `usuarios`.
3. **CHAT-03** (P2). Fijar `rescateId` en `update`. Una línea.
4. **CHAT-05** (P2). `creadoEn == request.time`. Una línea.

Las 4 van juntas: mismo archivo, mismo deploy, cada una con su caso
negativo en `test_rules/`. El `predeploy` de `firebase.json` ya corre esa
suite y no publica si falla.

**Tanda 2 — cliente, necesita APK**

5. **AUTH-02** (P1). Borrar `fcmToken` antes del `signOut()`.
6. **CHAT-02** (P1). Primero **verificarlo en modo avión**. Si se confirma,
   id de mensaje estable entre reintentos.

**Tanda 3 — cuando haya aire**

7. **DATA-01** (P2). `clearPersistence()` al cerrar sesión.
8. **CHAT-06** (P2). Verificar primero; puede no existir.
9. **PERF-01, PRIV-01, ROLE-01, CHAT-04** (P3). Decisiones de producto más
   que bugs. Conviene decidirlas, no necesariamente cambiarlas.

**Fuera de la lista de bugs, pero lo pondría antes que la tanda 3:**

* **Averiguar si App Check está activado.** Es lo que separa "un agujero de
  reglas" de "un agujero de reglas explotable con un script desde
  cualquier lado". Cambia la urgencia real de todo lo de arriba.
* **Confirmar que la política de TTL de `_eventosProcesados` existe.**

---

## Qué queda explícitamente sin verificar

Para que no se lea como cobertura que no tengo:

* ❓ Todo el comportamiento de runtime del chat: offline, reconexión, dos
  dispositivos, dos sesiones simultáneas.
* ❓ Estados de UI: loading infinito, modales, navegación atrás, estados
  imposibles. 3 de 33 pantallas tienen test y no ejecuté la app.
* ❓ Entrega real de push de punta a punta.
* ❓ Concurrencia real de dos aprobaciones simultáneas. La transacción
  existe y está bien escrita, pero `fake_cloud_firestore` no simula
  contención, así que el test que pasa no prueba el caso.
* ❓ Paginación del historial de chat con volumen real.
* ❓ App Check, TTL de `_eventosProcesados`, y si las reglas desplegadas
  coinciden con las del repo.
* ❓ Si alguno de los 571 tests es un falso positivo.

---

*Ningún archivo del proyecto fue modificado para producir este informe.*
