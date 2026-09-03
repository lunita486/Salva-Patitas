// Borra los animalitos de las cuentas que se usaron para desarrollar, y
// TODO lo que cuelga de ellos. Es la limpieza previa a publicar en Google
// Play: la base traía tres meses de pruebas mezcladas con los animalitos de
// los testers de verdad, y un usuario nuevo los veía todos en el feed.
//
// **Qué se borra.** Los `rescates` de estas tres cuentas, elegidas a mano
// por Eliza, y para cada uno:
//   - sus `solicitudes`   (adopción y hogar de paso)
//   - sus `chats` enteros, con la subcolección `mensajes`
//   - sus `favoritos`
//   - su carpeta en Storage, `rescates/{id}/`
//
// **Qué NO se borra.** Los animalitos de las otras 9 cuentas: Salva
// Mininos, Henning Lange, Dario Bertuccelli, Sandra Milena Tumble, David
// casas jimenez, marta maria jimenez, Karen Cancino, Edith Lange y
// 5hZLN7ws. Ni sus solicitudes, ni sus chats, ni sus fotos. Tampoco se toca
// ninguna cuenta de `usuarios`, ni los chats de consulta a un aliado (esos
// no tienen `rescateId`).
//
// **Favoritos y Storage se borran ACÁ, a propósito**, aunque
// onRescateEliminado ya lo haga. Ese trigger es asíncrono y de "al menos
// una vez": con 111 borrados de golpe no hay forma de saber desde acá si
// todos corrieron. Borrarlo también en el script lo vuelve verificable en
// el momento. Es idempotente: borrar algo que ya no está no falla.
//
// **No escribe nada por defecto.** Sin `--aplicar` solo informa.
//
//   node functions/_limpiar_datos_de_prueba.js             (simulacro)
//   node functions/_limpiar_datos_de_prueba.js --aplicar   (borra)
//
// Hay un volcado local de la base entera de antes de esta limpieza en
// ~/Desktop/backup-firestore-2026-09-04 (1000 documentos, 9 colecciones).
const APLICAR = process.argv.includes('--aplicar');
const PROYECTO = 'patitas-dd0bb';
const BUCKET = 'patitas-dd0bb.firebasestorage.app';

// Las tres cuentas, con el número de animalitos que tenían al decidirse
// esto. Si no coincide, algo cambió y el script para sin escribir: no se
// borra a ciegas una cuenta que creció o se achicó desde entonces.
const CUENTAS = [
  { uid: 'jqElNvVgfGMfSZpttHaTvSTbRax1', nombre: 'Alberguito domingo', esperados: 66 },
  { uid: 'bFHZ7SCMZbMsgxWwwaZI9oSzhk62', nombre: 'Tierheim Bremerhaven', esperados: 36 },
  { uid: 'poClFoN65UPWcWnYNcZa7Y6I5Rh2', nombre: 'Carmen Lucia Jimenez Hincapie', esperados: 9 },
];

const POR_TANDA = 500;
const POR_IN = 30; // tope de Firestore para un `where in`

const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');

initializeApp({ projectId: PROYECTO, storageBucket: BUCKET });
const db = getFirestore();

const enTandas = (arr, n) => {
  const salida = [];
  for (let i = 0; i < arr.length; i += n) salida.push(arr.slice(i, i + n));
  return salida;
};

(async () => {
  console.log(`${APLICAR ? 'BORRANDO en' : 'SIMULACRO sobre'} producción (${PROYECTO})\n`);

  // 1) Los animalitos de esas cuentas.
  const todos = await db.collection('rescates').get();
  const rescates = [];
  for (const c of CUENTAS) {
    const suyos = todos.docs.filter((d) => d.data().rescatistaId === c.uid);
    console.log(`  ${c.nombre.padEnd(32)} ${String(suyos.length).padStart(3)} animalitos (esperados ${c.esperados})`);
    if (suyos.length !== c.esperados) {
      console.log('\n*** PARÁ: la cantidad no coincide con la que se aprobó.');
      console.log('*** Volvé a mirar la lista antes de borrar nada.');
      process.exit(1);
    }
    rescates.push(...suyos);
  }
  console.log(`\n  ${todos.size} animalitos en total, ${rescates.length} a borrar, ${todos.size - rescates.length} quedan.\n`);

  const ids = rescates.map((d) => d.id);
  const idsSet = new Set(ids);

  // 2) Lo que cuelga de ellos.
  const colgando = async (coleccion) => {
    const salida = [];
    for (const tanda of enTandas(ids, POR_IN)) {
      const snap = await db.collection(coleccion).where('rescateId', 'in', tanda).get();
      salida.push(...snap.docs);
    }
    return salida;
  };
  const [solicitudes, chats, favoritos] = await Promise.all([
    colgando('solicitudes'), colgando('chats'), colgando('favoritos'),
  ]);

  let mensajes = 0;
  for (const c of chats) mensajes += (await c.ref.collection('mensajes').get()).size;

  // 3) Sus fotos.
  const [archivos] = await getStorage().bucket().getFiles({ prefix: 'rescates/' });
  const fotos = archivos.filter((f) => {
    const m = f.name.match(/^rescates\/([^/]+)\//);
    return m && idsSet.has(m[1]);
  });
  const bytes = fotos.reduce((a, f) => a + Number(f.metadata.size || 0), 0);

  console.log('  cuelga de ellos:');
  console.log(`     solicitudes  ${solicitudes.length}`);
  console.log(`     chats        ${chats.length}   (con ${mensajes} mensajes adentro)`);
  console.log(`     favoritos    ${favoritos.length}`);
  console.log(`     fotos        ${fotos.length}   (${(bytes / 1024 / 1024).toFixed(1)} MB)`);

  const total = rescates.length + solicitudes.length + chats.length + favoritos.length;
  console.log(`\n  ${total} documentos + ${fotos.length} archivos de Storage.`);

  if (!APLICAR) {
    console.log('\nNo se escribió NADA. Volvé a correrlo con --aplicar.');
    return;
  }

  // 4) Borrado. Los chats primero y de a uno: tienen subcolección, así que
  //    necesitan recursiveDelete y no entran en un batch.
  for (const c of chats) await db.recursiveDelete(c.ref);
  console.log(`\n  ${chats.length} chats borrados (con sus mensajes)`);

  const refs = [...rescates, ...solicitudes, ...favoritos].map((d) => d.ref);
  let n = 0;
  for (const tanda of enTandas(refs, POR_TANDA)) {
    const batch = db.batch();
    for (const ref of tanda) batch.delete(ref);
    await batch.commit();
    n += tanda.length;
    console.log(`  tanda de ${tanda.length}: hecha (${n}/${refs.length})`);
  }

  // 5) Las fotos. De a una: son pocas y así un fallo no se lleva al resto.
  let f = 0;
  for (const foto of fotos) {
    try { await foto.delete(); f++; } catch (e) { console.error(`  no se pudo borrar ${foto.name}: ${e.message}`); }
  }
  console.log(`  ${f} archivos de Storage borrados`);

  console.log(`\n${n + chats.length} documentos y ${f} archivos borrados.`);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
