const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

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
