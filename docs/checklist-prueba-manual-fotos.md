# Checklist de prueba manual — migración de fotos a Storage

Instalá el APK en tu celular y probá esto en orden. Marcá cada uno.
Si algo falla, anotá en qué paso fue y qué mensaje/comportamiento viste.



## A. Publicar un rescate (rescatista)

- [ ] Publicar un animal nuevo con **1 sola foto** → se publica sin error,
      la foto se ve en la pantalla de éxito.
- [ ] Publicar otro animal con **2 fotos** → se publica sin error.
- [ ] Mientras se publica, fijate si ves el porcentaje de subida
      (debería aparecer un "X%" al lado del spinner, no solo un spinner ciego).
- [ ] El animal recién publicado aparece en el feed del adoptante con su foto.
- [ ] El animal recién publicado aparece en "Mis rescates" con su foto.

## B. Publicar en lote (si sos albergue)

- [ ] Subir un lote de 2-3 animales de una — todos quedan publicados con
      su foto.
- [ ] Mientras se publica, ves "Publicando X de N..." (no un spinner ciego).

## C. Editar un rescate

- [ ] Abrir un animal ya publicado (con 2 fotos) y **reemplazar** la
      primera foto por otra → guarda bien, la foto nueva se ve en el feed.
- [ ] En el mismo animal, **quitar** la segunda foto sin reemplazarla →
      guarda bien, ahora se ve solo con 1 foto en todos lados.
- [ ] Eliminar un animal publicado → desaparece del feed y de "Mis rescates".

## D. Ver el animal (adoptante)

- [ ] Abrir el detalle de un animal con 2 fotos → el carrusel swipea entre
      las dos.
- [ ] Guardarlo en Favoritos → aparece ahí con su foto.
- [ ] Compartir el animal (botón compartir) → se genera la tarjeta con la
      foto (no solo texto).

## E. Solicitud de adopción

- [ ] Mandar una solicitud de adopción sobre un animal → la foto se ve en
      el paso "antes de continuar" de la solicitud.
- [ ] Como rescatista, ver esa solicitud en la lista → la foto del animal
      se ve en la tarjeta de la solicitud.
- [ ] Aprobar la solicitud → sin error.
- [ ] Rechazar otra solicitud → sin error.

## F. Chat

- [ ] Abrir el chat sobre un animal (desde la solicitud aprobada, o desde
      "hacer una pregunta" en el feed) → la foto del animal se ve en el
      header del chat.
- [ ] Mandar un mensaje → llega bien, sin duplicados.
- [ ] **Importante:** abrir un chat de **consulta a un negocio aliado**
      (no relacionado a ningún animal — desde la pantalla de un aliado,
      botón "Contactar") → el logo del aliado se sigue viendo bien ahí.
      Este es el caso que más riesgo tenía de romperse con el cambio de hoy.
- [ ] En la lista de conversaciones, tanto los chats de animales como los
      de aliados muestran su foto/logo correctamente (no mezclados ni en
      blanco).

## G. Caso límite

- [ ] Si podés, probá publicar un animal **sin conexión** o con el wifi
      cortado a mitad de subida — la app debería avisar el error, no
      quedar colgada ni crashear.

## H. Arreglos del 11 de julio (re-verificar en V13)

- [ ] Publicar **sin GPS activado** → sale el diálogo "Sin ubicación
      detectada". "Publicar sin ubicación" publica igual; "Volver y
      detectar de nuevo" vuelve al formulario y arranca solo el
      "Detectando ubicación...".
- [ ] Con el permiso de ubicación **bloqueado**, tocar el campo de
      ubicación → el aviso trae el botón "Abrir Ajustes" y te lleva
      directo a los permisos de la app.
- [ ] En el panel de rescatista sin ciudad detectada → NO se ve el pin
      de ubicación suelto.
- [ ] Quitar el corazón de un favorito → se quita **sin preguntar** y el
      animal **reaparece en el carrusel** principal.
- [ ] Tocar el corazón en el carrusel → la tarjeta se oculta al instante,
      sin parpadear.
- [ ] Las descripciones de los animales se ven **sin comillas** alrededor
      (tarjeta del feed, detalle "Mi historia" y motivación del adoptante).

## I. Arreglos del 12 de julio (re-verificar en la próxima versión)

