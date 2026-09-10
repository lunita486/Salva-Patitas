# Dónde quedamos

Última actualización: **10 de septiembre de 2026**

Este archivo existe porque Eliza empieza una Weiterbildung de KI Managerin el
martes 15 de septiembre, de 9 a 17, hasta diciembre. La idea es que pueda
volver acá dentro de tres semanas sin tener que acordarse de nada.

---

## Lo primero: la app está publicada y funcionando

**Salva Patitas salió a Google Play el 4 de septiembre de 2026.**

| | |
|---|---|
| Versión | `1.1.10` (versionCode **110**) |
| Paquete | `com.salvapatitas.app` |
| Link público | https://play.google.com/store/apps/details?id=com.salvapatitas.app |
| Países | 14 (13 de Latinoamérica y España + Alemania, más Suiza agregada después) |
| Plataforma | Solo Android |

**No hace falta tocar nada para que siga viva.** El backend corre solo, tiene
techo de gasto y alarma de facturación. Si pasan semanas sin que nadie entre
al proyecto, cuando se vuelva está todo igual.

---

## Estado del repositorio

- Rama: **`fix/copias-y-duplicacion`**
- Último commit: **`720fc43`** — *chore: limitar instancias globales de Firebase Functions*
- Árbol limpio, **todo subido a GitHub** (0 commits pendientes)
- Repo remoto: https://github.com/lunita486/Salva-Patitas

**El código de la app está congelado en `dbbeda1` (`build: APK110`)**, que es
exactamente lo que Google tiene publicado. Todo lo que cambió después vive
solo en `functions/`: los seis scripts de limpieza y el `maxInstances`.

Se comprueba con:

```bash
git diff --name-only dbbeda1..HEAD
```

Si eso devuelve algo dentro de `lib/`, quiere decir que la app en el teléfono
de la gente ya no coincide con el código de acá.

**La rama nunca se mergeó a main y no hay PR abierto.** No es urgente, pero
está anotado.

---

## Estado de producción

### Firestore

Al 10 de septiembre:

- **3 animalitos** publicados (Colo, Nina, y uno sin nombre — todos perros, Córdoba)
- **1 usuario**: la cuenta de Eliza (`lunita486@gmail.com`)
- `_eventosProcesados`: bitácora interna de los triggers, se limpia sola

Toda la base de prueba se borró antes de publicar. Hay un volcado completo de
cómo estaba antes en `~/Desktop/backup-firestore-2026-09-04/`.

### Storage

**Vacío.** Ni una foto vieja. Las fotos de los 3 animalitos nuevos sí están,
en `rescates/{id}/`.

### Cloud Functions

Las 10 desplegadas y en estado `ACTIVE`, todas con `maxInstances: 10`:

| Función | Tipo | Región |
|---|---|---|
| `eliminarCuenta` | HTTP callable | europe-west1 |
| `landingAnimales` | HTTP público | us-central1 |
| `avisarVencimientosHogarDePaso` | diaria 09:00 | europe-west1 |
| `onRescateActualizado` | trigger | europe-west1 |
| `onPerfilActualizado` | trigger | europe-west1 |
| `onRescateContado` | trigger | europe-west1 |
| `onNuevoMensaje` | trigger | europe-west1 |
| `onNuevaSolicitud` | trigger | europe-west1 |
| `onCambioEstadoSolicitud` | trigger | europe-west1 |
| `onRescateEliminado` | trigger | europe-west1 |

Para volver a desplegarlas: `firebase deploy --only functions`

---

## Google Cloud y facturación

- Cuenta de facturación **convertida a de pago** el 4 de septiembre (el trial vencía)
- Gasto real hasta ahora: **€0.00** (la cuota gratis lo cubre entero)
- Presupuesto **"Salva Patitas"** con alarmas a **€1, €3 y €5**, actual y proyectado
- Cubre los dos proyectos que facturan: `patitas-dd0bb` y `My First Project`

**Si alguna vez llega un mail de alarma de presupuesto, hay que mirarlo.** Con
este volumen el gasto debería ser cero, así que un aviso significa que algo
raro está pasando.

Hay un tercer proyecto, **"Default Gemini Project"**, que Google creó solo al
entrar a AI Studio. No tiene facturación conectada y no puede generar cobros.
Ignorar.

---

## ⏰ Pendiente CON FECHA

### Android developer verification — antes del 30 de septiembre de 2026

En el Play Console apareció un aviso pidiendo registrar las apps para la
verificación de desarrollador de Android. El cartel grande dice que ya está
hecho (*"All of your apps have been successfully registered"*), pero conviene
entrar una vez a **Android developer verification** y confirmar que figura
`com.salvapatitas.app`.

Es lo único de toda la lista que tiene fecha límite.

---

## Pendientes sin fecha, por orden

### 1. Publicar más animalitos ⭐

Hay 3. Con el feed casi vacío, quien instala no ve gran cosa. Es lo que más
mueve la aguja y no requiere tocar código.

