const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const { motivoBloqueo, clasificarSolicitud, clasificarChat } = require('../eliminar_cuenta_logica');

describe('motivoBloqueo', () => {
  test('null si no hay ningún animal en estado activo a cargo de la cuenta', () => {
    assert.equal(motivoBloqueo({ tieneComoAdoptante: false, tieneComoRescatista: false }), null);
  });

  test('bloquea si la cuenta tiene un animal a su cargo ahora mismo (hogar de paso/en proceso)', () => {
    const mensaje = motivoBloqueo({ tieneComoAdoptante: true, tieneComoRescatista: false });
    assert.match(mensaje, /a tu cargo/);
  });

  test('bloquea si la cuenta (rescatista/albergue) tiene un animal publicado activo con otra persona', () => {
    const mensaje = motivoBloqueo({ tieneComoAdoptante: false, tieneComoRescatista: true });
    assert.match(mensaje, /con otra persona/);
  });

  test('el lado "adoptante" gana si por algún motivo aplican los dos a la vez', () => {
    const mensaje = motivoBloqueo({ tieneComoAdoptante: true, tieneComoRescatista: true });
    assert.match(mensaje, /a tu cargo/);
  });
});

describe('clasificarSolicitud', () => {
  const UID = 'uid-adoptante';

  test('pendiente se borra — no llegó a nada', () => {
    assert.equal(clasificarSolicitud({ estado: 'pendiente', adoptanteId: UID }, UID), 'borrar');
  });

  test('rechazada se borra — no llegó a nada', () => {
    assert.equal(clasificarSolicitud({ estado: 'rechazada', adoptanteId: UID }, UID), 'borrar');
  });

  test('aprobada y esta cuenta es quien adoptó — se anonimiza, no se borra '
      + '(el rescatista necesita conservar el registro permanente de la adopción)', () => {
    assert.equal(clasificarSolicitud({ estado: 'aprobada', adoptanteId: UID }, UID), 'anonimizar');
  });

  test('aprobada pero esta cuenta es el rescatista/albergue (no el adoptante) — se deja '
      + 'como está, los datos personales del documento son de OTRA cuenta', () => {
    assert.equal(clasificarSolicitud({ estado: 'aprobada', adoptanteId: 'otro-uid' }, UID), 'dejar');
  });
});

describe('clasificarChat', () => {
  test('consulta a un aliado siempre se anonimiza, aunque no haya ninguna solicitud aprobada '
      + '— para poder reportar "cuántas consultas recibió cada aliado" sin datos personales', () => {
    const resultado = clasificarChat(
      { tipoSolicitud: 'consulta_aliado', rescateId: '', adoptanteId: 'uid-1' },
      new Set(),
    );
    assert.equal(resultado, 'anonimizar');
  });

  test('chat de un animal con una adopción ya aprobada se anonimiza, no se borra', () => {
    const clavesAprobadas = new Set(['rescate-1_uid-1']);
    const resultado = clasificarChat(
      { tipoSolicitud: undefined, rescateId: 'rescate-1', adoptanteId: 'uid-1' },
      clavesAprobadas,
    );
    assert.equal(resultado, 'anonimizar');
  });

  test('chat de un animal SIN adopción aprobada se borra', () => {
    const resultado = clasificarChat(
      { tipoSolicitud: undefined, rescateId: 'rescate-2', adoptanteId: 'uid-1' },
      new Set(['rescate-1_uid-1']),
    );
    assert.equal(resultado, 'borrar');
  });

  test('chat legado sin rescateId (no se puede emparejar con ninguna solicitud aprobada) se borra', () => {
    const resultado = clasificarChat(
      { tipoSolicitud: undefined, rescateId: '', adoptanteId: 'uid-1' },
      new Set(['rescate-1_uid-1']), // ninguna clave aprobada coincide con un rescateId vacío
    );
    assert.equal(resultado, 'borrar');
  });
});
