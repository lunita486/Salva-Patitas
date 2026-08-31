const { test } = require('node:test');
const assert = require('node:assert');
const {
  DEFINICIONES,
  CAMPOS,
  definicionDe,
  aRecontar,
  contadoresDesactualizados,
} = require('../contadores_logica');

// Qué se custodia acá: CUÁNDO se recuenta y de quién.
//
// El recuento en sí se prueba en contadores.test.js. Lo que se prueba en
// este archivo es el guard: recontar de más cuesta plata en cada escritura
// masiva, y recontar de menos deja el número mentiroso hasta la próxima vez
// que esa persona toque un animalito.

const animalito = (extra = {}) => ({
  rescatistaId: 'rita',
  creadoPor: 'rescatista',
  estadoAdopcion: 'Rescatado',
  nombre: 'Naranjita',
  ...extra,
});
const deAlbergue = (extra = {}) =>
  animalito({ rescatistaId: 'refugio', creadoPor: 'albergue', ...extra });

// ── La tabla de definiciones ──────────────────────────────────────────
test('hay una definición por rol, y ningún campo repetido', () => {
  assert.deepStrictEqual(DEFINICIONES.map((d) => d.rol), ['rescatista', 'albergue']);
  assert.strictEqual(new Set(CAMPOS).size, CAMPOS.length, 'dos contadores comparten campo');
  assert.strictEqual(CAMPOS.length, 4);
});

test('cada campo dice de qué rol habla', () => {
  // Una misma cuenta puede ser rescatista Y albergue a la vez. Si los
  // nombres no dijeran de qué sombrero hablan, un contador pisaría al otro
  // sin que nadie lo note.
  for (const { rol, campos } of DEFINICIONES) {
    for (const { campo } of campos) {
      assert.match(campo.toLowerCase(), new RegExp(rol));
    }
  }
});

// Las definiciones son las que ya tenían las pantallas. Este test es el que
// se rompe si alguien "ordena" la tabla y de paso cambia qué se cuenta.
test('las definiciones son exactamente las de las pantallas', () => {
  assert.deepStrictEqual(definicionDe('rescatista').campos, [
    // "Animales rescatados": TODOS los estados, también adoptados y fallecidos.
    { campo: 'contadorRescatistaTotal', estados: null },
    { campo: 'contadorRescatistaAdoptados', estados: ['Adoptado'] },
  ]);
  assert.deepStrictEqual(definicionDe('albergue').campos, [
    // "En cuidado" / "Disponibles": la misma lista que la grilla. Sin
    // 'Hogar de paso'.
    { campo: 'contadorAlbergueEnCuidado', estados: ['Rescatado', 'Regresado'] },
    { campo: 'contadorAlbergueAdoptados', estados: ['Adoptado'] },
  ]);
});

test('un rol sin contadores no tiene definición', () => {
  assert.strictEqual(definicionDe('adoptante'), undefined);
  assert.strictEqual(definicionDe('aliado'), undefined);
  assert.strictEqual(definicionDe(undefined), undefined);
});

// ── El guard, para los dos roles ──────────────────────────────────────
test('publicar recuenta al dueño, en su rol', () => {
  assert.deepStrictEqual(aRecontar({ antes: undefined, despues: animalito() }), [
    { uid: 'rita', rol: 'rescatista' },
  ]);
  assert.deepStrictEqual(aRecontar({ antes: undefined, despues: deAlbergue() }), [
    { uid: 'refugio', rol: 'albergue' },
  ]);
});

test('borrar también', () => {
  assert.deepStrictEqual(aRecontar({ antes: animalito(), despues: undefined }), [
    { uid: 'rita', rol: 'rescatista' },
  ]);
  assert.deepStrictEqual(aRecontar({ antes: deAlbergue(), despues: undefined }), [
    { uid: 'refugio', rol: 'albergue' },
  ]);
});

test('cambiar el estado recuenta, en los dos roles', () => {
  for (const hacer of [animalito, deAlbergue]) {
    const r = aRecontar({
      antes: hacer({ estadoAdopcion: 'Rescatado' }),
      despues: hacer({ estadoAdopcion: 'Adoptado' }),
    });
    assert.strictEqual(r.length, 1);
    assert.strictEqual(r[0].rol, hacer === animalito ? 'rescatista' : 'albergue');
  }
});

