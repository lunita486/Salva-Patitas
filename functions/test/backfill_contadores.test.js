const { test } = require('node:test');
const assert = require('node:assert');
const { unirPares, clave } = require('../_backfill_contadores');

// A quién alcanza el backfill.
//
// Buscaba las cuentas solo por su campo `roles`, y eso dejaba afuera un caso
// REAL de producción: 'albergue' y 'rescatista' son mutuamente excluyentes
// en el onboarding, así que una cuenta que publicó con un sombrero y después
// eligió el otro conserva los animalitos viejos y pierde el rol con el que
// los publicó. Sus contadores de ese rol no se sembraban nunca.
//
// La fuente de verdad de a qué contador pertenece un animalito es su
// `creadoPor`, igual que en el trigger, que tampoco mira `roles`.

const animales = (...pares) => new Set(pares.map(([u, r]) => clave(u, r)));
const roles = animales;

test('una cuenta con rol y con animalitos aparece una sola vez', () => {
  const r = unirPares({
    deAnimales: animales(['refugio', 'albergue']),
    deRoles: roles(['refugio', 'albergue']),
  });
  assert.deepStrictEqual(r, [
    { uid: 'refugio', roles: [{ rol: 'albergue', origen: 'ambos' }] },
  ]);
});

// EL caso que motivó el cambio, con los números reales de producción:
// 29 animalitos como rescatista y 7 como albergue, en una cuenta que por el
// modelo de roles solo puede declarar uno de los dos.
test('una cuenta que perdió el rol igual entra, por sus animalitos', () => {
  const r = unirPares({
    deAnimales: animales(['bFHZ', 'rescatista'], ['bFHZ', 'albergue']),
    deRoles: roles(['bFHZ', 'rescatista']),
  });
  assert.deepStrictEqual(r, [
    {
      uid: 'bFHZ',
      roles: [
        { rol: 'albergue', origen: 'animalitos' },
        { rol: 'rescatista', origen: 'ambos' },
      ],
    },
  ]);
});

// Y el caso simétrico, que es por qué no alcanza con mirar solo los
// animalitos: sin esta mitad, una cuenta nueva sin nada publicado nunca
// recibiría su 0 y caería al count() para siempre.
test('una cuenta con rol y sin ningún animalito también entra', () => {
  const r = unirPares({
    deAnimales: animales(),
    deRoles: roles(['nuevo', 'albergue']),
  });
  assert.deepStrictEqual(r, [
    { uid: 'nuevo', roles: [{ rol: 'albergue', origen: 'roles' }] },
  ]);
});

test('cada rol de una cuenta se anota por separado', () => {
  const r = unirPares({
    deAnimales: animales(['dos', 'albergue']),
    deRoles: roles(['dos', 'rescatista']),
  });
  assert.deepStrictEqual(r[0].roles, [
    { rol: 'albergue', origen: 'animalitos' },
    { rol: 'rescatista', origen: 'roles' },
  ]);
});

test('sin nada de ningún lado, no hay a quién escribirle', () => {
  assert.deepStrictEqual(unirPares({ deAnimales: animales(), deRoles: roles() }), []);
});

test('el resultado es estable: dos corridas imprimen lo mismo', () => {
  const a = unirPares({
    deAnimales: animales(['zeta', 'albergue'], ['alfa', 'rescatista']),
    deRoles: roles(['medio', 'albergue'], ['alfa', 'albergue']),
  });
  const b = unirPares({
    deAnimales: animales(['alfa', 'rescatista'], ['zeta', 'albergue']),
    deRoles: roles(['alfa', 'albergue'], ['medio', 'albergue']),
  });
  assert.deepStrictEqual(a, b);
  assert.deepStrictEqual(a.map((c) => c.uid), ['alfa', 'medio', 'zeta']);
});

test('el origen distingue lo que la versión vieja se salteaba', () => {
  const r = unirPares({
    deAnimales: animales(['x', 'albergue'], ['y', 'albergue']),
    deRoles: roles(['y', 'albergue']),
  });
  const soloPorAnimalitos = r.flatMap((c) =>
    c.roles.filter((rol) => rol.origen === 'animalitos').map(() => c.uid),
  );
  assert.deepStrictEqual(
      soloPorAnimalitos,
      ['x'],
      'sin esto el simulacro no deja ver a quién se estaba salteando',
  );
});


// El separador de la clave es NUL, no un espacio ni un guion: un uid de
// Firebase es alfanumérico, así que NUL no puede aparecer adentro de uno y
// el par nunca se parte mal. Con un separador que sí pudiera aparecer en un
// uid, se le escribirían contadores a una cuenta inventada.
test('el separador no puede aparecer en un uid de Firebase', () => {
  const uid = 'jqElNvVgfGMfSZpttHaTvSTbRax1';
  assert.deepStrictEqual(clave(uid, 'albergue').split('\u0000'), [uid, 'albergue']);
  assert.match(uid, /^[A-Za-z0-9_-]+$/);
});
