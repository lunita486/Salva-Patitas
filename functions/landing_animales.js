const { onRequest } = require('firebase-functions/v2/https');
const { getFirestore } = require('firebase-admin/firestore');

// Misma definición de "disponible" que usa el feed del adoptante en la app
// (ver adoptante_feed_screen.dart) — sin estado, o Rescatado/Regresado/
// Hogar de paso. Adoptado/Fallecido quedan afuera. Se filtra acá, en el
// servidor, en vez de exponer una query de Firestore sin autenticar desde
// la landing: así la landing no necesita config de Firebase ni SDK, y solo
// se publican los campos que de verdad hacen falta para la vidriera.
const ESTADOS_DISPONIBLES = new Set(['Rescatado', 'Regresado', 'Hogar de paso']);

// Endpoint público (sin auth) para la landing en GitHub Pages: devuelve
// hasta 12 animales disponibles, con foto, para la vidriera de la home.
// `cors: true` porque la landing vive en otro origen (lunita486.github.io),
// no en el dominio de Cloud Functions.
exports.landingAnimales = onRequest({ cors: true, region: 'us-central1' }, async (req, res) => {
  res.set('Cache-Control', 'public, max-age=300, s-maxage=300');
  try {
    const snap = await getFirestore()
      .collection('rescates')
      .orderBy('creadoEn', 'desc')
      .limit(60)
      .get();

    const animales = snap.docs
      .map((doc) => doc.data())
      .filter((d) => !d.estadoAdopcion || ESTADOS_DISPONIBLES.has(d.estadoAdopcion))
      .filter((d) => !!d.fotoUrl)
      .slice(0, 12)
      .map((d) => ({
        nombre: d.nombre || 'Sin nombre',
        especie: d.especie || 'Perro',
        edad: d.edad || '',
        ubicacion: d.ubicacion || '',
        foto: d.fotoUrl,
      }));

    res.json({ animales });
  } catch (e) {
    res.status(500).json({ animales: [] });
  }
});
