// Siembra el SANDBOX (emuladores locales). Nunca toca produccion:
// FIRESTORE_EMULATOR_HOST fuerza el destino, y el Auth emulator vive en 9099.
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8097';
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
initializeApp({ projectId: 'patitas-dd0bb' });
const db = getFirestore();

const AUTH = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake';

async function crearCuenta(email, displayName) {
  const r = await fetch(AUTH, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: 'sandbox1234', displayName, returnSecureToken: true }),
  });
  const j = await r.json();
  if (!j.localId) throw new Error(`${email}: ${JSON.stringify(j)}`);
  return j.localId;
}

(async () => {
  const ana   = await crearCuenta('ana@sandbox.test',   'Ana Adoptante');
  const rita  = await crearCuenta('rita@sandbox.test',  'Rita Rescatista');
  const perla = await crearCuenta('perla@sandbox.test', 'Refugio La Perla');
  const vet   = await crearCuenta('vet@sandbox.test',   'Veterinaria 30');

  await db.collection('usuarios').doc(ana).set({
    nombre: 'Ana Adoptante', email: 'ana@sandbox.test', roles: ['adoptante'],
    ciudad: 'Santiago de los Caballeros', latitud: 19.4517, longitud: -70.6970,
    paisCodigo: 'DO', creadoEn: FieldValue.serverTimestamp(),
  });
  await db.collection('usuarios').doc(rita).set({
    nombre: 'Rita Rescatista', email: 'rita@sandbox.test', roles: ['adoptante', 'rescatista'],
    ciudad: 'Santiago de los Caballeros', latitud: 19.4517, longitud: -70.6970,
    paisCodigo: 'DO', creadoEn: FieldValue.serverTimestamp(),
  });
  await db.collection('usuarios').doc(perla).set({
    nombre: 'Eliza', email: 'perla@sandbox.test', roles: ['adoptante', 'albergue'],
    albergueNombre: 'Refugio La Perla', albergueTipo: 'Refugio', capacidadTotal: 10,
    ciudad: 'Santiago de los Caballeros', latitud: 19.4517, longitud: -70.6970,
    paisCodigo: 'DO', creadoEn: FieldValue.serverTimestamp(),
  });
  await db.collection('usuarios').doc(vet).set({
    nombre: 'Dra. Vet', email: 'vet@sandbox.test', roles: ['adoptante', 'aliado'],
    aliadoNombre: 'Veterinaria 30', aliadoTipo: 'Veterinaria',
    aliadoCiudad: 'Santiago de los Caballeros', aliadoTelefono: '+18095550030',
    creadoEn: FieldValue.serverTimestamp(),
  });

  const animales = [
    { id: 'a_pacolin', nombre: 'Pacolin', especie: 'Gato',  duenio: perla, rol: 'albergue',
      rescatistaNombre: 'Refugio La Perla' },
    { id: 'a_firulais', nombre: 'Firulais', especie: 'Perro', duenio: perla, rol: 'albergue',
      rescatistaNombre: 'Refugio La Perla' },
    { id: 'a_luna',    nombre: 'Luna',    especie: 'Perro', duenio: rita,  rol: 'rescatista',
      rescatistaNombre: 'Rita Rescatista' },
    { id: 'a_sinnombre', nombre: '',      especie: 'Perro', duenio: rita,  rol: 'rescatista',
      rescatistaNombre: 'Rita Rescatista' },
  ];
  for (const a of animales) {
    await db.collection('rescates').doc(a.id).set({
      nombre: a.nombre, especie: a.especie, raza: 'Criolla', edad: '2 años',
      genero: 'Macho', tamano: 'Mediano', energia: 'Media', estado: 'Sano',
      estadoAdopcion: 'Rescatado', urgencia: 'Normal',
      descripcion: `${a.nombre || 'Este animalito'} busca hogar.`,
      rescatistaId: a.duenio, creadoPor: a.rol, rescatistaNombre: a.rescatistaNombre,
      ubicacion: 'Santiago de los Caballeros', latitud: 19.4517, longitud: -70.6970,
      paisCodigo: 'DO', okConNinos: true, okConMascotas: true,
      requiereExperiencia: false, vacunado: true, desparasitado: true,
      creadoEn: FieldValue.serverTimestamp(),
    });
  }

  await db.collection('servicios').doc('s_consulta').set({
    aliadoId: vet, nombre: 'Consulta general', precio: 800,
    descripcion: 'Revision completa', activo: true,
    creadoEn: FieldValue.serverTimestamp(),
  });

  console.log(JSON.stringify({ ana, rita, perla, vet }, null, 1));
  console.log('SEMBRADO OK');
  process.exit(0);
})().catch((e) => { console.error('FALLO:', e.message); process.exit(1); });
