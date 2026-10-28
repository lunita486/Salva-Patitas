// Marca como VERIFICADO el correo de las cuentas de prueba del sandbox, en
// el EMULADOR de Firebase Auth. Las Functions del equipo del albergue (y la
// regla de invitaciones) exigen correo verificado, y las cuentas del
// sandbox nacen sin verificar.
//
// Nunca toca producción: sin FIREBASE_AUTH_EMULATOR_HOST apuntando a esta
// máquina se niega a correr, y solo cambia cuentas @sandbox.test.
//
//   FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
//     node functions/_verificar_correos_emulador.js
//
// Después hay que salir y volver a entrar en la app (o esperar a que se
// renueve el token) para que la sesión vea el correo verificado.
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');

const HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '';
if (!/^(127\.0\.0\.1|localhost):\d+$/.test(HOST)) {
  console.error('Me niego: FIREBASE_AUTH_EMULATOR_HOST no apunta al emulador local (127.0.0.1:9099).');
  process.exit(1);
}

const PROYECTO = process.env.GCLOUD_PROJECT || 'patitas-dd0bb';
const CUENTAS = ['ana@sandbox.test', 'rita@sandbox.test', 'perla@sandbox.test', 'vet@sandbox.test'];

(async () => {
  initializeApp({ projectId: PROYECTO });
  const auth = getAuth();
  for (const email of CUENTAS) {
    if (!email.endsWith('@sandbox.test')) continue;
    try {
      const u = await auth.getUserByEmail(email);
      await auth.updateUser(u.uid, { emailVerified: true });
      console.log(`✔ ${email} verificado (uid ${u.uid})`);
    } catch (e) {
      console.log(`- ${email}: ${e.code === 'auth/user-not-found' ? 'todavía no existe (entrá una vez con su botón)' : e.message}`);
    }
  }
})();
