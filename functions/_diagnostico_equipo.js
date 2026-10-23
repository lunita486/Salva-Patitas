// Diagnóstico de SOLO LECTURA antes de los equipos de albergue.
//
// **Qué contesta.** Si los datos de hoy permiten abrir los recursos del
// albergue a los miembros del equipo sin exponer nada ajeno (consultas a
// negocios aliados, recursos personales, hogares de paso de otro contexto),
// y qué datos viejos necesitan una revisión a mano. Ver
// PLAN-EQUIPO-ALBERGUE.md. Solo informa: no corrige, no migra y no borra
// nada.
//
// Resultado: APLICABLE, BLOQUEADO o REQUIERE REVISIÓN MANUAL.
//
// Uso
// ---
//   node functions/_diagnostico_equipo.js --emulador
//   node functions/_diagnostico_equipo.js --produccion --proyecto=patitas-dd0bb
//
// Opciones (cualquier otra se rechaza):
//   --fase=bloqueantes   (por defecto) solo lo necesario para decidir
//   --fase=completa      además lee completas chats, solicitudes y rescates
//   --max-documentos=N   tope de documentos (por defecto 20000): se compara
//                        con la estimación antes de leer y se hace cumplir
//                        DURANTE la lectura; nunca lee más de N documentos
//   --mostrar-ids        id reales en vez de seudónimos (solo cambia el texto)
//
// Qué garantiza y qué no
// ----------------------
// 1. **El flujo solo lee.** Las únicas operaciones contra la base son
//    select-get, where-get, count-get y getAll, todas dentro de recolectar()
//    y contarPrevio(). Las pruebas corren el flujo entero contra una base
//    falsa que falla ante cualquier otra operación.
// 2. **Protección extra, NO universal.** soloLectura() reemplaza los métodos
//    de escritura públicos del SDK de Firestore para que un cambio futuro que
//    los llame falle. No bloquea vías internas del SDK (WriteBatch._commit,
//    Firestore.request, un BulkWriter creado a mano), otros servicios de
//    firebase-admin (Auth, Storage) ni un pedido directo a la API REST. El
//    único bloqueo universal sería correrlo con una identidad que solo tenga
//    permiso de lectura.
//
// Destino
// -------
// --emulador fija FIRESTORE_EMULATOR_HOST en 127.0.0.1:8097 (pisando lo que
// hubiera: con la variable vacía el SDK iba a producción) y aborta antes de
// leer si no puede demostrar que el cliente apunta a esa máquina.
// --produccion exige --proyecto=patitas-dd0bb, borra la variable del
// emulador y usa Application Default Credentials (ADC) de forma explícita.
// Crear el cliente no consulta nada; antes de la PRIMERA consulta (incluidos
// los conteos, que también se cobran) muestra qué se va a hacer y pide
// escribir "CONTAR patitas-dd0bb". Después de los conteos muestra la
// estimación y pide "LEER patitas-dd0bb" antes de leer documentos. Sin
// terminal interactiva, o con cualquier otra respuesta, cancela.
//
// Qué lee (solo estos campos, con select o fieldMask)
// ---------------------------------------------------
//   usuarios     roles, albergueNombre, aliadoNombre, trabajaEn   (completa)
//   servicios    aliadoId                                        (completa)
//   rescates     rescatistaId, creadoPor
//   chats        adoptanteId, rescatistaId, creadoPor, tipoSolicitud,
//                rescateId, solicitudId
//   solicitudes  rescatistaId, creadoPor, rescateId
//   hogaresDePaso albergueId, creadoEn (nunca nombres, teléfonos ni correos)
//                                                               (completa)
//   membresias, invitaciones, equipos: solo count
// En fase bloqueantes, de rescates, chats y solicitudes lee solo los de
// creadoPor == 'albergue' (exactamente lo que la regla de miembro abriría),
// los chats con tipoSolicitud == 'consulta_aliado' y los documentos a los que
// esos apuntan. Además, por cada cuenta con hogares de paso viejos o sin
// fecha, mira si tiene al menos un animal personal (1 lectura, limit 1).
// Seleccionar campos NO abarata: se cobra una lectura por documento igual.
const { hash } = require('node:crypto');
const { existsSync } = require('node:fs');
const { basename, join } = require('node:path');
const { homedir } = require('node:os');

const PROYECTO = 'patitas-dd0bb';
const HOST_EMULADOR = '127.0.0.1:8097';
const HOSTS_LOCALES = ['127.0.0.1', 'localhost', '::1', '[::1]'];
const MAX_DOCUMENTOS_DEFECTO = 20000;
const RESERVADAS = ['membresias', 'invitaciones', 'equipos'];
const ROLES_CONOCIDOS = ['adoptante', 'rescatista', 'albergue', 'aliado'];
const TIPOS_CONOCIDOS = ['adopcion', 'hogar_de_paso', 'consulta', 'consulta_aliado'];
const FRASE_CONTAR = `CONTAR ${PROYECTO}`;
const FRASE_LEER = `LEER ${PROYECTO}`;
// Desde este día firestore.rules exige el rol 'albergue' para crear en
// hogaresDePaso (commit abf8525). Antes, una cuenta sin ese rol también podía.
const REGLA_ROL_ALBERGUE = Date.UTC(2026, 6, 31);

