# Arquitectura de roles y permisos

Este documento explica un problema real que tuvo la app y la solución que se
implementó, para que quien toque este código después (probablemente Claude,
en una sesión futura sin memoria de esta) entienda el porqué, no solo el qué.

## El incidente que originó esto

En una misma sesión de trabajo se arreglaron 3 bugs seguidos, todos con la
misma forma exacta: una pantalla filtraba por dueño (`rescatistaId == uid`)
pero se olvidaba de filtrar también por el sub-rol con el que se creó el
documento (`creadoPor == 'rescatista'` vs `'albergue'`). Como una misma
cuenta puede tener varios roles a la vez (`rescatista` + `albergue`, por
ejemplo — es una función real de la app), ese olvido hacía que un rol viera
datos del otro.

Durante la investigación aparecieron dos bugs más de la misma familia:
`preferencias` usaba un único documento compartido (`preferencias/adoptante`)
para TODOS los usuarios, y el contador de "Nuevas solicitudes" del rescatista
tampoco filtraba por `creadoPor`.

La causa de fondo no era ningún bug individual — era que había ~100 llamadas
`FirebaseFirestore.instance.collection(...).where(...)` escritas a mano,
repartidas en 28+ pantallas, sin ninguna capa central. Cada pantalla
reinventaba su propia consulta, así que era fácil que una se olvidara una
condición. Y no había ninguna Regla de Seguridad de Firestore desplegada —
cualquier bug de filtrado del cliente era, en ese momento, un hueco de
seguridad real, no solo un error de UI.

## Los dos conceptos de "rol" (no confundirlos)

1. **Rol de cuenta** (`usuarios/{uid}.roles`, lista): qué puede hacer esta
   persona en general — `adoptante`, `rescatista`, `albergue`, `aliado`. Uno
   puede tener varios a la vez.
2. **Rol de creación** (`creadoPor` en el documento, tipo [`CreatorRole`](lib/data/creator_role.dart)):
   con qué sombrero se creó ESE documento específico. Solo existe para
   `rescates` y `solicitudes`, y solo tiene dos valores: `rescatista` o
   `albergue`.

Cada bug de esta familia fue: se validó #1 (¿es del uid?) y se olvidó #2
(¿con qué sombrero?). La arquitectura de acá modela esta distinción de forma
explícita en vez de dejarla implícita en cada pantalla.

## Capa 1 — Firestore Security Rules (`firestore.rules`)

Esta es la barrera real. El filtrado en Dart es una optimización de UX (no
traer datos de más), **nunca** hay que asumir que alcanza para seguridad —
un bug de cliente, o alguien llamando a Firestore directo sin pasar por el
app, tienen que seguir topándose con la regla del servidor.

Tabla resumen (ver el archivo para el detalle exacto):

| Colección | Lectura | Escritura |
|---|---|---|
| `usuarios` | cualquier logueado (hay perfiles públicos) | solo el dueño; `roles` se valida contra la lista permitida |
| `rescates` | pública (catálogo de adopción) | solo el dueño, y `creadoPor` debe coincidir con un rol de cuenta que ese uid realmente tenga |
| `solicitudes` | adoptante dueño o rescatista/albergue destinatario | crear: solo el adoptante. Cambiar `estado`: solo el rescatista/albergue destinatario, y solo de `pendiente` a `aprobada`/`rechazada` — el adoptante no puede escribir su propia solicitud después de creada |
| `preferencias/{uid}` | solo el dueño | solo el dueño |
| `favoritos` | solo el adoptante dueño | solo el adoptante dueño |
| `chats` / `mensajes` | los dos participantes | los dos participantes |
| `servicios` | pública (catálogo de negocios) | solo el `aliadoId` dueño |

Importante: el día que se despliega este archivo, cualquier colección sin
regla explícita queda **bloqueada por defecto**. Por eso el archivo cubre
todas las colecciones que existen hoy, aunque solo `rescates`/`solicitudes`/
`preferencias` tengan repositorio en Dart todavía.

## Fotos de animales — Firebase Storage (`storage.rules`)

Las fotos de `rescates` viven en Firebase Storage (`rescates/{rescateId}/foto{1,2}.jpg`),
no embebidas en el documento de Firestore. El documento solo guarda
`fotoUrl`/`fotoUrl2` (URLs de descarga). Antes eran strings base64 dentro
del propio doc — eso hacía que el feed público descargara el catálogo
entero con todas las fotos en cada apertura, y acercaba cada documento al
límite de 1 MiB de Firestore.

Repositorio: [`RescateFotosRepository`](lib/data/rescate_fotos_repository.dart)
(`subir()`, `eliminar()`, `eliminarTodas()`) — mismo patrón que el resto de
`lib/data/`. Widget de lectura: `FotoUrl` en `lib/widgets/fotos.dart` (análogo a
`FotoSegura`, pero para `Image.network` en vez de base64).

**El flujo de creación está reordenado a propósito**: primero se crea el
documento en Firestore (sin foto), después se sube la foto a Storage usando
el id ya generado, y por último se actualiza el doc con la URL. Es así
porque `storage.rules` verifica dueño cruzando contra el documento de
Firestore (`firestore.get(...)`) — ese documento tiene que existir antes de
poder subir el archivo. Si falla la foto obligatoria (o el paso de crear el
doc), se hace rollback completo; si falla solo la segunda foto (opcional),
se publica igual sin ella. Ver `subir_rescate_screen.dart`/`subir_lote_screen.dart`.

