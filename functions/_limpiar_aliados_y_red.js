// Borra los negocios aliados y la red de hogares de paso, antes de
// publicar en Google Play. Es la última tanda de la limpieza de datos de
// prueba, después de _vaciar_animalitos.js.
//
// **Qué borra.**
//   - todos los `chats` de tipo `consulta_aliado`, con sus `mensajes`
//   - todos los `servicios`
//   - los datos de aliado DENTRO de `usuarios`: los 9 campos `aliado*`
//     (incluida `aliadoFotoBase64`, que es donde vive la foto del negocio)
//     y el rol 'aliado' de `roles`
//   - todas las filas de `hogaresDePaso`, la red del albergue
//
// **Qué NO borra: ninguna cuenta.** Los documentos de `usuarios` se
// quedan, solo pierden su parte de aliado. Nadie pierde el acceso ni sus
// otros roles. Ojo con una: la única cuenta cuyo ÚNICO rol era 'aliado'
// queda con `roles: []`, así que la app la va a mandar a elegir rol la
// próxima vez que entre (ver resolverPantallaPerfil). Es un estado
// previsto, no un error.
//
// **La foto del aliado no está en Storage.** Va en base64 dentro del doc
// del usuario, así que se borra sacando el campo. El bucket ya quedó
// vacío con _vaciar_animalitos.js.
//
// **No escribe nada por defecto.** Sin `--aplicar` solo informa.
//
//   node functions/_limpiar_aliados_y_red.js             (simulacro)
//   node functions/_limpiar_aliados_y_red.js --aplicar   (borra)
//
// Hay un volcado local de la base de antes de todas estas limpiezas en
// ~/Desktop/backup-firestore-2026-09-04.
const APLICAR = process.argv.includes('--aplicar');
const PROYECTO = 'patitas-dd0bb';
const POR_TANDA = 500;

// Los 9 campos que la app escribe para un aliado. Se sacan todos: dejar
// uno solo (la foto, el teléfono) haría que el perfil quedara a medias.
const CAMPOS_ALIADO = [
  'aliadoNombre', 'aliadoTipo', 'aliadoTelefono', 'aliadoEmail',
  'aliadoDireccion', 'aliadoCiudad', 'aliadoCiudadVerificada',
  'aliadoSitioWeb', 'aliadoFotoBase64',
];

const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

initializeApp({ projectId: PROYECTO });
const db = getFirestore();

const enTandas = (arr, n) => {
  const salida = [];
  for (let i = 0; i < arr.length; i += n) salida.push(arr.slice(i, i + n));
  return salida;
};

(async () => {
  console.log(`${APLICAR ? 'BORRANDO en' : 'SIMULACRO sobre'} producción (${PROYECTO})\n`);

  const [chatsTodos, servicios, usuarios, hogares] = await Promise.all([
    db.collection('chats').get(), db.collection('servicios').get(),
    db.collection('usuarios').get(), db.collection('hogaresDePaso').get(),
  ]);

  const consultas = chatsTodos.docs.filter((d) => d.data().tipoSolicitud === 'consulta_aliado');
  let mensajes = 0;
  for (const c of consultas) mensajes += (await c.ref.collection('mensajes').get()).size;

  // Las cuentas con algo de aliado: o el rol, o cualquiera de los campos.
  const conAliado = usuarios.docs.filter((d) => {
    const u = d.data();
    return (u.roles ?? []).includes('aliado') || CAMPOS_ALIADO.some((c) => u[c] !== undefined);
  });

  console.log(`  chats consulta_aliado   ${consultas.length}   (con ${mensajes} mensajes)`);
  console.log(`  otros chats             ${chatsTodos.size - consultas.length}   (no se tocan)`);
  console.log(`  servicios               ${servicios.size}`);
  console.log(`  hogaresDePaso           ${hogares.size}`);
  console.log(`\n  cuentas con datos de aliado: ${conAliado.length}`);
  for (const d of conAliado) {
    const u = d.data();
    const tiene = CAMPOS_ALIADO.filter((c) => u[c] !== undefined);
    const rolesDespues = (u.roles ?? []).filter((r) => r !== 'aliado');
    const foto = u.aliadoFotoBase64 ? `${Math.round(u.aliadoFotoBase64.length / 1024)} KB de foto` : 'sin foto';
    console.log(`     ${d.id.slice(0, 14)}  ${JSON.stringify(u.aliadoNombre ?? u.nombre)}`);
    console.log(`        se le sacan ${tiene.length} campos (${foto})`);
    console.log(`        roles: ${JSON.stringify(u.roles ?? [])} -> ${JSON.stringify(rolesDespues)}`);
    if (rolesDespues.length === 0) {
      console.log('        *** queda SIN roles: la app la va a mandar a elegir rol');
    }
  }

  const total = consultas.length + servicios.size + hogares.size;
  console.log(`\n  ${total} documentos a borrar, ${conAliado.length} cuentas a limpiar (sin borrarlas).`);

  if (!APLICAR) {
    console.log('\nNo se escribió NADA. Volvé a correrlo con --aplicar.');
    return;
  }

  for (const c of consultas) await db.recursiveDelete(c.ref);
  console.log(`\n  ${consultas.length} chats de consulta borrados (con sus mensajes)`);

  const refs = [...servicios.docs, ...hogares.docs].map((d) => d.ref);
  let n = 0;
  for (const tanda of enTandas(refs, POR_TANDA)) {
    const batch = db.batch();
    for (const ref of tanda) batch.delete(ref);
    await batch.commit();
    n += tanda.length;
  }
  console.log(`  ${servicios.size} servicios y ${hogares.size} filas de la red borradas`);

  // update() con FieldValue.delete(): saca solo esos campos, no reemplaza
  // el documento ni toca nada más de la cuenta.
  for (const tanda of enTandas(conAliado, POR_TANDA)) {
    const batch = db.batch();
    for (const d of tanda) {
      const cambios = {};
      for (const c of CAMPOS_ALIADO) cambios[c] = FieldValue.delete();
      cambios.roles = (d.data().roles ?? []).filter((r) => r !== 'aliado');
      batch.update(d.ref, cambios);
    }
    await batch.commit();
  }
  console.log(`  ${conAliado.length} cuentas limpiadas de datos de aliado`);

  console.log(`\n${n + consultas.length} documentos borrados, ${conAliado.length} cuentas actualizadas.`);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
