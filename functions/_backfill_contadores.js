// Inicializa los contadores de perfil en las cuentas que ya existen, para
// los dos roles que los llevan (rescatista y albergue).
//
// **Por qué hace falta.** El trigger onRescateContado mantiene los números
// al día de acá en adelante, pero solo se despierta cuando alguien da de
// alta, borra o cambia el estado de un animalito. Una cuenta que hoy tiene
// 54 animalitos y no toca ninguno nunca tendría los campos, y su perfil se
// quedaría cayendo al count() de siempre. Esto los siembra de una vez.
//
// **No escribe nada por defecto.** Sin `--aplicar` solo imprime qué haría.
//
//   node functions/_backfill_contadores.js                  (simulacro, producción)
//   node functions/_backfill_contadores.js --aplicar        (escribe en producción)
//   node functions/_backfill_contadores.js --emulador       (contra el sandbox)
//
// Contra producción usa las credenciales de gcloud (ADC). Si no las tenés:
//   gcloud auth application-default login
//
// **Es seguro correrlo dos veces.** Cuenta y compara: a una cuenta que ya
// tiene los números correctos no le escribe nada. Y como cuenta con la
// MISMA función que el trigger (contarDe), no puede dejar cifras que el
// trigger después contradiga.
//
// A quién alcanza: la UNIÓN de dos conjuntos
// ------------------------------------------
// Este script buscaba las cuentas solo por su campo `roles`, y eso dejaba
// afuera un caso REAL de producción.
//
// El rol que hace falta para publicar se valida UNA vez, al crear el
// animalito (firestore.rules). Después, el `creadoPor` del animalito no se
// puede cambiar nunca más, pero el `roles` de la cuenta sí se mueve. Y se
// mueve de verdad: 'albergue' y 'rescatista' son MUTUAMENTE EXCLUYENTES en
// el onboarding (ver _rolesExclusivos en seleccion_rol_screen.dart), así
// que una cuenta que publicó con un sombrero y después eligió el otro
// conserva los animalitos viejos y pierde el rol con el que los publicó.
//
// En producción hay al menos una cuenta así: 29 animalitos con
// `creadoPor: 'rescatista'` y 7 con `creadoPor: 'albergue'`, cuando el
// modelo de roles hace imposible tener los dos roles a la vez. Con la
// selección por `roles`, uno de sus dos pares de contadores no se sembraba
// nunca.
//
// Por eso ahora se recorren los dos conjuntos y se unen:
//
//   · los pares {cuenta, rol} que salen de los ANIMALITOS que existen,
//     mirando `creadoPor` — la MISMA fuente de verdad que usa el trigger,
//     que tampoco mira `roles`;
//   · los pares que salen de `roles`, para que una cuenta con el rol y sin
//     ningún animalito igual reciba su 0, que es la respuesta correcta y
//     le evita caer al count() para siempre.
//
// Ninguno de los dos alcanza solo. El primero se pierde las cuentas
// vacías; el segundo se pierde las que perdieron el rol.
const APLICAR = process.argv.includes('--aplicar');
const EMULADOR = process.argv.includes('--emulador');
const PROYECTO = 'patitas-dd0bb';

if (EMULADOR) process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8097';

const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const {
  DEFINICIONES,
  contadoresDesactualizados,
} = require('./contadores_logica');
const { contarDe } = require('./contadores');

const ROLES = DEFINICIONES.map((d) => d.rol);

/**
 * Separador de la clave "uid + rol". Es NUL a propósito: un uid de
 * Firebase es alfanumérico, así que este carácter no puede aparecer
 * adentro de uno y el par nunca se puede partir mal.
 */
const SEP = '\u0000';
const clave = (uid, rol) => `${uid}${SEP}${rol}`;

/**
 * Une los pares que vienen de los animalitos con los que vienen de los
 * roles, y los agrupa por cuenta.
 *
 * Devuelve una lista de `{ uid, roles: [{ rol, origen }] }`, ordenada por
 * uid y por rol para que dos corridas impriman lo mismo. `origen` es
 * 'animalitos', 'roles' o 'ambos', y existe solo para que el simulacro deje
 * ver CUÁLES son los que la versión anterior se salteaba.
 *
 * Pura a propósito: es la parte que se puede equivocar y la única que se
 * puede probar sin una base de datos.
 */
function unirPares({ deAnimales, deRoles }) {
  const porUid = new Map();
  const anotar = (par, origen) => {
    const [uid, rol] = par.split(SEP);
    if (!porUid.has(uid)) porUid.set(uid, new Map());
    const roles = porUid.get(uid);
    roles.set(rol, roles.has(rol) && roles.get(rol) !== origen ? 'ambos' : origen);
  };

  for (const par of deAnimales) anotar(par, 'animalitos');
  for (const par of deRoles) anotar(par, 'roles');

  return [...porUid.entries()]
      .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
      .map(([uid, roles]) => ({
        uid,
        roles: [...roles.entries()]
            .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
            .map(([rol, origen]) => ({ rol, origen })),
      }));
}

/**
 * Los pares {cuenta, rol} que salen de los animalitos que existen hoy.
 *
 * `select()` trae solo esos dos campos, no el documento entero: con la
 * colección creciendo sin techo, la diferencia entre proyectar dos campos y
 * bajar cada animalito con su descripción y sus fotos es enorme. Y
 * `stream()` va de a tandas solo, sin cursores a mano y sin cargar todo en
 * memoria.
 */
