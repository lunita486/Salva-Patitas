import 'dart:async';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

/// Única puerta de entrada a las fotos de animales en Firebase Storage.
/// Ver ARCHITECTURE.md — reemplaza el esquema viejo de fotos embebidas en
/// base64 dentro del documento de Firestore (`fotoBase64`/`fotoBase642`).
///
/// El path (`rescates/{rescateId}/foto{slot}.jpg`) no es un detalle
/// interno: `storage.rules` lo usa para cruzar contra el documento de
/// Firestore y verificar dueño. Si este path cambia, hay que actualizar
/// la regla en el mismo commit.
class RescateFotosRepository {
  RescateFotosRepository({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;
  final FirebaseStorage _storage;

  Reference _ref({required String rescateId, required int slot}) =>
      _storage.ref('rescates/$rescateId/foto$slot.jpg');

  /// True si [url] es una URL de descarga que apunta al archivo
  /// `foto{slot}.jpg` de un rescate. Las URLs de descarga vienen con el
  /// path codificado (`rescates%2F{id}%2Ffoto2.jpg`), por eso se revisa
  /// tanto la forma decodificada como la cruda — y nunca lanza, ni con
  /// una URL malformada (una detección que crashea es peor que una que
  /// no detecta).
  ///
  /// Vive acá (y no como helper privado de una pantalla) porque es la
  /// única regla para responder "¿este campo apunta a este slot?" — la
  /// usa editar_rescate_screen para detectar la promoción foto 2 → foto 1
  /// Y como red de seguridad para jamás borrar un archivo que la ficha
  /// todavía referencia. Única fuente, testeable con URLs reales.
  static bool urlApuntaASlot(String? url, int slot) {
    if (url == null) return false;
    final marca = 'foto$slot.jpg';
    if (url.contains('%2F$marca') || url.contains('%2f$marca')) return true;
    try {
      return Uri.decodeFull(url).contains('/$marca');
    } catch (_) {
      return false;
    }
  }

  /// Sube [bytes] (ya comprimidos a JPEG por el llamador) y devuelve la
  /// URL de descarga. [onProgreso] (0.0 a 1.0) es opcional y best-effort —
  /// nunca hace fallar la subida si no se puede calcular (algunos entornos,
  /// como los mocks de test, no exponen bytesTransferred/totalBytes).
  ///
  /// El timeout se maneja ACÁ ADENTRO, y no envolviendo el resultado con
  /// `.timeout()` desde afuera (como se hacía antes en cada llamador) —
  /// diferencia que importa de verdad: `Future.timeout()` no cancela la
  /// operación original, solo deja de esperarla. Con la subida real
  /// siguiendo en segundo plano, un rollback que borra el archivo apenas
  /// se dispara el timeout podía terminar borrando "nada" (el archivo
  /// todavía no existía) y el archivo real completaba la subida recién
  /// después, sin que nada volviera a apuntarlo ni a borrarlo nunca — un
  /// huérfano en Storage, silencioso, para siempre. Achica el problema a
  /// un costo mensual chiquito, pero es plata perdida sin ningún beneficio
  /// y sin forma de encontrarlo desde la app.
  ///
  /// [UploadTask] sí se puede cancelar de verdad (a diferencia del
  /// `Future` genérico que devuelve `.timeout()`) — por eso el timeout
  /// necesita vivir donde el `UploadTask` todavía es un `UploadTask`, no
  /// más afuera donde ya se perdió esa referencia.
  Future<String> subir({
    required String rescateId,
    required int slot,
    required Uint8List bytes,
    void Function(double progreso)? onProgreso,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final ref = _ref(rescateId: rescateId, slot: slot);
    final task = ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    if (onProgreso != null) {
      // onError vacío a propósito: si la subida falla, el error real se
      // maneja abajo con `await task` (lo propaga al llamador). Sin este
      // onError, el mismo error también saldría por el stream sin manejar
      // y quedaría como excepción async no controlada en los logs.
      task.snapshotEvents.listen((snap) {
        try {
          if (snap.totalBytes > 0) onProgreso(snap.bytesTransferred / snap.totalBytes);
        } catch (_) {}
      }, onError: (_) {});
    }
    await task.timeout(timeout, onTimeout: () {
      // best-effort: si ya terminó (carrera con el propio timeout) o el
      // plugin no puede cancelarla en este estado, cancel() devuelve
      // false en vez de lanzar — no hay nada más que hacer acá, el throw
      // de abajo igual avisa al llamador.
      unawaited(task.cancel().catchError((_) => false));
      throw TimeoutException('Se agotó el tiempo subiendo la foto.');
    });
    return ref.getDownloadURL();
  }

  /// Mueve la foto de [deSlot] a [aSlot] (descarga los bytes, los re-sube
  /// al slot destino y borra el archivo de origen) y devuelve la URL nueva.
  /// Si el archivo de origen no existe devuelve null sin tocar nada.
  ///
  /// Existe para la "promoción" al editar: si se quita la foto 1 habiendo
  /// foto 2, la 2 pasa a ocupar el lugar de la 1. Eso tiene que mover el
  /// ARCHIVO, no solo copiar la URL de un campo al otro: los campos
  /// `fotoUrl`/`fotoUrl2` prometen apuntar a `foto1.jpg`/`foto2.jpg`
  /// respectivamente, y el resto del código (reemplazos y borrados por
  /// slot) cuenta con eso. Copiando solo la URL, `fotoUrl` quedaba
  /// apuntando a `foto2.jpg` y el mismo guardado borraba ese archivo como
  /// "slot 2 ahora vacío" — la ficha quedaba apuntando a un archivo
  /// borrado y el feed mostraba el emoji de repuesto (bug real: "rarito 2").
  ///
  /// El orden es a propósito: el borrado del origen va ÚLTIMO, recién
  /// después de que la re-subida confirmó — si algo falla a mitad de
  /// camino, lo peor que queda es un archivo duplicado, nunca una foto
  /// perdida.
  Future<String?> moverFoto({
    required String rescateId,
    required int deSlot,
    required int aSlot,
    Duration timeoutDescarga = const Duration(seconds: 20),
  }) async {
    final Uint8List? bytes;
    try {
      // getData() no devuelve un Task cancelable como putData() — no hay
      // nada que orfanar en Storage por abandonar una LECTURA (a
      // diferencia de subir(), acá el timeout es solo para no dejar a la
      // persona esperando de por vida, no una cuestión de limpieza).
      bytes = await _ref(rescateId: rescateId, slot: deSlot)
          .getData(_maxBytesFoto)
          .timeout(timeoutDescarga);
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') return null;
      rethrow;
    }
    if (bytes == null) return null;
    final url = await subir(rescateId: rescateId, slot: aSlot, bytes: bytes);
    await eliminar(rescateId: rescateId, slot: deSlot);
    return url;
  }

  // Tope de descarga para moverFoto — las fotos pasan por normalizarFoto
  // (JPEG q80, ancho máx. 1000) antes de subirse, así que rondan los
  // 100-300 KB; 15 MB es margen de sobra sin arriesgar memoria.
  static const _maxBytesFoto = 15 * 1024 * 1024;

  /// Borra la foto de [rescateId] en [slot] si existe. No falla si ya no
  /// existía (ej. slot que nunca tuvo segunda foto, o doble intento de
  /// borrado) — cualquier otro error sí se propaga.
  Future<void> eliminar({required String rescateId, required int slot}) async {
    try {
      await _ref(rescateId: rescateId, slot: slot).delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }
  }

  /// Borra las fotos de los dos slots posibles — para cuando se elimina
  /// el rescate entero. Best-effort: si alguna no existía, se ignora.
  ///
  /// `async` a propósito (no devolver el `Future.wait` directo): el objeto
  /// de `Future.wait` es en runtime un `Future<List<void>>`, y un
  /// `.catchError((_) {})` del llamador sobre ese tipo lanza
  /// "Invalid argument(s) (onError)" — eso escondió el error real de un
  /// 403 de Storage detrás de una publicación que fallaba en silencio.
  Future<void> eliminarTodas(String rescateId) async {
    await Future.wait(
      [1, 2].map((slot) => eliminar(rescateId: rescateId, slot: slot)),
    );
  }
}
