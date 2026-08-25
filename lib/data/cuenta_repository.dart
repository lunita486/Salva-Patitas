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
  // `FirebaseFunctions.instance` (sin especificar región) apunta a
  // us-central1 por defecto — pero `eliminarCuenta` se desplegó a
  // propósito en europe-west1 (mismo region que el resto de functions/
  // index.js, ver el comentario ahí). Sin esto, TODO pedido de borrado de
  // cuenta llamaba a una función que no existe en us-central1 (nunca hubo
  // logs de ejecución del lado del servidor, ni un solo intento real
  // llegaba a correr) y el cliente mostraba el error genérico de "revisá
  // tu conexión" — rompía la eliminación de cuenta para cualquier persona,
  // con cualquier conexión. Hallazgo real de Eliza probando antes del
  // lanzamiento.
  // Pública (no privada) a propósito: así un test puede confirmar que
  // sigue coincidiendo con la región real donde vive la función
  // desplegada, sin necesitar una conexión real a Firebase para probarlo.
  static const region = 'europe-west1';
  CuentaRepository({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instanceFor(region: region);
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
  ///
  /// Antes eran 120s — técnicamente "más corto que 300", pero nadie se
  /// queda mirando un spinner sin ninguna señal de progreso durante dos
  /// minutos enteros: Eliza terminó cerrando la app a la fuerza (el
  /// borrado había terminado bien del lado del servidor de todos modos,
  /// pero la persona no tenía forma de saberlo). 30s sigue siendo tiempo
  /// de sobra para que la enorme mayoría de los borrados normales
  /// terminen bien DENTRO del timeout (nunca muestran el aviso de
  /// "tardando"); para la cuenta rara con muchísimos chats que sí tarda
  /// más, la persona ve antes el aviso de que puede seguir esperando
  /// tranquila en vez de whatsapp de que la app se colgó. Hallazgo real
  /// de Eliza: "me tocó cerrar la app e ingresar nuevamente... el usuario
  /// no tendría por qué salir e ingresar de nuevo".
  Future<void> eliminarCuenta({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      await _functions.httpsCallable('eliminarCuenta').call().timeout(timeout);
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'failed-precondition') {
        throw CuentaBloqueada(
          e.message ?? 'No se puede eliminar la cuenta todavía.',
        );
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
