const { onDocumentCreated, onDocumentUpdated, onDocumentDeleted } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { getStorage } = require('firebase-admin/storage');

initializeApp();

// Tokens que FCM reporta como muertos (app desinstalada, token vencido/rotado).
// Sin esto, un usuario que desinstaló la app acumula intentos de envío fallidos
// para siempre y el token nunca se limpia.
const TOKEN_INVALIDO = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

// Busca el token del destinatario y le envía la notificación. Si FCM dice
// que el token ya no sirve, lo borra del perfil en la misma operación.
async function notificar(uid, title, body) {
  const userRef = getFirestore().collection('usuarios').doc(uid);
  const doc = await userRef.get();
  const token = doc.exists ? (doc.data().fcmToken || null) : null;
  if (!token) return;
  try {
    await getMessaging().send({
      token,
      notification: { title, body },
      android: { priority: 'high' },
    });
  } catch (e) {
    console.error('FCM error:', e.code || e.message);
    if (TOKEN_INVALIDO.has(e.code)) {
      await userRef.update({ fcmToken: FieldValue.delete() }).catch(() => {});
    }
  }
}

// Nuevo mensaje → notifica al destinatario
exports.onNuevoMensaje = onDocumentCreated(
  'chats/{chatId}/mensajes/{msgId}',
  async (event) => {
    const data = event.data.data();
    const chatId = event.params.chatId;

    const chatDoc = await getFirestore().collection('chats').doc(chatId).get();
    if (!chatDoc.exists) return;
    const chat = chatDoc.data();

    // emisor puede ser 'rescatista' o 'adoptante'
    const emisor = data.emisor;
    const recipientId = emisor === 'rescatista' ? chat.adoptanteId : chat.rescatistaId;
    if (!recipientId) return;

    const animal = chat.animalNombre || 'Animal';
    await notificar(recipientId, `Mensaje sobre ${animal}`, data.texto || '');
  }
);

// Nueva solicitud → notifica al rescatista
exports.onNuevaSolicitud = onDocumentCreated(
  'solicitudes/{solId}',
  async (event) => {
    const sol = event.data.data();
    const rescatistaId = sol.rescatistaId;
    if (!rescatistaId) return;

    const tipo = sol.tipoSolicitud === 'hogar_de_paso' ? 'hogar de paso' : 'adopción';
    await notificar(
      rescatistaId,
      `Nueva solicitud de ${tipo}`,
      `${sol.nombre || 'Alguien'} quiere adoptar a ${sol.animalNombre || 'tu animal'}`
    );
  }
);

// Solicitud aprobada/rechazada → notifica al adoptante
exports.onCambioEstadoSolicitud = onDocumentUpdated(
  'solicitudes/{solId}',
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();

    if (before.estado === after.estado) return;
    if (!['aprobada', 'rechazada'].includes(after.estado)) return;

    const adoptanteId = after.adoptanteId;
    if (!adoptanteId) return;

    const animal = after.animalNombre || 'tu animal';

    if (after.estado === 'aprobada') {
      await notificar(adoptanteId, '¡Tu solicitud fue aprobada! 🐾', `¡Felicidades! Tu solicitud para ${animal} fue aprobada.`);
    } else {
      await notificar(adoptanteId, 'Solicitud no aceptada', `Tu solicitud para ${animal} no fue aceptada esta vez.`);
    }
  }
);

// Rescate borrado → limpia lo que le quedaba apuntando, sin importar si
// el borrado se aplicó al toque (con señal) o recién se sincronizó más
// tarde (Firestore encola escrituras sin conexión; Storage no). Este
// trigger corre en el servidor cuando el documento YA desapareció de
// verdad, así que cubre el caso offline que el cliente nunca puede
// garantizar por su cuenta — antes, borrar sin señal (o perder la señal
// a mitad del borrado) dejaba las fotos huérfanas en Storage para
// siempre. RescatesRepository.eliminar() ya hace esta misma limpieza de
// favoritos del lado del cliente cuando SÍ hay señal (para que
// desaparezca al toque); esto es la red de seguridad que garantiza que
// pase siempre, tarde o temprano, sin depender de reglas de seguridad ni
// de que el rescatista siga conectado.
exports.onRescateEliminado = onDocumentDeleted(
  'rescates/{rescateId}',
  async (event) => {
    const rescateId = event.params.rescateId;

    try {
      await getStorage().bucket().deleteFiles({ prefix: `rescates/${rescateId}/` });
    } catch (e) {
      console.error(`No se pudieron borrar las fotos de ${rescateId}:`, e.message);
    }

    try {
      const db = getFirestore();
      const favoritos = await db.collection('favoritos')
          .where('rescateId', '==', rescateId).get();
      // Un WriteBatch tiene un tope duro de 500 operaciones — un animal
      // con más de 500 favoritos (improbable hoy, pero no imposible)
      // hacía que batch.commit() tirara, el catch de abajo lo tapaba con
      // un solo console.error, y NINGÚN favorito se borraba, ni siquiera
      // los primeros 500. Partido en tandas de a 500, cada tanda que
      // logra terminar queda borrada de verdad aunque una tanda más
      // adelante falle.
      const docs = favoritos.docs;
      for (let i = 0; i < docs.length; i += 500) {
        const batch = db.batch();
        docs.slice(i, i + 500).forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
      }
    } catch (e) {
      console.error(`No se pudieron borrar los favoritos de ${rescateId}:`, e.message);
    }
  }
);