const CAMPOS = {
  usuarios: ['roles', 'albergueNombre', 'aliadoNombre', 'trabajaEn'],
  servicios: ['aliadoId'],
  rescates: ['rescatistaId', 'creadoPor'],
  chats: ['adoptanteId', 'rescatistaId', 'creadoPor', 'tipoSolicitud', 'rescateId', 'solicitudId'],
  solicitudes: ['rescatistaId', 'creadoPor', 'rescateId'],
  hogaresDePaso: ['albergueId', 'creadoEn'],
};

// ─── Argumentos ──────────────────────────────────────────────────────────

/** Lee los argumentos. Lanza un Error con el motivo ante cualquier duda. */
function parsearArgs(argv) {
  const op = { modo: null, fase: 'bloqueantes', mostrarIds: false, proyecto: null, maxDocumentos: MAX_DOCUMENTOS_DEFECTO };
  const vistos = [];
  for (const arg of argv) {
    const nombre = arg.split('=')[0];
    if (vistos.includes(nombre)) throw new Error(`Argumento repetido: ${nombre}`);
    vistos.push(nombre);
    if (arg === '--emulador' || arg === '--produccion') {
      if (op.modo) throw new Error('Elegí exactamente uno: --emulador o --produccion.');
      op.modo = arg.slice(2);
    } else if (arg === '--mostrar-ids') {
      op.mostrarIds = true;
    } else if (nombre === '--fase') {
      const v = arg.slice('--fase='.length);
      if (v !== 'bloqueantes' && v !== 'completa') throw new Error('--fase tiene que ser bloqueantes o completa.');
      op.fase = v;
    } else if (nombre === '--proyecto') {
      op.proyecto = arg.slice('--proyecto='.length);
    } else if (nombre === '--max-documentos') {
      const v = arg.slice('--max-documentos='.length);
      if (!/^[1-9][0-9]*$/.test(v)) throw new Error('--max-documentos tiene que ser un entero positivo.');
      op.maxDocumentos = Number(v);
    } else {
      throw new Error(`Argumento desconocido: ${arg}`);
    }
  }
  if (!op.modo) throw new Error('Elegí exactamente uno: --emulador o --produccion.');
  if (op.proyecto !== null && op.proyecto !== PROYECTO) {
    throw new Error(`--proyecto tiene que ser ${PROYECTO}; llegó "${op.proyecto}".`);
  }
  if (op.modo === 'produccion' && op.proyecto !== PROYECTO) {
    throw new Error(`En producción hay que escribir --proyecto=${PROYECTO}.`);
  }
  return op;
}

// ─── Destino ─────────────────────────────────────────────────────────────

/** Ajusta el entorno ANTES de crear el cliente. Pisa siempre la variable. */
function prepararEntorno(modo, env) {
  if (modo === 'emulador') {
    // `=` y no `??=`: una variable vacía no es "nula" para `??=`, y el SDK la
    // trata como si no existiera, o sea, va a producción.
    env.FIRESTORE_EMULATOR_HOST = HOST_EMULADOR;
  } else {
    delete env.FIRESTORE_EMULATOR_HOST;
  }
}

/**
 * Demuestra a dónde apunta el cliente ya creado, o lanza. Mira `_settings`,
 * que es interno del SDK: si un día cambia de forma, esto deja de poder
 * demostrarlo y aborta, que es lo que tiene que pasar.
 */
function verificarDestino(modo, db, env) {
  const s = db && db._settings;
  if (!s || typeof s !== 'object') {
    throw new Error('No se puede leer la configuración del cliente; no se puede demostrar el destino.');
  }
  const proyecto = db._projectId ?? s.projectId;
  if (proyecto !== PROYECTO) {
    throw new Error(`El cliente apunta al proyecto "${proyecto}", no a ${PROYECTO}.`);
  }
  if (modo === 'emulador') {
    if (env.FIRESTORE_EMULATOR_HOST !== HOST_EMULADOR) {
      throw new Error('FIRESTORE_EMULATOR_HOST no es el emulador local.');
    }
    if (!HOSTS_LOCALES.includes(s.servicePath) || s.port !== 8097 || s.ssl !== false) {
      throw new Error(`El cliente no apunta al emulador local (host ${s.servicePath ?? 'por defecto'}, puerto ${s.port}).`);
    }
  } else {
    if (env.FIRESTORE_EMULATOR_HOST !== undefined) {
      throw new Error('En producción no puede quedar FIRESTORE_EMULATOR_HOST definida.');
    }
    if (s.servicePath !== undefined && s.servicePath !== 'firestore.googleapis.com') {
      throw new Error(`El cliente apunta a un host inesperado: ${s.servicePath}.`);
    }
  }
}

/** De dónde sacaría ADC las credenciales. No lee el contenido de ningún archivo. */
function describirCredenciales(env, existe = existsSync) {
  if (env.GOOGLE_APPLICATION_CREDENTIALS) {
    return `archivo de GOOGLE_APPLICATION_CREDENTIALS (${basename(env.GOOGLE_APPLICATION_CREDENTIALS)})`;
  }
  if (existe(join(homedir(), '.config', 'gcloud', 'application_default_credentials.json'))) {
    return 'credenciales de gcloud (gcloud auth application-default login)';
  }
  return 'ninguna encontrada: la conexión va a fallar (configurá ADC primero)';
}

// ─── Protección extra (no universal, ver arriba) ────────────────────────

const METODOS_BLOQUEADOS = {
  DocumentReference: ['set', 'update', 'delete', 'create'],
  CollectionReference: ['add'],
  WriteBatch: ['commit'],
  Transaction: ['set', 'update', 'delete', 'create'],
  Firestore: ['runTransaction', 'bulkWriter', 'recursiveDelete', 'batch'],
};

