const { test, describe, after } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const fsAdmin = require('firebase-admin/firestore');
const { initializeApp, deleteApp } = require('firebase-admin/app');
const D = require('../_diagnostico_equipo');

// Qué tiene que garantizar el diagnóstico previo a los equipos de albergue:
// solo lee, nunca apunta a producción por accidente, y clasifica sin adivinar
// los datos que la regla de miembro abriría (creadoPor == 'albergue').
//
// Nada de este archivo habla con Firebase de verdad: el flujo corre contra
// una base falsa en memoria, y las pruebas de destino arman el cliente real
// del SDK sin hacerle ninguna consulta (armarlo no abre conexión).

// Los métodos originales del SDK, para comprobar al final que ninguna prueba
// los dejó cambiados.
const ORIGINALES = Object.entries(D.METODOS_BLOQUEADOS).flatMap(([clase, metodos]) =>
  metodos.map((m) => [clase, m, fsAdmin[clase].prototype[m]]));

after(() => {
  for (const [clase, m, f] of ORIGINALES) {
    assert.equal(fsAdmin[clase].prototype[m], f, `${clase}.${m} quedó alterado`);
  }
});

// ─── Base falsa ──────────────────────────────────────────────────────────
//
// Solo tiene lo que el diagnóstico puede usar. Cualquier otra propiedad
// (set, update, delete, add, batch, runTransaction, bulkWriter...) lanza.
// Registra cada operación en `ops`.

function estricto(nombre, obj) {
  return new Proxy(obj, {
    get(t, p) {
      if (typeof p === 'symbol' || p === 'then') return t[p];
      if (!(p in t)) throw new Error(`operación no permitida en ${nombre}: ${p}`);
      return t[p];
    },
  });
}

// `conteosEnCero` simula que los datos crecieron entre el conteo previo y la
// lectura: count() contesta 0, así la estimación no frena nada y el tope se
// tiene que hacer cumplir durante la lectura.
function baseFalsa(colecciones, { conteosEnCero = false } = {}) {
  const ops = [];
  const proyectar = (d, campos) => {
    const out = {};
    for (const c of campos ?? Object.keys(d)) if (c !== 'id' && d[c] !== undefined) out[c] = d[c];
    return out;
  };
  const consulta = (col, filtros = [], campos = null, tope = null) => {
    const desc = () => col + filtros.map(([f, v]) => `[${f}==${v}]`).join('');
    const docs = () => (colecciones[col] ?? []).filter((d) => filtros.every(([f, v]) => d[f] === v));
    return estricto(`consulta ${col}`, {
      where(f, op, v) {
        if (op !== '==') throw new Error(`operador no esperado: ${op}`);
        return consulta(col, [...filtros, [f, v]], campos, tope);
      },
      select: (...cs) => consulta(col, filtros, cs, tope),
      limit: (n) => {
        if (!Number.isInteger(n) || n < 1) throw new Error(`limit inválido: ${n}`);
        return consulta(col, filtros, campos, n);
      },
      get: async () => {
        const lista = docs().slice(0, tope ?? Infinity);
        ops.push(`get ${desc()} select=${(campos ?? ['*']).join(',')} limit=${tope ?? '-'} -> ${lista.length}`);
        return { docs: lista.map((d) => ({ id: d.id, data: () => proyectar(d, campos) })) };
      },
      count: () => estricto('count', {
        get: async () => {
          ops.push(`count ${desc()}`);
          return { data: () => ({ count: conteosEnCero ? 0 : docs().length }) };
        },
      }),
      doc: (id) => estricto(`doc ${col}/${id}`, { id, coleccion: col }),
    });
  };
  const db = estricto('db', {
    collection: (col) => consulta(col),
    getAll: async (...args) => {
      const { fieldMask } = args.pop();
      ops.push(`getAll ${args[0].coleccion} n=${args.length} campos=${fieldMask.join(',')}`);
      return args.map((ref) => {
        const d = (colecciones[ref.coleccion] ?? []).find((x) => x.id === ref.id);
        return { id: ref.id, exists: !!d, data: () => (d ? proyectar(d, fieldMask) : undefined) };
      });
    },
  });
  return { db, ops };
}

/** Documentos leídos según el registro de la base falsa (get y getAll). */
const documentosLeidos = (ops) => ops.reduce((s, o) => {
  if (o.startsWith('get ')) return s + Number(/-> (\d+)$/.exec(o)[1]);
  if (o.startsWith('getAll ')) return s + Number(/n=(\d+)/.exec(o)[1]);
  return s;
}, 0);

/** Un Timestamp falso, con la misma forma que el del SDK (toMillis). */
const fecha = (anio, mes, dia) => ({ toMillis: () => Date.UTC(anio, mes - 1, dia) });

const vacio = () => ({ usuarios: [], servicios: [], rescates: [], chats: [], solicitudes: [], reservadas: {} });

// Un escenario con un poco de todo, para el flujo completo.
function escenario() {
  return {
    usuarios: [
      { id: 'perla', roles: ['albergue'], albergueNombre: 'La Perla' },
      { id: 'mixta', roles: ['albergue', 'aliado'], albergueNombre: 'Gatitos' },
      { id: 'vet', roles: ['aliado'], aliadoNombre: 'Vet 30' },
      { id: 'ana', roles: ['adoptante'] },
      { id: 'raro', roles: 'albergue' },
    ],
    servicios: [{ id: 's1', aliadoId: 'vet' }],
    rescates: [
      { id: 'rA', rescatistaId: 'perla', creadoPor: 'albergue' },
      { id: 'rP', rescatistaId: 'perla', creadoPor: 'rescatista' },
    ],
    chats: [
      { id: 'cOk', adoptanteId: 'ana', rescatistaId: 'perla', creadoPor: 'albergue', tipoSolicitud: 'adopcion', rescateId: 'rA' },
      { id: 'cPersonal', adoptanteId: 'ana', rescatistaId: 'perla', creadoPor: 'albergue', tipoSolicitud: 'adopcion', rescateId: 'rP' },
      { id: 'cFuga', adoptanteId: 'ana', rescatistaId: 'mixta', creadoPor: 'albergue', tipoSolicitud: 'consulta_aliado' },
      { id: 'cSinAncla', adoptanteId: 'ana', rescatistaId: 'perla', creadoPor: 'albergue' },
      { id: 'cViejo', adoptanteId: 'ana', rescatistaId: 'perla', rescateId: 'rA' },
    ],
    solicitudes: [{ id: 'sA', rescatistaId: 'perla', creadoPor: 'albergue', rescateId: 'rA' }],
    // perla tiene un animal personal (rP): sus hogares viejos o sin fecha son dudosos.
    hogaresDePaso: [
      { id: 'hViejo', albergueId: 'perla', creadoEn: fecha(2026, 5, 1), nombre: 'Familia Ruiz', telefono: '300 000 0000' },
      { id: 'hNuevo', albergueId: 'perla', creadoEn: fecha(2026, 9, 1) },
      { id: 'hSinFecha', albergueId: 'perla' },
      { id: 'hLatente', albergueId: 'ana', creadoEn: fecha(2026, 3, 1) },
    ],
    membresias: [], invitaciones: [], equipos: [],
  };
}