async function paresDesdeAnimales(db) {
  const pares = new Set();
  const cursor = db.collection('rescates')
      .select('rescatistaId', 'creadoPor')
      .stream();
  for await (const doc of cursor) {
    const { rescatistaId, creadoPor } = doc.data();
    if (!ROLES.includes(creadoPor)) continue;
    if (typeof rescatistaId !== 'string' || rescatistaId === '') continue;
    pares.add(clave(rescatistaId, creadoPor));
  }
  return pares;
}

/** Los pares que salen del campo `roles` de cada cuenta. */
async function paresDesdeRoles(db) {
  const pares = new Set();
  // Sin orderBy y sin cursor a mano: un `array-contains-any` suelto se
  // resuelve con el índice automático del campo, y stream() se ocupa de
  // recorrerlo entero.
  const cursor = db.collection('usuarios')
      .where('roles', 'array-contains-any', ROLES)
      .stream();
  for await (const doc of cursor) {
    for (const rol of doc.data().roles || []) {
      if (ROLES.includes(rol)) pares.add(clave(doc.id, rol));
    }
  }
  return pares;
}

/** "54/3", o "(sin dato)/(sin dato)" para lo que todavía no existe. */
function mostrar(datos, campos) {
  return campos.map((c) => datos[c] ?? '(sin dato)').join('/');
}

async function correr() {
  initializeApp({ projectId: PROYECTO });
  const db = getFirestore();

  const destino = EMULADOR ? 'EL EMULADOR' : `producción (${PROYECTO})`;
  console.log(`${APLICAR ? 'Escribiendo en' : 'SIMULACRO sobre'} ${destino}\n`);

  const [deAnimales, deRoles] = await Promise.all([
    paresDesdeAnimales(db),
    paresDesdeRoles(db),
  ]);
  const cuentas = unirPares({ deAnimales, deRoles });

  const soloPorAnimalitos = cuentas.flatMap((c) =>
    c.roles.filter((r) => r.origen === 'animalitos').map((r) => `${c.uid} (${r.rol})`),
  );
  console.log(
      `${deAnimales.size} pares desde animalitos, ${deRoles.size} desde roles`
      + ` -> ${cuentas.length} cuentas.`,
  );
  if (soloPorAnimalitos.length > 0) {
    // Estos son exactamente los que la versión anterior de este script se
    // salteaba: tienen animalitos publicados bajo un rol que su cuenta ya
    // no declara.
    console.log(
        `\n${soloPorAnimalitos.length} par(es) que SOLO aparecen por sus animalitos,`
        + ' no por su campo roles:',
    );
    for (const linea of soloPorAnimalitos) console.log(`  · ${linea}`);
  }
  console.log('');

  let sinPerfil = 0;
  let cambiarian = 0;
  let escritas = 0;

  for (const cuenta of cuentas) {
    const ref = db.collection('usuarios').doc(cuenta.uid);
    const snap = await ref.get();
    if (!snap.exists) {
      // Cuenta borrada cuyos animalitos sobrevivieron. No se crea el
      // documento: uno que exista con solo contadores adentro dejaría a esa
      // persona sin onboarding (ver el comentario de recontar()).
      sinPerfil++;
      continue;
    }
    const actual = snap.data();

    // Los contadores de CADA rol del par, calculados con la misma función
    // que usa el trigger, y escritos todos juntos en una sola actualización.
    let nuevos = {};
    for (const { rol } of cuenta.roles) {
      nuevos = { ...nuevos, ...await contarDe(db, { uid: cuenta.uid, rol }) };
    }
    if (Object.keys(nuevos).length === 0) continue;
    if (!contadoresDesactualizados(actual, nuevos)) continue;

    cambiarian++;
    const campos = Object.keys(nuevos);
    const roles = cuenta.roles.map((r) => `${r.rol} por ${r.origen}`).join(', ');
    console.log(`  ${cuenta.uid}  [${roles}]`);
    console.log(`      ${campos.join(', ')}`);
    console.log(`      ${mostrar(actual, campos)}  ->  ${mostrar(nuevos, campos)}`);

    if (APLICAR) {
      // update y no set(merge): el documento existe (lo acabamos de leer), y
      // así esto tampoco puede crear perfiles fantasma. Mismo criterio que
      // el trigger.
      await ref.update(nuevos);
      escritas++;
    }
  }

  console.log(`\n${cuentas.length} cuentas miradas, ${cambiarian} desactualizadas.`);
  if (sinPerfil > 0) {
    console.log(`${sinPerfil} sin documento de perfil (salteadas, no se crean).`);
  }
  if (APLICAR) {
    console.log(`${escritas} escritas.`);
  } else if (cambiarian > 0) {
    console.log('No se escribió nada. Volvé a correrlo con --aplicar.');
  }
}

// Solo corre si se lo invoca directo. Así el test puede requerir este
// archivo para probar unirPares() sin que el script se ejecute ni intente
// hablar con Firestore.
if (require.main === module) {
  correr().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}

module.exports = { unirPares, clave, ROLES };
