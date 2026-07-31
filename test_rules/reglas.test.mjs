// Pruebas de firestore.rules contra el emulador de Firestore.
//
// Por qué existe este archivo: `firestore.rules` es la ÚNICA barrera real de
// seguridad (ver CLAUDE.md / ARCHITECTURE.md) — el filtrado en Dart solo
// evita traer datos de más. Pero hasta ahora las reglas no tenían ninguna
// prueba: se validaba que COMPILARAN (`firebase deploy` lo hace solo), nunca
// que hicieran lo que dicen hacer. Así se coló a producción el agujero de
// `solicitudes/create`: la rama de `update` prohibía cuidadosamente que un
// adoptante se auto-aprobara una solicitud, pero `create` no miraba `estado`,
// así que bastaba con saltarse el update y crear el documento ya aprobado.
//
// Cada `it()` de acá es una invariante que se rompió, o se pudo haber roto,
// escribiendo Dart perfectamente correcto. Al agregar una regla nueva,
// agregá también su caso negativo (lo que NO se debe poder hacer) — el caso
// positivo casi siempre lo cubre la app al usarse, el negativo no lo prueba
// nadie hasta que alguien lo explota.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { before, after, beforeEach, describe, it } from 'node:test';
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
  deleteDoc,
  collection,
  addDoc,
  query,
  where,
  limit,
} from 'firebase/firestore';

const aca = dirname(fileURLToPath(import.meta.url));

const ADOPTANTE = 'uid_adoptante';
const ALBERGUE = 'uid_albergue';
const OTRO = 'uid_intruso';

let testEnv;

/** Firestore como un usuario logueado. */
const como = (uid) => testEnv.authenticatedContext(uid).firestore();
/** Firestore sin sesión. */
const sinSesion = () => testEnv.unauthenticatedContext().firestore();

