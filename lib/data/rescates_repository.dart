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
  Stream<QuerySnapshot<Map<String, dynamic>>> feedPublico() =>
      _col.orderBy('creadoEn', descending: true).snapshots();

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

  Future<void> eliminar(String rescateId) => _col.doc(rescateId).delete();
}