function soloLectura(fs) {
  for (const [clase, metodos] of Object.entries(METODOS_BLOQUEADOS)) {
    for (const m of metodos) {
      fs[clase].prototype[m] = function () {
        throw new Error(`_diagnostico_equipo es de solo lectura: se bloqueó ${clase}.${m}()`);
      };
    }
  }
}

// ─── Lecturas ────────────────────────────────────────────────────────────

/** Las consultas de cada fase, en un solo lugar para contar y leer igual. */
function consultasDe(fase) {
  const todas = fase === 'completa';
  return [
    { clave: 'usuarios', coleccion: 'usuarios' },
    { clave: 'servicios', coleccion: 'servicios' },
    todas
      ? { clave: 'rescates', coleccion: 'rescates' }
      : { clave: 'rescates', coleccion: 'rescates', donde: ['creadoPor', 'albergue'] },
    ...(todas
      ? [{ clave: 'chats', coleccion: 'chats' }]
      : [
          { clave: 'chats', coleccion: 'chats', donde: ['creadoPor', 'albergue'] },
          { clave: 'chats', coleccion: 'chats', donde: ['tipoSolicitud', 'consulta_aliado'] },
        ]),
    todas
      ? { clave: 'solicitudes', coleccion: 'solicitudes' }
      : { clave: 'solicitudes', coleccion: 'solicitudes', donde: ['creadoPor', 'albergue'] },
    // No tiene campo de contexto: hay que leerla entera en las dos fases.
    { clave: 'hogaresDePaso', coleccion: 'hogaresDePaso' },
  ];
}

function consulta(db, c) {
  const col = db.collection(c.coleccion);
  return c.donde ? col.where(c.donde[0], '==', c.donde[1]) : col;
}

async function contar(q) {
  return (await q.count().get()).data().count;
}

/**
 * Cuántos documentos leería cada consulta, con count. Cuesta 1 lectura por
 * cada 1000 documentos contados (mínimo 1 por consulta).
 */
async function contarPrevio(db, fase) {
  const detalle = [];
  for (const c of consultasDe(fase)) {
    detalle.push({ ...c, n: await contar(consulta(db, c)) });
  }
  const reservadas = {};
  for (const nombre of RESERVADAS) reservadas[nombre] = await contar(db.collection(nombre));
  // En fase bloqueantes además se leen los documentos a los que apuntan los
  // chats y solicitudes del albergue (como mucho uno por rescateId y uno por
  // solicitudId de cada chat, y uno por rescateId de cada solicitud) y, por
  // cada cuenta con hogares de paso viejos o sin fecha, 1 lectura de
  // historial (como mucho una por hogar).
  let referenciados = 0;
  if (fase === 'bloqueantes') {
    const n = (coleccion, campo) =>
      detalle.find((d) => d.coleccion === coleccion && (campo ? d.donde && d.donde[0] === campo : !d.donde))?.n ?? 0;
    referenciados = 2 * n('chats', 'creadoPor') + n('solicitudes', 'creadoPor') + n('hogaresDePaso');
  }
  const estimadas = detalle.reduce((s, d) => s + d.n, 0) + referenciados;
  const lecturasDelConteo = [...detalle.map((d) => d.n), ...Object.values(reservadas)]
      .reduce((s, n) => s + Math.max(1, Math.ceil(n / 1000)), 0);
  return { detalle, reservadas, referenciados, estimadas, lecturasDelConteo };
}

// ─── Tope de documentos durante la lectura ──────────────────────────────
//
// La estimación previa puede quedarse corta si los datos crecen entre el
// conteo y la lectura. Por eso cada lectura descuenta de un presupuesto y
// nunca pide más de lo que queda: el script no puede leer más de
// --max-documentos documentos. Una consulta que no devuelve nada se cobra
// igual (1 lectura), así que también descuenta 1.

class TopeAlcanzado extends Error {}

function topeAlcanzado(presupuesto) {
  return new TopeAlcanzado(
    `Se alcanzó el tope de --max-documentos=${presupuesto.max} durante la lectura ` +
    '(los datos pueden haber crecido desde el conteo). Se detuvo sin analizar nada.');
}

async function leerConsulta(db, c, presupuesto) {
  if (presupuesto.restante < 1) throw topeAlcanzado(presupuesto);
  const snap = await consulta(db, c).select(...CAMPOS[c.coleccion]).limit(presupuesto.restante).get();
  // Si llenó el límite justo, puede haber más documentos sin leer: se corta
  // antes de analizar con datos incompletos.
  if (snap.docs.length >= presupuesto.restante) throw topeAlcanzado(presupuesto);
  presupuesto.restante -= Math.max(1, snap.docs.length);
  return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
}

async function leerPorId(db, coleccion, ids, presupuesto) {
  const encontrados = [];
  const lista = [...new Set(ids)].filter((id) => typeof id === 'string' && id !== '' && !id.includes('/'));
  // getAll cobra una lectura por id, exista o no: se comprueba antes de pedir.
  if (lista.length > presupuesto.restante) throw topeAlcanzado(presupuesto);
  presupuesto.restante -= lista.length;
  for (let i = 0; i < lista.length; i += 300) {
    const refs = lista.slice(i, i + 300).map((id) => db.collection(coleccion).doc(id));
    const snaps = await db.getAll(...refs, { fieldMask: CAMPOS[coleccion] });
    for (const s of snaps) if (s.exists) encontrados.push({ id: s.id, ...s.data() });
  }
  return encontrados;
}

