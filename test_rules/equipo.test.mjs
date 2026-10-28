// Equipo del albergue: qué puede LEER una miembro con las reglas reales.
//
// Hogares de paso (fase 2, 2026-10-25): una miembro activa ve todos los del
// albergue y los maneja. Chats y mensajes: solo los del albergue con un
// tipo del equipo (adopcion, hogar_de_paso, consulta); nunca las consultas
// a negocios aliados, los chats sin tipo o con un tipo desconocido.
// tipoSolicitud queda fijo después de crear el chat. usuarios.trabajaEn lo
// escribe solo el servidor. El resto de las escrituras de la fase 2
// (animales, mensajes, solicitudes, fotos) está en equipo_fase2.test.mjs.
// membresias/invitaciones/equipos: lectura mínima, escritura solo de Functions.
//
// Ver PLAN-EQUIPO-ALBERGUE.md (decisiones del 2026-10-22).

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { before, after, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc, addDoc, collection, collectionGroup, query, where,
  deleteField, serverTimestamp,
} from 'firebase/firestore';

const aca = dirname(fileURLToPath(import.meta.url));

const RESP = 'uid_responsable';       // responsable del albergue A
const MIEMBRO = 'uid_miembro';        // miembro activa de A
const REVOCADA = 'uid_revocada';      // membresía revocada de A
const RESP_B = 'uid_responsable_b';   // otro albergue
const MIEMBRO_B = 'uid_miembro_b';    // miembro activa de B
const OTRO_ALB = 'uid_otro_albergue'; // albergue que consulta a un negocio aliado
const ADOPT = 'uid_adoptante';
const VET = 'uid_negocio';            // negocio aliado
const NADIE = 'uid_sin_membresia';
const SALIENTE = 'uid_saliente';      // salió del equipo de A
const SIN_ESTADO = 'uid_sin_estado';  // membresía mal formada, sin estado
const TIPOS = ['adopcion', 'hogar_de_paso', 'consulta'];

let env;
const como = (uid) => env.authenticatedContext(uid).firestore();
const sembrar = (fn) => env.withSecurityRulesDisabled(async (ctx) => fn(ctx.firestore()));

const CHATS = {
  cAdop: { adoptanteId: ADOPT, rescatistaId: RESP, creadoPor: 'albergue', tipoSolicitud: 'adopcion', rescateId: 'rA' },
  cHogar: { adoptanteId: ADOPT, rescatistaId: RESP, creadoPor: 'albergue', tipoSolicitud: 'hogar_de_paso', rescateId: 'rA' },
  cConsulta: { adoptanteId: ADOPT, rescatistaId: RESP, creadoPor: 'albergue', tipoSolicitud: 'consulta', rescateId: 'rA' },
  cPersonal: { adoptanteId: ADOPT, rescatistaId: RESP, creadoPor: 'rescatista', tipoSolicitud: 'adopcion', rescateId: 'rP' },
  cSinTipo: { adoptanteId: ADOPT, rescatistaId: RESP, creadoPor: 'albergue', rescateId: 'rA' },
  cTipoNull: { adoptanteId: ADOPT, rescatistaId: RESP, creadoPor: 'albergue', tipoSolicitud: null, rescateId: 'rA' },
  cTipoRaro: { adoptanteId: ADOPT, rescatistaId: RESP, creadoPor: 'albergue', tipoSolicitud: 'zzz', rescateId: 'rA' },
  // Consulta que OTRO albergue le mandó a la responsable cuando ella ya era negocio aliado.
  cAliadoRecibida: { adoptanteId: OTRO_ALB, rescatistaId: RESP, creadoPor: 'albergue', tipoSolicitud: 'consulta_aliado' },
  // Consulta que la responsable le MANDÓ a un negocio aliado.
  cAliadoEnviada: { adoptanteId: RESP, rescatistaId: VET, creadoPor: 'albergue', tipoSolicitud: 'consulta_aliado' },
  cOtroAlbergue: { adoptanteId: ADOPT, rescatistaId: RESP_B, creadoPor: 'albergue', tipoSolicitud: 'adopcion', rescateId: 'rB' },
};

const HOGARES = {
  hSinCampo: { albergueId: RESP, nombre: 'Familia Ruiz', telefono: '300 000 0000' },
  hFalse: { albergueId: RESP, nombre: 'Familia Gómez', visibleEquipo: false },
  hTrue: { albergueId: RESP, nombre: 'Familia Pérez', visibleEquipo: true,
    revisionEquipo: { decision: 'compartir', por: RESP, en: new Date(Date.UTC(2026, 9, 20)) } },
  hB: { albergueId: RESP_B, nombre: 'Familia de B', visibleEquipo: true },
};

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'patitas-equipo-reglas-test',
    firestore: { rules: readFileSync(join(aca, '..', 'firestore.rules'), 'utf8'), host: '127.0.0.1', port: 8097 },
  });
});
after(async () => { await env.cleanup(); });

