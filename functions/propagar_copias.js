// Triggers que mantienen al día las copias de datos del animal y del
// albergue repartidas por otras colecciones. El PORQUÉ de que esto viva en
// el servidor está explicado en propagar_copias_logica.js — leer ese
// comentario antes de tocar nada acá.
const { onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const {
  CAMPOS_ANIMAL_A_CHAT,
  CAMPOS_ANIMAL_A_SOLICITUD,
  CAMPOS_PERFIL_A_ANIMAL,
  CAMPOS_PERFIL_A_ANIMAL_RESCATISTA,
  CAMPOS_PERFIL_A_CHAT,
  CAMPOS_PERFIL_A_SOLICITUD,
  CAMPOS_PERFIL_A_CHAT_ADOPTANTE,
  CAMPOS_A_BORRAR_EN_CHAT_DE_ANIMAL,
  CAMPOS_PERFIL_ALIADO_A_CHAT,
  cambiosAPropagar,
  destinosQueHayQueRevisar,
  valoresDeseados,
  desactualizado,
  enTandas,
  esChatDeAnimal,
} = require('./propagar_copias_logica');

/**
 * Aplica `cambios` a todos los documentos que devuelve `consulta` (después
 * de pasar por `filtro`, si se da uno — ver el comentario en
 * onPerfilActualizado sobre por qué hace falta para los chats de
 * albergue), en tandas de 500. Cada tanda que logra terminar queda escrita
 * de verdad aunque una posterior falle — mismo criterio que
 * onRescateEliminado.
 *
 * `descripcion` solo se usa para el log: cuando algo falla acá, lo único
 * que va a quedar es esa línea, así que dice qué se estaba propagando y a
 * dónde.
 */
async function aplicarATodos({ db, consulta, cambios, descripcion, filtro }) {
  try {
    const snap = await consulta.get();
    if (snap.empty) return;
    const docs = filtro ? snap.docs.filter(filtro) : snap.docs;
    if (docs.length === 0) return;
    for (const tanda of enTandas(docs)) {
      const batch = db.batch();
      tanda.forEach((doc) => batch.update(doc.ref, cambios));
      await batch.commit();
    }
  } catch (e) {
    console.error(`No se pudo propagar ${descripcion}:`, e.message);
  }
}

// Cambió un animal: refrescar su nombre/foto en las solicitudes y los chats
// que lo mencionan. Las dos colecciones guardan los mismos dos campos con
// los mismos nombres, así que comparten `cambios`.
//
// A diferencia de la versión del lado del cliente, acá NO hace falta
// acotar la consulta por dueño: un trigger corre con permisos de admin y
// las reglas de seguridad no se le aplican. Justamente esa falta de
// acotación era lo que hacía fallar a la del cliente en silencio.
exports.onRescateActualizado = onDocumentUpdated(
  'rescates/{rescateId}',
  async (event) => {
    const antes = event.data?.before?.data();
    const despues = event.data?.after?.data();
    if (!despues) return;

    const db = getFirestore();
    const rescateId = event.params.rescateId;

    // Cada colección con su propio mapa: un chat solo necesita el nombre y
    // la foto del animal, mientras que una solicitud además copia las 5
    // etiquetas con las que se calcula el puntaje de compatibilidad que ve
    // quien la aprueba. Ver el comentario de CAMPOS_ANIMAL_A_SOLICITUD.
    for (const { coleccion, campos } of [
      { coleccion: 'solicitudes', campos: CAMPOS_ANIMAL_A_SOLICITUD },
      { coleccion: 'chats', campos: CAMPOS_ANIMAL_A_CHAT },
    ]) {
      const cambios = cambiosAPropagar({ antes, despues, campos });
      if (cambios === null) continue;
      await aplicarATodos({
        db,
        consulta: db.collection(coleccion).where('rescateId', '==', rescateId),
        cambios,
        descripcion: `${Object.keys(cambios).join('/')} del animal ${rescateId} a ${coleccion}`,
      });
    }
  }
);

// Cambió un perfil: refrescar lo que copian los documentos de esa cuenta.
//
// Cubre los dos roles que denormalizan datos de perfil, por separado a
// propósito: una misma cuenta puede ser albergue Y aliado a la vez, y cada
// rol guarda su nombre y su logo en campos distintos. Lo que publica como
// rescatista no hereda nada del perfil del albergue — misma separación por
// CreatorRole que usa toda la app.
exports.onPerfilActualizado = onDocumentUpdated(
  'usuarios/{uid}',
  async (event) => {
    const antes = event.data?.before?.data();
    const despues = event.data?.after?.data();
    if (!despues) return;

    const db = getFirestore();
    const uid = event.params.uid;
    const chats = db.collection('chats').where('rescatistaId', '==', uid);

    // Cada destino con su propio mapa de campos y su propia consulta.
    const destinos = [
      {
        campos: CAMPOS_PERFIL_A_ANIMAL,
        consulta: db.collection('rescates')
            .where('rescatistaId', '==', uid)
            .where('creadoPor', '==', 'albergue'),
        que: 'sus animales',
      },
      // Los animales publicados con el otro sombrero. Consulta separada
      // (creadoPor == 'rescatista') y mapa separado: ver
      // CAMPOS_PERFIL_A_ANIMAL_RESCATISTA para por que no comparten nada.
      {
        campos: CAMPOS_PERFIL_A_ANIMAL_RESCATISTA,
        consulta: db.collection('rescates')
            .where('rescatistaId', '==', uid)
            .where('creadoPor', '==', 'rescatista'),
        que: 'sus animales de rescatista',
      },
      {
        campos: CAMPOS_PERFIL_A_CHAT,
        // Ver CAMPOS_A_BORRAR_EN_CHAT_DE_ANIMAL: `fotoBase64` no pertenece
        // a un chat de animal, y hay que sacarlo activamente — quedó
        // escrito por una versión anterior de este mismo trigger y no se
        // limpia solo.
        aBorrar: CAMPOS_A_BORRAR_EN_CHAT_DE_ANIMAL,
        consulta: chats.where('creadoPor', '==', 'albergue'),
        // Ver el comentario de esChatDeAnimal() en propagar_copias_logica.js
        // para el porqué de este filtro — no es cosmético, es lo que evita
        // que este destino (pensado solo para chats de ANIMAL) también
        // toque chats de consulta_aliado.
        filtro: (doc) => esChatDeAnimal(doc.data()),
        que: 'sus chats de albergue',
      },
      // El aliado no tiene animales: un chat suyo es una consulta a su
      // negocio, y se distingue por tipoSolicitud, no por creadoPor (ahí
      // el rescatistaId es el aliado, y quien tiene el rol de
      // rescatista/albergue es la otra parte). Esta consulta SÍ es
      // inambigua tal cual está: tipoSolicitud=='consulta_aliado' nunca
      // aparece en un chat de animal, así que no necesita el mismo filtro
      // que la de arriba.
      {
        campos: CAMPOS_PERFIL_ALIADO_A_CHAT,
        consulta: chats.where('tipoSolicitud', '==', 'consulta_aliado'),
        que: 'sus chats de negocio',
      },
      // Los dos destinos del lado ADOPTANTE. Van por `adoptanteId`, no por
      // `rescatistaId`, así que son consultas propias y no salen de
      // `chats` (que ya viene filtrada por rescatistaId).
      //
      // Una misma cuenta puede aparecer de los dos lados —pedir un animal
      // y publicar otro— y entonces corren los destinos de arriba Y estos.
      // Es correcto: cada uno escribe en documentos distintos, con el
      // campo del perfil que a ese documento le corresponde. Lo que NO
      // hacen es mezclarse: el nombre de albergue nunca cae en el lado de
      // adoptante ni al revés, que es el bug de roles cruzados que ya
      // conocemos.
      {
        campos: CAMPOS_PERFIL_A_SOLICITUD,
        consulta: db.collection('solicitudes').where('adoptanteId', '==', uid),
        que: 'sus solicitudes',
      },
      {
        campos: CAMPOS_PERFIL_A_CHAT_ADOPTANTE,
        consulta: db.collection('chats').where('adoptanteId', '==', uid),
        que: 'sus chats como adoptante',
      },
    ];

    // Se propagan los valores DESEADOS (todos, no solo los que cambiaron
    // en este guardado) pero escribiendo únicamente en los documentos que
    // hoy tienen algo distinto — ver valoresDeseados/desactualizado en
    // propagar_copias_logica.js.
    //
    // Ese par es lo que hace que guardar el perfil REPARE copias que
    // quedaron mal por bugs anteriores, en vez de solo mantener al día las
    // que ya estaban bien. Con "propagá solo lo que cambió" (como estaba),
    // una copia corrupta sobrevivía para siempre salvo que justo ese campo
    // cambiara: Eliza le cambió la FOTO a su negocio y la foto del chat se
    // reparó sola, pero el NOMBRE siguió mostrando el del albergue, porque
    // el nombre no había cambiado. Mismo razonamiento que ya se aplicó a la
    // ciudad del albergue (ver albergue_perfil_screen.dart).
    //
    // No es "reescribir todo en cada guardado": el filtro `desactualizado`
    // deja fuera los documentos que ya están bien, así que un guardado que
    // no rompió nada (o un refresco de token que ni toca estos campos) no
    // escribe absolutamente nada.
    // Solo los destinos que de verdad tienen algo que revisar. Ver
    // destinosQueHayQueRevisar: sin esto eran 5 consultas por cada apertura
    // de la app, casi siempre para no escribir nada.
    for (const { campos, consulta, que, filtro, aBorrar = [] } of
      destinosQueHayQueRevisar({ antes, despues, destinos })) {
      const deseados = valoresDeseados({ despues, campos });
      if (deseados === null) continue;
      await aplicarATodos({
        db,
        consulta,
        cambios: {
          ...deseados,
          // Los campos que sobran se borran en la MISMA escritura que
          // corrige los que faltan — un solo update por documento.
          ...Object.fromEntries(
              aBorrar.map((campo) => [campo, FieldValue.delete()]),
          ),
        },
        filtro: (doc) =>
          (filtro ? filtro(doc) : true) &&
          desactualizado(doc.data(), deseados, aBorrar),
        descripcion: `${Object.keys(deseados).join('/')} del perfil ${uid} a ${que}`,
      });
    }
  }
);
