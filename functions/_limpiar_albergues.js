// Borra las cuentas de albergue de prueba y les saca los datos de albergue
// a las que se quedan. Cierra la limpieza previa a Google Play.
//
// **Qué borra: 3 cuentas enteras.**
//   jqElNvVg…  "Alberguito domingo"   roles: ['albergue']
//   d9m1t6sT…  "Salva Mininos"        roles: ['albergue']
//   DpnGvscU…  ex "tu pet shop"       quedó sin roles al sacarle el aliado
//   con sus `preferencias`.
//
// **Qué NO borra: la cuenta de Eliza.** `bFHZ7SCM…` tiene datos de albergue
// ("Tierheim Bremerhaven", su logo y sus contadores) pero sus roles son
// adoptante y rescatista. Borrarla entera la dejaría sin perfil y la
// mandaría a elegir rol de nuevo. Se le sacan solo los campos del albergue.
//
// **Qué NO se toca.** Las otras 19 cuentas, que son de testers sin rol de
// albergue.
//
// **El logo del albergue no está en Storage.** Va en base64 en
// `usuarios/{uid}.fotoBase64`, así que se borra sacando el campo o
// borrando el documento. El bucket ya quedó vacío.
//
// **No escribe nada por defecto.** Sin `--aplicar` solo informa.
//
//   node functions/_limpiar_albergues.js             (simulacro)
//   node functions/_limpiar_albergues.js --aplicar   (borra)
//
// Hay un volcado local de la base de antes de todas estas limpiezas en
// ~/Desktop/backup-firestore-2026-09-04.
const APLICAR = process.argv.includes('--aplicar');
const PROYECTO = 'patitas-dd0bb';

// Las cuentas a borrar, con el nombre que tenían al decidirse esto. Si no
// coincide, el script para: no se borra a ciegas una cuenta que cambió.
const A_BORRAR = [
  { uid: 'jqElNvVgfGMfSZpttHaTvSTbRax1', esperado: 'Alberguito domingo' },
  { uid: 'd9m1t6sTviYYaV9Z1YwQhcEBAvI3', esperado: 'Salva Mininos' },
  { uid: 'DpnGvscUeqdG521U9mTiSVkxRR62', esperado: null }, // ex aliado, sin albergueNombre
];

// La cuenta que se queda, sin su parte de albergue.
const A_LIMPIAR = 'bFHZ7SCMZbMsgxWwwaZI9oSzhk62';

// Lo que la app escribe para un albergue. `fotoBase64` es el logo; ojo que
// ese campo NO es la foto personal (esa es `foto`, que viene de Google y no
// se toca).
const CAMPOS_ALBERGUE = [
  'albergueNombre', 'albergueTipo', 'albergueTelefono', 'albergueEmail',
  'albergueDireccion', 'albergueCiudad', 'albergueCiudadVerificada',
  'albergueSitioWeb', 'albergueDescripcion', 'fotoBase64',
  'capacidadTotal', 'contadorAlbergueEnCuidado', 'contadorAlbergueAdoptados',
];

const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

initializeApp({ projectId: PROYECTO });
const db = getFirestore();

(async () => {
  console.log(`${APLICAR ? 'BORRANDO en' : 'SIMULACRO sobre'} producción (${PROYECTO})\n`);

  console.log('--- cuentas a BORRAR ---');
  const borrar = [];
  for (const c of A_BORRAR) {
    const doc = await db.collection('usuarios').doc(c.uid).get();
    if (!doc.exists) { console.log(`  ${c.uid.slice(0, 14)}  ya no existe, se saltea`); continue; }
    const u = doc.data();
    console.log(`  ${c.uid.slice(0, 14)}  ${u.nombre ?? '?'}  "${u.albergueNombre ?? '(sin albergue)'}"  roles=${JSON.stringify(u.roles ?? [])}`);
    if (c.esperado !== null && u.albergueNombre !== c.esperado) {
      console.log(`\n*** PARÁ: esperaba "${c.esperado}" y encontré "${u.albergueNombre}".`);
      process.exit(1);
    }
    borrar.push(doc);
  }

  console.log('\n--- cuenta a LIMPIAR (no se borra) ---');
  const doc = await db.collection('usuarios').doc(A_LIMPIAR).get();
  const u = doc.data();
  const tiene = CAMPOS_ALBERGUE.filter((c) => u[c] !== undefined);
  console.log(`  ${A_LIMPIAR.slice(0, 14)}  ${u.nombre}  ${u.email ?? ''}`);
  console.log(`     roles ${JSON.stringify(u.roles ?? [])}  <- no se tocan`);
  console.log(`     se le sacan ${tiene.length} campos: ${tiene.join(', ')}`);

  // Las preferencias de las cuentas que se van.
  const prefs = [];
  for (const d of borrar) {
    const p = await db.collection('preferencias').doc(d.id).get();
    if (p.exists) prefs.push(p);
  }
  console.log(`\n--- preferencias de esas cuentas: ${prefs.length} ---`);

  console.log(`\n  ${borrar.length} cuentas + ${prefs.length} preferencias a borrar, 1 cuenta a limpiar.`);

  if (!APLICAR) {
    console.log('\nNo se escribió NADA. Volvé a correrlo con --aplicar.');
    return;
  }

  const batch = db.batch();
  for (const d of borrar) batch.delete(d.ref);
  for (const p of prefs) batch.delete(p.ref);
  const cambios = {};
  for (const c of CAMPOS_ALBERGUE) cambios[c] = FieldValue.delete();
  batch.update(doc.ref, cambios);
  await batch.commit();

  console.log(`\n${borrar.length} cuentas y ${prefs.length} preferencias borradas.`);
  console.log('1 cuenta limpiada de datos de albergue, sin borrarla.');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