beforeEach(async () => {
  await env.clearFirestore();
  await sembrar(async (db) => {
    await setDoc(doc(db, 'usuarios', RESP), { roles: ['albergue'], albergueNombre: 'La Perla' });
    await setDoc(doc(db, 'usuarios', RESP_B), { roles: ['albergue'], albergueNombre: 'Huellitas' });
    await setDoc(doc(db, 'usuarios', OTRO_ALB), { roles: ['albergue'], albergueNombre: 'Gatitos' });
    await setDoc(doc(db, 'usuarios', VET), { roles: ['aliado'], aliadoNombre: 'Vet 30' });
    await setDoc(doc(db, 'usuarios', ADOPT), { roles: ['adoptante'] });
    await setDoc(doc(db, 'usuarios', MIEMBRO), { roles: ['adoptante', 'rescatista'], trabajaEn: RESP });
    await setDoc(doc(db, 'rescates', 'rA'), { rescatistaId: RESP, creadoPor: 'albergue' });
    await setDoc(doc(db, 'rescates', 'rP'), { rescatistaId: RESP, creadoPor: 'rescatista' });
    await setDoc(doc(db, 'rescates', 'rB'), { rescatistaId: RESP_B, creadoPor: 'albergue' });
    await setDoc(doc(db, 'solicitudes', 'sAlbergue'), { adoptanteId: ADOPT, rescatistaId: RESP, creadoPor: 'albergue', estado: 'pendiente' });
    await setDoc(doc(db, 'solicitudes', 'sPersonal'), { adoptanteId: ADOPT, rescatistaId: RESP, creadoPor: 'rescatista', estado: 'pendiente' });
    for (const [id, data] of Object.entries(CHATS)) {
      await setDoc(doc(db, 'chats', id), data);
      await setDoc(doc(db, 'chats', id, 'mensajes', 'm1'), { texto: 'hola', emisor: 'adoptante' });
    }
    for (const [id, data] of Object.entries(HOGARES)) await setDoc(doc(db, 'hogaresDePaso', id), data);
    await setDoc(doc(db, 'membresias', MIEMBRO), { albergueId: RESP, estado: 'activa' });
    await setDoc(doc(db, 'membresias', REVOCADA), { albergueId: RESP, estado: 'revocada' });
    await setDoc(doc(db, 'membresias', MIEMBRO_B), { albergueId: RESP_B, estado: 'activa' });
    await setDoc(doc(db, 'membresias', SALIENTE), { albergueId: RESP, estado: 'saliente' });
    await setDoc(doc(db, 'membresias', SIN_ESTADO), { albergueId: RESP });
    await setDoc(doc(db, 'solicitudes', 'sVieja'), { adoptanteId: ADOPT, rescatistaId: RESP, estado: 'pendiente' });
  });
});

const hogaresEquipo = (db, albergue) =>
  query(collection(db, 'hogaresDePaso'), where('albergueId', '==', albergue));
const chatsEquipo = (db, albergue, tipos = TIPOS) =>
  query(collection(db, 'chats'), where('rescatistaId', '==', albergue), where('creadoPor', '==', 'albergue'), where('tipoSolicitud', 'in', tipos));

// ─── Hogares de paso: lectura ────────────────────────────────────────────

describe('hogares de paso: lectura', () => {
  it('la responsable lee todos sus hogares', async () => {
    for (const id of ['hSinCampo', 'hFalse', 'hTrue']) await assertSucceeds(getDoc(doc(como(RESP), 'hogaresDePaso', id)));
    const snap = await assertSucceeds(getDocs(hogaresEquipo(como(RESP), RESP)));
    assert.equal(snap.size, 3);
  });
  it('miembro activa: lee todos los del albergue, tengan o no el viejo visibleEquipo', async () => {
    for (const id of ['hSinCampo', 'hFalse', 'hTrue']) await assertSucceeds(getDoc(doc(como(MIEMBRO), 'hogaresDePaso', id)));
    const snap = await assertSucceeds(getDocs(hogaresEquipo(como(MIEMBRO), RESP)));
    assert.deepEqual(snap.docs.map((d) => d.id).sort(), ['hFalse', 'hSinCampo', 'hTrue']);
  });
  it('miembro de otro albergue, revocada o sin membresía: no', async () => {
    for (const uid of [MIEMBRO_B, REVOCADA, NADIE]) {
      await assertFails(getDoc(doc(como(uid), 'hogaresDePaso', 'hSinCampo')));
      await assertFails(getDocs(hogaresEquipo(como(uid), RESP)));
    }
  });
  it('miembro de A no lee los hogares de B', async () => {
    await assertFails(getDoc(doc(como(MIEMBRO), 'hogaresDePaso', 'hB')));
    await assertFails(getDocs(hogaresEquipo(como(MIEMBRO), RESP_B)));
  });
});

// ─── Hogares de paso: escritura ──────────────────────────────────────────

