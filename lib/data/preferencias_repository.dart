import 'package:cloud_firestore/cloud_firestore.dart';

/// Arregla un bug real: antes, `configuracion_screens.dart` leía/escribía
/// un único documento fijo (`preferencias/adoptante`) compartido por TODOS
/// los usuarios. Acá el id del documento es siempre el uid.
class PreferenciasRepository {
  PreferenciasRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection('preferencias').doc(uid);

  Stream<DocumentSnapshot<Map<String, dynamic>>> stream(String uid) => _doc(uid).snapshots();

  Future<void> actualizar(String uid, Map<String, dynamic> cambios) =>
      _doc(uid).set(cambios, SetOptions(merge: true));
}
