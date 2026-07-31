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

// Cloud Functions/Eventarc entrega "al menos una vez": el mismo evento
// puede volver a disparar el trigger (reintento tras una falla transitoria,
// redespliegue a mitad de un evento, etc.), con el MISMO event.id. Sin nada
// que lo detecte, un reenvío repetía el push entero — la misma persona
// podía recibir "¡Tu solicitud fue aprobada!" dos veces por la misma
// aprobación real (el guard before.estado===after.estado de
// onCambioEstadoSolicitud NO protege contra esto: un reenvío trae el MISMO
// before/after, pasa ese guard igual las dos veces).
//
// event.id es el identificador único que Eventarc asigna a cada entrega, y
// se mantiene igual entre reintentos del mismo evento — es la base del
// patrón oficial de Google para funciones idempotentes. Se usa acá como
// llave de un cerrojo atómico en Firestore: la PRIMERA entrega logra CREAR
// el documento (create() falla si ya existe, a diferencia de set()) y
// sigue; cualquier entrega repetida del mismo evento choca contra un
// documento que ya existe y se corta sola, sin mandar el push de nuevo.
// Atómico a propósito (create(), no "leer si existe y después escribir"):
// dos entregas casi simultáneas del mismo reintento no tienen una ventana
// donde las dos lean "no existe todavía" y las dos sigan de largo.
async function primeraVezQueSeVeEsteEvento(eventId) {
  const ref = getFirestore().collection('_eventosProcesados').doc(eventId);
  try {
    await ref.create({ procesadoEn: FieldValue.serverTimestamp() });
    return true;
  } catch (e) {
    // code 6 = ALREADY_EXISTS (gRPC) — ya se procesó este evento, o se está
    // procesando ahora mismo en otra instancia. Cualquier OTRO error es
    // real (permiso, red) y no se tapa: mejor arriesgarse a un duplicado
    // raro que perder notificaciones por un error de infraestructura.
    if (e.code === 6 || e.code === 'already-exists') return false;
    throw e;
  }
}

// Nuevo mensaje → notifica al destinatario
exports.onNuevoMensaje = onDocumentCreated(
  'chats/{chatId}/mensajes/{msgId}',
  async (event) => {
    if (!(await primeraVezQueSeVeEsteEvento(event.id))) return;
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
    await notificar(recipientId, `Mensaje sobre ${animal}`, data.texto || '', 'notif_mensajes');
  }
);

// Nueva solicitud → notifica al rescatista
exports.onNuevaSolicitud = onDocumentCreated(
  'solicitudes/{solId}',
  async (event) => {
    if (!(await primeraVezQueSeVeEsteEvento(event.id))) return;
    const sol = event.data.data();
    const rescatistaId = sol.rescatistaId;
    if (!rescatistaId) return;

    const tipo = sol.tipoSolicitud === 'hogar_de_paso' ? 'hogar de paso' : 'adopción';
    await notificar(
      rescatistaId,
      `Nueva solicitud de ${tipo}`,
      `${sol.nombre || 'Alguien'} quiere adoptar a ${sol.animalNombre || 'tu animal'}`,
      'notif_solicitudes'
    );
  }
);

// Solicitud aprobada/rechazada → notifica al adoptante
exports.onCambioEstadoSolicitud = onDocumentUpdated(
  'solicitudes/{solId}',
  async (event) => {
    if (!(await primeraVezQueSeVeEsteEvento(event.id))) return;
    const before = event.data.before.data();
    const after  = event.data.after.data();

    if (before.estado === after.estado) return;
    if (!['aprobada', 'rechazada'].includes(after.estado)) return;

    const adoptanteId = after.adoptanteId;
    if (!adoptanteId) return;

    const animal = after.animalNombre || 'tu animal';

    if (after.estado === 'aprobada') {
      await notificar(adoptanteId, '¡Tu solicitud fue aprobada! 🐾', `¡Felicidades! Tu solicitud para ${animal} fue aprobada.`, 'notif_solicitudes');
    } else {
      await notificar(adoptanteId, 'Solicitud no aceptada', `Tu solicitud para ${animal} no fue aceptada esta vez.`, 'notif_solicitudes');
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
