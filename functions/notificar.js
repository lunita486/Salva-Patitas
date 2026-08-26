const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

// Mandar una notificación push vivía adentro de index.js, sin exportar.
// Se movió acá (movido, no copiado) cuando avisos_vencimiento.js necesitó
// lo mismo: el aviso de "el hogar de paso vence" tiene que poder llegarle
// al rescatista aunque no haya ningún chat de por medio, y la alternativa
// era una segunda copia de esta lógica con su propio criterio sobre los
// tokens muertos y las preferencias.

// Tokens que FCM reporta como muertos (app desinstalada, token vencido/rotado).
// Sin esto, un usuario que desinstaló la app acumula intentos de envío fallidos
// para siempre y el token nunca se limpia.
const TOKEN_INVALIDO = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

// Busca el token del destinatario y le envía la notificación. Si FCM dice
// que el token ya no sirve, lo borra del perfil en la misma operación.
//
// [tipoPreferencia] es el campo de preferencias/{uid} que corresponde a
// ESTE tipo de aviso ('notif_mensajes'/'notif_solicitudes' — ver
// notificaciones_screen.dart). Antes esta función nunca lo miraba: los
// interruptores de esa pantalla guardaban el dato pero nada lo leía, así
// que apagarlos no hacía nada de verdad (hallazgo de auditoría de
// código). Default `true` si el documento o el campo no existen — mismo
// default que ya usa la pantalla, para no silenciar de golpe a nadie que
// nunca entró a configurar esto.
async function notificar(uid, title, body, tipoPreferencia) {
  const userRef = getFirestore().collection('usuarios').doc(uid);
  const doc = await userRef.get();
  const token = doc.exists ? (doc.data().fcmToken || null) : null;
  if (!token) return;

  if (tipoPreferencia) {
    const prefDoc = await getFirestore().collection('preferencias').doc(uid).get();
    const habilitado = prefDoc.exists ? (prefDoc.data()[tipoPreferencia] ?? true) : true;
    if (!habilitado) return;
  }

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

module.exports = { notificar, TOKEN_INVALIDO };