/** ¿Esta cuenta tiene al menos un animal personal? 1 lectura (limit 1). */
async function tieneAnimalPersonal(db, uid, presupuesto) {
  if (presupuesto.restante < 1) throw topeAlcanzado(presupuesto);
  presupuesto.restante -= 1;
  const snap = await db.collection('rescates')
      .where('rescatistaId', '==', uid).where('creadoPor', '==', 'rescatista')
      .select('rescatistaId').limit(1).get();
  return snap.docs.length > 0;
}

/** Milisegundos de un Timestamp del SDK o de un Date; null si no hay fecha válida. */
function msDe(v) {
  if (v && typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date && !Number.isNaN(v.getTime())) return v.getTime();
  return null;
}

/** Un hogar de paso creado antes de que la regla exigiera el rol, o sin fecha. */
const hogarViejoOSinFecha = (h) => {
  const ms = msDe(h.creadoEn);
  return ms === null || ms < REGLA_ROL_ALBERGUE;
};

function unir(a, b) {
  const ids = new Set(a.map((d) => d.id));
  return [...a, ...b.filter((d) => !ids.has(d.id))];
}

/**
 * Junta los documentos (sin repetir) que necesita analizar(). Solo lee, y
 * nunca más de `maxDocumentos` documentos (ver el tope, arriba).
 */
async function recolectar(db, fase, reservadas, maxDocumentos = MAX_DOCUMENTOS_DEFECTO) {
  const presupuesto = { max: maxDocumentos, restante: maxDocumentos };
  const datos = { usuarios: [], servicios: [], rescates: [], chats: [], solicitudes: [], hogaresDePaso: [] };
  for (const c of consultasDe(fase)) {
    datos[c.clave] = unir(datos[c.clave], await leerConsulta(db, c, presupuesto));
  }
  const historialRescatista = [];
  if (fase === 'bloqueantes') {
    const deChats = datos.chats.filter((c) => c.creadoPor === 'albergue');
    const deSolicitudes = datos.solicitudes.filter((s) => s.creadoPor === 'albergue');
    const yaRescates = new Set(datos.rescates.map((r) => r.id));
    const yaSolicitudes = new Set(datos.solicitudes.map((s) => s.id));
    const rescatesFaltan = [...deChats, ...deSolicitudes].map((d) => d.rescateId).filter((id) => !yaRescates.has(id));
    const solicitudesFaltan = deChats.map((c) => c.solicitudId).filter((id) => !yaSolicitudes.has(id));
    datos.rescates = unir(datos.rescates, await leerPorId(db, 'rescates', rescatesFaltan, presupuesto));
    datos.solicitudes = unir(datos.solicitudes, await leerPorId(db, 'solicitudes', solicitudesFaltan, presupuesto));
    // En la fase completa ya están todos los rescates; acá se pregunta solo
    // por las cuentas que tienen hogares de paso viejos o sin fecha.
    const candidatas = [...new Set(datos.hogaresDePaso.filter(hogarViejoOSinFecha)
        .map((h) => h.albergueId).filter((id) => typeof id === 'string' && id !== '' && !id.includes('/')))].sort();
    for (const uid of candidatas) {
      if (await tieneAnimalPersonal(db, uid, presupuesto)) historialRescatista.push(uid);
    }
  }
  return { ...datos, historialRescatista, reservadas, fase };
}

// ─── Análisis (puro) ─────────────────────────────────────────────────────

const clase = (v) =>
  v === undefined ? 'ausente'
    : v === null ? 'null'
      : typeof v === 'string' ? (v.trim() === '' ? 'vacio' : 'texto')
        : 'otro';
const esTexto = (v) => clase(v) === 'texto';
const tiene = (lista, valor) => Array.isArray(lista) && lista.includes(valor);
const descTipo = (t) =>
  clase(t) !== 'texto' ? `tipoSolicitud ${clase(t)}`
    : TIPOS_CONOCIDOS.includes(t) ? `tipoSolicitud '${t}'` : 'tipoSolicitud inesperado';

/**
 * Toda la decisión, sin Firestore: recibe los documentos ya leídos como
 * objetos planos `{ id, ...campos }`. Cada hallazgo es `{ id, motivo }`.
 *
 * La clave de la opción (b): la regla de miembro abre un chat o solicitud
 * cuando `creadoPor == 'albergue'` (igualdad exacta) y el rescatistaId es
 * el albergue. Así que se clasifica CADA documento con ese creadoPor según
 * lo que se pueda demostrar con sus anclajes, sin adivinar por el tipo.
 */
