// Prueba de extremo a extremo del ciclo de vida completo de un animal,
// contra el emulador REAL de Firestore (no fake_cloud_firestore, que no
// aplica reglas de seguridad — ver el comentario de reglas.test.mjs).
//
// Por qué existe, aparte de reglas.test.mjs: ese archivo prueba invariantes
// AISLADAS (¿se puede crear esto? ¿se puede leer aquello?). Este archivo
// reproduce la SECUENCIA completa que un rescatista, un albergue y un
// adoptante viven de verdad, un paso atrás del otro — publicar, solicitar,
// aprobar, rechazar, marcar un desenlace — exactamente como lo pidió Eliza:
// "crea un animalito desde el rescatista y albergue... adóptalo y rechaza y
// hogar de paso, todo, que todo funcione". El bug más grave de toda la
// sesión (el aviso de "falleció"/rechazo que no le llegaba a nadie con
// quien nunca hubo chat) solo se vio probando la secuencia real, no reglas
// sueltas — por eso vale la pena tener las dos formas de prueba.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { before, after, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  doc,
  getDoc,
  getDocs,
  setDoc,
  updateDoc,
  collection,
  addDoc,
  serverTimestamp,
} from 'firebase/firestore';

const aca = dirname(fileURLToPath(import.meta.url));

const RESCATISTA = 'uid_rescatista';
const ALBERGUE = 'uid_albergue';
const ADOPTANTE = 'uid_adoptante';
const OTRO = 'uid_intruso';

