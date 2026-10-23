const { test, describe, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { avisarPorVencimiento } = require('../avisos_vencimiento');

// El aviso de vencimiento de hogar de paso crea chats desde el servidor.
// Admin SDK no pasa por la regla que deja tipoSolicitud fijo, así que el
// código tiene que cumplirla solo: tipo 'hogar_de_paso' SOLO al crear, nunca
// en un chat que ya existe, y sin escribir encima si el chat aparece en el
// medio.
//
// Solo corre con el emulador local y un proyecto "demo-" (no existe en la
// nube). Sin emulador, se salta y lo dice:
//
//   firebase emulators:exec --only firestore --project demo-equipo-test \
//     "node --test functions/test/avisos_vencimiento.emulador.test.js"

const HOST = process.env.FIRESTORE_EMULATOR_HOST || '';
const EMULADOR_LOCAL = /^(127\.0\.0\.1|localhost|\[::1\]):\d+$/.test(HOST);
const SIN_EMULADOR = EMULADOR_LOCAL ? false : 'necesita el emulador de Firestore local (FIRESTORE_EMULATOR_HOST)';

let app;
let db;
let n = 0;
// El pid va en el id: los archivos de prueba corren en paralelo contra el
// mismo emulador, y dos procesos pueden empezar en el mismo milisegundo.
const nuevoId = (p) => `${p}_${process.pid}_${Date.now().toString(36)}_${++n}`;

function datosAviso(rescateId, adoptanteId, extra = {}) {
  return {
    rescateId, adoptanteId, rescatistaId: 'perla', rescatista: 'La Perla', adoptanteNombre: 'Ana',
    animalNombre: 'Toby', especie: 'Perro', fotoUrl: 'https://foto/toby.jpg', creadoPor: 'albergue',
    texto: 'El hogar de paso de Toby vence mañana.', ...extra,
  };
}
const chatDe = async (rescateId, adoptanteId) =>
  (await db.collection('chats').doc(`${rescateId}_${adoptanteId}`).get()).data();
const mensajesDe = async (rescateId, adoptanteId) =>
  (await db.collection('chats').doc(`${rescateId}_${adoptanteId}`).collection('mensajes').get()).docs.map((d) => d.data());

describe('avisarPorVencimiento con el emulador', { skip: SIN_EMULADOR }, () => {
  before(() => {
    app = initializeApp({ projectId: 'demo-equipo-test' }, 'avisos-emulador');
    db = getFirestore(app);
    assert.ok(['127.0.0.1', 'localhost', '[::1]', '::1'].includes(db._settings.servicePath), 'el cliente no apunta al emulador local');
  });
  after(async () => { if (app) await deleteApp(app); });

  test('chat nuevo: nace con tipoSolicitud hogar_de_paso, su identidad y el mensaje', async () => {
    const r = nuevoId('r'); const a = nuevoId('ana');
    await avisarPorVencimiento(db, datosAviso(r, a));
    const c = await chatDe(r, a);
    assert.equal(c.tipoSolicitud, 'hogar_de_paso');
    assert.equal(c.creadoPor, 'albergue');
    assert.equal(c.rescatistaId, 'perla');
    assert.equal(c.adoptanteId, a);
    assert.equal(c.noLeidosAdoptante, 1);
    assert.equal(c.noLeidosRescatista, 1);
    assert.equal((await mensajesDe(r, a)).length, 1);
  });

  test('chat viejo SIN tipo: sigue sin tipo; solo cambia la vista previa', async () => {
    const r = nuevoId('r'); const a = nuevoId('ana');
    const ref = db.collection('chats').doc(`${r}_${a}`);
    await ref.set({ adoptanteId: a, rescatistaId: 'perla', creadoPor: 'albergue', rescateId: r,
      adoptanteNombre: 'Nombre viejo', fotoUrl: 'https://foto/vieja.jpg', noLeidosAdoptante: 3 });
    await avisarPorVencimiento(db, datosAviso(r, a));
    const c = await chatDe(r, a);
    assert.equal('tipoSolicitud' in c, false, 'no se le agrega tipo');
    assert.equal(c.adoptanteNombre, 'Nombre viejo', 'la identidad no se pisa');
    assert.equal(c.fotoUrl, 'https://foto/vieja.jpg', 'la foto que ya tenía no se pisa');
    assert.equal(c.noLeidosAdoptante, 4);
    assert.equal(c.ultimoMensaje, 'El hogar de paso de Toby vence mañana.');
  });

  test('chat que ya tenía tipo: lo conserva tal cual', async () => {
    const r = nuevoId('r'); const a = nuevoId('ana');
    await db.collection('chats').doc(`${r}_${a}`).set({ adoptanteId: a, rescatistaId: 'perla', creadoPor: 'albergue', rescateId: r, tipoSolicitud: 'adopcion' });
    await avisarPorVencimiento(db, datosAviso(r, a));
    assert.equal((await chatDe(r, a)).tipoSolicitud, 'adopcion');
  });

  test('dos avisos a la vez sobre un chat que no existe: un solo chat, sin escribir encima, y los dos mensajes', async () => {
    const r = nuevoId('r'); const a = nuevoId('ana');
    await Promise.all([
      avisarPorVencimiento(db, datosAviso(r, a, { texto: 'aviso 1' })),
      avisarPorVencimiento(db, datosAviso(r, a, { texto: 'aviso 2' })),
    ]);
    const c = await chatDe(r, a);
    assert.equal(c.tipoSolicitud, 'hogar_de_paso');
    assert.equal(c.noLeidosAdoptante, 2, 'los dos avisos sumaron: ninguno pisó al otro');
    assert.equal(c.noLeidosRescatista, 2);
    assert.deepEqual((await mensajesDe(r, a)).map((m) => m.texto).sort(), ['aviso 1', 'aviso 2']);
  });

  test('un chat creado por otro (sin tipo) en paralelo con el aviso: no queda con tipo agregado', async () => {
    const r = nuevoId('r'); const a = nuevoId('ana');
    const ref = db.collection('chats').doc(`${r}_${a}`);
    // Lo crea "la app vieja" a la vez que corre el aviso.
    await Promise.all([
      ref.create({ adoptanteId: a, rescatistaId: 'perla', creadoPor: 'albergue', rescateId: r, adoptanteNombre: 'Desde la app' }).catch(() => 'perdió'),
      avisarPorVencimiento(db, datosAviso(r, a)),
    ]);
    const c = await chatDe(r, a);
    // Dos resultados válidos según quién llegó primero. Lo que no puede pasar
    // es que el chat de la app quede con el tipo agregado por el servidor.
    if (c.adoptanteNombre === 'Desde la app') {
      assert.equal('tipoSolicitud' in c, false);
    } else {
      assert.equal(c.tipoSolicitud, 'hogar_de_paso');
    }
    assert.equal((await mensajesDe(r, a)).length, 1);
  });
});