function analizar({
  usuarios, servicios, rescates, chats, solicitudes, reservadas,
  hogaresDePaso = [], historialRescatista = [], fase = 'completa',
}) {
  const completa = fase === 'completa';
  const rescatePorId = new Map(rescates.map((r) => [r.id, r]));
  const solicitudPorId = new Map(solicitudes.map((s) => [s.id, s]));
  const usuarioPorId = new Map(usuarios.map((u) => [u.id, u]));

  const bloqueantes = { duenaYAliada: [], consultasRecibidasPorDuena: [], reservadasConDatos: [], trabajaEnEnUso: [] };
  const revision = {
    valoresInesperados: [], chatsIncoherentes: [], chatsIndeterminados: [], solicitudesIncoherentes: [],
    solicitudesIndeterminadas: [], hogaresDudosos: [],
  };
  const huerfanos = { chats: [], solicitudes: [] };
  const informativo = {
    consultasLatentes: [], trabajaEnVacio: [], invisiblesAlEquipo: { chats: [], solicitudes: [] },
    creadoPorInesperado: [], chatsSinTipo: null, animalesDeAlbergueSinRol: [], duenaYRescatista: null,
    hogaresLatentes: [], hogaresCompartidos: 0,
  };

  // Señales de "responsable del albergue" y de "negocio aliado", por todos
  // los lados y no solo por roles: los roles se mueven, lo publicado queda.
  const animalesAlbergue = new Set(rescates.filter((r) => r.creadoPor === 'albergue').map((r) => r.rescatistaId));
  const conServicio = new Set(servicios.map((s) => s.aliadoId));
  const recibioConsultaAliado = new Set(chats.filter((c) => c.tipoSolicitud === 'consulta_aliado').map((c) => c.rescatistaId));

  const senalesDuena = (uid) => {
    const u = usuarioPorId.get(uid) ?? {};
    return [
      tiene(u.roles, 'albergue') && 'rol albergue',
      esTexto(u.albergueNombre) && 'nombre de albergue',
      animalesAlbergue.has(uid) && 'animales de albergue',
    ].filter(Boolean);
  };
  const senalesAliada = (uid) => {
    const u = usuarioPorId.get(uid) ?? {};
    return [
      tiene(u.roles, 'aliado') && 'rol de negocio aliado',
      esTexto(u.aliadoNombre) && 'nombre de negocio',
      conServicio.has(uid) && 'servicio publicado',
      recibioConsultaAliado.has(uid) && 'recibió consultas como negocio aliado',
    ].filter(Boolean);
  };
  const esDuena = (uid) => senalesDuena(uid).length > 0;

  // Valores que no permiten decidir si alguien es responsable o negocio aliado.
  for (const u of usuarios) {
    if (u.roles !== undefined && !Array.isArray(u.roles)) {
      revision.valoresInesperados.push({ id: u.id, motivo: `usuarios.roles no es una lista (${clase(u.roles)})` });
    } else if (Array.isArray(u.roles) && u.roles.some((r) => !ROLES_CONOCIDOS.includes(r))) {
      revision.valoresInesperados.push({ id: u.id, motivo: 'usuarios.roles con un valor desconocido' });
    }
    for (const campo of ['albergueNombre', 'aliadoNombre']) {
      if (clase(u[campo]) === 'otro') {
        revision.valoresInesperados.push({ id: u.id, motivo: `usuarios.${campo} no es texto` });
      }
    }
    // A4: solo un texto no vacío es uso real del campo.
    const t = clase(u.trabajaEn);
    if (t === 'texto') bloqueantes.trabajaEnEnUso.push({ id: u.id, motivo: 'trabajaEn con valor' });
    else if (t === 'null' || t === 'vacio') informativo.trabajaEnVacio.push({ id: u.id, motivo: `trabajaEn ${t}` });
    else if (t === 'otro') revision.valoresInesperados.push({ id: u.id, motivo: 'usuarios.trabajaEn no es texto' });
  }

  // A1
  const ids = new Set([...usuarioPorId.keys(), ...animalesAlbergue, ...conServicio, ...recibioConsultaAliado]);
  for (const uid of [...ids].sort()) {
    const d = senalesDuena(uid);
    const a = senalesAliada(uid);
    if (d.length && a.length) bloqueantes.duenaYAliada.push({ id: uid, motivo: [...d, ...a].join(', ') });
  }

  // Chats que la regla de miembro abriría.
  for (const c of chats.filter((x) => x.creadoPor === 'albergue')) {
    if (c.tipoSolicitud === 'consulta_aliado') {
      // Fuga segura si el negocio aliado destinatario es responsable de un
      // albergue. Si no lo es, queda latente: se volvería fuga si esa cuenta
      // algún día tuviera equipo y la regla no excluyera estas consultas.
      (esDuena(c.rescatistaId) ? bloqueantes.consultasRecibidasPorDuena : informativo.consultasLatentes)
          .push({ id: c.id, motivo: 'consulta_aliado con creadoPor albergue' });
      continue;
    }
    const tipo = descTipo(c.tipoSolicitud);
    const r = esTexto(c.rescateId) ? rescatePorId.get(c.rescateId) : undefined;
    const s = esTexto(c.solicitudId) ? solicitudPorId.get(c.solicitudId) : undefined;
    const animalOk = r && r.rescatistaId === c.rescatistaId && r.creadoPor === 'albergue';
    const solicitudOk = s && s.rescatistaId === c.rescatistaId && s.creadoPor === 'albergue';
    if (animalOk || (!r && solicitudOk)) continue; // demostrable como chat del albergue
    if (r) {
      const motivo = r.rescatistaId === c.rescatistaId
        ? 'su animal es personal (creadoPor del animal no es albergue)'
        : 'su animal es de otra cuenta';
      revision.chatsIncoherentes.push({ id: c.id, motivo: `${motivo}; ${tipo}` });
    } else if (s) {
      revision.chatsIncoherentes.push({ id: c.id, motivo: `su solicitud no es de este albergue; ${tipo}` });
    } else if (esTexto(c.rescateId) || esTexto(c.solicitudId)) {
      huerfanos.chats.push({ id: c.id, motivo: `apunta a un animal o solicitud que ya no existe; ${tipo}` });
    } else {
      revision.chatsIndeterminados.push({ id: c.id, motivo: `sin rescateId ni solicitudId; ${tipo}` });
    }
  }

  // Solicitudes que la regla de miembro abriría.
  for (const s of solicitudes.filter((x) => x.creadoPor === 'albergue')) {
    const r = esTexto(s.rescateId) ? rescatePorId.get(s.rescateId) : undefined;
    if (r && r.rescatistaId === s.rescatistaId && r.creadoPor === 'albergue') continue;
    if (r) {
      revision.solicitudesIncoherentes.push({
        id: s.id, motivo: r.rescatistaId === s.rescatistaId ? 'su animal es personal' : 'su animal es de otra cuenta',
      });
    } else if (esTexto(s.rescateId)) {
      huerfanos.solicitudes.push({ id: s.id, motivo: 'apunta a un animal que ya no existe' });
    } else {
      revision.solicitudesIndeterminadas.push({ id: s.id, motivo: 'sin rescateId' });
    }
  }

  // Cuentas con animales de albergue que perdieron el rol.
  for (const uid of [...animalesAlbergue].sort()) {
    if (!tiene(usuarioPorId.get(uid)?.roles, 'albergue')) {
      informativo.animalesDeAlbergueSinRol.push({ id: uid, motivo: 'animales de albergue sin el rol' });
    }
  }

  // Lo que solo se puede ver leyendo las colecciones completas: documentos
  // SIN creadoPor (Firestore no puede buscar "campo ausente").
  if (completa) {
    const sinCreadoPor = (d) => ['ausente', 'null', 'vacio'].includes(clase(d.creadoPor));
    const deAlbergueCoherente = (d) => {
      const r = esTexto(d.rescateId) ? rescatePorId.get(d.rescateId) : undefined;
      return r && r.creadoPor === 'albergue' && r.rescatistaId === d.rescatistaId;
    };
    for (const c of chats) {
      if (sinCreadoPor(c) && c.tipoSolicitud !== 'consulta_aliado' && deAlbergueCoherente(c)) {
        informativo.invisiblesAlEquipo.chats.push({ id: c.id, motivo: `sin creadoPor, animal del albergue; ${descTipo(c.tipoSolicitud)}` });
      }
    }
    for (const s of solicitudes) {
      if (sinCreadoPor(s) && deAlbergueCoherente(s)) {
        informativo.invisiblesAlEquipo.solicitudes.push({ id: s.id, motivo: 'sin creadoPor, animal del albergue' });
      }
    }
    // creadoPor con otro valor: la regla compara con igualdad exacta, así que
    // el equipo no los vería. Se listan igual para no esconder nada.
    for (const [col, docs] of [['rescates', rescates], ['chats', chats], ['solicitudes', solicitudes]]) {
      for (const d of docs) {
        if (!sinCreadoPor(d) && d.creadoPor !== 'albergue' && d.creadoPor !== 'rescatista') {
          informativo.creadoPorInesperado.push({ id: d.id, motivo: `${col}.creadoPor inesperado` });
        }
      }
    }
    const sinTipo = { total: 0, albergue: 0, rescatista: 0, sinCampo: 0, otro: 0, consulta: 0, inesperado: 0 };
    for (const c of chats) {
      if (c.tipoSolicitud === 'consulta') sinTipo.consulta++;
      else if (esTexto(c.tipoSolicitud) && !TIPOS_CONOCIDOS.includes(c.tipoSolicitud)) sinTipo.inesperado++;
      if (esTexto(c.tipoSolicitud)) continue;
      sinTipo.total++;
      if (c.creadoPor === 'albergue') sinTipo.albergue++;
      else if (c.creadoPor === 'rescatista') sinTipo.rescatista++;
      else if (sinCreadoPor(c)) sinTipo.sinCampo++;
      else sinTipo.otro++;
    }
    informativo.chatsSinTipo = sinTipo;
    const deRescatista = new Set(rescates.filter((r) => r.creadoPor === 'rescatista').map((r) => r.rescatistaId));
    informativo.duenaYRescatista = [...ids].filter((uid) => esDuena(uid) &&
      (tiene(usuarioPorId.get(uid)?.roles, 'rescatista') || deRescatista.has(uid))).length;
  }

  // Hogares de paso: el equipo vería toda la red de la responsable, con datos
  // de contacto de las familias, y la colección no tiene campo de contexto.
  // Hasta REGLA_ROL_ALBERGUE una cuenta sin el rol de albergue también podía
  // crear ahí; si la responsable tuvo vida de rescatista, un hogar de antes
  // de esa fecha (o sin fecha) no se puede demostrar como del albergue.
  const conHistorial = new Set([
    ...historialRescatista,
    ...rescates.filter((r) => r.creadoPor === 'rescatista').map((r) => r.rescatistaId),
  ]);
  const tuvoVidaDeRescatista = (uid) => tiene(usuarioPorId.get(uid)?.roles, 'rescatista') || conHistorial.has(uid);
  for (const h of hogaresDePaso) {
    const uid = h.albergueId;
    if (!esTexto(uid)) {
      informativo.hogaresLatentes.push({ id: h.id, motivo: 'sin albergueId válido (nadie puede leerlo)' });
    } else if (!esDuena(uid)) {
      informativo.hogaresLatentes.push({ id: h.id, motivo: 'la cuenta no es responsable de un albergue hoy', de: uid });
    } else {
      informativo.hogaresCompartidos++;
      if (tuvoVidaDeRescatista(uid) && hogarViejoOSinFecha(h)) {
        revision.hogaresDudosos.push({
          id: h.id, de: uid,
          motivo: msDe(h.creadoEn) === null ? 'sin fecha de creación válida' : 'creado antes del 2026-07-31',
        });
      }
    }
  }

  for (const nombre of RESERVADAS) {
    if ((reservadas[nombre] ?? 0) > 0) {
      bloqueantes.reservadasConDatos.push({ id: nombre, motivo: `${reservadas[nombre]} documentos` });
    }
  }

  const hay = (o) => Object.values(o).some((l) => l.length > 0);
  const estado = hay(bloqueantes) ? 'BLOQUEADO' : hay(revision) ? 'REQUIERE REVISIÓN MANUAL' : 'APLICABLE';

  return {
    fase,
    totales: {
      usuarios: usuarios.length, servicios: servicios.length, rescates: rescates.length,
      chats: chats.length, solicitudes: solicitudes.length, hogaresDePaso: hogaresDePaso.length,
    },
    bloqueantes, revision, huerfanos, informativo, estado,
    opcionBAplicable: estado === 'APLICABLE',
  };
}

