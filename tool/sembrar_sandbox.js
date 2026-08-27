// Deja las 4 cuentas de prueba del sandbox listas para usar, cada una con
// sus roles ya puestos.
//
// **Por qué existe.** Los botones Ana/Rita/Refugio/Veterinaria de la
// pantalla de entrada CREAN la cuenta, pero nace sin roles, así que cada vez
// había que pasar por la selección de rol a mano. Peor con albergue y
// aliado: además del rol necesitan nombre de negocio, porque
// resolverPantallaPerfil() manda a completar el perfil (no al panel) si
// falta `albergueNombre`/`aliadoNombre`. Sembrarlas de una vez evita repetir
// esa configuración en cada prueba.
//
// **Por qué no puede tocar producción.** Habla solo con 127.0.0.1 y usa una
// clave de API de mentira, que es lo único que el emulador de Auth acepta.
// Contra Firebase de verdad ninguna de las dos cosas funciona.
//
//   node tool/sembrar_sandbox.js
//
// Es idempotente: correrlo dos veces deja lo mismo, no duplica cuentas.
const PROYECTO = 'patitas-dd0bb';
const AUTH = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1';
const FS = `http://127.0.0.1:8097/v1/projects/${PROYECTO}/databases/(default)/documents`;
const CLAVE = 'sandbox1234'; // la misma que usa entrarEnSandbox()

const CUENTAS = [
  {
    email: 'ana@sandbox.test',
    nombre: 'Ana Adoptante',
    roles: ['adoptante'],
  },
  {
    email: 'rita@sandbox.test',
    nombre: 'Rita Rescatista',
    roles: ['adoptante', 'rescatista'],
  },
  {
    email: 'perla@sandbox.test',
    nombre: 'Refugio La Perla',
    roles: ['albergue'],
    extra: {
      albergueNombre: 'Refugio La Perla',
      albergueTipo: 'Refugio',
      ciudad: 'Medellín',
      capacidadTotal: 40,
    },
  },
  {
    email: 'vet@sandbox.test',
    nombre: 'Veterinaria 30',
    roles: ['aliado'],
    extra: {
      aliadoNombre: 'Veterinaria 30',
      aliadoTipo: 'Veterinaria',
      ciudad: 'Medellín',
    },
  },
];

const valor = (v) =>
  typeof v === 'string'
    ? { stringValue: v }
    : typeof v === 'number'
      ? { integerValue: String(v) }
      : Array.isArray(v)
        ? { arrayValue: { values: v.map(valor) } }
        : { nullValue: null };

async function uidDe({ email, nombre }) {
  // Si la cuenta ya existe, signUp falla; ahí entramos con la contraseña.
  // Los dos caminos devuelven el mismo localId, por eso correr esto de
  // nuevo no duplica nada.
  for (const ruta of ['accounts:signUp', 'accounts:signInWithPassword']) {
    const r = await fetch(`${AUTH}/${ruta}?key=fake-api-key`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email,
        password: CLAVE,
        displayName: nombre,
        returnSecureToken: true,
      }),
    });
    if (r.ok) return (await r.json()).localId;
  }
  throw new Error(`no pude crear ni entrar con ${email}`);
}

(async () => {
  for (const c of CUENTAS) {
    const uid = await uidDe(c);
    const fields = {
      nombre: valor(c.nombre),
      email: valor(c.email),
      roles: valor(c.roles),
    };
    for (const [k, v] of Object.entries(c.extra ?? {})) fields[k] = valor(v);
    const r = await fetch(`${FS}/usuarios/${uid}`, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        // El emulador de Firestore SÍ aplica firestore.rules, y esta
        // escritura no viene de ninguna sesión: sin esto contesta
        // PERMISSION_DENIED sobre `usuarios`. "Bearer owner" es el acceso de
        // administrador que el emulador reconoce, y que solo él reconoce.
        Authorization: 'Bearer owner',
      },
      body: JSON.stringify({ fields }),
    });
    if (!r.ok) throw new Error(`${c.email}: ${r.status} ${await r.text()}`);
    console.log(`  ${c.nombre.padEnd(18)} -> ${c.roles.join(' + ')}`);
  }
  console.log('\nListo. Entrá con los botones de la pantalla de inicio.');
})();
