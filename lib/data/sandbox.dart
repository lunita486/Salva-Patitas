import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Modo sandbox: la app habla con los emuladores locales de Firebase en vez
/// de con `patitas-dd0bb`.
///
/// **Por qué existe.** Hasta ahora no había ninguna forma de recorrer la app
/// sin escribir en la base de verdad. Probar una adopción, un hogar de paso
/// o un mensaje a un negocio significaba crear documentos reales y dispararle
/// notificaciones push a personas reales. Eso volvía imposible verificar de
/// punta a punta: había que deducir desde el código, o arriesgarse.
///
/// Además, las reglas de seguridad solo se probaban contra el emulador desde
/// `test_rules/` con payloads escritos a mano. Con esto se pueden probar
/// contra lo que la app manda de verdad.
///
/// **Cómo se enciende.**
/// ```
/// firebase emulators:start --only firestore,auth,storage
/// flutter run --dart-define=SANDBOX=true
/// ```
///
/// **Por qué no puede colarse a un APK de producción.** [kDebugMode] es una
/// constante de compilación: en release el `&&` se resuelve a `false` en
/// tiempo de compilación y todo lo que cuelga de [enSandbox] se elimina del
/// binario. Aunque alguien pasara `--dart-define=SANDBOX=true` a un build
/// de release, no tendría efecto. La comprobación doble es a propósito: que
/// no dependa de acordarse de no pasar una bandera.
const _bandera = String.fromEnvironment('SANDBOX');

// `const`, no `final`: solo así el compilador puede resolverlo en tiempo de
// compilación y BORRAR del binario todo lo que cuelga de él. Con `final` la
// comprobación quedaría en tiempo de ejecución, y el código del sandbox
// viajaría dentro del APK de producción aunque nunca se ejecutara.
//
// Se acepta también `profile` y no solo `debug` por un motivo práctico que
// costó descubrir: una build de DEBUG en el emulador de Android es tan
// lenta que Android la mata con "Salva Patitas isn't responding" antes de
// poder tocar nada ("Skipped 182 frames", cero peticiones llegando a los
// emuladores). En `profile` el código va compilado AOT, la app corre a
// velocidad casi de release, y el sandbox se vuelve usable de verdad.
//
// La garantía no se debilita: `release` sigue afuera, que es lo único que
// se le instala a alguien. Las dos constantes son de compilación, así que
// en un APK de release esto es `false` y el bloque entero desaparece.
const bool enSandbox = (kDebugMode || kProfileMode) && _bandera == 'true';

/// Estamos en una build de pruebas (debug o profile), nunca en release.
///
/// Es lo que decide si se dibuja el botón morado de cambiar de rol. Antes
/// ese botón preguntaba por [kDebugMode] a secas, en cinco pantallas, y eso
/// lo dejaba afuera de las builds de PROFILE — justo las que se usan para
/// probar en el emulador de Android, porque una build de debug ahí es tan
/// lenta que Android la mata antes de poder tocar nada (ver el comentario
/// largo de [enSandbox]).
///
/// El resultado era una trampa: la única build que corre bien en el
/// emulador es la única sin el botón para cambiar de rol. Eliza:
/// "recordás que teníamos un botón morado en el emulador, una vez me
/// logueaba con mi cuenta de gmail podía entrar a cualquier rol desde la
/// misma cuenta mía de gmail".
///
/// Separado de [enSandbox] a propósito: cambiar de rol con la cuenta de
/// Google DE VERDAD es justamente lo que ella quiere poder hacer, así que
/// este botón no puede depender de que se hayan levantado los emuladores
/// locales.
///
/// La garantía de release es la misma y por el mismo motivo: las dos son
/// constantes de compilación, así que en un APK de release esto es `false`
/// y todo lo que cuelga de acá se borra del binario.
const bool enModoPruebas = kDebugMode || kProfileMode;

/// `localhost` desde adentro del emulador de Android es el propio teléfono
/// virtual, no la máquina. 10.0.2.2 es el alias que Android reserva para
/// "la máquina que me hospeda". En iOS y escritorio sí es localhost.
String get _host =>
    (!kIsWeb && Platform.isAndroid) ? '10.0.2.2' : '127.0.0.1';

/// Redirige los tres SDK a los emuladores. Se llama una sola vez, justo
/// después de `Firebase.initializeApp()` y ANTES de cualquier lectura.
Future<void> conectarEmuladores() async {
  final host = _host;
  // Los puertos son los mismos de firebase.json (8097 el de Firestore, no
  // el 8080 de siempre — ver el comentario ahí sobre el choque de puertos
  // con el emulador de Android en esta máquina).
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8097);
  await FirebaseAuth.instance.useAuthEmulator(host, 9099);
  await FirebaseStorage.instance.useStorageEmulator(host, 9199);
  debugPrint('SANDBOX: hablando con los emuladores en $host');
}

/// Entra con email y contraseña, creando la cuenta si no existe.
///
/// Solo sirve contra el emulador de Auth. En producción la app entra
/// únicamente con Google (ver auth_helper.dart) y este camino no existe: lo
/// llama solo el botón que login_screen dibuja bajo [enSandbox].
///
/// El punto de todo esto es no necesitar ninguna credencial real para
/// recorrer la app.
Future<UserCredential> entrarEnSandbox({
  required String email,
  required String nombre,
}) async {
  final auth = FirebaseAuth.instance;
  const clave = 'sandbox1234';
  try {
    return await auth.signInWithEmailAndPassword(
      email: email,
      password: clave,
    );
  } on FirebaseAuthException {
    final cred = await auth.createUserWithEmailAndPassword(
      email: email,
      password: clave,
    );
    // La app lee displayName en varios lados (el nombre con el que se firma
    // un animal publicado como rescatista, el del adoptante en un chat); sin
    // esto todas las cuentas de prueba salen sin nombre y no se distinguen.
    await cred.user?.updateDisplayName(nombre);
    await cred.user?.reload();
    return cred;
  }
}
