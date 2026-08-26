// Lógica pura de "¿toca avisar hoy que un hogar de paso vence mañana o ya
// venció?" — sin ninguna llamada a Firestore acá adentro, a propósito
// (mismo criterio que eliminar_cuenta_logica.js): permite testear con
// `node --test` simple, sin depender del emulador.
//
// Mismo criterio EXACTO que verificarVencimientos() del lado del cliente
// (lib/screens/solicitudes_rescatista_screen.dart) — dos flags separados
// (avisoPrevioAvisado/vencimientoAvisado) para que el aviso de "vence
// mañana" y el de "ya venció" no se pisen entre sí, cada uno se manda una
// sola vez.

function textoVenceManana(nombre) {
  return `📋 El período de hogar de paso de ${nombre} vence mañana. `
    + 'Coordiná con tiempo la devolución o el proceso de adopción definitivo. 🐾';
}

function textoVencido(nombre) {
  return `📋 El período de hogar de paso de ${nombre} ha vencido. `
    + 'Por favor coordina la devolución o el proceso de adopción definitivo. 🐾';
}

function sinHora(fecha) {
  return new Date(fecha.getFullYear(), fecha.getMonth(), fecha.getDate());
}

// null si no toca avisar nada (todavía falta más de un día, o ya se avisó
// lo que correspondía) — si no, { tipo, flag, mensaje } con el flag que hay
// que marcar en `rescates/{id}` para no volver a mandar este mismo aviso.
function decidirAviso({ fechaFin, ahora, avisoPrevioAvisado, vencimientoAvisado, nombre }) {
  if (fechaFin > ahora) {
    const diasRestantes = Math.round((sinHora(fechaFin) - sinHora(ahora)) / 86400000);
    if (diasRestantes === 1 && avisoPrevioAvisado !== true) {
      return { tipo: 'previo', flag: 'avisoPrevioAvisado', mensaje: textoVenceManana(nombre) };
    }
    return null;
  }
  if (vencimientoAvisado === true) return null;
  return { tipo: 'vencido', flag: 'vencimientoAvisado', mensaje: textoVencido(nombre) };
}

/**
 * ¿Por qué vía le avisamos, y a quién?
 *
 * **El caso que faltaba.** Un hogar de paso puesto A MANO desde el
 * desplegable de estado no tiene cuenta en la app: es la señora que ayuda
 * al refugio y que nunca va a instalar nada. Sin `adoptanteIdEnProceso` no
 * hay a quién escribirle por chat.
 *
 * Antes eso hacía que la función salteara el animalito ENTERO
 * (`if (!fechaFinTs || !adoptanteId || !rescatistaId) continue`), así que
 * el rescatista tampoco se enteraba. El recordatorio no existía para el
 * caso más común en un refugio de verdad.
 *
 * Ahora se separan las dos cosas: si el cuidador tiene cuenta, el aviso va
 * por chat y los dos lo ven. Si no la tiene, igual le llega al
 * rescatista/albergue por notificación, que es quien puede hacer algo al
 * respecto.
 *
 * Devuelve `null` solo cuando no hay dueño: ahí sí no hay nadie a quien
 * avisarle.
 */
function comoAvisar({ adoptanteIdEnProceso, rescatistaId }) {
  if (!rescatistaId) return null;
  const cuidador = (adoptanteIdEnProceso || '').trim();
  return cuidador !== ''
    ? { via: 'chat', adoptanteId: cuidador, rescatistaId }
    : { via: 'push', rescatistaId };
}

/**
 * El nombre de un animalito, listo para meter DENTRO de una frase.
 *
 * Es el espejo en JS de `nombreDeAnimal(..., enFrase: true)`
 * (lib/domain/reglas_negocio.dart). Existir dos veces es inevitable: el
 * servidor no puede importar Dart. Pero UNA por lenguaje, no diez: en la
 * app había siete copias sueltas más dos funciones, y por eso el mismo bug
 * ("Para Sin nombre", que reportó Eliza) se arregló una vez y siguió vivo
 * en las otras nueve.
 *
 * Los textos de acá siempre son frases ("El período de hogar de paso de X
 * vence mañana"), así que no hace falta la forma de título.
 *
 * Trata el literal 'Sin nombre' como ausencia de nombre, igual que la
 * versión de Dart: ese texto se coló a la base guardado como si fuera el
 * dato real, y sin esto saldría "El período de hogar de paso de Sin nombre
 * vence mañana".
 */
function nombreEnFrase(nombre) {
  const limpio = (nombre || '').trim();
  return limpio === '' || limpio === 'Sin nombre' ? 'un animalito' : limpio;
}

/** Título de la notificación, según si ya venció o vence mañana. */
function tituloPush(tipo) {
  return tipo === 'previo'
    ? 'Un hogar de paso vence mañana'
    : 'Un hogar de paso ya venció';
}

module.exports = {
  decidirAviso,
  nombreEnFrase,
  textoVenceManana,
  textoVencido,
  comoAvisar,
  tituloPush,
};
