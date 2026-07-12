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

---

**Si todo lo de arriba pasa:** A1 queda cerrado del todo, listo para
generar el `.aab` final y subirlo a producción cuando quieras.

**Si algo falla:** contame el paso exacto y el mensaje/comportamiento —
no hace falta que lo arregles vos, solo que me digas qué pasó.
