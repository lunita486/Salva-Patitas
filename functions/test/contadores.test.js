const { test } = require('node:test');
const assert = require('node:assert');
const { contarDe, manejarEscritura } = require('../contadores');

// Acá se prueba lo que el trigger ESCRIBE, no solo cuándo se despierta.
//
// El Firestore falso de abajo aplica los `where` de verdad sobre una lista
// de animalitos. Eso importa: si la consulta se olvidara de filtrar por
// `creadoPor`, el contador del rescatista sumaría también los animalitos
// que esa misma cuenta publicó como albergue, que es exactamente la clase
// de bug de roles cruzados que ya costó tres hallazgos en esta app. Con un
// mock que solo devolviera un número fijo, ese error pasaría igual.

/** Un Firestore de mentira con lo justo: where (==, in), count y update. */
function firestoreFalso(animalitos, usuarios = ['rita', 'carmen', 'refugio']) {
  const escrituras = [];

  const cumple = (a, [campo, op, valor]) =>
    op === 'in' ? valor.includes(a[campo]) : a[campo] === valor;

  const consulta = (filtros) => ({
    where: (campo, op, valor) => consulta([...filtros, [campo, op, valor]]),
    count: () => ({
      get: async () => ({
        data: () => ({
          count: animalitos.filter((a) => filtros.every((f) => cumple(a, f))).length,
        }),
      }),
    }),
  });

  return {
    escrituras,
    collection: (nombre) => ({
      where: (campo, op, valor) => {
        assert.strictEqual(nombre, 'rescates');
        return consulta([]).where(campo, op, valor);
      },
      doc: (uid) => ({
        update: async (cambios) => {
          assert.strictEqual(nombre, 'usuarios');
          if (!usuarios.includes(uid)) {
            const e = new Error('NOT_FOUND');
            e.code = 5;
            throw e;
          }
          escrituras.push({ uid, cambios });
        },
      }),
    }),
  };
}

const delRescatista = (extra = {}) => ({
  rescatistaId: 'rita',
  creadoPor: 'rescatista',
  estadoAdopcion: 'Rescatado',
  ...extra,
});
const delAlbergue = (extra = {}) => ({
  rescatistaId: 'refugio',
  creadoPor: 'albergue',
  estadoAdopcion: 'Rescatado',
  ...extra,
});

// ── Rescatista: las definiciones de siempre ───────────────────────────
test('rescatista: el total incluye TODOS los estados', async () => {
  const db = firestoreFalso([
    delRescatista(),
    delRescatista({ estadoAdopcion: 'Adoptado' }),
    delRescatista({ estadoAdopcion: 'Fallecido' }),
    delRescatista({ estadoAdopcion: 'Hogar de paso' }),
  ]);
  assert.deepStrictEqual(await contarDe(db, { uid: 'rita', rol: 'rescatista' }), {
    contadorRescatistaTotal: 4,
    contadorRescatistaAdoptados: 1,
  });
});

// ── Albergue: En cuidado = Rescatado + Regresado, sin Hogar de paso ───
test('albergue: "en cuidado" son Rescatado + Regresado, y nada más', async () => {
  const db = firestoreFalso([
    delAlbergue({ estadoAdopcion: 'Rescatado' }),
    delAlbergue({ estadoAdopcion: 'Rescatado' }),
    delAlbergue({ estadoAdopcion: 'Regresado' }),
    delAlbergue({ estadoAdopcion: 'Hogar de paso' }),
    delAlbergue({ estadoAdopcion: 'En proceso de adopción' }),
    delAlbergue({ estadoAdopcion: 'Adoptado' }),
  ]);
  assert.deepStrictEqual(await contarDe(db, { uid: 'refugio', rol: 'albergue' }), {
    contadorAlbergueEnCuidado: 3,
    contadorAlbergueAdoptados: 1,
  });
});

// El caso real de Eliza, con los números que verifiqué contra producción:
// 52 Rescatado + 2 Regresado + 5 Hogar de paso + 3 Adoptado + 1 En proceso.
test('el albergue real de Eliza da 54 en cuidado y 3 adoptados', async () => {
  const muchos = [];
  const sembrar = (n, estado) => {
    for (let i = 0; i < n; i++) muchos.push(delAlbergue({ estadoAdopcion: estado }));
  };
  sembrar(52, 'Rescatado');
  sembrar(2, 'Regresado');
  sembrar(5, 'Hogar de paso');
  sembrar(3, 'Adoptado');
  sembrar(1, 'En proceso de adopción');

  assert.deepStrictEqual(
      await contarDe(firestoreFalso(muchos), { uid: 'refugio', rol: 'albergue' }),
      { contadorAlbergueEnCuidado: 54, contadorAlbergueAdoptados: 3 },
  );
});

// ── El bug de roles cruzados, en su versión contador ──────────────────
test('los dos sombreros de una misma cuenta no se mezclan', async () => {
  const db = firestoreFalso([
    { rescatistaId: 'rita', creadoPor: 'rescatista', estadoAdopcion: 'Rescatado' },
    { rescatistaId: 'rita', creadoPor: 'albergue', estadoAdopcion: 'Rescatado' },
    { rescatistaId: 'rita', creadoPor: 'albergue', estadoAdopcion: 'Adoptado' },
  ]);
  assert.deepStrictEqual(await contarDe(db, { uid: 'rita', rol: 'rescatista' }), {
    contadorRescatistaTotal: 1,
    contadorRescatistaAdoptados: 0,
  });
  assert.deepStrictEqual(await contarDe(db, { uid: 'rita', rol: 'albergue' }), {
    contadorAlbergueEnCuidado: 1,
    contadorAlbergueAdoptados: 1,
  });
});

