// Equipo del albergue, fase 2 ("modo Albergue", 2026-10-25): qué puede
// ESCRIBIR una miembro activa, a nombre del albergue, con las reglas reales
// de Firestore y Storage.
//
// Sí: crear y editar animales del albergue (con su autorUid), borrar solo
// los que cargó ella, leer las solicitudes del albergue, escribir en los
// chats del albergue como el albergue (con su autorUid), poner en cero el
// "sin leer" compartido, crear el chat de un aviso automático, y subir o
// borrar fotos de animales del albergue.
// No: aprobar ni rechazar, borrar animales de otra persona, tocar lo
// personal de la responsable (animales, solicitudes y chats con sombrero
// de rescatista, consultas a negocios aliados), atribuirle algo a otra
// persona, contestarse a sí misma como el albergue, ni nada de esto con la
// membresía revocada, de otro albergue o si la cuenta ya no es albergue.
//
// Ver PLAN-EQUIPO-ALBERGUE.md, sección "Fase 2".

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { before, after, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc, addDoc, collection, query, where, serverTimestamp,
} from 'firebase/firestore';
import { ref, uploadBytes, deleteObject } from 'firebase/storage';

const aca = dirname(fileURLToPath(import.meta.url));

const RESP = 'uid_responsable';       // responsable del albergue A (La Perla)
const MIEMBRO = 'uid_miembro';        // Ana, miembro activa de A
const MIEMBRO2 = 'uid_miembro2';      // otra miembro activa de A
const REVOCADA = 'uid_revocada';
const SALIENTE = 'uid_saliente';
const RESP_B = 'uid_responsable_b';
const MIEMBRO_B = 'uid_miembro_b';    // miembro activa de B
const ADOPT = 'uid_adoptante';
const VET = 'uid_negocio';
const NADIE = 'uid_sin_membresia';
const AJENAS = [REVOCADA, SALIENTE, MIEMBRO_B, NADIE];

let env;
const como = (uid) => env.authenticatedContext(uid).firestore();
const storageDe = (uid) => env.authenticatedContext(uid).storage();
const sembrar = (fn) => env.withSecurityRulesDisabled(async (ctx) => fn(ctx.firestore()));

before(async () => {
  env = await initializeTestEnvironment({
    // El mismo proyecto con el que correr.mjs arranca los emuladores: las
    // reglas de Storage leen Firestore de ese proyecto, no del de la prueba.
    projectId: 'demo-patitas-reglas',
    firestore: { rules: readFileSync(join(aca, '..', 'firestore.rules'), 'utf8'), host: '127.0.0.1', port: 8097 },
    storage: { rules: readFileSync(join(aca, '..', 'storage.rules'), 'utf8'), host: '127.0.0.1', port: 9199 },
  });
});
after(async () => { await env.cleanup(); });

