const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const {
  decidirAviso,
  textoVenceManana,
  textoVencido,
  comoAvisar,
  nombreEnFrase,
  tituloPush,
} = require('../avisos_vencimiento_logica');

// 2026-08-20 12:00 como "ahora" en todos los tests, para no depender de
// cuándo se corre la suite.
const AHORA = new Date(2026, 7, 20, 12, 0, 0);

describe('decidirAviso', () => {
  test('null si falta más de un día para vencer', () => {
    const fechaFin = new Date(2026, 7, 25);
    assert.equal(
      decidirAviso({ fechaFin, ahora: AHORA, avisoPrevioAvisado: false, vencimientoAvisado: false, nombre: 'Toby' }),
      null,
    );
  });

  test('avisa "previo" cuando falta exactamente un día y todavía no se avisó', () => {
    const fechaFin = new Date(2026, 7, 21);
    const aviso = decidirAviso({ fechaFin, ahora: AHORA, avisoPrevioAvisado: false, vencimientoAvisado: false, nombre: 'Toby' });
    assert.equal(aviso.tipo, 'previo');
    assert.equal(aviso.flag, 'avisoPrevioAvisado');
    assert.equal(aviso.mensaje, textoVenceManana('Toby'));
  });

  test('null si falta un día pero el aviso previo YA se mandó — no se duplica', () => {
    const fechaFin = new Date(2026, 7, 21);
    assert.equal(
      decidirAviso({ fechaFin, ahora: AHORA, avisoPrevioAvisado: true, vencimientoAvisado: false, nombre: 'Toby' }),
      null,
    );
  });

  test('avisa "vencido" el mismo día que vence', () => {
    const fechaFin = new Date(2026, 7, 20, 8, 0);
    const aviso = decidirAviso({ fechaFin, ahora: AHORA, avisoPrevioAvisado: false, vencimientoAvisado: false, nombre: 'Toby' });
    assert.equal(aviso.tipo, 'vencido');
    assert.equal(aviso.flag, 'vencimientoAvisado');
    assert.equal(aviso.mensaje, textoVencido('Toby'));
  });

  test('avisa "vencido" muchos días después de vencido, si todavía no se avisó', () => {
    const fechaFin = new Date(2026, 7, 1);
    const aviso = decidirAviso({ fechaFin, ahora: AHORA, avisoPrevioAvisado: true, vencimientoAvisado: false, nombre: 'Toby' });
    assert.equal(aviso.tipo, 'vencido');
  });

  test('null si ya venció y el aviso de vencido YA se mandó — no se duplica', () => {
    const fechaFin = new Date(2026, 7, 1);
    assert.equal(
      decidirAviso({ fechaFin, ahora: AHORA, avisoPrevioAvisado: true, vencimientoAvisado: true, nombre: 'Toby' }),
      null,
    );
  });

  test('no confunde "falta un día" con "faltan dos" — solo avisa el día exacto antes', () => {
    const fechaFin = new Date(2026, 7, 22);
    assert.equal(
      decidirAviso({ fechaFin, ahora: AHORA, avisoPrevioAvisado: false, vencimientoAvisado: false, nombre: 'Toby' }),
      null,
    );
  });
});

describe(
  'comoAvisar — un hogar de paso puesto A MANO no tiene cuenta en la app. ' +
  'Antes eso hacia que la funcion salteara el animalito entero, asi que el ' +
  'rescatista TAMPOCO se enteraba: el recordatorio no existia para el caso ' +
  'mas comun en un refugio de verdad.',
  () => {
    test('con cuidador con cuenta: por chat, y los dos lo ven', () => {
      assert.deepStrictEqual(
          comoAvisar({ adoptanteIdEnProceso: 'ana', rescatistaId: 'rita' }),
          { via: 'chat', adoptanteId: 'ana', rescatistaId: 'rita' },
      );
    });

    // EL CASO QUE MOTIVA TODO ESTO.
    test('sin cuidador con cuenta: igual le llega al dueno, por push', () => {
      assert.deepStrictEqual(
          comoAvisar({ rescatistaId: 'rita' }),
          { via: 'push', rescatistaId: 'rita' },
      );
    });

    test('un adoptanteId vacio o en blanco cuenta como sin cuenta', () => {
      for (const vacio of ['', '   ', null, undefined]) {
        assert.strictEqual(
            comoAvisar({ adoptanteIdEnProceso: vacio, rescatistaId: 'rita' }).via,
            'push',
            `con ${JSON.stringify(vacio)}`,
        );
      }
    });

    // Lo unico que sigue sin tener salida: un animalito sin dueno. Ahi de
    // verdad no hay a quien avisarle.
    test('sin dueno no hay a quien avisar', () => {
      assert.strictEqual(comoAvisar({ rescatistaId: '' }), null);
      assert.strictEqual(comoAvisar({ adoptanteIdEnProceso: 'ana' }), null);
    });

    test('el titulo del push distingue "vence manana" de "ya vencio"', () => {
      assert.notStrictEqual(tituloPush('previo'), tituloPush('vencido'));
      assert.ok(tituloPush('previo').includes('manana') ||
                tituloPush('previo').includes('mañana'));
    });
  },
);

describe(
  'nombreEnFrase — el espejo en JS de nombreDeAnimal(enFrase: true). ' +
  'Existir dos veces es inevitable (el servidor no puede importar Dart) ' +
  'pero UNA por lenguaje, no diez.',
  () => {
    test('con nombre real lo deja tal cual', () => {
      assert.strictEqual(nombreEnFrase('Pacolin'), 'Pacolin');
    });

    test('sin nombre da la forma de frase, no la de titulo', () => {
      assert.strictEqual(nombreEnFrase(''), 'un animalito');
      assert.strictEqual(nombreEnFrase('   '), 'un animalito');
      assert.strictEqual(nombreEnFrase(null), 'un animalito');
      assert.strictEqual(nombreEnFrase(undefined), 'un animalito');
    });

    // El texto de pantalla se colo a la base guardado como si fuera el dato
    // real. Sin esto la push diria "El periodo de hogar de paso de Sin
    // nombre vence manana".
    test('el literal "Sin nombre" GUARDADO cuenta como no tener nombre', () => {
      assert.strictEqual(nombreEnFrase('Sin nombre'), 'un animalito');
    });

    // Y un animalito que de verdad se llama parecido no cae en el caso de
    // arriba: la comparacion es exacta, igual que en Dart.
    test('un nombre que solo se PARECE al relleno se respeta', () => {
      assert.strictEqual(nombreEnFrase('Sin nombre aun'), 'Sin nombre aun');
    });

    test('y el texto del aviso queda legible', () => {
      const { textoVenceManana } = require('../avisos_vencimiento_logica');
      assert.ok(
          textoVenceManana(nombreEnFrase('')).includes('de un animalito'),
          textoVenceManana(nombreEnFrase('')),
      );
    });
  },
);
