const { onSchedule } = require('firebase-functions/v2/scheduler');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { decidirAviso } = require('./avisos_vencimiento_logica');

// El aviso de "hogar de paso vence mañana/ya venció" solo se mandaba desde
// el lado del cliente (verificarVencimientos(), lib/screens/
// solicitudes_rescatista_screen.dart), disparado en el initState del panel
// del rescatista/albergue — así que si esa cuenta no abría su app justo el
// día que correspondía, el mensaje nunca se llegaba a generar, aunque
// "Mis solicitudes" del adoptante siguiera mostrando "vence hoy" (ese
// texto se calcula aparte, en el momento, sin depender de si el aviso se
// mandó). Esta función corre todos los días sin depender de que nadie
// abra nada. Hallazgo real de Eliza: nunca le llegó el aviso por chat.
//
// No reemplaza a verificarVencimientos() — las dos pueden mandar el mismo
// aviso el mismo día (los flags avisoPrevioAvisado/vencimientoAvisado
// evitan que se duplique, gane quien llegue primero).

function horaAhora(d = new Date()) {
  return `${d.getHours()}:${String(d.getMinutes()).padStart(2, '0')}`;
}

// Mismo esquema que ChatsRepository.idAnimal (lib/data/chats_repository.
// dart) — el mismo par (animal, adoptante) siempre da el mismo id de chat,
// tanto si lo crea el cliente como si lo crea esta función.
function idAnimal(rescateId, adoptanteId) {
  return `${rescateId}_${adoptanteId}`;
}

// Mismo nombre de respaldo que ya usa enviarMensajeChat() del lado del
// cliente: el logo de albergue si lo tiene, si no su nombre, si no un
// genérico.
async function nombreDeUsuario(db, uid, generico) {
  try {
    const doc = await db.collection('usuarios').doc(uid).get();
    const data = doc.data() || {};
    if (data.albergueNombre) return data.albergueNombre;
    if (data.nombre) return data.nombre;
  } catch (_) {}
  return generico;
}

// Réplica de ChatsRepository.avisarSobreAnimal() (rama "chat de animal por
// rescateId determinístico") pero corriendo con permisos de administrador:
// a diferencia del cliente, acá SÍ se puede escribir el chat y su primer
// mensaje en un solo batch atómico — el problema que obligó a partir esa
// función en dos pasos del lado del cliente es una regla de seguridad
// (mensajes.create no ve el chat recién creado EN EL MISMO batch), y las
// Cloud Functions con privilegios de administrador no están sujetas a esas
// reglas.
async function avisarPorVencimiento(db, {
  rescateId, adoptanteId, rescatistaId, rescatista, adoptanteNombre,
  animalNombre, especie, fotoUrl, creadoPor, texto,
}) {
  const chatRef = db.collection('chats').doc(idAnimal(rescateId, adoptanteId));
  const chatSnap = await chatRef.get();
  const existia = chatSnap.exists;
  const datosPrevios = existia ? chatSnap.data() : {};
  // Mismo criterio que ChatsRepository.emisorPara: 'adoptante' solo en la
  // autoconsulta (un albergue con un hogar de paso de su propio animal).
  const emisor = adoptanteId === rescatistaId ? 'adoptante' : 'rescatista';
  const hora = horaAhora();

  const batch = db.batch();
  batch.set(chatRef, {
    ...(!existia ? {
      rescateId,
      adoptanteId,
      adoptanteNombre,
      animalNombre,
      creadoPor: creadoPor || 'rescatista',
      rescatistaId,
      rescatista,
      ...(especie ? { especie } : {}),
    } : {}),
    // La foto solo se completa si el chat todavía no tenía una — nunca se
    // pisa la que ya estaba.
    ...(fotoUrl && !datosPrevios.fotoUrl ? { fotoUrl } : {}),
    ultimoMensaje: texto,
    ultimaHora: hora,
    ultimoMensajeEn: FieldValue.serverTimestamp(),
    // Los dos lados suman "sin leer": lo dispara el paso del tiempo, no
    // una acción consciente del rescatista/albergue — sin esto, el aviso
    // quedaba guardado en el chat sin ninguna señal visible en SU panel
    // (ni badge, ni ícono de Chats). Mismo motivo que avisoParaAmbosLados
    // en ChatsRepository.registrarMensaje.
    noLeidosAdoptante: FieldValue.increment(1),
    noLeidosRescatista: FieldValue.increment(1),
  }, { merge: true });
  batch.set(chatRef.collection('mensajes').doc(), {
    texto,
    emisor,
    hora,
    creadoEn: FieldValue.serverTimestamp(),
    // Este aviso lo manda siempre el rescatista/albergue. En una
    // autoconsulta `emisor` vale 'adoptante' (ver arriba), así que sin
    // este dato el aviso se dibujaría del lado equivocado en pantalla.
    escritoPorRescatista: true,
  });
  await batch.commit();
}

exports.avisarVencimientosHogarDePaso = onSchedule(
  {
    schedule: 'every day 09:00',
    timeZone: 'America/Bogota',
    region: 'europe-west1',
  },
  async () => {
    const db = getFirestore();
    const ahora = new Date();
    const snap = await db.collection('rescates')
      .where('estadoAdopcion', '==', 'Hogar de paso')
      .get();

    for (const doc of snap.docs) {
      const d = doc.data();
      const fechaFinTs = d.fechaFinHogar;
      const adoptanteId = d.adoptanteIdEnProceso;
      const rescatistaId = d.rescatistaId;
      // Sin fecha, sin adoptante o sin dueño no hay a quién avisarle ni con
      // qué criterio — mismo chequeo defensivo que verificarVencimientos()
      // del lado del cliente.
      if (!fechaFinTs || !adoptanteId || !rescatistaId) continue;

      const nombre = (d.nombre || '').trim() || 'Sin nombre';
      const aviso = decidirAviso({
        fechaFin: fechaFinTs.toDate(),
        ahora,
        avisoPrevioAvisado: d.avisoPrevioAvisado,
        vencimientoAvisado: d.vencimientoAvisado,
        nombre,
      });
      if (!aviso) continue;

      try {
        const rescatista = await nombreDeUsuario(db, rescatistaId, 'Rescatista');
        await avisarPorVencimiento(db, {
          rescateId: doc.id,
          adoptanteId,
          rescatistaId,
          rescatista,
          adoptanteNombre: 'Adoptante',
          animalNombre: nombre,
          especie: d.especie,
          fotoUrl: d.fotoUrl,
          creadoPor: d.creadoPor,
          texto: aviso.mensaje,
        });
        // Solo se marca "avisado" si el mensaje realmente se guardó — mismo
        // criterio que verificarVencimientos(): un aviso que falló a mitad
        // de camino tiene que poder reintentarse mañana, no perderse.
        await doc.ref.update({ [aviso.flag]: true });
      } catch (e) {
        console.error(`avisarVencimientosHogarDePaso falló para ${doc.id}:`, e.message);
      }
    }
  }
);
