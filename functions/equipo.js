// Functions del equipo del albergue: invitaciones, membresías y qué hogares
// de paso ve el equipo. Ver PLAN-EQUIPO-ALBERGUE.md.
//
// Admin SDK no pasa por firestore.rules: cada Function comprueba ella misma
// quién llama y qué puede hacer, siempre con `request.auth` y con lo que lee
// del servidor. Del cliente solo se acepta el correo a invitar o el id de la
// invitación; cualquier otro campo se rechaza.
//
// Barrera de hogares de paso (barrera 1 del diseño): ni invitar ni aceptar
// funcionan mientras la responsable tenga hogares de paso dudosos sin una
// revisión válida. Se calcula en cada llamada leyendo los hogares, nunca
// desde un conteo guardado. La barrera 2 son las reglas: el equipo solo lee
// hogares con `visibleEquipo == true`, que únicamente escribe
// revisarHogarEquipo.
//
// Las notificaciones van DESPUÉS de cada transacción y nunca hacen fallar
// la operación: si FCM falla, la invitación o el cambio de equipo ya quedó
// hecho igual.
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');
const L = require('./equipo_logica');

// Solo lo necesario para decidir. Nunca nombres, teléfonos, correos ni notas
// de las familias.
const CAMPOS_HOGAR = ['albergueId', 'creadoEn', 'revisionEquipo'];

// Varias aceptaciones o invitaciones simultáneas del mismo albergue chocan a
// propósito sobre equipos/{albergueId}; con más reintentos que el valor por
// defecto (5) ninguna falla por contención, solo por las reglas de negocio.
const MAX_INTENTOS = 30;

function aHttps(e) {
  return e instanceof L.ErrorEquipo ? new HttpsError(e.code, e.message) : e;
}

/** Sesión con correo verificado. El uid y el correo salen del token, nunca de request.data. */
function comprobarSesion(request) {
  if (!request || !request.auth || !request.auth.uid) {
    throw new L.ErrorEquipo('unauthenticated', 'Iniciá sesión de nuevo e intentá otra vez.');
  }
  const token = request.auth.token || {};
  if (token.email_verified !== true) {
    throw new L.ErrorEquipo('failed-precondition', 'Primero verificá tu correo electrónico.');
  }
  const email = L.normalizarEmail(token.email);
  if (!email) throw new L.ErrorEquipo('failed-precondition', 'Tu cuenta no tiene un correo asociado.');
  return { uid: request.auth.uid, email, nombre: typeof token.name === 'string' ? token.name : '' };
}

/**
 * Ids de los hogares de paso dudosos sin revisión válida de este albergue.
 * Se lee dentro de la transacción, así que es el dato del momento.
 */
async function leerHogaresPendientes(tx, db, albergueId, responsable) {
  const snap = await tx.get(db.collection('hogaresDePaso')
      .where('albergueId', '==', albergueId).select(...CAMPOS_HOGAR));
  const hogares = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
  if (!hogares.length) return [];
  let tuvoVidaDeRescatista = Array.isArray(responsable?.roles) && responsable.roles.includes('rescatista');
  if (!tuvoVidaDeRescatista) {
    const animal = await tx.get(db.collection('rescates')
        .where('rescatistaId', '==', albergueId).where('creadoPor', '==', 'rescatista')
        .select('rescatistaId').limit(1));
    tuvoVidaDeRescatista = !animal.empty;
  }
  return L.hogaresPendientesDeRevision(hogares, tuvoVidaDeRescatista);
}

const datos = (snap) => (snap.exists ? snap.data() : null);
const contador = (snap) => (snap.exists ? Number(snap.data().miembrosActivos) || 0 : 0);

// Dependencias que las pruebas reemplazan. Se cargan recién al usarlas: en
// el emulador no hay app por defecto de Admin ni emulador de Auth.
const avisarPorDefecto = (uid, titulo, cuerpo) => require('./notificar').notificar(uid, titulo, cuerpo);
async function buscarUidPorDefecto(email) {
  try {
    return (await require('firebase-admin/auth').getAuth().getUserByEmail(email)).uid;
  } catch (_) {
    return null;
  }
}

async function avisarSinFallar(avisar, uid, titulo, cuerpo) {
  if (!uid) return;
  try {
    await avisar(uid, titulo, cuerpo);
  } catch (e) {
    console.error('Aviso del equipo no enviado:', e.code || e.message);
  }
}

