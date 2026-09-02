// Borra el campo `rescatistaFotoBase64` de los animalitos que todavía lo
// tengan. NADA MÁS: ni un campo más, ni un documento menos.
//
// **Por qué.** Ese campo es una copia del logo del albergue en base64, unos
// 85 KB, guardada DENTRO de cada animalito. Medido contra producción, la
// Jauría del panel baja 962 KB en dos consultas y el 97% es ese logo
// repetido; el perfil público baja 2,7 MB y el 98,9% es lo mismo. Ninguna
// de las dos pantallas usa ese campo: es peso muerto.
//
// El código ya no lo escribe ni lo lee (el avatar del feed sale de
// `usuarios/{uid}` vía AvatarUsuario, y el trigger dejó de propagarlo),
// pero sacarlo del mapa no borra lo ya escrito: `valoresDeseados` solo
// escribe, nunca borra un campo que salga de él. Por eso hace falta esto.
//
// **El logo original no se toca.** Sigue en `usuarios/{uid}.fotoBase64`,
// que es su única fuente. Acá se borran copias.
//
// **No escribe nada por defecto.** Sin `--aplicar` solo informa.
//
//   node functions/_limpiar_logo_duplicado.js                (simulacro)
//   node functions/_limpiar_logo_duplicado.js --aplicar      (borra)
//   node functions/_limpiar_logo_duplicado.js --emulador     (contra el sandbox)
//
// Contra producción usa las credenciales de gcloud (ADC).
//
// **Es seguro correrlo dos veces.** Solo toca los documentos que todavía
// tienen el campo; a los ya limpios no les escribe nada.
//
// **Qué despierta.** Cada borrado es un update sobre `rescates`, así que
// dispara onRescateActualizado y onRescateContado. Los dos salen sin hacer
// nada: el primero compara los campos que copia (nombre y foto del
// animalito, que no cambian) y el segundo mira `estadoAdopcion`,
// `rescatistaId` y `creadoPor`, que tampoco. Hay tests que lo fijan.
const APLICAR = process.argv.includes('--aplicar');
const EMULADOR = process.argv.includes('--emulador');
const PROYECTO = 'patitas-dd0bb';
const CAMPO = 'rescatistaFotoBase64';
const POR_TANDA = 500;

if (EMULADOR) process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8097';

const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

initializeApp({ projectId: PROYECTO });
const db = getFirestore();

(async () => {
  const destino = EMULADOR ? 'EL EMULADOR' : `producción (${PROYECTO})`;
  console.log(`${APLICAR ? 'Borrando en' : 'SIMULACRO sobre'} ${destino}\n`);

  // La MISMA consulta y la MISMA comprobación en los dos modos.
  //
  // Estuvo partida en dos ramas: al aplicar usaba `select()` sin campos
  // para no descargar los logos, ya que para borrarlos alcanza con la
  // referencia. Esa optimización se llevó puesta la comprobación de
  // existencia, y el modo real le mandó un `delete` a los 187 documentos de
  // la colección en vez de a los 73 que tenían el campo. No rompió nada
  // (borrar un campo que no existe deja el documento igual, y se verificó
  // con un hash de todos los demás campos antes y después) pero escribió
  // en 114 documentos que no hacía falta tocar, y disparó sus triggers.
  //
  // Ahorrar esa descarga no vale un script que hace algo distinto de lo que
  // mostró el simulacro. Ahora la única diferencia entre los dos modos es
  // si se escribe o no.
  const conCampo = [];
  let mirados = 0;
  let bytes = 0;

  for await (const doc of db.collection('rescates').select(CAMPO).stream()) {
    mirados++;
    const valor = doc.data()[CAMPO];
    if (typeof valor !== 'string') continue;
    conCampo.push(doc.ref);
    bytes += valor.length;
  }

  if (!APLICAR) {
    console.log(`${mirados} animalitos mirados en total.`);
    console.log(`${conCampo.length} tienen ${CAMPO}.`);
    console.log(`Se borrarían ${(bytes / 1024 / 1024).toFixed(2)} MB.\n`);
    if (conCampo.length > 0) {
      console.log('Los documentos afectados:');
      for (const ref of conCampo) console.log(`  ${ref.id}`);
      console.log(`\nEl ÚNICO campo que se borra es ${CAMPO}.`);
      console.log('No se borra ningún documento y no se toca ningún otro campo.');
      console.log('\nNo se escribió nada. Volvé a correrlo con --aplicar.');
    }
    return;
  }

  // update() con FieldValue.delete() del único campo: no reemplaza el
  // documento, no crea nada y no toca nada más. En tandas de 500, que es el
  // tope duro de un WriteBatch; cada tanda que termina queda escrita de
  // verdad aunque una posterior falle. Mismo criterio que onRescateEliminado.
  let borrados = 0;
  for (let i = 0; i < conCampo.length; i += POR_TANDA) {
    const tanda = conCampo.slice(i, i + POR_TANDA);
    const batch = db.batch();
    for (const ref of tanda) batch.update(ref, { [CAMPO]: FieldValue.delete() });
    await batch.commit();
    borrados += tanda.length;
    console.log(`  tanda de ${tanda.length}: hecha (${borrados}/${conCampo.length})`);
  }
  console.log(`\n${mirados} animalitos mirados, ${borrados} actualizados.`);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