beforeEach(async () => {
  await env.clearFirestore();
  await sembrar(async (db) => {
    await setDoc(doc(db, 'usuarios', RESP), { roles: ['albergue', 'rescatista'], albergueNombre: 'La Perla' });
    await setDoc(doc(db, 'usuarios', RESP_B), { roles: ['albergue'], albergueNombre: 'Huellitas' });
    await setDoc(doc(db, 'usuarios', VET), { roles: ['aliado'] });
    await setDoc(doc(db, 'usuarios', ADOPT), { roles: ['adoptante'] });
    await setDoc(doc(db, 'usuarios', MIEMBRO), { roles: ['adoptante', 'rescatista'], trabajaEn: RESP });
    await setDoc(doc(db, 'membresias', MIEMBRO), { albergueId: RESP, estado: 'activa' });
    await setDoc(doc(db, 'membresias', MIEMBRO2), { albergueId: RESP, estado: 'activa' });
    await setDoc(doc(db, 'membresias', REVOCADA), { albergueId: RESP, estado: 'revocada' });
    await setDoc(doc(db, 'membresias', SALIENTE), { albergueId: RESP, estado: 'saliente' });
    await setDoc(doc(db, 'membresias', MIEMBRO_B), { albergueId: RESP_B, estado: 'activa' });
    // Animales: del albergue cargado por Perla, por Ana, por otra miembro;
    // personal de Perla; personal de Ana; de otro albergue.
    await setDoc(doc(db, 'rescates', 'rA'), { rescatistaId: RESP, creadoPor: 'albergue', nombre: 'Luna' });
    await setDoc(doc(db, 'rescates', 'rDeAna'), { rescatistaId: RESP, creadoPor: 'albergue', nombre: 'Tito', autorUid: MIEMBRO, autorNombre: 'Ana' });
    await setDoc(doc(db, 'rescates', 'rDeOtra'), { rescatistaId: RESP, creadoPor: 'albergue', nombre: 'Coco', autorUid: MIEMBRO2, autorNombre: 'Bea' });
    await setDoc(doc(db, 'rescates', 'rP'), { rescatistaId: RESP, creadoPor: 'rescatista', nombre: 'Personal' });
    await setDoc(doc(db, 'rescates', 'rAnaPersonal'), { rescatistaId: MIEMBRO, creadoPor: 'rescatista', nombre: 'Michi' });
    await setDoc(doc(db, 'rescates', 'rB'), { rescatistaId: RESP_B, creadoPor: 'albergue', nombre: 'De B' });
    // Solicitudes.
    await setDoc(doc(db, 'solicitudes', 'sA'), { adoptanteId: ADOPT, rescatistaId: RESP, rescateId: 'rA', creadoPor: 'albergue', estado: 'pendiente' });
    await setDoc(doc(db, 'solicitudes', 'sP'), { adoptanteId: ADOPT, rescatistaId: RESP, rescateId: 'rP', creadoPor: 'rescatista', estado: 'pendiente' });
    await setDoc(doc(db, 'solicitudes', 'sVieja'), { adoptanteId: ADOPT, rescatistaId: RESP, rescateId: 'rA', estado: 'pendiente' });
    await setDoc(doc(db, 'solicitudes', 'sB'), { adoptanteId: ADOPT, rescatistaId: RESP_B, rescateId: 'rB', creadoPor: 'albergue', estado: 'pendiente' });
    // Chats.
    const chat = (extra) => ({ adoptanteId: ADOPT, rescatistaId: RESP, creadoPor: 'albergue', rescateId: 'rA',
      noLeidosAdoptante: 0, noLeidosRescatista: 3, ...extra });
    await setDoc(doc(db, 'chats', 'cA'), chat({ tipoSolicitud: 'adopcion' }));
    await setDoc(doc(db, 'chats', 'cPersonal'), chat({ creadoPor: 'rescatista', rescateId: 'rP', tipoSolicitud: 'adopcion' }));
    await setDoc(doc(db, 'chats', 'cSinTipo'), chat({}));
    await setDoc(doc(db, 'chats', 'cLegado'), { adoptanteId: ADOPT, rescatistaId: RESP, noLeidosAdoptante: 0, noLeidosRescatista: 1 });
    await setDoc(doc(db, 'chats', 'cAliado'), { adoptanteId: VET, rescatistaId: RESP, creadoPor: 'albergue', tipoSolicitud: 'consulta_aliado' });
    // Ana adoptando un animal de su propio albergue.
    await setDoc(doc(db, 'chats', 'cAnaAdopta'), chat({ adoptanteId: MIEMBRO, tipoSolicitud: 'adopcion' }));
    await setDoc(doc(db, 'chats', 'cB'), chat({ rescatistaId: RESP_B, rescateId: 'rB', tipoSolicitud: 'adopcion' }));
  });
});

const animalNuevo = (extra = {}) => ({
  rescatistaId: RESP, creadoPor: 'albergue', nombre: 'Nuevo', autorUid: MIEMBRO, autorNombre: 'Ana',
  creadoEn: serverTimestamp(), ...extra,
});

// ─── Animales ────────────────────────────────────────────────────────────

