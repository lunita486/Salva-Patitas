const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const L = require('../equipo_logica');

// Lógica pura del equipo del albergue. Las pruebas con Firestore (incluida
// la concurrencia) están en equipo.emulador.test.js.

const fecha = (anio, mes, dia) => ({ toMillis: () => Date.UTC(anio, mes - 1, dia) });
const codigo = (fn) => { try { fn(); } catch (e) { return e.code; } return null; };

describe('validarPayload: solo los campos permitidos', () => {
  test('acepta exactamente lo permitido', () => {
    L.validarPayload({ email: 'a@b.co' }, ['email']);
    L.validarPayload({}, ['email']);
  });
  for (const [caso, data] of [
    ['campo inventado', { email: 'a@b.co', sinHogaresDudosos: true }],
    ['albergue elegido por el cliente', { email: 'a@b.co', albergueId: 'otro' }],
    ['hogares "revisados" por el cliente', { invitacionId: 'x', hogaresRevisados: ['h1'] }],
    ['null', null],
    ['una lista', ['email']],
    ['un texto', 'email'],
  ]) {
    test(`rechaza: ${caso}`, () => {
      assert.equal(codigo(() => L.validarPayload(data, ['email', 'invitacionId'])), 'invalid-argument');
    });
  }
});

describe('correo', () => {
  test('normaliza mayúsculas y espacios', () => assert.equal(L.normalizarEmail('  Ana@Mail.COM '), 'ana@mail.com'));
  test('no texto da vacío', () => assert.equal(L.normalizarEmail(42), ''));
  for (const malo of ['', 'ana', 'ana@', '@mail.com', 'ana@mail', 'a na@mail.com']) {
    test(`inválido: ${JSON.stringify(malo)}`, () => assert.equal(L.emailValido(malo), false));
  }
  test('válido', () => assert.equal(L.emailValido('ana@mail.com'), true));
});

describe('identidades', () => {
  test('responsable: rol albergue y nombre', () => {
    assert.equal(L.esResponsable({ roles: ['albergue'], albergueNombre: 'La Perla' }), true);
    assert.equal(L.esResponsable({ roles: ['albergue'] }), false);
    assert.equal(L.esResponsable({ roles: ['albergue'], albergueNombre: '  ' }), false);
    assert.equal(L.esResponsable({ roles: 'albergue', albergueNombre: 'X' }), false);
    assert.equal(L.esResponsable(null), false);
  });
  test('señal de responsable con el perfil incompleto', () => {
    assert.equal(L.tieneSenalDeResponsable({ roles: ['albergue'] }), true);
    assert.equal(L.tieneSenalDeResponsable({ albergueNombre: 'X' }), true);
    assert.equal(L.tieneSenalDeResponsable({ roles: ['adoptante'] }), false);
  });
  test('negocio aliado por rol o por nombre de negocio', () => {
    assert.equal(L.esNegocioAliado({ roles: ['aliado'] }), true);
    assert.equal(L.esNegocioAliado({ aliadoNombre: 'Vet 30' }), true);
    assert.equal(L.esNegocioAliado({ roles: ['adoptante'] }), false);
  });
});

describe('hogares de paso: sin revisión ni barrera desde la fase 2', () => {
  test('la lógica ya no exporta nada de hogares dudosos ni de revisión', () => {
    for (const nombre of ['hogarDudoso', 'revisionValida', 'hogaresPendientesDeRevision',
      'errorHogaresPendientes', 'comprobarPuedeRevisarHogar', 'REGLA_ROL_ALBERGUE', 'DECISIONES_REVISION']) {
      assert.equal(L[nombre], undefined, nombre);
    }
  });
  test('el mensaje genérico para la invitada no da pistas de la cuenta', () => {
    const e = L.errorAlbergueNoDisponible();
    assert.equal(e.code, 'failed-precondition');
    assert.doesNotMatch(e.message, /\d/, 'sin números');
    assert.doesNotMatch(e.message, /rescatista|hogar|aliado/i);
  });
});

