import 'package:cloud_firestore/cloud_firestore.dart';

/// Única puerta de entrada a la colección `hogaresDePaso` — el roster de
/// personas de confianza para hogar de paso de un albergue (mejora
/// "Red de voluntarios/hogares de paso" comparada contra software real de
/// shelters). Solo para albergues, no rescatistas — ver ARCHITECTURE.md.
class HogaresDePasoRepository {
  HogaresDePasoRepository({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('hogaresDePaso');

  /// Minúsculas y sin espacios alrededor — para comparar o guardar, nunca
  /// para mostrar. Sin esto, 'David.Casas@Gmail.com' (como lo tipeó el
  /// albergue a mano en [agregarManual]) y 'david.casas@gmail.com' (el
  /// email real de Google Sign-In que llega a [registrarAyuda], ya en
  /// minúsculas) nunca calzaban en la consulta por email — el sistema
  /// pensado justo para fusionar esos dos casos en una sola fila terminaba
  /// creando una fila duplicada para la misma persona (hallazgo de
  /// auditoría de código). Un solo lugar acá adentro para los 3 métodos
  /// que tocan email, para que no se puedan volver a desincronizar entre
  /// sí.
  String _normalizarEmail(String email) => email.trim().toLowerCase();

  Stream<QuerySnapshot<Map<String, dynamic>>> deAlbergue(String albergueId) =>
      _col.where('albergueId', isEqualTo: albergueId).snapshots();

  /// Primera fila de la red de [albergueId] con el mismo [nombre] Y el
  /// mismo [email] (sin importar mayúsculas/espacios en ninguno de los
  /// dos) — para avisar de un posible duplicado antes de agregar a mano.
  /// [agregarManual] no tenía ningún chequeo (a diferencia de
  /// [registrarAyuda], que sí fusiona por adoptanteId/email): nada impedía
  /// crear la misma persona varias veces si el albergue tocaba "Agregar" y
  /// completaba el formulario de nuevo cada vez. Hallazgo real de Eliza,
  /// con captura mostrando "Pepito Perez" repetido 3 veces.
  ///
  /// Compara nombre Y email JUNTOS (no el nombre solo) a propósito — dos
  /// personas reales pueden compartir nombre, y avisar solo por eso
  /// hubiera sido un falso positivo molesto. El email es el dato que de
  /// verdad distingue a una persona de otra con el mismo nombre, y ahora
  /// es obligatorio en el formulario de alta manual (ver
  /// _AgregarHogarSheet) exactamente para que esta comparación siempre
  /// tenga con qué trabajar. Pedido explícito de Eliza.
  ///
  /// Trae todas las filas propias (roster acotado a un albergue, nunca
  /// miles de filas) y compara en cliente — mismo criterio que
  /// RescatesRepository.buscarDuplicado: una query exacta se rompería con
  /// cualquier diferencia de mayúsculas/espacios, que es justo el caso más
  /// común al tipear el mismo dato dos veces.
  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> buscarDuplicado({
    required String albergueId,
    required String nombre,
    required String email,
  }) async {
    final nombreBuscado = nombre.trim().toLowerCase();
    final emailBuscado = _normalizarEmail(email);
    if (nombreBuscado.isEmpty || emailBuscado.isEmpty) return null;
    final snap = await _col.where('albergueId', isEqualTo: albergueId).get();
    for (final d in snap.docs) {
      final data = d.data();
      final nombreActual = ((data['nombre'] as String?) ?? '')
          .trim()
          .toLowerCase();
      final emailActual = ((data['email'] as String?) ?? '')
          .trim()
          .toLowerCase();
      if (nombreActual == nombreBuscado && emailActual == emailBuscado)
        return d;
    }
    return null;
  }

  /// Se llama al aprobar una solicitud de hogar de paso: si esa persona ya
  /// está en la red, suma 1 a `vecesAyudo`; si es la primera vez, la agrega.
  ///
  /// Antes de crear una fila nueva, revisa dos casos (en orden):
  /// 1. ¿Ya hay una fila vinculada a esta MISMA cuenta (`adoptanteId`)? —
  ///    no es la primera vez que ayuda, sumar ahí.
  /// 2. ¿Hay una fila agregada A MANO con el mismo email, todavía sin
  ///    vincular a ninguna cuenta? — es la misma persona que alguien había
  ///    anotado antes de que existiera cuenta suya en la app; se fusiona
  ///    (se le pone el vínculo real) en vez de crear una fila duplicada.
  ///    Pedido real de Eliza: agregó a "David Casas" a mano, y preguntó
  ///    qué pasaba si esa misma persona después ayudaba de verdad por la
  ///    app — sin esto, quedaban dos filas para la misma persona.
  ///
  /// Los dos chequeos son QUERIES (`where`), no un `get()` por id — a
  /// propósito: `firestore.rules` deniega la LECTURA de un documento
  /// puntual que no existe (`resource` es null ahí), pero una query nunca
  /// tiene ese problema porque solo evalúa contra documentos que sí
  /// existen (si no hay ninguno, devuelve vacío sin necesitar permiso
  /// sobre nada). Mismo motivo por el que el fallback final usa
  /// `set(merge: true)` en vez de `get()` + branch.
  Future<void> registrarAyuda({
    required String albergueId,
    required String adoptanteId,
    required String nombre,
    String? email,
  }) async {
    if (adoptanteId.isEmpty) return;

    final porCuenta = await _col
        .where('albergueId', isEqualTo: albergueId)
        .where('adoptanteId', isEqualTo: adoptanteId)
        .limit(1)
        .get();
    if (porCuenta.docs.isNotEmpty) {
      await porCuenta.docs.first.reference.update({
        if (nombre.isNotEmpty) 'nombre': nombre,
        'vecesAyudo': FieldValue.increment(1),
        'ultimaVez': FieldValue.serverTimestamp(),
      });
      return;
    }

    final emailNorm = (email == null || email.isEmpty)
        ? null
        : _normalizarEmail(email);

    if (emailNorm != null) {
      final porEmail = await _col
          .where('albergueId', isEqualTo: albergueId)
          .where('email', isEqualTo: emailNorm)
          .where('adoptanteId', isEqualTo: '')
          .limit(1)
          .get();
      if (porEmail.docs.isNotEmpty) {
        await porEmail.docs.first.reference.update({
          'adoptanteId': adoptanteId,
          if (nombre.isNotEmpty) 'nombre': nombre,
          'agregadoManualmente': false,
          'vecesAyudo': FieldValue.increment(1),
          'ultimaVez': FieldValue.serverTimestamp(),
        });
        return;
      }
    }

    await _col.doc('${albergueId}_$adoptanteId').set({
      'albergueId': albergueId,
      'adoptanteId': adoptanteId,
      if (emailNorm != null) 'email': emailNorm,
      if (nombre.isNotEmpty) 'nombre': nombre,
      'agregadoManualmente': false,
      'vecesAyudo': FieldValue.increment(1),
      'ultimaVez': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Agregar a mano a alguien de confianza que el albergue ya conoce fuera
  /// de la app — no hace falta que haya pasado por una solicitud todavía.
  /// El email es opcional pero es lo que permite fusionar esta fila más
  /// adelante si esa persona termina ayudando de verdad por la app (ver
  /// [registrarAyuda]).
  ///
  /// [timeout] vive ACÁ ADENTRO, no envuelto desde afuera — igual que en
  /// `ChatsRepository`/`conReintentoSiTokenVencido`: sin señal, un
  /// `.add()`/`.update()`/`.delete()` de Firestore no falla, se queda
  /// esperando al servidor para siempre. `agregarManual` ya tenía un
  /// try/catch en la pantalla que hoy no atrapaba nada porque nunca había
  /// una excepción real que atrapar; `actualizarContacto`/`eliminar` ni
  /// siquiera tenían eso. Hallazgo de auditoría de código.
  /// Suma a la red al cuidador de un hogar de paso puesto A MANO desde el
  /// desplegable de estado.
  ///
  /// Es el gemelo de [registrarAyuda] para el caso sin cuenta. No se puede
  /// reusar aquella: corta de entrada con `if (adoptanteId.isEmpty) return`,
  /// porque su trabajo es vincular a una cuenta real. Acá, por definición,
  /// no hay ninguna: la mayoría de los hogares de paso de un refugio son
  /// personas que ayudan y que nunca van a instalar la app.
  ///
  /// Si esa persona ya estaba en la red (mismo nombre y mismo email) le
  /// suma una ayuda en vez de crear una fila repetida. Si no la encuentra,
  /// la agrega con [agregarManual].
  ///
  /// Ojo con el caso sin email: [buscarDuplicado] necesita nombre Y email
  /// para poder afirmar que son la misma persona, así que sin email no hay
  /// forma de distinguir a dos "María" distintas y se agrega una fila
  /// nueva. Es a propósito: preferimos dos filas que puedan unirse a mano
  /// antes que fusionar por nombre a dos personas que no lo son.
  Future<void> sumarAyudaManual({
    required String albergueId,
    required String nombre,
    String email = '',
  }) async {
    if (nombre.trim().isEmpty) return;
    final yaEsta = await buscarDuplicado(
      albergueId: albergueId,
      nombre: nombre,
      email: email,
    );
    if (yaEsta != null) {
      await yaEsta.reference.update({'vecesAyudo': FieldValue.increment(1)});
      return;
    }
    await agregarManual(
      albergueId: albergueId,
      nombre: nombre.trim(),
      email: email,
      // Uno, no cero: esta persona no es un contacto anotado, se está
      // llevando a un animalito ahora mismo.
      vecesAyudo: 1,
    );
  }

  Future<void> agregarManual({
    required String albergueId,
    required String nombre,
    String telefono = '',
    String notas = '',
    String email = '',
    /// Cuántas ayudas lleva ya. Cero cuando alguien anota un contacto que
    /// conoce (todavía no cuidó a nadie), UNO cuando se agrega porque en
    /// este mismo momento se está llevando a un animalito — ver
    /// [sumarAyudaManual].
    int vecesAyudo = 0,
    Duration timeout = const Duration(seconds: 15),
  }) => _col
      .add({
        'albergueId': albergueId,
        'adoptanteId': '',
        'nombre': nombre,
        'telefono': telefono,
        'notas': notas,
        'email': _normalizarEmail(email),
        'vecesAyudo': vecesAyudo,
        'ultimaVez': null,
        'creadoEn': FieldValue.serverTimestamp(),
        'agregadoManualmente': true,
      })
      .timeout(timeout);

  /// Las filas que se agregan solas (al aprobar una solicitud) nacen sin
  /// teléfono ni notas — esto deja completarlos después, tanto para esas
  /// como para las agregadas a mano (pedido real de Eliza). También deja
  /// completar el email de una fila agregada a mano que no lo tenía, para
  /// que pueda fusionarse más adelante si esa persona ayuda de verdad.
  ///
  /// [email] es `String?` (sin valor por defecto) a propósito — antes
  /// tenía `= ''`, así que un futuro llamador que se olvidara de pasarlo
  /// (por ejemplo, una pantalla que solo quisiera actualizar el teléfono)
  /// borraba en silencio el email ya guardado, justo el dato que permite
  /// fusionar esta fila con la cuenta real de la persona más adelante (ver
  /// [registrarAyuda]). Ahora solo se toca el campo si se pasa
  /// explícitamente — la pantalla que edita el contacto sigue pudiendo
  /// vaciarlo a propósito, pasando `''` (el campo llega prellenado con el
  /// valor actual: un `''` real significa que la persona lo borró adrede).
  /// Hallazgo de auditoría de código.
  Future<void> actualizarContacto(
    String docId, {
    required String telefono,
    required String notas,
    String? email,
    Duration timeout = const Duration(seconds: 15),
  }) => _col
      .doc(docId)
      .update({
        'telefono': telefono,
        'notas': notas,
        if (email != null) 'email': _normalizarEmail(email),
      })
      .timeout(timeout);

  Future<void> eliminar(
    String docId, {
    Duration timeout = const Duration(seconds: 15),
  }) => _col.doc(docId).delete().timeout(timeout);
}