function idValido(id) {
  return typeof id === 'string' && id !== '' && !id.includes('/') && id.length <= 200;
}

async function invitarMiembroHandler(request, {
  db = getFirestore(), ahora = Date.now, avisar = avisarPorDefecto, buscarUid = buscarUidPorDefecto,
} = {}) {
  try {
    const { uid, email: emailPropio } = comprobarSesion(request);
    L.validarPayload(request.data, ['email']);
    const email = L.normalizarEmail(request.data.email);
    if (!L.emailValido(email)) throw new L.ErrorEquipo('invalid-argument', 'El correo no es válido.');
    if (email === emailPropio) throw new L.ErrorEquipo('invalid-argument', 'No te podés invitar a vos misma.');

    const r = await db.runTransaction(async (tx) => {
      const t = ahora();
      const equipoRef = db.collection('equipos').doc(uid);
      const usuario = datos(await tx.get(db.collection('usuarios').doc(uid)));
      const membresiaPropia = datos(await tx.get(db.collection('membresias').doc(uid)));
      const equipoSnap = await tx.get(equipoRef);
      const pendientesSnap = await tx.get(db.collection('invitaciones')
          .where('albergueId', '==', uid).where('estado', '==', 'pendiente'));

      L.comprobarPuedeInvitar({ usuario, membresiaPropia });
      const pendientes = await leerHogaresPendientes(tx, db, uid, usuario);
      if (pendientes.length) throw L.errorHogaresPendientes();

      const vigentes = pendientesSnap.docs.map((d) => d.data()).filter((i) => L.invitacionVigente(i, t));
      if (vigentes.some((i) => L.normalizarEmail(i.emailDestino) === email)) {
        throw new L.ErrorEquipo('already-exists', 'Ya hay una invitación pendiente para ese correo.');
      }
      const miembrosActivos = contador(equipoSnap);
      L.comprobarCupoParaInvitar({ miembrosActivos, invitacionesVigentes: vigentes.length });

      const invRef = db.collection('invitaciones').doc();
      const creadaEn = Timestamp.fromMillis(t);
      const expiraEn = Timestamp.fromMillis(L.venceEn(t));
      tx.set(invRef, {
        albergueId: uid, albergueNombre: usuario.albergueNombre, emailDestino: email, estado: 'pendiente',
        creadaEn, expiraEn, creadaPor: uid, aceptadaPor: null, aceptadaEn: null,
      });
      // Se escribe siempre: así dos invitaciones o aceptaciones simultáneas
      // del mismo albergue chocan acá y una se reintenta viendo a la otra.
      tx.set(equipoRef, { miembrosActivos, actualizadoEn: creadaEn }, { merge: true });
      return { invitacionId: invRef.id, expiraEn: expiraEn.toMillis(), albergueNombre: usuario.albergueNombre };
    }, { maxAttempts: MAX_INTENTOS });
    // Si esa persona ya tiene cuenta, se entera al toque; si no, ve la
    // invitación cuando entre con ese correo. A quien invita no se le dice
    // si la cuenta existe.
    const destino = await buscarUid(email);
    if (destino && destino !== uid) {
      await avisarSinFallar(avisar, destino, 'Te invitaron a un equipo 🐾',
          `${r.albergueNombre} te invitó a sumarte a su equipo en Salva Patitas.`);
    }
    return { invitacionId: r.invitacionId, expiraEn: r.expiraEn };
  } catch (e) {
    throw aHttps(e);
  }
}