// ─── Informe ─────────────────────────────────────────────────────────────

const seudonimo = (id) => '#' + hash('sha256', String(id)).slice(0, 8);

/** El informe en texto. `nombrar` decide si se ven id reales o seudónimos. */
function formatear(r, nombrar = seudonimo) {
  const L = [];
  const item = (codigo, titulo, lista) => {
    L.push(`  ${codigo} ${titulo}: ${lista.length}`);
    for (const h of lista) {
      L.push(`      ${nombrar(h.id)} (${h.motivo}${h.de === undefined ? '' : `; cuenta ${nombrar(h.de)}`})`);
    }
  };
  const t = r.totales;
  L.push(`Fase: ${r.fase}. Leídos: ${t.usuarios} usuarios, ${t.servicios} servicios, ${t.rescates} rescates, ` +
    `${t.chats} chats, ${t.solicitudes} solicitudes, ${t.hogaresDePaso} hogares de paso.`);
  L.push('');
  L.push('BLOQUEANTES:');
  item('A1', 'cuentas que son responsable del albergue y negocio aliado a la vez', r.bloqueantes.duenaYAliada);
  item('A2', 'consultas a negocios aliados con creadoPor albergue recibidas por una responsable del albergue', r.bloqueantes.consultasRecibidasPorDuena);
  L.push(`  A3 colecciones nuevas que ya tienen datos: ${r.bloqueantes.reservadasConDatos.length}`);
  for (const h of r.bloqueantes.reservadasConDatos) L.push(`      ${h.id} (${h.motivo})`);
  item('A4', 'perfiles con trabajaEn en uso', r.bloqueantes.trabajaEnEnUso);
  L.push('');
  L.push('REQUIEREN REVISIÓN MANUAL (el equipo los vería y los datos no alcanzan para demostrar que son del albergue):');
  item('R1', 'valores inesperados en usuarios', r.revision.valoresInesperados);
  item('R2', 'chats de albergue incoherentes', r.revision.chatsIncoherentes);
  item('R3', 'chats de albergue indeterminados', r.revision.chatsIndeterminados);
  item('R4', 'solicitudes de albergue incoherentes', r.revision.solicitudesIncoherentes);
  item('R5', 'solicitudes de albergue indeterminadas', r.revision.solicitudesIndeterminadas);
  item('R6', 'hogares de paso de una responsable que también fue rescatista, anteriores al 2026-07-31 o sin fecha', r.revision.hogaresDudosos);
  L.push('');
  L.push('HUÉRFANOS (no bloquean; su animal o solicitud ya no existe):');
  item('H1', 'chats', r.huerfanos.chats);
  item('H2', 'solicitudes', r.huerfanos.solicitudes);
  L.push('');
  L.push('INFORMATIVO:');
  item('I1', 'consultas latentes (el negocio aliado destinatario no es responsable de un albergue hoy)', r.informativo.consultasLatentes);
  item('I2', 'trabajaEn presente pero vacío', r.informativo.trabajaEnVacio);
  item('I3', 'cuentas con animales de albergue y sin el rol', r.informativo.animalesDeAlbergueSinRol);
  item('I9', 'hogares de paso de cuentas que hoy no son responsables de un albergue (latentes)', r.informativo.hogaresLatentes);
  L.push(`  I10 hogares de paso de responsables, que el equipo vería (con datos de contacto de las familias): ${r.informativo.hogaresCompartidos}`);
  if (r.fase === 'completa') {
    item('I4', 'chats sin creadoPor de animales del albergue (el equipo no los vería)', r.informativo.invisiblesAlEquipo.chats);
    item('I5', 'solicitudes sin creadoPor de animales del albergue (ídem)', r.informativo.invisiblesAlEquipo.solicitudes);
    item('I6', 'creadoPor con valor inesperado (el equipo no los vería)', r.informativo.creadoPorInesperado);
    const s = r.informativo.chatsSinTipo;
    L.push(`  I7 chats sin tipoSolicitud: ${s.total} (creadoPor albergue ${s.albergue}, rescatista ${s.rescatista}, sin campo ${s.sinCampo}, otro ${s.otro}); con 'consulta': ${s.consulta}; con tipo inesperado: ${s.inesperado}`);
    L.push(`  I8 cuentas responsables de un albergue y además rescatistas (no es conflicto): ${r.informativo.duenaYRescatista}`);
  } else {
    L.push('  I4 a I8: no evaluados en fase bloqueantes (necesitan --fase=completa).');
  }
  L.push('');
  L.push(`RESULTADO: ${r.estado}.`);
  if (r.fase === 'bloqueantes') {
    L.push('Nota: la fase bloqueantes ve completo lo que la regla de miembro abriría (creadoPor == albergue). Los datos sin creadoPor no se evaluaron.');
  }
  return L.join('\n');
}

