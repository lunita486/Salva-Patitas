// Mantiene al día los contadores que las dos pantallas de perfil leen
// desde `usuarios/{uid}`. El PORQUÉ de que esto exista, de que recuente en
// vez de incrementar, y de que sea UN módulo para los dos roles, está en
// contadores_logica.js — leer ese comentario antes de tocar nada acá.
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { getFirestore } = require('firebase-admin/firestore');
const { definicionDe, aRecontar } = require('./contadores_logica');

/**
 * Los números de [uid] bajo [rol], recién contados. No escribe nada.
 *
 * Cada consulta es una agregación: cuenta del lado del servidor y no
 * devuelve ni un documento. Van en paralelo porque no dependen entre sí.
 *
 * Está separado de [recontar] para que el backfill
 * (_backfill_contadores.js) pueda mostrar qué escribiría sin escribirlo, y
 * sobre todo para que el backfill y el trigger cuenten con LA MISMA
 * consulta. Si cada uno armara la suya, alcanzaría con que una cambiara
 * para que el backfill dejara números que el trigger después contradice.
 */
async function contarDe(db, { uid, rol }) {
  const definicion = definicionDe(rol);
  if (!definicion) return {};

  const suyos = db.collection('rescates')
      .where('rescatistaId', '==', uid)
      .where('creadoPor', '==', rol);

  const cuentas = await Promise.all(
      definicion.campos.map(({ estados }) => {
        let q = suyos;
        if (estados) {
          // `in` con un solo valor es una igualdad, y escribirla como
          // igualdad le ahorra a Firestore la unión de consultas.
          q = estados.length === 1
            ? q.where('estadoAdopcion', '==', estados[0])
            : q.where('estadoAdopcion', 'in', estados);
        }
        return q.count().get();
      }),
  );

  return Object.fromEntries(
      definicion.campos.map((c, i) => [c.campo, cuentas[i].data().count]),
  );
}

/**
 * Recalcula los números de una cuenta bajo un rol y los guarda.
 *
 * `update` y NO `set(..., {merge: true})`, a propósito. `set` con merge
 * CREA el documento si no existe, y un `usuarios/{uid}` que existe con solo
 * unos contadores adentro sería peor que ninguno: AuthWrapper decide mandar
 * una cuenta al onboarding justamente cuando el servidor le confirma que
 * ese perfil NO existe (ver usuarios_repository.dart), así que un documento
 * fantasma dejaría a esa persona sin onboarding y sin rol. Con `update`, si
 * el documento no está, la escritura falla con NOT_FOUND y no se crea nada.
 */
async function recontar(db, clave) {
  const numeros = await contarDe(db, clave);
  if (Object.keys(numeros).length === 0) return;
  await db.collection('usuarios').doc(clave.uid).update(numeros);
}

/**
 * Todo lo que hace el trigger, sin depender de Cloud Functions ni de
 * `getFirestore()`. Separado para que se pueda probar entero (el wrapper de
 * abajo queda en pegamento).
 */
async function manejarEscritura({ db, antes, despues }) {
  // Cada contador con su propio try: que falle uno no puede dejar al otro
  // sin actualizar. Mismo criterio que aplicarATodos() en propagar_copias.js.
  for (const clave of aRecontar({ antes, despues })) {
    try {
      await recontar(db, clave);
    } catch (e) {
      // NOT_FOUND (código 5) es esperable y no es un error: el perfil puede
      // estar borrándose ahora mismo, y eliminarCuenta ya se ocupa de sus
      // animalitos. Cualquier otra cosa sí se registra.
      if (e.code === 5 || e.code === 'not-found') continue;
      console.error(
          `No se pudieron recontar los animalitos de ${clave.uid} (${clave.rol}):`,
          e.message,
      );
    }
  }
}

// UN solo trigger para los dos roles y para los tres eventos.
// `onDocumentWritten` cubre alta, baja y modificación, y las tres terminan
// haciendo lo mismo: recontar. Con triggers separados serían varias
// funciones desplegadas, varios arranques en frío y la misma lógica
// repetida.
//
// No lleva el cerrojo de idempotencia por event.id que usan las
// notificaciones: acá no hace falta, porque recontar dos veces el mismo
// evento escribe el mismo número. Ver el comentario en la lógica.
exports.onRescateContado = onDocumentWritten(
    'rescates/{rescateId}',
    async (event) => manejarEscritura({
      db: getFirestore(),
      antes: event.data?.before?.data(),
      despues: event.data?.after?.data(),
    }),
);

// Para los tests y para el backfill. La consulta vive en un solo lugar a
// propósito: ver el comentario de contarDe.
exports.contarDe = contarDe;
exports.recontar = recontar;
exports.manejarEscritura = manejarEscritura;
