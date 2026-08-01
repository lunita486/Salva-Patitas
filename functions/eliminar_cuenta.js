const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
const { ESTADOS_ACTIVOS, motivoBloqueo, clasificarSolicitud, clasificarChat } = require('./eliminar_cuenta_logica');

const SENTINEL = 'Usuario eliminado';

async function borrarEnLotes(db, refs) {
  for (let i = 0; i < refs.length; i += 500) {
    const batch = db.batch();
    refs.slice(i, i + 500).forEach((ref) => batch.delete(ref));
    await batch.commit();
  }
}

// A diferencia de onRescateEliminado (que trae los favoritos de un solo
// get(), rara vez son muchos), una subcolección de mensajes de un chat
// viejo puede tener más docs de los que conviene traer en un solo viaje —
// se pagina de a `tamanoLote` hasta vaciarla del todo.
async function borrarSubcoleccion(colRef, tamanoLote = 400) {
  for (;;) {
    const snap = await colRef.limit(tamanoLote).get();
    if (snap.empty) return;
    const batch = colRef.firestore.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    if (snap.size < tamanoLote) return;
  }
}

// Dos consultas, no una: `adoptanteIdEnProceso` y `rescatistaId` son
// campos distintos, así que no se puede pedir "cualquiera de los dos" en
// una sola query de Firestore. Requiere los índices compuestos agregados
// en firestore.indexes.json (adoptanteIdEnProceso+estadoAdopcion,
// rescatistaId+estadoAdopcion).
async function chequearBloqueo(db, uid) {
  const [comoAdoptante, comoRescatista] = await Promise.all([
    db.collection('rescates').where('adoptanteIdEnProceso', '==', uid)
      .where('estadoAdopcion', 'in', ESTADOS_ACTIVOS).limit(1).get(),
    db.collection('rescates').where('rescatistaId', '==', uid)
      .where('estadoAdopcion', 'in', ESTADOS_ACTIVOS).limit(1).get(),
  ]);
  return motivoBloqueo({
    tieneComoAdoptante: !comoAdoptante.empty,
    tieneComoRescatista: !comoRescatista.empty,
  });
}

