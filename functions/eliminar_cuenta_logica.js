// Lógica pura de "eliminar mi cuenta" — sin ninguna llamada a Firestore/Auth
// acá adentro, a propósito: es lo que permite testear la parte más delicada
// (qué se borra, qué se anonimiza, cuándo se bloquea) con `node --test`
// simple, sin depender del emulador (que esta máquina no puede correr hoy
// por falta de Java). `eliminar_cuenta.js` hace las consultas reales y
// llama a estas funciones para decidir.

// Mismos strings que ya usa RescatesRepository.mensajeBloqueoEliminar
// (lib/data/rescates_repository.dart) para las mismas dos categorías de
// estado "reversible/activo" — un animal en cualquiera de estos dos
// estados tiene a alguien con la custodia física ahora mismo o un proceso
// sin resolver.
const ESTADOS_ACTIVOS = ['Hogar de paso', 'En proceso de adopción'];

// null si no bloquea; el mensaje de bloqueo (para mostrar tal cual) si sí.
// Bloquea por dos lados: la cuenta puede tener un animal a su cargo AHORA
// (como adoptante/hogar de paso) o puede tener publicado un animal que
// está actualmente con otra persona (como rescatista/albergue) — en los
// dos casos, borrar la cuenta le haría perder a alguien la referencia de
// quién tiene al animal.
function motivoBloqueo({ tieneComoAdoptante, tieneComoRescatista }) {
  if (tieneComoAdoptante) {
    return 'Tenés un animal en hogar de paso o en proceso de adopción a tu cargo '
      + 'ahora mismo. Esperá a que termine ese proceso antes de eliminar tu cuenta.';
  }
  if (tieneComoRescatista) {
    return 'Tenés un animal publicado que está actualmente en hogar de paso o en '
      + 'proceso de adopción con otra persona. Esperá a que termine ese proceso '
      + 'antes de eliminar tu cuenta.';
  }
  return null;
}

// 'borrar' | 'anonimizar' | 'dejar' para un doc de `solicitudes`.
// - pendiente/rechazada: no llegaron a nada, se borran sin más.
// - aprobada y esta cuenta es quien adoptó: es el registro permanente del
//   rescatista/albergue de que el animal encontró hogar — se conserva,
//   pero sin los datos personales de quien ya no tiene cuenta.
// - aprobada y esta cuenta es el rescatista/albergue: los datos sensibles
//   del documento (vivienda, familia, motivación) son del ADOPTANTE, no de
//   esta cuenta — no hay nada que anonimizar acá, se deja como está.
function clasificarSolicitud({ estado, adoptanteId }, uid) {
  if (estado === 'pendiente' || estado === 'rechazada') return 'borrar';
  if (estado === 'aprobada' && adoptanteId === uid) return 'anonimizar';
  return 'dejar';
}

// 'borrar' | 'anonimizar' para un doc de `chats` (la subcolección
// `mensajes` se borra aparte, siempre, en los dos casos — ver comentario
// en eliminar_cuenta.js sobre por qué el texto libre no se anonimiza).
//
// Las consultas a un aliado (tipoSolicitud 'consulta_aliado') se
// anonimizan siempre, aunque no tengan una "solicitud aprobada" detrás —
// decisión explícita de Eliza para poder armar más adelante reportes tipo
// "cuántas consultas recibió cada aliado" sin ningún dato personal.
//
// Un chat legado sin rescateId (ver el comentario "Fallback legado" en
// firestore.rules) no se puede emparejar con ninguna solicitud aprobada
// de forma confiable — por defecto se borra (dato viejo, bajo riesgo).
function clasificarChat({ tipoSolicitud, rescateId, adoptanteId }, clavesAprobadas) {
  if (tipoSolicitud === 'consulta_aliado') return 'anonimizar';
  const clave = `${rescateId || ''}_${adoptanteId || ''}`;
  return clavesAprobadas.has(clave) ? 'anonimizar' : 'borrar';
}

module.exports = { ESTADOS_ACTIVOS, motivoBloqueo, clasificarSolicitud, clasificarChat };
