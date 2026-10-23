const { test, describe, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');
const E = require('../equipo');

// Gestión del equipo contra el EMULADOR de Firestore: rechazar y cancelar
// invitaciones, quitar a alguien, salir del equipo, decidir qué hogares ve
// el equipo, la limpieza al eliminar una cuenta y los avisos push.
//
// Mismas condiciones que equipo.emulador.test.js: solo con el emulador local
// y un proyecto "demo-". Cómo correrlas:
//
//   firebase emulators:exec --only firestore --project demo-equipo-test \
//     "node --test functions/test/equipo_gestion.emulador.test.js"

const HOST = process.env.FIRESTORE_EMULATOR_HOST || '';
const EMULADOR_LOCAL = /^(127\.0\.0\.1|localhost|\[::1\]):\d+$/.test(HOST);
const SIN_EMULADOR = EMULADOR_LOCAL ? false : 'necesita el emulador de Firestore local (FIRESTORE_EMULATOR_HOST)';

const AHORA = Date.UTC(2026, 9, 23, 12, 0, 0);
const DIA = 24 * 60 * 60 * 1000;
const ts = (ms) => Timestamp.fromMillis(ms);

let app;
let db;
let n = 0;
// El pid va en el id: los archivos de prueba corren en paralelo contra el
// mismo emulador, y dos procesos pueden empezar en el mismo milisegundo.
const nuevoId = (p) => `${p}_${process.pid}_${Date.now().toString(36)}_${++n}`;

const sesion = (uid, email, { verificado = true, nombre = 'Ana' } = {}) =>
  ({ uid, token: { email, email_verified: verificado, name: nombre } });
const correoDe = (uid) => `${uid}@mail.com`.toLowerCase();

/** Avisos capturados en vez de mandados. */
function buzon() {
  const enviados = [];
  return { enviados, avisar: async (uid, titulo, cuerpo) => { enviados.push({ uid, titulo, cuerpo }); } };
}
const silencio = { avisar: async () => {}, buscarUid: async () => null };

const llamar = (handler, uid, data, deps = {}, opciones) =>
  handler({ auth: sesion(uid, correoDe(uid), opciones), data }, { db, ahora: () => AHORA, ...silencio, ...deps });

const poner = (col, id, data) => db.collection(col).doc(id).set(data);
const leer = async (col, id) => {
  const s = await db.collection(col).doc(id).get();
  return s.exists ? s.data() : undefined;
};
const responsable = (uid, extra = {}) => poner('usuarios', uid, { roles: ['albergue'], albergueNombre: 'La Perla', ...extra });

async function falla(promesa, code) {
  await assert.rejects(promesa, (e) => {
    assert.equal(e.code, code, `se esperaba ${code}, llegó ${e.code}: ${e.message}`);
    return true;
  });
}

/** Responsable con una miembro activa, por el camino real (invitar + aceptar). */
async function equipoConMiembro() {
  const resp = nuevoId('resp');
  const miembro = nuevoId('miembro');
  await responsable(resp);
  const { invitacionId } = await llamar(E.invitarMiembroHandler, resp, { email: correoDe(miembro) });
  await llamar(E.aceptarInvitacionHandler, miembro, { invitacionId });
  return { resp, miembro, invitacionId };
}

describe('gestión del equipo con el emulador', { skip: SIN_EMULADOR }, () => {
  before(() => {
    app = initializeApp({ projectId: 'demo-equipo-test' }, 'equipo-gestion');
    db = getFirestore(app);
    assert.ok(['127.0.0.1', 'localhost', '[::1]', '::1'].includes(db._settings.servicePath), 'el cliente no apunta al emulador local');
  });
  after(async () => { if (app) await deleteApp(app); });

  describe('avisos', () => {
    test('invitar guarda el nombre del albergue y avisa a la persona si ya tiene cuenta', async () => {
      const resp = nuevoId('resp');
      await responsable(resp);
      const b = buzon();
      const r = await llamar(E.invitarMiembroHandler, resp, { email: 'ana@mail.com' },
          { avisar: b.avisar, buscarUid: async (email) => (email === 'ana@mail.com' ? 'uid_ana' : null) });
      assert.equal((await leer('invitaciones', r.invitacionId)).albergueNombre, 'La Perla');
      assert.equal(b.enviados.length, 1);
      assert.equal(b.enviados[0].uid, 'uid_ana');
      assert.match(b.enviados[0].cuerpo, /La Perla te invitó/);
    });
    test('sin cuenta con ese correo no se avisa a nadie, y la respuesta no lo revela', async () => {
      const resp = nuevoId('resp');
      await responsable(resp);
      const b = buzon();
      const r = await llamar(E.invitarMiembroHandler, resp, { email: 'nadie@mail.com' }, { avisar: b.avisar });
      assert.deepEqual(Object.keys(r).sort(), ['expiraEn', 'invitacionId']);
      assert.equal(b.enviados.length, 0);
    });
    test('si el aviso falla, la invitación queda hecha igual', async () => {
      const resp = nuevoId('resp');
      await responsable(resp);
      const r = await llamar(E.invitarMiembroHandler, resp, { email: 'ana@mail.com' },
          { avisar: async () => { throw new Error('FCM caído'); }, buscarUid: async () => 'uid_ana' });
      assert.equal((await leer('invitaciones', r.invitacionId)).estado, 'pendiente');
    });
    test('aceptar avisa a la responsable', async () => {
      const resp = nuevoId('resp');
      const miembro = nuevoId('miembro');
      await responsable(resp);
      const { invitacionId } = await llamar(E.invitarMiembroHandler, resp, { email: correoDe(miembro) });
      const b = buzon();
      await llamar(E.aceptarInvitacionHandler, miembro, { invitacionId }, { avisar: b.avisar });
      assert.deepEqual(b.enviados.map((x) => x.uid), [resp]);
    });
  });

  describe('rechazarInvitacion', () => {
    test('la persona invitada rechaza: queda rechazada y ya no se puede aceptar', async () => {
      const resp = nuevoId('resp'); const ana = nuevoId('ana');
      await responsable(resp);
      const { invitacionId } = await llamar(E.invitarMiembroHandler, resp, { email: correoDe(ana) });
      await llamar(E.rechazarInvitacionHandler, ana, { invitacionId });
      assert.equal((await leer('invitaciones', invitacionId)).estado, 'rechazada');
      await falla(llamar(E.aceptarInvitacionHandler, ana, { invitacionId }), 'failed-precondition');
    });
    test('otra persona no puede rechazarla ni enterarse de nada', async () => {
      const resp = nuevoId('resp'); const ana = nuevoId('ana');
      await responsable(resp);
      const { invitacionId } = await llamar(E.invitarMiembroHandler, resp, { email: correoDe(ana) });
      await falla(llamar(E.rechazarInvitacionHandler, nuevoId('otra'), { invitacionId }), 'not-found');
      await falla(llamar(E.rechazarInvitacionHandler, resp, { invitacionId }), 'not-found');
      assert.equal((await leer('invitaciones', invitacionId)).estado, 'pendiente');
    });
    test('campos de más o id inválido: rechazo', async () => {
      const ana = nuevoId('ana');
      await falla(llamar(E.rechazarInvitacionHandler, ana, { invitacionId: 'x', estado: 'aceptada' }), 'invalid-argument');
      await falla(llamar(E.rechazarInvitacionHandler, ana, { invitacionId: 'a/b' }), 'invalid-argument');
      await falla(llamar(E.rechazarInvitacionHandler, ana, { invitacionId: 'no-existe' }), 'not-found');
    });
  });

  describe('cancelarInvitacion', () => {
    test('la responsable cancela: libera el lugar y se puede volver a invitar a ese correo', async () => {
      const resp = nuevoId('resp');
      await responsable(resp);
      const { invitacionId } = await llamar(E.invitarMiembroHandler, resp, { email: 'ana@mail.com' });
      await llamar(E.cancelarInvitacionHandler, resp, { invitacionId });
      assert.equal((await leer('invitaciones', invitacionId)).estado, 'cancelada');
      await llamar(E.invitarMiembroHandler, resp, { email: 'ana@mail.com' });
    });
    test('una invitación cancelada no se puede aceptar', async () => {
      const resp = nuevoId('resp'); const ana = nuevoId('ana');
      await responsable(resp);
      const { invitacionId } = await llamar(E.invitarMiembroHandler, resp, { email: correoDe(ana) });
      await llamar(E.cancelarInvitacionHandler, resp, { invitacionId });
      await falla(llamar(E.aceptarInvitacionHandler, ana, { invitacionId }), 'failed-precondition');
    });
    test('otra responsable o la invitada no pueden cancelarla; una ya aceptada tampoco', async () => {
      const { resp, invitacionId, miembro } = await equipoConMiembro();
      const otra = nuevoId('resp');
      await responsable(otra);
      await falla(llamar(E.cancelarInvitacionHandler, otra, { invitacionId }), 'not-found');
      await falla(llamar(E.cancelarInvitacionHandler, miembro, { invitacionId }), 'not-found');
      await falla(llamar(E.cancelarInvitacionHandler, resp, { invitacionId }), 'failed-precondition');
    });
  });

  describe('revocarMiembro', () => {
    test('la responsable quita a una miembro: membresía revocada, contador en 0 y aviso', async () => {
      const { resp, miembro } = await equipoConMiembro();
      const b = buzon();
      await llamar(E.revocarMiembroHandler, resp, { miembroUid: miembro }, { avisar: b.avisar });
      const m = await leer('membresias', miembro);
      assert.equal(m.estado, 'revocada');
      assert.equal(m.terminadaPor, resp);
      assert.equal(m.terminadaEn.toMillis(), AHORA);
      assert.equal((await leer('equipos', resp)).miembrosActivos, 0);
      assert.deepEqual(b.enviados.map((x) => x.uid), [miembro]);
    });
    test('quitarse a sí misma, a alguien de otro albergue o a alguien ya quitado: rechazo', async () => {
      const { resp, miembro } = await equipoConMiembro();
      const otro = await equipoConMiembro();
      await falla(llamar(E.revocarMiembroHandler, resp, { miembroUid: resp }), 'invalid-argument');
      await falla(llamar(E.revocarMiembroHandler, resp, { miembroUid: otro.miembro }), 'not-found');
      assert.equal((await leer('membresias', otro.miembro)).estado, 'activa');
      await llamar(E.revocarMiembroHandler, resp, { miembroUid: miembro });
      await falla(llamar(E.revocarMiembroHandler, resp, { miembroUid: miembro }), 'not-found');
      assert.equal((await leer('equipos', resp)).miembrosActivos, 0);
    });
    test('una miembro no puede quitar a otra', async () => {
      const { resp, miembro } = await equipoConMiembro();
      const segunda = nuevoId('m2');
      const { invitacionId } = await llamar(E.invitarMiembroHandler, resp, { email: correoDe(segunda) });
      await llamar(E.aceptarInvitacionHandler, segunda, { invitacionId });
      await falla(llamar(E.revocarMiembroHandler, miembro, { miembroUid: segunda }), 'not-found');
      assert.equal((await leer('equipos', resp)).miembrosActivos, 2);
    });
    test('la persona quitada puede ser invitada de nuevo y volver', async () => {
      const { resp, miembro } = await equipoConMiembro();
      await llamar(E.revocarMiembroHandler, resp, { miembroUid: miembro });
      const { invitacionId } = await llamar(E.invitarMiembroHandler, resp, { email: correoDe(miembro) });
      await llamar(E.aceptarInvitacionHandler, miembro, { invitacionId });
      assert.equal((await leer('membresias', miembro)).estado, 'activa');
      assert.equal((await leer('equipos', resp)).miembrosActivos, 1);
    });
  });

  describe('salirDelEquipo', () => {
    test('una miembro sale: membresía "salio", contador en 0 y aviso a la responsable', async () => {
      const { resp, miembro } = await equipoConMiembro();
      const b = buzon();
      await llamar(E.salirDelEquipoHandler, miembro, null, { avisar: b.avisar });
      const m = await leer('membresias', miembro);
      assert.equal(m.estado, 'salio');
      assert.equal(m.terminadaPor, miembro);
      assert.equal((await leer('equipos', resp)).miembrosActivos, 0);
      assert.deepEqual(b.enviados.map((x) => x.uid), [resp]);
    });
    test('sin equipo, o mandando datos: rechazo', async () => {
      await falla(llamar(E.salirDelEquipoHandler, nuevoId('nadie'), null), 'failed-precondition');
      const { miembro } = await equipoConMiembro();
      await falla(llamar(E.salirDelEquipoHandler, miembro, { albergueId: 'x' }), 'invalid-argument');
      assert.equal((await leer('membresias', miembro)).estado, 'activa');
    });
    test('salir y ser quitada a la vez: termina una sola vez y el contador no baja de 0', async () => {
      const { resp, miembro } = await equipoConMiembro();
      const r = await Promise.allSettled([
        llamar(E.salirDelEquipoHandler, miembro, null),
        llamar(E.revocarMiembroHandler, resp, { miembroUid: miembro }),
      ]);
      assert.equal(r.filter((x) => x.status === 'fulfilled').length, 1, 'gana una sola de las dos');
      assert.ok(['salio', 'revocada'].includes((await leer('membresias', miembro)).estado));
      assert.equal((await leer('equipos', resp)).miembrosActivos, 0);
    });
  });

  describe('revisarHogarEquipo', () => {
    const hogar = async (albergueId, extra = {}) => {
      const id = nuevoId('hogar');
      await poner('hogaresDePaso', id, { albergueId, nombre: 'Familia Ruiz', telefono: '300', ...extra });
      return id;
    };
    test('compartir: visibleEquipo true y revisión completa; no_compartir: false', async () => {
      const resp = nuevoId('resp');
      await responsable(resp);
      const h1 = await hogar(resp);
      const h2 = await hogar(resp, { visibleEquipo: true });
      await llamar(E.revisarHogarEquipoHandler, resp, { hogarId: h1, decision: 'compartir' });
      await llamar(E.revisarHogarEquipoHandler, resp, { hogarId: h2, decision: 'no_compartir' });
      const a = await leer('hogaresDePaso', h1);
      assert.equal(a.visibleEquipo, true);
      assert.deepEqual({ decision: a.revisionEquipo.decision, por: a.revisionEquipo.por }, { decision: 'compartir', por: resp });
      assert.equal(a.revisionEquipo.en.toMillis(), AHORA);
      assert.equal(a.nombre, 'Familia Ruiz', 'no toca los datos de la familia');
      assert.equal((await leer('hogaresDePaso', h2)).visibleEquipo, false);
    });
    test('revisar los hogares dudosos destraba las invitaciones', async () => {
      const resp = nuevoId('resp');
      await responsable(resp, { roles: ['albergue', 'rescatista'] });
      const viejo = await hogar(resp, { creadoEn: ts(Date.UTC(2026, 5, 1)) });
      await falla(llamar(E.invitarMiembroHandler, resp, { email: 'ana@mail.com' }), 'failed-precondition');
      await llamar(E.revisarHogarEquipoHandler, resp, { hogarId: viejo, decision: 'no_compartir' });
      await llamar(E.invitarMiembroHandler, resp, { email: 'ana@mail.com' });
    });
    test('hogar de otro albergue, una miembro o quien no es responsable: rechazo sin cambios', async () => {
      const { resp, miembro } = await equipoConMiembro();
      const otra = nuevoId('resp');
      await responsable(otra);
      const h = await hogar(resp);
      await falla(llamar(E.revisarHogarEquipoHandler, otra, { hogarId: h, decision: 'compartir' }), 'not-found');
      await poner('usuarios', miembro, { roles: ['adoptante'] });
      await falla(llamar(E.revisarHogarEquipoHandler, miembro, { hogarId: h, decision: 'compartir' }), 'permission-denied');
      assert.equal((await leer('hogaresDePaso', h)).visibleEquipo, undefined);
    });
    test('decisión inventada o campos de más: rechazo', async () => {
      const resp = nuevoId('resp');
      await responsable(resp);
      const h = await hogar(resp);
      await falla(llamar(E.revisarHogarEquipoHandler, resp, { hogarId: h, decision: 'si' }), 'invalid-argument');
      await falla(llamar(E.revisarHogarEquipoHandler, resp, { hogarId: h, decision: 'compartir', visibleEquipo: true }), 'invalid-argument');
      await falla(llamar(E.revisarHogarEquipoHandler, resp, { hogarId: 'no-existe', decision: 'compartir' }), 'not-found');
    });
  });

  describe('eliminación de cuenta', () => {
    test('responsable con miembros o con una invitación vigente: bloqueada; vencida o sin equipo: no', async () => {
      const { resp } = await equipoConMiembro();
      assert.match(await E.bloqueoEquipoAlEliminar(db, resp, () => AHORA), /quitá a las personas del equipo/);
      const conInv = nuevoId('resp');
      await responsable(conInv);
      await llamar(E.invitarMiembroHandler, conInv, { email: 'ana@mail.com' });
      assert.ok(await E.bloqueoEquipoAlEliminar(db, conInv, () => AHORA));
      assert.equal(await E.bloqueoEquipoAlEliminar(db, conInv, () => AHORA + 8 * DIA), null, 'la invitación ya venció');
      assert.equal(await E.bloqueoEquipoAlEliminar(db, nuevoId('nadie'), () => AHORA), null);
    });
    test('una miembro que elimina su cuenta: se borra su membresía y el equipo deja de contarla', async () => {
      const { resp, miembro } = await equipoConMiembro();
      await E.limpiarEquipoAlEliminar(db, miembro, correoDe(miembro), () => AHORA);
      assert.equal(await leer('membresias', miembro), undefined);
      assert.equal((await leer('equipos', resp)).miembrosActivos, 0);
      assert.equal(await E.bloqueoEquipoAlEliminar(db, resp, () => AHORA), null);
    });
    test('se borran las invitaciones a su correo; las de otras personas quedan', async () => {
      const resp = nuevoId('resp');
      await responsable(resp);
      const a = await llamar(E.invitarMiembroHandler, resp, { email: 'Ana@Mail.com' });
      const b = await llamar(E.invitarMiembroHandler, resp, { email: 'bea@mail.com' });
      await E.limpiarEquipoAlEliminar(db, nuevoId('ana'), 'ANA@mail.com', () => AHORA);
      assert.equal(await leer('invitaciones', a.invitacionId), undefined);
      assert.equal((await leer('invitaciones', b.invitacionId)).estado, 'pendiente');
    });
    test('responsable sin equipo: se van su contador y sus invitaciones viejas; las membresías de otras personas no', async () => {
      const { resp, miembro } = await equipoConMiembro();
      await llamar(E.revocarMiembroHandler, resp, { miembroUid: miembro });
      await E.limpiarEquipoAlEliminar(db, resp, correoDe(resp), () => AHORA);
      assert.equal(await leer('equipos', resp), undefined);
      const quedan = await db.collection('invitaciones').where('albergueId', '==', resp).get();
      assert.equal(quedan.size, 0);
      assert.equal((await leer('membresias', miembro)).estado, 'revocada', 'es de la otra persona');
    });
    test('se puede volver a correr sin romper nada', async () => {
      const { resp, miembro } = await equipoConMiembro();
      await E.limpiarEquipoAlEliminar(db, miembro, correoDe(miembro), () => AHORA);
      await E.limpiarEquipoAlEliminar(db, miembro, correoDe(miembro), () => AHORA);
      assert.equal((await leer('equipos', resp)).miembrosActivos, 0);
    });
  });
});