test('ni los animalitos de otra persona', async () => {
  const db = firestoreFalso([
    delAlbergue(),
    { rescatistaId: 'otro', creadoPor: 'albergue', estadoAdopcion: 'Rescatado' },
  ]);
  assert.deepStrictEqual(await contarDe(db, { uid: 'refugio', rol: 'albergue' }), {
    contadorAlbergueEnCuidado: 1,
    contadorAlbergueAdoptados: 0,
  });
});

// ── Alta, baja y adopción escriben el número nuevo ────────────────────
test('publicar escribe el total nuevo, en el campo del rol que toca', async () => {
  const db = firestoreFalso([delAlbergue(), delAlbergue()]);
  await manejarEscritura({ db, antes: undefined, despues: delAlbergue() });

  assert.deepStrictEqual(db.escrituras, [
    {
      uid: 'refugio',
      cambios: { contadorAlbergueEnCuidado: 2, contadorAlbergueAdoptados: 0 },
    },
  ]);
});

test('borrar también', async () => {
  const db = firestoreFalso([delRescatista()]);
  await manejarEscritura({ db, antes: delRescatista(), despues: undefined });
  assert.strictEqual(db.escrituras[0].cambios.contadorRescatistaTotal, 1);
});

// Aprobar una solicitud no toca ningún contador por su cuenta: escribe
// `estadoAdopcion: 'Adoptado'` en el animalito (solicitudes_repository.dart),
// y eso es lo que despierta este trigger. Por eso el mismo camino cubre
// "aprobé una adopción" y "cambié el estado a mano desde el panel".
test('aprobar una adopción mueve los DOS números del albergue', async () => {
  const db = firestoreFalso([
    delAlbergue({ estadoAdopcion: 'Adoptado' }),
    delAlbergue({ estadoAdopcion: 'Rescatado' }),
  ]);
  await manejarEscritura({
    db,
    antes: delAlbergue({ estadoAdopcion: 'En proceso de adopción' }),
    despues: delAlbergue({ estadoAdopcion: 'Adoptado' }),
  });

  assert.deepStrictEqual(db.escrituras, [
    {
      uid: 'refugio',
      // El animalito salió de "en cuidado" y entró en "adoptados": los dos
      // números cambian con la misma escritura.
      cambios: { contadorAlbergueEnCuidado: 1, contadorAlbergueAdoptados: 1 },
    },
  ]);
});

test('y en el rescatista sube adoptados sin bajar el total', async () => {
  const db = firestoreFalso([
    delRescatista({ estadoAdopcion: 'Adoptado' }),
    delRescatista(),
  ]);
  await manejarEscritura({
    db,
    antes: delRescatista({ estadoAdopcion: 'Rescatado' }),
    despues: delRescatista({ estadoAdopcion: 'Adoptado' }),
  });

  assert.deepStrictEqual(db.escrituras[0].cambios, {
    contadorRescatistaTotal: 2,
    contadorRescatistaAdoptados: 1,
  });
});

// ── Lo que NO tiene que escribir ──────────────────────────────────────
test('cambiar el nombre de un animalito no escribe nada', async () => {
  const db = firestoreFalso([delAlbergue()]);
  await manejarEscritura({
    db,
    antes: delAlbergue({ nombre: 'Naranjita' }),
    despues: delAlbergue({ nombre: 'Naranjito' }),
  });
  assert.deepStrictEqual(db.escrituras, [],
      'una reescritura masiva de nombres no puede disparar agregaciones');
});

test('un animalito de un rol sin contador no escribe en ningún perfil', async () => {
  const db = firestoreFalso([delAlbergue()]);
  await manejarEscritura({
    db,
    antes: undefined,
    despues: { rescatistaId: 'vete', creadoPor: 'aliado' },
  });
  assert.deepStrictEqual(db.escrituras, []);
});

// ── Idempotencia: la razón de recontar en vez de incrementar ──────────
test('procesar dos veces el mismo evento deja el mismo número', async () => {
  const db = firestoreFalso([delAlbergue(), delAlbergue()]);
  const evento = { antes: undefined, despues: delAlbergue() };

  await manejarEscritura({ db, ...evento });
  await manejarEscritura({ db, ...evento });

  assert.strictEqual(db.escrituras.length, 2, 'escribió las dos veces');
  assert.deepStrictEqual(
      db.escrituras[0].cambios,
      db.escrituras[1].cambios,
      'un reintento de Eventarc no puede cambiar el resultado: con '
      + 'increment(1) el número quedaría inflado para siempre',
  );
});

// ── Un perfil que no existe no rompe el trigger ni se crea solo ───────
test('si el perfil no existe, no explota y no se crea un documento fantasma',
    async () => {
      const db = firestoreFalso(
          [delAlbergue({ rescatistaId: 'fantasma' })], ['refugio']);
      await manejarEscritura({
        db,
        antes: undefined,
        despues: delAlbergue({ rescatistaId: 'fantasma' }),
      });
      assert.deepStrictEqual(db.escrituras, []);
    });