// ─── Ejecución ───────────────────────────────────────────────────────────

/**
 * Pregunta una frase de confirmación en la terminal y la compara exacta. Sin
 * terminal interactiva se niega: así no corre desde un script o un pipe sin
 * que alguien mire.
 */
async function confirmarEnTerminal(texto, frase, io = process) {
  if (!io.stdin.isTTY || !io.stdout.isTTY) return false;
  const rl = require('node:readline/promises').createInterface({ input: io.stdin, output: io.stdout });
  try {
    return (await rl.question(texto)).trim() === frase;
  } finally {
    rl.close();
  }
}

/** Lo que se muestra ANTES de la primera consulta a producción. */
function avisoDeAcceso(fase) {
  const desc = (c) => c.coleccion + (c.donde ? ` donde ${c.donde[0]} == '${c.donde[1]}'` : ' (completa)');
  const conteos = [...consultasDe(fase).map(desc), ...RESERVADAS.map((n) => `${n} (completa)`)];
  return [
    '',
    `Vas a acceder a PRODUCCIÓN: proyecto ${PROYECTO}. No se escribe nada.`,
    '',
    `Paso 1, conteos (${conteos.length} consultas count):`,
    ...conteos.map((c) => `  · ${c}`),
    '  Los conteos también generan lecturas: al menos 1 por consulta, y 1 por',
    '  cada 1000 documentos contados.',
    '',
    `Paso 2, solo con una segunda confirmación ("${FRASE_LEER}"): leer los`,
    '  documentos de esas consultas (solo los campos listados en el script),',
    '  los documentos a los que apuntan y, por cada cuenta con hogares de paso',
    '  viejos o sin fecha, si tiene algún animal personal (1 lectura).',
    '  Nunca más de --max-documentos documentos.',
    '',
  ].join('\n');
}

