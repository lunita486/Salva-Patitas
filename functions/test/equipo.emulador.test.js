const { test, describe, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');
const E = require('../equipo');

// invitarMiembro y aceptarInvitacion contra el EMULADOR de Firestore.
//
// Solo corre con FIRESTORE_EMULATOR_HOST apuntando a esta máquina, y con un
// proyecto "demo-", que Google reserva para emuladores: no existe en la nube.
// Sin emulador, `npm test` las salta (y lo dice). Cómo correrlas:
//
//   firebase emulators:exec --only firestore --project demo-equipo-test \
//     "node --test functions/test/equipo.emulador.test.js"
//
// Las Functions se llaman directo (el handler), con una sesión armada a mano.
// Cada prueba usa ids propios, así no se pisan entre sí.

const HOST = process.env.FIRESTORE_EMULATOR_HOST || '';
const EMULADOR_LOCAL = /^(127\.0\.0\.1|localhost|\[::1\]):\d+$/.test(HOST);
const PROYECTO = 'demo-equipo-test';
const SIN_EMULADOR = EMULADOR_LOCAL ? false : 'necesita el emulador de Firestore local (FIRESTORE_EMULATOR_HOST)';

const AHORA = Date.UTC(2026, 9, 22, 12, 0, 0);
const DIA = 24 * 60 * 60 * 1000;
const ts = (ms) => Timestamp.fromMillis(ms);
const fecha = (anio, mes, dia) => Timestamp.fromMillis(Date.UTC(anio, mes - 1, dia));

let app;
let db;
let n = 0;
// El pid va en el id: los archivos de prueba corren en paralelo contra el
// mismo emulador, y dos procesos pueden empezar en el mismo milisegundo.
const nuevoId = (prefijo) => `${prefijo}_${process.pid}_${Date.now().toString(36)}_${++n}`;

const sesion = (uid, email, { verificado = true, nombre = 'Ana' } = {}) =>
  ({ uid, token: { email, email_verified: verificado, name: nombre } });
// Sin push en estas pruebas: los avisos tienen las suyas en equipo_gestion.
const sinAvisos = { avisar: async () => {}, buscarUid: async () => null };
const invitar = (uid, email, data, opciones) =>
  E.invitarMiembroHandler({ auth: sesion(uid, `${uid}@mail.com`, opciones), data }, { db, ahora: () => AHORA, ...sinAvisos });
const aceptar = (uid, email, data, opciones, ahora = AHORA) =>
  E.aceptarInvitacionHandler({ auth: sesion(uid, email, opciones), data }, { db, ahora: () => ahora, ...sinAvisos });

const poner = (col, id, data) => db.collection(col).doc(id).set(data);
const leer = async (col, id) => (await db.collection(col).doc(id).get()).data();
const responsable = (uid, extra = {}) => poner('usuarios', uid, { roles: ['albergue'], albergueNombre: 'La Perla', ...extra });
const invitacionesDe = async (albergueId) =>
  (await db.collection('invitaciones').where('albergueId', '==', albergueId).get()).docs.map((d) => d.data());

/** La promesa tiene que fallar con ese código de HttpsError. */
async function falla(promesa, code) {
  await assert.rejects(promesa, (e) => {
    assert.equal(e.code, code, `se esperaba ${code}, llegó ${e.code}: ${e.message}`);
    return true;
  });
}

/** Una invitación sembrada a mano, sin pasar por invitarMiembro (vía alternativa). */
async function invitacionSembrada(albergueId, email, extra = {}) {
  const id = nuevoId('inv');
  await poner('invitaciones', id, {
    albergueId, emailDestino: email, estado: 'pendiente', creadaEn: ts(AHORA - DIA),
    expiraEn: ts(AHORA + 6 * DIA), creadaPor: albergueId, aceptadaPor: null, aceptadaEn: null, ...extra,
  });
  return id;
}

describe('equipo con el emulador', { skip: SIN_EMULADOR }, () => {
  before(() => {
    app = initializeApp({ projectId: PROYECTO }, 'equipo-emulador');
    db = getFirestore(app);
    // Seguro extra: si el cliente no apunta a esta máquina, no se corre nada.
    assert.ok(['127.0.0.1', 'localhost', '[::1]', '::1'].includes(db._settings.servicePath), 'el cliente no apunta al emulador local');
  });
  after(async () => { if (app) await deleteApp(app); });

  describe('invitarMiembro', () => {
    test('la responsable invita: invitación pendiente que vence en 7 días', async () => {
      const resp = nuevoId('resp');
      await responsable(resp);
      const r = await invitar(resp, null, { email: '  Ana@Mail.com ' });
      const inv = await leer('invitaciones', r.invitacionId);
      assert.equal(inv.albergueId, resp);
      assert.equal(inv.emailDestino, 'ana@mail.com');
      assert.equal(inv.estado, 'pendiente');
      assert.equal(inv.expiraEn.toMillis() - inv.creadaEn.toMillis(), 7 * DIA);
      assert.equal((await leer('equipos', resp)).miembrosActivos, 0);
    });
    test('sin sesión o con el correo sin verificar: no se crea nada', async () => {
      const resp = nuevoId('resp');
      await responsable(resp);
      await falla(E.invitarMiembroHandler({ data: { email: 'a@mail.com' } }, { db, ahora: () => AHORA }), 'unauthenticated');
      await falla(invitar(resp, null, { email: 'a@mail.com' }, { verificado: false }), 'failed-precondition');
      assert.deepEqual(await invitacionesDe(resp), []);
    });
    test('campos inventados por el cliente: rechazo, no se crea nada', async () => {
      const resp = nuevoId('resp');
      await responsable(resp);
      await falla(invitar(resp, null, { email: 'a@mail.com', sinHogaresDudosos: true }), 'invalid-argument');
      await falla(invitar(resp, null, { email: 'a@mail.com', albergueId: 'otro' }), 'invalid-argument');
      assert.deepEqual(await invitacionesDe(resp), []);
    });
    test('correo inválido o el propio: rechazo', async () => {
      const resp = nuevoId('resp');
      await responsable(resp);
      await falla(invitar(resp, null, { email: 'no-es-correo' }), 'invalid-argument');
      await falla(invitar(resp, null, { email: `${resp}@mail.com` }), 'invalid-argument');
    });
    test('sin perfil de responsable: rechazo', async () => {
      const a = nuevoId('a'); const b = nuevoId('b');
      await poner('usuarios', a, { roles: ['albergue'] });
      await poner('usuarios', b, { roles: ['adoptante', 'rescatista'] });
      await falla(invitar(a, null, { email: 'x@mail.com' }), 'permission-denied');
      await falla(invitar(b, null, { email: 'x@mail.com' }), 'permission-denied');
      await falla(invitar(nuevoId('sinPerfil'), null, { email: 'x@mail.com' }), 'permission-denied');
    });
    test('responsable que también es negocio aliado: rechazo', async () => {
      const resp = nuevoId('resp');
      await responsable(resp, { roles: ['albergue', 'aliado'] });
      await falla(invitar(resp, null, { email: 'x@mail.com' }), 'failed-precondition');
    });
    test('un miembro activo no puede invitar', async () => {
      const resp = nuevoId('resp');
      await responsable(resp);
      await poner('membresias', resp, { albergueId: 'otro', estado: 'activa' });
      await falla(invitar(resp, null, { email: 'x@mail.com' }), 'permission-denied');
    });
    test('invitación repetida al mismo correo: rechazo; si la anterior venció, se puede', async () => {
      const resp = nuevoId('resp');
      await responsable(resp);
      await invitar(resp, null, { email: 'ana@mail.com' });
      await falla(invitar(resp, null, { email: 'ANA@mail.com' }), 'already-exists');
      const resp2 = nuevoId('resp');
      await responsable(resp2);
      await invitacionSembrada(resp2, 'ana@mail.com', { expiraEn: ts(AHORA - 1) });
      await invitar(resp2, null, { email: 'ana@mail.com' });
    });
    test('sin tope: con 30 miembros y 5 invitaciones pendientes se puede seguir invitando', async () => {
      const grande = nuevoId('resp');
      await responsable(grande);
      await poner('equipos', grande, { miembrosActivos: 30 });
      for (const e of ['a', 'b', 'c', 'd', 'e']) await invitacionSembrada(grande, `${e}@mail.com`);
      await invitar(grande, null, { email: 'x@mail.com' });
      assert.equal((await invitacionesDe(grande)).length, 6);
      assert.equal((await leer('equipos', grande)).miembrosActivos, 30, 'invitar no toca el contador');
    });
  });

  describe('hogares de paso: ya no bloquean (fase 2)', () => {
    // Desde la fase 2 el equipo ve todos los hogares del albergue: no hay
    // revisión hogar por hogar ni barrera de "hogares dudosos".
    test('responsable con vida de rescatista y hogares viejos o sin fecha: invita y la invitada acepta', async () => {
      const resp = nuevoId('resp');
      await responsable(resp, { roles: ['albergue', 'rescatista'] });
      await poner('rescates', nuevoId('r'), { rescatistaId: resp, creadoPor: 'rescatista' });
      await poner('hogaresDePaso', nuevoId('h'), { albergueId: resp, nombre: 'Familia Ruiz', creadoEn: fecha(2026, 5, 1) });
      await poner('hogaresDePaso', nuevoId('h'), { albergueId: resp, nombre: 'Familia Gómez' });
      const { invitacionId } = await invitar(resp, null, { email: 'ana@mail.com' });
      const ana = nuevoId('ana');
      await aceptar(ana, 'ana@mail.com', { invitacionId });
      assert.equal((await leer('membresias', ana)).estado, 'activa');
    });
    test('el cliente sigue sin poder mandar campos de más', async () => {
      const resp = nuevoId('resp');
      await responsable(resp);
      const invitacionId = await invitacionSembrada(resp, 'ana@mail.com');
      await falla(invitar(resp, null, { email: 'x@mail.com', hogaresRevisados: ['todos'] }), 'invalid-argument');
      await falla(aceptar(nuevoId('ana'), 'ana@mail.com', { invitacionId, hogaresRevisados: ['todos'] }), 'invalid-argument');
      await falla(aceptar(nuevoId('ana'), 'ana@mail.com', { invitacionId, albergueId: 'otro' }), 'invalid-argument');
    });
    test('las Functions de revisión ya no existen', () => {
      assert.equal(E.revisarHogarEquipo, undefined);
      assert.equal(E.revisarHogarEquipoHandler, undefined);
      assert.equal(E.leerHogaresPendientes, undefined);
    });
  });

  describe('aceptarInvitacion', () => {
    async function invitacionValida() {
      const resp = nuevoId('resp');
      await responsable(resp);
      const { invitacionId } = await invitar(resp, null, { email: 'ana@mail.com' });
      return { resp, invitacionId };
    }

    test('caso válido: membresía activa, sin tocar roles ni recursos personales', async () => {
      const { resp, invitacionId } = await invitacionValida();
      const ana = nuevoId('ana');
      await poner('usuarios', ana, { roles: ['adoptante', 'rescatista'], nombre: 'Ana' });
      const animal = nuevoId('r');
      await poner('rescates', animal, { rescatistaId: ana, creadoPor: 'rescatista', nombre: 'Toby' });
      const r = await aceptar(ana, 'ANA@mail.com', { invitacionId });
      assert.deepEqual(r, { albergueId: resp });
      const m = await leer('membresias', ana);
      assert.equal(m.albergueId, resp);
      assert.equal(m.estado, 'activa');
      assert.equal(m.invitacionId, invitacionId);
      assert.equal((await leer('invitaciones', invitacionId)).estado, 'aceptada');
      assert.equal((await leer('equipos', resp)).miembrosActivos, 1);
      const u = await leer('usuarios', ana);
      assert.deepEqual(u, { roles: ['adoptante', 'rescatista'], nombre: 'Ana' }, 'el perfil queda intacto: ni roles ni trabajaEn');
      assert.deepEqual(await leer('rescates', animal), { rescatistaId: ana, creadoPor: 'rescatista', nombre: 'Toby' }, 'su animal personal sigue siendo suyo');
    });
    test('sin perfil: acepta igual y no se crea un perfil vacío', async () => {
      const { invitacionId } = await invitacionValida();
      const ana = nuevoId('ana');
      await aceptar(ana, 'ana@mail.com', { invitacionId });
      assert.equal(await leer('usuarios', ana), undefined);
    });
    test('correo sin verificar u otro correo: rechazo', async () => {
      const { invitacionId } = await invitacionValida();
      await falla(aceptar(nuevoId('ana'), 'ana@mail.com', { invitacionId }, { verificado: false }), 'failed-precondition');
      await falla(aceptar(nuevoId('otra'), 'otra@mail.com', { invitacionId }), 'permission-denied');
    });
    test('vencida: rechazo y queda marcada como expirada', async () => {
      const { invitacionId } = await invitacionValida();
      await falla(aceptar(nuevoId('ana'), 'ana@mail.com', { invitacionId }, undefined, AHORA + 7 * DIA), 'failed-precondition');
      assert.equal((await leer('invitaciones', invitacionId)).estado, 'expirada');
    });
    test('otro correo con una invitación vencida: no se entera ni la marca', async () => {
      const { invitacionId } = await invitacionValida();
      await falla(aceptar(nuevoId('otra'), 'otra@mail.com', { invitacionId }, undefined, AHORA + 8 * DIA), 'permission-denied');
      assert.equal((await leer('invitaciones', invitacionId)).estado, 'pendiente');
    });
    test('ya aceptada o revocada: rechazo', async () => {
      const { invitacionId } = await invitacionValida();
      await aceptar(nuevoId('ana'), 'ana@mail.com', { invitacionId });
      await falla(aceptar(nuevoId('ana'), 'ana@mail.com', { invitacionId }), 'failed-precondition');
      const resp = nuevoId('resp');
      await responsable(resp);
      const revocada = await invitacionSembrada(resp, 'ana@mail.com', { estado: 'revocada' });
      await falla(aceptar(nuevoId('ana'), 'ana@mail.com', { invitacionId: revocada }), 'failed-precondition');
    });
    test('quien acepta es responsable o negocio aliado: rechazo', async () => {
      const { invitacionId } = await invitacionValida();
      const r1 = nuevoId('r1'); const r2 = nuevoId('r2');
      await poner('usuarios', r1, { roles: ['albergue'] });
      await poner('usuarios', r2, { roles: ['aliado'], aliadoNombre: 'Vet' });
      await falla(aceptar(r1, 'ana@mail.com', { invitacionId }), 'permission-denied');
      await falla(aceptar(r2, 'ana@mail.com', { invitacionId }), 'permission-denied');
    });
    test('ya es miembro activo de otro albergue: rechazo', async () => {
      const { invitacionId } = await invitacionValida();
      const ana = nuevoId('ana');
      await poner('membresias', ana, { albergueId: 'otro', estado: 'activa' });
      await falla(aceptar(ana, 'ana@mail.com', { invitacionId }), 'failed-precondition');
      assert.equal((await leer('membresias', ana)).albergueId, 'otro');
    });
    test('la responsable dejó de serlo: rechazo', async () => {
      const { resp, invitacionId } = await invitacionValida();
      await poner('usuarios', resp, { roles: ['adoptante'] });
      await falla(aceptar(nuevoId('ana'), 'ana@mail.com', { invitacionId }), 'failed-precondition');
    });
    test('su propia invitación: rechazo', async () => {
      const resp = nuevoId('resp');
      await responsable(resp);
      const invitacionId = await invitacionSembrada(resp, `${resp}@mail.com`);
      await falla(aceptar(resp, `${resp}@mail.com`, { invitacionId }), 'permission-denied');
    });
    test('sin tope: en un equipo de 30 se acepta igual y el contador sube a 31', async () => {
      const { resp, invitacionId } = await invitacionValida();
      await poner('equipos', resp, { miembrosActivos: 30 });
      await aceptar(nuevoId('ana'), 'ana@mail.com', { invitacionId });
      assert.equal((await leer('equipos', resp)).miembrosActivos, 31);
    });
    test('id inválido o inexistente', async () => {
      await falla(aceptar(nuevoId('ana'), 'ana@mail.com', { invitacionId: 'a/b' }), 'invalid-argument');
      await falla(aceptar(nuevoId('ana'), 'ana@mail.com', { invitacionId: '' }), 'invalid-argument');
      await falla(aceptar(nuevoId('ana'), 'ana@mail.com', { invitacionId: nuevoId('nada') }), 'not-found');
    });
  });

  describe('concurrencia', () => {
    test('C1 15 aceptaciones simultáneas en un equipo vacío: las 15 entran y el contador queda exacto', async () => {
      const resp = nuevoId('resp');
      await responsable(resp);
      const personas = [];
      for (let i = 0; i < 15; i++) {
        const uid = nuevoId('m');
        personas.push({ uid, email: `${uid}@mail.com`, invitacionId: await invitacionSembrada(resp, `${uid}@mail.com`) });
      }
      const r = await Promise.allSettled(personas.map((p) => aceptar(p.uid, p.email, { invitacionId: p.invitacionId })));
      const rechazos = r.filter((x) => x.status === 'rejected').map((x) => x.reason.code);
      assert.deepEqual(rechazos, [], `rechazos: ${rechazos.join(', ')}`);
      assert.equal((await leer('equipos', resp)).miembrosActivos, 15);
      const activas = await db.collection('membresias').where('albergueId', '==', resp).where('estado', '==', 'activa').get();
      assert.equal(activas.size, 15);
    });
    test('C2 una persona acepta dos albergues a la vez: queda en uno solo', async () => {
      const a = nuevoId('respA'); const b = nuevoId('respB');
      await responsable(a); await responsable(b);
      const ana = nuevoId('ana');
      const invA = await invitacionSembrada(a, 'ana@mail.com');
      const invB = await invitacionSembrada(b, 'ana@mail.com');
      const r = await Promise.allSettled([aceptar(ana, 'ana@mail.com', { invitacionId: invA }), aceptar(ana, 'ana@mail.com', { invitacionId: invB })]);
      const ok = r.filter((x) => x.status === 'fulfilled');
      assert.equal(ok.length, 1, JSON.stringify(r.map((x) => x.status === 'rejected' ? x.reason.code : 'ok')));
      assert.equal(r.find((x) => x.status === 'rejected').reason.code, 'failed-precondition');
      const ganador = ok[0].value.albergueId;
      assert.equal((await leer('membresias', ana)).albergueId, ganador);
      const perdedor = ganador === a ? b : a;
      assert.equal((await leer('equipos', ganador)).miembrosActivos, 1);
      assert.equal((await leer('equipos', perdedor))?.miembrosActivos ?? 0, 0);
    });
    test('C3 la misma invitación aceptada dos veces a la vez: una sola membresía y contador en 1', async () => {
      const resp = nuevoId('resp');
      await responsable(resp);
      const ana = nuevoId('ana');
      const invitacionId = await invitacionSembrada(resp, 'ana@mail.com');
      const r = await Promise.allSettled([aceptar(ana, 'ana@mail.com', { invitacionId }), aceptar(ana, 'ana@mail.com', { invitacionId })]);
      assert.equal(r.filter((x) => x.status === 'fulfilled').length, 1);
      assert.equal((await leer('equipos', resp)).miembrosActivos, 1);
    });
    test('C4 15 invitaciones simultáneas a correos distintos: se crean las 15', async () => {
      const resp = nuevoId('resp');
      await responsable(resp);
      const r = await Promise.allSettled(Array.from({ length: 15 }, (_, i) => invitar(resp, null, { email: `p${i}@mail.com` })));
      const rechazos = r.filter((x) => x.status === 'rejected').map((x) => x.reason.code);
      assert.deepEqual(rechazos, [], `rechazos: ${rechazos.join(', ')}`);
      assert.equal((await invitacionesDe(resp)).length, 15);
    });
    test('C5 tres invitaciones simultáneas al mismo correo: una sola', async () => {
      const resp = nuevoId('resp');
      await responsable(resp);
      const r = await Promise.allSettled([1, 2, 3].map(() => invitar(resp, null, { email: 'ana@mail.com' })));
      assert.equal(r.filter((x) => x.status === 'fulfilled').length, 1);
      assert.deepEqual(r.filter((x) => x.status === 'rejected').map((x) => x.reason.code), ['already-exists', 'already-exists']);
      assert.equal((await invitacionesDe(resp)).length, 1);
    });
    test('C6 aceptaciones e invitaciones mezcladas: el contador cuenta exactamente a quienes aceptaron', async () => {
      const resp = nuevoId('resp');
      await responsable(resp);
      const personas = [];
      for (let i = 0; i < 6; i++) {
        const uid = nuevoId('m');
        personas.push({ uid, email: `${uid}@mail.com`, invitacionId: await invitacionSembrada(resp, `${uid}@mail.com`) });
      }
      await Promise.allSettled([
        ...personas.map((p) => aceptar(p.uid, p.email, { invitacionId: p.invitacionId })),
        ...Array.from({ length: 8 }, (_, i) => invitar(resp, null, { email: `nueva${i}@mail.com` })),
      ]);
      assert.equal((await leer('equipos', resp)).miembrosActivos, 6);
      const pendientes = (await invitacionesDe(resp)).filter((i) => i.estado === 'pendiente').length;
      assert.equal(pendientes, 8, 'las 8 invitaciones nuevas quedaron pendientes');
    });
  });
});