describe('hogares de paso: escritura', () => {
  it('la responsable crea, edita y borra los suyos', async () => {
    const db = como(RESP);
    await assertSucceeds(setDoc(doc(db, 'hogaresDePaso', 'nuevo'), { albergueId: RESP, nombre: 'X', creadoEn: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(db, 'hogaresDePaso', 'hTrue'), { telefono: '301 111 1111', notas: 'Tiene patio' }));
    await assertSucceeds(setDoc(doc(db, 'hogaresDePaso', 'hSinCampo'), { vecesAyudo: 2 }, { merge: true }));
    await assertSucceeds(deleteDoc(doc(db, 'hogaresDePaso', 'hFalse')));
  });
  it('miembro activa: agrega, edita y borra hogares del albergue', async () => {
    const db = como(MIEMBRO);
    await assertSucceeds(setDoc(doc(db, 'hogaresDePaso', 'deAna'), { albergueId: RESP, nombre: 'Familia Ríos', creadoEn: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(db, 'hogaresDePaso', 'hSinCampo'), { telefono: '303 333 3333' }));
    await assertSucceeds(setDoc(doc(db, 'hogaresDePaso', 'hTrue'), { notas: 'Solo gatos' }, { merge: true }));
    await assertSucceeds(deleteDoc(doc(db, 'hogaresDePaso', 'hFalse')));
  });
  it('miembro: no se lleva un hogar a otro albergue ni a su propio uid', async () => {
    const db = como(MIEMBRO);
    await assertFails(updateDoc(doc(db, 'hogaresDePaso', 'hSinCampo'), { albergueId: RESP_B }));
    await assertFails(updateDoc(doc(db, 'hogaresDePaso', 'hSinCampo'), { albergueId: MIEMBRO }));
  });
  it('miembro: no crea a nombre propio ni de otro albergue, ni toca los de otro albergue', async () => {
    const db = como(MIEMBRO);
    await assertFails(setDoc(doc(db, 'hogaresDePaso', 'n1'), { albergueId: MIEMBRO, nombre: 'X' }));
    await assertFails(setDoc(doc(db, 'hogaresDePaso', 'n2'), { albergueId: RESP_B, nombre: 'X' }));
    await assertFails(updateDoc(doc(db, 'hogaresDePaso', 'hB'), { telefono: '1' }));
    await assertFails(deleteDoc(doc(db, 'hogaresDePaso', 'hB')));
  });
  it('revocada, saliente, de otro albergue o sin membresía: nada', async () => {
    for (const uid of [REVOCADA, SALIENTE, MIEMBRO_B, NADIE]) {
      const db = como(uid);
      await assertFails(setDoc(doc(db, 'hogaresDePaso', `n_${uid}`), { albergueId: RESP, nombre: 'X' }));
      await assertFails(updateDoc(doc(db, 'hogaresDePaso', 'hSinCampo'), { telefono: '1' }));
      await assertFails(deleteDoc(doc(db, 'hogaresDePaso', 'hSinCampo')));
    }
  });
  it('si la cuenta del albergue ya no tiene el rol albergue, la miembro no crea ni edita', async () => {
    await sembrar((db) => setDoc(doc(db, 'usuarios', RESP), { roles: ['rescatista'], albergueNombre: 'La Perla' }));
    const db = como(MIEMBRO);
    await assertFails(setDoc(doc(db, 'hogaresDePaso', 'n3'), { albergueId: RESP, nombre: 'X' }));
    await assertFails(updateDoc(doc(db, 'hogaresDePaso', 'hSinCampo'), { telefono: '1' }));
  });
});

// ─── Chats y mensajes: lectura ───────────────────────────────────────────

describe('chats: lo que la miembro sí ve', () => {
  for (const id of ['cAdop', 'cHogar', 'cConsulta']) {
    it(`lee ${id} y sus mensajes`, async () => {
      await assertSucceeds(getDoc(doc(como(MIEMBRO), 'chats', id)));
      await assertSucceeds(getDocs(collection(como(MIEMBRO), 'chats', id, 'mensajes')));
    });
  }
  it('la lista con los tres filtros trae exactamente los chats del equipo', async () => {
    const snap = await assertSucceeds(getDocs(chatsEquipo(como(MIEMBRO), RESP)));
    assert.deepEqual(snap.docs.map((d) => d.id).sort(), ['cAdop', 'cConsulta', 'cHogar']);
  });
  it('la lista con un subconjunto de tipos o con igualdad también funciona', async () => {
    await assertSucceeds(getDocs(chatsEquipo(como(MIEMBRO), RESP, ['adopcion'])));
    await assertSucceeds(getDocs(query(collection(como(MIEMBRO), 'chats'), where('rescatistaId', '==', RESP), where('creadoPor', '==', 'albergue'), where('tipoSolicitud', '==', 'hogar_de_paso'))));
  });
});

describe('chats: consultas a negocios aliados, nunca para el equipo', () => {
  it('la consulta que recibió la responsable (con rol aliado antes de tener equipo): ni el chat ni sus mensajes', async () => {
    await sembrar((db) => setDoc(doc(db, 'usuarios', RESP), { roles: ['albergue', 'aliado'], albergueNombre: 'La Perla', aliadoNombre: 'Tienda' }));
    await assertFails(getDoc(doc(como(MIEMBRO), 'chats', 'cAliadoRecibida')));
    await assertFails(getDocs(collection(como(MIEMBRO), 'chats', 'cAliadoRecibida', 'mensajes')));
  });
  it('la responsable se agrega el rol aliado después: una consulta nueva tampoco', async () => {
    await sembrar((db) => setDoc(doc(db, 'usuarios', RESP), { roles: ['albergue', 'aliado'], albergueNombre: 'La Perla', aliadoNombre: 'Tienda' }));
    await assertSucceeds(setDoc(doc(como(OTRO_ALB), 'chats', 'cNueva'), {
      adoptanteId: OTRO_ALB, rescatistaId: RESP, creadoPor: 'albergue', tipoSolicitud: 'consulta_aliado',
      adoptanteNombre: 'Gatitos', animalNombre: 'Tienda', rescatista: 'Tienda',
      ultimoMensaje: '', ultimaHora: '', ultimoMensajeEn: serverTimestamp(), noLeidosAdoptante: 0, noLeidosRescatista: 0,
    }));
    await assertFails(getDoc(doc(como(MIEMBRO), 'chats', 'cNueva')));
    const snap = await assertSucceeds(getDocs(chatsEquipo(como(MIEMBRO), RESP)));
    assert.ok(!snap.docs.some((d) => d.id === 'cNueva'));
  });
  it('la consulta que la responsable mandó a un negocio aliado: no', async () => {
    await assertFails(getDoc(doc(como(MIEMBRO), 'chats', 'cAliadoEnviada')));
  });
  it('listas que intentan traer consultas: sin filtro de tipo, con consulta_aliado en el in, o por igualdad', async () => {
    const db = como(MIEMBRO);
    await assertFails(getDocs(query(collection(db, 'chats'), where('rescatistaId', '==', RESP), where('creadoPor', '==', 'albergue'))));
    await assertFails(getDocs(chatsEquipo(db, RESP, [...TIPOS, 'consulta_aliado'])));
    await assertFails(getDocs(query(collection(db, 'chats'), where('rescatistaId', '==', RESP), where('creadoPor', '==', 'albergue'), where('tipoSolicitud', '==', 'consulta_aliado'))));
  });
  it('los participantes de la consulta la siguen leyendo', async () => {
    await assertSucceeds(getDoc(doc(como(OTRO_ALB), 'chats', 'cAliadoRecibida')));
    await assertSucceeds(getDoc(doc(como(RESP), 'chats', 'cAliadoRecibida')));
    await assertSucceeds(getDoc(doc(como(VET), 'chats', 'cAliadoEnviada')));
  });
});

describe('chats: sin tipo, con tipo null o desconocido, personales y ajenos', () => {
  for (const id of ['cSinTipo', 'cTipoNull', 'cTipoRaro']) {
    it(`${id}: la miembro no lo lee ni lee sus mensajes; la responsable sí`, async () => {
      await assertFails(getDoc(doc(como(MIEMBRO), 'chats', id)));
      await assertFails(getDocs(collection(como(MIEMBRO), 'chats', id, 'mensajes')));
      await assertSucceeds(getDoc(doc(como(RESP), 'chats', id)));
    });
  }
  it('los chats sin tipo o raros no salen en la lista del equipo', async () => {
    const snap = await assertSucceeds(getDocs(chatsEquipo(como(MIEMBRO), RESP)));
    assert.ok(snap.docs.every((d) => TIPOS.includes(d.data().tipoSolicitud)));
  });
  it('chat personal de la responsable (creadoPor rescatista): ni directo, ni lista, ni mensajes', async () => {
    await assertFails(getDoc(doc(como(MIEMBRO), 'chats', 'cPersonal')));
    await assertFails(getDocs(collection(como(MIEMBRO), 'chats', 'cPersonal', 'mensajes')));
    await assertFails(getDocs(query(collection(como(MIEMBRO), 'chats'), where('rescatistaId', '==', RESP), where('creadoPor', '==', 'rescatista'), where('tipoSolicitud', 'in', TIPOS))));
  });
  it('chats de otro albergue: la miembro de A no; la miembro de B no lee los de A', async () => {
    await assertFails(getDoc(doc(como(MIEMBRO), 'chats', 'cOtroAlbergue')));
    await assertFails(getDocs(chatsEquipo(como(MIEMBRO), RESP_B)));
    await assertFails(getDoc(doc(como(MIEMBRO_B), 'chats', 'cAdop')));
    await assertFails(getDocs(chatsEquipo(como(MIEMBRO_B), RESP)));
    await assertSucceeds(getDoc(doc(como(MIEMBRO_B), 'chats', 'cOtroAlbergue')));
  });
  it('membresía revocada o inexistente: nada', async () => {
    for (const uid of [REVOCADA, NADIE]) {
      await assertFails(getDoc(doc(como(uid), 'chats', 'cAdop')));
      await assertFails(getDocs(chatsEquipo(como(uid), RESP)));
      await assertFails(getDocs(collection(como(uid), 'chats', 'cAdop', 'mensajes')));
    }
  });
});

// ─── Chats: escrituras ───────────────────────────────────────────────────

describe('chats: tipoSolicitud fijo después de crear', () => {
  it('nadie cambia el tipo de un chat (ni la responsable ni el adoptante)', async () => {
    await assertFails(updateDoc(doc(como(RESP), 'chats', 'cAdop'), { tipoSolicitud: 'consulta_aliado' }));
    await assertFails(updateDoc(doc(como(ADOPT), 'chats', 'cAdop'), { tipoSolicitud: 'hogar_de_paso' }));
    await assertFails(updateDoc(doc(como(RESP), 'chats', 'cAliadoRecibida'), { tipoSolicitud: 'consulta' }));
  });
  it('a un chat sin tipo nadie le agrega uno (ni con merge, como al reabrirlo)', async () => {
    await assertFails(updateDoc(doc(como(RESP), 'chats', 'cSinTipo'), { tipoSolicitud: 'adopcion' }));
    await assertFails(setDoc(doc(como(ADOPT), 'chats', 'cSinTipo'), { tipoSolicitud: 'adopcion' }, { merge: true }));
  });
  it('tampoco se puede borrar el tipo', async () => {
    await assertFails(updateDoc(doc(como(RESP), 'chats', 'cAdop'), { tipoSolicitud: deleteField() }));
  });
  it('las actualizaciones normales siguen funcionando', async () => {
    await assertSucceeds(updateDoc(doc(como(RESP), 'chats', 'cAdop'), { ultimoMensaje: 'Hola', noLeidosRescatista: 0 }));
    await assertSucceeds(setDoc(doc(como(ADOPT), 'chats', 'cSinTipo'), { adoptanteNombre: 'Ana' }, { merge: true }));
  });
});

describe('chats: el tipo de un chat nuevo sale del contexto real', () => {
  const chatAnimal = (extra) => ({
    adoptanteId: ADOPT, rescatistaId: RESP, creadoPor: 'albergue', rescateId: 'rA',
    adoptanteNombre: 'Ana', rescatista: 'La Perla', ...extra,
  });
  it('chat de un animal con tipo adopcion, o sin tipo (versiones viejas de la app): se crea', async () => {
    await assertSucceeds(setDoc(doc(como(ADOPT), 'chats', 'nuevo1'), chatAnimal({ tipoSolicitud: 'adopcion' })));
    await assertSucceeds(setDoc(doc(como(ADOPT), 'chats', 'nuevo2'), chatAnimal({})));
  });
  it('chat de un animal disfrazado de consulta a negocio aliado o con un tipo inventado: rechazado', async () => {
    await assertFails(setDoc(doc(como(ADOPT), 'chats', 'nuevo3'), chatAnimal({ tipoSolicitud: 'consulta_aliado' })));
    await assertFails(setDoc(doc(como(ADOPT), 'chats', 'nuevo4'), chatAnimal({ tipoSolicitud: 'zzz' })));
  });
  it('sombrero de albergue y tipo sobre una solicitud PERSONAL de la responsable: rechazado', async () => {
    await assertFails(setDoc(doc(como(ADOPT), 'chats', 'nuevo5'), {
      adoptanteId: ADOPT, rescatistaId: RESP, solicitudId: 'sPersonal', creadoPor: 'albergue', tipoSolicitud: 'adopcion',
    }));
  });
  it('sobre una solicitud del albergue, con tipo: se crea; sin tipo sigue funcionando como antes', async () => {
    await assertSucceeds(setDoc(doc(como(ADOPT), 'chats', 'nuevo6'), {
      adoptanteId: ADOPT, rescatistaId: RESP, solicitudId: 'sAlbergue', creadoPor: 'albergue', tipoSolicitud: 'adopcion',
    }));
    await assertSucceeds(setDoc(doc(como(ADOPT), 'chats', 'nuevo7'), {
      adoptanteId: ADOPT, rescatistaId: RESP, solicitudId: 'sPersonal', creadoPor: 'rescatista',
    }));
  });
});

// ─── Colecciones del equipo ──────────────────────────────────────────────

const conCorreo = (uid, email, verificado = true) =>
  env.authenticatedContext(uid, { email, email_verified: verificado }).firestore();

describe('membresias: cada persona la suya, la responsable las de su albergue', () => {
  it('una miembro lee su propia membresía; otra persona no', async () => {
    await assertSucceeds(getDoc(doc(como(MIEMBRO), 'membresias', MIEMBRO)));
    await assertSucceeds(getDoc(doc(como(REVOCADA), 'membresias', REVOCADA)));
    await assertFails(getDoc(doc(como(NADIE), 'membresias', MIEMBRO)));
    await assertFails(getDoc(doc(como(MIEMBRO_B), 'membresias', MIEMBRO)));
  });
  it('la responsable lee las de su albergue (doc y lista filtrada); la de otro albergue no', async () => {
    await assertSucceeds(getDoc(doc(como(RESP), 'membresias', MIEMBRO)));
    await assertSucceeds(getDocs(query(collection(como(RESP), 'membresias'), where('albergueId', '==', RESP))));
    await assertFails(getDoc(doc(como(RESP_B), 'membresias', MIEMBRO)));
    await assertFails(getDocs(query(collection(como(RESP_B), 'membresias'), where('albergueId', '==', RESP))));
  });
  it('una miembro no lista el resto del equipo; nadie lista sin filtro', async () => {
    await assertFails(getDocs(query(collection(como(MIEMBRO), 'membresias'), where('albergueId', '==', RESP))));
    for (const uid of [RESP, MIEMBRO, NADIE]) await assertFails(getDocs(collection(como(uid), 'membresias')));
  });
  it('nadie escribe membresías desde la app, ni la propia ni la responsable', async () => {
    await assertFails(setDoc(doc(como(NADIE), 'membresias', NADIE), { albergueId: RESP, estado: 'activa' }));
    await assertFails(updateDoc(doc(como(REVOCADA), 'membresias', REVOCADA), { estado: 'activa' }));
    await assertFails(deleteDoc(doc(como(MIEMBRO), 'membresias', MIEMBRO)));
    await assertFails(updateDoc(doc(como(RESP), 'membresias', MIEMBRO), { estado: 'revocada' }));
    await assertFails(deleteDoc(doc(como(RESP), 'membresias', MIEMBRO)));
  });
});

describe('invitaciones: la responsable las suyas, cada persona las de su correo verificado', () => {
  const INV = { albergueId: RESP, albergueNombre: 'La Perla', emailDestino: 'ana@mail.com', estado: 'pendiente' };
  beforeEach(async () => {
    await sembrar(async (db) => {
      await setDoc(doc(db, 'invitaciones', 'inv1'), INV);
      await setDoc(doc(db, 'invitaciones', 'invB'), { ...INV, albergueId: RESP_B, emailDestino: 'otra@mail.com' });
    });
  });
  const deAna = (db) => query(collection(db, 'invitaciones'), where('emailDestino', '==', 'ana@mail.com'), where('estado', '==', 'pendiente'));
  it('la responsable lee las de su albergue; la de otro albergue no', async () => {
    await assertSucceeds(getDoc(doc(como(RESP), 'invitaciones', 'inv1')));
    await assertSucceeds(getDocs(query(collection(como(RESP), 'invitaciones'), where('albergueId', '==', RESP))));
    await assertFails(getDoc(doc(como(RESP_B), 'invitaciones', 'inv1')));
    await assertFails(getDocs(query(collection(como(RESP_B), 'invitaciones'), where('albergueId', '==', RESP))));
  });
  it('la persona invitada las lee con su correo verificado, aunque lo escriba con mayúsculas', async () => {
    await assertSucceeds(getDoc(doc(conCorreo(NADIE, 'Ana@Mail.com'), 'invitaciones', 'inv1')));
    await assertSucceeds(getDocs(deAna(conCorreo(NADIE, 'ana@mail.com'))));
  });
  it('correo sin verificar, sin correo o con otro correo: nada', async () => {
    await assertFails(getDoc(doc(conCorreo(NADIE, 'ana@mail.com', false), 'invitaciones', 'inv1')));
    await assertFails(getDocs(deAna(conCorreo(NADIE, 'ana@mail.com', false))));
    await assertFails(getDoc(doc(como(NADIE), 'invitaciones', 'inv1')));
    await assertFails(getDoc(doc(conCorreo(ADOPT, 'otra@mail.com'), 'invitaciones', 'inv1')));
    await assertFails(getDocs(deAna(conCorreo(ADOPT, 'otra@mail.com'))));
  });
  it('nadie lista sin filtro; una miembro no ve las invitaciones del albergue', async () => {
    for (const uid of [RESP, MIEMBRO, NADIE]) await assertFails(getDocs(collection(como(uid), 'invitaciones')));
    await assertFails(getDocs(query(collection(como(MIEMBRO), 'invitaciones'), where('albergueId', '==', RESP))));
  });
  it('nadie crea, acepta ni cancela desde la app (solo las Functions)', async () => {
    await assertFails(setDoc(doc(como(RESP), 'invitaciones', 'nueva'), { ...INV, emailDestino: 'x@mail.com' }));
    await assertFails(updateDoc(doc(conCorreo(NADIE, 'ana@mail.com'), 'invitaciones', 'inv1'), { estado: 'aceptada' }));
    await assertFails(updateDoc(doc(como(RESP), 'invitaciones', 'inv1'), { estado: 'cancelada' }));
    await assertFails(deleteDoc(doc(como(RESP), 'invitaciones', 'inv1')));
  });
});

describe('equipos: el contador lo leen la responsable y su equipo activo', () => {
  beforeEach(async () => { await sembrar((db) => setDoc(doc(db, 'equipos', RESP), { miembrosActivos: 1 })); });
  it('responsable y miembro activa leen; otro albergue, revocadas y desconocidas no', async () => {
    await assertSucceeds(getDoc(doc(como(RESP), 'equipos', RESP)));
    await assertSucceeds(getDoc(doc(como(MIEMBRO), 'equipos', RESP)));
    for (const uid of [RESP_B, MIEMBRO_B, REVOCADA, SALIENTE, NADIE]) await assertFails(getDoc(doc(como(uid), 'equipos', RESP)));
  });
  it('nadie lo escribe desde la app', async () => {
    await assertFails(setDoc(doc(como(RESP), 'equipos', RESP), { miembrosActivos: 0 }));
    await assertFails(updateDoc(doc(como(MIEMBRO), 'equipos', RESP), { miembrosActivos: 9 }));
    await assertFails(setDoc(doc(como(NADIE), 'equipos', NADIE), { miembrosActivos: 0 }));
  });
});

// ─── usuarios.trabajaEn ──────────────────────────────────────────────────

describe('usuarios.trabajaEn: solo lo escribe el servidor', () => {
  it('nadie se asigna un albergue al crear su perfil', async () => {
    await assertFails(setDoc(doc(como(NADIE), 'usuarios', NADIE), { roles: ['adoptante'], trabajaEn: RESP }));
    await assertSucceeds(setDoc(doc(como(NADIE), 'usuarios', NADIE), { roles: ['adoptante'] }));
  });
  it('no se agrega, no se cambia y no se borra después', async () => {
    await assertFails(updateDoc(doc(como(ADOPT), 'usuarios', ADOPT), { trabajaEn: RESP }));
    await assertFails(setDoc(doc(como(ADOPT), 'usuarios', ADOPT), { trabajaEn: RESP }, { merge: true }));
    await assertFails(updateDoc(doc(como(MIEMBRO), 'usuarios', MIEMBRO), { trabajaEn: RESP_B }));
    await assertFails(updateDoc(doc(como(MIEMBRO), 'usuarios', MIEMBRO), { trabajaEn: deleteField() }));
  });
  it('regresión: el resto del perfil se sigue guardando como hoy (update y set con merge)', async () => {
    await assertSucceeds(updateDoc(doc(como(MIEMBRO), 'usuarios', MIEMBRO), { ultimaVezActiva: serverTimestamp() }));
    await assertSucceeds(setDoc(doc(como(MIEMBRO), 'usuarios', MIEMBRO), { prefEspecie: 'Gato' }, { merge: true }));
    await assertSucceeds(setDoc(doc(como(MIEMBRO), 'usuarios', MIEMBRO), { ultimoRolActivo: 'adoptante' }, { merge: true }));
    await assertSucceeds(updateDoc(doc(como(ADOPT), 'usuarios', ADOPT), { roles: ['adoptante', 'rescatista'] }));
    let u;
    await sembrar(async (db) => { u = (await getDoc(doc(db, 'usuarios', MIEMBRO))).data(); });
    assert.equal(u.trabajaEn, RESP, 'trabajaEn queda como estaba');
  });
});

// ─── Casos que faltaban (auditoría del 2026-10-22) ──────────────────────

describe('membresías que no están activas', () => {
  for (const [caso, uid] of [['saliente', SALIENTE], ['sin estado', SIN_ESTADO]]) {
    it(`${caso}: ni chats, ni mensajes, ni hogares`, async () => {
      const db = como(uid);
      await assertFails(getDoc(doc(db, 'chats', 'cAdop')));
      await assertFails(getDocs(chatsEquipo(db, RESP)));
      await assertFails(getDocs(collection(db, 'chats', 'cAdop', 'mensajes')));
      await assertFails(getDoc(doc(db, 'hogaresDePaso', 'hSinCampo')));
      await assertFails(getDocs(hogaresEquipo(db, RESP)));
    });
  }
});

describe('sin sesión', () => {
  it('nada del equipo: chats, mensajes, hogares, colecciones del equipo', async () => {
    const db = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'chats', 'cAdop')));
    await assertFails(getDocs(chatsEquipo(db, RESP)));
    await assertFails(getDocs(collection(db, 'chats', 'cAdop', 'mensajes')));
    await assertFails(getDoc(doc(db, 'hogaresDePaso', 'hTrue')));
    await assertFails(getDocs(hogaresEquipo(db, RESP)));
    await assertFails(getDoc(doc(db, 'membresias', MIEMBRO)));
    await assertFails(getDoc(doc(db, 'invitaciones', 'cualquiera')));
    await assertFails(getDoc(doc(db, 'equipos', RESP)));
  });
});