describe('animales: la miembro carga y edita a nombre del albergue', () => {
  it('crea un animal del albergue con su autorUid', async () => {
    await assertSucceeds(setDoc(doc(como(MIEMBRO), 'rescates', 'n1'), animalNuevo()));
  });
  it('sin autorUid, con el de otra persona o sin sombrero de albergue: rechazado', async () => {
    const db = como(MIEMBRO);
    const { autorUid, ...sinAutor } = animalNuevo();
    assert.equal(autorUid, MIEMBRO);
    await assertFails(setDoc(doc(db, 'rescates', 'n2'), sinAutor));
    await assertFails(setDoc(doc(db, 'rescates', 'n3'), animalNuevo({ autorUid: MIEMBRO2 })));
    await assertFails(setDoc(doc(db, 'rescates', 'n4'), animalNuevo({ autorUid: RESP })));
    await assertFails(setDoc(doc(db, 'rescates', 'n5'), animalNuevo({ creadoPor: 'rescatista' })));
  });
  it('no publica a nombre de otro albergue', async () => {
    await assertFails(setDoc(doc(como(MIEMBRO), 'rescates', 'n6'), animalNuevo({ rescatistaId: RESP_B })));
  });
  it('un autorNombre gigante o que no es texto: rechazado', async () => {
    const db = como(MIEMBRO);
    await assertFails(setDoc(doc(db, 'rescates', 'n7'), animalNuevo({ autorNombre: 'x'.repeat(101) })));
    await assertFails(setDoc(doc(db, 'rescates', 'n8'), animalNuevo({ autorNombre: 42 })));
  });
  it('edita cualquier animal del albergue (los de Perla, los suyos, los de otra miembro)', async () => {
    const db = como(MIEMBRO);
    for (const id of ['rA', 'rDeAna', 'rDeOtra']) {
      await assertSucceeds(updateDoc(doc(db, 'rescates', id), { estadoAdopcion: 'En proceso de adopción', edad: '2 años' }));
    }
  });
  it('al editar no cambia el dueño, el sombrero, ni quién lo cargó', async () => {
    const db = como(MIEMBRO);
    await assertFails(updateDoc(doc(db, 'rescates', 'rA'), { rescatistaId: MIEMBRO }));
    await assertFails(updateDoc(doc(db, 'rescates', 'rA'), { creadoPor: 'rescatista' }));
    await assertFails(updateDoc(doc(db, 'rescates', 'rDeOtra'), { autorUid: MIEMBRO }));
    await assertFails(updateDoc(doc(db, 'rescates', 'rDeOtra'), { autorNombre: 'Ana' }));
    await assertFails(updateDoc(doc(db, 'rescates', 'rA'), { autorUid: MIEMBRO }));
  });
  it('no toca animales personales de Perla, de otro albergue, ni de otra cuenta', async () => {
    const db = como(MIEMBRO);
    await assertFails(updateDoc(doc(db, 'rescates', 'rP'), { edad: '1' }));
    await assertFails(updateDoc(doc(db, 'rescates', 'rB'), { edad: '1' }));
    await assertFails(deleteDoc(doc(db, 'rescates', 'rP')));
  });
  it('sus animales personales de rescatista siguen como siempre', async () => {
    const db = como(MIEMBRO);
    await assertSucceeds(setDoc(doc(db, 'rescates', 'propio'), { rescatistaId: MIEMBRO, creadoPor: 'rescatista', nombre: 'Michi 2' }));
    await assertSucceeds(updateDoc(doc(db, 'rescates', 'rAnaPersonal'), { edad: '3' }));
  });
  it('no publica como albergue a su propio nombre (no tiene ese rol)', async () => {
    await assertFails(setDoc(doc(como(MIEMBRO), 'rescates', 'n9'), animalNuevo({ rescatistaId: MIEMBRO })));
  });
});

describe('animales: borrar', () => {
  it('la miembro borra un animal que cargó ella', async () => {
    await assertSucceeds(deleteDoc(doc(como(MIEMBRO), 'rescates', 'rDeAna')));
  });
  it('no borra los que cargó Perla ni los de otra miembro', async () => {
    await assertFails(deleteDoc(doc(como(MIEMBRO), 'rescates', 'rA')));
    await assertFails(deleteDoc(doc(como(MIEMBRO), 'rescates', 'rDeOtra')));
  });
  it('la responsable borra cualquiera del albergue, también los que cargó Ana', async () => {
    await assertSucceeds(deleteDoc(doc(como(RESP), 'rescates', 'rDeAna')));
    await assertSucceeds(deleteDoc(doc(como(RESP), 'rescates', 'rA')));
  });
  it('si ya no es del equipo, no borra ni lo que cargó ella', async () => {
    await sembrar((db) => setDoc(doc(db, 'membresias', MIEMBRO), { albergueId: RESP, estado: 'revocada' }));
    await assertFails(deleteDoc(doc(como(MIEMBRO), 'rescates', 'rDeAna')));
  });
});