describe('invitar', () => {
  const resp = { roles: ['albergue'], albergueNombre: 'La Perla' };
  test('la responsable puede', () => L.comprobarPuedeInvitar({ usuario: resp, membresiaPropia: null }));
  test('sin perfil de responsable, no', () => {
    assert.equal(codigo(() => L.comprobarPuedeInvitar({ usuario: { roles: ['albergue'] }, membresiaPropia: null })), 'permission-denied');
    assert.equal(codigo(() => L.comprobarPuedeInvitar({ usuario: { roles: ['adoptante'] }, membresiaPropia: null })), 'permission-denied');
    assert.equal(codigo(() => L.comprobarPuedeInvitar({ usuario: null, membresiaPropia: null })), 'permission-denied');
  });
  test('un miembro activo no puede invitar', () => {
    assert.equal(codigo(() => L.comprobarPuedeInvitar({ usuario: resp, membresiaPropia: { estado: 'activa' } })), 'permission-denied');
    L.comprobarPuedeInvitar({ usuario: resp, membresiaPropia: { estado: 'revocada' } });
  });
  test('una responsable que también es negocio aliado no puede', () => {
    assert.equal(codigo(() => L.comprobarPuedeInvitar({ usuario: { ...resp, roles: ['albergue', 'aliado'] }, membresiaPropia: null })), 'failed-precondition');
  });
  test('vigencia de 7 días', () => {
    const t = Date.UTC(2026, 9, 22);
    assert.equal(L.venceEn(t) - t, 7 * 24 * 60 * 60 * 1000);
    assert.equal(L.invitacionVigente({ estado: 'pendiente', expiraEn: { toMillis: () => t + 1 } }, t), true);
    assert.equal(L.invitacionVigente({ estado: 'pendiente', expiraEn: { toMillis: () => t } }, t), false);
    assert.equal(L.invitacionVigente({ estado: 'aceptada', expiraEn: { toMillis: () => t + 1 } }, t), false);
    assert.equal(L.invitacionVigente({ estado: 'pendiente' }, t), false, 'sin fecha de vencimiento no es vigente');
  });
});

describe('aceptar', () => {
  const t = Date.UTC(2026, 9, 22);
  const base = () => ({
    invitacion: { albergueId: 'resp', emailDestino: 'ana@mail.com', estado: 'pendiente', expiraEn: { toMillis: () => t + 1000 } },
    uid: 'ana', email: 'ana@mail.com', ahora: t, membresiaPropia: null,
    usuario: { roles: ['adoptante', 'rescatista'] },
    responsable: { roles: ['albergue'], albergueNombre: 'La Perla' },
  });
  const con = (cambios) => ({ ...base(), ...cambios });

  test('caso válido, aunque la persona sea rescatista y adoptante', () => {
    assert.deepEqual(L.comprobarPuedeAceptar(base()), { vencida: false });
  });
  test('otro correo: rechazo, y no se entera de si venció', () => {
    const vencidaAjena = con({ email: 'otra@mail.com', invitacion: { ...base().invitacion, expiraEn: { toMillis: () => t - 1 } } });
    assert.equal(codigo(() => L.comprobarPuedeAceptar(vencidaAjena)), 'permission-denied');
  });
  test('vencida: se informa para marcarla', () => {
    assert.deepEqual(L.comprobarPuedeAceptar(con({ invitacion: { ...base().invitacion, expiraEn: { toMillis: () => t } } })), { vencida: true });
  });
  for (const estado of ['aceptada', 'revocada', 'expirada']) {
    test(`invitación ${estado}: rechazo`, () => {
      assert.equal(codigo(() => L.comprobarPuedeAceptar(con({ invitacion: { ...base().invitacion, estado } }))), 'failed-precondition');
    });
  }
  test('invitación propia: rechazo', () => {
    assert.equal(codigo(() => L.comprobarPuedeAceptar(con({ uid: 'resp' }))), 'permission-denied');
  });
  test('ya es miembro activo: rechazo', () => {
    assert.equal(codigo(() => L.comprobarPuedeAceptar(con({ membresiaPropia: { estado: 'activa' } }))), 'failed-precondition');
  });
  test('quien acepta es responsable (aunque el perfil esté incompleto) o negocio aliado: rechazo', () => {
    assert.equal(codigo(() => L.comprobarPuedeAceptar(con({ usuario: { roles: ['albergue'] } }))), 'permission-denied');
    assert.equal(codigo(() => L.comprobarPuedeAceptar(con({ usuario: { roles: ['aliado'] } }))), 'permission-denied');
  });
  test('la responsable dejó de serlo o se volvió negocio aliado: rechazo con el mensaje genérico', () => {
    const generico = L.errorAlbergueNoDisponible().message;
    for (const responsable of [{ roles: ['adoptante'] }, { roles: ['albergue', 'aliado'], albergueNombre: 'X' }]) {
      try { L.comprobarPuedeAceptar(con({ responsable })); assert.fail('no rechazó'); } catch (e) {
        assert.equal(e.code, 'failed-precondition');
        assert.equal(e.message, generico);
      }
    }
  });
});