describe('consultas de lista que intentan otro camino', () => {
  it('collectionGroup de mensajes: rechazada, también para una miembro', async () => {
    await assertFails(getDocs(query(collectionGroup(como(MIEMBRO), 'mensajes'))));
    await assertFails(getDocs(query(collectionGroup(como(RESP), 'mensajes'))));
  });
  it('hogares sin decir de qué albergue: rechazada', async () => {
    await assertFails(getDocs(query(collection(como(MIEMBRO), 'hogaresDePaso'))));
    await assertFails(getDocs(query(collection(como(MIEMBRO), 'hogaresDePaso'), where('visibleEquipo', '==', true))));
  });
});

describe('tipo null y solicitudes viejas', () => {
  it('un chat con tipo null no puede recibir un tipo', async () => {
    await assertFails(updateDoc(doc(como(RESP), 'chats', 'cTipoNull'), { tipoSolicitud: 'adopcion' }));
    await assertFails(setDoc(doc(como(ADOPT), 'chats', 'cTipoNull'), { tipoSolicitud: 'hogar_de_paso' }, { merge: true }));
  });
  it('rama C con una solicitud vieja sin creadoPor: con sombrero de albergue y tipo, rechazado; sin tipo, como antes', async () => {
    await assertFails(setDoc(doc(como(ADOPT), 'chats', 'viejo1'), {
      adoptanteId: ADOPT, rescatistaId: RESP, solicitudId: 'sVieja', creadoPor: 'albergue', tipoSolicitud: 'adopcion',
    }));
    await assertSucceeds(setDoc(doc(como(ADOPT), 'chats', 'viejo2'), {
      adoptanteId: ADOPT, rescatistaId: RESP, solicitudId: 'sVieja', creadoPor: 'albergue',
    }));
  });
});