async function aceptarInvitacionHandler(request, { db = getFirestore(), ahora = Date.now, avisar = avisarPorDefecto } = {}) {
  try {
    const { uid, email, nombre } = comprobarSesion(request);
    L.validarPayload(request.data, ['invitacionId']);
    const id = request.data.invitacionId;
    if (!idValido(id)) throw new L.ErrorEquipo('invalid-argument', 'Invitación inválida.');

    const r = await db.runTransaction(async (tx) => {
      const t = ahora();
      const invRef = db.collection('invitaciones').doc(id);
      const invitacion = datos(await tx.get(invRef));
      if (!invitacion) throw new L.ErrorEquipo('not-found', 'La invitación no existe.');
      const albergueId = invitacion.albergueId;
      if (typeof albergueId !== 'string' || !albergueId || albergueId.includes('/')) {
        throw new L.ErrorEquipo('failed-precondition', 'La invitación está dañada.');
      }
      const usuarioRef = db.collection('usuarios').doc(uid);
      const membresiaRef = db.collection('membresias').doc(uid);
      const equipoRef = db.collection('equipos').doc(albergueId);
      const usuarioSnap = await tx.get(usuarioRef);
      const membresiaPropia = datos(await tx.get(membresiaRef));
      const responsable = datos(await tx.get(db.collection('usuarios').doc(albergueId)));
      const equipoSnap = await tx.get(equipoRef);

      const { vencida } = L.comprobarPuedeAceptar({
        invitacion, uid, email, ahora: t, membresiaPropia, usuario: datos(usuarioSnap), responsable,
      });
      if (vencida) {
        tx.update(invRef, { estado: 'expirada' });
        return { vencida: true };
      }
      // Se vuelve a mirar al aceptar: una invitación vieja, o una que no pasó
      // por invitarMiembro, tampoco puede saltarse la barrera.
      const pendientes = await leerHogaresPendientes(tx, db, albergueId, responsable);
      if (pendientes.length) throw L.errorAlbergueNoDisponible();
      const miembrosActivos = contador(equipoSnap);
      L.comprobarCupoParaAceptar({ miembrosActivos });

      const ahoraTs = Timestamp.fromMillis(t);
      tx.set(membresiaRef, {
        albergueId, estado: 'activa', rol: 'miembro', nombre, email,
        invitacionId: id, desde: ahoraTs, terminadaEn: null, terminadaPor: null,
      });
      tx.update(invRef, { estado: 'aceptada', aceptadaPor: uid, aceptadaEn: ahoraTs });
      tx.set(equipoRef, { miembrosActivos: miembrosActivos + 1, actualizadoEn: ahoraTs }, { merge: true });
      // No se escribe nada en usuarios/{uid}: ni `roles` ni `trabajaEn`. El
      // perfil lo puede leer cualquier cuenta con sesión, y ahí quedaría a
      // la vista a qué equipo pertenece cada persona. La fuente de verdad
      // es membresias/{uid}. (firestore.rules sigue impidiendo que un
      // cliente escriba `trabajaEn`.)
      return { vencida: false, albergueId };
    }, { maxAttempts: MAX_INTENTOS });

    if (r.vencida) throw new L.ErrorEquipo('failed-precondition', 'La invitación venció. Pedile una nueva a la responsable.');
    await avisarSinFallar(avisar, r.albergueId, 'Se sumó alguien a tu equipo', `${nombre || email} aceptó tu invitación.`);
    return { albergueId: r.albergueId };
  } catch (e) {
    throw aHttps(e);
  }
}

async function cancelarInvitacionHandler(request, { db = getFirestore(), ahora = Date.now } = {}) {
  try {
    const { uid } = comprobarSesion(request);
    L.validarPayload(request.data, ['invitacionId']);
    const id = request.data.invitacionId;
    if (!idValido(id)) throw new L.ErrorEquipo('invalid-argument', 'Invitación inválida.');
    await db.runTransaction(async (tx) => {
      const invRef = db.collection('invitaciones').doc(id);
      const equipoRef = db.collection('equipos').doc(uid);
      const invitacion = datos(await tx.get(invRef));
      const equipoSnap = await tx.get(equipoRef);
      L.comprobarPuedeCancelar({ uid, invitacion });
      const t = Timestamp.fromMillis(ahora());
      tx.update(invRef, { estado: 'cancelada', canceladaEn: t });
      // Mismo punto de choque que invitar y aceptar (ver invitarMiembro).
      tx.set(equipoRef, { miembrosActivos: contador(equipoSnap), actualizadoEn: t }, { merge: true });
    }, { maxAttempts: MAX_INTENTOS });
    return { ok: true };
  } catch (e) {
    throw aHttps(e);
  }
}

async function rechazarInvitacionHandler(request, { db = getFirestore(), ahora = Date.now } = {}) {
  try {
    const { email } = comprobarSesion(request);
    L.validarPayload(request.data, ['invitacionId']);
    const id = request.data.invitacionId;
    if (!idValido(id)) throw new L.ErrorEquipo('invalid-argument', 'Invitación inválida.');
    await db.runTransaction(async (tx) => {
      const invRef = db.collection('invitaciones').doc(id);
      const invitacion = datos(await tx.get(invRef));
      L.comprobarPuedeRechazar({ email, invitacion });
      tx.update(invRef, { estado: 'rechazada', rechazadaEn: Timestamp.fromMillis(ahora()) });
    }, { maxAttempts: MAX_INTENTOS });
    return { ok: true };
  } catch (e) {
    throw aHttps(e);
  }
}

