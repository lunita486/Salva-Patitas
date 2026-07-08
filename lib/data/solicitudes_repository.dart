import 'package:cloud_firestore/cloud_firestore.dart';
import 'creator_role.dart';

/// Única puerta de entrada a la colección `solicitudes`. Ver ARCHITECTURE.md.
///
/// Hay dos métodos con nombres distintos ([paraOwner] y [misSolicitudes])
/// en vez de uno genérico, porque son dos relaciones distintas con la
/// misma colección: el nombre del método ya dice qué relación es, así
/// que no se puede llamar el equivocado por error.
class SolicitudesRepository {
  SolicitudesRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('solicitudes');

  /// Solicitudes recibidas por el rescatista/albergue dueño del animal.
  /// [role] es obligatorio por la misma razón que en RescatesRepository.
  Stream<QuerySnapshot<Map<String, dynamic>>> paraOwner({
    required String uid,
    required CreatorRole role,
    String? estado,
  }) {
    Query<Map<String, dynamic>> q = _col
        .where('rescatistaId', isEqualTo: uid)
        .where('creadoPor', isEqualTo: role.firestoreValue);
    if (estado != null) q = q.where('estado', isEqualTo: estado);
    return q.snapshots();
  }

  /// Solicitudes que mandó el adoptante — sin ambigüedad de rol, un
  /// adoptante no tiene doble sombrero.
  Stream<QuerySnapshot<Map<String, dynamic>>> misSolicitudes(String uid) =>
      _col.where('adoptanteId', isEqualTo: uid).snapshots();

  Future<bool> yaAplico({required String uid, required String animalNombre}) async =>
      (await estadoExistente(uid: uid, animalNombre: animalNombre)) != null;

  /// Estado de la solicitud pendiente/aprobada que ya tenga [uid] sobre
  /// [animalNombre], o `null` si no aplicó todavía.
  Future<String?> estadoExistente({required String uid, required String animalNombre}) async {
    final q = await _col
        .where('adoptanteId', isEqualTo: uid)
        .where('animalNombre', isEqualTo: animalNombre)
        .where('estado', whereIn: ['pendiente', 'aprobada'])
        .limit(1)
        .get();
    if (q.docs.isEmpty) return null;
    return q.docs.first.data()['estado'] as String? ?? '';
  }

  Future<DocumentReference<Map<String, dynamic>>> crear({
    required String adoptanteUid,
    required String rescatistaId,
    required CreatorRole creadoPor,
    required Map<String, dynamic> datos,
  }) =>
      _col.add({
        ...datos,
        'adoptanteId': adoptanteUid,
        'rescatistaId': rescatistaId,
        'creadoPor': creadoPor.firestoreValue,
        'estado': 'pendiente',
        'creadoEn': FieldValue.serverTimestamp(),
      });

  Future<void> cambiarEstado(String solicitudId, String estado) =>
      _col.doc(solicitudId).update({'estado': estado});
}
