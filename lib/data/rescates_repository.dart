import 'package:cloud_firestore/cloud_firestore.dart';
import 'creator_role.dart';

/// Única puerta de entrada a la colección `rescates`. Las pantallas no
/// deben llamar `FirebaseFirestore.instance.collection('rescates')`
/// directamente — ver ARCHITECTURE.md.
class RescatesRepository {
  RescatesRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('rescates');

  /// Animales publicados por [uid] bajo el rol [role]. `role` es
  /// obligatorio a propósito: una cuenta puede ser rescatista Y albergue
  /// a la vez, y sin este filtro se mezclan (bug real, arreglado hoy).
  Stream<QuerySnapshot<Map<String, dynamic>>> misRescates({
    required String uid,
    required CreatorRole role,
  }) =>
      _col
          .where('rescatistaId', isEqualTo: uid)
          .where('creadoPor', isEqualTo: role.firestoreValue)
          .snapshots();

  /// Feed público de adopción — sin scope por diseño, cualquiera lo ve.
  ///
  /// Sin `orderBy('creadoEn')` a propósito: Firestore no solo ordenaría mal
  /// los documentos que no tengan ese campo (legados, o un futuro path que
  /// se olvide de setearlo) — los EXCLUIRÍA del resultado por completo,
  /// desapareciéndolos del feed en silencio. El orden por fecha se aplica
  /// del lado del cliente, en la pantalla que consume este stream.
  Stream<QuerySnapshot<Map<String, dynamic>>> feedPublico() => _col.snapshots();

  /// Lectura puntual (no stream) de "mis animales en tal estado" — para
  /// chequeos únicos como avisos de vencimiento de hogar de paso.
  Future<QuerySnapshot<Map<String, dynamic>>> misRescatesPorEstado({
    required String uid,
    required CreatorRole role,
    required String estadoAdopcion,
  }) =>
      _col
          .where('rescatistaId', isEqualTo: uid)
          .where('creadoPor', isEqualTo: role.firestoreValue)
          .where('estadoAdopcion', isEqualTo: estadoAdopcion)
          .get();

  Future<DocumentReference<Map<String, dynamic>>> crear({
    required String uid,
    required CreatorRole role,
    required Map<String, dynamic> datos,
  }) =>
      _col.add({
        ...datos,
        'rescatistaId': uid,
        'creadoPor': role.firestoreValue,
        'creadoEn': FieldValue.serverTimestamp(),
      });

  Future<void> actualizar(String rescateId, Map<String, dynamic> cambios) =>
      _col.doc(rescateId).update(cambios);

  /// Fallback para solicitudes viejas guardadas sin `rescateId`: busca el
  /// rescate por nombre+dueño y lo actualiza si lo encuentra. Si hay más de
  /// un animal con el mismo nombre bajo la misma cuenta, actualiza el
  /// primero que encuentre — mismo comportamiento legado que reemplaza.
  Future<void> actualizarPorNombre({
    required String nombre,
    required String rescatistaId,
    required Map<String, dynamic> cambios,
  }) async {
    final q = await _col
        .where('nombre', isEqualTo: nombre)
        .where('rescatistaId', isEqualTo: rescatistaId)
        .limit(1)
        .get();
    if (q.docs.isNotEmpty) {
      await q.docs.first.reference.update(cambios);
    }
  }

  Future<void> eliminar(String rescateId) => _col.doc(rescateId).delete();
}