**Esquema mixto en `chats` — importante si tocás fotos de chat:**
`ChatsRepository.asegurarChatAnimal()` guarda `fotoUrl` (foto del animal,
Storage). `asegurarChatNegocio()` sigue guardando `fotoBase64` (logo propio
del negocio aliado — nunca migró, no tiene el problema de "N documentos en
una query" porque es 1 foto por cuenta). Los dos tipos de chat viven en la
misma colección y se renderizan con el mismo código
(`chat_screen.dart`, `adoptante_chats_screen.dart`), así que esas pantallas
revisan los dos campos (`fotoUrl` primero, `fotoBase64` como fallback) en
vez de asumir uno solo.

**Fotos de perfil (usuario/albergue/aliado) siguen en base64** — 1 foto por
cuenta, sin el problema de escala del feed. Quedaron fuera a propósito;
si algún día se migran, sería el mismo patrón (repositorio + `FotoUrl` +
reordenar creación si la regla de Storage llega a necesitar verificar dueño).

**Incidente 2026-07-10 — "publico y no pasa nada" (dos causas encadenadas):**

1. *En producción, TODA subida de foto daba 403* aunque la regla estaba bien
   escrita y pasaba los tests contra el emulador local. Causa: la regla usa
   `firestore.get()` (cross-service), y eso requiere que el agente de
   servicio de Storage (`service-<nº-proyecto>@gcp-sa-firebasestorage.iam.gserviceaccount.com`)
   tenga el rol `roles/firebaserules.firestoreServiceAgent`. La CLI de
   Firebase otorga ese rol al desplegar, **pero se lo salta en silencio en
   modo no interactivo** (`if (nonInteractive) return;` en su código) — y el
   deploy original corrió desde un script. El emulador local no exige IAM,
   por eso los tests de reglas no lo detectaron. Si esto vuelve a pasar
   (proyecto nuevo, restore, etc.): otorgar el rol a mano en IAM o
   re-desplegar `storage.rules` desde una terminal interactiva y aceptar la
   pregunta de permiso.

2. *El error real quedaba escondido*: en el rollback de `_publicar()` había
   un `.catchError((_) {})` sobre el `Future` de `eliminarTodas()`, que en
   runtime era un `Future<List<void>>` (devolvía el `Future.wait` directo) —
   eso lanza `Invalid argument (onError)` DENTRO del bloque `catch`, y el
   SnackBar de error nunca llegaba a mostrarse. Regla práctica que quedó en
   el código: para ignorar errores best-effort usar `try { await ... } catch (_) {}`,
   no `.catchError((_) {})`, y los repos nunca devuelven `Future.wait`
   directo (siempre `async`/`await` para que el tipo runtime sea `Future<void>` real).

## Capa 2 — Repositorios en Dart (`lib/data/`)

**Regla del proyecto: ninguna pantalla en `lib/screens/` debe llamar
`FirebaseFirestore.instance.collection(...)` directamente para `rescates`,
`solicitudes`, `preferencias`, ni para escribir `usuarios.roles`.** Siempre a
través de `lib/data/`.

Pieza clave: `CreatorRole` (`lib/data/creator_role.dart`) es un parámetro
**obligatorio**, no opcional, en los métodos que devuelven "mis animales" o
"mis solicitudes":

```dart
Stream<QuerySnapshot<Map<String, dynamic>>> misRescates({
  required String uid,
  required CreatorRole role,   // ← no se puede olvidar, es obligatorio
}) => ...
```

Esto es lo que hace que "olvidarse el filtro" pase de ser un bug fácil de
copiar-pegar a un error de compilación si alguien intenta omitirlo.

`SolicitudesRepository` tiene dos métodos con nombres distintos —
`paraOwner()` y `misSolicitudes()` — en vez de uno genérico, porque son dos
relaciones distintas con la misma colección. El nombre del método ya dice
qué relación es, así que no se puede llamar el equivocado por error.

### Mensajes de chat — `ChatsRepository` es el único que los escribe

La escritura de un mensaje tiene cuatro detalles que **no se ven** leyendo
una copia suelta, y por eso ninguna pantalla arma la suya:

1. **El orden importa**: primero la vista previa del chat, después el
   mensaje. Al revés, si falla la segunda escritura el mensaje ya quedó
   guardado y un reintento lo duplica.
2. **`emisor` no alcanza para dibujar.** Lo dicta la regla de Firestore
   (`adoptanteId == uid ? 'adoptante' : 'rescatista'`), así que en una
   AUTOCONSULTA vale siempre `'adoptante'`, escriba quien escriba. El
   sombrero real va aparte, en `escritoPorRescatista`, y **solo se usa para
   dibujar y solo en autoconsulta** (ver `esMiBurbuja`) — tomarlo como
   señal de seguridad reabriría el agujero de firmar un mensaje como otro.
3. **La hora** tiene un formato único (`horaAhora()`).
4. **Buscar un chat que no existe da `permission-denied`**, no "no está":
   las reglas no pueden probar "sos participante" de un documento ausente.
   `buscarDeAnimal()` traduce eso a `null`.

El aviso de "el animal falleció" (`CambiarEstadoSheet`, en
`widgets/cambiar_estado_sheet.dart`) tenía su propia copia hecha
a mano y había quedado atrás en **las cuatro cosas a la vez**, sin que nada
lo delatara: mensajes duplicables al reintentar, el aviso dibujado del lado
equivocado en autoconsulta, la hora repetida a mano, y una excepción suelta
cuando el chat no existía. Hallazgo de auditoría, no de pruebas — ningún
usuario lo habría reportado como "cuatro bugs", se ve como "a veces los
mensajes se comportan raro".

Las decisiones que antes vivían inline en las pantallas hoy son funciones
puras y testeadas del repositorio: `esMiBurbuja`, `noLeidosPara`,
`perteneceALaLista`, `emisorPara`, `campoLogoRescatista`/`campoLogoAdoptante`,
`rolParaRecontactar`.

#### `avisarSobreAnimal`: avisar por chat, creando el chat si hace falta

Existía DOS veces, con comportamiento DISTINTO — `enviarMensajeChat`
(`solicitudes_rescatista_screen.dart`, para aprobar/rechazar/vencimiento/
seguimiento) sí creaba el chat si no existía; el aviso de "el animal
falleció" (`CambiarEstadoSheet`) no, se limitaba a buscar uno existente.

Esa diferencia era un bug, no solo duplicación: `adoptanteIdEnProceso`
(a quién avisar cuando el animal muere) solo se completa cuando una
solicitud se APRUEBA — un animal con solicitudes todavía PENDIENTES
(nunca aprobadas, el caso más común con un animal recién publicado) no
tenía a nadie en ese campo. Y aunque lo tuviera, una solicitud recién
mandada muchas veces todavía no tiene ningún chat abierto — así que el
aviso de "falleció", al no poder crear uno, se descartaba en silencio.
Hallazgo real de Eliza: pidió adoptar un animal, el rescatista lo marcó
como fallecido, y el aviso nunca le llegó.

El arreglo fue doble: `SolicitudesRepository.rechazarPendientesPorFallecimiento()`
cierra todas las solicitudes que seguían esperando respuesta **y devuelve
las que cerró**, así que esa misma lista es la que recibe el aviso — no solo
el adoptante ya aprobado. Que sea UNA operación no es cosmético: hubo un
método de solo lectura para obtener la lista, y con dos pasos separados el
orden importa, porque cerrar primero deja la consulta vacía y a todos sin
aviso. Y
`ChatsRepository.avisarSobreAnimal()` es ahora la única fuente de "avisar
+ crear el chat si hace falta" — `enviarMensajeChat` y el aviso de
fallecido delegan los dos ahí, así que ninguno puede volver a quedarse
atrás del otro en si crea el chat o no.

#### Avisos automáticos: ¿a quién le suma "sin leer"?

Un mensaje escrito por una PERSONA solo le suma "sin leer" al que lo
recibe — el que lo escribió ya sabe que lo escribió. Pero
`solicitudes_rescatista_screen.dart` también manda avisos que dispara el
paso del tiempo (vencimiento de hogar de paso, seguimiento post-adopción a
los 7/30 días), sin que el rescatista/albergue haga nada. Esos se
guardaban con `escritoPorRescatista: true` (se dibujan de su lado) pero
sin sumarle ningún "sin leer" a él — quedaban en el chat sin ninguna señal
visible (ni el badge azul del panel, ni el ícono de Chats), y solo se
enteraba si abría esa conversación puntual por otro motivo. Con varios
animales a la vez, en la práctica nunca se enteraba. Hallazgo real de
Eliza: "el rescatista recibe un mensaje... pero no se da cuenta para
nada".

`ChatsRepository.registrarMensaje(avisoParaAmbosLados: true)` es la
excepción a la regla de arriba, y es SOLO para esto: avisos que la persona
no disparó a propósito. Un mensaje que sí dispara una acción consciente
suya (aprobar, rechazar una solicitud) sigue siendo de un solo lado — de
esos ya sabe, porque los hizo ella misma. La pregunta para decidir cuál es
cuál: **¿el rescatista/albergue tomó una decisión ahora mismo, o el
sistema mandó esto solo porque pasó el tiempo?**

#### El contador de "sin leer" es atómico con el mensaje — `_escribirChatYMensaje`

Cada mensaje implica dos escrituras: la vista previa/contador del chat
(`chats/{id}`) y el mensaje en sí (`chats/{id}/mensajes/{msgId}`). Hasta
hace poco eran dos operaciones separadas y seguidas (`.set()` del chat,
`await`, después `.add()` del mensaje) — con el orden elegido a propósito
(chat primero) para que un mensaje nunca quedara guardado sin que su vista
previa se reflejara. Pero esa elección dejaba abierto el problema
simétrico: si el proceso moría **después** de escribir el chat y **antes**
de escribir el mensaje, el contador de "sin leer" quedaba incrementado (o
el chat recién creado) sin que el mensaje correspondiente existiera de
verdad — un "sin leer" fantasma para siempre, porque nada en la app
recalcula el contador desde los mensajes reales de la subcolección.
Auditoría de arquitectura, riesgo 🟡 "sin reconciliación".

**La solución no es reconciliar, es no dejar que se desincronice.** Las
dos escrituras ahora viajan en un único `WriteBatch` (`_escribirChatYMensaje`,
privado) — Firestore garantiza que todas las escrituras de un batch se
confirman juntas o ninguna lo hace. Ya no hay dos escrituras que puedan
quedar a mitad de camino una respecto de la otra, así que no hace falta
ningún mecanismo de reconciliación: el desfasaje deja de ser posible por
construcción. Como beneficio adicional, un reintento tras un fallo ya no
puede duplicar nada (un fallo ahora significa que NINGUNA de las dos
escrituras se aplicó, no que una quedó a medias).

`registrarMensaje()` y la rama de `avisarSobreAnimal()` que crea el chat
de cero pasan las dos por acá. `agregarMensaje()` (solo el mensaje, sin
tocar el chat) sigue existiendo para el caso genuino de "el chat ya tiene
su vista previa resuelta de antes" — pero su propio comentario ahora
advierte contra volver a combinarla con una escritura aparte del chat,
que es exactamente el patrón que este arreglo cerró.

### El vocabulario del dominio vive en el repositorio

Los valores válidos de cada campo de un rescate (`estados`, `tamanos`,
`edades`, `especies`, `urgencias`, …) son constantes de
`RescatesRepository`, no listas declaradas en cada pantalla.

Estaban declaradas por separado en `subir_rescate_screen.dart` y
`editar_rescate_screen.dart`, y **ya se habían desincronizado**:

```
publicar: ['Sano', 'Herido', 'En tratamiento', 'Crítico']
editar:   ['Sano', 'En tratamiento', 'Recuperado']
```

Un animal publicado como `Herido` o `Crítico` se abría en Editar **sin
ningún chip marcado** — su valor real no estaba en la lista de esa
pantalla. Parecía que el dato se había perdido, y tocar cualquier otra
opción lo pisaba de verdad. Al revés, `Recuperado` solo podía ponerse
editando, nunca al publicar. Nadie lo reportó nunca: no se ve como un
error, se ve como un formulario vacío.

Dos listas para el mismo campo no se mantienen iguales a mano. Una sola no
puede divergir.

**Quitar un valor de una lista es una migración, no una edición.** Los
animales que ya lo tengan guardado caen en el mismo caso de arriba. Por
eso `estados` conserva la unión de las dos listas históricas.

Como red de seguridad permanente, `ChipsSeleccionables`
(`widgets/chips_seleccionables.dart`)
dibuja igual un valor guardado que no esté entre sus opciones, marcado y
como una opción más — así este fallo nunca vuelve a ser invisible, ni con
datos viejos ni si alguien quita un valor sin migrar.

### Checklist para agregar una pantalla nueva que toque estas colecciones

1. ¿Existe ya el método que necesitás en `lib/data/`? Si no, agregalo ahí,
   no en la pantalla.
2. ¿El método que devuelve "mis cosas" pide `CreatorRole` si la colección es
   `rescates` o `solicitudes`? Si no lo pide, probablemente hay un bug de
   esta misma familia esperando a pasar.
3. ¿Escribiste una regla en `firestore.rules` para la colección si es nueva?
4. ¿Agregaste un test en `test/data/` para el método nuevo? (Con
   `fake_cloud_firestore` — no hace falta tocar Firebase real.)

## Capa 3 — Servicios de plataforma (`lib/services/`)

Mismo principio que `lib/data/`, pero para lo que no es Firestore: **cuando
una secuencia que habla con el sistema operativo aparece en más de una
pantalla, se le da un dueño único en `lib/services/` y las pantallas
consumen ese dueño.**

### `UbicacionService` — GPS y geocoding

**Regla: ninguna pantalla llama `Geolocator.getCurrentPosition`,
`isLocationServiceEnabled`, `checkPermission`, `requestPermission`,
`getLastKnownPosition`, `placemarkFromCoordinates` ni `locationFromAddress`
directamente.** Todo pasa por `UbicacionService`.

Excepciones legítimas, que NO son la secuencia de detección:
`Geolocator.distanceBetween` (matemática pura, sin plataforma) y
`Geolocator.openLocationSettings`/`openAppSettings` (abrir ajustes, que es
UI y depende de cada pantalla).

**El incidente que originó esto** (mismo patrón que el de `CreatorRole`, en
otro dominio): esa secuencia estaba copiada a mano en **7 pantallas** —
`home_screen`, `perfil_adoptante_screen`, `adoptante_feed_screen`,
`subir_rescate_screen`, `editar_rescate_screen`, `seleccion_rol_screen` y
`CampoCiudad` (`widgets/campo_ciudad.dart`). Las copias divergieron, así que cada bug de
ubicación existía tantas veces como copias sin arreglar hubiera, y
arreglarlo en una no arreglaba las otras. En una sola jornada de pruebas
aparecieron cuatro familias del mismo cluster:

| Bug | Copias afectadas |
|---|---|
| Diálogo nativo de Android en bucle (faltaba chequear `isLocationServiceEnabled` antes de pedir posición) | 3 |
| Aviso de GPS pegado sobre la pantalla de atrás (SnackBar sin limpiar en `dispose`) | 3 |
| Un solo tropiezo del GPS dejaba el pin vacío toda la visita (solo el geocoding se reintentaba, no la posición) | 2 |
| Texto de ubicación y coordenadas desincronizados al editar a mano | 2 |

Al centralizar apareció una copia más que nadie había encontrado:
`seleccion_rol_screen` (la pantalla de registro) seguía sin el chequeo de
servicio **y** sin `timeLimit`, o sea que le disparaba el diálogo nativo a
cada persona que se registraba.

**El servicio nunca hace UI, a propósito.** Devuelve `ResultadoUbicacion` y
cada pantalla decide qué mostrar, porque esa parte sí difiere de verdad
(publicar un rescate muestra un SnackBar con "Abrir Ajustes"; el pin del
perfil simplemente no se dibuja). Meter el SnackBar adentro del servicio
habría forzado un `BuildContext` ahí y con él toda la familia de bugs de
"aviso pegado sobre otra pantalla".

Los motivos de falla se distinguen (`FalloUbicacion`) en vez de devolver un
único `null`, porque cada uno lleva a una acción distinta: servicio apagado
→ ajustes de ubicación del sistema; permiso bloqueado → ajustes de la app;
permiso denegado → no mostrar nada (se le puede volver a preguntar).

`UsoUltimaConocida` tiene 3 valores porque los 3 usos eran decisiones
reales y distintas, no copias divergidas: no usarla (publicar un rescate
quiere dónde está el animal AHORA), usarla como anticipo y refinar (el
feed), o quedarse con ella sin encender el GPS (un pin a nivel ciudad).

### Checklist para una pantalla nueva que necesite ubicación

1. ¿Necesitás coordenadas, nombre de ciudad, o los dos? → `actual(conCiudad: ...)`.
2. ¿Es un lugar que la persona escribió a mano? → `desdeTexto()`, y respetá
   la distinción entre `null` ("eso no existe") y excepción ("no se pudo
   verificar"): aplanarlas hace que un problema de señal bloquee una ciudad
   válida.
3. ¿Vas a mostrar un aviso? Mapeá `FalloUbicacion` vos, en la pantalla, y
   acordate de limpiar los SnackBars en `dispose` (ver el patrón de
   `_scaffoldMessenger` en `subir_rescate_screen.dart`).
4. Agregá el caso a `test/services/ubicacion_service_test.dart` si sumaste
   una rama nueva al servicio. Los fakes de `GeolocatorPlatform`/
   `GeocodingPlatform` ya están ahí, no hace falta hardware ni red.

### `ubicacion_lifecycle.dart` — reintentar cuando la persona vuelve de segundo plano

**Regla: ninguna pantalla implementa `WidgetsBindingObserver` a mano para
reintentar una detección de ubicación al volver de segundo plano.** Se usa
uno de los dos mixins de `lib/services/ubicacion_lifecycle.dart`.

Antes de esto, el patrón "escuchar `didChangeAppLifecycleState`, y si
volvió a `resumed` y todavía falta la ubicación, reintentar" estaba copiado
a mano en **5 pantallas** (`home_screen`, `perfil_adoptante_screen`,
`adoptante_feed_screen`, `subir_rescate_screen`, `editar_rescate_screen`),
cada una con su propio `addObserver`/`removeObserver`/`dispose`.

Hay **dos** variantes, y no son intercambiables — la diferencia es si el
reintento puede abrir el diálogo nativo de permisos:

- **`ReintentoUbicacionAlVolver`** — para reintentos que llaman
  `UbicacionService.actual(pedirPermisoSiFalta: false)`, que nunca abre el
  diálogo del sistema. Por eso es seguro reintentar en **cualquier**
  `resumed` mientras falte el recurso, sin condición extra. La usan
  `home_screen`, `perfil_adoptante_screen` y `adoptante_feed_screen`.
- **`ReintentoUbicacionTrasAjustes`** — para reintentos que SÍ pueden abrir
  el diálogo del sistema (la persona tocó un botón de "detectar mi GPS" a
  propósito). Reintentar sin condición acá reabriría el bug real que esto
  vino a arreglar: diálogo → la app pasa a segundo plano → `resumed` →
  reintento → diálogo de nuevo → bucle, pantalla inusable. Por eso solo
  reintenta **una vez**, y solo tras llamar `marcarVolviendoDeAjustes()`
  justo antes de abrir Ajustes del sistema. La usan `subir_rescate_screen`
  y `editar_rescate_screen`.

Cada mixin pide 2 getters (`yaTieneUbicacion`, `detectandoUbicacion`) y un
método de reintento — la pantalla sigue siendo dueña de qué significa
"tener ubicación" y cómo se ve un reintento, el mixin solo decide cuándo
llamarlo.

**Checklist para una pantalla nueva con este problema:**

1. ¿El reintento puede abrir el diálogo nativo de permisos? Si nunca lo
   abre (`pedirPermisoSiFalta: false`) → `ReintentoUbicacionAlVolver`. Si sí
   puede → `ReintentoUbicacionTrasAjustes`, y llamá
   `marcarVolviendoDeAjustes()` justo antes de mandar a Ajustes.
2. La clase de estado necesita `with WidgetsBindingObserver, <Mixin>` (en
   ese orden) además de extender `State<T>`.
3. No agregues un `dispose()` que llame `removeObserver` — el mixin ya lo
   hace vía `super.dispose()`. Si la pantalla tiene otra limpieza propia
   (streams, controllers), esa sigue en su `dispose()` normal.
4. Agregá el caso a `test/services/ubicacion_lifecycle_test.dart` si sumaste
   una rama nueva a alguno de los dos mixins.

## Capa 4 — Widgets de UI y funciones de negocio (`lib/widgets/`, `lib/domain/`, `lib/theme.dart`)

Mismo problema que las capas anteriores, pero de layout en vez de datos: un
patrón visual copiado a mano en varias pantallas, arreglado en una y no en
las otras porque nada avisa que hay una segunda copia.

### De un archivo de 2.350 líneas a tres carpetas con un dueño cada una

`theme.dart` mezclaba cinco cosas de naturaleza distinta — tokens de color,
widgets de campo de formulario, widgets de UI compartida, funciones
utilitarias sueltas, y un par de diálogos que sí escriben al backend. Un
primer paso lo reordenó en 5 secciones dentro del mismo archivo; el
siguiente lo partió de verdad en archivos separados, uno por pieza, con
imports explícitos en vez de "todo entra con `theme.dart`":

```
lib/theme.dart                          ← SOLO tokens de diseño ahora
  appBg/appDark/appTeal/appOrange/appInk, msgError/msgAdvertencia/msgExito,
  aliadoTipoIcono/Pastel/Texto, cicloColor — 77 líneas, nada de widgets

lib/domain/
  reglas_negocio.dart                   ← puro Dart, sin Flutter
    formatearFecha, whatsappUrl, sitioWebUrl, umbral de estancamiento
    (constantes + 3 funciones), tiempoRelativo, prioridadEstado,
    contarMensajesSinLeer
  resolucion_perfil.dart                ← de la fase 3, ver más abajo
  compatibilidad.dart                   ← puntaje + explicación de
    compatibilidad adoptante/animal (mudado acá desde la raíz de lib/)

lib/widgets/                            ← 15 archivos, uno por widget/grupo
  campos_perfil.dart          perfilLabel, perfilCampo (sin más deps)
  campo_pais_telefono.dart    Pais, banderaPais, CampoTelefono... (usa
                               campos_perfil.dart)
  campo_ciudad.dart           CampoCiudad (usa UbicacionService)
  tardando_mucho_mixin.dart   TardandoMuchoMixin
  umbral_estancado_sheet.dart UmbralEstancadoSheet (usa reglas_negocio.dart)
  especie_chip.dart           especieOpciones/especieChipGap/especieChip
  fondo_decorativo.dart       _PawPrintPainter + LeafOverlay/leafBackground
                               (juntos a la fuerza: clase privada compartida)
  estado_error_feed.dart      errorFeedState
  fotos.dart                  bytesFotoSegura, FotoSegura/FotoUrl/FotoAnimal
  texto_sin_desborde.dart     TextoSinDesborde
  chips_seleccionables.dart   ChipsSeleccionables
  avatares.dart                AvatarPersona, AvatarUsuario (usa fotos.dart)
  pedir_motivo.dart           pedirMotivo, _MotivoDialog
  elegir_foto_animal.dart     elegirFotoAnimal (cámara + galería, animales)
  elegir_foto_perfil.dart     elegirFotoPerfil (solo galería, perfil/logo —
                               usa foto_normalizador.dart)
  confirmar_ciudad_resuelta.dart  confirmarCiudadResuelta (usa
                               campo_pais_telefono.dart para banderaPais)
  cambiar_estado_sheet.dart   CambiarEstadoSheet (usa pedir_motivo.dart +
                               3 repositorios — escribe al backend)
  cambiar_rol_debug.dart      mostrarCambiarRolDebug (escribe al backend)
```

Cada pantalla ahora importa exactamente lo que usa (`import
'../widgets/fotos.dart';`, `import '../domain/reglas_negocio.dart';`, etc.)
en vez de un `import '../theme.dart';` que traía todo. Las ~35 pantallas
que consumían algo de `theme.dart` se actualizaron una por una — se armó
un mapa completo de qué símbolo usa cada archivo antes de tocar nada, para
no dejar ningún import roto ni ninguno de más.

**Contenido verificado byte a byte**: antes de tocar ningún import, se
comparó el multiset de líneas de código no vacías del `theme.dart`
original contra la suma de los 19 archivos nuevos — idéntico, cero
pérdidas y cero duplicados. Los tests que vivían en `test/theme_test.dart`
se dividieron con el mismo criterio, en `test/domain/` y `test/widgets/`,
con la misma verificación de contenido.

**Por qué `fondo_decorativo.dart` junta dos cosas que en la lista de
arriba parecen no tener nada que ver**: `_hoja()` (la función del fondo)
llama directo a `_PawPrintPainter`, una clase privada — en Dart, "privado"
es privado al *archivo*, no a la clase que lo declaró, así que las dos
tienen que vivir juntas o dejar de ser privadas. Se optó por lo primero.

### `TextoSinDesborde` — texto variable en una fila, sin desbordarse

Un `Row` con un texto de largo variable (nombre de negocio, de persona, o
una ciudad que devuelve el geocoder) junto a algo de ancho fijo se
desborda apenas ese texto no entra en una línea, si el `Text` no está
envuelto en `Flexible`. Empuja a su vecino fuera de la pantalla.

Apareció tres veces, en dos formas que son la misma:

| Dónde | Forma | Estado antes |
|---|---|---|
| Encabezado del chat | nombre + puntito "en línea" | arreglado a mano |
| Panel del aliado | nombre + puntito "en línea" | **roto** (~1029px) |
| Línea de ciudad (📍 + ciudad) | ícono + texto | **4 de 6 copias rotas** |

El del panel del aliado lo encontró Eliza con "Veterinario Huellitas...".
Las copias de la línea de ciudad las encontró una auditoría: dos tenían
`Flexible`/`Expanded` y cuatro no, sin nada que lo delatara.

`TextoSinDesborde(texto:, style:, antes:, despues:)` lo resuelve por
construcción — `antes` es lo que va a la izquierda (un ícono), `despues`
lo que va a la derecha (un puntito, un candado). La protección vive en un
solo lugar en vez de depender de que alguien se acuerde de repetirla.

### Checklist para una fila nueva con texto de largo variable

1. ¿El texto lo escribe la persona o viene de un servicio (nombre,
   ciudad) y comparte la fila con otra cosa? → `TextoSinDesborde`, no un
   `Row` armado a mano.
2. ¿Es solo el texto, sin nada al lado? Un `Text` con
   `overflow: TextOverflow.ellipsis` alcanza.
3. ¿Va dentro de un `Column` que está a su vez dentro de un `Row`? Ojo:
   la `Column` toma su ancho natural y desborda igual — necesita
   `Expanded` alrededor (el caso del nombre en el perfil del adoptante).
4. ¿Va dentro de un `Column` suelto? No hace falta nada: ahí un texto
   largo se envuelve solo a la línea siguiente.

### `ChipsSeleccionables` — grilla de opciones tipo chip

Tres pantallas (`tipo_animal_screen.dart`, `subir_rescate_screen.dart`,
`editar_rescate_screen.dart`) tenían su propia copia de "opciones en chips,
tocar una las marca" — `_grupo`, `_chips`, `_selector`, cada una con su
nombre. Dos ya usaban `Wrap`; la tercera (las preferencias de tamaño/edad
del adoptante) se había quedado con un `SingleChildScrollView` horizontal
sin ninguna señal de que había más opciones fuera de vista — bug real
reportado por Eliza, y exactamente el riesgo de tener el mismo patrón
repetido: se corrige una copia y las otras se quedan atrás.

La consolidación fue deliberadamente mínima: `ChipsSeleccionables`
(`widgets/chips_seleccionables.dart`) es SOLO la grilla en sí (Wrap + chip tocable), sin opinión
sobre etiqueta ni padding exterior — cada una de las tres pantallas
conserva su propio estilo (colores, tamaños, espaciados) pasándolos como
parámetros. Los tres métodos viejos (`_grupo`/`_chips`/`_selector`) siguen
existiendo, ahora como una o dos líneas que delegan a
`ChipsSeleccionables` — así ninguno de los ~25 lugares que los llaman
(`subir_rescate_screen.dart` y `editar_rescate_screen.dart` son las dos
pantallas más grandes y más críticas de la app: publicar y editar un
animal) tuvo que tocarse. El objetivo era sacar la LÓGICA duplicada
(cómo se arma la grilla), no unificar el aspecto visual de las tres
pantallas ni arriesgar ese flujo central.

### `elegirFotoAnimal` — la hoja de "Tomar foto / Elegir de la galería"

Estaba escrita dos veces (publicar y editar un animal), y las copias
**habían divergido en el manejo de errores**:

| | Hoja | Cámara falla | Calidad |
|---|---|---|---|
| `subir_rescate_screen.dart` | propia | avisa "usa la galería" | q90 |
| `editar_rescate_screen.dart` | propia | **excepción sin atrapar** | q80 |

En un dispositivo sin cámara, con el permiso denegado, o un emulador sin
cámara configurada, tocar "Tomar foto" **al editar** lanzaba una excepción
que nadie manejaba: no pasaba nada, sin ningún aviso. Al publicar sí
avisaba. Hallazgo de auditoría de código, y exactamente el mismo patrón
que el resto de esta sección: arreglado en una copia, olvidado en la otra.

Ahora las dos usan `elegirFotoAnimal(context)` (`widgets/elegir_foto_animal.dart`), con q90 en
las dos — `normalizarFoto()` recomprime todo a q80 después igual, así que
entrar con más calidad solo evita comprimir dos veces seguidas.

Lo que el helper NO decide, a propósito: dónde guardar el archivo ni si
todavía hay lugar para otra foto — eso depende del estado propio de cada
pantalla (una lista en publicar, dos slots en editar).

### `elegirFotoPerfil` — la foto de perfil/logo (solo galería)

Mismo mecanismo que `elegirFotoAnimal`, encontrado en una auditoría
posterior en un subsistema distinto: un selector de foto de galería
(sin opción de cámara, para el perfil personal o el logo de un negocio)
estaba copiado a mano en **3 pantallas** — `aliado_perfil_screen.dart`,
`albergue_home_screen.dart`, `albergue_perfil_screen.dart` — y ya habían
divergido en dos cosas a la vez, sin que nada avisara:

| | `normalizarFoto()` | try/catch |
|---|---|---|
| `aliado_perfil_screen.dart` | sí | sí (silencioso) |
| `albergue_home_screen.dart` | **no** | sí |
| `albergue_perfil_screen.dart` | **no** | **no** |

Las dos copias sin `normalizarFoto()` guardaban la foto tal cual salía de
`picked.readAsBytes()` — sin la corrección de orientación EXIF que
`normalizarFoto()` hace al decodificar y re-codificar la imagen, así que
una foto tomada con el celular en la orientación que el sensor no espera
se guardaba rotada. `albergue_perfil_screen.dart`, además, no tenía
ningún manejo de error: un fallo al leer los bytes de la foto elegida
tiraba una excepción sin atrapar.

Ahora las tres usan `elegirFotoPerfil({maxWidth, quality})`
(`widgets/elegir_foto_perfil.dart`) — SIEMPRE pasa por `normalizarFoto()`
y devuelve `null` en vez de propagar si algo falla. Solo galería a
propósito (un logo no se "toma ahí mismo, ahora" como un rescate), así
que tampoco necesita el aviso de "cámara no disponible" de su hermano.
4 tests con una imagen real generada en memoria, verificando tamaño final
y el camino de error.

`subir_lote_screen.dart` queda afuera de este consolidado: su segunda
foto de un alta en lote normaliza en batch al momento de publicar (junto
a la primera, elegida con `pickMultiImage`) — es una decisión de diseño
distinta y consistente consigo misma, no una cuarta copia divergida.

### Fotos en Storage — las tres capas

```
editar/subir_rescate_screen.dart   ← elige archivos, normaliza
        ↓
RescatesRepository                 ← coreografía: qué subir, mover, borrar
  · publicarConFotos()               (alta, con rollback completo)
  · resolverFotosAlEditar()          (edición: la única que MUEVE y BORRA)
        ↓
RescateFotosRepository             ← primitivas sobre Storage
  · subir / moverFoto / eliminar / eliminarTodas / urlApuntaASlot
```

`RescateFotosRepository` tiene 14 tests propios (incluido que el timeout
de `subir` **cancela de verdad** la tarea, no solo deja de esperarla).

`resolverFotosAlEditar` era la asimetría de este esquema: `publicarConFotos`
ya vivía en el repositorio, pero su contraparte de edición estaba inline en
la pantalla — o sea que la única parte que **mueve y borra** archivos (no
solo sube) era la única sin tests posibles. Ahora está al lado de la otra,
con 7 tests que cubren los escenarios reales: sin cambios, foto nueva,
quitar la segunda, la promoción foto 2 → foto 1 (el bug de "rarito 2"),
promoción con una segunda foto nueva en la misma edición (que exige orden
serie, no paralelo), origen ausente, y la red de seguridad que evita
borrar un archivo todavía referenciado.

Las tres reglas que gobiernan la edición están documentadas en el método
mismo — no se ven leyendo una sola rama, y cada una nació de un bug real.

## `AuthWrapper` — efectos de sesión separados de la UI

`AuthWrapper` (`lib/main.dart`) es el widget raíz: decide qué pantalla
mostrar leyendo el estado de auth y el perfil de Firestore con dos
`StreamBuilder` anidados. Además de decidir qué mostrar, tenía que hacer
dos cosas cada vez que una cuenta entra: sincronizar la foto de perfil con
la de Google si cambió, y sellar `ultimaVezActiva`. Antes esas dos
escrituras vivían **dentro del `builder` del `StreamBuilder` del perfil** —
es decir, dentro de `build()`.

**Por qué eso era un problema, aunque funcionara:** Flutter puede volver a
llamar `build()` por motivos que no tienen nada que ver con "cambió la
sesión" — un rebuild del padre, un cambio de tema, cualquier
`InheritedWidget` del que el árbol dependa. Una escritura a Firestore
metida ahí no tiene forma de distinguir un motivo real de uno espurio; que
no causara un bucle infinito dependía enteramente de un guard hecho a mano
(`_ultimaVezActivaMarcadaParaUid`, comparado contra el uid actual, no un
`bool`, porque la app permite cambiar de cuenta sin cerrar sesión). El
guard era correcto, pero era la única barrera, y vivía en el lugar
equivocado: el método que arma la UI.

**Qué se hizo:** las dos escrituras se movieron a una suscripción propia,
armada en `initState()` y cerrada en `dispose()`, separada de los
`StreamBuilder` que arman la UI:

```
initState()
  → authStateChanges().listen(_onCambioDeSesion)

_onCambioDeSesion(user)
  → sesión cerrada: limpia el guard y cancela la suscripción del perfil
  → sesión nueva (uid distinto al ya suscripto): se suscribe al doc de
    perfil de ESA cuenta

_sincronizarEfectosDeSesion(user, snapshot del perfil)
  → sync de foto (oportunista, sin guard — es idempotente: una vez
    igualada, la condición deja de cumplirse sola)
  → sello de ultimaVezActiva (con el mismo guard de antes, ahora
    disparado solo por un snapshot real del perfil, no por cualquier
    rebuild)
```

`build()` quedó sin ninguna escritura — solo lee `snap`/`userSnap` y
decide qué pantalla devolver. Las reglas de UI ya endurecidas ahí (caché
vs. servidor al decidir "no existe todavía", el timeout de
`_CargaConSalida`, el manejo de error del stream) no se tocaron: siguen
exactamente igual, solo que ahora ese método no hace nada más que
renderizar.

### `lib/domain/resolucion_perfil.dart` — qué pantalla según el perfil

La resolución de rol (qué pantalla según `roles`, `albergueNombre`,
`aliadoNombre`) vivía inline en el `builder` de `build()` — se podía
probar solo montando todo el widget con Firebase. Ahora es
`resolverPantallaPerfil(Map<String, dynamic> perfil) → PantallaPerfil`,
una función pura sin Firestore ni Flutter: recibe el mapa del documento y
devuelve un valor del enum `PantallaPerfil`. `build()` solo llama a la
función y hace un `switch` sobre el resultado para elegir el widget —
cero lógica de negocio ahí, solo mapeo a pantallas.

Es el primer archivo de la capa `lib/domain/`: funciones puras de
negocio, sin Firestore ni Flutter, para lógica que antes vivía repartida
en `build()`s y callbacks de pantallas. `compatibilidad.dart` (puntaje y
explicación de compatibilidad adoptante/animal) se mudó acá después —
nació antes de que existiera esta carpeta, pero ya era el mismo tipo de
función pura.

El orden de desempate en doble rol (`albergue` antes que `aliado`) es el
mismo que tenía el código original — se conservó tal cual, documentado en
el propio archivo, para no cambiar comportamiento de una cuenta real por
el camino.

## Navegación — `go_router` y `lib/routing/app_router.dart`

Hasta el 2026-08-16 la navegación entre pantallas era ~62
`Navigator.push(context, MaterialPageRoute(builder: (_) => Pantalla(...)))`
repartidos en 17 archivos de `lib/screens/`. Funcionaba, pero el grafo de
qué pantalla lleva a cuál era implícito — solo se veía leyendo cada
`onTap` uno por uno, no había un lugar único donde mirarlo.

**Qué se hizo:** se agregó `go_router` y se creó `lib/routing/app_router.dart`
con:

- `AppRoutes` — una clase con una constante `static const` por ruta
  (`'/subir-rescate'`, `'/chat'`, etc.), para no repetir strings sueltos.
- Un `typedef` de record por cada pantalla que necesita más de un
  argumento simple (`ChatArgs`, `MisRescatesArgs`, `AdoptanteChatsArgs`,
  etc.) — se usan records de Dart en vez de una clase "Args" por pantalla
  porque son un contenedor tipado sin ceremonia, y ya era un idioma que
  el código usaba (`partirTelefono`).
- El propio `GoRouter(routes: [...])`, con un `GoRoute` por pantalla. Cada
  `builder` hace el *unpack* de `state.extra` al tipo del record
  correspondiente (con un valor por defecto vía `??` cuando todos los
  campos son opcionales, para no obligar a pasar `extra` en esos casos).

**Qué pantallas quedaron afuera de la tabla de rutas, a propósito:**
las que solo se usan embebidas dentro de otra (`SolicitudesPreview`,
`AdoptanteFeedScreen` dentro de `HomeScreen`) y las que son raíz exclusiva
de `AuthWrapper` (`SeleccionRolScreen`) — ninguna de las dos se alcanza
nunca con `context.push`, así que no les corresponde una ruta propia.

`main.dart` pasó de `MaterialApp(home: const AuthWrapper(), navigatorObservers: [...])`
a `MaterialApp.router(routerConfig: appRouter)`; el `FirebaseAnalyticsObserver`
que antes colgaba de `navigatorObservers` ahora cuelga de
`GoRouter(observers: [...])` — mismo tracking de pantallas, otro dueño.

Cada sitio de navegación se tradujo 1 a 1: `Navigator.push(context,
MaterialPageRoute(builder: (_) => Pantalla(args)))` → `context.push(
AppRoutes.pantalla, extra: args)`. `Navigator.pop(context, resultado)` y
`.then((_) => ...)` (para refrescar al volver) se dejaron exactamente
igual — `go_router` envuelve un `Navigator` normal por debajo, así que
ambos siguen funcionando sin cambios.

Verificado con `flutter analyze` (0 errores), la suite completa de tests
(416, sin regresiones) y navegación real en un emulador Android: se probó
en vivo con datos reales de Firestore el flujo Adoptar → Favoritos → volver,
Adoptar → Chats → abrir una conversación → volver, y en la faceta
Rescatista: Subir un rescate, Solicitudes (con Aprobar/Rechazar visibles),
Mis rescates y Editar animal (con los datos del documento precargados en
el formulario) — los cinco navegaron y volvieron sin perder el estado de
la pantalla debajo.

## Segunda pasada de auditoría de código (2026-08-16, post go_router)

Después de migrar la navegación, se repitió el mismo ejercicio de la fase 5
(sección 6) sobre todo lo agregado esta sesión: barrer el diff completo
contra las 6 reglas del hook, y buscar funciones con el mismo nombre
repetidas en más de una pantalla. Dos resultados:

**`tiempoRelativo` — encontrada y resuelta.** `solicitudes_preview.dart` y
`solicitudes_rescatista_screen.dart` tenían cada una su propia
`_tiempoRelativo(DateTime fecha)`, copiada byte a byte ("hace Xmin/h/d").
Todavía no habían divergido, pero es el mismo mecanismo que sí llegó a
causar bugs reales acá (vocabulario de estado de salud, scoring de
compatibilidad): dos copias sin dueño único, sin nada que avisara si una
cambiaba y la otra no. Se movió a `reglas_negocio.dart` como `tiempoRelativo`
(puro Dart, mismo patrón que `formatearFecha`/`whatsappUrl`), con 3 tests
nuevos en `test/domain/reglas_negocio_test.dart`, y las dos pantallas ahora
la importan en vez de tener su propia copia.

**`_verificarVencimientos`/`_verificarSeguimientoPostAdopcion` — duplicación
ya conocida, ahora documentada.** `albergue_home_screen.dart` y
`home_screen.dart` tienen cada una un wrapper privado idéntico (mismo
cuerpo, solo cambia `role`/`creadoPor` según la faceta) que llama a las
funciones compartidas del mismo nombre en `solicitudes_rescatista_screen.dart`.
Esto ya se había encontrado y decidido dejar así en una sesión anterior — el
propio código lo dice en un comentario ("duplicadas byte a byte con
[el otro archivo] — hallazgo de auditoría de código") — pero no estaba
anotado en ningún documento, así que no se podía saber que era una decisión
tomada sin leer ese comentario puntual. Queda anotado acá: es deuda
aceptada, no un olvido, porque las dos llamadas ya delegan la lógica real
a las funciones top-level compartidas — lo único repetido es el wrapper de
2 líneas que decide qué `role`/`creadoPor` pasar.

## Los `catch (_) {}` de `lib/` — auditados como conjunto

18 catches vacíos en todo `lib/`, revisados uno por uno (no solo los que
cruzaron el camino de otra tarea). Los 18 son best-effort genuino: en cada
uno, lo que falla es un dato secundario o una limpieza posterior, nunca la
acción principal que la persona pidió — y 17 de los 18 ya lo explicaban en
un comentario al lado. El único sin comentario
(`UbicacionService.desdeTexto()`, el reverse geocoding que solo alimenta el
diálogo de confirmación de ciudad) se documentó para quedar igual de
explícito que sus hermanos — mismo comportamiento, nada cambió.

Los tres patrones que se repiten:

- **Dato de respaldo con fallback ya declarado antes del `try`** (nombre a
  mostrar, distancia, región de una ciudad): si falla, se sigue con el
  valor por defecto que ya estaba puesto.
- **Limpieza secundaria que corre DESPUÉS de que la acción principal ya se
  confirmó** (borrar fotos huérfanas, actualizar un roster, apagar/prender
  la red antes de reintentar): si falla, el peor caso es un residuo, nunca
  deshace lo que la persona ya logró.
- **Rollback en un `catch` que termina en `rethrow`** (`publicarConFotos`):
  el error real siempre se propaga, la limpieza best-effort no lo
  reemplaza ni lo esconde.

Ningún catch de los 18 escondía un error que debiera mostrarse ni una falla
que debiera bloquear la acción — no hizo falta cambiar comportamiento en
ninguno.

## Hook de pre-commit

`.githooks/pre-commit` (versionado, se activa con `git config core.hooksPath
.githooks` — ya corrido en este checkout) revisa las líneas **agregadas** en
cada commit. Solo mira líneas nuevas, no el código ya existente, así que no
bloquea commits que no tocan ninguno de estos patrones — es la alarma
automática que reemplaza a "esperar que alguien lo note en code review".

Seis reglas hoy, cada una: patrón + carpeta que sí puede usarlo + el bug
real que la motivó (documentado en el propio hook):

1. **Firestore de `rescates`/`solicitudes`/`preferencias`** fuera de
   `lib/data/`.
2. **GPS y geocoding** (`Geolocator.*`, `placemarkFromCoordinates`,
   `locationFromAddress`) fuera de `UbicacionService`.
3. **Escritura de mensajes** (`collection('mensajes')`) fuera de
   `ChatsRepository`.
4. **Observador de ciclo de vida** (`didChangeAppLifecycleState`,
   `WidgetsBinding.instance.addObserver`/`removeObserver`) fuera de
   `lib/services/ubicacion_lifecycle.dart`.
5. **Selector de foto de galería** (`ImagePicker().pickImage(`, la forma
   inline) fuera de `elegir_foto_animal.dart`/`elegir_foto_perfil.dart`.
   A propósito solo bloquea esa forma exacta, no cualquier `.pickImage(`
   — así no molesta a `subir_lote_screen.dart`, que guarda su propio
   `ImagePicker` en un campo y normaliza distinto por diseño, no por
   copia.
6. **Qué pantalla mostrar según el rol** (`.contains('albergue')` /
   `.contains('aliado')`, con comillas simples o dobles) fuera de
   `lib/domain/resolucion_perfil.dart`. Agregada el 2026-08-16, más
   angosta que las otras cinco a propósito: no bloquea `roles.contains(rol)`
   ni ningún otro chequeo de rol, solo esos dos literales exactos, que hoy
   solo aparecen legítimamente en `resolverPantallaPerfil`. Verificado
   contra el código real (cero falsos positivos) y con una inyección
   sintética de prueba (bloqueó, con el mensaje correcto).

## Qué falta (a propósito, no es urgente)

- `chats` no tiene el mismo problema de `CreatorRole` porque un chat ya
  identifica a sus dos dueños (`adoptanteId`/`rescatistaId`) — no hay
  ambigüedad de "con qué sombrero" ahí. (Actualizado tras revisión: las dos
  dudas que estaban anotadas acá — el contador de mensajes sin distinguir
  la faceta rescatista/albergue, y `chat_screen.dart` leyendo `rescates`
  directo — ya no aplican. `contarMensajesSinLeer` filtra por `creadoPor`
  según la faceta, y `chat_screen.dart` usa `RescatesRepository().obtener()`.
  Quedaron sin corregir esta nota cuando se arreglaron; auditoría de
  2026-08-15.)
- Cloud Functions (`functions/`) usa el Admin SDK, que **ignora
  `firestore.rules` por completo** — no son parte de esta barrera. Confían
  en lo que sea que dispare el trigger, o (en `eliminarCuenta`) en el
  propio código de la función para acotar el alcance.
  **Corrección tras una re-auditoría (2026-08-16): la nota anterior decía
  "solo mandan notificaciones push, no exponen datos" — ya no es exacta.**
  Hoy hay tres categorías, no una:
  1. **Notificaciones push** (`onNuevoMensaje`, `onNuevaSolicitud`,
     `onCambioEstadoSolicitud`) — matchea la nota original, sin cambios.
  2. **`eliminarCuenta`** (`onCall`) — lee/escribe/borra en `rescates`,
     `solicitudes`, `chats`, `favoritos`, `servicios`, `hogaresDePaso`,
     `usuarios`, `preferencias` con privilegios de Admin SDK. No es un
     agujero: el código mismo nunca acepta un uid por parámetro, siempre
     usa `request.auth.uid` (comentario explícito en el archivo: "nunca
     un uid que venga de `request.data`"), así que el alcance queda
     acotado por construcción a la propia cuenta que llama. Pero ya no es
     "solo notificaciones push".
  3. **`landingAnimales`** (`onRequest`, sin auth) — expone A PROPÓSITO
     una lista pública de animales disponibles (nombre, especie, edad,
     ubicación, foto) para la landing de GitHub Pages. Es una decisión de
     producto, no un descuido — pero sí es "exponer datos", así que la
     nota original tampoco era exacta acá.
- ~~Node.js 20 (Cloud Functions) queda fuera de servicio el 30 de octubre
  de 2026~~ — **hecho (2026-08-16):** `functions/package.json` actualizado
  a Node 22 (LTS vigente, confirmado soportado por Cloud Functions 2nd
  gen), `firebase-admin` 12→14, `firebase-functions` 5→7. Revisados los
  breaking changes documentados de las dos librerías contra el código real
  (ninguno aplica: sin uso de `functions.config()`, sin namespace legado,
  sin tipos de messaging deprecados — todo el código ya usaba imports
  modulares de v2). `npm test` (12 tests de `eliminar_cuenta_logica.js`)
  y una carga real de `index.js` con las versiones nuevas, los dos limpios.
  **Sin deployar a propósito** — el código está listo, `firebase deploy
  --only functions` queda pendiente de que Eliza decida cuándo publicarlo.
- `_verificarVencimientos`/`_verificarSeguimientoPostAdopcion` — wrappers
  privados duplicados entre `albergue_home_screen.dart` y
  `home_screen.dart` (mismo cuerpo, solo cambia `role`/`creadoPor`). Deuda
  aceptada, no un olvido — ver el detalle completo en "Segunda pasada de
  auditoría de código" más abajo.