/** Saca a una persona del equipo y baja el contador, en una transacción. */
async function terminarMembresia(tx, db, membresiaRef, membresia, motivo, por, t) {
  const equipoRef = db.collection('equipos').doc(membresia.albergueId);
  const equipoSnap = await tx.get(equipoRef);
  tx.update(membresiaRef, { estado: motivo, terminadaEn: t, terminadaPor: por });
  tx.set(equipoRef, { miembrosActivos: L.restarMiembro(contador(equipoSnap)), actualizadoEn: t }, { merge: true });
}

async function revocarMiembroHandler(request, { db = getFirestore(), ahora = Date.now, avisar = avisarPorDefecto } = {}) {
  try {
    const { uid } = comprobarSesion(request);
    L.validarPayload(request.data, ['miembroUid']);
    const miembroUid = request.data.miembroUid;
    if (!idValido(miembroUid)) throw new L.ErrorEquipo('invalid-argument', 'Persona inválida.');
    await db.runTransaction(async (tx) => {
      const ref = db.collection('membresias').doc(miembroUid);
      const membresia = datos(await tx.get(ref));
      L.comprobarPuedeRevocar({ uid, miembroUid, membresia });
      await terminarMembresia(tx, db, ref, membresia, 'revocada', uid, Timestamp.fromMillis(ahora()));
    }, { maxAttempts: MAX_INTENTOS });
    await avisarSinFallar(avisar, miembroUid, 'Cambio en tu equipo', 'Ya no formás parte del equipo del albergue.');
    return { ok: true };
  } catch (e) {
    throw aHttps(e);
  }
}

async function salirDelEquipoHandler(request, { db = getFirestore(), ahora = Date.now, avisar = avisarPorDefecto } = {}) {
  try {
    const { uid, email } = comprobarSesion(request);
    L.validarPayload(request.data ?? {}, []);
    const r = await db.runTransaction(async (tx) => {
      const ref = db.collection('membresias').doc(uid);
      const membresia = datos(await tx.get(ref));
      L.comprobarPuedeSalir({ membresia });
      await terminarMembresia(tx, db, ref, membresia, 'salio', uid, Timestamp.fromMillis(ahora()));
      return { albergueId: membresia.albergueId, nombre: membresia.nombre };
    }, { maxAttempts: MAX_INTENTOS });
    await avisarSinFallar(avisar, r.albergueId, 'Cambio en tu equipo', `${r.nombre || email} salió de tu equipo.`);
    return { ok: true };
  } catch (e) {
    throw aHttps(e);
  }
}

/**
 * La responsable decide si un hogar de su red lo ve el equipo. Es el único
 * camino que escribe `visibleEquipo` y `revisionEquipo` (las reglas se lo
 * prohíben a la app). Sirve también para resolver los hogares dudosos que
 * bloquean las invitaciones: cualquier decisión cuenta como revisión.
 */
async function revisarHogarEquipoHandler(request, { db = getFirestore(), ahora = Date.now } = {}) {
  try {
    const { uid } = comprobarSesion(request);
    L.validarPayload(request.data, ['hogarId', 'decision']);
    const { hogarId, decision } = request.data;
    if (!idValido(hogarId)) throw new L.ErrorEquipo('invalid-argument', 'Hogar inválido.');
    await db.runTransaction(async (tx) => {
      const usuario = datos(await tx.get(db.collection('usuarios').doc(uid)));
      const ref = db.collection('hogaresDePaso').doc(hogarId);
      const hogar = datos(await tx.get(ref));
      L.comprobarPuedeRevisarHogar({ uid, usuario, hogar, decision });
      tx.update(ref, {
        revisionEquipo: { decision, por: uid, en: Timestamp.fromMillis(ahora()) },
        visibleEquipo: decision === 'compartir',
      });
    }, { maxAttempts: MAX_INTENTOS });
    return { ok: true, visibleEquipo: decision === 'compartir' };
  } catch (e) {
    throw aHttps(e);
  }
}

