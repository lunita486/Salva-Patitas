# Pruebas manuales — APK90

Reemplaza a `checklist-prueba-manual-fotos.md` (402 líneas, secciones A a P,
del 11 al 24 de julio) y a `pruebas-v33.md` (V37). Todo eso ya se probó y
salió en builds anteriores; si alguna vez hace falta, sigue en el historial
de git. Acá va solo lo que cambió en APK90 y todavía no probaste.

---

## 1. Tus reportes

Esto es lo que reportaste vos, con tus palabras. Es la lista que importa:
si alguno sigue fallando, el arreglo no sirvió.

### Ya deberían estar (confirmar que siguen bien)

- [ ] "cambio la foto y la descripcion, voy a mis rescates como rescatista
      y sigo viendo la foto vieja y el nombre viejo"
- [ ] "en la pantalla del rescatista en mis solicitudes la imagen se
      actualizo pero el nombre es el mismo"
- [ ] "el albergue está en Santiago de los Caballeros pero el feed muestra
      Córdoba"
- [ ] "el mismo Pacolin tambien se muestra mal en los favoritos, dice
      Cordoba"
- [ ] "el nombre del albergue no se ve bien en feed, favoritos y
      solicitudes"
- [ ] "capacidad 0 permitida, dirección de 100 caracteres no activa
      Guardar"
- [ ] "los servicios de los aliados, el precio debe ser mayor a 0"
- [ ] "el editar un animalito tarda en guardar, solo con una foto y el
      cambio del nombre"
- [ ] "Naranjita Lange no tiene ubicacion y en el feed aparece la bandera,
      no deberia mostrar nada"
- [ ] "escribi www.veterinariola30 para el aliado y no valida que la
      pagina web este bien escrita"

### Nuevo en APK90

- [ ] "me llego una notificacion al chat, el titulo dice adoptante
      adoptante y muestra una H, y me llego doble mensaje"

      Probar: aprobar una solicitud y contar las notificaciones que te
      llegan al teléfono del adoptante. Tiene que llegar **una sola**,
      la que dice "¡Tu solicitud fue aprobada! 🐾". Lo mismo al rechazar.

      Ojo: esto necesita APK90 **y** el servidor, que ya está desplegado.
      Con un APK viejo sigue llegando doble aunque el servidor esté al día.

---

## 2. Lo que encontré yo (no lo reportaste, no lo habías visto todavía)

### Datos que salían mal

- [ ] Mandar una solicitud sobre un **gato** y abrir el chat que sale de
      aprobarla o rechazarla. El emoji tiene que ser 🐱, no 🐶.
- [ ] Editar un animalito y tocar el botón de detectar ubicación en un
      lugar donde el GPS anda pero no resuelve el nombre de la ciudad
      (a veces pasa adentro de un edificio). Antes: las coordenadas se
      movían al lugar nuevo y el texto de ciudad se quedaba con el viejo,
      con el tilde en verde. Ahora tiene que avisar "No pudimos
      identificar tu ciudad" y **no cambiar nada**.
- [ ] Cambiarte el nombre en tu perfil y mirar una solicitud que hayas
      mandado **antes** de cambiarlo. Tiene que aparecer el nombre nuevo.
      Lo mismo en el chat de esa solicitud.
- [ ] Cambiar tu foto de Google y abrir un animalito que publicaste como
      **rescatista** (no como albergue) antes del cambio. Tiene que verse
      la foto nueva, y tu nombre tiene que ser el que editaste en la app,
      no el de Google.
- [ ] En el feed, un animalito sin ubicación no debe mostrar ninguna
      distancia (antes podía decir cosas como "a 8875.1 km de ti").

### Textos y nombres

- [ ] Un animalito sin nombre se llama igual en todos lados. En una
      tarjeta o encabezado dice "Sin nombre"; dentro de una frase dice
      "un animalito" (por ejemplo "Para un animalito"). Nunca "Animal",
      nunca "Para Sin nombre", nunca en blanco.
- [ ] Ajustes → Notificaciones: el interruptor de solicitudes ahora dice
      "Cuando alguien pide uno de tus animales, y cuando responden a tus
      solicitudes". Apagarlo tiene que silenciar **las dos** cosas.

### Fotos

- [ ] "Subir lote": tocar para agregar la **segunda** foto de un animalito
      de la lista. Antes iba directo a la galería; ahora tiene que ofrecer
      "Tomar foto / Elegir de la galería", igual que al publicar y editar.
- [ ] Compartir un animalito con **muy mala señal** (o wifi cortado a
      mitad). Antes el botón se quedaba colgado sin spinner ni error.
      Ahora, después de unos 15 segundos, tiene que compartir igual con
      solo texto.

---

## Si algo falla

Contame el paso exacto y qué viste. Si podés, una captura. No hace falta
que lo arregles vos.
