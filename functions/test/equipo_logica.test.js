const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const L = require('../equipo_logica');

// Lógica pura del equipo del albergue. Las pruebas con Firestore (incluida
// la concurrencia) están en equipo.emulador.test.js.

const fecha = (anio, mes, dia) => ({ toMillis: () => Date.UTC(anio, mes - 1, dia) });
const revision = (extra = {}) => ({ decision: 'compartir', por: 'uid_resp', en: fecha(2026, 10, 20), ...extra });
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

describe('hogares de paso dudosos', () => {
  test('sin vida de rescatista, ningún hogar es dudoso', () => {
    assert.equal(L.hogarDudoso({ creadoEn: fecha(2026, 1, 1) }, false), false);
    assert.equal(L.hogarDudoso({}, false), false);
  });
  test('con vida de rescatista: viejo o sin fecha es dudoso, desde el 2026-07-31 no', () => {
    assert.equal(L.hogarDudoso({ creadoEn: fecha(2026, 7, 30) }, true), true);
    assert.equal(L.hogarDudoso({ creadoEn: fecha(2026, 7, 31) }, true), false);
    assert.equal(L.hogarDudoso({}, true), true);
    assert.equal(L.hogarDudoso({ creadoEn: '2026-09-01' }, true), true, 'una fecha como texto no vale');
    assert.equal(L.hogarDudoso({ creadoEn: new Date(Date.UTC(2026, 8, 1)) }, true), false);
  });
  test('revisión válida: decisión conocida, quién y cuándo', () => {
    assert.equal(L.revisionValida(revision()), true);
    assert.equal(L.revisionValida(revision({ decision: 'no_compartir' })), true);
  });
  for (const [caso, rev] of [
    ['decisión desconocida', revision({ decision: 'si' })],
    ['sin decisión', revision({ decision: undefined })],
    ['sin quién', revision({ por: '' })],
    ['quién no es texto', revision({ por: 7 })],
    ['sin cuándo', revision({ en: undefined })],
    ['cuándo como texto', revision({ en: '2026-10-20' })],
    ['una lista', ['compartir']],
    ['un texto', 'compartir'],
    ['true', true],
    ['null', null],
  ]) {
    test(`revisión mal formada no cuenta: ${caso}`, () => assert.equal(L.revisionValida(rev), false));
  }
  test('pendientes: solo los dudosos sin revisión válida', () => {
    const hogares = [
      { id: 'viejo', creadoEn: fecha(2026, 5, 1) },
      { id: 'sinFecha' },
      { id: 'nuevo', creadoEn: fecha(2026, 9, 1) },
      { id: 'revisadoSi', revisionEquipo: revision() },
      { id: 'revisadoNo', revisionEquipo: revision({ decision: 'no_compartir' }) },
      { id: 'revisadoMal', revisionEquipo: revision({ por: '' }) },
    ];
    assert.deepEqual(L.hogaresPendientesDeRevision(hogares, true), ['viejo', 'sinFecha', 'revisadoMal']);
    assert.deepEqual(L.hogaresPendientesDeRevision(hogares, false), []);
  });
  test('los mensajes de bloqueo no dicen cuántos hogares hay ni nada del historial', () => {
    const paraResponsable = L.errorHogaresPendientes();
    const paraInvitada = L.errorAlbergueNoDisponible();
    for (const e of [paraResponsable, paraInvitada]) {
      assert.equal(e.code, 'failed-precondition');
      assert.doesNotMatch(e.message, /\d/, 'sin números');
      assert.doesNotMatch(e.message, /rescatista|época|dudos/i, 'sin historial de la cuenta');
    }
    assert.doesNotMatch(paraInvitada.message, /hogar/i, 'la invitada no se entera de que es por los hogares');
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
  test('cupo: activos + vigentes nunca pasan de 10', () => {
    L.comprobarCupoParaInvitar({ miembrosActivos: 9, invitacionesVigentes: 0 });
    L.comprobarCupoParaInvitar({ miembrosActivos: 5, invitacionesVigentes: 4 });
    assert.equal(codigo(() => L.comprobarCupoParaInvitar({ miembrosActivos: 10, invitacionesVigentes: 0 })), 'resource-exhausted');
    assert.equal(codigo(() => L.comprobarCupoParaInvitar({ miembrosActivos: 7, invitacionesVigentes: 3 })), 'resource-exhausted');
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
  test('cupo al aceptar: 10 activos es el máximo', () => {
    L.comprobarCupoParaAceptar({ miembrosActivos: 9 });
    assert.equal(codigo(() => L.comprobarCupoParaAceptar({ miembrosActivos: 10 })), 'resource-exhausted');
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
  test('revisar un hogar: decisión conocida, responsable y hogar de su red', () => {
    const usuario = { roles: ['albergue'], albergueNombre: 'La Perla' };
    const hogar = { albergueId: 'resp' };
    L.comprobarPuedeRevisarHogar({ uid: 'resp', usuario, hogar, decision: 'no_compartir' });
    assert.equal(codigo(() => L.comprobarPuedeRevisarHogar({ uid: 'resp', usuario, hogar, decision: 'si' })), 'invalid-argument');
    assert.equal(codigo(() => L.comprobarPuedeRevisarHogar({ uid: 'resp', usuario: { roles: ['adoptante'] }, hogar, decision: 'compartir' })), 'permission-denied');
    assert.equal(codigo(() => L.comprobarPuedeRevisarHogar({ uid: 'otra', usuario, hogar, decision: 'compartir' })), 'not-found');
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