describe('sin tope de personas por equipo', () => {
  test('la lógica ya no tiene cupo: no exporta MAX_EQUIPO ni comprobaciones de cupo', () => {
    assert.equal(L.MAX_EQUIPO, undefined);
    assert.equal(L.comprobarCupoParaInvitar, undefined);
    assert.equal(L.comprobarCupoParaAceptar, undefined);
  });
});

describe('terminar membresías, invitaciones y eliminación de cuenta', () => {
  const activa = { albergueId: 'resp', estado: 'activa' };
  test('revocar: solo una miembro activa del propio albergue, nunca a sí misma', () => {
    L.comprobarPuedeRevocar({ uid: 'resp', miembroUid: 'm', membresia: activa });
    assert.equal(codigo(() => L.comprobarPuedeRevocar({ uid: 'resp', miembroUid: 'resp', membresia: activa })), 'invalid-argument');
    assert.equal(codigo(() => L.comprobarPuedeRevocar({ uid: 'otra', miembroUid: 'm', membresia: activa })), 'not-found');
    assert.equal(codigo(() => L.comprobarPuedeRevocar({ uid: 'resp', miembroUid: 'm', membresia: { ...activa, estado: 'revocada' } })), 'not-found');
    assert.equal(codigo(() => L.comprobarPuedeRevocar({ uid: 'resp', miembroUid: 'm', membresia: null })), 'not-found');
  });
  test('salir: solo con membresía activa', () => {
    L.comprobarPuedeSalir({ membresia: activa });
    for (const m of [null, { ...activa, estado: 'salio' }, { albergueId: 'resp' }]) {
      assert.equal(codigo(() => L.comprobarPuedeSalir({ membresia: m })), 'failed-precondition');
    }
  });
  test('cancelar y rechazar: solo pendientes, y solo quien corresponde', () => {
    const inv = { albergueId: 'resp', emailDestino: 'ana@mail.com', estado: 'pendiente' };
    L.comprobarPuedeCancelar({ uid: 'resp', invitacion: inv });
    L.comprobarPuedeRechazar({ email: 'ana@mail.com', invitacion: { ...inv, emailDestino: ' Ana@Mail.com' } });
    assert.equal(codigo(() => L.comprobarPuedeCancelar({ uid: 'otra', invitacion: inv })), 'not-found');
    assert.equal(codigo(() => L.comprobarPuedeCancelar({ uid: 'resp', invitacion: { ...inv, estado: 'aceptada' } })), 'failed-precondition');
    assert.equal(codigo(() => L.comprobarPuedeRechazar({ email: 'otra@mail.com', invitacion: inv })), 'not-found');
    assert.equal(codigo(() => L.comprobarPuedeRechazar({ email: 'ana@mail.com', invitacion: { ...inv, estado: 'cancelada' } })), 'failed-precondition');
  });
  test('el contador nunca baja de cero', () => {
    assert.equal(L.restarMiembro(3), 2);
    assert.equal(L.restarMiembro(0), 0);
    assert.equal(L.restarMiembro(undefined), 0);
    assert.equal(L.restarMiembro('x'), 0);
  });
  test('eliminar cuenta: bloquea con miembros o invitaciones vigentes, sin decir nombres', () => {
    assert.equal(L.bloqueoEliminarCuenta({ miembrosActivos: 0, invitacionesVigentes: 0 }), null);
    for (const caso of [{ miembrosActivos: 1, invitacionesVigentes: 0 }, { miembrosActivos: 0, invitacionesVigentes: 2 }]) {
      const msg = L.bloqueoEliminarCuenta(caso);
      assert.match(msg, /equipo/);
      assert.doesNotMatch(msg, /\d/);
    }
  });
});