describe('animales: la responsable sigue igual', () => {
  it('crea sin autorUid, o con el suyo; no a nombre de una miembro', async () => {
    const db = como(RESP);
    await assertSucceeds(setDoc(doc(db, 'rescates', 'p1'), { rescatistaId: RESP, creadoPor: 'albergue', nombre: 'A' }));
    await assertSucceeds(setDoc(doc(db, 'rescates', 'p2'), { rescatistaId: RESP, creadoPor: 'albergue', nombre: 'B', autorUid: RESP, autorNombre: 'Perla' }));
    await assertFails(setDoc(doc(db, 'rescates', 'p3'), { rescatistaId: RESP, creadoPor: 'albergue', nombre: 'C', autorUid: MIEMBRO }));
  });
  it('edita sin poder cambiar quién cargó el animal', async () => {
    await assertSucceeds(updateDoc(doc(como(RESP), 'rescates', 'rDeAna'), { edad: '5' }));
    await assertFails(updateDoc(doc(como(RESP), 'rescates', 'rDeAna'), { autorUid: RESP }));
  });
});

describe('animales: membresías que no sirven', () => {
  it('revocada, saliente, de otro albergue o sin membresía: no crea, no edita, no borra', async () => {
    for (const uid of AJENAS) {
      const db = como(uid);
      await assertFails(setDoc(doc(db, 'rescates', `x_${uid}`), animalNuevo({ autorUid: uid })));
      await assertFails(updateDoc(doc(db, 'rescates', 'rA'), { edad: '1' }));
      await assertFails(deleteDoc(doc(db, 'rescates', 'rA')));
    }
  });
  it('si la cuenta del albergue deja de ser albergue, la miembro no carga ni edita', async () => {
    await sembrar((db) => setDoc(doc(db, 'usuarios', RESP), { roles: ['rescatista'], albergueNombre: 'La Perla' }));
    await assertFails(setDoc(doc(como(MIEMBRO), 'rescates', 'n10'), animalNuevo()));
    await assertFails(updateDoc(doc(como(MIEMBRO), 'rescates', 'rA'), { edad: '1' }));
  });
});

// ─── Solicitudes ─────────────────────────────────────────────────────────

const solicitudesEquipo = (db, albergue) =>
  query(collection(db, 'solicitudes'), where('rescatistaId', '==', albergue), where('creadoPor', '==', 'albergue'));

describe('solicitudes: la miembro lee las del albergue y no decide', () => {
  it('lee una solicitud del albergue y la lista filtrada', async () => {
    await assertSucceeds(getDoc(doc(como(MIEMBRO), 'solicitudes', 'sA')));
    const snap = await assertSucceeds(getDocs(solicitudesEquipo(como(MIEMBRO), RESP)));
    assert.deepEqual(snap.docs.map((d) => d.id), ['sA']);
  });
  it('no lee las personales de Perla, las viejas sin sombrero, ni las de otro albergue', async () => {
    const db = como(MIEMBRO);
    await assertFails(getDoc(doc(db, 'solicitudes', 'sP')));
    await assertFails(getDoc(doc(db, 'solicitudes', 'sVieja')));
    await assertFails(getDoc(doc(db, 'solicitudes', 'sB')));
    await assertFails(getDocs(query(collection(db, 'solicitudes'), where('rescatistaId', '==', RESP))));
    await assertFails(getDocs(solicitudesEquipo(db, RESP_B)));
  });
  it('no aprueba ni rechaza', async () => {
    const db = como(MIEMBRO);
    await assertFails(updateDoc(doc(db, 'solicitudes', 'sA'), { estado: 'aprobada' }));
    await assertFails(updateDoc(doc(db, 'solicitudes', 'sA'), { estado: 'rechazada', motivoRechazo: 'x' }));
  });
  it('la responsable sigue aprobando', async () => {
    await assertSucceeds(updateDoc(doc(como(RESP), 'solicitudes', 'sA'), { estado: 'aprobada' }));
  });
  it('revocada, saliente, de otro albergue o sin membresía: no lee', async () => {
    for (const uid of AJENAS) {
      await assertFails(getDoc(doc(como(uid), 'solicitudes', 'sA')));
      await assertFails(getDocs(solicitudesEquipo(como(uid), RESP)));
    }
  });
});

