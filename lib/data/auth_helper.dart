import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'usuarios_repository.dart';

/// Todo el flujo de sesión de Google/Firebase vive acá — login Y logout —
/// para que ninguna pantalla hable con GoogleSignIn directo. Historia de por
/// qué, en orden (cada capa arregló un bug real de Eliza):
///
/// 1. Timeouts en cada paso: sin ellos, una llamada nativa colgada dejaba el
///    spinner girando para siempre ("se queda cargando eternamente").
/// 2. Los dos pasos del logout en try/catch INDEPENDIENTES: si el de Google
///    se colgaba, el de Firebase nunca corría — y como AuthWrapper
///    (main.dart) decide qué pantalla mostrar mirando
///    FirebaseAuth.authStateChanges(), la app ENTERA quedaba atrapada en el
///    spinner de carga, sin salida (10+ minutos trabada al cambiar de
///    cuenta).
/// 3. El candado [_authOcupado]: Future.timeout() NO cancela la llamada
///    nativa original, solo deja de esperarla — reintentar enseguida apilaba
///    una llamada nueva sobre la fantasma.
/// 4. Migración a google_sign_in v7 (la solución de fondo): la 6.x usaba el
///    SDK viejo de Google (hoy deprecado) con un bug documentado —
///    "Concurrent operations detected" — donde una operación colgada dejaba
///    una bandera nativa interna trabada PARA SIEMPRE, y todo intento
///    posterior chocaba contra ella. El bug real: cambiar de cuenta
///    funcionaba 2 veces y a la 3ra el spinner quedaba infinito, sin que
///    ninguno de los parches de arriba pudiera destrabarlo (la bandera vive
///    dentro del plugin, fuera de nuestro alcance). La v7 es un rediseño
///    (singleton + Credential Manager en Android) hecho, entre otras cosas,
///    para eso.
///
/// El candado se conserva en v7 como defensa extra: sigue evitando que un
/// doble toque dispare dos flujos a la vez.
bool _authOcupado = false;

bool get hayOperacionDeSesionEnCurso => _authOcupado;

/// Cliente OAuth "web" del proyecto (tipo 3 en google-services.json) — es el
/// que Google exige para emitir el idToken que Firebase valida. Es
/// información pública (viaja dentro del APK); pasarlo explícito evita
/// depender de que el recurso autogenerado `default_web_client_id` exista.
const _serverClientId =
    '205018856680-m0guhvmh4lrmous3glimjstranjqinf4.apps.googleusercontent.com';

/// initialize() de la v7 debe correr UNA vez antes de cualquier otra llamada.
/// Memoizado con reset en error: si falla (ej. sin red al abrir la app), el
/// próximo intento de login vuelve a intentarlo en vez de quedar envenenado.
Future<void>? _gsiInicializando;
Future<void> _asegurarGoogleSignInListo() async {
  try {
    _gsiInicializando ??=
        GoogleSignIn.instance.initialize(serverClientId: _serverClientId);
    await _gsiInicializando;
  } catch (_) {
    _gsiInicializando = null;
    rethrow;
  }
}

void _marcarOcupado() => _authOcupado = true;

/// Con [conEspera], suelta el candado recién a los 15 segundos: le da tiempo
/// a una llamada nativa abandonada por timeout a morir de verdad antes de
/// permitir una nueva. Sin [conEspera] (flujo que terminó limpio, exitoso o
/// cancelado por la persona), suelta de inmediato — no hay fantasma que
/// esperar, y así cerrar sesión justo después de entrar no molesta con
/// "esperá unos segundos".
void _liberarOcupado({bool conEspera = false}) {
  if (!conEspera) {
    _authOcupado = false;
    return;
  }
  Future.delayed(const Duration(seconds: 15), () {
    _authOcupado = false;
  });
}

enum ResultadoLogin {
  /// Sesión iniciada en Google Y Firebase.
  ok,

  /// La persona cerró el selector de cuenta sin elegir — no es un error, no
  /// mostrar mensaje de falla.
  cancelado,

  /// Hay otra operación de sesión en curso (o recién abandonada por
  /// timeout) — pedir que espere unos segundos y reintente.
  ocupado,
}

/// Flujo completo de login con Google → Firebase. Lanza excepción en
/// cualquier falla real (sin red, timeout, credencial rechazada) — el
/// llamador decide el mensaje; los dos desenlaces esperables sin error
/// llegan como [ResultadoLogin].
Future<ResultadoLogin> iniciarSesionGoogle() async {
  if (_authOcupado) return ResultadoLogin.ocupado;
  _marcarOcupado();
  try {
    await _asegurarGoogleSignInListo()
        .timeout(const Duration(seconds: 15));
    // authenticate() muestra el selector de cuenta nativo y espera a que la
    // persona elija — por eso su timeout es más largo que los demás pasos,
    // que son solo de red.
    final cuenta = await GoogleSignIn.instance
        .authenticate()
        .timeout(const Duration(seconds: 60));
    final credential = GoogleAuthProvider.credential(
      idToken: cuenta.authentication.idToken,
    );
    await FirebaseAuth.instance
        .signInWithCredential(credential)
        .timeout(const Duration(seconds: 20));
    // Asegura que usuarios/{uid} exista desde el primer ingreso (ver el
    // porqué completo en UsuariosRepository.asegurarPerfilBase) — así
    // AuthWrapper nunca depende de que el servidor confirme "esta cuenta
    // es nueva", el camino que dejaba a una cuenta sin perfil atrapada en
    // el spinner de arranque. Best-effort con timeout corto y errores
    // tragados a propósito: el efecto que importa (el doc en la caché
    // local) ocurre al instante aunque el await ni termine — el await solo
    // espera la confirmación del servidor, que acá no hace falta.
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await UsuariosRepository().asegurarPerfilBase(
          uid: user.uid,
          nombre: user.displayName,
          email: user.email,
          foto: user.photoURL,
        ).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    _liberarOcupado();
    return ResultadoLogin.ok;
  } on GoogleSignInException catch (e) {
    if (e.code == GoogleSignInExceptionCode.canceled ||
        e.code == GoogleSignInExceptionCode.interrupted) {
      _liberarOcupado();
      return ResultadoLogin.cancelado;
    }
    _liberarOcupado(conEspera: true);
    rethrow;
  } catch (_) {
    // Timeout o falla de red: la llamada nativa abandonada puede seguir viva
    // — soltar el candado con espera para no apilar otra encima.
    _liberarOcupado(conEspera: true);
    rethrow;
  }
}

/// Cierra la sesión de Google Y de Firebase Auth — en dos pasos con manejo
/// de error INDEPENDIENTE cada uno, a propósito (ver historia arriba: el
/// paso de Firebase es el que de verdad saca a la persona de la app vía
/// AuthWrapper, y nunca debe quedar bloqueado por un problema del lado de
/// Google).
///
/// Devuelve `false` sin hacer nada si ya hay una operación de sesión en
/// curso — llamar igual apilaría otra llamada sobre una que puede seguir
/// viva.
Future<bool> cerrarSesion() async {
  if (_authOcupado) return false;
  _marcarOcupado();
  var huboProblema = false;
  try {
    await _asegurarGoogleSignInListo().timeout(const Duration(seconds: 10));
    await GoogleSignIn.instance.signOut().timeout(const Duration(seconds: 10));
  } catch (_) {
    huboProblema = true;
  }
  try {
    await FirebaseAuth.instance.signOut().timeout(const Duration(seconds: 10));
  } catch (_) {
    huboProblema = true;
  }
  _liberarOcupado(conEspera: huboProblema);
  return true;
}
