# Checklist de prueba — V37 (todo lo hecho después del AAB #3)

Instalá `Salva Patitas V37.apk` en tu celular y probá esto en orden. Marcá
cada uno. Si algo falla, anotá en qué paso fue y qué mensaje/comportamiento
viste.

El historial completo de rondas anteriores (con todo lo del AAB #3 hacia
atrás, ya confirmado) queda en `docs/checklist-prueba-manual-fotos.md` —
acá va solo lo nuevo, para no reprobar lo que ya sabemos que funciona.

## 1. Colores de los mensajes (toda la app)
- [ ] Un error real (ej. dejar un campo obligatorio vacío, o intentar
      algo sin conexión) se ve con fondo **rojo**.
- [ ] Una advertencia (la acción principal funcionó pero algo secundario
      falló) se ve con fondo **naranja**.
- [ ] Un éxito completo se ve con fondo **verde**.
- [ ] Ningún mensaje de error/advertencia/éxito queda con el fondo negro
      por defecto de antes. (Los de puro progreso tipo "Eliminando…" se
      dejan neutros a propósito.)
- [ ] Ningún mensaje (diálogos incluidos) tiene un guión largo "—".

## 2. Teléfono, dirección, email y web (albergue y aliado)
- [ ] Perfil de albergue: podés cargar Teléfono/WhatsApp, Dirección,
      Email y Página web, los 4 opcionales.
- [ ] Mismo en el perfil de aliado.
- [ ] Si tu cuenta tiene rol de albergue Y de aliado a la vez, cargar el
      contacto de uno NO aparece en el otro.
- [ ] El perfil público de un albergue muestra esos datos en "Contacto",
      con botón de WhatsApp directo a wa.me.
- [ ] Mismo en el perfil público de un aliado.
- [ ] **Nuevo**: "Configura tu albergue" y "Configura tu negocio" se ven
      con la misma tipografía, etiquetas en mayúsculas chicas y en negro,
      cajas blancas sin ícono adentro (antes cada pantalla tenía un estilo
      distinto).

## 3. Aviso de animales "estancados"
- [ ] Animal en "Rescatado", "Hogar de paso" o "Regresado" con más días
      que tu umbral configurado → aviso **naranja** en su tarjeta con la
      cantidad de días.
- [ ] Al doble de tu umbral, el aviso pasa a **rojo**.
- [ ] El botón "Compartir en redes" adentro del aviso funciona.
- [ ] Si el aviso de estancado está visible, el ícono de compartir de
      abajo de la tarjeta **desaparece** (ya no queda duplicado).
- [ ] En tu perfil hay "Aviso de animal sin adoptar" con 6 valores (15
      días a 1 año y más) que cambia el umbral.
- [ ] Chip **"Estancados"** en los filtros de "Mis rescates"/"Mis
      animales" muestra solo esos animales.
- [ ] En "Mis animales" (albergue), los filtros de especie ya no tienen
      un chip "Todos" duplicado.

## 4. Aviso de capacidad (solo albergue)
- [ ] **Nuevo**: la tarjeta ya NO muestra el número de porcentaje
      ("67% ocupado", etc.), solo "N de M animales" — el porcentaje
      confundía más de lo que ayudaba.
- [ ] Con todos los lugares ocupados (100%) → la barra se pone **roja** y
      el aviso dice "Llegaste al límite de capacidad".
- [ ] Con capacidad chica (ej. 3 lugares), si te queda **1 lugar libre o
      menos** (aunque no esté lleno del todo), el aviso "Cerca del
      límite de capacidad" aparece igual.

## 5. Hogar de paso
- [ ] En "Mis rescates"/"Mis animales", un animal en "Hogar de paso"
      muestra la fecha de inicio → fin y cuántos días restan (o si ya
      venció) directo en su tarjeta.
- [ ] Cuando vence, además del mensaje automático al adoptante, a VOS te
      aparece un aviso en pantalla al abrir tu panel.
- [ ] Un día ANTES de que venza, también te avisa (a vos y al adoptante),
      "vence mañana", no solo cuando ya pasó.
- [ ] Un animal "Regresado" cuenta como "en cuidado" (ocupa capacidad),
      volvió físicamente con vos.
- [ ] Un animal en "Hogar de paso" YA NO cuenta como "en cuidado", está en
      la casa de otra persona, libera ese lugar.

## 6. Recordatorio automático post-adopción
- [ ] Animal "Adoptado" hace 7+ días → al adoptante le llega un mensaje
      de chat preguntando cómo le va.