// Elimina la cuenta que llama (SIEMPRE `request.auth.uid` — nunca un uid
// que venga de `request.data`, para que nadie pueda pedir borrar la
// cuenta de otra persona). Ver el plan de esta función
// (C:\Users\Eliza\.claude\plans\joyful-waddling-squid.md) para el porqué
// completo de cada decisión de negocio.
//
// Todo lo que borra/actualiza acá es idempotente (borrar o pisar algo que
// ya no existe/ya quedó anonimizado no falla) — si algo se corta a mitad
// de camino, reintentar más tarde es seguro. Por eso el borrado de la
// cuenta de Firebase Auth es lo ÚLTIMO que se hace, y solo si todo lo
// demás terminó bien: es el único paso de los dos que no se puede
// reintentar solo (con la cuenta de Auth borrada, `request.auth` no
// vuelve a existir para poder invocar esta función de nuevo).
// Mismo region que el resto de functions/index.js (europe-west1) — sin
// esto, por defecto cae en us-central1, una región nueva para este
// proyecto que necesita su propia política de limpieza de Artifact
// Registry (costo chico, pero evitable).
exports.eliminarCuenta = onCall({ timeoutSeconds: 300, memory: '256MiB', region: 'europe-west1' }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Iniciá sesión de nuevo e intentá otra vez.');
  const uid = request.auth.uid;
  const db = getFirestore();

  const bloqueo = await chequearBloqueo(db, uid);
  if (bloqueo) throw new HttpsError('failed-precondition', bloqueo);

  try {
    await Promise.all([
      // usuarios/{uid} incluye fcmToken, así que se va con el resto del doc.
      db.collection('usuarios').doc(uid).delete(),
      db.collection('preferencias').doc(uid).delete(),

      (async () => {
        const s = await db.collection('favoritos').where('adoptanteId', '==', uid).get();
        await borrarEnLotes(db, s.docs.map((d) => d.ref));
      })(),

      // Animales propios que NO están en un estado activo (el chequeo de
      // bloqueo de arriba ya debería haber cortado esto antes, este filtro
      // es solo defensivo contra una carrera entre ese chequeo y este
      // borrado). Borrar el doc dispara onRescateEliminado, que ya limpia
      // las fotos de Storage y los favoritos huérfanos por su cuenta — no
      // se duplica esa lógica acá.
      (async () => {
        const s = await db.collection('rescates').where('rescatistaId', '==', uid).get();
        const refs = s.docs
          .filter((d) => !ESTADOS_ACTIVOS.includes(d.data().estadoAdopcion))
          .map((d) => d.ref);
        await borrarEnLotes(db, refs);
      })(),

      (async () => {
        const s = await db.collection('servicios').where('aliadoId', '==', uid).get();
        await borrarEnLotes(db, s.docs.map((d) => d.ref));
      })(),

      // adoptanteId==uid (esta cuenta ayudó como hogar de paso en la red de
      // algún albergue) o albergueId==uid (es el roster propio de esta
      // cuenta, si es albergue) — pueden coincidir ambas consultas en un
      // mismo doc solo en teoría, por eso se deduplica por id antes de borrar.
      (async () => {
        const [a, b] = await Promise.all([
          db.collection('hogaresDePaso').where('adoptanteId', '==', uid).get(),
          db.collection('hogaresDePaso').where('albergueId', '==', uid).get(),
        ]);
        const refs = new Map();
        [...a.docs, ...b.docs].forEach((d) => refs.set(d.id, d.ref));
        await borrarEnLotes(db, [...refs.values()]);
      })(),
    ]);

    // solicitudes y chats comparten "cuáles quedaron aprobadas" (para
    // saber qué chat corresponde a una adopción ya concretada), así que se
    // resuelven solicitudes primero y ese resultado alimenta la
    // clasificación de chats.
    const [comoAdoptanteSol, comoRescatistaSol] = await Promise.all([
      db.collection('solicitudes').where('adoptanteId', '==', uid).get(),
      db.collection('solicitudes').where('rescatistaId', '==', uid).get(),
    ]);
    const solicitudes = new Map();
    [...comoAdoptanteSol.docs, ...comoRescatistaSol.docs].forEach((d) => solicitudes.set(d.id, d));

    const clavesAprobadas = new Set();
    const aBorrarSol = [];
    const aAnonimizarSol = [];
    for (const doc of solicitudes.values()) {
      const s = doc.data();
      if (s.estado === 'aprobada') clavesAprobadas.add(`${s.rescateId || ''}_${s.adoptanteId || ''}`);
      const accion = clasificarSolicitud(s, uid);
      if (accion === 'borrar') aBorrarSol.push(doc.ref);
      if (accion === 'anonimizar') aAnonimizarSol.push(doc.ref);
    }
    await borrarEnLotes(db, aBorrarSol);
    await Promise.all(aAnonimizarSol.map((ref) => ref.update({
      nombre: SENTINEL,
      email: SENTINEL,
      integrantes: FieldValue.delete(),
      horasFuera: FieldValue.delete(),
      vivienda: FieldValue.delete(),
      tieneNinos: FieldValue.delete(),
      tieneMascotas: FieldValue.delete(),
      experienciaPrevia: FieldValue.delete(),
      motivacion: FieldValue.delete(),
    })));

    const [comoAdoptanteChat, comoRescatistaChat] = await Promise.all([
      db.collection('chats').where('adoptanteId', '==', uid).get(),
      db.collection('chats').where('rescatistaId', '==', uid).get(),
    ]);
    const chats = new Map();
    [...comoAdoptanteChat.docs, ...comoRescatistaChat.docs].forEach((d) => chats.set(d.id, d));

    for (const doc of chats.values()) {
      const c = doc.data();
      // Los mensajes SIEMPRE se borran aparte, en los dos casos: son texto
      // libre (la persona puede haber escrito su teléfono, dirección,
      // etc. adentro), no hay forma segura de "anonimizarlos" campo por
      // campo como con solicitudes. Firestore tampoco borra subcolecciones
      // solo al borrar el doc padre, así que esto hace falta igual aunque
      // el chat se vaya a borrar entero abajo.
      await borrarSubcoleccion(doc.ref.collection('mensajes'));

      const accion = clasificarChat(c, clavesAprobadas);
      if (accion === 'anonimizar') {
        const cambios = {};
        if (c.adoptanteId === uid) cambios.adoptanteNombre = SENTINEL;
        if (c.rescatistaId === uid) cambios.rescatista = SENTINEL;
        await doc.ref.update(cambios);
      } else {
        await doc.ref.delete();
      }
    }
  } catch (e) {
    console.error(`eliminarCuenta falló a mitad de camino para ${uid}:`, e);
    throw new HttpsError('internal', 'No pudimos eliminar tu cuenta por completo. Volvé a intentar en un momento.');
  }

  // Repite el chequeo de bloqueo (barato, 2 queries) justo antes del paso
  // irreversible, por si algo cambió mientras corría la cascada de arriba
  // (ej. alguien aprobó un hogar de paso para esta cuenta en ese ratito).
  const bloqueoFinal = await chequearBloqueo(db, uid);
  if (bloqueoFinal) throw new HttpsError('failed-precondition', bloqueoFinal);

  await getAuth().deleteUser(uid);
  return { ok: true };
});
