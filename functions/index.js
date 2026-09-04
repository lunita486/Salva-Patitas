const { onDocumentCreated, onDocumentUpdated, onDocumentDeleted } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { getStorage } = require('firebase-admin/storage');
const { setGlobalOptions } = require('firebase-functions/v2');

initializeApp();

// Techo de instancias para las 10 funciones. Sin esto todas se despliegan
// con `maxInstances` sin definir, o sea el máximo de la plataforma: el gasto
// de cómputo de Functions no tiene tope. `landingAnimales` es el caso que
// motivó esto — `onRequest` sin auth, alcanzable por cualquiera.
//
// Tiene que ir ACÁ, antes de los require() de abajo: esos módulos definen
// sus funciones al cargarse, leyendo las opciones globales vigentes en ese
// momento. Puesto después, no las alcanza (comprobado: quedan en
// ResetValue). 10 está muy por encima del pico real de la app; el efecto de
// tocar el techo sería que los eventos se encolan, no que se pierdan.
setGlobalOptions({ maxInstances: 10 });

// Cumplimiento de la política de eliminación de cuenta de Google Play —
// ver el plan en C:\Users\Eliza\.claude\plans\joyful-waddling-squid.md
// para el razonamiento completo de qué se borra/anonimiza/bloquea.
exports.eliminarCuenta = require('./eliminar_cuenta').eliminarCuenta;

// Endpoint público para la vidriera de animales de la landing (docs/index.html).
exports.landingAnimales = require('./landing_animales').landingAnimales;

// Aviso diario de "hogar de paso vence mañana/ya venció" — antes solo lo
// disparaba el cliente al abrir el panel del rescatista/albergue, así que
// dependía de que esa cuenta abriera la app justo ese día (ver el
// comentario completo en avisos_vencimiento.js).
exports.avisarVencimientosHogarDePaso =
  require('./avisos_vencimiento').avisarVencimientosHogarDePaso;

// Mantienen al día las copias del nombre/foto del animal (en solicitudes y
// chats) y de la ubicación/nombre/logo del albergue (en sus animales y sus
// chats). Antes esto lo hacía solo la app, en segundo plano y sin avisar
// si fallaba — y falló de cuatro formas distintas, todas en silencio. Ver
// el comentario largo en propagar_copias_logica.js.
exports.onRescateActualizado =
  require('./propagar_copias').onRescateActualizado;
exports.onPerfilActualizado =
  require('./propagar_copias').onPerfilActualizado;

// Mantiene en usuarios/{uid} los números que muestran los dos perfiles: el
// del rescatista ("Animales rescatados" / "Adopciones aprobadas") y el
// público del albergue ("En cuidado" / "Adoptados"). Existen para que esas
// pantallas lean UN documento —que sí sale del caché local, como ya pasaba
// con la capacidad del albergue— en vez de pagar un viaje al servidor con
// count(), que no tiene caché posible. Un solo trigger para los dos roles:
// ver el comentario largo en contadores_logica.js.
exports.onRescateContado = require('./contadores').onRescateContado;

const { notificar } = require('./notificar');

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
    // expiraEn (no procesadoEn) es el campo que apunta la política de TTL
    // de Firestore (se activa aparte, en la consola — ver ARCHITECTURE.md):
    // esa política borra el documento cuando el RELOJ pasa el valor de este
    // campo, así que tiene que ser "ahora + margen", no la hora de creación.
    // 7 días de margen es de sobra frente a los reintentos reales de
    // Eventarc (minutos a pocas horas) — sin este campo, la colección
    // crecía un documento por cada mensaje/solicitud/cambio de estado, para
    // siempre, sin que nada la vaciara nunca.
    const expiraEn = Timestamp.fromMillis(Date.now() + 7 * 24 * 60 * 60 * 1000);
    await ref.create({ procesadoEn: FieldValue.serverTimestamp(), expiraEn });
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

    // AUTOCONSULTA: la misma cuenta es las dos partes del chat (un albergue
    // que pidió adopción u hogar de paso para su propio animal, o alguien
    // que le escribe a su propio negocio aliado). Ahí `emisor` vale SIEMPRE
    // 'adoptante' — se lo exige la regla de Firestore, que resuelve quién
    // escribe con `adoptanteId == uid`, y con los dos ids iguales ese
    // ternario no puede dar otra cosa. Así que el destinatario calculado
    // arriba termina siendo quien acaba de escribir, y la persona recibía
    // una notificación push de su PROPIO mensaje cada vez.
    //
    // Se compara contra quien escribió en vez de contra los ids del chat
    // para que el guard cubra también cualquier caso futuro donde
    // destinatario y remitente coincidan por otro motivo.
    const remitenteId = emisor === 'adoptante' ? chat.adoptanteId : chat.rescatistaId;
    if (recipientId === remitenteId) return;

    // Los avisos que acompanan un cambio de estado de la solicitud
    // (aprobada / rechazada) ya tienen su propia push, la de
    // onCambioEstadoSolicitud, que ademas dice mejor lo que paso: "Tu
    // solicitud fue aprobada" contra el generico "Mensaje sobre Pacolin".
    // Sin este guard llegaban las DOS por un solo hecho, con textos
    // distintos, y la segunda no aportaba nada. El mensaje se escribe y se
    // ve en el chat igual que siempre; lo unico que se saltea es la push.
    if (data.avisoDeEstado === true) return;

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

    // El TIPO manda en el título Y en el cuerpo. Antes el título lo
    // respetaba ("Nueva solicitud de hogar de paso") pero el cuerpo decía
    // "quiere adoptar a X" fijo, así que una misma notificación se
    // contradecía sola: el albergue leía "hogar de paso" arriba y
    // "adoptar" abajo, y la app (que sí ramifica bien) le mostraba otra
    // cosa al abrirla.
    const esHogar = sol.tipoSolicitud === 'hogar_de_paso';
    const tipo = esHogar ? 'hogar de paso' : 'adopción';
    const quien = sol.nombre || 'Alguien';
    const animal = sol.animalNombre || 'tu animal';
    await notificar(
      rescatistaId,
      `Nueva solicitud de ${tipo}`,
      esHogar
        ? `${quien} se ofrece como hogar de paso para ${animal}`
        : `${quien} quiere adoptar a ${animal}`,
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