const opcionesEmulador = (extra = {}) => ({ ...D.parsearArgs(['--emulador']), ...extra });
const sinConfirmar = async () => { throw new Error('no debería pedir confirmación'); };

// ─── Argumentos ──────────────────────────────────────────────────────────

describe('parsearArgs', () => {
  for (const [caso, argv, error] of [
    ['sin modo', [], /exactamente uno/],
    ['los dos modos', ['--emulador', '--produccion'], /exactamente uno/],
    ['modo mal escrito', ['--produccio'], /desconocido/],
    ['argumento desconocido', ['--emulador', '--aplicar'], /desconocido: --aplicar/],
    ['argumento repetido', ['--emulador', '--emulador'], /repetido/],
    ['producción sin proyecto', ['--produccion'], /--proyecto=patitas-dd0bb/],
    ['producción con otro proyecto', ['--produccion', '--proyecto=otro'], /tiene que ser patitas-dd0bb/],
    ['emulador con otro proyecto', ['--emulador', '--proyecto=otro'], /tiene que ser patitas-dd0bb/],
    ['fase inválida', ['--emulador', '--fase=todo'], /bloqueantes o completa/],
    ['tope inválido', ['--emulador', '--max-documentos=0'], /entero positivo/],
    ['tope no numérico', ['--emulador', '--max-documentos=10k'], /entero positivo/],
  ]) {
    test(`rechaza: ${caso}`, () => assert.throws(() => D.parsearArgs(argv), error));
  }

  test('acepta emulador con valores por defecto', () => {
    assert.deepEqual(D.parsearArgs(['--emulador']),
      { modo: 'emulador', fase: 'bloqueantes', mostrarIds: false, proyecto: null, maxDocumentos: 20000 });
  });

  test('acepta producción completa con todas las opciones', () => {
    const op = D.parsearArgs(['--produccion', '--proyecto=patitas-dd0bb', '--fase=completa', '--max-documentos=500', '--mostrar-ids']);
    assert.deepEqual(op, { modo: 'produccion', fase: 'completa', mostrarIds: true, proyecto: 'patitas-dd0bb', maxDocumentos: 500 });
  });
});

// ─── Destino ─────────────────────────────────────────────────────────────

describe('destino: con datos de configuración armados a mano', () => {
  const ok = { servicePath: '127.0.0.1', port: 8097, ssl: false };
  const db = (s, projectId = 'patitas-dd0bb') => ({ _settings: s, _projectId: projectId });
  const envEmu = { FIRESTORE_EMULATOR_HOST: '127.0.0.1:8097' };

  test('emulador local: pasa', () => D.verificarDestino('emulador', db(ok), envEmu));
  test('emulador: host de producción, aborta', () =>
    assert.throws(() => D.verificarDestino('emulador', db({}), envEmu), /no apunta al emulador local/));
  test('emulador: otro host, aborta', () =>
    assert.throws(() => D.verificarDestino('emulador', db({ ...ok, servicePath: '10.0.0.5' }), envEmu), /no apunta/));
  test('emulador: otro puerto, aborta', () =>
    assert.throws(() => D.verificarDestino('emulador', db({ ...ok, port: 8080 }), envEmu), /no apunta/));
  test('emulador: variable distinta, aborta', () =>
    assert.throws(() => D.verificarDestino('emulador', db(ok), { FIRESTORE_EMULATOR_HOST: '' }), /no es el emulador/));
  test('sin configuración legible, aborta (no se puede demostrar)', () =>
    assert.throws(() => D.verificarDestino('emulador', {}, envEmu), /no se puede demostrar/));
  test('otro proyecto, aborta', () =>
    assert.throws(() => D.verificarDestino('emulador', db(ok, 'otro'), envEmu), /proyecto "otro"/));
  test('producción con la variable del emulador todavía puesta, aborta', () =>
    assert.throws(() => D.verificarDestino('produccion', db({}), envEmu), /no puede quedar/));
  test('producción con host raro, aborta', () =>
    assert.throws(() => D.verificarDestino('produccion', db({ servicePath: 'evil.example' }), {}), /host inesperado/));
  test('producción normal: pasa', () => D.verificarDestino('produccion', db({}), {}));
});

describe('destino: con el cliente real del SDK (sin hacer consultas)', () => {
  let n = 0;
  // Arma el cliente como correr(), con la variable del entorno dada, y corre
  // verificarDestino ahí mismo (lee el entorno, así que tiene que ser antes
  // de restaurarlo). Devuelve una función que relanza su resultado.
  async function armar({ modo, variable, preparar }) {
    const antes = process.env.FIRESTORE_EMULATOR_HOST;
    if (variable === undefined) delete process.env.FIRESTORE_EMULATOR_HOST;
    else process.env.FIRESTORE_EMULATOR_HOST = variable;
    const app = initializeApp({ projectId: D.PROYECTO }, `destino-${++n}`);
    try {
      if (preparar) D.prepararEntorno(modo, process.env);
      const db = fsAdmin.getFirestore(app);
      let error = null;
      try {
        D.verificarDestino(modo, db, process.env);
      } catch (e) {
        error = e;
      }
      const verificar = () => { if (error) throw error; };
      verificar.servicePath = db._settings.servicePath;
      return verificar;
    } finally {
      await deleteApp(app);
      if (antes === undefined) delete process.env.FIRESTORE_EMULATOR_HOST;
      else process.env.FIRESTORE_EMULATOR_HOST = antes;
    }
  }

  test('EL BUG: variable vacía sin prepararEntorno apunta a producción y se detecta', async () => {
    const verificar = await armar({ modo: 'emulador', variable: '', preparar: false });
    // Sin corrección, el SDK deja el host por defecto: firestore.googleapis.com.
    assert.equal(verificar.servicePath, undefined);
    assert.throws(verificar);
  });
  for (const variable of [undefined, '', '10.0.0.5:8080', 'localhost:9999']) {
    test(`emulador con variable ${JSON.stringify(variable)}: prepararEntorno la corrige y se demuestra local`, async () => {
      const verificar = await armar({ modo: 'emulador', variable, preparar: true });
      assert.equal(verificar.servicePath, '127.0.0.1');
      verificar();
    });
  }
  test('otro host sin prepararEntorno: se detecta', async () => {
    const verificar = await armar({ modo: 'emulador', variable: '10.0.0.5:8080', preparar: false });
    assert.throws(verificar, /no es el emulador/);
  });
  test('producción: prepararEntorno quita la variable y apunta al proyecto correcto', async () => {
    const verificar = await armar({ modo: 'produccion', variable: '127.0.0.1:8097', preparar: true });
    verificar();
  });
});