- [ ] En "Mis rescates" y en el perfil de adoptante, sin ciudad detectada
      → NO se ve el pin de ubicación suelto (mismo arreglo de la sección H,
      encontrado en 2 pantallas más).
- [ ] Editar un animalito del albergue → el campo "Ubicación" aparece
      **una sola vez** (antes salía duplicado).
- [ ] Rescatista: en una solicitud de **hogar de paso** aprobada, tocar
      "Ir al chat" → abre el chat (antes no hacía nada).
- [ ] Rescatista: en un animal "En proceso de adopción", tocar "Contactar
      adoptante" → abre el chat (antes no hacía nada).
- [ ] En cualquier chat, el encabezado muestra a la **otra persona** (no a
      vos mismo) — y si el animal es de un albergue, dice "Albergue" en
      vez de "Rescatista".
- [ ] Adoptante: tocar "Hacer una pregunta" sobre un animal publicado por
      un **albergue** → abre el chat sin error (bug de datos real,
      encontrado y corregido en las reglas de Firestore).

## J. Arreglos del 13 de julio (re-verificar en V15)

### Chats
- [ ] Abrir un chat de animal → el encabezado muestra la **foto real** de
      la otra persona (si tiene foto de Google), no solo una inicial.
- [ ] Contactar a un aliado como **Rescatista** y después al **mismo
      aliado** como **Albergue** → son **dos conversaciones separadas**,
      no se mezclan los mensajes.
- [ ] Tu pestaña de Chats (como rescatista o como albergue) solo muestra
      las conversaciones con aliados que vos mandaste con ESE rol — no ve
      las que mandaste como adoptante, ni al revés.
- [ ] Contactar a un aliado que todavía no subió su logo → el avatar
      muestra la **inicial del negocio**, no un emoji de perro/gato.
- [ ] En la lista de Conversaciones, el círculo chico de cada fila
      (esquina inferior) muestra la foto real de la contraparte, no solo
      una letra.
- [ ] No aparecen conversaciones duplicadas en la lista.

### Solicitudes
- [ ] Panel del **albergue**: la sección "Solicitudes" muestra las
      últimas 3 pendientes con el detalle del adoptante y el score de
      compatibilidad — igual que el panel del rescatista (antes solo
      tenía un contador).
- [ ] El avatar de cada tarjeta de solicitud muestra la foto real del
      adoptante, no la tuya.
- [ ] Mandar una solicitud desde **"Me interesa ayudar"** (botón del
      feed) → el panel de compatibilidad muestra el tamaño/energía real
      del animal, no los valores por defecto ("Mediano", etc.).
- [ ] Mandar una solicitud desde el botón **"Adoptar" en Favoritos** →
      mismo chequeo que arriba.
- [ ] Intentar **eliminar** un animal con una solicitud pendiente → la
      app lo bloquea con un mensaje claro en vez de dejarte borrarlo.

### Estados del animal
- [ ] Marcar un animal **"Regresado"** y después aprobar una solicitud
      nueva para ese mismo animal → se aprueba bien (antes quedaba
      atascado, autorrechazándose para siempre).
- [ ] En "Ya encontraron hogar" del albergue, los animales adoptados
      tienen el mismo desplegable para cambiar estado que los activos
      (antes tenían un ícono fijo, sin poder marcarlos "Regresado").

### Publicar un rescate
- [ ] Publicar un animal con conexión normal → sigue funcionando igual
      que siempre.
- [ ] Publicar **sin conexión** (modo avión) → después de unos segundos
      aparece un mensaje de error claro; la app **no queda colgada**.
- [ ] Lo mismo con **"Subir lote"**.

### Negocios aliados
- [ ] Los aliados que ya subieron su logo lo muestran correctamente en
      "Negocios aliados", tanto para el rescatista/albergue como para el
      adoptante.

## K. Arreglos del 20 de julio (re-verificar en V33 — todo lo hecho después del AAB #2)

### Fotos
- [ ] Rescatista: en "Mis rescates", el botón Compartir aparece incluso en
      un animal **sin foto todavía** (antes no aparecía).
- [ ] Rescatista: las fotos propias en el panel principal y en "Mis
      rescates" se ven **completas**, no recortadas (antes un retrato
      vertical podía verse como un fondo vacío).
- [ ] Mandar una solicitud de adopción sobre un animal con foto en formato
      retrato (el animal en la mitad inferior de la foto) → en el paso
      "Antes de continuar" se ve el animal **completo**, no un bloque de
      color sólido.
