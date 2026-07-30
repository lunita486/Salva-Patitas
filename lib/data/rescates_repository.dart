import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'creator_role.dart';
import 'solicitudes_repository.dart';
import 'firestore_resiliencia.dart';
import 'rescate_fotos_repository.dart';

/// Única puerta de entrada a la colección `rescates`. Las pantallas no
/// deben llamar `FirebaseFirestore.instance.collection('rescates')`
/// directamente — ver ARCHITECTURE.md.
class RescatesRepository {
  RescatesRepository({FirebaseFirestore? db, FirebaseAuth? auth})
      : _db = db ?? FirebaseFirestore.instance,
        _authOverride = auth;
  final FirebaseFirestore _db;
  // FirebaseAuth.instance recién se evalúa cuando hace falta de verdad
  // (dentro de eliminar(), y solo en la rama de permission-denied) — no en
  // el constructor. Evaluarlo ahí de entrada rompía CUALQUIER test de este
  // repositorio que no pasara un `auth:` mockeado (incluidos los que ni
  // tocan eliminar()), porque FirebaseAuth.instance exige un
  // Firebase.initializeApp() que `flutter test` no corre.
  final FirebaseAuth? _authOverride;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

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

  /// True si [uid] ya tiene publicado otro animal con el mismo [nombre], la
  /// misma [especie] (sin importar mayúsculas/espacios en el nombre) Y bajo
  /// el mismo [role]. Se filtra por CreatorRole a propósito — una cuenta
  /// puede tener rol de rescatista Y de albergue a la vez, pero en la
  /// práctica eso representa a la misma persona operando dos "negocios"
  /// distintos (decisión de producto: no es realista en producción que la
  /// mayoría de las cuentas tengan doble rol, y cuando pasa, publicar el
  /// mismo nombre en cada uno por separado no es necesariamente un error).
  /// Antes no se filtraba por role y cruzaba rescatista con albergue de la
  /// misma cuenta — molestaba con avisos falsos exactamente en ese caso.
  ///
  /// Comparar también la especie evita falsos positivos con nombres
  /// populares que se repiten en animales realmente distintos — un
  /// "Richard" perro no debería chocar con un "Richard" gato del mismo rol.
  /// Comparar la foto en sí (para acercarse aún más a "duplicado real")
  /// queda pendiente — compararla a este nivel implicaría hashear el
  /// contenido de la imagen, no solo leer un campo de Firestore.
  ///
  /// El primer rescate de [uid] bajo [role] con el mismo [nombre] (y, si se
  /// pasa, la misma [especie]) — para el aviso de "posible duplicado" antes
  /// de publicar. Devuelve el documento (no solo un bool) para que la
  /// pantalla pueda ofrecer "Ver ficha existente" en vez de solo
  /// cancelar/continuar a ciegas sobre cuál es el otro animal.
  ///
  /// Un nombre vacío nunca cuenta como duplicado — el nombre es opcional y
  /// comparar vacíos contra vacíos daría falsos positivos entre animales
  /// sin nombre que no tienen nada que ver.
  ///
  /// Tolerante a fallas de red a propósito: este chequeo es un AVISO de
  /// cortesía, no una barrera de datos — su respuesta jamás debe impedir
  /// publicar. Justo después de recuperar señal (modo avión), la consulta
  /// al servidor puede fallar aunque ya haya internet (el canal tarda hasta
  /// ~1 minuto en reconectar); en ese caso se consulta la copia LOCAL, y si
  /// hasta eso falla se devuelve null (sin duplicado): mejor publicar sin
  /// el aviso que un botón "Publicar" muerto sin mensaje (las pantallas lo
  /// llaman ANTES de su manejo de errores — mismo bug de raíz que el
  /// "no pudimos verificar si se puede eliminar" de tienePendientesPara en
  /// SolicitudesRepository, ver ese comentario).
  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> buscarDuplicado({
    required String uid,
    required String nombre,
    required CreatorRole role,
    String? especie,
  }) async {
    final buscado = nombre.trim().toLowerCase();
    if (buscado.isEmpty) return null;
    final consulta = _col
        .where('rescatistaId', isEqualTo: uid)
        .where('creadoPor', isEqualTo: role.firestoreValue);
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await consulta.get();
    } catch (_) {
      try {
        snap = await consulta.get(const GetOptions(source: Source.cache));
      } catch (_) {
        return null;
      }
    }
    for (final d in snap.docs) {
      final data = d.data();
      final mismoNombre = ((data['nombre'] as String?) ?? '').trim().toLowerCase() == buscado;
      if (!mismoNombre) continue;
      if (especie != null && especie.isNotEmpty && data['especie'] != especie) continue;
      return d;
    }
    return null;
  }

  /// Conveniencia sobre [buscarDuplicado] para los llamadores (ej. el lote,
  /// que solo necesita saber si avisar) a los que no les hace falta el
  /// documento completo.
  Future<bool> existeNombre({
    required String uid,
    required String nombre,
    required CreatorRole role,
    String? especie,
  }) async =>
      (await buscarDuplicado(uid: uid, nombre: nombre, role: role, especie: especie)) != null;

  /// Todos los "nombre_especie" (nombre en minúscula) ya publicados por
  /// [uid] bajo [role], en UNA sola consulta — para chequear varios
  /// animales a la vez (el lote) sin repetir la misma consulta a
  /// [buscarDuplicado]/[existeNombre] una vez por animal (mismo filtro
  /// rescatistaId+creadoPor cada vez, hallazgo de auditoría de código:
  /// un lote de N animales hacía N viajes de red idénticos antes de
  /// arrancar a publicar).
  Future<Set<String>> nombresExistentes({
    required String uid,
    required CreatorRole role,
  }) async {
    final consulta = _col
        .where('rescatistaId', isEqualTo: uid)
        .where('creadoPor', isEqualTo: role.firestoreValue);
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await consulta.get();
    } catch (_) {
      try {
        snap = await consulta.get(const GetOptions(source: Source.cache));
      } catch (_) {
        return {};
      }
    }
    return snap.docs.map((d) {
      final data = d.data();
      final nombre = ((data['nombre'] as String?) ?? '').trim().toLowerCase();
      final especie = (data['especie'] as String?) ?? '';
      return '${nombre}_$especie';
    }).toSet();
  }

  /// Feed público de adopción — sin scope por diseño, cualquiera lo ve.
  ///
  /// Sin `orderBy('creadoEn')` a propósito: Firestore no solo ordenaría mal
  /// los documentos que no tengan ese campo (legados, o un futuro path que
  /// se olvide de setearlo) — los EXCLUIRÍA del resultado por completo,
  /// desapareciéndolos del feed en silencio. El orden por fecha se aplica
  /// del lado del cliente, en la pantalla que consume este stream.
  Stream<QuerySnapshot<Map<String, dynamic>>> feedPublico() => _col.snapshots();

  /// Stream de UN rescate por id — para pantallas que necesitan reaccionar
  /// en vivo a cambios de estado (ej. chat_screen.dart, que muestra "✅
  /// Adoptado"/"🌈 Falleció" apenas cambian, sin recargar la pantalla).
  Stream<DocumentSnapshot<Map<String, dynamic>>> porId(String rescateId) =>
      _col.doc(rescateId).snapshots();

  /// Stream por nombre+dueño — fallback para chats/solicitudes viejos
  /// guardados sin `rescateId` (ver actualizarPorNombre, mismo criterio:
  /// dato legado, puede confundirse si hay 2 animales con el mismo nombre
  /// bajo la misma cuenta en distinto rol, pero es el mejor esfuerzo
  /// posible sin ese id).
  Stream<QuerySnapshot<Map<String, dynamic>>> porNombreYDueno({
    required String rescatistaId,
    required String nombre,
  }) =>
      _col
          .where('rescatistaId', isEqualTo: rescatistaId)
          .where('nombre', isEqualTo: nombre)
          .limit(1)
          .snapshots();

  /// Lectura puntual de UN rescate por id — usada para chequear su estado
  /// actual justo antes de eliminarlo (ver editar_rescate_screen.dart y
  /// mis_rescates_screen.dart). No alcanza con el estado que la pantalla
  /// cargó al abrir: puede haber cambiado desde entonces (ej. se aprobó un
  /// hogar de paso mientras la pantalla de edición seguía abierta).
  Future<DocumentSnapshot<Map<String, dynamic>>> obtener(String rescateId) =>
      _col.doc(rescateId).get();

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

  /// Genera un id de rescate sin tocar la red (`.doc()` sin argumentos es
  /// puramente local) — para poder conocer el id ANTES de intentar el
  /// `set()` de [crear]. Necesario para hacer rollback de forma confiable:
  /// `Future.timeout()` no cancela la operación original, solo deja de
  /// esperarla. Si `crear()` usara `.add()` y el timeout se disparara antes
  /// de que la escritura realmente terminara, el llamador nunca se entera
  /// del id — pero el `.add()` original sigue corriendo en segundo plano y,
  /// si la conexión vuelve más tarde, puede terminar creando el documento
  /// igual, sin que nadie sepa que existe para poder borrarlo (bug real:
  /// publicar 2 veces sin señal dejó 2 rescates fantasma sin foto, visibles
  /// para el adoptante, porque el rollback nunca tuvo un id que borrar).
  DocumentReference<Map<String, dynamic>> nuevoRef() => _col.doc();

  Future<DocumentReference<Map<String, dynamic>>> crear({
    required String uid,
    required CreatorRole role,
    required Map<String, dynamic> datos,
    DocumentReference<Map<String, dynamic>>? ref,
  }) async {
    final destino = ref ?? _col.doc();
    await destino.set({
      ...datos,
      'rescatistaId': uid,
      'creadoPor': role.firestoreValue,
      'creadoEn': FieldValue.serverTimestamp(),
    });
    return destino;
  }

  Future<void> actualizar(String rescateId, Map<String, dynamic> cambios) =>
      _col.doc(rescateId).update(cambios);

  /// Cambia `estadoAdopcion` desde el picker de estado (`CambiarEstadoSheet`).
  /// [extra] son campos propios de ese estado (ej. `fechaAdopcion`,
  /// `motivoRegreso`, `notaFallecido`).
  ///
  /// Al volver a 'Rescatado'/'Regresado'/'Fallecido' limpia
  /// `adoptanteIdEnProceso` a propósito: ese campo lo escribe
  /// `SolicitudesRepository.aprobarSiDisponible` para saber a quién le
  /// pertenece el proceso activo, y si queda pegado después de que el
  /// animal vuelve a estar disponible, la próxima solicitud que se intente
  /// aprobar se autorrechaza para siempre (la transacción cree que YA hay
  /// un adoptante con el proceso activo, aunque ese adoptante ya no tenga
  /// nada que ver). Bug real: un animal "Regresado" y republicado como
  /// disponible no dejaba aprobar ninguna solicitud nueva.
  Future<void> cambiarEstadoAdopcion(String rescateId, String nuevoEstado, {
    Map<String, dynamic> extra = const {},
  }) {
    final limpiaClaim = nuevoEstado == 'Rescatado' || nuevoEstado == 'Regresado' || nuevoEstado == 'Fallecido';
    return _col.doc(rescateId).update({
      'estadoAdopcion': nuevoEstado,
      if (limpiaClaim) 'adoptanteIdEnProceso': FieldValue.delete(),
      ...extra,
    });
  }

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

  /// Un `permission-denied` acá casi siempre NO es un problema real de
  /// permisos — la regla de `rescates` solo compara `rescatistaId` contra
  /// el uid actual, y si la pantalla te muestra el botón de eliminar es
  /// porque ya sabe que sos el dueño. Lo que sí pasa: después de rato
  /// alternando entre modo avión y señal real (justo el patrón de una
  /// sesión larga de pruebas offline), el token de sesión puede quedar
  /// vencido sin que el refresco automático llegue a tiempo — el pedido
  /// sale con un token viejo y el servidor lo rechaza. Antes esto se
  /// mostraba tal cual, como texto técnico en inglés ("Error:
  /// [cloud_firestore/permission-denied] The caller does not have
  /// permission..."), dejando a la usuaria sin ninguna acción clara. Se
  /// fuerza un refresh del token y se reintenta UNA vez antes de
  /// rendirse — si era eso, la persona ni se entera de que pasó algo.
  Future<void> eliminar(String rescateId) async {
    // El refresh-token-y-reintentar vive en firestore_resiliencia.dart
    // (conReintentoSiTokenVencido), compartido con UsuariosRepository —
    // ver el porqué completo en el doc-comment de arriba.
    await conReintentoSiTokenVencido(() => _auth, () => _col.doc(rescateId).delete());
    // Sin esperar (fire-and-forget) a propósito: esto YA es best-effort
    // (ver doc de _borrarFavoritos), así que no tiene sentido que la
    // persona que está borrando su animal espere por una limpieza que ni
    // siquiera es su acción. Antes estaba con `await` acá, y sumaba sus
    // propios timeouts (hasta 10s) DENTRO del `eliminar()` que las
    // pantallas envuelven en su propio `.timeout(12s)` — el guard
    // `_eliminando` de mis_rescates_screen.dart/editar_rescate_screen.dart
    // se soltaba recién cuando ESTO también terminaba, no cuando el
    // borrado real (lo único que la persona ve y espera) ya había
    // pasado. El bug real que reportó Eliza: "borro un animalito bien, y
    // al borrar el siguiente dice que hay una eliminación en curso" — la
    // tarjeta ya había desaparecido, pero el guard seguía trabado
    // esperando esta limpieza silenciosa de fondo.
    _borrarFavoritos(rescateId);
  }

  /// Los `favoritos` que apuntan a este rescate no se borran solos: sin
  /// esto, un animal eliminado seguía viéndose en la pantalla de
  /// Favoritos del adoptante como si siguiera disponible para adoptar,
  /// con un botón "Adoptar" apuntando a un rescate que ya no existe (el
  /// bug real que reportó Eliza). Solo se tocan los favoritos de ESTE
  /// rescatista/albergue (regla de seguridad: `rescatistaId == uid()`,
  /// además de `adoptanteId == uid()` que ya tenían) — el dueño del
  /// favorito nunca ve este borrado como una acción suya, así que es
  /// best-effort: si falla (sin señal, error transitorio), no bloquea el
  /// borrado real que la persona pidió, y ni siquiera se espera (ver
  /// comentario en `eliminar`). La pantalla de Favoritos se defiende del
  /// lado del adoptante por si esto no llega a correr, y el Cloud
  /// Function `onRescateEliminado` (functions/index.js) lo garantiza de
  /// todas formas del lado del servidor, incluso si el borrado pasó sin
  /// señal y esto ni llegó a intentarse.
  Future<void> _borrarFavoritos(String rescateId) async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;
      // Timeouts propios, más cortos que los de las pantallas (10-12s
      // sobre eliminar() completo): sin límite acá, una consulta lenta de
      // favoritos podía estirar eliminar() hasta el timeout del llamador
      // y convertir un borrado que YA salió bien en el mensaje de "está
      // tardando" — un error fantasma por culpa de la limpieza secundaria.
      final favoritos = await _db
          .collection('favoritos')
          .where('rescateId', isEqualTo: rescateId)
          .where('rescatistaId', isEqualTo: uid)
          .get()
          .timeout(const Duration(seconds: 5));
      if (favoritos.docs.isEmpty) return;
      final batch = _db.batch();
      for (final doc in favoritos.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit().timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  /// Traduce lo que puede salir mal en [eliminar] (si el reintento con
  /// token renovado TAMBIÉN falla) a un mensaje que una persona sin
  /// conocimientos técnicos pueda entender y accionar — usado por las dos
  /// pantallas que llaman a [eliminar] (mis_rescates_screen.dart,
  /// editar_rescate_screen.dart) en vez de mostrar el texto crudo de la
  /// excepción tal cual llega.
  ///
  /// Un TimeoutException NUNCA llega acá a propósito: timeout ≠ error (el
  /// borrado queda encolado, Firestore lo aplica solo al reconectar y la
  /// Cloud Function onRescateEliminado limpia fotos/favoritos en el
  /// servidor), así que las dos pantallas lo atrapan ANTES con su propio
  /// `on TimeoutException` y muestran el mismo "Publicación eliminada"
  /// del camino feliz. Hubo dos intentos de mensaje especial para ese
  /// caso ("estamos sin señal", después "está tardando") y ambos
  /// confundieron en las pruebas reales: la tarjeta ya había
  /// desaparecido, y un aviso naranja sobre un borrado visiblemente
  /// exitoso se lee como que algo falló.
  static String mensajeErrorEliminar(Object error) {
    if (error is FirebaseException && error.code == 'permission-denied') {
      return 'No pudimos eliminar. Puede que tu sesión necesite renovarse. '
          'Cerrá sesión y volvé a entrar, o intentá de nuevo en un momento.';
    }
    return 'No se pudo eliminar. Revisá tu conexión e intentá de nuevo.';
  }

  /// Título y mensaje del diálogo que bloquea el borrado cuando el animal no
  /// está en "Rescatado". Antes vivía duplicado byte a byte en
  /// mis_rescates_screen.dart y editar_rescate_screen.dart (hallazgo de
  /// auditoría de código) — un cambio de texto necesitaba dos ediciones.
  /// "Hogar de paso"/"En proceso de adopción"/"Regresado" son reversibles
  /// (cambiando el estado a "Rescatado" se puede eliminar después);
  /// "Adoptado"/"Fallecido" son registros permanentes (pedido explícito de
  /// Eliza) sin ningún camino para desbloquearlos.
  static (String, String) mensajeBloqueoEliminar(String estado, String nombre) {
    switch (estado) {
      case 'Hogar de paso':
        return ('No se puede eliminar todavía',
            '$nombre está en hogar de paso ahora mismo. Cambiá su estado a "Rescatado" primero, y después podés eliminar la publicación.');
      case 'En proceso de adopción':
        return ('No se puede eliminar todavía',
            '$nombre tiene un proceso de adopción en curso. Cambiá su estado primero, y después podés eliminar la publicación.');
      case 'Regresado':
        return ('No se puede eliminar todavía',
            '$nombre está marcado como "Regresado". Cambiá su estado a "Rescatado" primero, y después podés eliminar la publicación.');
      case 'Adoptado':
        return ('No se puede eliminar', '$nombre ya fue adoptado. Queda como registro permanente, no se puede eliminar.');
      case 'Fallecido':
        return ('No se puede eliminar', '$nombre fue marcado como "Fallecido". Queda como registro permanente, no se puede eliminar.');
      default:
        return ('No se puede eliminar', '$nombre no se puede eliminar en su estado actual.');
    }
  }

  /// (título, mensaje) del bloqueo si [rescateId] todavía no se puede
  /// eliminar, o `null` si sí se puede — junta en un solo lugar los 3
  /// chequeos que antes vivían duplicados en mis_rescates_screen.dart y
  /// editar_rescate_screen.dart (hallazgo de auditoría de código).
  ///
  /// Los 3 chequeos corren en paralelo, no uno atrás del otro: en el caso
  /// más común (nada bloquea, se puede eliminar) los tres hacen falta
  /// igual, así que separarlos solo sumaba tiempo de espera sin necesidad
  /// (otro hallazgo de la misma auditoría). El costo es leer de más en el
  /// caso menos común donde el primer chequeo ya bloquea — un descarte
  /// barato frente a la demora de 3 viajes de red seguidos en el camino
  /// feliz.
  ///
  /// Tira una excepción si no se pudo verificar por conexión — el llamador
  /// la distingue con su propio try/catch, igual que el resto de los
  /// chequeos de esta clase (no se traga el error acá para no esconder
  /// una falla real de red detrás de un "sí se puede eliminar" falso).
  Future<(String, String)?> bloqueoParaEliminar({
    required String rescateId,
    required String nombre,
  }) async {
    // Mismo _db que este repositorio (no FirebaseFirestore.instance a
    // secas) — así un test que inyecta un Firestore fake en
    // RescatesRepository ve ese mismo fake acá adentro, en vez de que
    // este chequeo se escape a la instancia real por su cuenta.
    final solicitudesRepo = SolicitudesRepository(db: _db);
    final resultados = await Future.wait([
      solicitudesRepo.tienePendientesPara(rescateId),
      obtener(rescateId).then((d) => d.data()),
      solicitudesRepo.tuvoSolicitudAprobada(rescateId),
    ]);
    final tienePendientes = resultados[0] as bool;
    final datosActuales   = resultados[1] as Map<String, dynamic>?;
    final tuvoAprobada    = resultados[2] as bool;

    if (tienePendientes) {
      return ('No se puede eliminar todavía',
          '$nombre tiene una solicitud esperando respuesta. Aprobala o rechazala primero, y después podés eliminar la publicación.');
    }
    final estadoActual = datosActuales?['estadoAdopcion'] as String? ?? 'Rescatado';
    if (estadoActual != 'Rescatado') {
      return mensajeBloqueoEliminar(estadoActual, nombre);
    }
    if (tuvoAprobada) {
      return ('No se puede eliminar',
          '$nombre tuvo una adopción o un hogar de paso aprobado alguna vez. '
          'Queda como registro permanente, marcalo como "Adoptado", "Regresado" o "Fallecido" en vez de eliminarlo.');
    }
    return null;
  }

  /// Stream de varios rescates a la vez por su id — para pantallas como
  /// Favoritos, que necesitan el estado de N animales guardados sin abrir
  /// un listener por cada uno. Antes favoritos_screen.dart armaba esta
  /// consulta directo contra Firestore en vez de pasar por acá (hallazgo
  /// de auditoría de código — ver ARCHITECTURE.md).
  ///
  /// [ids] ya tiene que venir recortado a como mucho 30 (límite de
  /// Firestore para `whereIn`) — el recorte queda del lado del llamador
  /// porque suele necesitar saber CUÁLES ids terminaron consultados de
  /// verdad, para no confundir "no vino en la respuesta" con "nunca se
  /// preguntó por él" (ej. para detectar favoritos huérfanos).
  Stream<QuerySnapshot<Map<String, dynamic>>> porIds(List<String> ids) {
    if (ids.isEmpty) return const Stream.empty();
    return _col.where(FieldPath.documentId, whereIn: ids).snapshots();
  }

  /// Crea un rescate y sube su(s) foto(s): "doc sin fotos → subir en
  /// paralelo → vincular" — antes duplicado (~80 líneas) entre
  /// subir_rescate_screen.dart y subir_lote_screen.dart (hallazgo de
  /// auditoría de código).
  ///
  /// [datos] son los campos propios del formulario (nombre, especie,
  /// etc. — SIN fotoUrl/fotoUrl2, eso lo agrega este método). [fotos] es
  /// la foto 1 (obligatoria) y, si hay, la 2 (opcional), ya normalizadas.
  /// [onProgreso] es opcional — el alta individual lo usa para su barra de
  /// progreso; el lote no pasa nada y no pierde nada por no pasarlo.
  ///
  /// Si algo falla ANTES de terminar (el doc, la foto obligatoria, o el
  /// paso de vincular), hace rollback completo (borra las fotos que
  /// llegaron a subir + el doc) y RELANZA la excepción tal cual — este
  /// método no decide qué mensaje mostrar ni si abortar del todo o seguir
  /// con el resto de un lote, eso lo resuelve cada pantalla llamadora con
  /// su propio try/catch, igual que antes.
  ///
  /// Si falla solo la foto 2 (opcional), no hay rollback: la publicación
  /// se completa igual y `foto2Fallo` queda en `true` para que el
  /// llamador pueda avisar "se publicó, pero la segunda foto no subió".
  Future<({String rescateId, bool foto2Fallo})> publicarConFotos({
    required String uid,
    required CreatorRole role,
    required Map<String, dynamic> datos,
    required List<Uint8List> fotos,
    void Function(double progreso)? onProgreso,
  }) async {
    final fotosRepo = RescateFotosRepository();
    String? rescateId;
    try {
      // El id se genera ACÁ (local, sin red) y se asigna a rescateId ANTES
      // del await de crear() — Future.timeout() no cancela la escritura
      // original, así que si el timeout se dispara primero, el create
      // puede terminar solo en segundo plano y crear el documento igual
      // cuando vuelva la señal. Con el id ya conocido, el rollback de
      // abajo sabe qué borrar aunque eso pase; si no, quedaba un rescate
      // fantasma sin foto (bug real reportado por Eliza).
      final nuevaRef = nuevoRef();
      rescateId = nuevaRef.id;
      await crear(ref: nuevaRef, uid: uid, role: role, datos: datos)
          .timeout(const Duration(seconds: 15), onTimeout: () =>
              throw Exception('No hay conexión a internet.'));

      double progreso1 = 0, progreso2 = 0;
      var foto2Fallo = false;
      void actualizarProgreso() {
        onProgreso?.call(fotos.length > 1 ? (progreso1 + progreso2) / 2 : progreso1);
      }

      final idRescate = rescateId;
      Future<String?> subirFoto2(Uint8List bytes) async {
        try {
          return await fotosRepo.subir(
            rescateId: idRescate, slot: 2, bytes: bytes,
            onProgreso: (p) { progreso2 = p; actualizarProgreso(); },
          ).timeout(const Duration(seconds: 45), onTimeout: () =>
              throw Exception('tiempo agotado'));
        } catch (_) {
          foto2Fallo = true;
          return null;
        }
      }

      final resultados = await Future.wait([
        fotosRepo.subir(
          rescateId: idRescate, slot: 1, bytes: fotos[0],
          onProgreso: (p) { progreso1 = p; actualizarProgreso(); },
        ).timeout(const Duration(seconds: 45), onTimeout: () =>
            throw Exception('No hay conexión a internet.')),
        if (fotos.length > 1) subirFoto2(fotos[1]),
      ]);
      final fotoUrl = resultados[0]!;
      final fotoUrl2 = resultados.length > 1 ? resultados[1] : null;

      await actualizar(rescateId, {
        'fotoUrl': fotoUrl,
        if (fotoUrl2 != null) 'fotoUrl2': fotoUrl2,
      }).timeout(const Duration(seconds: 15), onTimeout: () =>
          throw Exception('No hay conexión a internet.'));

      return (rescateId: rescateId, foto2Fallo: foto2Fallo);
    } catch (_) {
      // Orden importa: storage.rules valida dueño de una foto leyendo
      // rescates/{id}.rescatistaId — si el doc de Firestore se borra
      // PRIMERO, esa lectura falla (documento inexistente) y la limpieza
      // de Storage queda con permission-denied, dejando fotos huérfanas.
      if (rescateId != null) {
        final id = rescateId;
        try { await fotosRepo.eliminarTodas(id).timeout(const Duration(seconds: 10)); } catch (_) {}
        try { await eliminar(id).timeout(const Duration(seconds: 10)); } catch (_) {}
      }
      rethrow;
    }
  }
}
