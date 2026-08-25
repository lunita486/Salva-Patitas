import 'package:cloud_firestore/cloud_firestore.dart';

/// Única puerta de entrada a la colección `favoritos`. Ver ARCHITECTURE.md.
///
/// Un favorito guarda una COPIA de los datos del animal (nombre, foto,
/// ubicación...) tomada en el momento de guardarlo, para poder dibujar la
/// grilla sin leer cada rescate por separado. Esa copia envejece — es la
/// misma familia de problemas que costó toda esta sesión — y por eso
/// `favoritos_screen.dart` contrasta cada favorito contra el rescate REAL
/// antes de mostrarlo. Tener las consultas acá es lo que hace que ese
/// contraste se pueda razonar en un solo lugar en vez de repetirse.
class FavoritosRepository {
  FavoritosRepository({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('favoritos');

  /// Id determinístico de un favorito: la misma persona sobre el mismo
  /// animal siempre da el mismo documento, así guardar dos veces no crea
  /// duplicados.
  ///
  /// Sin `rescateId` (favoritos viejos, de antes de que ese campo se
  /// guardara) se cae a un id derivado del NOMBRE — por eso este método
  /// existe en vez de armar el id en la pantalla: la regla de "cuál es el
  /// id de este favorito" tiene que ser idéntica al guardar y al borrar, o
  /// se borra un documento distinto del que se guardó.
  static String idDe({
    required String uid,
    required String rescateId,
    required String animalNombre,
  }) => rescateId.isNotEmpty
      ? '${uid}_$rescateId'
      : '${uid}_${animalNombre.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

  /// Los favoritos de [uid], en vivo.
  Stream<QuerySnapshot<Map<String, dynamic>>> mios(String uid) =>
      _col.where('adoptanteId', isEqualTo: uid).snapshots();

  /// Guarda (o refresca) un favorito. `merge` a propósito: si ya existía,
  /// actualiza la copia en vez de perder lo que no venga en [datos].
  Future<void> guardar({
    required String uid,
    required String rescateId,
    required String animalNombre,
    required Map<String, dynamic> datos,
  }) => _col
      .doc(idDe(uid: uid, rescateId: rescateId, animalNombre: animalNombre))
      .set({
        ...datos,
        'adoptanteId': uid,
        'creadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Future<void> eliminar(String favoritoId) => _col.doc(favoritoId).delete();

  /// Todos los favoritos que apuntan a [rescateId] y pertenecen a los
  /// animales de [rescatistaId] — para limpiarlos cuando ese animal se
  /// elimina.
  ///
  /// El filtro por `rescatistaId` no es de más: las reglas solo dejan que
  /// el dueño del animal toque estos documentos, y Firestore rechaza
  /// ENTERA cualquier consulta que pudiera devolver algo sin permiso (el
  /// mismo motivo, y el mismo bug, que documenta
  /// `SolicitudesRepository._hayAlguna`).
  Future<QuerySnapshot<Map<String, dynamic>>> deRescate({
    required String rescateId,
    required String rescatistaId,
  }) => _col
      .where('rescateId', isEqualTo: rescateId)
      .where('rescatistaId', isEqualTo: rescatistaId)
      .get();
}
