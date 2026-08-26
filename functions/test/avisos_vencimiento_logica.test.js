const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const {
  decidirAviso,
  textoVenceManana,
  textoVencido,
  comoAvisar,
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