describe('solicitudes: el sombrero sale del animal', () => {
  const nueva = (extra) => ({ adoptanteId: ADOPT, rescatistaId: RESP, estado: 'pendiente', ...extra });
  it('sobre un animal del albergue con sombrero de albergue, o sin el campo: se crea', async () => {
    await assertSucceeds(setDoc(doc(como(ADOPT), 'solicitudes', 'n1'), nueva({ rescateId: 'rA', creadoPor: 'albergue' })));
    await assertSucceeds(setDoc(doc(como(ADOPT), 'solicitudes', 'n2'), nueva({ rescateId: 'rA' })));
    await assertSucceeds(setDoc(doc(como(ADOPT), 'solicitudes', 'n3'), nueva({ rescateId: 'rP', creadoPor: 'rescatista' })));
  });
  it('sobre un animal personal de Perla disfrazada de albergue: rechazada (si no, el equipo la vería)', async () => {
    await assertFails(setDoc(doc(como(ADOPT), 'solicitudes', 'n4'), nueva({ rescateId: 'rP', creadoPor: 'albergue' })));
  });
  it('sobre un animal del albergue disfrazada de personal: rechazada', async () => {
    await assertFails(setDoc(doc(como(ADOPT), 'solicitudes', 'n5'), nueva({ rescateId: 'rA', creadoPor: 'rescatista' })));
  });
});

// ─── Chats ───────────────────────────────────────────────────────────────

const mensaje = (extra = {}) => ({ texto: 'Hola, soy del albergue', emisor: 'rescatista', autorUid: MIEMBRO, autorNombre: 'Ana', creadoEn: serverTimestamp(), ...extra });

describe('chats: la miembro escribe como el albergue', () => {
  it('manda un mensaje en un chat del albergue, con su autorUid', async () => {
    await assertSucceeds(addDoc(collection(como(MIEMBRO), 'chats', 'cA', 'mensajes'), mensaje()));
  });
  it('sin autorUid, con el de otra persona, o como adoptante: rechazado', async () => {
    const db = como(MIEMBRO);
    const { autorUid, ...sinAutor } = mensaje();
    assert.equal(autorUid, MIEMBRO);
    await assertFails(addDoc(collection(db, 'chats', 'cA', 'mensajes'), sinAutor));
    await assertFails(addDoc(collection(db, 'chats', 'cA', 'mensajes'), mensaje({ autorUid: RESP })));
    await assertFails(addDoc(collection(db, 'chats', 'cA', 'mensajes'), mensaje({ emisor: 'adoptante' })));
  });
  it('el texto sigue con tope y la fecha la sigue poniendo el servidor', async () => {
    const db = como(MIEMBRO);
    await assertFails(addDoc(collection(db, 'chats', 'cA', 'mensajes'), mensaje({ texto: 'x'.repeat(2001) })));
    await assertFails(addDoc(collection(db, 'chats', 'cA', 'mensajes'), mensaje({ creadoEn: new Date(Date.UTC(2099, 0, 1)) })));
  });
  it('actualiza el resumen del chat y pone en cero el "sin leer" del albergue', async () => {
    const db = como(MIEMBRO);
    await assertSucceeds(updateDoc(doc(db, 'chats', 'cA'), { ultimoMensaje: 'Hola', noLeidosAdoptante: 1 }));
    await assertSucceeds(updateDoc(doc(db, 'chats', 'cA'), { noLeidosRescatista: 0 }));
  });
  it('no inventa contadores, ni pone en cero el del adoptante, ni cambia de quién es el chat', async () => {
    const db = como(MIEMBRO);
    await assertFails(updateDoc(doc(db, 'chats', 'cA'), { noLeidosRescatista: 99 }));
    await assertFails(updateDoc(doc(db, 'chats', 'cA'), { noLeidosAdoptante: 5 }));
    await sembrar((s) => updateDoc(doc(s, 'chats', 'cA'), { noLeidosAdoptante: 4 }));
    await assertFails(updateDoc(doc(db, 'chats', 'cA'), { noLeidosAdoptante: 0 }));
    await assertFails(updateDoc(doc(db, 'chats', 'cA'), { rescatistaId: MIEMBRO }));
    await assertFails(updateDoc(doc(db, 'chats', 'cA'), { adoptanteId: MIEMBRO }));
    await assertFails(updateDoc(doc(db, 'chats', 'cA'), { creadoPor: 'rescatista' }));
  });
  it('no escribe en chats personales de Perla, sin tipo, legados, consultas a negocios ni de otro albergue', async () => {
    const db = como(MIEMBRO);
    for (const id of ['cPersonal', 'cSinTipo', 'cLegado', 'cAliado', 'cB']) {
      await assertFails(addDoc(collection(db, 'chats', id, 'mensajes'), mensaje()));
      await assertFails(updateDoc(doc(db, 'chats', id), { noLeidosRescatista: 0 }));
    }
  });
  it('en un chat donde ella es la adoptante, no se contesta como el albergue', async () => {
    const db = como(MIEMBRO);
    await assertFails(addDoc(collection(db, 'chats', 'cAnaAdopta', 'mensajes'), mensaje()));
    // Como adoptante sigue escribiendo normal.
    await assertSucceeds(addDoc(collection(db, 'chats', 'cAnaAdopta', 'mensajes'), { texto: 'Hola', emisor: 'adoptante', creadoEn: serverTimestamp() }));
  });
  it('revocada, saliente, de otro albergue o sin membresía: no escribe', async () => {
    for (const uid of AJENAS) {
      await assertFails(addDoc(collection(como(uid), 'chats', 'cA', 'mensajes'), mensaje({ autorUid: uid })));
      await assertFails(updateDoc(doc(como(uid), 'chats', 'cA'), { noLeidosRescatista: 0 }));
    }
  });
});

