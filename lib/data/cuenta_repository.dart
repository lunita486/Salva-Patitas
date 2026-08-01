import 'package:cloud_functions/cloud_functions.dart';

/// Puerta de entrada al borrado de cuenta — toda la lógica real (qué se
/// borra, qué se anonimiza, cuándo se bloquea) vive del lado del servidor,
/// en la Cloud Function `eliminarCuenta` (functions/eliminar_cuenta.js),
/// con privilegios de administrador. Acá solo se la invoca y se traduce su
/// resultado a algo que la pantalla pueda mostrar.
///
/// Por qué del lado del servidor y no con reglas de Firestore nuevas: ver
/// el plan completo en el historial de esta sesión. Resumen corto: el
/// chequeo de "¿tenés un animal en hogar de paso activo ahora mismo?" es
/// una consulta, no algo que una regla de seguridad pueda expresar contra
/// un documento puntual — del lado del cliente nunca sería una barrera de
/// verdad.
class CuentaRepository {
  CuentaRepository({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;
  final FirebaseFunctions _functions;

  /// Lanza [CuentaBloqueada] si la cuenta tiene un animal en hogar de paso
  /// o en proceso de adopción a su cargo ahora mismo (mensaje ya armado
  /// del lado del servidor, listo para mostrar tal cual). Cualquier otro
  /// error se propaga sin traducir — el llamador usa [mensajeError] para
  /// mostrar algo genérico.
  ///
  /// El timeout acá es más corto que el de la función en sí
  /// (timeoutSeconds: 300 del lado del servidor) a propósito: no cancela
  /// el borrado ya en curso (`Future.timeout()` nunca cancela la llamada
  /// original, mismo motivo que en `RescateFotosRepository`/
  /// `ChatsRepository`), solo deja de esperar. Si vence, la pantalla debe
  /// avisar que puede seguir terminando de fondo, no que "falló".
  Future<void> eliminarCuenta({Duration timeout = const Duration(seconds: 120)}) async {
    try {
      await _functions.httpsCallable('eliminarCuenta').call().timeout(timeout);
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'failed-precondition') {
        throw CuentaBloqueada(e.message ?? 'No se puede eliminar la cuenta todavía.');
      }
      rethrow;
    }
  }

  static String mensajeError(Object error) {
    if (error is CuentaBloqueada) return error.mensaje;
    return 'No pudimos eliminar tu cuenta. Revisá tu conexión e intentá de nuevo.';
  }
}

/// La cuenta tiene un animal a su cargo ahora mismo (hogar de paso o
/// proceso de adopción activo) — [mensaje] ya viene listo para mostrar,
/// armado del lado del servidor (mismo texto para cualquier pantalla que
/// lo use).
class CuentaBloqueada implements Exception {
  CuentaBloqueada(this.mensaje);
  final String mensaje;
}
