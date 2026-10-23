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
const revision = (decision = 'compartir', extra = {}) => ({ decision, por: 'x', en: fecha(2026, 10, 20), ...extra });

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
    test('cupo: 10 activos, o 7 activos + 3 pendientes vigentes, no dejan invitar; las vencidas no cuentan', async () => {
      const lleno = nuevoId('resp');
      await responsable(lleno);
      await poner('equipos', lleno, { miembrosActivos: 10 });
      await falla(invitar(lleno, null, { email: 'x@mail.com' }), 'resource-exhausted');

      const mixto = nuevoId('resp');
      await responsable(mixto);
      await poner('equipos', mixto, { miembrosActivos: 7 });
      for (const e of ['a', 'b', 'c']) await invitacionSembrada(mixto, `${e}@mail.com`);
      await falla(invitar(mixto, null, { email: 'x@mail.com' }), 'resource-exhausted');

      const conVencida = nuevoId('resp');
      await responsable(conVencida);
      await poner('equipos', conVencida, { miembrosActivos: 7 });
      await invitacionSembrada(conVencida, 'a@mail.com');
      await invitacionSembrada(conVencida, 'b@mail.com');
      await invitacionSembrada(conVencida, 'c@mail.com', { expiraEn: ts(AHORA - 1) });
      await invitar(conVencida, null, { email: 'x@mail.com' });
    });
  });

  describe('barrera de hogares de paso dudosos', () => {
    // La responsable con vida de rescatista (G2 a G7): por rol o por un animal personal.
    async function respConHogares(hogares, { porAnimal = false } = {}) {
      const resp = nuevoId('resp');
      await responsable(resp, porAnimal ? {} : { roles: ['albergue', 'rescatista'] });
      if (porAnimal) await poner('rescates', nuevoId('r'), { rescatistaId: resp, creadoPor: 'rescatista' });
      for (const h of hogares) {
        await poner('hogaresDePaso', nuevoId('h'), {
          albergueId: resp, nombre: 'Familia Ruiz', telefono: '300 000 0000', email: 'familia@mail.com', ...h,
        });
      }
      return resp;
    }
    const invitaBien = async (resp) => { await invitar(resp, null, { email: 'nueva@mail.com' }); };
    const bloqueada = async (resp) => {
      const antes = await leer('equipos', resp);
      await assert.rejects(invitar(resp, null, { email: 'nueva@mail.com' }), (e) => {
        assert.equal(e.code, 'failed-precondition');
        assert.doesNotMatch(e.message, /\d|rescatista/i, 'el mensaje no dice cuántos hogares ni el historial');
        return true;
      });
      assert.deepEqual(await invitacionesDe(resp), [], 'no tiene que crearse la invitación');
      assert.deepEqual(await leer('equipos', resp), antes, 'el contador no cambia');
    };

    test('G1 responsable que nunca fue rescatista, con hogares viejos y sin fecha: invita', async () => {
      const resp = nuevoId('resp');
      await responsable(resp);
      await poner('hogaresDePaso', nuevoId('h'), { albergueId: resp, creadoEn: fecha(2026, 3, 1) });
      await poner('hogaresDePaso', nuevoId('h'), { albergueId: resp });
      await invitaBien(resp);
    });
    test('G2 rol de rescatista y un hogar viejo sin revisar: bloqueada', async () => {
      await bloqueada(await respConHogares([{ creadoEn: fecha(2026, 5, 1) }]));
    });
    test('G3 vida de rescatista por un animal personal, sin el rol: bloqueada', async () => {
      await bloqueada(await respConHogares([{ creadoEn: fecha(2026, 5, 1) }], { porAnimal: true }));
    });
    test('G4 hogar sin fecha (como los que agrega la app sola): bloqueada', async () => {
      await bloqueada(await respConHogares([{ adoptanteId: 'x', vecesAyudo: 2 }]));
    });
    test('G5 hogar con fecha desde el 2026-07-31: no bloquea', async () => {
      await invitaBien(await respConHogares([{ creadoEn: fecha(2026, 7, 31) }]));
    });
    test('G6 hogares dudosos con revisión válida compartir o no_compartir: no bloquean', async () => {
      await invitaBien(await respConHogares([
        { creadoEn: fecha(2026, 5, 1), revisionEquipo: revision('compartir') },
        { revisionEquipo: revision('no_compartir') },
      ]));
    });
    for (const [caso, rev] of [
      ['decisión desconocida', revision('si')],
      ['sin quién', revision('compartir', { por: '' })],
      ['sin cuándo', revision('compartir', { en: null })],
      ['cuándo como texto', revision('compartir', { en: '2026-10-20' })],
      ['revisión como true', true],
    ]) {
      test(`G7 revisión mal formada (${caso}): sigue bloqueada`, async () => {
        await bloqueada(await respConHogares([{ creadoEn: fecha(2026, 5, 1), revisionEquipo: rev }]));
      });
    }
    test('G7b un solo hogar pendiente entre varios revisados: bloqueada', async () => {
      await bloqueada(await respConHogares([
        { creadoEn: fecha(2026, 5, 1), revisionEquipo: revision() },
        { creadoEn: fecha(2026, 4, 1) },
      ]));
    });
    test('G8 invitación creada antes de que aparezca un hogar dudoso: aceptar la rechaza', async () => {
      const resp = await respConHogares([]);
      const { invitacionId } = await invitar(resp, null, { email: 'ana@mail.com' });
      await poner('hogaresDePaso', nuevoId('h'), { albergueId: resp, creadoEn: fecha(2026, 5, 1) });
      const ana = nuevoId('ana');
      await assert.rejects(aceptar(ana, 'ana@mail.com', { invitacionId }), (e) => {
        assert.equal(e.code, 'failed-precondition');
        // B1: la invitada no se entera de que es por los hogares ni del historial de la responsable.
        assert.doesNotMatch(e.message, /hogar|rescatista|\d/i);
        return true;
      });
      assert.equal(await leer('membresias', ana), undefined);
      assert.equal((await leer('invitaciones', invitacionId)).estado, 'pendiente');
    });
    test('G8b invitación sembrada sin pasar por invitarMiembro: aceptar también la rechaza', async () => {
      const resp = await respConHogares([{ creadoEn: fecha(2026, 5, 1) }]);
      const invitacionId = await invitacionSembrada(resp, 'ana@mail.com');
      const ana = nuevoId('ana');
      await falla(aceptar(ana, 'ana@mail.com', { invitacionId }), 'failed-precondition');
      assert.equal(await leer('membresias', ana), undefined);
    });
    test('G9 el cliente manda campos para saltarse la barrera: rechazo', async () => {
      const resp = await respConHogares([{ creadoEn: fecha(2026, 5, 1) }]);
      const invitacionId = await invitacionSembrada(resp, 'ana@mail.com');
      await falla(invitar(resp, null, { email: 'x@mail.com', hogaresRevisados: ['todos'] }), 'invalid-argument');
      await falla(aceptar(nuevoId('ana'), 'ana@mail.com', { invitacionId, hogaresRevisados: ['todos'] }), 'invalid-argument');
      await falla(aceptar(nuevoId('ana'), 'ana@mail.com', { invitacionId, albergueId: 'otro' }), 'invalid-argument');
    });
    test('G10 hogares dudosos de OTRO albergue no bloquean', async () => {
      const otra = await respConHogares([{ creadoEn: fecha(2026, 5, 1) }]);
      const resp = nuevoId('resp');
      await responsable(resp, { roles: ['albergue', 'rescatista'] });
      await poner('hogaresDePaso', nuevoId('h'), { albergueId: resp, creadoEn: fecha(2026, 9, 1) });
      await invitaBien(resp);
      await bloqueada(otra);
    });
    test('G12 cuando los hogares quedan revisados, se puede aceptar', async () => {
      const resp = await respConHogares([{ creadoEn: fecha(2026, 5, 1), revisionEquipo: revision('no_compartir') }]);
      const { invitacionId } = await invitar(resp, null, { email: 'ana@mail.com' });
      await aceptar(nuevoId('ana'), 'ana@mail.com', { invitacionId });
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
    test('equipo lleno: rechazo', async () => {
      const { resp, invitacionId } = await invitacionValida();
      await poner('equipos', resp, { miembrosActivos: 10 });
      await falla(aceptar(nuevoId('ana'), 'ana@mail.com', { invitacionId }), 'resource-exhausted');
    });
    test('id inválido o inexistente', async () => {
      await falla(aceptar(nuevoId('ana'), 'ana@mail.com', { invitacionId: 'a/b' }), 'invalid-argument');
      await falla(aceptar(nuevoId('ana'), 'ana@mail.com', { invitacionId: '' }), 'invalid-argument');
      await falla(aceptar(nuevoId('ana'), 'ana@mail.com', { invitacionId: nuevoId('nada') }), 'not-found');
    });
  });

  describe('concurrencia', () => {
    test('C1 11 aceptaciones simultáneas en un equipo vacío: exactamente 10 activas', async () => {
      const resp = nuevoId('resp');
      await responsable(resp);
      // Sembradas a mano: invitarMiembro no deja tener 11 pendientes.
      const personas = [];
      for (let i = 0; i < 11; i++) {
        const uid = nuevoId('m');
        personas.push({ uid, email: `${uid}@mail.com`, invitacionId: await invitacionSembrada(resp, `${uid}@mail.com`) });
      }
      const r = await Promise.allSettled(personas.map((p) => aceptar(p.uid, p.email, { invitacionId: p.invitacionId })));
      const ok = r.filter((x) => x.status === 'fulfilled').length;
      const rechazos = r.filter((x) => x.status === 'rejected').map((x) => x.reason.code);
      assert.equal(ok, 10, `aceptadas: ${ok}, rechazos: ${rechazos.join(', ')}`);
      assert.deepEqual(rechazos, ['resource-exhausted']);
      assert.equal((await leer('equipos', resp)).miembrosActivos, 10);
      const activas = await db.collection('membresias').where('albergueId', '==', resp).where('estado', '==', 'activa').get();
      assert.equal(activas.size, 10);
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
    test('C4 12 invitaciones simultáneas: exactamente 10 creadas', async () => {
      const resp = nuevoId('resp');
      await responsable(resp);
      const r = await Promise.allSettled(Array.from({ length: 12 }, (_, i) => invitar(resp, null, { email: `p${i}@mail.com` })));
      const ok = r.filter((x) => x.status === 'fulfilled').length;
      const rechazos = r.filter((x) => x.status === 'rejected').map((x) => x.reason.code);
      assert.equal(ok, 10, `creadas: ${ok}, rechazos: ${rechazos.join(', ')}`);
      assert.deepEqual(rechazos, ['resource-exhausted', 'resource-exhausted']);
      assert.equal((await invitacionesDe(resp)).length, 10);
    });
    test('C5 tres invitaciones simultáneas al mismo correo: una sola', async () => {
      const resp = nuevoId('resp');
      await responsable(resp);
      const r = await Promise.allSettled([1, 2, 3].map(() => invitar(resp, null, { email: 'ana@mail.com' })));
      assert.equal(r.filter((x) => x.status === 'fulfilled').length, 1);
      assert.deepEqual(r.filter((x) => x.status === 'rejected').map((x) => x.reason.code), ['already-exists', 'already-exists']);
      assert.equal((await invitacionesDe(resp)).length, 1);
    });
    test('C6 aceptaciones e invitaciones mezcladas: nunca más de 10 entre activos y pendientes', async () => {
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
      const activos = (await leer('equipos', resp)).miembrosActivos;
      const pendientes = (await invitacionesDe(resp)).filter((i) => i.estado === 'pendiente').length;
      assert.ok(activos + pendientes <= 10, `activos ${activos} + pendientes ${pendientes}`);
      assert.equal(activos, 6);
    });
  });
});

// Esta no necesita el emulador: comprueba qué campos pide la consulta de hogares.
describe('consulta de hogares de paso (sin emulador)', () => {
  test('pide solo albergueId, creadoEn y revisionEquipo, y el historial con limit 1', async () => {
    const pedidos = [];
    const consulta = (col, pasos = []) => ({
      where: (f, op, v) => consulta(col, [...pasos, `where ${f}${op}${v}`]),
      select: (...campos) => consulta(col, [...pasos, `select ${campos.join(',')}`]),
      limit: (k) => consulta(col, [...pasos, `limit ${k}`]),
      _col: col, _pasos: pasos,
    });
    const db = { collection: (col) => consulta(col) };
    const tx = {
      get: async (q) => {
        pedidos.push(`${q._col}: ${q._pasos.join(' · ')}`);
        if (q._col === 'hogaresDePaso') return { docs: [{ id: 'h1', data: () => ({ albergueId: 'resp', creadoEn: null }) }] };
        return { empty: true, docs: [] };
      },
    };
    const pendientes = await E.leerHogaresPendientes(tx, db, 'resp', { roles: ['albergue'] });
    assert.deepEqual(pedidos, [
      'hogaresDePaso: where albergueId==resp · select albergueId,creadoEn,revisionEquipo',
      'rescates: where rescatistaId==resp · where creadoPor==rescatista · select rescatistaId · limit 1',
    ]);
    assert.deepEqual(pendientes, [], 'sin animal personal, el hogar sin fecha no es dudoso');
    assert.deepEqual(E.CAMPOS_HOGAR, ['albergueId', 'creadoEn', 'revisionEquipo']);
  });
  test('sin hogares no hace falta mirar el historial', async () => {
    const pedidos = [];
    const q = { where: () => q, select: () => q, limit: () => q };
    const tx = { get: async () => { pedidos.push('x'); return { docs: [], empty: true }; } };
    assert.deepEqual(await E.leerHogaresPendientes(tx, { collection: () => q }, 'resp', null), []);
    assert.equal(pedidos.length, 1);
  });
});