// ─── Eliminación de cuenta (la usa eliminar_cuenta.js) ───────────────────

/** Mensaje si la cuenta [uid] es responsable de un equipo con gente; si no, null. */
async function bloqueoEquipoAlEliminar(db, uid, ahora = Date.now) {
  const [equipoSnap, pendientes] = await Promise.all([
    db.collection('equipos').doc(uid).get(),
    db.collection('invitaciones').where('albergueId', '==', uid).where('estado', '==', 'pendiente').get(),
  ]);
  const t = ahora();
  return L.bloqueoEliminarCuenta({
    miembrosActivos: contador(equipoSnap),
    invitacionesVigentes: pendientes.docs.filter((d) => L.invitacionVigente(d.data(), t)).length,
  });
}

/**
 * Borra lo del equipo que tiene datos de esta persona: su membresía (con
 * su nombre y correo, bajando el contador si estaba activa), las
 * invitaciones a su correo y, si era responsable sin equipo, su contador y
 * sus invitaciones viejas. No toca a ninguna otra persona: las membresías
 * de otros que alguna vez estuvieron en su equipo son de ellas.
 * Idempotente: se puede volver a correr si algo se corta.
 */
async function limpiarEquipoAlEliminar(db, uid, email, ahora = Date.now) {
  await db.runTransaction(async (tx) => {
    const ref = db.collection('membresias').doc(uid);
    const membresia = datos(await tx.get(ref));
    if (L.membresiaActiva(membresia)) {
      const equipoRef = db.collection('equipos').doc(membresia.albergueId);
      const equipoSnap = await tx.get(equipoRef);
      tx.set(equipoRef, {
        miembrosActivos: L.restarMiembro(contador(equipoSnap)), actualizadoEn: Timestamp.fromMillis(ahora()),
      }, { merge: true });
    }
    if (membresia) tx.delete(ref);
  }, { maxAttempts: MAX_INTENTOS });

  const consultas = [db.collection('invitaciones').where('albergueId', '==', uid).get()];
  const correo = L.normalizarEmail(email);
  if (correo) consultas.push(db.collection('invitaciones').where('emailDestino', '==', correo).get());
  const refs = new Map();
  for (const snap of await Promise.all(consultas)) snap.docs.forEach((d) => refs.set(d.id, d.ref));
  const lista = [...refs.values()];
  for (let i = 0; i < lista.length; i += 400) {
    const batch = db.batch();
    lista.slice(i, i + 400).forEach((r) => batch.delete(r));
    await batch.commit();
  }
  await db.collection('equipos').doc(uid).delete();
}

// Misma región que el resto de las Functions (europe-west1).
const OPCIONES = { region: 'europe-west1' };
exports.invitarMiembro = onCall(OPCIONES, (request) => invitarMiembroHandler(request));
exports.aceptarInvitacion = onCall(OPCIONES, (request) => aceptarInvitacionHandler(request));
exports.rechazarInvitacion = onCall(OPCIONES, (request) => rechazarInvitacionHandler(request));
exports.cancelarInvitacion = onCall(OPCIONES, (request) => cancelarInvitacionHandler(request));
exports.revocarMiembro = onCall(OPCIONES, (request) => revocarMiembroHandler(request));
exports.salirDelEquipo = onCall(OPCIONES, (request) => salirDelEquipoHandler(request));
exports.revisarHogarEquipo = onCall(OPCIONES, (request) => revisarHogarEquipoHandler(request));

exports.bloqueoEquipoAlEliminar = bloqueoEquipoAlEliminar;
exports.limpiarEquipoAlEliminar = limpiarEquipoAlEliminar;

// Para las pruebas.
exports.invitarMiembroHandler = invitarMiembroHandler;
exports.aceptarInvitacionHandler = aceptarInvitacionHandler;
exports.rechazarInvitacionHandler = rechazarInvitacionHandler;
exports.cancelarInvitacionHandler = cancelarInvitacionHandler;
exports.revocarMiembroHandler = revocarMiembroHandler;
exports.salirDelEquipoHandler = salirDelEquipoHandler;
exports.revisarHogarEquipoHandler = revisarHogarEquipoHandler;
exports.leerHogaresPendientes = leerHogaresPendientes;
exports.CAMPOS_HOGAR = CAMPOS_HOGAR;
