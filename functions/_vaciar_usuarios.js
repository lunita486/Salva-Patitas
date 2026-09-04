// Borra TODAS las cuentas de la app y sus preferencias. Es el último paso
// de la limpieza previa a Google Play: arrancar la versión pública con la
// base completamente vacía.
//
// **Qué borra.** Todos los `usuarios` y todas las `preferencias`.
//
// **Qué NO borra: las cuentas de Firebase Auth.** Esto vacía lo que la app
// guarda de cada persona, no su registro. Quien vuelva a entrar con Google
// va a poder hacerlo, y `asegurarPerfilBase` le va a crear un documento
// nuevo: la app la va a mandar a elegir rol y armar su perfil de cero, como
// si fuera la primera vez. Es el efecto buscado. Borrar las cuentas de Auth
// es otra operación y no se hace acá.
//
// **Ojo: incluye la cuenta de Eliza.** La próxima vez que entre con
// lunita486@gmail.com va a ver la pantalla de elegir rol.
//
// **Qué queda.** `_eventosProcesados`, la bitácora que usan los triggers
// para no procesar dos veces el mismo evento. No es dato de nadie y se
// limpia sola.
//
// **No escribe nada por defecto.** Sin `--aplicar` solo informa.
//
//   node functions/_vaciar_usuarios.js             (simulacro)
//   node functions/_vaciar_usuarios.js --aplicar   (borra)
//
// Hay un volcado local de la base de antes de todas estas limpiezas en
// ~/Desktop/backup-firestore-2026-09-04.
const APLICAR = process.argv.includes('--aplicar');
const PROYECTO = 'patitas-dd0bb';
const POR_TANDA = 500;

const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

initializeApp({ projectId: PROYECTO });
const db = getFirestore();

const enTandas = (arr, n) => {
  const salida = [];
  for (let i = 0; i < arr.length; i += n) salida.push(arr.slice(i, i + n));
  return salida;
};

(async () => {
  console.log(`${APLICAR ? 'BORRANDO en' : 'SIMULACRO sobre'} producción (${PROYECTO})\n`);

  const [usuarios, preferencias] = await Promise.all([
    db.collection('usuarios').get(), db.collection('preferencias').get(),
  ]);

  console.log(`  usuarios      ${usuarios.size}`);
  console.log(`  preferencias  ${preferencias.size}`);

  const roles = {};
  for (const d of usuarios.docs) {
    const k = (d.data().roles ?? []).slice().sort().join('+') || '(sin roles)';
    roles[k] = (roles[k] ?? 0) + 1;
  }
  console.log('\n  por rol:');
  for (const [k, n] of Object.entries(roles)) console.log(`     ${k.padEnd(24)} ${n}`);

  // Que no quede nada apuntando a estas cuentas. Si aparece algo, es que
  // alguna limpieza anterior dejó cabos sueltos y hay que mirarlo.
  const otras = [];
  for (const c of await db.listCollections()) {
    if (['usuarios', 'preferencias', '_eventosProcesados'].includes(c.id)) continue;
    const n = (await c.get()).size;
    if (n > 0) otras.push(`${c.id} (${n})`);
  }
  if (otras.length) {
    console.log(`\n*** PARÁ: todavía hay datos en ${otras.join(', ')}.`);
    console.log('*** Esas colecciones referencian cuentas. Limpialas primero.');
    process.exit(1);
  }
  console.log('\n  el resto de las colecciones ya está vacío.');

  console.log(`\n  ${usuarios.size + preferencias.size} documentos a borrar.`);

  if (!APLICAR) {
    console.log('\nNo se escribió NADA. Volvé a correrlo con --aplicar.');
    return;
  }

  const refs = [...usuarios.docs, ...preferencias.docs].map((d) => d.ref);
  let n = 0;
  for (const tanda of enTandas(refs, POR_TANDA)) {
    const batch = db.batch();
    for (const ref of tanda) batch.delete(ref);
    await batch.commit();
    n += tanda.length;
  }
  console.log(`\n${n} documentos borrados.`);
  console.log('Las cuentas de Firebase Auth NO se tocaron: quien entre con');
  console.log('Google va a poder, y va a armar su perfil de cero.');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