describe('chats: los participantes siguen igual', () => {
  it('el adoptante escribe y actualiza su chat, también los legados sin creadoPor ni tipo', async () => {
    const db = como(ADOPT);
    await assertSucceeds(addDoc(collection(db, 'chats', 'cA', 'mensajes'), { texto: 'Hola', emisor: 'adoptante', creadoEn: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(db, 'chats', 'cA'), { noLeidosRescatista: 4 }));
    await assertSucceeds(addDoc(collection(db, 'chats', 'cLegado', 'mensajes'), { texto: 'Hola', emisor: 'adoptante', creadoEn: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(db, 'chats', 'cLegado'), { noLeidosRescatista: 2, ultimoMensaje: 'Hola' }));
  });
  it('el adoptante no se hace pasar por una miembro ni pone en cero el "sin leer" del albergue', async () => {
    const db = como(ADOPT);
    await assertFails(addDoc(collection(db, 'chats', 'cA', 'mensajes'), { texto: 'x', emisor: 'adoptante', autorUid: MIEMBRO, creadoEn: serverTimestamp() }));
    await assertFails(updateDoc(doc(db, 'chats', 'cA'), { noLeidosRescatista: 0 }));
  });
  it('la responsable escribe con o sin su autorUid, nunca con el de Ana', async () => {
    const db = como(RESP);
    await assertSucceeds(addDoc(collection(db, 'chats', 'cA', 'mensajes'), { texto: 'Hola', emisor: 'rescatista', creadoEn: serverTimestamp() }));
    await assertSucceeds(addDoc(collection(db, 'chats', 'cA', 'mensajes'), mensaje({ autorUid: RESP, autorNombre: 'Perla' })));
    await assertFails(addDoc(collection(db, 'chats', 'cA', 'mensajes'), mensaje()));
  });
});

describe('chats: crear el chat de un aviso automático', () => {
  const avisoChat = (extra) => ({
    adoptanteId: ADOPT, rescatistaId: RESP, creadoPor: 'albergue', rescateId: 'rA', tipoSolicitud: 'adopcion',
    noLeidosAdoptante: 0, noLeidosRescatista: 0, ...extra,
  });
  it('la miembro crea, del lado del albergue, el chat sobre un animal o una solicitud del albergue', async () => {
    await assertSucceeds(setDoc(doc(como(MIEMBRO), 'chats', 'aviso1'), avisoChat()));
    await assertSucceeds(setDoc(doc(como(MIEMBRO), 'chats', 'aviso2'), avisoChat({ rescateId: '', solicitudId: 'sA' })));
  });
  it('sin tipo, sobre un animal personal de Perla, de otro albergue o como consulta a un negocio: rechazado', async () => {
    const db = como(MIEMBRO);
    const { tipoSolicitud, ...sinTipo } = avisoChat();
    assert.equal(tipoSolicitud, 'adopcion');
    await assertFails(setDoc(doc(db, 'chats', 'aviso3'), sinTipo));
    await assertFails(setDoc(doc(db, 'chats', 'aviso4'), avisoChat({ rescateId: 'rP', creadoPor: 'rescatista' })));
    await assertFails(setDoc(doc(db, 'chats', 'aviso5'), avisoChat({ rescateId: 'rP' })));
    await assertFails(setDoc(doc(db, 'chats', 'aviso6'), avisoChat({ rescatistaId: RESP_B, rescateId: 'rB' })));
    await assertFails(setDoc(doc(db, 'chats', 'aviso7'), avisoChat({ rescatistaId: VET, rescateId: '', tipoSolicitud: 'consulta_aliado' })));
    await assertFails(setDoc(doc(db, 'chats', 'aviso8'), avisoChat({ rescateId: '', solicitudId: 'sP' })));
  });
  it('revocada, saliente, de otro albergue o sin membresía: no crea', async () => {
    for (const uid of AJENAS) await assertFails(setDoc(doc(como(uid), 'chats', `aviso_${uid}`), avisoChat()));
  });
});

// ─── Fotos (Storage) ─────────────────────────────────────────────────────

const JPG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 0, 0, 0]);
const subir = (uid, rescateId, archivo = 'foto1.jpg') =>
  uploadBytes(ref(storageDe(uid), `rescates/${rescateId}/${archivo}`), JPG, { contentType: 'image/jpeg' });
