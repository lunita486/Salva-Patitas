// Lógica pura del equipo del albergue (invitaciones y membresías), sin
// ninguna llamada a Firestore ni a Auth: es la parte que decide quién puede
// invitar, quién puede aceptar y cuándo un hogar de paso bloquea al equipo.
// `equipo.js` lee los datos del servidor y le pregunta a estas funciones.
// Mismo patrón que eliminar_cuenta_logica.js.
//
// Diseño aprobado: PLAN-EQUIPO-ALBERGUE.md (decisiones del 2026-10-21 y
// 2026-10-22). Términos: "responsable del albergue" es la cuenta dueña
// (su uid es el albergueId), "miembro del equipo" es una persona invitada,
// "negocio aliado" es el rol técnico `aliado`.

const MAX_EQUIPO = 10;
const DIAS_VIGENCIA = 7;
const DIA_MS = 24 * 60 * 60 * 1000;
// Desde este día firestore.rules exige el rol 'albergue' para crear en
// hogaresDePaso (commit abf8525). Antes, una cuenta sin ese rol también podía.
const REGLA_ROL_ALBERGUE = Date.UTC(2026, 6, 31);
const DECISIONES_REVISION = ['compartir', 'no_compartir'];

const esTexto = (v) => typeof v === 'string' && v.trim() !== '';
const tiene = (lista, valor) => Array.isArray(lista) && lista.includes(valor);

/** Error con el código de HttpsError que corresponde; equipo.js lo traduce. */
class ErrorEquipo extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

/**
 * El cliente solo puede mandar estos campos. Cualquier otro se rechaza, para
 * que nadie pueda "declarar" desde la app cosas que decide el servidor (por
 * ejemplo que sus hogares ya están revisados o cuál es su albergue).
 */
function validarPayload(data, permitidos) {
  if (data === null || typeof data !== 'object' || Array.isArray(data)) {
    throw new ErrorEquipo('invalid-argument', 'Datos inválidos.');
  }
  const sobrantes = Object.keys(data).filter((k) => !permitidos.includes(k));
  if (sobrantes.length) {
    throw new ErrorEquipo('invalid-argument', `Campos no permitidos: ${sobrantes.join(', ')}.`);
  }
}

function normalizarEmail(email) {
  return typeof email === 'string' ? email.trim().toLowerCase() : '';
}

// A propósito simple: Auth es quien verifica el correo de verdad. Esto solo
// descarta lo que claramente no es un correo.
const emailValido = (email) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) && email.length <= 254;

/** Milisegundos de un Timestamp del SDK o de un Date; null si no hay fecha válida. */
function msDe(v) {
  if (v && typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date && !Number.isNaN(v.getTime())) return v.getTime();
  return null;
}

// ─── Identidades ─────────────────────────────────────────────────────────

/** Responsable del albergue: rol albergue y nombre de albergue cargado. */
function esResponsable(usuario) {
  return !!usuario && tiene(usuario.roles, 'albergue') && esTexto(usuario.albergueNombre);
}

/** Cualquier señal de responsable, aunque el perfil esté incompleto. */
function tieneSenalDeResponsable(usuario) {
  return !!usuario && (tiene(usuario.roles, 'albergue') || esTexto(usuario.albergueNombre));
}

function esNegocioAliado(usuario) {
  return !!usuario && (tiene(usuario.roles, 'aliado') || esTexto(usuario.aliadoNombre));
}

const membresiaActiva = (m) => !!m && m.estado === 'activa';

// ─── Hogares de paso dudosos ─────────────────────────────────────────────
//
// La colección no tiene campo de contexto. Un hogar es dudoso cuando la
// responsable tuvo vida de rescatista (rol o algún animal personal) y el
// hogar no tiene una fecha posterior a REGLA_ROL_ALBERGUE: pudo haberse
// creado fuera del contexto del albergue.
//
// Límite conocido: las reglas no obligan a que `creadoEn` sea la hora del
// servidor, así que una fecha posterior a la regla NO prueba que el hogar
// sea del albergue. Por eso esta barrera no alcanza sola: en una fase
// posterior las reglas solo dejarán ver al equipo hogares con
// `visibleEquipo == true`, y ningún hogar se vuelve visible por defecto.

function hogarDudoso(hogar, tuvoVidaDeRescatista) {
  if (!tuvoVidaDeRescatista) return false;
  const ms = msDe(hogar.creadoEn);
  return ms === null || ms < REGLA_ROL_ALBERGUE;
}

/**
 * Una revisión cuenta solo si está completa: decisión conocida, quién la
 * tomó y cuándo. Cualquier otra forma se trata como no revisada.
 */
function revisionValida(rev) {
  return !!rev && typeof rev === 'object' && !Array.isArray(rev) &&
    DECISIONES_REVISION.includes(rev.decision) &&
    esTexto(rev.por) &&
    msDe(rev.en) !== null;
}