test('y sacarlo de Adoptado también, para que el número pueda bajar', () => {
  assert.deepStrictEqual(
      aRecontar({
        antes: deAlbergue({ estadoAdopcion: 'Adoptado' }),
        despues: deAlbergue({ estadoAdopcion: 'Regresado' }),
      }),
      [{ uid: 'refugio', rol: 'albergue' }],
  );
});

// EL test del guard. Sin esto, cambiar la foto del perfil dispara una
// reescritura en masa de todos los animalitos (onPerfilActualizado), y cada
// una de esas escrituras pediría dos agregaciones.
test('cambiar el nombre o la foto NO recuenta nada', () => {
  for (const hacer of [animalito, deAlbergue]) {
    assert.deepStrictEqual(
        aRecontar({
          antes: hacer({ nombre: 'Naranjita', fotoUrl: 'a.jpg' }),
          despues: hacer({ nombre: 'Naranjito', fotoUrl: 'b.jpg' }),
        }),
        [],
    );
  }
});

test('los roles sin contador no despiertan nada', () => {
  const deAliado = { rescatistaId: 'vete', creadoPor: 'aliado' };
  assert.deepStrictEqual(aRecontar({ antes: undefined, despues: deAliado }), []);
  assert.deepStrictEqual(aRecontar({ antes: deAliado, despues: undefined }), []);
});

test('un documento sin rescatistaId no rompe ni escribe en ningún lado', () => {
  assert.deepStrictEqual(
      aRecontar({ antes: undefined, despues: { creadoPor: 'albergue' } }), []);
  assert.deepStrictEqual(
      aRecontar({
        antes: undefined,
        despues: { creadoPor: 'albergue', rescatistaId: '' },
      }),
      [],
  );
  assert.deepStrictEqual(aRecontar({}), []);
});

// Hoy las reglas prohíben mover rescatistaId y creadoPor después de creado,
// así que esto solo llegaría por una escritura de admin. Queda cubierto
// igual: son DOS contadores los que quedan mal, no uno.
test('si un animalito cambiara de dueño, se recuentan los dos', () => {
  assert.deepStrictEqual(
      aRecontar({
        antes: animalito({ rescatistaId: 'rita' }),
        despues: animalito({ rescatistaId: 'carmen' }),
      }),
      [{ uid: 'rita', rol: 'rescatista' }, { uid: 'carmen', rol: 'rescatista' }],
  );
});

test('si cambiara de rol, se recuentan los dos sombreros', () => {
  assert.deepStrictEqual(
      aRecontar({
        antes: animalito({ rescatistaId: 'rita', creadoPor: 'rescatista' }),
        despues: animalito({ rescatistaId: 'rita', creadoPor: 'albergue' }),
      }),
      [{ uid: 'rita', rol: 'rescatista' }, { uid: 'rita', rol: 'albergue' }],
  );
});

// ── El comparador del backfill ────────────────────────────────────────
test('una cuenta sin contadores está desactualizada; una al día, no', () => {
  const nuevos = { contadorAlbergueEnCuidado: 54, contadorAlbergueAdoptados: 3 };

  assert.strictEqual(contadoresDesactualizados({ nombre: 'Refugio' }, nuevos), true);
  assert.strictEqual(contadoresDesactualizados(undefined, nuevos), true);
  assert.strictEqual(contadoresDesactualizados({ ...nuevos }, nuevos), false);
  assert.strictEqual(
      contadoresDesactualizados({ ...nuevos, contadorAlbergueAdoptados: 2 }, nuevos),
      true,
  );
  // Un cero real cuenta como dato: no se reescribe si ya está.
  assert.strictEqual(
      contadoresDesactualizados(
          { contadorAlbergueEnCuidado: 0, contadorAlbergueAdoptados: 0 },
          { contadorAlbergueEnCuidado: 0, contadorAlbergueAdoptados: 0 },
      ),
      false,
  );
});

test('los contadores del OTRO rol no cuentan como desactualización', () => {
  // Una cuenta con los dos sombreros: al mirar solo los del albergue, que
  // los del rescatista existan o no es irrelevante.
  const nuevos = { contadorAlbergueEnCuidado: 54, contadorAlbergueAdoptados: 3 };
  assert.strictEqual(
      contadoresDesactualizados({ ...nuevos, contadorRescatistaTotal: 7 }, nuevos),
      false,
  );
});
