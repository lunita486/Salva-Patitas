import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';

/// Tres patrones de tolerancia a fallas transitorias de Firestore, antes
/// copiados por separado en varios repositorios y pantallas (hallazgo de
/// auditoría de código) — se centralizan acá para que la política de cada
/// uno tenga un solo lugar donde cambiar. Son funciones DISTINTAS a
/// propósito, no una sola: cubren síntomas diferentes con respuestas
/// diferentes.

/// **Lectura que tropieza con el canal recién reconectando.** Reintenta
/// [accion] UNA vez, tras una espera corta, si la primera llamada falla.
/// Pensado para el "ya hay señal pero el canal de Firestore todavía está
/// levantándose" (típico al salir de modo avión). Si el segundo intento
/// también falla, la excepción se propaga tal cual — no es un reintento
/// infinito. El llamador suele encadenar un fallback a `Source.cache`
/// después de que esto se rinda.
Future<T> conReintento<T>(Future<T> Function() accion) async {
  try {
    return await accion();
  } catch (_) {
    await Future.delayed(const Duration(milliseconds: 1500));
    return accion();
  }
}

/// **Escritura rechazada por un token de sesión vencido.** Un
/// `permission-denied` en una escritura de la que ya se sabe que la cuenta
/// es dueña (la regla solo compara el uid, y la pantalla no habría ofrecido
/// la acción si no lo fuera) casi nunca es falta de permiso real: es el
/// token viejo, algo que pasa tras un rato alternando entre modo avión y
/// señal. Se fuerza un refresh del token con [auth] y se reintenta UNA vez.
/// Cualquier OTRO código de error (o un permission-denied que persiste con
/// el token nuevo) se propaga sin tocar — el refresh es específico de este
/// caso, no un reintento genérico.
///
/// [auth] se recibe como función (no como instancia) a propósito: así
/// `FirebaseAuth.instance` solo se evalúa DENTRO del catch, cuando de
/// verdad hubo un permission-denied. Evaluarlo eager en cada llamada
/// rompería los tests del camino feliz de los repositorios, que no mockean
/// auth porque en su flujo normal nunca se lo necesita.
///
/// [timeout] vive ACÁ ADENTRO (no envuelto desde afuera en cada llamador)
/// a propósito — mismo motivo que `guardarConAviso`/`subir()`: sin esto,
/// `escritura()` sin señal no se pierde ni falla, se queda esperando al
/// servidor para siempre, y los try/catch de las pantallas que llaman a
/// esta función (`seleccion_rol_screen.dart` eligiendo tu primer rol,
/// `ChatsRepository` abriendo un chat) nunca llegan a dispararse porque
/// nunca hay una excepción que atrapar — quedan con el spinner trabado en
/// vez de mostrar el aviso de error que ya tienen escrito. Un llamador que
/// necesite un límite más chico (ej. `eliminar()`, que ya envuelve esto
/// con su propio `.timeout(12s)` desde afuera) sigue funcionando igual:
/// el más corto de los dos gana. Hallazgo de auditoría de código.
Future<void> conReintentoSiTokenVencido(
  FirebaseAuth Function() auth,
  Future<void> Function() escritura, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  try {
    await escritura().timeout(timeout);
  } on FirebaseException catch (e) {
    if (e.code != 'permission-denied') rethrow;
    await auth().currentUser?.getIdToken(true);
    await escritura().timeout(timeout);
  }
}

/// Qué pasó al intentar guardar — [siguePendiente] es DISTINTO de
/// [fallo]: no es un error, es "todavía no hay confirmación".
enum ResultadoGuardado {
  /// El servidor confirmó a tiempo.
  confirmado,

  /// No hubo confirmación dentro de [guardarConAviso]'s timeout, pero
  /// [escritura] YA está encolada — Firestore la va a aplicar sola apenas
  /// vuelva la señal. No es una falla, así que no se puede avisar "no se
  /// pudo guardar" (sería mentira: sí se va a guardar).
  siguePendiente,

  /// [escritura] lanzó de verdad (permission-denied persistente, una
  /// operación que a diferencia de un `.update()` de Firestore NO se
  /// reintenta sola sin señal, etc.).
  fallo,
}

/// **Botón de "Guardar" que se queda pegado para siempre, sin avisar
/// nada.** Mismo bug, encontrado 3 veces en pantallas distintas
/// (albergue_perfil_screen.dart, aliado_perfil_screen.dart,
/// subir_servicio_screen.dart) después de haberse arreglado una vez en
/// editar_rescate_screen.dart y nunca replicado acá — exactamente el tipo
/// de cosa que este archivo existe para evitar: un patrón correcto
/// escrito una sola vez, no copiado a mano cada vez que hace falta.
///
/// La razón por la que esto necesitaba ser una función y no "agregarle un
/// try/catch a cada pantalla" sin más: un `.update()`/`.add()` de
/// Firestore sin señal NO se pierde — el SDK lo encola solo y lo aplica
/// apenas vuelva la conexión. Ponerle un timeout que CANCELE el guardado y
/// avisar "no se pudo guardar" sería mentirle a la persona: el cambio SÍ
/// se va a guardar. [guardarConAviso] usa el timeout solo para decidir QUÉ
/// avisar (confirmado ya vs. todavía en camino), nunca para cortar la
/// escritura — y en los dos casos, el llamador queda libre de soltar el
/// botón/cerrar la pantalla en vez de dejarla trabada esperando una
/// confirmación que capaz tarda minutos en volver.
Future<ResultadoGuardado> guardarConAviso(
  Future<void> Function() escritura, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  try {
    await escritura().timeout(timeout);
    return ResultadoGuardado.confirmado;
  } on TimeoutException {
    return ResultadoGuardado.siguePendiente;
  } catch (_) {
    return ResultadoGuardado.fallo;
  }
}
