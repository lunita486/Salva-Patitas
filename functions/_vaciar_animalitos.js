// Borra TODOS los animalitos que queden y todo lo que cuelga de ellos.
//
// **Por qué existe.** Al publicar en Google Play, Eliza decidió arrancar
// con la base de animalitos vacía: los que quedaban después de
// _limpiar_datos_de_prueba.js eran de los testers, publicados durante el
// desarrollo, y no tienen por qué aparecerle a alguien que instala la app
// el primer día.
//
// **Qué borra.** Todos los `rescates`, y para cada uno:
//   - sus `solicitudes`   (adopción y hogar de paso)
//   - sus `chats` enteros, con la subcolección `mensajes`
//   - sus `favoritos`
//   - su carpeta en Storage, `rescates/{id}/`
//
// Y además los huérfanos: solicitudes, chats y favoritos que apunten a un
// `rescateId` que ya no existe. Quedaban tres de julio, de animalitos
// borrados a mano hace meses.
//
// **Qué NO borra.** Ninguna cuenta de `usuarios`, ni sus perfiles, ni sus
// preferencias. Ni la red de hogares de paso (`hogaresDePaso`), que no
// depende de ningún animalito. Ni los chats de consulta a un aliado, que no
// tienen `rescateId`. Ni `servicios`.
//
// **No escribe nada por defecto.** Sin `--aplicar` solo informa.
//
//   node functions/_vaciar_animalitos.js             (simulacro)
//   node functions/_vaciar_animalitos.js --aplicar   (borra)
//
// Hay un volcado local de la base de antes de todas estas limpiezas en
// ~/Desktop/backup-firestore-2026-09-04 (1000 documentos, 9 colecciones).
const APLICAR = process.argv.includes('--aplicar');
const PROYECTO = 'patitas-dd0bb';
const BUCKET = 'patitas-dd0bb.firebasestorage.app';
const POR_TANDA = 500;

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

  const rescates = (await db.collection('rescates').get()).docs;
  const vivos = new Set(rescates.map((d) => d.id));

  // Como se van TODOS los animalitos, todo lo que tenga un `rescateId` deja
  // de tener sentido, exista o no ese animalito. Por eso no hace falta
  // cruzar por id: alcanza con "tiene rescateId".
  const conRescate = async (coleccion) =>
    (await db.collection(coleccion).get()).docs.filter((d) => {
      const r = d.data().rescateId;
      return typeof r === 'string' && r.length > 0;
    });
  const [solicitudes, chats, favoritos] = await Promise.all([
    conRescate('solicitudes'), conRescate('chats'), conRescate('favoritos'),
  ]);

  let mensajes = 0;
  for (const c of chats) mensajes += (await c.ref.collection('mensajes').get()).size;

  const [archivos] = await getStorage().bucket().getFiles({ prefix: 'rescates/' });

  const huerfanos = {
    solicitudes: solicitudes.filter((d) => !vivos.has(d.data().rescateId)).length,
    chats: chats.filter((d) => !vivos.has(d.data().rescateId)).length,
    favoritos: favoritos.filter((d) => !vivos.has(d.data().rescateId)).length,
  };

  console.log(`  rescates      ${rescates.length}`);
  console.log(`  solicitudes   ${solicitudes.length}   (${huerfanos.solicitudes} ya eran huérfanas)`);
  console.log(`  chats         ${chats.length}   (${huerfanos.chats} huérfanos, con ${mensajes} mensajes en total)`);
  console.log(`  favoritos     ${favoritos.length}   (${huerfanos.favoritos} huérfanos)`);
  console.log(`  fotos         ${archivos.length}`);

  // Lo que queda en pie, para que se vea que no se toca.
  const [usuarios, hogares, servicios, todosChats] = await Promise.all([
    db.collection('usuarios').get(), db.collection('hogaresDePaso').get(),
    db.collection('servicios').get(), db.collection('chats').get(),
  ]);
  const consultas = todosChats.docs.length - chats.length;
  console.log('\n  quedan en pie:');
  console.log(`     usuarios      ${usuarios.size}`);
  console.log(`     hogaresDePaso ${hogares.size}`);
  console.log(`     servicios     ${servicios.size}`);
  console.log(`     chats sin rescateId (consultas a aliados)  ${consultas}`);

  const total = rescates.length + solicitudes.length + chats.length + favoritos.length;
  console.log(`\n  ${total} documentos + ${archivos.length} archivos de Storage.`);

  if (!APLICAR) {
    console.log('\nNo se escribió NADA. Volvé a correrlo con --aplicar.');
    return;
  }

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

  // onRescateEliminado también las borra; acá se hace igual para poder
  // verificarlo en el momento, sin esperar a un trigger asíncrono. Los
  // "No such object" son normales: significa que el trigger llegó primero.
  let f = 0;
  for (const a of archivos) {
    try { await a.delete(); f++; } catch (_) { /* ya lo borró el trigger */ }
  }
  console.log(`  ${f} archivos de Storage borrados por el script (el resto los borró el trigger)`);

  console.log(`\n${n + chats.length} documentos borrados.`);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