describe('credenciales', () => {
  test('GOOGLE_APPLICATION_CREDENTIALS: muestra solo el nombre del archivo', () => {
    const t = D.describirCredenciales({ GOOGLE_APPLICATION_CREDENTIALS: '/ruta/secreta/clave.json' }, () => false);
    assert.match(t, /clave\.json/);
    assert.doesNotMatch(t, /secreta/);
  });
  test('gcloud', () => assert.match(D.describirCredenciales({}, () => true), /gcloud/));
  test('ninguna', () => assert.match(D.describirCredenciales({}, () => false), /ninguna/));
});

// ─── Solo lectura ────────────────────────────────────────────────────────

describe('solo lectura', () => {
  test('el código del diagnóstico no contiene llamadas de escritura', () => {
    const fuente = readFileSync(join(__dirname, '..', '_diagnostico_equipo.js'), 'utf8')
        .replace(/\/\*[\s\S]*?\*\//g, '')
        .split('\n').map((l) => l.replace(/\/\/.*$/, '')).join('\n');
    const escritura = /\.(set|update|delete|create|add|commit|batch|runTransaction|bulkWriter|recursiveDelete|request|requestStream)\s*\(|\bBulkWriter\b|\bfetch\s*\(|getAuth|getStorage|getDatabase/;
    // El patrón tiene que reconocer una escritura real, si no la prueba no prueba nada.
    assert.match("db.collection('x').doc('y').set({})", escritura);
    assert.doesNotMatch(fuente, escritura);
  });

  test('cargar el módulo no altera el SDK', () => {
    for (const [clase, m, f] of ORIGINALES) assert.equal(fsAdmin[clase].prototype[m], f);
  });

  test('soloLectura bloquea los métodos públicos de escritura y se puede deshacer', () => {
    try {
      D.soloLectura(fsAdmin);
      for (const [clase, m] of ORIGINALES) {
        assert.throws(() => fsAdmin[clase].prototype[m].call({}), /solo lectura/, `${clase}.${m}`);
      }
    } finally {
      for (const [clase, m, f] of ORIGINALES) fsAdmin[clase].prototype[m] = f;
    }
  });

  test('límite documentado: soloLectura NO bloquea las vías internas', () => {
    // No es una garantía universal, y esta prueba deja constancia de eso.
    try {
      D.soloLectura(fsAdmin);
      assert.equal(typeof fsAdmin.WriteBatch.prototype._commit, 'function');
      assert.equal(typeof fsAdmin.Firestore.prototype.request, 'function');
      assert.equal(typeof fsAdmin.BulkWriter, 'function');
    } finally {
      for (const [clase, m, f] of ORIGINALES) fsAdmin[clase].prototype[m] = f;
    }
  });

  test('la base falsa falla ante escrituras (si no, las pruebas de flujo no probarían nada)', () => {
    const { db } = baseFalsa({});
    assert.throws(() => db.batch(), /no permitida/);
    assert.throws(() => db.runTransaction(), /no permitida/);
    assert.throws(() => db.bulkWriter(), /no permitida/);
    assert.throws(() => db.collection('x').add({}), /no permitida/);
    assert.throws(() => db.collection('x').doc('y').set({}), /no permitida/);
    assert.throws(() => db.collection('x').doc('y').delete(), /no permitida/);
  });

  for (const fase of ['bloqueantes', 'completa']) {
    test(`flujo completo (${fase}): solo lecturas, y solo los campos declarados`, async () => {
      const { db, ops } = baseFalsa(escenario());
      await D.ejecutarDiagnostico({ db, opciones: opcionesEmulador({ fase }), imprimir: () => {}, confirmar: sinConfirmar });
      assert.ok(ops.length > 0);
      for (const op of ops) assert.match(op, /^(get|count|getAll) /, op);
      for (const op of ops.filter((o) => o.startsWith('get '))) assert.doesNotMatch(op, /select=\*/, `lectura sin select: ${op}`);
    });
  }

  test('fase bloqueantes: lee solo lo filtrado, no las colecciones grandes enteras', async () => {
    const { db, ops } = baseFalsa(escenario());
    await D.ejecutarDiagnostico({ db, opciones: opcionesEmulador(), imprimir: () => {}, confirmar: sinConfirmar });
    const gets = ops.filter((o) => o.startsWith('get '));
    for (const col of ['chats', 'solicitudes', 'rescates']) {
      for (const g of gets.filter((o) => o.startsWith(`get ${col}`))) assert.match(g, /\[/, `lectura completa de ${col}: ${g}`);
    }
  });
});

// ─── Flujo: tope, confirmación y --mostrar-ids ──────────────────────────

describe('flujo', () => {
  test('--mostrar-ids hace exactamente las mismas operaciones y solo cambia el texto', async () => {
    const correr = async (mostrarIds) => {
      const { db, ops } = baseFalsa(escenario());
      const salida = [];
      await D.ejecutarDiagnostico({ db, opciones: opcionesEmulador({ mostrarIds }), imprimir: (t) => salida.push(t), confirmar: sinConfirmar });
      return { ops, texto: salida.join('\n') };
    };
    const sin = await correr(false);
    const con = await correr(true);
    assert.deepEqual(con.ops, sin.ops);
    assert.notEqual(con.texto, sin.texto);
    assert.match(con.texto, /cFuga/);
    for (const real of ['cFuga', 'mixta', 'perla', 'raro', 'cPersonal', 'cSinAncla', 'hViejo', 'hSinFecha']) {
      assert.ok(!sin.texto.includes(real), `el informe por defecto muestra el id real ${real}`);
    }
  });

  test('si la estimación supera el tope, aborta tras los conteos sin leer documentos', async () => {
    const { db, ops } = baseFalsa(escenario());
    await assert.rejects(
      D.ejecutarDiagnostico({ db, opciones: opcionesEmulador({ maxDocumentos: 3 }), imprimir: () => {}, confirmar: sinConfirmar }),
      /supera --max-documentos=3/);
    assert.ok(ops.every((o) => o.startsWith('count ')), ops.join('\n'));
  });

  test('en el emulador nunca se pide confirmación', async () => {
    // sinConfirmar lanza si se la llama: el flujo entero tiene que terminar igual.
    const { db } = baseFalsa(escenario());
    await D.ejecutarDiagnostico({ db, opciones: opcionesEmulador(), imprimir: () => {}, confirmar: sinConfirmar });
  });

  test('las dos fases encuentran los mismos bloqueantes y casos a revisar', async () => {
    const r = {};
    for (const fase of ['bloqueantes', 'completa']) {
      const { db } = baseFalsa(escenario());
      r[fase] = await D.ejecutarDiagnostico({ db, opciones: opcionesEmulador({ fase }), imprimir: () => {}, confirmar: sinConfirmar });
    }
    assert.deepEqual(r.bloqueantes.bloqueantes, r.completa.bloqueantes);
    assert.deepEqual(r.bloqueantes.revision, r.completa.revision);
    assert.deepEqual(r.bloqueantes.huerfanos, r.completa.huerfanos);
    assert.equal(r.bloqueantes.estado, r.completa.estado);
  });

  test('el conteo previo estima por arriba todo lo que después se lee', async () => {
    for (const fase of ['bloqueantes', 'completa']) {
      const { db, ops } = baseFalsa(escenario());
      const salida = [];
      await D.ejecutarDiagnostico({ db, opciones: opcionesEmulador({ fase }), imprimir: (t) => salida.push(t), confirmar: sinConfirmar });
      const estimadas = Number(/hasta (\d+) lecturas/.exec(salida[0])[1]);
      const leidas = documentosLeidos(ops);
      assert.ok(leidas > 0);
      assert.ok(estimadas >= leidas, `${fase}: estimó ${estimadas}, leyó ${leidas}`);
    }
  });
});

// ─── Producción: dos confirmaciones ─────────────────────────────────────
//
// Ninguna de estas pruebas toca producción: el modo 'produccion' corre
// contra la base falsa. Lo que se prueba es el ORDEN: aviso, primera
// confirmación, conteos, estimación, segunda confirmación, lectura.

describe('producción: dos confirmaciones', () => {
  const opcionesProd = (extra = {}) => ({ ...D.parsearArgs(['--produccion', '--proyecto=patitas-dd0bb']), ...extra });

  // Arma un intento con un registro común de todo lo que pasa, en orden:
  // lo impreso, cada pregunta (con cuántas consultas había hecho la base en
  // ese momento) y las consultas mismas.
  function intento(respuestas, extra) {
    const { db, ops } = baseFalsa(escenario());
    const registro = [];
    const preguntas = [];
    const confirmar = async (texto, frase) => {
      preguntas.push({ texto, frase, consultasAntes: ops.length, soloConteos: ops.every((o) => o.startsWith('count ')) });
      registro.push(`pregunta ${frase}`);
      return respuestas[preguntas.length - 1] ?? false;
    };
    const imprimir = (t) => registro.push(`imprime ${t}`);
    const correr = () => D.ejecutarDiagnostico({ db, opciones: opcionesProd(extra), imprimir, confirmar });
    return { ops, registro, preguntas, correr };
  }

  test('cancelar en la primera confirmación: cero consultas', async () => {
    const t = intento([false]);
    await assert.rejects(t.correr(), /No se hizo ninguna consulta/);
    assert.deepEqual(t.ops, []);
    assert.equal(t.preguntas.length, 1);
    assert.equal(t.preguntas[0].frase, 'CONTAR patitas-dd0bb');
  });

  test('la primera pregunta llega antes de cualquier consulta, con el aviso ya mostrado', async () => {
    const t = intento([true, true]);
    await t.correr();
    assert.equal(t.preguntas[0].consultasAntes, 0);
    const iPregunta = t.registro.indexOf('pregunta CONTAR patitas-dd0bb');
    const aviso = t.registro.slice(0, iPregunta).join('\n');
    assert.match(aviso, /PRODUCCIÓN: proyecto patitas-dd0bb/);
    assert.match(aviso, /No se escribe nada/);
    assert.match(aviso, /conteos también generan lecturas/);
    assert.match(aviso, /segunda confirmación \("LEER patitas-dd0bb"\)/);
    for (const c of D.consultasDe('bloqueantes')) assert.match(aviso, new RegExp(`· ${c.coleccion}`));
    for (const n of ['membresias', 'invitaciones', 'equipos']) assert.match(aviso, new RegExp(`· ${n}`));
  });

  test('el aviso describe la fase elegida', () => {
    assert.match(D.avisoDeAcceso('bloqueantes'), /chats donde creadoPor == 'albergue'/);
    assert.match(D.avisoDeAcceso('completa'), /chats \(completa\)/);
  });

  test('aceptar la primera y cancelar la segunda: solo conteos, ningún documento', async () => {
    const t = intento([true, false]);
    await assert.rejects(t.correr(), /No se leyó ningún documento/);
    assert.ok(t.ops.length > 0);
    assert.ok(t.ops.every((o) => o.startsWith('count ')), t.ops.join('\n'));
    assert.equal(t.preguntas[1].frase, 'LEER patitas-dd0bb');
    // La estimación se mostró antes de la segunda pregunta.
    const iEstimacion = t.registro.findIndex((r) => r.startsWith('imprime Estimación'));
    assert.ok(iEstimacion > -1 && iEstimacion < t.registro.indexOf('pregunta LEER patitas-dd0bb'));
  });

  test('con las dos aceptadas: cuenta, pregunta otra vez, lee y analiza', async () => {
    const t = intento([true, true]);
    const r = await t.correr();
    assert.deepEqual(t.preguntas.map((p) => p.frase), ['CONTAR patitas-dd0bb', 'LEER patitas-dd0bb']);
    assert.equal(t.preguntas[1].soloConteos, true, 'antes de la segunda pregunta solo hubo conteos');
    assert.ok(t.ops.some((o) => o.startsWith('get ')));
    assert.equal(r.estado, 'BLOQUEADO');
  });

  test('tope superado: aborta después de los conteos y ya no pregunta por segunda vez', async () => {
    const t = intento([true, true], { maxDocumentos: 3 });
    await assert.rejects(t.correr(), /supera --max-documentos=3/);
    assert.equal(t.preguntas.length, 1);
    assert.ok(t.ops.every((o) => o.startsWith('count ')));
  });

  describe('confirmarEnTerminal', () => {
    const { PassThrough } = require('node:stream');
    // Una terminal falsa: stdin y stdout marcados como interactivos.
    async function responder(texto, frase) {
      const stdin = new PassThrough();
      const stdout = new PassThrough();
      stdin.isTTY = true;
      stdout.isTTY = true;
      const respuesta = D.confirmarEnTerminal('¿? ', frase, { stdin, stdout });
      stdin.end(texto + '\n');
      return respuesta;
    }

    test('sin terminal interactiva se niega, sin preguntar', async () => {
      for (const io of [
        { stdin: { isTTY: false }, stdout: { isTTY: true } },
        { stdin: { isTTY: true }, stdout: { isTTY: false } },
        { stdin: {}, stdout: {} },
      ]) {
        assert.equal(await D.confirmarEnTerminal('?', D.FRASE_CONTAR, io), false);
      }
    });
    test('la frase exacta confirma (se toleran espacios alrededor)', async () => {
      assert.equal(await responder('CONTAR patitas-dd0bb', D.FRASE_CONTAR), true);
      assert.equal(await responder('  LEER patitas-dd0bb  ', D.FRASE_LEER), true);
    });
    for (const mal of ['contar patitas-dd0bb', 'CONTAR', 'si', '', 'LEER patitas-dd0bb']) {
      test(`"${mal}" no confirma CONTAR`, async () => {
        assert.equal(await responder(mal, D.FRASE_CONTAR), false);
      });
    }
    test('la frase de contar no sirve para leer', async () => {
      assert.equal(await responder('CONTAR patitas-dd0bb', D.FRASE_LEER), false);
    });
  });
});

// ─── Clasificación ───────────────────────────────────────────────────────

describe('A1: dueña y aliada', () => {
  const a1 = (d) => D.analizar(d).bloqueantes.duenaYAliada.map((h) => h.id);

  test('por roles', () => {
    const d = vacio();
    d.usuarios = [{ id: 'x', roles: ['albergue', 'aliado'] }];
    assert.deepEqual(a1(d), ['x']);
  });
  test('por animales viejos y servicio, sin ninguno de los dos roles', () => {
    const d = vacio();
    d.usuarios = [{ id: 'x', roles: ['adoptante'] }];
    d.rescates = [{ id: 'r', rescatistaId: 'x', creadoPor: 'albergue' }];
    d.servicios = [{ id: 's', aliadoId: 'x' }];
    assert.deepEqual(a1(d), ['x']);
  });
  test('por nombre de albergue y por haber recibido consultas de aliado', () => {
    const d = vacio();
    d.usuarios = [{ id: 'x', albergueNombre: 'Refugio' }];
    d.chats = [{ id: 'c', adoptanteId: 'ana', rescatistaId: 'x', tipoSolicitud: 'consulta_aliado' }];
    assert.deepEqual(a1(d), ['x']);
  });
  test('cuenta sin documento de perfil pero con animales y servicio', () => {
    const d = vacio();
    d.rescates = [{ id: 'r', rescatistaId: 'fantasma', creadoPor: 'albergue' }];
    d.servicios = [{ id: 's', aliadoId: 'fantasma' }];
    assert.deepEqual(a1(d), ['fantasma']);
  });
  test('nombres vacíos, null o ausentes no son señal', () => {
    const d = vacio();
    d.usuarios = [
      { id: 'a', roles: ['albergue'], aliadoNombre: '' },
      { id: 'b', roles: ['albergue'], aliadoNombre: '   ' },
      { id: 'c', roles: ['aliado'], albergueNombre: null },
      { id: 'e', roles: ['aliado'] },
    ];
    assert.deepEqual(a1(d), []);
    assert.equal(D.analizar(d).estado, 'APLICABLE');
  });
  test('la consulta que una dueña MANDA no la vuelve aliada', () => {
    const d = vacio();
    d.usuarios = [{ id: 'perla', roles: ['albergue'] }, { id: 'vet', roles: ['aliado'] }];
    d.chats = [{ id: 'c', adoptanteId: 'perla', rescatistaId: 'vet', creadoPor: 'albergue', tipoSolicitud: 'consulta_aliado' }];
    const r = D.analizar(d);
    assert.deepEqual(r.bloqueantes.duenaYAliada, []);
    assert.deepEqual(r.bloqueantes.consultasRecibidasPorDuena, []);
    assert.equal(r.estado, 'APLICABLE');
  });
});

describe('R1: valores inesperados en usuarios (no se descartan en silencio)', () => {
  for (const [caso, u, motivo] of [
    ['roles como texto', { roles: 'albergue' }, /no es una lista \(texto\)/],
    ['roles null', { roles: null }, /no es una lista \(null\)/],
    ['rol desconocido', { roles: ['Albergue'] }, /valor desconocido/],
    ['nombre de albergue no texto', { albergueNombre: 7 }, /albergueNombre no es texto/],
    ['nombre de negocio no texto', { aliadoNombre: { a: 1 } }, /aliadoNombre no es texto/],
  ]) {
    test(caso, () => {
      const d = vacio();
      d.usuarios = [{ id: 'u', ...u }];
      const r = D.analizar(d);
      assert.match(r.revision.valoresInesperados[0].motivo, motivo);
      assert.equal(r.estado, 'REQUIERE REVISIÓN MANUAL');
    });
  }
});

describe('A2 y chats que el equipo vería (creadoPor albergue)', () => {
  const base = () => {
    const d = vacio();
    d.usuarios = [{ id: 'perla', roles: ['albergue'] }, { id: 'otra', roles: ['albergue'] }];
    d.rescates = [
      { id: 'rA', rescatistaId: 'perla', creadoPor: 'albergue' },
      { id: 'rP', rescatistaId: 'perla', creadoPor: 'rescatista' },
      { id: 'rOtra', rescatistaId: 'otra', creadoPor: 'albergue' },
    ];
    d.solicitudes = [
      { id: 'sA', rescatistaId: 'perla', creadoPor: 'albergue', rescateId: 'rA' },
      { id: 'sP', rescatistaId: 'perla', creadoPor: 'rescatista', rescateId: 'rP' },
    ];
    return d;
  };
  const chat = (campos) => ({ id: 'c', adoptanteId: 'ana', rescatistaId: 'perla', creadoPor: 'albergue', ...campos });
  const con = (c) => { const d = base(); d.chats = [chat(c)]; return D.analizar(d); };

  test('consulta_aliado recibida por una dueña: bloqueante', () => {
    const r = con({ tipoSolicitud: 'consulta_aliado' });
    assert.deepEqual(r.bloqueantes.consultasRecibidasPorDuena.map((h) => h.id), ['c']);
    assert.equal(r.estado, 'BLOQUEADO');
  });
  test('consulta_aliado recibida por quien no es dueña: latente, informativo', () => {
    const d = base();
    d.chats = [chat({ rescatistaId: 'vet', tipoSolicitud: 'consulta_aliado' })];
    const r = D.analizar(d);
    assert.deepEqual(r.informativo.consultasLatentes.map((h) => h.id), ['c']);
    assert.deepEqual(r.bloqueantes.consultasRecibidasPorDuena, []);
  });
  test('consulta_aliado SIN creadoPor (de un adoptante): el equipo no la vería, no se lista', () => {
    const d = base();
    d.chats = [{ id: 'c', adoptanteId: 'ana', rescatistaId: 'perla', tipoSolicitud: 'consulta_aliado' }];
    const r = D.analizar(d);
    assert.deepEqual(r.bloqueantes.consultasRecibidasPorDuena, []);
    // ...pero sí delata que perla recibe consultas de aliado: A1.
    assert.deepEqual(r.bloqueantes.duenaYAliada.map((h) => h.id), ['perla']);
  });
  test('animal del albergue: demostrable, no se lista', () => {
    const r = con({ tipoSolicitud: 'adopcion', rescateId: 'rA' });
    assert.equal(r.estado, 'APLICABLE');
  });
  test('chat de pregunta (tipo consulta) sobre un animal del albergue: demostrable', () => {
    assert.equal(con({ tipoSolicitud: 'consulta', rescateId: 'rA' }).estado, 'APLICABLE');
  });
  test('sin animal pero con solicitud del albergue: demostrable', () => {
    assert.equal(con({ solicitudId: 'sA' }).estado, 'APLICABLE');
  });
  test('animal personal del mismo dueño: incoherente', () => {
    const r = con({ tipoSolicitud: 'adopcion', rescateId: 'rP' });
    assert.match(r.revision.chatsIncoherentes[0].motivo, /animal es personal/);
    assert.equal(r.estado, 'REQUIERE REVISIÓN MANUAL');
  });
  test('animal de otra cuenta: incoherente', () => {
    assert.match(con({ rescateId: 'rOtra' }).revision.chatsIncoherentes[0].motivo, /otra cuenta/);
  });
  test('solicitud personal: incoherente', () => {
    assert.match(con({ solicitudId: 'sP' }).revision.chatsIncoherentes[0].motivo, /solicitud no es de este albergue/);
  });
  test('animal borrado: huérfano, separado de los incoherentes, no bloquea', () => {
    const r = con({ tipoSolicitud: 'adopcion', rescateId: 'borrado' });
    assert.equal(r.huerfanos.chats.length, 1);
    assert.equal(r.revision.chatsIncoherentes.length, 0);
    assert.equal(r.estado, 'APLICABLE');
  });
  test('solicitud borrada: huérfano', () => {
    assert.equal(con({ solicitudId: 'borrada' }).huerfanos.chats.length, 1);
  });
  for (const [caso, tipo, texto] of [
    ['sin tipoSolicitud', undefined, /tipoSolicitud ausente/],
    ["con tipoSolicitud 'consulta'", 'consulta', /tipoSolicitud 'consulta'/],
    ['con tipoSolicitud inesperado', 'Consulta Aliado!!', /tipoSolicitud inesperado/],
    ['con tipoSolicitud vacío', '', /tipoSolicitud vacio/],
    ['con tipoSolicitud de otro tipo de dato', 3, /tipoSolicitud otro/],
  ]) {
    test(`sin animal ni solicitud, ${caso}: indeterminado, nunca se adivina que es de aliado`, () => {
      const r = con({ tipoSolicitud: tipo });
      assert.equal(r.revision.chatsIndeterminados.length, 1);
      assert.match(r.revision.chatsIndeterminados[0].motivo, texto);
      assert.deepEqual(r.bloqueantes.consultasRecibidasPorDuena, []);
      assert.equal(r.estado, 'REQUIERE REVISIÓN MANUAL');
    });
  }
  test('el informe no muestra el valor real de un tipo inesperado', () => {
    const texto = D.formatear(con({ tipoSolicitud: 'texto libre raro' }));
    assert.ok(!texto.includes('texto libre raro'));
  });
});

describe('solicitudes que el equipo vería (creadoPor albergue)', () => {
  const con = (s) => {
    const d = vacio();
    d.rescates = [
      { id: 'rA', rescatistaId: 'perla', creadoPor: 'albergue' },
      { id: 'rP', rescatistaId: 'perla', creadoPor: 'rescatista' },
    ];
    d.solicitudes = [{ id: 's', rescatistaId: 'perla', creadoPor: 'albergue', ...s }];
    return D.analizar(d);
  };
  test('coherente', () => assert.equal(con({ rescateId: 'rA' }).estado, 'APLICABLE'));
  test('animal personal: incoherente', () => assert.equal(con({ rescateId: 'rP' }).revision.solicitudesIncoherentes.length, 1));
  test('animal borrado: huérfana', () => assert.equal(con({ rescateId: 'x' }).huerfanos.solicitudes.length, 1));
  test('sin rescateId: indeterminada', () => {
    const r = con({});
    assert.equal(r.revision.solicitudesIndeterminadas.length, 1);
    assert.equal(r.estado, 'REQUIERE REVISIÓN MANUAL');
  });
});

describe('A3 y A4', () => {
  test('colecciones nuevas con datos: bloqueante, con el número', () => {
    const d = vacio();
    d.reservadas = { membresias: 0, invitaciones: 2, equipos: 0 };
    const r = D.analizar(d);
    assert.deepEqual(r.bloqueantes.reservadasConDatos, [{ id: 'invitaciones', motivo: '2 documentos' }]);
    assert.equal(r.estado, 'BLOQUEADO');
  });
  test('trabajaEn con texto: bloqueante', () => {
    const d = vacio();
    d.usuarios = [{ id: 'u', trabajaEn: 'perla' }];
    assert.equal(D.analizar(d).bloqueantes.trabajaEnEnUso.length, 1);
  });
  for (const v of [null, '', '  ']) {
    test(`trabajaEn ${JSON.stringify(v)}: informativo, listado, no bloquea`, () => {
      const d = vacio();
      d.usuarios = [{ id: 'u', trabajaEn: v }];
      const r = D.analizar(d);
      assert.equal(r.informativo.trabajaEnVacio.length, 1);
      assert.equal(r.estado, 'APLICABLE');
    });
  }
  test('trabajaEn de otro tipo: revisión', () => {
    const d = vacio();
    d.usuarios = [{ id: 'u', trabajaEn: 5 }];
    assert.equal(D.analizar(d).estado, 'REQUIERE REVISIÓN MANUAL');
  });
});

describe('datos sin creadoPor (solo en fase completa)', () => {
  const datos = () => {
    const d = vacio();
    d.rescates = [{ id: 'rA', rescatistaId: 'perla', creadoPor: 'albergue' }, { id: 'rP', rescatistaId: 'perla', creadoPor: 'rescatista' }];
    d.chats = [
      { id: 'cA', rescatistaId: 'perla', rescateId: 'rA' },
      { id: 'cNull', rescatistaId: 'perla', rescateId: 'rA', creadoPor: null },
      { id: 'cP', rescatistaId: 'perla', rescateId: 'rP' },
      { id: 'cOtro', rescatistaId: 'otra', rescateId: 'rA' },
      { id: 'cRaro', rescatistaId: 'perla', rescateId: 'rA', creadoPor: 'Albergue' },
    ];
    d.solicitudes = [{ id: 'sA', rescatistaId: 'perla', rescateId: 'rA' }];
    return d;
  };
  test('solo cuentan si el animal es del albergue y del mismo dueño', () => {
    const r = D.analizar(datos());
    assert.deepEqual(r.informativo.invisiblesAlEquipo.chats.map((h) => h.id), ['cA', 'cNull']);
    assert.deepEqual(r.informativo.invisiblesAlEquipo.solicitudes.map((h) => h.id), ['sA']);
    assert.deepEqual(r.informativo.creadoPorInesperado.map((h) => h.id), ['cRaro']);
    assert.equal(r.estado, 'APLICABLE', 'no son bloqueantes ni a revisar: el equipo no los ve');
  });
  test('en fase bloqueantes no se evalúan, y el informe lo dice', () => {
    const r = D.analizar({ ...datos(), fase: 'bloqueantes' });
    assert.deepEqual(r.informativo.invisiblesAlEquipo.chats, []);
    assert.match(D.formatear(r), /no evaluados en fase bloqueantes/);
  });
  test('I7 cuenta chats sin tipo, con consulta y con tipo inesperado', () => {
    const d = vacio();
    d.chats = [
      { id: '1', creadoPor: 'albergue' }, { id: '2', creadoPor: 'rescatista' }, { id: '3' },
      { id: '4', tipoSolicitud: 'consulta' }, { id: '5', tipoSolicitud: 'raro' }, { id: '6', tipoSolicitud: 'adopcion' },
    ];
    assert.deepEqual(D.analizar(d).informativo.chatsSinTipo,
      { total: 3, albergue: 1, rescatista: 1, sinCampo: 1, otro: 0, consulta: 1, inesperado: 1 });
  });
});

describe('resultado', () => {
  test('base vacía: APLICABLE', () => {
    const r = D.analizar(vacio());
    assert.equal(r.estado, 'APLICABLE');
    assert.equal(r.opcionBAplicable, true);
  });
  test('bloqueante y revisión a la vez: gana BLOQUEADO', () => {
    const d = vacio();
    d.usuarios = [{ id: 'x', roles: ['albergue', 'aliado'] }, { id: 'y', roles: 'raro' }];
    const r = D.analizar(d);
    assert.equal(r.estado, 'BLOQUEADO');
    assert.equal(r.opcionBAplicable, false);
  });
  test('solo revisión: REQUIERE REVISIÓN MANUAL y opcionBAplicable falso', () => {
    const d = vacio();
    d.usuarios = [{ id: 'y', roles: 'raro' }];
    const r = D.analizar(d);
    assert.equal(r.estado, 'REQUIERE REVISIÓN MANUAL');
    assert.equal(r.opcionBAplicable, false);
  });
  test('huérfanos e informativos no cambian APLICABLE', () => {
    const d = vacio();
    d.usuarios = [{ id: 'u', trabajaEn: null }];
    d.chats = [{ id: 'c', rescatistaId: 'p', creadoPor: 'albergue', rescateId: 'borrado' }];
    assert.equal(D.analizar(d).estado, 'APLICABLE');
  });
  test('el informe usa seudónimos por defecto', () => {
    const d = vacio();
    d.usuarios = [{ id: 'UID_REAL_123', roles: ['albergue', 'aliado'] }];
    const texto = D.formatear(D.analizar(d));
    assert.ok(!texto.includes('UID_REAL_123'));
    assert.ok(texto.includes(D.seudonimo('UID_REAL_123')));
  });
});

// ─── Hogares de paso ─────────────────────────────────────────────────────
//
// El equipo vería toda la red de hogares de paso de la responsable. La
// colección no tiene campo de contexto y, hasta el 2026-07-31, una cuenta
// sin el rol de albergue también podía crear ahí.

describe('hogares de paso', () => {
  const base = () => {
    const d = vacio();
    d.usuarios = [
      { id: 'pura', roles: ['albergue'] },               // nunca fue rescatista
      { id: 'mixta', roles: ['albergue', 'rescatista'] }, // rescatista por rol
      { id: 'exResc', roles: ['albergue'] },             // rescatista por historial
      { id: 'ana', roles: ['adoptante'] },
    ];
    d.historialRescatista = ['exResc'];
    return d;
  };
  const r6 = (d) => D.analizar(d).revision.hogaresDudosos.map((h) => h.id).sort();

  test('responsable que nunca fue rescatista: ningún hogar es dudoso, aunque sea viejo o sin fecha', () => {
    const d = base();
    d.hogaresDePaso = [{ id: 'h1', albergueId: 'pura', creadoEn: fecha(2026, 1, 1) }, { id: 'h2', albergueId: 'pura' }];
    assert.deepEqual(r6(d), []);
    assert.equal(D.analizar(d).informativo.hogaresCompartidos, 2);
    assert.equal(D.analizar(d).estado, 'APLICABLE');
  });
  test('responsable con rol de rescatista: viejos y sin fecha son dudosos, los nuevos no', () => {
    const d = base();
    d.hogaresDePaso = [
      { id: 'viejo', albergueId: 'mixta', creadoEn: fecha(2026, 7, 30) },
      { id: 'justo', albergueId: 'mixta', creadoEn: fecha(2026, 7, 31) },
      { id: 'nuevo', albergueId: 'mixta', creadoEn: fecha(2026, 10, 1) },
      { id: 'sinFecha', albergueId: 'mixta' },
    ];
    assert.deepEqual(r6(d), ['sinFecha', 'viejo']);
    assert.equal(D.analizar(d).estado, 'REQUIERE REVISIÓN MANUAL');
  });
  test('responsable con historial de rescatista (animal personal) aunque ya no tenga el rol', () => {
    const d = base();
    d.hogaresDePaso = [{ id: 'h', albergueId: 'exResc', creadoEn: fecha(2026, 2, 1) }];
    assert.deepEqual(r6(d), ['h']);
  });
  test('en fase completa el historial sale de los rescates leídos', () => {
    const d = base();
    d.historialRescatista = [];
    d.rescates = [{ id: 'rp', rescatistaId: 'exResc', creadoPor: 'rescatista' }];
    d.hogaresDePaso = [{ id: 'h', albergueId: 'exResc' }];
    assert.deepEqual(r6(d), ['h']);
  });
  test('fecha con un tipo inesperado cuenta como sin fecha (no se descarta)', () => {
    const d = base();
    d.hogaresDePaso = [{ id: 'h', albergueId: 'mixta', creadoEn: '2026-09-01' }];
    const r = D.analizar(d);
    assert.deepEqual(r6(d), ['h']);
    assert.match(r.revision.hogaresDudosos[0].motivo, /sin fecha de creación válida/);
  });
  test('hogares de cuentas que hoy no son responsables: latentes, informativo', () => {
    const d = base();
    d.hogaresDePaso = [{ id: 'h', albergueId: 'ana', creadoEn: fecha(2026, 1, 1) }];
    const r = D.analizar(d);
    assert.deepEqual(r.informativo.hogaresLatentes.map((h) => h.id), ['h']);
    assert.equal(r.informativo.hogaresCompartidos, 0);
    assert.equal(r.estado, 'APLICABLE');
  });
  test('hogar sin albergueId: latente, con su motivo', () => {
    const d = base();
    d.hogaresDePaso = [{ id: 'h' }, { id: 'h2', albergueId: '' }];
    assert.equal(D.analizar(d).informativo.hogaresLatentes.filter((h) => /sin albergueId/.test(h.motivo)).length, 2);
  });
  test('el informe muestra la cuenta con seudónimo, nunca el id real', () => {
    const d = base();
    d.hogaresDePaso = [{ id: 'hogarReal', albergueId: 'mixta' }];
    const texto = D.formatear(D.analizar(d));
    assert.match(texto, /R6 .*: 1/);
    assert.ok(!texto.includes('hogarReal') && !texto.includes('mixta'));
    assert.ok(texto.includes(`cuenta ${D.seudonimo('mixta')}`));
  });
  test('el flujo lee de hogaresDePaso solo albergueId y creadoEn, y nunca imprime nombres ni teléfonos', async () => {
    for (const mostrarIds of [false, true]) {
      const { db, ops } = baseFalsa(escenario());
      const salida = [];
      await D.ejecutarDiagnostico({ db, opciones: opcionesEmulador({ mostrarIds }), imprimir: (t) => salida.push(t), confirmar: sinConfirmar });
      const gets = ops.filter((o) => o.startsWith('get hogaresDePaso'));
      assert.ok(gets.length > 0);
      for (const g of gets) assert.match(g, /select=albergueId,creadoEn /);
      const texto = salida.join('\n');
      assert.ok(!texto.includes('Familia Ruiz') && !texto.includes('300 000 0000'));
    }
  });
  test('fase bloqueantes: pregunta por el historial solo de cuentas con hogares viejos o sin fecha, con limit 1', async () => {
    const { db, ops } = baseFalsa(escenario());
    await D.ejecutarDiagnostico({ db, opciones: opcionesEmulador(), imprimir: () => {}, confirmar: sinConfirmar });
    const historial = ops.filter((o) => o.includes('[creadoPor==rescatista]'));
    assert.deepEqual(historial.map((o) => /\[rescatistaId==(\w+)\]/.exec(o)[1]).sort(), ['ana', 'perla']);
    for (const o of historial) assert.match(o, /limit=1 /);
  });
  test('las dos fases marcan los mismos hogares dudosos en el escenario', async () => {
    const r = {};
    for (const fase of ['bloqueantes', 'completa']) {
      const { db } = baseFalsa(escenario());
      r[fase] = await D.ejecutarDiagnostico({ db, opciones: opcionesEmulador({ fase }), imprimir: () => {}, confirmar: sinConfirmar });
    }
    assert.deepEqual(r.bloqueantes.revision.hogaresDudosos.map((h) => h.id).sort(), ['hSinFecha', 'hViejo']);
    assert.deepEqual(r.bloqueantes.revision.hogaresDudosos, r.completa.revision.hogaresDudosos);
    assert.deepEqual(r.bloqueantes.informativo.hogaresLatentes, r.completa.informativo.hogaresLatentes);
  });
});

// ─── Tope de documentos durante la lectura ──────────────────────────────

describe('tope de documentos', () => {
  for (const fase of ['bloqueantes', 'completa']) {
    test(`${fase}: si los datos crecieron después del conteo, corta durante la lectura sin pasarse del tope`, async () => {
      const { db, ops } = baseFalsa(escenario(), { conteosEnCero: true });
      const salida = [];
      await assert.rejects(
        D.ejecutarDiagnostico({ db, opciones: opcionesEmulador({ fase, maxDocumentos: 6 }), imprimir: (t) => salida.push(t), confirmar: sinConfirmar }),
        /tope de --max-documentos=6 durante la lectura/);
      assert.ok(documentosLeidos(ops) <= 6, `leyó ${documentosLeidos(ops)}`);
      assert.ok(!salida.join('\n').includes('RESULTADO'), 'no tiene que analizar con datos incompletos');
    });
  }
  test('cada consulta pide como mucho lo que queda del presupuesto', async () => {
    const { db, ops } = baseFalsa(escenario());
    await D.ejecutarDiagnostico({ db, opciones: opcionesEmulador({ maxDocumentos: 500 }), imprimir: () => {}, confirmar: sinConfirmar });
    let restante = 500;
    for (const o of ops) {
      if (o.startsWith('get ')) {
        const lim = Number(/limit=(\d+)/.exec(o)[1]);
        assert.ok(lim <= restante, `${o} con ${restante} restantes`);
        restante -= Math.max(1, Number(/-> (\d+)$/.exec(o)[1]));
      } else if (o.startsWith('getAll ')) {
        restante -= Number(/n=(\d+)/.exec(o)[1]);
      }
    }
    assert.ok(restante >= 0);
  });
  test('getAll se comprueba antes de pedir: si no alcanza, no se llama', async () => {
    // usuarios(5) + servicios(1) + rescates del albergue(1) + chats del albergue(6) + consultas a negocios
    // aliados(1) + solicitudes(1) + hogares(4) = 19 lecturas. Quedan 2 y faltan 3 animales: no alcanza.
    const datos = escenario();
    datos.chats.push({ id: 'cExtra', adoptanteId: 'ana', rescatistaId: 'perla', creadoPor: 'albergue', tipoSolicitud: 'adopcion', rescateId: 'rOtro1' });
    datos.chats.push({ id: 'cExtra2', adoptanteId: 'ana', rescatistaId: 'perla', creadoPor: 'albergue', tipoSolicitud: 'adopcion', rescateId: 'rOtro2' });
    const { db, ops } = baseFalsa(datos, { conteosEnCero: true });
    await assert.rejects(
      D.ejecutarDiagnostico({ db, opciones: opcionesEmulador({ maxDocumentos: 21 }), imprimir: () => {}, confirmar: sinConfirmar }),
      /tope/);
    assert.ok(!ops.some((o) => o.startsWith('getAll ')), ops.join('\n'));
  });
  test('con margen suficiente el resultado no cambia', async () => {
    const { db } = baseFalsa(escenario());
    const r = await D.ejecutarDiagnostico({ db, opciones: opcionesEmulador({ maxDocumentos: 1000 }), imprimir: () => {}, confirmar: sinConfirmar });
    assert.equal(r.estado, 'BLOQUEADO');
  });
});

// ─── Terminología visible ────────────────────────────────────────────────

describe('terminología del informe', () => {
  test('el informe y el aviso dicen "negocio aliado" y "responsable", nunca "dueña" ni "aliada"', async () => {
    const { db } = baseFalsa(escenario());
    const salida = [];
    await D.ejecutarDiagnostico({ db, opciones: opcionesEmulador({ fase: 'completa', mostrarIds: true }), imprimir: (t) => salida.push(t), confirmar: sinConfirmar });
    const texto = [salida.join('\n'), D.avisoDeAcceso('bloqueantes'), D.avisoDeAcceso('completa')].join('\n');
    assert.doesNotMatch(texto, /dueñ|aliada/i);
    assert.match(texto, /responsable del albergue y negocio aliado/);
    assert.match(texto, /rol de negocio aliado/);
  });
  test('el aviso de producción incluye hogaresDePaso y el tope', () => {
    const aviso = D.avisoDeAcceso('bloqueantes');
    assert.match(aviso, /· hogaresDePaso \(completa\)/);
    assert.match(aviso, /Nunca más de --max-documentos documentos/);
  });
});