// ─── Roles incompatibles con el equipo (M2) ──────────────────────────────

describe('roles: combinaciones prohibidas con el equipo', () => {
  it('una miembro activa no se suma el rol albergue ni aliado (update, set con merge ni al crear)', async () => {
    const db = como(MIEMBRO);
    await assertFails(updateDoc(doc(db, 'usuarios', MIEMBRO), { roles: ['adoptante', 'rescatista', 'albergue'] }));
    await assertFails(updateDoc(doc(db, 'usuarios', MIEMBRO), { roles: ['adoptante', 'aliado'] }));
    await assertFails(setDoc(doc(db, 'usuarios', MIEMBRO), { roles: ['albergue'] }, { merge: true }));
    // Miembro de B sin perfil todavía: tampoco puede crearlo con esos roles.
    await assertFails(setDoc(doc(como(MIEMBRO_B), 'usuarios', MIEMBRO_B), { roles: ['albergue'] }));
    await assertFails(setDoc(doc(como(MIEMBRO_B), 'usuarios', MIEMBRO_B), { roles: ['aliado'] }));
    await assertSucceeds(setDoc(doc(como(MIEMBRO_B), 'usuarios', MIEMBRO_B), { roles: ['adoptante'] }));
  });
  it('una miembro activa sí maneja sus roles personales (adoptante, rescatista)', async () => {
    const db = como(MIEMBRO);
    await assertSucceeds(updateDoc(doc(db, 'usuarios', MIEMBRO), { roles: ['adoptante'] }));
    await assertSucceeds(updateDoc(doc(db, 'usuarios', MIEMBRO), { roles: ['adoptante', 'rescatista'] }));
  });
  it('membresía revocada o saliente: ya puede sumarse albergue', async () => {
    await assertSucceeds(setDoc(doc(como(REVOCADA), 'usuarios', REVOCADA), { roles: ['albergue'] }));
    await assertSucceeds(setDoc(doc(como(SALIENTE), 'usuarios', SALIENTE), { roles: ['aliado'] }));
  });
  it('responsable con miembros activos no se suma aliado; sin miembros sí', async () => {
    await sembrar((db) => setDoc(doc(db, 'equipos', RESP), { miembrosActivos: 2 }));
    await assertFails(updateDoc(doc(como(RESP), 'usuarios', RESP), { roles: ['albergue', 'aliado'] }));
    await assertFails(setDoc(doc(como(RESP), 'usuarios', RESP), { roles: ['albergue', 'aliado'] }, { merge: true }));
    await assertSucceeds(updateDoc(doc(como(RESP), 'usuarios', RESP), { albergueNombre: 'La Perla 2' }));
    await sembrar((db) => setDoc(doc(db, 'equipos', RESP_B), { miembrosActivos: 0 }));
    await assertSucceeds(updateDoc(doc(como(RESP_B), 'usuarios', RESP_B), { roles: ['albergue', 'aliado'] }));
    await assertSucceeds(updateDoc(doc(como(OTRO_ALB), 'usuarios', OTRO_ALB), { roles: ['albergue', 'aliado'] }));
  });
  it('una cuenta que ya tenía la combinación de antes sigue guardando su perfil', async () => {
    await sembrar(async (db) => {
      await setDoc(doc(db, 'usuarios', MIEMBRO), { roles: ['adoptante', 'albergue'] });
      await setDoc(doc(db, 'usuarios', RESP), { roles: ['albergue', 'aliado'], albergueNombre: 'La Perla' });
      await setDoc(doc(db, 'equipos', RESP), { miembrosActivos: 1 });
    });
    await assertSucceeds(updateDoc(doc(como(MIEMBRO), 'usuarios', MIEMBRO), { prefEspecie: 'Gato' }));
    await assertSucceeds(updateDoc(doc(como(RESP), 'usuarios', RESP), { albergueNombre: 'La Perla 3' }));
  });
});