/** Ids de los hogares dudosos que todavía no tienen una revisión válida. */
function hogaresPendientesDeRevision(hogares, tuvoVidaDeRescatista) {
  return hogares
      .filter((h) => hogarDudoso(h, tuvoVidaDeRescatista) && !revisionValida(h.revisionEquipo))
      .map((h) => h.id);
}

// Mensajes de la barrera de hogares. No dicen cuántos hogares hay, ni cuáles,
// ni nada del historial de la cuenta: la persona invitada no tiene por qué
// enterarse de nada de la responsable, y la responsable ve sus hogares en
// la app (la revisión es de una fase posterior).
function errorHogaresPendientes() {
  return new ErrorEquipo('failed-precondition',
      'Antes de invitar a tu equipo tenés que revisar tu red de hogares de paso.');
}

// Mismo texto para cualquier motivo por el que el albergue no puede sumar
// gente ahora (hogares sin revisar, la responsable dejó de serlo o es
// negocio aliado): así la persona invitada no puede deducir cuál es.
function errorAlbergueNoDisponible() {
  return new ErrorEquipo('failed-precondition',
      'Este albergue todavía no puede sumar personas a su equipo. Pedile a la responsable que revise su cuenta.');
}

// ─── Invitar ─────────────────────────────────────────────────────────────

/** Lanza si quien llama no puede invitar. */
function comprobarPuedeInvitar({ usuario, membresiaPropia }) {
  if (!esResponsable(usuario)) {
    throw new ErrorEquipo('permission-denied', 'Solo la responsable de un albergue puede invitar.');
  }
  if (membresiaActiva(membresiaPropia)) {
    throw new ErrorEquipo('permission-denied', 'Una persona que es miembro de un equipo no puede invitar.');
  }
  if (esNegocioAliado(usuario)) {
    throw new ErrorEquipo('failed-precondition',
        'Una cuenta que también es negocio aliado no puede tener equipo de albergue.');
  }
}

const invitacionVigente = (inv, ahora) => inv.estado === 'pendiente' && (msDe(inv.expiraEn) ?? 0) > ahora;

/** Lanza si no hay lugar: activos + invitaciones vigentes no pueden pasar de 10. */
function comprobarCupoParaInvitar({ miembrosActivos, invitacionesVigentes }) {
  if (miembrosActivos + invitacionesVigentes >= MAX_EQUIPO) {
    throw new ErrorEquipo('resource-exhausted',
        `El equipo ya tiene ${MAX_EQUIPO} lugares ocupados entre miembros e invitaciones pendientes.`);
  }
}

const venceEn = (ahora) => ahora + DIAS_VIGENCIA * DIA_MS;

// ─── Aceptar ─────────────────────────────────────────────────────────────

/**
 * Lanza si la invitación no se puede aceptar. `vencida` se devuelve aparte
 * porque en ese caso equipo.js además la marca como expirada.
 */
function comprobarPuedeAceptar({ invitacion, uid, email, ahora, membresiaPropia, usuario, responsable }) {
  if (!invitacion) throw new ErrorEquipo('not-found', 'La invitación no existe.');
  // El correo va primero: quien tenga el id de una invitación ajena no tiene
  // que poder averiguar nada de ella (ni siquiera si venció).
  if (normalizarEmail(invitacion.emailDestino) !== email) {
    throw new ErrorEquipo('permission-denied', 'Esta invitación es para otro correo.');
  }
  if (invitacion.estado !== 'pendiente') {
    throw new ErrorEquipo('failed-precondition', 'Esta invitación ya no está disponible.');
  }
  if ((msDe(invitacion.expiraEn) ?? 0) <= ahora) {
    return { vencida: true };
  }
  if (invitacion.albergueId === uid) {
    throw new ErrorEquipo('permission-denied', 'No podés aceptar una invitación de tu propio albergue.');
  }
  if (membresiaActiva(membresiaPropia)) {
    throw new ErrorEquipo('failed-precondition', 'Ya sos miembro de un equipo. Primero tenés que salir de ese equipo.');
  }
  if (tieneSenalDeResponsable(usuario)) {
    throw new ErrorEquipo('permission-denied', 'Una responsable de albergue no puede ser miembro de otro equipo.');
  }
  if (esNegocioAliado(usuario)) {
    throw new ErrorEquipo('permission-denied', 'Una cuenta de negocio aliado no puede ser miembro de un equipo.');
  }
  if (!esResponsable(responsable) || esNegocioAliado(responsable)) {
    throw errorAlbergueNoDisponible();
  }
  return { vencida: false };
}

function comprobarCupoParaAceptar({ miembrosActivos }) {
  if (miembrosActivos >= MAX_EQUIPO) {
    throw new ErrorEquipo('resource-exhausted', `El equipo ya tiene ${MAX_EQUIPO} miembros.`);
  }
}