let testEnv;
const como = (uid) => testEnv.authenticatedContext(uid).firestore();
async function sembrar(fn) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => fn(ctx.firestore()));
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'patitas-ciclo-vida-test',
    firestore: {
      rules: readFileSync(join(aca, '..', 'firestore.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 8097,
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await sembrar(async (db) => {
    await setDoc(doc(db, 'usuarios', RESCATISTA), {
      roles: ['rescatista'],
      nombre: 'Eliza Rescatista',
    });
    await setDoc(doc(db, 'usuarios', ALBERGUE), {
      roles: ['albergue'],
      albergueNombre: 'Refugio Patitas',
    });
    await setDoc(doc(db, 'usuarios', ADOPTANTE), {
      roles: ['adoptante'],
      nombre: 'Ana Adoptante',
    });
    await setDoc(doc(db, 'usuarios', OTRO), { roles: ['adoptante'] });
  });
});

// Mismo esquema de id que ChatsRepository.idAnimal (lib/data/
// chats_repository.dart): '${rescateId}_${adoptanteId}'.
const idChat = (rescateId, adoptanteId) => `${rescateId}_${adoptanteId}`;

// Mismo patrón de DOS escrituras separadas que ChatsRepository.
// avisarSobreAnimal() (lib/data/chats_repository.dart) usa para un chat que
// todavía no existe — nunca un solo batch, porque mensajes.create hace
// get(chats/{chatId}) para decidir el emisor, y esa lectura no ve el
// propio chat si se crea EN EL MISMO batch (ver el comentario largo en
// chats_repository.dart). Reproducir el patrón real del cliente acá, no
// una versión simplificada, es lo que hace que esta prueba sirva de algo.
async function avisarPrimeraVez(
  db,
  { rescateId, adoptanteId, adoptanteNombre, rescatistaId, rescatista, creadoPor, animalNombre, texto, emisor },
) {
  const chatRef = doc(db, 'chats', idChat(rescateId, adoptanteId));
  await setDoc(
    chatRef,
    {
      rescateId,
      adoptanteId,
      adoptanteNombre,
      rescatistaId,
      rescatista,
      creadoPor,
      animalNombre,
      ultimoMensaje: texto,
      noLeidosAdoptante: 1,
      noLeidosRescatista: 0,
    },
    { merge: true },
  );
  return addDoc(collection(db, 'chats', idChat(rescateId, adoptanteId), 'mensajes'), {
    texto,
    emisor,
    hora: '10:00',
    creadoEn: serverTimestamp(),
    escritoPorRescatista: true,
  });
}

describe('Ciclo de vida completo de un animal', () => {
  it(
    'rescatista Y albergue publican, adoptante pide adopción y hogar de paso, '
    + 'se aprueba una y se rechaza la otra, y las dos avisan por chat — '
    + 'incluyendo el caso que más falló en la sesión: nunca hubo chat previo',
    async () => {
      const dbRescatista = como(RESCATISTA);
      const dbAlbergue = como(ALBERGUE);
      const dbAdoptante = como(ADOPTANTE);

      // 1) Rescatista publica un animal.
      await assertSucceeds(
        setDoc(doc(dbRescatista, 'rescates', 'animalR'), {
          rescatistaId: RESCATISTA,
          creadoPor: 'rescatista',
          nombre: 'Toby',
          especie: 'Perro',
          estadoAdopcion: 'Rescatado',
          fotoUrl: 'https://ejemplo.test/toby.jpg',
        }),
      );

      // 2) Albergue publica un animal.
      await assertSucceeds(
        setDoc(doc(dbAlbergue, 'rescates', 'animalA'), {
          rescatistaId: ALBERGUE,
          creadoPor: 'albergue',
          nombre: 'Luna',
          especie: 'Gato',
          estadoAdopcion: 'Rescatado',
          fotoUrl: 'https://ejemplo.test/luna.jpg',
        }),
      );

      // 3) Adoptante pide ADOPCIÓN para el animal del rescatista — nunca
      // chateó antes con esta cuenta.
      const solAdopcionRef = doc(collection(dbAdoptante, 'solicitudes'));
      await assertSucceeds(
        setDoc(solAdopcionRef, {
          adoptanteId: ADOPTANTE,
          rescatistaId: RESCATISTA,
          rescateId: 'animalR',
          animalNombre: 'Toby',
          tipoSolicitud: 'adopcion',
          estado: 'pendiente',
        }),
      );

      // 4) Adoptante pide HOGAR DE PASO para el animal del albergue —
      // tampoco chateó antes con esta cuenta.
      const solHogarRef = doc(collection(dbAdoptante, 'solicitudes'));
      await assertSucceeds(
        setDoc(solHogarRef, {
          adoptanteId: ADOPTANTE,
          rescatistaId: ALBERGUE,
          rescateId: 'animalA',
          animalNombre: 'Luna',
          tipoSolicitud: 'hogar_de_paso',
          estado: 'pendiente',
        }),
      );

      // 5) El rescatista APRUEBA la adopción.
      await assertSucceeds(
        updateDoc(doc(dbRescatista, 'solicitudes', solAdopcionRef.id), {
          estado: 'aprobada',
        }),
      );
      // ...y el aviso de aprobación le llega por chat al adoptante — chat
      // nuevo, mismo patrón de dos pasos que usa la app de verdad.
      await assertSucceeds(
        avisarPrimeraVez(dbRescatista, {
          rescateId: 'animalR',
          adoptanteId: ADOPTANTE,
          adoptanteNombre: 'Ana Adoptante',
          rescatistaId: RESCATISTA,
          rescatista: 'Eliza Rescatista',
          creadoPor: 'rescatista',
          animalNombre: 'Toby',
          texto: '¡Tu solicitud de adopción de Toby fue aprobada!',
          emisor: 'rescatista',
          creadoEn: serverTimestamp(),
        }),
      );

      // 6) El albergue RECHAZA el hogar de paso — el caso real que reportó
      // Eliza: "para un rechazo... no está el chat".
      await assertSucceeds(
        updateDoc(doc(dbAlbergue, 'solicitudes', solHogarRef.id), {
          estado: 'rechazada',
          motivoRechazo: 'Ya se asignó a otra familia',
        }),
      );
      await assertSucceeds(
        avisarPrimeraVez(dbAlbergue, {
          rescateId: 'animalA',
          adoptanteId: ADOPTANTE,
          adoptanteNombre: 'Ana Adoptante',
          rescatistaId: ALBERGUE,
          rescatista: 'Refugio Patitas',
          creadoPor: 'albergue',
          animalNombre: 'Luna',
          texto: 'Tu solicitud de hogar de paso para Luna no fue aceptada esta vez.',
          emisor: 'rescatista',
          creadoEn: serverTimestamp(),
        }),
      );

      // El adoptante tiene que poder LEER los dos chats y sus mensajes —
      // sin esto, "Mis solicitudes"/"Mis chats" del lado del adoptante se
      // rompería en silencio (permission-denied) aunque el aviso sí se
      // haya guardado del otro lado.
      const chatAdopcion = await assertSucceeds(
        getDoc(doc(dbAdoptante, 'chats', idChat('animalR', ADOPTANTE))),
      );
      assert.equal(chatAdopcion.data().ultimoMensaje, '¡Tu solicitud de adopción de Toby fue aprobada!');
      const mensajesAdopcion = await assertSucceeds(
        getDocs(collection(dbAdoptante, 'chats', idChat('animalR', ADOPTANTE), 'mensajes')),
      );
      assert.equal(mensajesAdopcion.size, 1);

      const chatHogar = await assertSucceeds(
        getDoc(doc(dbAdoptante, 'chats', idChat('animalA', ADOPTANTE))),
      );
      assert.equal(chatHogar.data().ultimoMensaje, 'Tu solicitud de hogar de paso para Luna no fue aceptada esta vez.');
      const mensajesHogar = await assertSucceeds(
        getDocs(collection(dbAdoptante, 'chats', idChat('animalA', ADOPTANTE), 'mensajes')),
      );
      assert.equal(mensajesHogar.size, 1);

      // 7) El rescatista marca a Toby como Fallecido — el chat YA existe
      // (paso 5), así que acá alcanza con un update()+mensaje nuevo, sin
      // volver a crear el documento del chat.
      await assertSucceeds(
        updateDoc(doc(dbRescatista, 'rescates', 'animalR'), {
          estadoAdopcion: 'Fallecido',
        }),
      );
      await assertSucceeds(
        updateDoc(doc(dbRescatista, 'chats', idChat('animalR', ADOPTANTE)), {
          ultimoMensaje: 'El estado de Toby cambió a Fallecido.',
          noLeidosAdoptante: 2,
        }),
      );
      await assertSucceeds(
        addDoc(collection(dbRescatista, 'chats', idChat('animalR', ADOPTANTE), 'mensajes'), {
          texto: 'El estado de Toby cambió a Fallecido.',
          emisor: 'rescatista',
          creadoEn: serverTimestamp(),
          hora: '10:05',
          creadoEn: serverTimestamp(),
          escritoPorRescatista: true,
        }),
      );

      // Un extraño (OTRO) no puede leer ninguno de los dos chats — ni el
      // de adopción ni el de hogar de paso, sin importar que sean de
      // rescatista o de albergue.
      await assertFails(getDoc(doc(como(OTRO), 'chats', idChat('animalR', ADOPTANTE))));
      await assertFails(getDoc(doc(como(OTRO), 'chats', idChat('animalA', ADOPTANTE))));
    },
  );

  it('un extraño no puede aprobar ni rechazar una solicitud ajena', async () => {
    const dbRescatista = como(RESCATISTA);
    const dbOtro = como(OTRO);
    await sembrar(async (db) => {
      await setDoc(doc(db, 'rescates', 'animalR'), {
        rescatistaId: RESCATISTA,
        creadoPor: 'rescatista',
      });
    });
    const solRef = doc(collection(dbRescatista, 'solicitudes'));
    await sembrar(async (db) =>
      setDoc(doc(db, 'solicitudes', solRef.id), {
        adoptanteId: ADOPTANTE,
        rescatistaId: RESCATISTA,
        rescateId: 'animalR',
        estado: 'pendiente',
      }),
    );

    await assertFails(
      updateDoc(doc(dbOtro, 'solicitudes', solRef.id), { estado: 'aprobada' }),
    );
  });

  it('el adoptante no puede auto-aprobarse su propia solicitud', async () => {
    const dbAdoptante = como(ADOPTANTE);
    await sembrar(async (db) => {
      await setDoc(doc(db, 'rescates', 'animalR'), {
        rescatistaId: RESCATISTA,
        creadoPor: 'rescatista',
      });
    });
    const solRef = doc(collection(dbAdoptante, 'solicitudes'));
    await sembrar(async (db) =>
      setDoc(doc(db, 'solicitudes', solRef.id), {
        adoptanteId: ADOPTANTE,
        rescatistaId: RESCATISTA,
        rescateId: 'animalR',
        estado: 'pendiente',
      }),
    );

    await assertFails(
      updateDoc(doc(dbAdoptante, 'solicitudes', solRef.id), { estado: 'aprobada' }),
    );
  });

  it(
    'no se puede mandar una solicitud "en nombre de" un rescatista/albergue '
    + 'que no es el dueño real del animal (spoofing de rescatistaId)',
    async () => {
      const dbAdoptante = como(ADOPTANTE);
      await sembrar(async (db) => {
        await setDoc(doc(db, 'rescates', 'animalR'), {
          rescatistaId: RESCATISTA,
          creadoPor: 'rescatista',
        });
      });

      await assertFails(
        setDoc(doc(collection(dbAdoptante, 'solicitudes')), {
          adoptanteId: ADOPTANTE,
          // OTRO no es el dueño real de animalR — intento de apuntar el
          // aviso/push a alguien sin relación con este animal.
          rescatistaId: OTRO,
          rescateId: 'animalR',
          estado: 'pendiente',
        }),
      );
    },
  );

  it(
    'nadie puede mandar un mensaje de chat marcado como si lo hubiera '
    + 'escrito el otro lado (emisor falsificado)',
    async () => {
      const dbRescatista = como(RESCATISTA);
      const dbAdoptante = como(ADOPTANTE);
      await sembrar(async (db) => {
        await setDoc(doc(db, 'rescates', 'animalR'), {
          rescatistaId: RESCATISTA,
          creadoPor: 'rescatista',
        });
        await setDoc(doc(db, 'chats', idChat('animalR', ADOPTANTE)), {
          rescateId: 'animalR',
          adoptanteId: ADOPTANTE,
          rescatistaId: RESCATISTA,
          creadoPor: 'rescatista',
        });
      });

      // El adoptante intenta escribir un mensaje marcado 'rescatista' —
      // como si lo hubiera escrito el rescatista, no él.
      await assertFails(
        addDoc(collection(dbAdoptante, 'chats', idChat('animalR', ADOPTANTE), 'mensajes'), {
          texto: 'mensaje falsificado',
          emisor: 'rescatista',
          creadoEn: serverTimestamp(),
          hora: '10:00',
          creadoEn: serverTimestamp(),
        }),
      );
      // Y al revés: el rescatista no puede firmar como 'adoptante'.
      await assertFails(
        addDoc(collection(dbRescatista, 'chats', idChat('animalR', ADOPTANTE), 'mensajes'), {
          texto: 'mensaje falsificado',
          emisor: 'adoptante',
          creadoEn: serverTimestamp(),
          hora: '10:00',
          creadoEn: serverTimestamp(),
        }),
      );
    },
  );
});
