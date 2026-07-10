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

  /// Sube [bytes] (ya comprimidos a JPEG por el llamador) y devuelve la
  /// URL de descarga. [onProgreso] (0.0 a 1.0) es opcional y best-effort —
  /// nunca hace fallar la subida si no se puede calcular (algunos entornos,
  /// como los mocks de test, no exponen bytesTransferred/totalBytes).
  Future<String> subir({
    required String rescateId,
    required int slot,
    required Uint8List bytes,
    void Function(double progreso)? onProgreso,
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
    await task;
    return ref.getDownloadURL();
  }

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
