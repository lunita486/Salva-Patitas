// Borra los animalitos de la prueba de paginación y lo que quedaría
// colgando de ellos. NADA MÁS: ni un documento de más.
//
// **Qué borra.**
//   - los 55 `rescates` llamados "TEST-paginación NN"
//   - las 2 `solicitudes` que apuntan a esos rescates
//   - el 1 `chat` que apunta a esos rescates
//
// **Por qué.** Los 55 se crearon el 2026-08-05 a las 17:38, todos en el
// mismo minuto, desde una sola cuenta y sin ninguna foto, para probar que
// el feed paginara bien con más de 50 animalitos. No son animales reales.
// El problema es que SÍ salen en el feed: de los 151 que ve alguien que
// instala la app hoy, 55 son estos. Antes de publicar en Google Play hay
// que sacarlos.
//
// **Por qué también las solicitudes y el chat.** `onRescateEliminado` (ver
// index.js) limpia solo las fotos de Storage y los `favoritos`. Las
// solicitudes y los chats NO los toca, así que quedarían apuntando a un
// animalito que ya no existe. Las 2 solicitudes son de Eliza, las dos
// `pendiente`; el chat tiene CERO mensajes (ni siquiera se ve en la lista,
// que esconde los chats sin vista previa). Los tres son datos de la misma
// prueba.
//
// **Lo que se limpia solo, y no hace falta pedirlo acá:**
//   - las fotos de Storage: ninguno de los 55 tiene, igual el trigger las
//     borraría
//   - los 107 `favoritos`: los borra onRescateEliminado
//   - los contadores del dueño: onRescateContado recuenta con cada borrado.
//     Dario Bertuccelli pasa de 58 a 3, que son sus animalitos de verdad.
//     Es lo correcto: los otros 55 nunca debieron contar.
//
// **No escribe nada por defecto.** Sin `--aplicar` solo informa.
//
//   node functions/_limpiar_test_paginacion.js             (simulacro)
//   node functions/_limpiar_test_paginacion.js --aplicar   (borra)
//
// Contra producción usa las credenciales del CLI de Firebase (ADC).
//
// **Es seguro correrlo dos veces.** Solo borra lo que todavía existe; si ya
// se corrió, la segunda vez no encuentra nada y no escribe.
//
// Mismo criterio que _limpiar_logo_duplicado.js: LA MISMA consulta y LA
// MISMA comprobación en los dos modos, para que el simulacro muestre
// exactamente lo que va a pasar. Ahí se aprendió por qué importa: una
// optimización que solo estaba en la rama de `--aplicar` se llevó puesta la
// comprobación de existencia y escribió en 187 documentos en vez de 73.
const APLICAR = process.argv.includes('--aplicar');
const PROYECTO = 'patitas-dd0bb';

// El nombre exacto que puso el script de siembra. El `\d+` y los acentos
// van a propósito: un animalito de verdad que se llame "test" o "TEST algo"
// NO entra acá.
const PATRON = /^TEST-paginación \d+$/;
const POR_TANDA = 500;

const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

initializeApp({ projectId: PROYECTO });
const db = getFirestore();

/// Firestore acepta como mucho 30 valores en un `where in`.
const enTandas = (arr, n) => {
  const salida = [];
  for (let i = 0; i < arr.length; i += n) salida.push(arr.slice(i, i + n));
  return salida;
};

(async () => {
  console.log(`${APLICAR ? 'BORRANDO en' : 'SIMULACRO sobre'} producción (${PROYECTO})\n`);

  // 1) Los rescates. Se traen TODOS y se filtra en cliente: son menos de
  //    200 y así el patrón es exactamente el mismo que se muestra en el
  //    simulacro, sin depender de cómo Firestore ordene un rango de texto.
  const todos = await db.collection('rescates').get();
  const rescates = todos.docs.filter((d) => PATRON.test(String(d.data().nombre ?? '').trim()));
  console.log(`${todos.size} animalitos mirados. ${rescates.length} son de la prueba de paginación.`);

  if (rescates.length === 0) {
    console.log('\nNo hay nada que borrar.');
    return;
  }

  // 2) Que sean el MISMO lote. Si esto no cuadra, algo cambió y hay que
  //    mirarlo a mano antes de borrar nada.
  const duenios = new Set(rescates.map((d) => d.data().rescatistaId));
  const conFoto = rescates.filter((d) => d.data().fotoUrl).length;
  console.log(`   dueños distintos: ${duenios.size}   con foto: ${conFoto}`);
  if (duenios.size !== 1 || conFoto !== 0) {
    console.log('\n*** PARÁ: no tienen la forma esperada (un solo dueño, sin fotos).');
    console.log('*** Revisalo a mano antes de borrar.');
    return;
  }

  // 3) Lo que colgaría de ellos. onRescateEliminado NO borra esto.
  const ids = rescates.map((d) => d.id);
  const colgando = async (coleccion) => {
    const encontrados = [];
    for (const tanda of enTandas(ids, 30)) {
      const snap = await db.collection(coleccion).where('rescateId', 'in', tanda).get();
      encontrados.push(...snap.docs);
    }
    return encontrados;
  };
  const [solicitudes, chats] = await Promise.all([colgando('solicitudes'), colgando('chats')]);

  console.log(`\nQuedarían colgando, así que también se borran:`);
  console.log(`   ${solicitudes.length} solicitudes`);
  for (const d of solicitudes) {
    console.log(`      ${d.id}  "${d.data().animalNombre}"  ${d.data().estado}`);
  }
  console.log(`   ${chats.length} chats`);
  for (const d of chats) {
    const msgs = await d.ref.collection('mensajes').get();
    console.log(`      ${d.id}  "${d.data().animalNombre}"  ${msgs.size} mensajes`);
    if (msgs.size > 0) {
      console.log('\n*** PARÁ: ese chat tiene mensajes de verdad. Revisalo a mano.');
      return;
    }
  }

  console.log('\nSe limpian solos (onRescateEliminado / onRescateContado):');
  console.log('   los favoritos, las fotos de Storage y los contadores del dueño.');

  const total = rescates.length + solicitudes.length + chats.length;

  if (!APLICAR) {
    console.log('\n--- los rescates ---');
    for (const d of rescates) console.log(`   ${d.id}  ${d.data().nombre}`);
    console.log(`\nSe borrarían ${total} documentos en total.`);
    console.log('No se escribió NADA. Volvé a correrlo con --aplicar.');
    return;
  }

  // 4) Borrado. En tandas de 500, que es el tope duro de un WriteBatch;
  //    cada tanda que termina queda escrita de verdad aunque una posterior
  //    falle. Los chats se borran de a uno porque un chat con
  //    subcolección necesita recursiveDelete, no un batch.
  for (const c of chats) {
    await db.recursiveDelete(c.ref);
    console.log(`   chat ${c.id}: borrado`);
  }
  const refs = [...rescates, ...solicitudes].map((d) => d.ref);
  let n = 0;
  for (const tanda of enTandas(refs, POR_TANDA)) {
    const batch = db.batch();
    for (const ref of tanda) batch.delete(ref);
    await batch.commit();
    n += tanda.length;
    console.log(`   tanda de ${tanda.length}: hecha (${n}/${refs.length})`);
  }
  console.log(`\n${n + chats.length} documentos borrados.`);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
