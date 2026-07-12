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

  /// Hay al menos una solicitud PENDIENTE sobre este animal — se usa para
  /// bloquear el borrado del rescate mientras alguien espera respuesta. Si
  /// no se revisa esto, borrar el animal y después aprobar esa solicitud
  /// revienta: la transacción de [aprobarSiDisponible] intenta actualizar
  /// un documento de `rescates` que ya no existe.
  Future<bool> tienePendientesPara(String rescateId) async {
    final res = await _col
        .where('rescateId', isEqualTo: rescateId)
        .where('estado', isEqualTo: 'pendiente')
        .limit(1)
        .get();
    return res.docs.isNotEmpty;
  }

  /// Estado de la solicitud pendiente/aprobada que ya tenga [uid] sobre este
  /// animal, o `null` si no aplicó todavía. Con [rescateId] se compara por
  /// el id único del animal (dos animales con el mismo nombre no se
  /// confunden); sin él (dato legado) se cae al viejo match por nombre.
  Future<String?> estadoExistente({
    required String uid,
    required String animalNombre,
    String? rescateId,
  }) async {
    Query<Map<String, dynamic>> q = _col
        .where('adoptanteId', isEqualTo: uid)
        .where('estado', whereIn: ['pendiente', 'aprobada']);
    q = (rescateId != null && rescateId.isNotEmpty)
        ? q.where('rescateId', isEqualTo: rescateId)
        : q.where('animalNombre', isEqualTo: animalNombre);
    final res = await q.limit(1).get();
    if (res.docs.isEmpty) return null;
    return res.docs.first.data()['estado'] as String? ?? '';
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

  /// Rechaza una solicitud dejando registrado el motivo (a diferencia de
  /// [cambiarEstado], que no toca `motivoRechazo`).
  Future<void> rechazar(String solicitudId, String motivo) =>
      _col.doc(solicitudId).update({'estado': 'rechazada', 'motivoRechazo': motivo});

  /// Cuando se aprueba una solicitud, rechaza automáticamente cualquier otra
  /// solicitud PENDIENTE por el mismo animal (excepto [excluirDocId]) — ya
  /// no tiene sentido seguir considerándolas. Devuelve los datos de las que
  /// rechazó (con su id incluido) para que el llamador pueda avisarle a cada
  /// adoptante por chat.
  ///
  /// Con [rescateId] se filtra por el id único del animal; sin él (dato
  /// legado) se cae al match por nombre+dueño, que puede confundir dos
  /// animales con el mismo nombre bajo la misma cuenta en distinto rol.
  Future<List<Map<String, dynamic>>> rechazarCompetidoras({
    required String animalNombre,
    required String rescatistaId,
    required String excluirDocId,
    String? rescateId,
  }) async {
    Query<Map<String, dynamic>> q = _col
        .where('animalNombre', isEqualTo: animalNombre)
        .where('rescatistaId', isEqualTo: rescatistaId)
        .where('estado', isEqualTo: 'pendiente');
    if (rescateId != null && rescateId.isNotEmpty) {
      q = q.where('rescateId', isEqualTo: rescateId);
    }
    final otros = await q.get();
    final rechazadas = <Map<String, dynamic>>[];
    for (final doc in otros.docs) {
      if (doc.id == excluirDocId) continue;
      await doc.reference.update({
        'estado': 'rechazada',
        'motivoRechazo': 'El proceso de adopción ya fue iniciado con otro adoptante.',
      });
      rechazadas.add({...doc.data(), 'id': doc.id});
    }
    return rechazadas;
  }

  /// Aprueba [solicitudId] de forma atómica junto con el rescate
  /// [rescateId]: dentro de una transacción, lee el rescate y verifica que
  /// no tenga ya un `adoptanteIdEnProceso` de OTRO adoptante antes de
  /// aprobar. Si dos solicitudes del mismo animal se aprueban casi al
  /// mismo tiempo (dos rescatistas, dos pestañas, doble tap), la segunda
  /// en llegar ve que el animal ya quedó tomado y se RECHAZA sola en la
  /// misma transacción — nunca quedan dos adoptantes "aprobados" para un
  /// solo animal.
  ///
  /// Alcance a propósito: toca `rescates` directo (no pasa por
  /// `RescatesRepository`) porque una `Transaction` de Firestore solo puede
  /// leer/escribir referencias de documento puntuales dentro de su propio
  /// callback — no puede llamar a otro repositorio ni hacer queries. Esto
  /// es lo único que necesita ser realmente atómico; rechazar competidoras
  /// y avisar por chat siguen siendo pasos separados después (best-effort,
  /// no corrompen datos si fallan a medias).
  ///
  /// Solo sirve cuando hay [rescateId] (todas las solicitudes nuevas lo
  /// tienen). Para el dato legado sin `rescateId`, no hay documento puntual
  /// contra el cual transaccionar — ver el fallback en
  /// `solicitudes_rescatista_screen.dart`.
  ///
  /// `aprobada`: true si se aprobó. `animalEliminado`: true si se rechazó
  /// porque el rescate ya no existe (se borró mientras la solicitud seguía
  /// pendiente) — antes esto no se revisaba y `tx.update(rescateRef, ...)`
  /// sobre un documento borrado tiraba un
  /// `[cloud_firestore/invalid-argument]` sin manejar, dejando la solicitud
  /// en limbo ("esperan respuesta" para siempre, sin poder aprobar NI
  /// reintentar). El llamador usa `animalEliminado` para avisarle al
  /// adoptante con el motivo real en vez del genérico "ya tiene un proceso
  /// con otro adoptante".
  Future<({bool aprobada, bool animalEliminado})> aprobarSiDisponible({
    required String solicitudId,
    required String rescateId,
    required String adoptanteId,
    required String nuevoEstadoAdopcion,
    Map<String, dynamic> camposExtra = const {},
  }) {
    final rescateRef = _db.collection('rescates').doc(rescateId);
    final solicitudRef = _col.doc(solicitudId);

    return _db.runTransaction((tx) async {
      final rescateSnap = await tx.get(rescateRef);

      if (!rescateSnap.exists) {
        tx.update(solicitudRef, {
          'estado': 'rechazada',
          'motivoRechazo': 'Este animalito ya no está disponible en la plataforma.',
        });
        return (aprobada: false, animalEliminado: true);
      }

      final yaClaimadoPor = (rescateSnap.data()?['adoptanteIdEnProceso'] as String?) ?? '';

      if (yaClaimadoPor.isNotEmpty && yaClaimadoPor != adoptanteId) {
        tx.update(solicitudRef, {
          'estado': 'rechazada',
          'motivoRechazo': 'El proceso de adopción ya fue iniciado con otro adoptante.',
        });
        return (aprobada: false, animalEliminado: false);
      }

      tx.update(solicitudRef, {'estado': 'aprobada'});
      tx.update(rescateRef, {
        'estadoAdopcion': nuevoEstadoAdopcion,
        'adoptanteIdEnProceso': adoptanteId,
        ...camposExtra,
      });
      return (aprobada: true, animalEliminado: false);
    });
  }
}