/** Escribe datos de partida saltándose las reglas (no es lo que se prueba). */
async function sembrar(fn) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => fn(ctx.firestore()));
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'patitas-reglas-test',
    firestore: {
      rules: readFileSync(join(aca, '..', 'firestore.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  // Perfiles base: varias reglas hacen get() sobre usuarios/{uid} para
  // validar roles (hasRole/tieneRol), así que sin esto fallarían por una
  // razón distinta a la que se está probando.
  await sembrar(async (db) => {
    await setDoc(doc(db, 'usuarios', ADOPTANTE), { roles: ['adoptante'] });
    await setDoc(doc(db, 'usuarios', ALBERGUE), { roles: ['albergue'] });
    await setDoc(doc(db, 'usuarios', OTRO), { roles: ['adoptante'] });
    await setDoc(doc(db, 'rescates', 'animal1'), {
      rescatistaId: ALBERGUE,
      creadoPor: 'albergue',
      nombre: 'Firulais',
    });
  });
});

/** Una solicitud pendiente ya existente, del ADOPTANTE hacia el ALBERGUE. */
async function sembrarSolicitudPendiente(id = 'sol1', extra = {}) {
  await sembrar(async (db) => {
    await setDoc(doc(db, 'solicitudes', id), {
      adoptanteId: ADOPTANTE,
      rescatistaId: ALBERGUE,
      rescateId: 'animal1',
      creadoPor: 'albergue',
      estado: 'pendiente',
      animalNombre: 'Firulais',
      ...extra,
    });
  });
}

describe('solicitudes — creación', () => {
  it('un adoptante puede crear su propia solicitud pendiente (flujo real, no romper)', async () => {
    await assertSucceeds(
      addDoc(collection(como(ADOPTANTE), 'solicitudes'), {
        adoptanteId: ADOPTANTE,
        rescatistaId: ALBERGUE,
        rescateId: 'animal1',
        creadoPor: 'albergue',
        estado: 'pendiente',
        animalNombre: 'Firulais',
      }),
    );
  });

  // ── El agujero que llegó a producción ────────────────────────────────
  // Un intruso lee el feed (rescates es de lectura pública), saca el
  // rescateId de un animal ajeno y crea una solicitud que YA NACE aprobada.
  // tuvoSolicitudAprobada() consulta por rescateId + estado 'aprobada' sin
  // filtrar por dueño, así que bloqueoParaEliminar dejaba ese animal
  // imposible de borrar para siempre, para su dueño real.
  it('NADIE puede crear una solicitud que ya nazca aprobada, ni sobre el animal de otro', async () => {
    await assertFails(
      addDoc(collection(como(OTRO), 'solicitudes'), {
        adoptanteId: OTRO,
        rescatistaId: ALBERGUE,
        rescateId: 'animal1',
        creadoPor: 'albergue',
        estado: 'aprobada',
        animalNombre: 'Firulais',
      }),
    );
  });

  it('tampoco puede nacer rechazada ni con cualquier otro estado inventado', async () => {
    for (const estado of ['rechazada', 'cancelada', '']) {
      await assertFails(
        addDoc(collection(como(ADOPTANTE), 'solicitudes'), {
          adoptanteId: ADOPTANTE,
          rescatistaId: ALBERGUE,
          rescateId: 'animal1',
          estado,
        }),
      );
    }
  });

  it('no se puede crear una solicitud que ya venga con el acuerdo aceptado', async () => {
    await assertFails(
      addDoc(collection(como(ADOPTANTE), 'solicitudes'), {
        adoptanteId: ADOPTANTE,
        rescatistaId: ALBERGUE,
        rescateId: 'animal1',
        estado: 'pendiente',
        acuerdoAceptado: true,
      }),
    );
  });

  it('no se puede crear una solicitud a nombre de otra persona', async () => {
    await assertFails(
      addDoc(collection(como(OTRO), 'solicitudes'), {
        adoptanteId: ADOPTANTE,
        rescatistaId: ALBERGUE,
        rescateId: 'animal1',
        estado: 'pendiente',
      }),
    );
  });

  it('sin sesión no se puede crear ninguna solicitud', async () => {
    await assertFails(
      addDoc(collection(sinSesion(), 'solicitudes'), {
        adoptanteId: ADOPTANTE,
        rescatistaId: ALBERGUE,
        estado: 'pendiente',
      }),
    );
  });
});

describe('solicitudes — aprobar / rechazar', () => {
  it('el rescatista dueño puede aprobar una solicitud pendiente', async () => {
    await sembrarSolicitudPendiente();
    await assertSucceeds(
      updateDoc(doc(como(ALBERGUE), 'solicitudes', 'sol1'), { estado: 'aprobada' }),
    );
  });

  it('el adoptante NO puede auto-aprobarse su solicitud', async () => {
    await sembrarSolicitudPendiente();
    await assertFails(
      updateDoc(doc(como(ADOPTANTE), 'solicitudes', 'sol1'), { estado: 'aprobada' }),
    );
  });

  it('un tercero ajeno no puede tocar el estado de una solicitud', async () => {
    await sembrarSolicitudPendiente();
    await assertFails(
      updateDoc(doc(como(OTRO), 'solicitudes', 'sol1'), { estado: 'aprobada' }),
    );
  });

  it('al aprobar no se pueden cambiar de contrabando otros campos (ej. el dueño)', async () => {
    await sembrarSolicitudPendiente();
    await assertFails(
      updateDoc(doc(como(ALBERGUE), 'solicitudes', 'sol1'), {
        estado: 'aprobada',
        adoptanteId: OTRO,
      }),
    );
  });

  it('una solicitud ya resuelta no se puede volver a cambiar de estado', async () => {
    await sembrarSolicitudPendiente('sol2', { estado: 'rechazada' });
    await assertFails(
      updateDoc(doc(como(ALBERGUE), 'solicitudes', 'sol2'), { estado: 'aprobada' }),
    );
  });
});

describe('solicitudes — acuerdo de adopción', () => {
  it('el adoptante puede aceptar el acuerdo si su solicitud ya está aprobada', async () => {
    await sembrarSolicitudPendiente('sol3', { estado: 'aprobada' });
    await assertSucceeds(
      updateDoc(doc(como(ADOPTANTE), 'solicitudes', 'sol3'), { acuerdoAceptado: true }),
    );
  });

  it('no puede aceptar el acuerdo mientras la solicitud sigue pendiente', async () => {
    await sembrarSolicitudPendiente('sol4');
    await assertFails(
      updateDoc(doc(como(ADOPTANTE), 'solicitudes', 'sol4'), { acuerdoAceptado: true }),
    );
  });

  it('no puede desmarcar el acuerdo una vez aceptado', async () => {
    await sembrarSolicitudPendiente('sol5', { estado: 'aprobada', acuerdoAceptado: true });
    await assertFails(
      updateDoc(doc(como(ADOPTANTE), 'solicitudes', 'sol5'), { acuerdoAceptado: false }),
    );
  });
});

describe('solicitudes — lectura', () => {
  it('el adoptante y el rescatista involucrados pueden leerla', async () => {
    await sembrarSolicitudPendiente();
    await assertSucceeds(getDoc(doc(como(ADOPTANTE), 'solicitudes', 'sol1')));
    await assertSucceeds(getDoc(doc(como(ALBERGUE), 'solicitudes', 'sol1')));
  });

  // Contiene datos de vivienda/familia del adoptante.
  it('un tercero NO puede leer una solicitud ajena', async () => {
    await sembrarSolicitudPendiente();
    await assertFails(getDoc(doc(como(OTRO), 'solicitudes', 'sol1')));
  });
});

// Una consulta puede estar perfecta en Dart, compilar, pasar los tests de
// `test/data/` (fake_cloud_firestore NO aplica reglas) y aun así ser
// rechazada entera por el servidor. Firestore no filtra los resultados: si
// una consulta PODRÍA devolver algo que no tenés permiso de leer, la
// rechaza completa. Y como los repositorios envuelven estas lecturas en un
// try/catch que cae a la caché local, el rechazo no se ve por ningún lado —
// la app simplemente contesta "no hay nada" para siempre.
//
// Pasó de verdad, y esto es lo que lo destapó: tienePendientesPara() y
// tuvoSolicitudAprobada() (el bloqueo de borrado) consultaban por rescateId
// + estado, sin filtrar por dueño → permission-denied en cada llamada →
// caché → "no hay solicitudes" → dejaba borrar un animal que sí tenía una
// adopción aprobada.
//
// Por eso estas pruebas comparan la consulta REAL contra la ingenua: si
// alguien le saca el filtro por dueño a un repositorio, acá se cae.
describe('formas de consulta que hacen los repositorios', () => {
  beforeEach(async () => {
    await sembrar(async (db) => {
      await setDoc(doc(db, 'solicitudes', 'sol_a'), {
        adoptanteId: ADOPTANTE, rescatistaId: ALBERGUE, rescateId: 'animal1',
        estado: 'aprobada',
      });
    });
  });

  const solicitudes = (uid) => collection(como(uid), 'solicitudes');

  it('SolicitudesRepository._hayAlguna: filtrada por dueño, el servidor la acepta', async () => {
    for (const estado of ['pendiente', 'aprobada']) {
      await assertSucceeds(
        getDocs(query(
          solicitudes(ALBERGUE),
          where('rescatistaId', '==', ALBERGUE),
          where('rescateId', '==', 'animal1'),
          where('estado', '==', estado),
          limit(1),
        )),
      );
    }
  });

  it('sin el filtro por dueño, esa misma consulta es rechazada (el bug)', async () => {
    await assertFails(
      getDocs(query(
        solicitudes(ALBERGUE),
        where('rescateId', '==', 'animal1'),
        where('estado', '==', 'aprobada'),
        limit(1),
      )),
    );
  });

  it('tampoco sirve filtrar por el dueño equivocado', async () => {
    await assertFails(
      getDocs(query(
        solicitudes(ALBERGUE),
        where('rescatistaId', '==', OTRO),
        where('rescateId', '==', 'animal1'),
        where('estado', '==', 'aprobada'),
        limit(1),
      )),
    );
  });

  it('SolicitudesRepository.misSolicitudes: el adoptante consulta las suyas', async () => {
    await assertSucceeds(
      getDocs(query(solicitudes(ADOPTANTE), where('adoptanteId', '==', ADOPTANTE))),
    );
  });

  it('SolicitudesRepository.paraOwner: el rescatista consulta las que le llegan', async () => {
    await assertSucceeds(
      getDocs(query(
        solicitudes(ALBERGUE),
        where('rescatistaId', '==', ALBERGUE),
        where('creadoPor', '==', 'albergue'),
      )),
    );
  });
});

describe('rescates', () => {
  it('el feed es de lectura pública, incluso sin sesión (decisión consciente)', async () => {
    await assertSucceeds(getDoc(doc(sinSesion(), 'rescates', 'animal1')));
  });

  it('no se puede publicar un animal a nombre de otra persona', async () => {
    await assertFails(
      addDoc(collection(como(OTRO), 'rescates'), {
        rescatistaId: ALBERGUE,
        creadoPor: 'albergue',
        nombre: 'Robado',
      }),
    );
  });

  it('no se puede publicar como albergue sin tener ese rol en la cuenta', async () => {
    await assertFails(
      addDoc(collection(como(ADOPTANTE), 'rescates'), {
        rescatistaId: ADOPTANTE,
        creadoPor: 'albergue',
        nombre: 'Falso',
      }),
    );
  });

  it('nadie puede editar ni borrar el animal de otro', async () => {
    await assertFails(
      updateDoc(doc(como(OTRO), 'rescates', 'animal1'), { estadoAdopcion: 'Adoptado' }),
    );
    await assertFails(deleteDoc(doc(como(OTRO), 'rescates', 'animal1')));
  });
});

describe('usuarios', () => {
  it('nadie puede escribir en el perfil de otra persona', async () => {
    await assertFails(
      updateDoc(doc(como(OTRO), 'usuarios', ADOPTANTE), { nombre: 'Hackeado' }),
    );
  });

  it('no se puede inventar un rol fuera de la lista permitida', async () => {
    await assertFails(
      setDoc(doc(como(ADOPTANTE), 'usuarios', ADOPTANTE), { roles: ['admin'] }),
    );
  });

  it('sí puede activarse un rol válido en la propia cuenta', async () => {
    await assertSucceeds(
      setDoc(doc(como(ADOPTANTE), 'usuarios', ADOPTANTE), {
        roles: ['adoptante', 'rescatista'],
      }),
    );
  });
});

describe('preferencias — perfil de adopción (vivienda, niños, mascotas)', () => {
  it('cada quien solo ve y edita el suyo', async () => {
    await sembrar(async (db) => {
      await setDoc(doc(db, 'preferencias', ADOPTANTE), { prefEspecie: 'Perro' });
    });
    await assertSucceeds(getDoc(doc(como(ADOPTANTE), 'preferencias', ADOPTANTE)));
    await assertFails(getDoc(doc(como(OTRO), 'preferencias', ADOPTANTE)));
    await assertFails(
      setDoc(doc(como(OTRO), 'preferencias', ADOPTANTE), { prefEspecie: 'Gato' }),
    );
  });
});

describe('favoritos', () => {
  beforeEach(async () => {
    await sembrar(async (db) => {
      await setDoc(doc(db, 'favoritos', 'fav1'), {
        adoptanteId: ADOPTANTE,
        rescateId: 'animal1',
        rescatistaId: ALBERGUE,
      });
    });
  });

  it('solo el adoptante dueño lee y borra sus favoritos', async () => {
    await assertSucceeds(getDoc(doc(como(ADOPTANTE), 'favoritos', 'fav1')));
    await assertFails(getDoc(doc(como(OTRO), 'favoritos', 'fav1')));
  });

  // La limpieza de favoritos huérfanos la hace el Cloud Function
  // onRescateEliminado con privilegios de admin, justamente para no tener
  // que darle este permiso al rescatista (ver el comentario en las reglas).
  it('el dueño del animal NO puede leer ni borrar los favoritos que le apuntan', async () => {
    await assertFails(getDoc(doc(como(ALBERGUE), 'favoritos', 'fav1')));
    await assertFails(deleteDoc(doc(como(ALBERGUE), 'favoritos', 'fav1')));
  });
});

describe('hogaresDePaso — roster privado del albergue', () => {
  beforeEach(async () => {
    await sembrar(async (db) => {
      await setDoc(doc(db, 'hogaresDePaso', 'hp1'), {
        albergueId: ALBERGUE,
        nombre: 'Vecina de confianza',
        telefono: '3001234567',
      });
    });
  });

  it('el albergue dueño lo lee y lo edita', async () => {
    await assertSucceeds(getDoc(doc(como(ALBERGUE), 'hogaresDePaso', 'hp1')));
    await assertSucceeds(
      updateDoc(doc(como(ALBERGUE), 'hogaresDePaso', 'hp1'), { vecesAyudo: 2 }),
    );
  });

  it('nadie más puede leerlo (son datos de contacto de terceros)', async () => {
    await assertFails(getDoc(doc(como(OTRO), 'hogaresDePaso', 'hp1')));
    await assertFails(getDoc(doc(como(ADOPTANTE), 'hogaresDePaso', 'hp1')));
  });

  it('no se puede meter gente en el roster de otro albergue', async () => {
    await assertFails(
      addDoc(collection(como(OTRO), 'hogaresDePaso'), {
        albergueId: ALBERGUE,
        nombre: 'Colado',
      }),
    );
  });

  // ADOPTANTE tiene roles: ['adoptante'] (sembrado al principio del
  // archivo) — sin hasRole('albergue') acá, esto pasaba: quedaba acotado
  // a su propio uid (nunca exponía datos de otra cuenta), pero cualquier
  // cuenta sin rol de albergue podía igual crear su propio roster.
  it('una cuenta sin rol de albergue no puede crear su propio roster', async () => {
    await assertFails(
      addDoc(collection(como(ADOPTANTE), 'hogaresDePaso'), {
        albergueId: ADOPTANTE,
        nombre: 'No debería poder',
      }),
    );
  });
});

describe('chats', () => {
  beforeEach(async () => {
    await sembrar(async (db) => {
      await setDoc(doc(db, 'chats', 'chat1'), {
        adoptanteId: ADOPTANTE,
        rescatistaId: ALBERGUE,
        rescateId: 'animal1',
        creadoPor: 'albergue',
      });
      await setDoc(doc(db, 'chats', 'chat1', 'mensajes', 'm1'), {
        texto: 'Hola',
        emisor: ADOPTANTE,
      });
    });
  });

  it('las dos partes leen el chat y sus mensajes', async () => {
    await assertSucceeds(getDoc(doc(como(ADOPTANTE), 'chats', 'chat1')));
    await assertSucceeds(getDoc(doc(como(ALBERGUE), 'chats', 'chat1', 'mensajes', 'm1')));
  });

  it('un tercero no puede leer la conversación ajena', async () => {
    await assertFails(getDoc(doc(como(OTRO), 'chats', 'chat1')));
    await assertFails(getDoc(doc(como(OTRO), 'chats', 'chat1', 'mensajes', 'm1')));
  });

  it('un tercero no puede infiltrar un mensaje en un chat ajeno', async () => {
    await assertFails(
      addDoc(collection(como(OTRO), 'chats', 'chat1', 'mensajes'), {
        texto: 'spam',
        emisor: OTRO,
      }),
    );
  });

  it('no se pueden reescribir los dueños de un chat ya creado', async () => {
    await assertFails(
      updateDoc(doc(como(ADOPTANTE), 'chats', 'chat1'), { rescatistaId: OTRO }),
    );
  });
});
