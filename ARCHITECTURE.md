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
`lib/data/`. Widget de lectura: `FotoUrl` en `lib/theme.dart` (análogo a
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

### Checklist para agregar una pantalla nueva que toque estas colecciones

1. ¿Existe ya el método que necesitás en `lib/data/`? Si no, agregalo ahí,
   no en la pantalla.
2. ¿El método que devuelve "mis cosas" pide `CreatorRole` si la colección es
   `rescates` o `solicitudes`? Si no lo pide, probablemente hay un bug de
   esta misma familia esperando a pasar.
3. ¿Escribiste una regla en `firestore.rules` para la colección si es nueva?
4. ¿Agregaste un test en `test/data/` para el método nuevo? (Con
   `fake_cloud_firestore` — no hace falta tocar Firebase real.)

## Hook de pre-commit

`.githooks/pre-commit` (versionado, se activa con `git config core.hooksPath
.githooks` — ya corrido en este checkout) revisa las líneas **agregadas** en
cada commit y bloquea si alguna llama
`FirebaseFirestore.instance.collection('rescates'|'solicitudes'|'preferencias')`
fuera de `lib/data/`. Solo mira líneas nuevas, no el código ya existente, así
que no bloquea commits que no tocan ese patrón. Es la alarma automática que
reemplaza a "esperar que alguien lo note en code review".

## Qué falta (a propósito, no es urgente)

- `chats` no tiene el mismo problema de `CreatorRole` porque un chat ya
  identifica a sus dos dueños (`adoptanteId`/`rescatistaId`) — no hay
  ambigüedad de "con qué sombrero" ahí. Sí hay un bug menor de UI (el
  contador de mensajes no distingue entre chats de la faceta rescatista vs
  albergue de una cuenta dual-rol) — cosmético, no de seguridad. `chat_screen.dart`
  todavía lee `rescates` directo (2 lecturas, para mostrar el estado del
  animal en el header) — no está migrado a `RescatesRepository` todavía, y el
  hook de pre-commit no lo bloquea porque esas líneas ya existían antes del hook.
- Cloud Functions (`functions/index.js`) usa el Admin SDK, que **ignora
  `firestore.rules` por completo** — no son parte de esta barrera. Confían
  en lo que sea que dispare el trigger. No es un problema hoy porque solo
  mandan notificaciones push, no exponen datos, pero vale la pena tenerlo
  presente si se les agrega más lógica.
