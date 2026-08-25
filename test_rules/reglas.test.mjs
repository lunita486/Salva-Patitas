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
  deleteField,
} from 'firebase/firestore';

const aca = dirname(fileURLToPath(import.meta.url));

const ADOPTANTE = 'uid_adoptante';
const ALBERGUE = 'uid_albergue';
const ALIADO = 'uid_aliado';
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
      // Tiene que ser el MISMO puerto que emulators.firestore.port en
      // firebase.json (ver el comentario ahí) — este archivo no lee ese
      // valor solo, así que si uno cambia el otro tiene que seguirlo.
      port: 8097,
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
    await setDoc(doc(db, 'usuarios', ALIADO), { roles: ['aliado'] });
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

  // ── El agujero de las notificaciones falsas ────────────────────────────
  // rescatistaId no se validaba contra nada — cualquiera podía escribir el
  // uid de CUALQUIER persona del sistema ahí (no tenía que ser dueño de
  // ningún animal siquiera) y disparar onNuevaSolicitud, que manda un push
  // real usando nombre/animalNombre tal cual. Confirmado explotable contra
  // el emulador antes de este arreglo: OTRO (sin ninguna relación con el
  // rescate ni con ADOPTANTE) podía apuntarle una solicitud a quien
  // quisiera con texto inventado.
  it('rescatistaId tiene que ser el dueño REAL del rescateId indicado — no cualquier uid del sistema', async () => {
    await assertFails(
      addDoc(collection(como(OTRO), 'solicitudes'), {
        adoptanteId: OTRO,
        rescatistaId: ADOPTANTE, // ADOPTANTE no es dueño de 'animal1' — el dueño real es ALBERGUE
        rescateId: 'animal1',
        estado: 'pendiente',
        nombre: 'GANASTE UN IPHONE, clic aquí bit.ly/xyz',
        animalNombre: 'texto inventado',
      }),
    );
  });

  it('rescateId tiene que apuntar a un animal que existe de verdad', async () => {
    await assertFails(
      addDoc(collection(como(OTRO), 'solicitudes'), {
        adoptanteId: OTRO,
        rescatistaId: ALBERGUE,
        rescateId: 'este_id_no_existe',
        estado: 'pendiente',
      }),
    );
  });

  it('rescateId no puede quedar vacío', async () => {
    await assertFails(
      addDoc(collection(como(OTRO), 'solicitudes'), {
        adoptanteId: OTRO,
        rescatistaId: ALBERGUE,
        rescateId: '',
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

describe('solicitudes — las copias del animal (fotoUrl/animalNombre) son intocables desde el cliente', () => {
  // Estas copias las mantiene al día el trigger onRescateActualizado
  // (functions/propagar_copias.js), que corre con permisos de admin y no
  // pasa por estas reglas. Ningún cliente necesita escribirlas, así que
  // nadie puede — ni el dueño del animal, ni el adoptante.
  //
  // Hubo una rama de la regla que sí se lo permitía al dueño, agregada
  // cuando la sincronización se intentaba desde la app. Al mudarla al
  // servidor esa rama quedó sin ningún llamador, y una regla que permite
  // algo que nadie usa es superficie de ataque regalada: se quitó. Estos
  // tests son los que avisan si alguien la vuelve a abrir sin querer.
  it('ni el rescatista dueño del animal puede escribir fotoUrl/animalNombre', async () => {
    await sembrarSolicitudPendiente();
    await assertFails(
      updateDoc(doc(como(ALBERGUE), 'solicitudes', 'sol1'), {
        fotoUrl: 'https://ejemplo.com/nueva.jpg',
        animalNombre: 'Otro nombre',
      }),
    );
  });

  it('tampoco el adoptante', async () => {
    await sembrarSolicitudPendiente();
    await assertFails(
      updateDoc(doc(como(ADOPTANTE), 'solicitudes', 'sol1'), {
        animalNombre: 'Otro nombre',
      }),
    );
  });

  it('ni un tercero ajeno', async () => {
    await sembrarSolicitudPendiente();
    await assertFails(
      updateDoc(doc(como(OTRO), 'solicitudes', 'sol1'), {
        fotoUrl: 'https://ejemplo.com/nueva.jpg',
      }),
    );
  });

  // Lo que el dueño SÍ tiene que poder seguir haciendo, para que los tests
  // de arriba no pasen por el motivo equivocado (una regla rota del todo).
  it('pero el dueño sigue pudiendo aprobar/rechazar, que es lo suyo', async () => {
    await sembrarSolicitudPendiente();
    await assertSucceeds(
      updateDoc(doc(como(ALBERGUE), 'solicitudes', 'sol1'), { estado: 'aprobada' }),
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
      await setDoc(doc(db, 'chats', 'chat_a'), {
        adoptanteId: ADOPTANTE, rescatistaId: ALBERGUE, rescateId: 'animal1',
        creadoPor: 'albergue', rescatista: 'Nombre viejo',
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

  // ── El agujero que reabría el ataque de notificaciones falsas ─────────
  // update() solo pedía ser el dueño ACTUAL, sin restringir a qué podía
  // cambiarlo — el propio dueño podía "regalarle" su animal al uid de
  // cualquier otra persona, y con eso volver a disparar el mismo push
  // falso que el anclaje de solicitudes.create supuestamente ya bloqueaba
  // (ese anclaje confía en QUE ESTE CAMPO no se pueda falsificar después
  // de creado el rescate).
  it('el dueño de un animal NO puede reasignarlo a otra cuenta al editarlo', async () => {
    await assertFails(
      updateDoc(doc(como(ALBERGUE), 'rescates', 'animal1'), { rescatistaId: OTRO }),
    );
  });

  it('tampoco puede cambiarle el rol con el que se publicó (creadoPor) al editarlo', async () => {
    await assertFails(
      updateDoc(doc(como(ALBERGUE), 'rescates', 'animal1'), { creadoPor: 'rescatista' }),
    );
  });

  it('el dueño real SÍ puede seguir editando el resto de los campos normalmente', async () => {
    await assertSucceeds(
      updateDoc(doc(como(ALBERGUE), 'rescates', 'animal1'), { estadoAdopcion: 'Adoptado' }),
    );
  });
});

describe('servicios — catálogo de negocios aliados', () => {
  beforeEach(async () => {
    await sembrar(async (db) => {
      await setDoc(doc(db, 'servicios', 'svc1'), {
        aliadoId: ALIADO,
        nombre: 'Baño y corte',
        precio: 50000,
        activo: true,
      });
    });
  });

  it('el catálogo es de lectura pública, incluso sin sesión', async () => {
    await assertSucceeds(getDoc(doc(sinSesion(), 'servicios', 'svc1')));
  });

  it('no se puede publicar un servicio a nombre de otro aliado, ni sin tener el rol', async () => {
    await assertFails(
      addDoc(collection(como(OTRO), 'servicios'), { aliadoId: ALIADO, nombre: 'Robado' }),
    );
    await assertFails(
      addDoc(collection(como(ADOPTANTE), 'servicios'), { aliadoId: ADOPTANTE, nombre: 'Falso' }),
    );
  });

  it('el aliado dueño puede editar sus propios campos (ej. activar/desactivar, cambiar precio)', async () => {
    await assertSucceeds(
      updateDoc(doc(como(ALIADO), 'servicios', 'svc1'), { activo: false, precio: 60000 }),
    );
  });

  // ── Mismo agujero que rescates.update ──────────────────────────────────
  // update() solo pedía ser el dueño ACTUAL, sin restringir a qué podía
  // cambiarlo — el propio aliado podía "regalarle" su servicio (público)
  // al uid de cualquier otro negocio sin su consentimiento.
  it('el dueño de un servicio NO puede reasignarlo a otra cuenta al editarlo', async () => {
    await assertFails(
      updateDoc(doc(como(ALIADO), 'servicios', 'svc1'), { aliadoId: OTRO }),
    );
  });

  it('nadie más puede editar ni borrar el servicio de otro', async () => {
    await assertFails(updateDoc(doc(como(OTRO), 'servicios', 'svc1'), { activo: false }));
    await assertFails(deleteDoc(doc(como(OTRO), 'servicios', 'svc1')));
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

  // Mismo agujero que rescates.update/servicios.update: sin este candado,
  // el propio albergue podía "traspasarle" una fila de contacto (privada)
  // al uid de cualquier otro albergue con un simple update().
  it('el albergue dueño NO puede reasignar una fila del roster a otro albergue', async () => {
    await assertFails(
      updateDoc(doc(como(ALBERGUE), 'hogaresDePaso', 'hp1'), { albergueId: OTRO }),
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

  // ── El agujero de los mensajes falsificados ────────────────────────────
  // emisor lo escribe el propio teléfono al mandar el mensaje, y antes la
  // regla no revisaba que coincidiera con quién es de verdad quien escribe
  // — cualquiera de los dos lados podía mandar SU mensaje marcado con el
  // emisor DEL OTRO, y ese mensaje se veía en la pantalla de la víctima
  // como si ELLA lo hubiera escrito (chat_screen.dart calcula la burbuja
  // comparando el rol propio contra este campo).
  it('no se puede mandar un mensaje marcado con el emisor del OTRO participante', async () => {
    await assertFails(
      addDoc(collection(como(ADOPTANTE), 'chats', 'chat1', 'mensajes'), {
        texto: 'yo nunca dije esto',
        emisor: 'rescatista',
      }),
    );
    await assertFails(
      addDoc(collection(como(ALBERGUE), 'chats', 'chat1', 'mensajes'), {
        texto: 'yo tampoco dije esto',
        emisor: 'adoptante',
      }),
    );
  });

  it('cada participante SÍ puede mandar un mensaje marcado con su propio lado (flujo real)', async () => {
    await assertSucceeds(
      addDoc(collection(como(ADOPTANTE), 'chats', 'chat1', 'mensajes'), {
        texto: 'hola, esto sí lo dije yo',
        emisor: 'adoptante',
      }),
    );
    await assertSucceeds(
      addDoc(collection(como(ALBERGUE), 'chats', 'chat1', 'mensajes'), {
        texto: 'y esto lo dije yo',
        emisor: 'rescatista',
      }),
    );
  });

  // Ni la app ni la regla ponían antes ningún tope al largo de un
  // mensaje — alguien podía mandar texto gigante saltándose el límite
  // del campo de la app (que solo frena a quien usa la app de verdad).
  it('un mensaje de más de 2000 caracteres se rechaza', async () => {
    await assertFails(
      addDoc(collection(como(ADOPTANTE), 'chats', 'chat1', 'mensajes'), {
        texto: 'x'.repeat(2001),
        emisor: 'adoptante',
      }),
    );
  });

  it('un mensaje de exactamente 2000 caracteres SÍ se acepta', async () => {
    await assertSucceeds(
      addDoc(collection(como(ADOPTANTE), 'chats', 'chat1', 'mensajes'), {
        texto: 'x'.repeat(2000),
        emisor: 'adoptante',
      }),
    );
  });

  // Caso real, probado en teléfono real 2026-08-03: una cuenta que además
  // tiene su propio negocio aliado registrado se consulta A SÍ MISMA
  // (tocó "Contactar" en el perfil público de su propio negocio) —
  // adoptanteId y rescatistaId de ESE chat terminan siendo el mismo uid.
  // Antes la regla chequeaba rescatistaId primero, así que ese uid
  // "ganaba" como rescatista y exigía emisor:'rescatista' — pero
  // chat_screen.dart siempre manda 'adoptante' para quien inició la
  // consulta (adoptanteId es, por diseño del esquema, "quien preguntó",
  // sin importar su rol real). Resultado: "No se pudo enviar el mensaje"
  // siempre, para cualquier cuenta que se consultara a sí misma.
  it('una cuenta que se consulta a sí misma (mismo uid en los dos lados) manda como adoptante', async () => {
    await sembrar(async (db) => {
      await setDoc(doc(db, 'chats', 'chatSelf'), {
        adoptanteId: ALIADO,
        rescatistaId: ALIADO,
        tipoSolicitud: 'consulta_aliado',
        creadoPor: 'rescatista',
      });
    });
    await assertSucceeds(
      addDoc(collection(como(ALIADO), 'chats', 'chatSelf', 'mensajes'), {
        texto: 'hola, me pregunto algo a mí mismo',
        emisor: 'adoptante',
      }),
    );
    await assertFails(
      addDoc(collection(como(ALIADO), 'chats', 'chatSelf', 'mensajes'), {
        texto: 'esto no debería colarse',
        emisor: 'rescatista',
      }),
    );
  });

  // ── El caso real de "no pudimos avisarle al adoptante" ─────────────────
  // La regla de mensajes.create hace `get(chats/$(chatId))` para saber si
  // quien escribe es adoptanteId o rescatistaId de ESE chat. Firestore
  // evalúa cada escritura de un batch/transacción contra el estado YA
  // COMMITEADO, no contra las otras escrituras del MISMO batch — así que
  // un chat que se crea en el mismo batch que su primer mensaje no existe
  // todavía para ese get(), y la regla entera se cae con un error de
  // evaluación (deniega TODO el batch). Ninguna prueba de este archivo
  // probó nunca ese caso — todas las de arriba pre-siembran el chat con
  // `sembrar()` antes de escribir el mensaje. Hallazgo real de Eliza: "Sin
  // nombre" (perro), marcado Fallecido, con una solicitud pendiente nunca
  // charlada — "el estado se guardó, pero no pudimos avisarle al
  // adoptante".
  it(
    'crear el chat Y su primer mensaje en el MISMO batch se RECHAZA — es ' +
      'justo el patrón que ChatsRepository.avisarSobreAnimal usaba antes ' +
      'para un chat que nunca existió, y por esto se cambió a dos pasos ' +
      'separados (ver el test de abajo). Si este test alguna vez empieza ' +
      'a pasar, revisá si cambiaron las reglas de mensajes.create antes ' +
      'de volver a juntar esto en un batch',
    async () => {
      const { writeBatch } = await import('firebase/firestore');
      const db = como(ALBERGUE);
      const batch = writeBatch(db);
      const chatRef = doc(db, 'chats', 'chatNuevo');
      const mensajeRef = doc(collection(db, 'chats', 'chatNuevo', 'mensajes'));
      batch.set(chatRef, {
        adoptanteId: OTRO,
        rescatistaId: ALBERGUE,
        rescateId: 'animal1',
        creadoPor: 'albergue',
      });
      batch.set(mensajeRef, {
        texto: 'Lamentamos informarte que Firulais falleció.',
        emisor: 'rescatista',
      });
      await assertFails(batch.commit());
    },
  );

  // El arreglo real: DOS escrituras separadas (asegurarChatAnimal primero,
  // registrarMensaje después, mismo patrón que chat_screen.dart ya usaba)
  // en vez del batch único de arriba. Para cuando se manda el mensaje, el
  // chat ya es un documento COMMITEADO de verdad, así que el get() de la
  // regla lo encuentra sin problema.
  it(
    'crear el chat como una escritura propia, y DESPUÉS su primer mensaje ' +
      'como otra — el arreglo real de avisarSobreAnimal — sí funciona',
    async () => {
      const db = como(ALBERGUE);
      await assertSucceeds(
        setDoc(
          doc(db, 'chats', 'chatNuevo2'),
          {
            adoptanteId: OTRO,
            rescatistaId: ALBERGUE,
            rescateId: 'animal1',
            creadoPor: 'albergue',
          },
          { merge: true },
        ),
      );
      await assertSucceeds(
        addDoc(collection(db, 'chats', 'chatNuevo2', 'mensajes'), {
          texto: 'Lamentamos informarte que Firulais falleció.',
          emisor: 'rescatista',
        }),
      );
    },
  );
});

// ── chats.create — P0-1 de la auditoría del 2026-08-25 ─────────────────
//
// Esta era la regla MENOS probada de todas: la suite tenía casos de
// `mensajes` (emisor falsificado, largo del texto) pero NINGUN caso
// negativo de `chats.create`. Por eso el agujero sobrevivió — el caso
// positivo lo ejercita la app todos los días, el negativo no lo prueba
// nadie hasta que alguien lo usa.
describe('chats — quién puede ABRIR una conversación (y contra quién)', () => {
  // El ataque real, verificado explotable antes del arreglo: omitir
  // `creadoPor` salteaba el anclaje entero, y onNuevoMensaje mandaba una
  // push con título y cuerpo elegidos por quien atacaba.
  it('un desconocido NO puede abrir un chat contra alguien sin relación, omitiendo creadoPor', async () => {
    const db = como(OTRO);
    await assertFails(setDoc(doc(db, 'chats', 'spam1'), {
      rescatistaId: OTRO,
      adoptanteId: ALBERGUE,
      animalNombre: 'URGENTE: tu cuenta será suspendida',
      ultimoMensaje: 'Entrá acá para no perderla',
    }));
  });

  it('tampoco al revés (poniéndose de adoptante y a la víctima de rescatista)', async () => {
    const db = como(OTRO);
    await assertFails(setDoc(doc(db, 'chats', 'spam2'), {
      rescatistaId: ALBERGUE,
      adoptanteId: OTRO,
      animalNombre: 'URGENTE',
    }));
  });

  // La rama legada exige tieneRol sobre el DESTINATARIO. Sin el candado de
  // `adoptanteId == uid()`, alcanzaba con auto-asignarse el rol (son
  // auto-asignables) y ponerse de rescatista para elegir a cualquiera.
  it('no alcanza con auto-asignarse el rol y ponerse del lado del rescatista', async () => {
    await sembrar(async (db) => {
      await setDoc(doc(db, 'usuarios', OTRO), { roles: ['adoptante', 'rescatista'] });
    });
    const db = como(OTRO);
    await assertFails(setDoc(doc(db, 'chats', 'spam3'), {
      rescatistaId: OTRO,
      adoptanteId: ADOPTANTE,
      rescateId: '',
      creadoPor: 'rescatista',
      animalNombre: 'lo que yo quiera',
    }));
  });

  // Una consulta a un negocio se ancla en que el DESTINATARIO sea un
  // aliado de verdad. Antes se miraba el rol de quien pregunta, que es el
  // lado que controla quien ataca.
  it('no se puede disfrazar de consulta_aliado para escribirle a quien no es aliado', async () => {
    await sembrar(async (db) => {
      await setDoc(doc(db, 'usuarios', OTRO), { roles: ['adoptante', 'rescatista'] });
    });
    const db = como(OTRO);
    await assertFails(setDoc(doc(db, 'chats', 'spam4'), {
      rescatistaId: ADOPTANTE,       // no es aliado
      adoptanteId: OTRO,
      tipoSolicitud: 'consulta_aliado',
      creadoPor: 'rescatista',
    }));
  });

  it('un chat de animal con rescateId inventado se rechaza', async () => {
    const db = como(ADOPTANTE);
    await assertFails(setDoc(doc(db, 'chats', 'spam5'), {
      rescatistaId: ALBERGUE,
      adoptanteId: ADOPTANTE,
      rescateId: 'no_existe',
      creadoPor: 'albergue',
    }));
  });

  it('un chat de animal apuntando a un animal real pero con el dueño cambiado se rechaza', async () => {
    const db = como(OTRO);
    await assertFails(setDoc(doc(db, 'chats', 'spam6'), {
      rescatistaId: OTRO,            // el dueño real es ALBERGUE
      adoptanteId: ADOPTANTE,
      rescateId: 'animal1',
      creadoPor: 'albergue',
    }));
  });

  // ── Los tres caminos LEGÍTIMOS: si alguno de estos se rompe, se rompió
  // la app de verdad, no un ataque. ──
  it('(A) un adoptante abre un chat sobre un animal real del albergue', async () => {
    const db = como(ADOPTANTE);
    await assertSucceeds(setDoc(doc(db, 'chats', 'animal1_' + ADOPTANTE), {
      rescatistaId: ALBERGUE,
      adoptanteId: ADOPTANTE,
      rescateId: 'animal1',
      creadoPor: 'albergue',
      animalNombre: 'Firulais',
    }));
  });

  it('(A) y el albergue dueño también puede abrirlo desde su lado', async () => {
    const db = como(ALBERGUE);
    await assertSucceeds(setDoc(doc(db, 'chats', 'animal1_' + ADOPTANTE), {
      rescatistaId: ALBERGUE,
      adoptanteId: ADOPTANTE,
      rescateId: 'animal1',
      creadoPor: 'albergue',
    }));
  });

  // Este es el caso que se rompía si se exigía `creadoPor` a secas:
  // asegurarChatNegocio NO lo escribe cuando quien pregunta es adoptante.
  it('(B) un adoptante contacta a un negocio aliado SIN creadoPor', async () => {
    const db = como(ADOPTANTE);
    await assertSucceeds(setDoc(doc(db, 'chats', ALIADO + '_' + ADOPTANTE + '_negocio_general'), {
      rescatistaId: ALIADO,
      adoptanteId: ADOPTANTE,
      tipoSolicitud: 'consulta_aliado',
    }));
  });

  it('(B) un albergue contacta al mismo negocio, y ahí sí va creadoPor', async () => {
    const db = como(ALBERGUE);
    await assertSucceeds(setDoc(doc(db, 'chats', ALIADO + '_' + ALBERGUE + '_negocio_albergue'), {
      rescatistaId: ALIADO,
      adoptanteId: ALBERGUE,
      tipoSolicitud: 'consulta_aliado',
      creadoPor: 'albergue',
    }));
  });

  // Caso real probado en teléfono el 2026-08-03: una cuenta que publicó un
  // negocio y se escribe a sí misma tiene el mismo uid de los dos lados.
  it('(B) un aliado que se consulta a sí mismo sigue pudiendo', async () => {
    const db = como(ALIADO);
    await assertSucceeds(setDoc(doc(db, 'chats', ALIADO + '_' + ALIADO + '_negocio_general'), {
      rescatistaId: ALIADO,
      adoptanteId: ALIADO,
      tipoSolicitud: 'consulta_aliado',
    }));
  });

  // (C) es el gemelo de (A) para cuando no hay animal contra el cual
  // anclar: el aviso automatico de "tu solicitud fue rechazada" sobre una
  // solicitud vieja sin rescateId. Lo crea el RESCATISTA, no el adoptante,
  // asi que la condicion de (D) no le sirve.
  it('(C) el rescatista puede crear el chat del aviso, anclado a la solicitud', async () => {
    await sembrarSolicitudPendiente('sol_vieja', { rescateId: '' });
    const db = como(ALBERGUE);
    await assertSucceeds(setDoc(doc(db, 'chats', 'aviso1'), {
      rescatistaId: ALBERGUE,
      adoptanteId: ADOPTANTE,
      solicitudId: 'sol_vieja',
      creadoPor: 'albergue',
      animalNombre: 'Firulais',
    }));
  });

  it('(C) pero la solicitud tiene que unir a ESAS dos personas', async () => {
    await sembrarSolicitudPendiente('sol_vieja', { rescateId: '' });
    const db = como(ALBERGUE);
    await assertFails(setDoc(doc(db, 'chats', 'aviso2'), {
      rescatistaId: ALBERGUE,
      adoptanteId: OTRO,            // no es el de la solicitud
      solicitudId: 'sol_vieja',
      creadoPor: 'albergue',
    }));
  });

  it('(C) y tiene que existir de verdad', async () => {
    const db = como(ALBERGUE);
    await assertFails(setDoc(doc(db, 'chats', 'aviso3'), {
      rescatistaId: ALBERGUE,
      adoptanteId: ADOPTANTE,
      solicitudId: 'no_existe',
      creadoPor: 'albergue',
    }));
  });

  // Ya no queda NINGUNA rama sin ancla. Un chat sin animal y sin solicitud
  // se rechaza, lo cree quien lo cree: las dos escrituras (la legitima de
  // antes y la de un ataque) eran identicas, asi que no habia forma de
  // distinguirlas y la unica salida era cerrar la puerta.
  it('un chat sin animal Y sin solicitud se rechaza, aunque lo cree el adoptante', async () => {
    const db = como(ADOPTANTE);
    await assertFails(setDoc(doc(db, 'chats', 'firulais_albergue'), {
      rescatistaId: ALBERGUE,
      adoptanteId: ADOPTANTE,
      rescateId: '',
      creadoPor: 'albergue',
      animalNombre: 'Firulais',
    }));
  });

  it('ni con el rol auto-asignado y poniendose del lado del rescatista', async () => {
    await sembrar(async (db) => {
      await setDoc(doc(db, 'usuarios', OTRO), { roles: ['adoptante', 'rescatista'] });
    });
    const db = como(OTRO);
    await assertFails(setDoc(doc(db, 'chats', 'spam7'), {
      rescatistaId: OTRO,
      adoptanteId: ALBERGUE,
      rescateId: '',
      creadoPor: 'rescatista',
      animalNombre: 'inventado',
    }));
  });

  // Y el camino real que antes caia ahi: una solicitud vieja sin rescateId,
  // abierta desde Mis Solicitudes. Ahora viaja con su solicitudId y entra
  // por (C).
  it('el chat de una solicitud vieja (sin rescateId) funciona con su solicitudId', async () => {
    await sembrarSolicitudPendiente('sol_vieja', { rescateId: '' });
    const db = como(ADOPTANTE);
    await assertSucceeds(setDoc(doc(db, 'chats', 'firulais_albergue'), {
      rescatistaId: ALBERGUE,
      adoptanteId: ADOPTANTE,
      rescateId: '',
      solicitudId: 'sol_vieja',
      creadoPor: 'albergue',
      animalNombre: 'Firulais',
    }));
  });
});

// ── usuarios: get vs list — P0-2 de la auditoría del 2026-08-25 ────────
describe('usuarios — leer UNO sí, listar TODOS no', () => {
  it('cualquier cuenta NO puede listar la colección entera', async () => {
    const db = como(OTRO);
    await assertFails(getDocs(collection(db, 'usuarios')));
  });

  // El filtro por rol solo abre la puerta para 'aliado'. Pedir la lista de
  // adoptantes con la misma forma de consulta se rechaza igual.
  it('tampoco listando por OTRO rol', async () => {
    const db = como(OTRO);
    await assertFails(getDocs(query(collection(db, 'usuarios'), where('roles', 'array-contains', 'adoptante'))));
  });

  it('ni filtrando por un campo cualquiera', async () => {
    const db = como(OTRO);
    await assertFails(getDocs(query(collection(db, 'usuarios'), where('ciudad', '==', 'Santiago'))));
  });

  // Lo que SÍ tiene que seguir andando: el directorio de negocios.
  it('el directorio de aliados (UsuariosRepository.aliados) sigue funcionando', async () => {
    await sembrar(async (db) => {
      await setDoc(doc(db, 'usuarios', ALIADO), {
        roles: ['aliado'], aliadoNombre: 'Veterinaria 30', aliadoTipo: 'veterinaria',
      });
    });
    const db = como(ADOPTANTE);
    const snap = await assertSucceeds(
      getDocs(query(collection(db, 'usuarios'), where('roles', 'array-contains', 'aliado'))),
    );
    if (snap.size !== 1) throw new Error(`esperaba 1 aliado, vinieron ${snap.size}`);
  });

  // Y leer el perfil de UNA contraparte, que es lo que necesitan el chat y
  // las pantallas públicas de albergue y aliado.
  it('leer el perfil puntual de otra persona sigue permitido', async () => {
    const db = como(ADOPTANTE);
    await assertSucceeds(getDoc(doc(db, 'usuarios', ALBERGUE)));
  });

  // P1: cerrarSesion() borra el token antes del signOut. Si la regla no lo
  // permitiera, ese borrado fallaria en silencio (es best-effort) y el
  // token quedaria pegado al perfil igual que antes.
  it('cada quien puede borrar su propio fcmToken', async () => {
    await sembrar(async (db) => {
      await setDoc(doc(db, 'usuarios', ADOPTANTE), {
        roles: ['adoptante'], nombre: 'Ana', fcmToken: 'token-telefono',
      });
    });
    const db = como(ADOPTANTE);
    await assertSucceeds(updateDoc(doc(db, 'usuarios', ADOPTANTE), {
      fcmToken: deleteField(),
    }));
  });

  it('pero no el de otra persona', async () => {
    await sembrar(async (db) => {
      await setDoc(doc(db, 'usuarios', ALBERGUE), {
        roles: ['albergue'], fcmToken: 'token-de-eliza',
      });
    });
    const db = como(OTRO);
    await assertFails(updateDoc(doc(db, 'usuarios', ALBERGUE), {
      fcmToken: deleteField(),
    }));
  });

  it('sin sesión no se lee nada', async () => {
    const db = sinSesion();
    await assertFails(getDoc(doc(db, 'usuarios', ALBERGUE)));
  });
});