const borrar = (uid, rescateId) => deleteObject(ref(storageDe(uid), `rescates/${rescateId}/foto1.jpg`));
const sembrarFoto = (rescateId) => env.withSecurityRulesDisabled((ctx) =>
  uploadBytes(ref(ctx.storage(), `rescates/${rescateId}/foto1.jpg`), JPG, { contentType: 'image/jpeg' }));

describe('fotos: la miembro sube y borra fotos de animales del albergue', () => {
  beforeEach(async () => { await env.clearStorage(); });
  it('sube fotos de un animal del albergue (de Perla, suyo o de otra miembro) y las borra', async () => {
    for (const id of ['rA', 'rDeAna', 'rDeOtra']) {
      await assertSucceeds(subir(MIEMBRO, id));
      await assertSucceeds(borrar(MIEMBRO, id));
    }
  });
  it('no toca fotos de animales personales de Perla ni de otro albergue', async () => {
    await sembrarFoto('rP');
    await assertFails(subir(MIEMBRO, 'rP'));
    await assertFails(borrar(MIEMBRO, 'rP'));
    await assertFails(subir(MIEMBRO, 'rB'));
  });
  it('los nombres y el tipo de archivo siguen acotados', async () => {
    await assertFails(subir(MIEMBRO, 'rA', 'otra.jpg'));
    await assertFails(uploadBytes(ref(storageDe(MIEMBRO), 'rescates/rA/foto1.jpg'), JPG, { contentType: 'text/plain' }));
  });
  it('revocada, saliente, de otro albergue o sin membresía: nada', async () => {
    await sembrarFoto('rA');
    for (const uid of AJENAS) {
      await assertFails(subir(uid, 'rA'));
      await assertFails(borrar(uid, 'rA'));
    }
  });
  it('la responsable y el dueño de un animal personal siguen como siempre', async () => {
    await assertSucceeds(subir(RESP, 'rA'));
    await assertSucceeds(subir(RESP, 'rP'));
    await assertSucceeds(subir(MIEMBRO, 'rAnaPersonal'));
    await assertFails(subir(RESP, 'rAnaPersonal'));
  });
});
