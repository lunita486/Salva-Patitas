import 'package:cloud_firestore/cloud_firestore.dart';
import 'creator_role.dart';
import 'firestore_resiliencia.dart';

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
  /// bloquear el borrado del rescate mientras alguien espera respuesta,
  /// para no dejarlo esperando una respuesta que nunca va a llegar.
  ///
  /// Este chequeo es una cortesía de UX, NO la barrera de datos real: si
  /// una solicitud pendiente se le escapa (borrado con caché desactualizada)
  /// y el animal se elimina igual, [aprobarSiDisponible] ya se protege sola
  /// — detecta que el rescate no existe y auto-rechaza la solicitud con un
  /// motivo honesto (`animalEliminado`). Nada se corrompe. Por eso acá se
  /// puede ser tolerante a fallas de red en vez de bloquear a la usuaria.
  ///
  /// Dos capas de tolerancia:
  ///  1. Reintento corto (ver [_conReintento]) — cubre el tropiezo de
  ///     "recién vuelve la señal y el canal está reconectando".
  ///  2. Si el servidor sigue sin responder, se consulta la COPIA LOCAL
  ///     (Source.cache). Tras salir de modo avión, la reconexión del canal
  ///     de Firestore puede tardar hasta ~1 minuto (backoff exponencial), y
  ///     el reintento corto no alcanza — el bug real: internet ya puesto y
  ///     "no pudimos verificar si se puede eliminar" en cada tap, tanto
  ///     desde la canequita como desde editar → eliminar.
  /// Solo si hasta la caché falla (rarísimo) se propaga el error y las
  /// pantallas muestran el mensaje de conexión.
  Future<bool> tienePendientesPara(String rescateId, {required String rescatistaId}) =>
      _hayAlguna(rescateId: rescateId, rescatistaId: rescatistaId, estado: 'pendiente');

  /// Motor compartido de [tienePendientesPara] y [tuvoSolicitudAprobada]:
  /// "¿existe al menos una solicitud en [estado] para este animal?".
  ///
  /// El filtro por [rescatistaId] no es de más — es lo que hace que la
  /// consulta funcione. Las reglas solo dejan leer una solicitud a sus dos
  /// partes (`adoptanteId` o `rescatistaId`), y Firestore no filtra: si una
  /// consulta PODRÍA devolver algo que no tenés permiso de leer, la rechaza
  /// entera. Sin este `where`, el servidor contestaba permission-denied
  /// SIEMPRE y el `catch` de abajo lo tapaba cayendo a la caché del
  /// teléfono: el bloqueo de borrado nunca llegó a consultar al servidor, y
  /// en un teléfono sin nada cacheado (nunca abrió Solicitudes) contestaba
  /// "no hay nada" y dejaba borrar igual. Compilaba, pasaba los tests
  /// (fake_cloud_firestore no aplica reglas) y fallaba solo en producción,
  /// en silencio. Verificado contra el emulador en test_rules/.
  Future<bool> _hayAlguna({
    required String rescateId,
    required String rescatistaId,
    required String estado,
  }) async {
    final q = _col
        .where('rescatistaId', isEqualTo: rescatistaId)
        .where('rescateId', isEqualTo: rescateId)
        .where('estado', isEqualTo: estado)
        .limit(1);
    try {
      final res = await conReintento(() => q.get());
      return res.docs.isNotEmpty;
    } on FirebaseException catch (e) {
      // permission-denied NO es un problema de red: significa que la
      // consulta no está acotada a lo que las reglas dejan leer. Caer a la
      // caché acá convertiría un error de programación en un "no hay nada"
      // silencioso — justo lo que escondió este bug hasta ahora. Se propaga
      // para que la pantalla bloquee el borrado en vez de dejarlo pasar.
      if (e.code == 'permission-denied') rethrow;
      return _desdeCache(q);
    } catch (_) {
      return _desdeCache(q);
    }
  }

  Future<bool> _desdeCache(Query<Map<String, dynamic>> q) async {
    final res = await q.get(const GetOptions(source: Source.cache));
    return res.docs.isNotEmpty;
  }

  /// True si [rescateId] tuvo ALGUNA VEZ una solicitud aprobada (adopción
  /// u hogar de paso) — sin importar el estado ACTUAL del animal. Usado
  /// para bloquear el borrado incluso si alguien revirtió el estado a
  /// "Rescatado" a mano: una vez que un adoptante real pasó por acá, el
  /// registro queda protegido igual que "Adoptado"/"Hogar de paso" activo.
  /// Bug real reportado por Eliza: un animal pasó de "En proceso de
  /// adopción" a "Rescatado" (revirtiendo el estado a mano) y se pudo
  /// eliminar, dejando la solicitud del adoptante ("aprobada") apuntando a
  /// un rescate que ya no existe.
  ///
  /// Mismo criterio de tolerancia a fallas que [tienePendientesPara]: si
  /// el servidor no responde, reintenta una vez, y si sigue sin responder
  /// cae a la copia local en caché.
  Future<bool> tuvoSolicitudAprobada(String rescateId, {required String rescatistaId}) =>
      _hayAlguna(rescateId: rescateId, rescatistaId: rescatistaId, estado: 'aprobada');

  /// Estado de la solicitud pendiente/aprobada que ya tenga [uid] sobre este
  /// animal, o `null` si no aplicó todavía. Con [rescateId] se compara por
  /// el id único del animal (dos animales con el mismo nombre no se
  /// confunden); sin él (dato legado) se cae al viejo match por nombre.
  ///
  /// Mismo criterio de tolerancia a fallas que [_hayAlguna]: reintenta una
  /// vez, y si el servidor sigue sin responder cae a la copia local en
  /// caché — antes esto era un `await` suelto sin ningún respaldo, y la
  /// pantalla que lo llama (el paso final para pedir adoptar) no tenía
  /// forma de distinguir "todavía cargando" de "se colgó para siempre".
  /// Hallazgo de auditoría de código.
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
    q = q.limit(1);
    QuerySnapshot<Map<String, dynamic>> res;
    try {
      res = await conReintento(() => q.get());
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') rethrow;
      res = await q.get(const GetOptions(source: Source.cache));
    } catch (_) {
      res = await q.get(const GetOptions(source: Source.cache));
    }
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

  /// Registra que el adoptante aceptó el compromiso de adopción
  /// (esterilización, no reventa, devolución en vez de abandono) — la
  /// versión simple de "registro del acuerdo de adopción": no hay firma
  /// dibujada ni PDF, la constancia es que quedó ligada a la cuenta
  /// autenticada del adoptante, con la fecha del servidor, dentro de la
  /// misma solicitud ya aprobada. Solo el propio adoptante puede llamarlo
  /// (ver firestore.rules) y solo una vez la solicitud está aprobada.
  Future<void> aceptarAcuerdo(String solicitudId) => _col.doc(solicitudId).update({
        'acuerdoAceptado': true,
        'acuerdoAceptadoEn': FieldValue.serverTimestamp(),
      });

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
  ///
  /// Los rechazos van en un solo `WriteBatch` (todo o nada), no uno por
  /// uno como antes — si la señal se cortaba a mitad del loop secuencial,
  /// algunos competidores quedaban rechazados y otros seguían "pendiente"
  /// sobre un animal que ya se fue con otro adoptante, sin que nadie les
  /// avisara (el llamador usa la lista devuelta para mandarles el aviso
  /// por chat — una solicitud que el batch nunca llegó a rechazar tampoco
  /// entra en esa lista, así que ni se entera). Hallazgo de auditoría de
  /// código.
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
    final batch = _db.batch();
    for (final doc in otros.docs) {
      if (doc.id == excluirDocId) continue;
      batch.update(doc.reference, {
        'estado': 'rechazada',
        'motivoRechazo': 'El proceso de adopción ya fue iniciado con otro adoptante.',
      });
      rechazadas.add({...doc.data(), 'id': doc.id});
    }
    if (rechazadas.isNotEmpty) await batch.commit();
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