- [ ] A los 30+ días, un segundo mensaje distinto, sin repetir el primero.

## 7. Ver la ficha del animal desde "Mis solicitudes"
- [ ] Tocar la foto de cualquier solicitud (pendiente, aprobada o
      rechazada) abre la ficha completa del animal (fotos grandes, raza,
      salud, descripción).

## 8. Red de hogares de paso (solo albergue)
- [ ] Tarjeta "Red de hogares de paso" en tu panel, con el ícono 🫶.
- [ ] Aprobar una solicitud de hogar de paso agrega sola a esa persona,
      con "ayudó 1 vez"; aprobar otra de la misma persona suma en la
      misma fila (no duplica).
- [ ] Si la persona ya tiene cuenta en la app, se ve su foto real (no la
      inicial, y nunca el logo de tu negocio).
- [ ] Si le cargaste el email a alguien agregado a mano, y esa persona
      más adelante ayuda de verdad por la app con ese mismo email, se
      fusiona sola en la misma fila (no crea una duplicada).
- [ ] Botón de WhatsApp funciona si hay teléfono cargado.
- [ ] Lápiz de "Editar contacto" deja cargar/cambiar teléfono, notas y
      email después, incluso en las filas que se agregaron solas.
- [ ] Se puede quitar a alguien de la red.

## 9. Compromiso / registro del acuerdo de adopción
- [ ] Adoptante con una solicitud de **adopción** (no hogar de paso) ya
      **aprobada** (aprobada desde el botón "Aprobar" en Solicitudes, no
      cambiando el estado a mano) → botón naranja "Ver compromiso de
      adopción".
- [ ] El texto ya NO incluye la línea de esterilización.
- [ ] Al aceptar, cambia a "✅ Compromiso de adopción aceptado el
      [fecha]".
- [ ] El rescatista/albergue ve la misma constancia (solo lectura) en su
      pantalla de Solicitudes.
- [ ] Si dos solicitudes distintas compiten por el mismo animal, la
      segunda se rechaza sola automáticamente ("el proceso ya fue
      iniciado con otro adoptante"), el animal se queda "En proceso de
      adopción" en los dos casos, acepte o no el compromiso.

## 10. Eliminar animales: solo en "Rescatado" (nuevo)
- [ ] Un animal en "Rescatado" se puede eliminar directo, con la
      confirmación de siempre.
- [ ] Un animal en "Hogar de paso", "En proceso de adopción" o
      "Regresado": el botón de eliminar sigue visible, pero al tocarlo
      avisa "No se puede eliminar todavía" y pide cambiar el estado
      primero.
- [ ] Un animal "Adoptado" o "Fallecido": el botón de eliminar
      directamente no aparece, quedan como registro permanente.
- [ ] Un animal que estuvo "Adoptado" (o tuvo un hogar de paso/adopción
      aprobados) y alguien lo volvió a pasar a "Rescatado" a mano:
      tampoco se puede eliminar, avisa "No se puede eliminar" y pide
      marcarlo como Adoptado/Regresado/Fallecido en su lugar. Así la
      solicitud del adoptante no queda apuntando a un animal borrado.

## 11. Arreglos chicos (nuevo)
- [ ] Una solicitud de hogar de paso sobre un animal sin nombre dice
      "Para un animalito" (antes decía, literalmente, "Para Sin
      nombre").
- [ ] En el feed del adoptante, cambiar de filtro de especie
      (Todos/Perros/Gatos/Otros) o tocar "Ver de nuevo" en "Eso es todo
      por hoy" no rompe la tarjeta del siguiente animal (antes, en
      ciertos casos, mostraba una pantalla de error roja).
- [ ] En "Mis rescates", un animal "En proceso de adopción" con el botón
      "Contactar" al lado ya no se ve con el botón pegado al borde, la
      píldora de estado queda a la izquierda y "Contactar" siempre a la
      derecha, igual que en los demás estados.
- [ ] Publicar un animal con el mismo nombre que otro que ya tenés
      (duplicado): sale el aviso "Posible animal duplicado" con 3
      opciones (Cancelar / Ver ficha existente / Publicar igual). Elegir
      "Publicar igual" publica sin error.

---

**Si todo lo de arriba pasa:** avisame y vemos qué sigue.

**Si algo falla:** contame el paso exacto y el mensaje/comportamiento —
no hace falta que lo arregles vos, solo que me digas qué pasó.