Uno de los tres **no tiene nombre**: en la app se muestra como "Sin nombre".
Se arregla editándolo desde la app.

### 2. Probar que llegue una notificación push

Nunca se confirmó en un teléfono real. El token sí se guarda (se vio
`fcmToken` en el perfil de Eliza), así que falta solo la otra mitad: que
alguien escriba en un chat y ver si llega el aviso.

### 3. Exigir App Check

Está activado en la app pero **no exigido** en Firebase. Exigirlo cierra la
puerta a que alguien hable con la base sin pasar por la app.

**Antes de exigirlo:** mirar las métricas de App Check unos días y confirmar
que el porcentaje de pedidos verificados es alto. Exigirlo a ciegas dejaría
afuera a todos los usuarios reales, sin aviso.

La firma SHA-1 ya está confirmada: Eliza instaló desde Play y entró con
Google el 9 de septiembre, así que la clave de Play App Signing está bien
registrada en Firebase.

### 4. Caché en `landingAnimales`

Esa función hace **60 lecturas de Firestore por cada visita** a la landing.
Hoy no importa porque hay 3 animalitos, pero cuando haya 60 o más conviene
guardar el resultado en memoria unos minutos.

Es el único lugar con exposición de costo que `maxInstances` no acota del
todo.

### 5. Miniaturas en el feed

Cuando haya cientos de animalitos, el feed va a bajar fotos grandes. No
molesta con pocos.

### 6. Deuda menor, anotada

- Los 100 issues de `flutter analyze` (ninguno bloquea, son avisos)
- Campo muerto `rescatistaFotoUrl`, escrito en `subir_rescate_screen.dart:457`
  y propagado en `propagar_copias_logica.js:126`
- `registrarAyuda` no absorbe filas manuales hacia atrás
- Las cuentas que cambian de rol pierden de vista sus chats viejos
- Las ~30 cuentas de Firebase Auth de los testers nunca se borraron (no
  tienen datos en la app, solo el registro)

---

## Si algo se rompe

**Mirar Crashlytics primero.** Está activo en release, así que los errores de
teléfonos reales aparecen ahí antes de que alguien los reporte.

**Logs de las funciones:** `firebase functions:log`

**Estado de las funciones:** `firebase functions:list`

**Antes de dar por terminado cualquier cambio** (está también en `CLAUDE.md`):

- `flutter analyze` sin errores nuevos
- Si se tocó `lib/data/`, agregar o actualizar su test en `test/data/`
- Si se tocó `firestore.rules`, agregar el caso NEGATIVO en `test_rules/`
- No generar APK/AAB salvo que se pida explícitamente

---

## Cosas que costaron entender, para no repetirlas

**El buscador de Play no es lo mismo que estar publicada.** La app estuvo
publicada cinco días sin aparecer al buscar "Salva Patitas". El índice tarda
una o dos semanas y va por país. **Siempre compartir el link, nunca decir
"buscala en Play".**

**Los testers no ven producción.** Play siempre sirve el canal de prueba más
prioritario en el que uno esté anotado (interna > cerrada > abierta >
producción). Por eso ningún teléfono de la familia mostraba la versión real,
y parecía que no estaba publicada. **Para comprobar si algo está vivo, hay que
preguntarle a alguien que nunca fue tester, o mirar el Play Console.**

**La cuenta de un albergue no se puede crear desde afuera.** Va atada a su
cuenta de Google. Lo que sí se puede es acompañarlo por videollamada con
pantalla compartida y dictarle cada paso.

---

## Enlaces

| Qué | Dónde |
|---|---|
| Ficha pública | https://play.google.com/store/apps/details?id=com.salvapatitas.app |
| Play Console | https://play.google.com/console |
| Firebase | https://console.firebase.google.com/project/patitas-dd0bb |
| Facturación | https://console.cloud.google.com/billing |
| Repo | https://github.com/lunita486/Salva-Patitas |
| Landing | https://lunita486.github.io/Salva-Patitas/ |
| Instagram | https://www.instagram.com/salvapatitas.rescue/ |

Documentación del proyecto: [`CLAUDE.md`](CLAUDE.md) y
[`ARCHITECTURE.md`](ARCHITECTURE.md).

---

## Contactos abiertos al 10 de septiembre

- **Héctor Rodríguez** — Fundación Damas Colombia (Medellín). Respondió que sí,
  quedó pendiente coordinar una videollamada para armarle el perfil de albergue
  y subirle los animalitos.
- **Viviana** — contacto que pasó Daniel. Invitó a conocer el albergue; se le
  va a proponer hacerlo por videollamada.

---

## Un ritmo realista mientras dure el curso

No hace falta más que esto:

- **Un rato entre semana**, de noche: contestar mensajes
- **Una o dos horas el fin de semana**: subir animalitos, escribirle a un
  albergue nuevo

Un albergue nuevo por semana son cincuenta en un año. La app no se muere por
ir despacio; se muere cuando nadie la atiende nunca.