// ─── Terminar una membresía ──────────────────────────────────────────────
//
// Una membresía terminada no se borra: queda con su motivo, para que la
// responsable vea quién estuvo y la persona pueda volver a ser invitada.
// La única excepción es la eliminación de cuenta de la propia persona, que
// borra su documento (tiene su nombre y su correo).

const MOTIVOS_FIN = ['revocada', 'salio'];

/** Lanza si la responsable [uid] no puede quitar a esa persona de su equipo. */
function comprobarPuedeRevocar({ uid, miembroUid, membresia }) {
  if (miembroUid === uid) {
    throw new ErrorEquipo('invalid-argument', 'No podés quitarte a vos misma del equipo.');
  }
  // Mismo mensaje si no existe o si es de otro albergue: quien llama no
  // tiene por qué saber si esa persona está en otro equipo.
  if (!membresiaActiva(membresia) || membresia.albergueId !== uid) {
    throw new ErrorEquipo('not-found', 'Esa persona no es miembro de tu equipo.');
  }
}

/** Lanza si quien llama no tiene un equipo del que salir. */
function comprobarPuedeSalir({ membresia }) {
  if (!membresiaActiva(membresia)) {
    throw new ErrorEquipo('failed-precondition', 'No sos miembro de ningún equipo.');
  }
}

/** Lanza si la responsable [uid] no puede cancelar esa invitación. */
function comprobarPuedeCancelar({ uid, invitacion }) {
  if (!invitacion || invitacion.albergueId !== uid) {
    throw new ErrorEquipo('not-found', 'La invitación no existe.');
  }
  if (invitacion.estado !== 'pendiente') {
    throw new ErrorEquipo('failed-precondition', 'Esta invitación ya no está pendiente.');
  }
}

/** Lanza si la persona con correo [email] no puede rechazar esa invitación. */
function comprobarPuedeRechazar({ email, invitacion }) {
  // Igual que al aceptar: el correo va primero, para no revelar nada de una
  // invitación ajena.
  if (!invitacion || normalizarEmail(invitacion.emailDestino) !== email) {
    throw new ErrorEquipo('not-found', 'La invitación no existe.');
  }
  if (invitacion.estado !== 'pendiente') {
    throw new ErrorEquipo('failed-precondition', 'Esta invitación ya no está disponible.');
  }
}

/** El contador nunca baja de cero, aunque el documento esté desfasado. */
const restarMiembro = (miembrosActivos) => Math.max(0, (Number(miembrosActivos) || 0) - 1);

// ─── Revisión de hogares para el equipo ──────────────────────────────────

/** Lanza si la responsable [uid] no puede decidir sobre ese hogar. */
function comprobarPuedeRevisarHogar({ uid, usuario, hogar, decision }) {
  if (!DECISIONES_REVISION.includes(decision)) {
    throw new ErrorEquipo('invalid-argument', 'Decisión inválida.');
  }
  if (!esResponsable(usuario)) {
    throw new ErrorEquipo('permission-denied', 'Solo la responsable del albergue decide qué ve su equipo.');
  }
  if (!hogar || hogar.albergueId !== uid) {
    throw new ErrorEquipo('not-found', 'Ese hogar de paso no está en tu red.');
  }
}

// ─── Eliminación de cuenta ───────────────────────────────────────────────

/**
 * Mensaje de bloqueo si la cuenta es responsable de un equipo con gente,
 * o null. Decisión 3: sin transferencia de propiedad en la v1.
 */
function bloqueoEliminarCuenta({ miembrosActivos, invitacionesVigentes }) {
  if (miembrosActivos > 0 || invitacionesVigentes > 0) {
    return 'Tu albergue tiene un equipo. Antes de eliminar tu cuenta, quitá a las personas del equipo y cancelá las invitaciones pendientes.';
  }
  return null;
}

module.exports = {
  MAX_EQUIPO, DIAS_VIGENCIA, REGLA_ROL_ALBERGUE, DECISIONES_REVISION,
  ErrorEquipo, validarPayload, normalizarEmail, emailValido, msDe,
  esResponsable, tieneSenalDeResponsable, esNegocioAliado, membresiaActiva,
  hogarDudoso, revisionValida, hogaresPendientesDeRevision, errorHogaresPendientes, errorAlbergueNoDisponible,
  comprobarPuedeInvitar, invitacionVigente, comprobarCupoParaInvitar, venceEn,
  comprobarPuedeAceptar, comprobarCupoParaAceptar,
  MOTIVOS_FIN, comprobarPuedeRevocar, comprobarPuedeSalir, comprobarPuedeCancelar, comprobarPuedeRechazar,
  restarMiembro, comprobarPuedeRevisarHogar, bloqueoEliminarCuenta,
};