/**
 * Lectura y análisis, con sus controles. En producción hay DOS
 * confirmaciones: una antes de cualquier consulta (incluidos los conteos) y
 * otra, ya con la estimación a la vista, antes de leer documentos. Recibe la
 * base y la confirmación por parámetro para poder probar el flujo entero con
 * una base falsa.
 */
async function ejecutarDiagnostico({ db, opciones, imprimir, confirmar }) {
  const produccion = opciones.modo === 'produccion';
  if (produccion) {
    imprimir(avisoDeAcceso(opciones.fase));
    const ok = await confirmar(`Para hacer los conteos escribí exactamente "${FRASE_CONTAR}": `, FRASE_CONTAR);
    if (!ok) throw new Error('Cancelado. No se hizo ninguna consulta.');
  }
  const previo = await contarPrevio(db, opciones.fase);
  imprimir(`Estimación: hasta ${previo.estimadas} lecturas de documentos ` +
    `(el conteo previo ya usó unas ${previo.lecturasDelConteo}).`);
  if (previo.estimadas > opciones.maxDocumentos) {
    throw new Error(`La estimación (${previo.estimadas}) supera --max-documentos=${opciones.maxDocumentos}. No se leyó ningún documento.`);
  }
  if (produccion) {
    const ok = await confirmar(`Para leer los documentos escribí exactamente "${FRASE_LEER}": `, FRASE_LEER);
    if (!ok) throw new Error('Cancelado después de los conteos. No se leyó ningún documento.');
  }
  const datos = await recolectar(db, opciones.fase, previo.reservadas, opciones.maxDocumentos);
  const r = analizar(datos);
  imprimir('');
  imprimir(formatear(r, opciones.mostrarIds ? (id) => id : seudonimo));
  return r;
}

async function correr(argv = process.argv.slice(2)) {
  let opciones;
  try {
    opciones = parsearArgs(argv);
  } catch (e) {
    console.error(e.message);
    process.exit(2);
  }
  prepararEntorno(opciones.modo, process.env);

  const fs = require('firebase-admin/firestore');
  const { initializeApp, applicationDefault } = require('firebase-admin/app');
  initializeApp(opciones.modo === 'produccion'
    ? { projectId: PROYECTO, credential: applicationDefault() }
    : { projectId: PROYECTO });
  const db = fs.getFirestore();
  verificarDestino(opciones.modo, db, process.env); // lanza antes de cualquier lectura
  soloLectura(fs);

  console.log(`Diagnóstico de solo lectura contra ${opciones.modo === 'emulador' ? `el EMULADOR (${HOST_EMULADOR})` : 'PRODUCCIÓN'}, proyecto ${PROYECTO}.`);
  if (opciones.modo === 'produccion') console.log(`Credenciales: ${describirCredenciales(process.env)}.`);
  await ejecutarDiagnostico({ db, opciones, imprimir: console.log, confirmar: confirmarEnTerminal });
}

// Solo corre si se lo invoca directo, para que el test pueda requerir el
// módulo sin hablar con Firestore.
if (require.main === module) {
  correr().catch((e) => {
    console.error(e.message);
    process.exit(1);
  });
}

module.exports = {
  PROYECTO, HOST_EMULADOR, FRASE_CONTAR, FRASE_LEER, METODOS_BLOQUEADOS,
  parsearArgs, prepararEntorno, verificarDestino, describirCredenciales,
  soloLectura, consultasDe, contarPrevio, recolectar, analizar, formatear, seudonimo,
  ejecutarDiagnostico, confirmarEnTerminal, avisoDeAcceso,
};