- [ ] Mismo caso en la grilla de animales del **perfil público de un
      albergue** (lo que ve el adoptante al entrar a un albergue).
- [ ] En el feed, rechazar varios animales seguidos con la X → la próxima
      foto aparece **sin demora** (se precarga mientras mirás la anterior).

### Salud del animal (vacunado / desparasitado)
- [ ] Publicar un animal nuevo → aparecen las preguntas "¿Está vacunado?"
      y "¿Está desparasitado?" (Sí / No / Aún no lo sé).
- [ ] Editar un animal y cambiar esas respuestas → se guardan bien.
- [ ] Como adoptante, ver el detalle de un animal marcado "Sí" en ambas →
      la sección SALUD dice **"Sí"**, no "Aún no lo sé" (bug real:
      el feed principal no traía estos dos campos, mostraba el default
      aunque el dato real fuera otro).

### Vivienda / compatibilidad
- [ ] Al mandar una solicitud, la vivienda tiene las opciones **"Casa sin
      jardín"** y **"Finca"** además de las de antes.
- [ ] Un animal grande con adoptante en "Casa sin jardín" o "Finca" da un
      puntaje de compatibilidad razonable (no lo trata como "sin
      experiencia").

### Compartir y "Mis rescates"
- [ ] Un animal marcado **"Adoptado"**: ya NO se ven los botones
      Compartir ni Eliminar (queda como registro permanente).
- [ ] El ícono de Compartir es el **mismo** en "Mis rescates" y en el feed
      del adoptante (solo ícono, sin la palabra "Compartir" en ningún
      lado — antes un lado tenía texto y el otro no).
- [ ] El mensaje de WhatsApp al compartir un animal incluye el **link
      directo a Play Store**.

### Hogar de paso / "Contactar"
- [ ] Rescatista: aprobar una solicitud de **"Hogar de paso"** → en "Mis
      rescates" aparece un botón naranja **"Contactar"** al lado del
      estado (antes no existía ahí para nada).
- [ ] Mismo botón "Contactar" aparece en el panel principal (antes solo
      aparecía para "En proceso de adopción", nunca para "Hogar de paso").
- [ ] Albergue: mismo botón "Contactar" en su propio panel (antes no
      existía tampoco).
- [ ] Tocar "Contactar" abre el chat con la persona correcta, con el
      mensaje automático de aprobación ya ahí.

### Filtro de especie (feed del adoptante)
- [ ] Arriba del feed aparecen los chips **Todos / 🐕 Perros / 🐈 Gatos /
      🐾 Otros** — tocar uno filtra al instante, sin ir al perfil.
- [ ] Perfil → "Tipo de animal preferido": el chip de especie se ve
      **igual** (mismo ícono, mismo color, mismo orden) que en el feed —
      es la misma preferencia, cambiarla en un lado se refleja en el otro.
- [ ] Filtrar por una especie sin animales disponibles (ej. "Otros") y
      llegar a "Eso es todo por hoy" → los chips **siguen visibles ahí**,
      podés cambiar de filtro sin ir al perfil (antes quedaba sin salida).
- [ ] Cambiar de filtro (ej. de Perros a Gatos) no salta directo a "Eso es
      todo por hoy" si el nuevo filtro sí tiene animales.
- [ ] La pantalla de "Eso es todo por hoy" ya no repite un título de más
      ("Cerca de ti") — se ve más limpia.

### Negocios aliados
- [ ] En "Negocios aliados", cada tarjeta muestra un **ícono de color**
      según su tipo (veterinaria, tienda de mascotas, spa canino,
      peluquería canina, otro) en vez de solo texto gris.
- [ ] Mismo ícono (en blanco) en el encabezado del perfil público del
      aliado.

### Sesión / perfil
- [ ] Si tu tía (o cualquier cuenta) tarda mucho sin abrir la app y vuelve
      a entrar para elegir rol → no debería trabarse con "no se pudo crear
      tu perfil" (reintenta sola con un token nuevo).

## L. Arreglos del 20 de julio, parte 2 (re-verificar en V34)

- [ ] En el feed, un animal con "Hogar de paso" y una ciudad de nombre
      largo (ej. "Schiffdorf") → el pin de ubicación y la insignia "Hogar
      de paso" ya NO se superponen.
- [ ] Al compartir un animal, la insignia "¡Necesito un hogar! 💚" aparece
      arriba a la derecha (en espejo con "Salva Patitas"), no abajo
      tapando al animal.
- [ ] Pantalla de elegir rol al entrar por primera vez, con letra grande
      activada (Ajustes → Accesibilidad → Tamaño de fuente) → las 4
      tarjetas se pueden deslizar y el botón "Continuar" queda **siempre
      visible** debajo (bug real reportado por una tester con Samsung Z
      Flip 3: el botón no se veía).

## M. Mejoras para albergues del 22 de julio (comparado con software real de shelters)

### Animales "estancados" (Mis rescates / Mis animales — rescatista y albergue)

- [ ] Un animal en estado "Rescatado" u "Hogar de paso" con 30+ días desde
      que se publicó → aparece un aviso naranja "Lleva N días esperando un
      hogar" en su tarjeta.
- [ ] Ese mismo animal con 60+ días → el aviso cambia a rojo.
- [ ] Un animal "En proceso de adopción", "Adoptado", "Regresado" o
      "Fallecido", aunque tenga muchos días → NO muestra el aviso (ya no
      está esperando, o el reloj no aplica).
- [ ] Tocar "Compartir en redes" dentro del aviso → abre el mismo flujo de
      compartir de siempre (no un botón roto ni duplicado).
- [ ] El aviso aparece igual tanto en "Mis rescates" (rescatista) como en
      "Mis animales" (albergue) — es la misma pantalla para los dos roles.

### Aviso de capacidad (panel principal del albergue)

- [ ] Con la ocupación por debajo del 90% → la tarjeta principal no
      muestra ningún aviso de capacidad (solo la barra normal).
- [ ] Con la ocupación en 90% o más (pero sin llegar al 100%) → aparece un
      aviso "Cerca del límite de capacidad — considerá acelerar
      adopciones."
- [ ] Con la ocupación en 100% o más → el aviso cambia a "Llegaste al
      límite de capacidad — considerá frenar nuevos ingresos."
- [ ] Un albergue sin "Capacidad total" configurada en su perfil → no
      muestra ni la barra ni el aviso (como ya era antes).

### Recordatorio post-adopción (chat automático)

- [ ] Un animal marcado "Adoptado" hace 7+ días (y todavía no se le mandó
      el aviso) → al abrir la app como rescatista/albergue, le llega al
      adoptante un mensaje de chat tipo "¿Cómo le va a [nombre] en su
      nuevo hogar? 🏡💚".
- [ ] Ese mismo animal, abriendo la app de nuevo al día siguiente → NO
      llega un segundo mensaje igual (el aviso de 7 días no se repite).
- [ ] Un animal "Adoptado" hace 30+ días → llega el mensaje más largo
      ("Ya pasó un mes... 🎉"), tanto si ya se mandó el de 7 días como si
      la app se abrió por primera vez después de los 30 días directo (no
      deberían llegar los dos mensajes, solo el de 30).
- [ ] Aplica igual para animales adoptados publicados por un rescatista y
      por un albergue (cada uno revisa los suyos al abrir su panel).

## N. Colores de mensajes y datos de contacto (previo al 22 de julio, sin build todavía)

### Colores de mensajes (toda la app)
- [ ] Un error real se ve con fondo **rojo**.
- [ ] Una advertencia (acción principal ok, algo secundario falló) se ve
      con fondo **naranja**.
- [ ] Un éxito completo se ve con fondo **verde**.
- [ ] Ningún mensaje de ERROR/ADVERTENCIA/ÉXITO queda con el fondo negro por defecto de antes. (Los de puro progreso tipo "Eliminando…" se dejan neutros a propósito.)

### Datos de contacto (albergue y aliado)
- [ ] Perfil de albergue y de aliado: se pueden cargar Teléfono/WhatsApp,
      Dirección, Email y Página web (los 4 opcionales).
- [ ] El perfil público de cada uno muestra esos datos en una sección
      "Contacto", con botón de WhatsApp directo a wa.me.

## O. Arreglos del 22 de julio, parte 2 (umbral, red de hogares de paso, compromiso de adopción)

### Umbral de "estancado" y filtro
- [ ] En tu perfil (rescatista o albergue) podés elegir "Aviso de animal
      sin adoptar" entre 6 valores (15 días a 1 año y más), y el aviso de
      la tarjeta respeta el valor elegido.
- [ ] Nuevo chip "Estancados" en los filtros de "Mis rescates"/"Mis
      animales" muestra solo esos animales.
- [ ] En "Mis animales" (albergue), ya no hay dos chips "Todos"
      duplicados en los filtros de especie.

### Aviso al rescatista/albergue de hogar de paso vencido
- [ ] Además del mensaje automático al adoptante, al abrir tu panel
      ahora te aparece también un aviso a vos, confirmando a quién se le
      avisó.

### Red de hogares de paso (solo albergue)
- [ ] Tarjeta nueva "Red de hogares de paso" en el panel del albergue.
- [ ] Aprobar una solicitud de hogar de paso agrega sola a esa persona a
      la red; aprobar otra de la misma persona suma en la misma fila (no
      duplica).
- [ ] Se puede agregar a mano a alguien de confianza (nombre, teléfono y
      notas opcionales), sumar una ayuda manual ("+1") y quitar a
      alguien de la red.

### Compromiso / registro del acuerdo de adopción
- [ ] Adoptante con una solicitud de adopción (no hogar de paso) ya
      aprobada → botón "Ver compromiso de adopción" con el texto del
      compromiso y un botón "Acepto estos compromisos".
- [ ] Al aceptar, cambia a "✅ Compromiso de adopción aceptado el
      [fecha]".
- [ ] El rescatista/albergue ve la misma constancia, en solo lectura, en
      su pantalla de Solicitudes.

## P. Arreglos y mejoras del 22-24 de julio (V33 a V36)

### Guión en mensajes
- [ ] Ningún mensaje ni diálogo de la app usa un guión largo "—" (se
      reemplazaron todos por puntos o comas).

### Colisión de datos albergue/aliado
- [ ] Una cuenta con rol de albergue Y de aliado a la vez: el contacto
      (teléfono/dirección/email/web) de uno ya NO aparece en el otro
      (bug real: compartían el mismo nombre de campo en Firestore).
- [ ] Mismo tipo de bug, corregido aparte: en "Red de hogares de paso",
      la foto de una persona ya no muestra el logo del albergue.

### Aviso de capacidad — lugares libres
- [ ] Con capacidad chica (ej. 3 lugares) y 1 lugar libre o menos, el
      aviso de capacidad aparece aunque el % ocupado no llegue al 90
      (antes solo miraba el porcentaje, no tenía sentido en albergues
      chicos).

### "En cuidado" — Regresado y Hogar de paso
- [ ] Un animal "Regresado" cuenta como "en cuidado" (ocupa capacidad,
      volvió físicamente).
- [ ] Un animal en "Hogar de paso" YA NO cuenta como "en cuidado" (está
      en la casa de otra persona, libera ese lugar). El número de la
      tarjeta "En cuidado" y la lista al tocarla siempre coinciden.

### Hogar de paso — fechas y aviso previo
- [ ] En "Mis rescates"/"Mis animales", un animal en "Hogar de paso"
      muestra la fecha de inicio → fin y los días restantes en su
      tarjeta.
- [ ] Un día antes de que venza el hogar de paso, avisa a adoptante,
      rescatista y albergue (antes solo avisaba cuando ya había vencido).

### Ver ficha desde "Mis solicitudes"
- [ ] Tocar la foto de cualquier solicitud abre la ficha completa del
      animal (antes no se podía ver desde ahí).

### Red de hogares de paso
- [ ] Ícono nuevo de la tarjeta: 🫶.
- [ ] Se puede agregar a mano a alguien con nombre, teléfono, notas y
      **email** (nuevo, opcional).
- [ ] Si le cargaste el email a alguien agregado a mano, y esa persona
      ayuda de verdad por la app con ese mismo email, se fusiona sola en
      la misma fila (no duplica).
- [ ] Ya no existe el botón "+" para sumar ayuda manual (se sacó, no
      tenía uso claro); la suma automática al aprobar una solicitud de
      hogar de paso sigue funcionando igual.

### Compromiso de adopción
- [ ] El texto del compromiso ya NO incluye la línea de esterilización
      (no hay un campo real que confirme si el animal está esterilizado,
      así que no correspondía prometerlo).

---

**Si todo lo de arriba pasa:** A1 queda cerrado del todo, listo para
generar el `.aab` final y subirlo a producción cuando quieras.

**Si algo falla:** contame el paso exacto y el mensaje/comportamiento —
no hace falta que lo arregles vos, solo que me digas qué pasó.
