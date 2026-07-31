// Arranca el emulador de Firestore y corre las pruebas de firestore.rules.
//
// Existe (en vez de llamar a `firebase emulators:exec` directo desde el
// script de npm) por una sola razón: el emulador necesita Java, y en la
// máquina de desarrollo Java viene con Android Studio pero NO está en el
// PATH. Sin esto, `firebase deploy` fallaría con "Could not spawn java"
// en vez de correr las pruebas — y como el predeploy de firebase.json
// depende de esto, un fallo así bloquearía el deploy por el motivo
// equivocado. Acá se busca el Java que haya y se lo pasa al emulador.

import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const aca = dirname(fileURLToPath(import.meta.url));
const esWindows = process.platform === 'win32';
const javaBin = esWindows ? 'java.exe' : 'java';

/** Devuelve el JAVA_HOME a usar, o null si Java ya está en el PATH. */
function buscarJavaHome() {
  // 1) Ya está en el PATH (o JAVA_HOME ya apunta bien): no tocar nada.
  const enPath = spawnSync(javaBin, ['-version'], { stdio: 'ignore', shell: esWindows });
  if (enPath.status === 0) return null;

  const candidatos = [
    process.env.JAVA_HOME,
    // Android Studio trae su propio JDK (JetBrains Runtime).
    'C:\\Program Files\\Android\\Android Studio\\jbr',
    '/Applications/Android Studio.app/Contents/jbr/Contents/Home',
    join(process.env.HOME ?? '', 'Android/Studio/jbr'),
  ].filter(Boolean);

  for (const base of candidatos) {
    if (existsSync(join(base, 'bin', javaBin))) return base;
  }
  return undefined; // no se encontró ninguno
}

const javaHome = buscarJavaHome();

if (javaHome === undefined) {
  console.error(`
No se encontró Java, y el emulador de Firestore lo necesita para correr las
pruebas de firestore.rules.

Instalá un JDK (o Android Studio, que trae el suyo) y volvé a intentar. Si ya
lo tenés en otra ruta, exportá JAVA_HOME apuntando ahí.
`);
  process.exit(1);
}

const env = { ...process.env };
if (javaHome) {
  env.JAVA_HOME = javaHome;
  env.PATH = `${join(javaHome, 'bin')}${esWindows ? ';' : ':'}${env.PATH}`;
}

/**
 * Ruta al CLI de Firebase. A propósito NO usa `npx`: cuando este script
 * corre anidado dentro de `npm run` (que es justo lo que hace el predeploy
 * de firebase.json), npx en Windows falla con "could not determine
 * executable to run" — las variables npm_config_* que hereda le rompen la
 * resolución. Llamarlo directo evita ese nivel de indirección.
 */
function buscarFirebase() {
  // 1) En el PATH (instalación global, el caso normal).
  const enPath = spawnSync('firebase', ['--version'], { stdio: 'ignore', shell: true });
  if (enPath.status === 0) return 'firebase';

  // 2) En la carpeta de binarios globales de npm.
  //
  // Ojo con el env: el predeploy llama a esto como
  // `npm --prefix test_rules test`, y ese --prefix se hereda al hijo como
  // npm_config_prefix, que es EXACTAMENTE la variable con la que npm
  // decide cuál es su prefijo global. Sin limpiarla, `npm prefix -g`
  // contesta "test_rules" en vez de la carpeta global de verdad, y firebase
  // nunca aparece. Costó un rato: el mismo comando funcionaba suelto y
  // fallaba solo dentro del deploy.
  const envLimpio = { ...process.env };
  delete envLimpio.npm_config_prefix;
  delete envLimpio.npm_config_global_prefix;

  const candidatos = [];
  const prefijo = spawnSync('npm', ['prefix', '-g'], {
    encoding: 'utf8',
    shell: true,
    env: envLimpio,
  });
  if (prefijo.status === 0) candidatos.push(prefijo.stdout.trim());
  // Respaldo por si npm no contesta: la ubicación estándar en cada sistema.
  if (esWindows && process.env.APPDATA) candidatos.push(join(process.env.APPDATA, 'npm'));
  candidatos.push('/usr/local/bin', '/usr/bin');

  for (const base of candidatos) {
    for (const ruta of [
      join(base, esWindows ? 'firebase.cmd' : 'firebase'),
      join(base, 'bin', esWindows ? 'firebase.cmd' : 'firebase'),
    ]) {
      if (existsSync(ruta)) return `"${ruta}"`;
    }
  }
  return null;
}

const firebase = buscarFirebase();

if (!firebase) {
  console.error(`
No se encontró el CLI de Firebase, necesario para levantar el emulador.

Instalalo con:  npm install -g firebase-tools
`);
  process.exit(1);
}

const resultado = spawnSync(
  `${firebase} emulators:exec --only firestore "node --test"`,
  { cwd: aca, env, stdio: 'inherit', shell: true },
);

process.exit(resultado.status ?? 1);
