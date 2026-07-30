import 'package:firebase_auth/firebase_auth.dart';

/// Dos patrones de tolerancia a fallas transitorias de Firestore, antes
/// copiados por separado en varios repositorios (hallazgo de auditoría de
/// código) — se centralizan acá para que la política de reintento tenga un
/// solo lugar donde cambiar. Son DOS funciones distintas a propósito, no
/// una sola: cubren dos síntomas diferentes con dos respuestas diferentes.

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
Future<void> conReintentoSiTokenVencido(
  FirebaseAuth Function() auth,
  Future<void> Function() escritura,
) async {
  try {
    await escritura();
  } on FirebaseException catch (e) {
    if (e.code != 'permission-denied') rethrow;
    await auth().currentUser?.getIdToken(true);
    await escritura();
  }
}
