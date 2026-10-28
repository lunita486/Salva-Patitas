import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'cuenta_repository.dart';

/// Equipo del albergue (PLAN-EQUIPO-ALBERGUE.md).
///
/// Todo lo que CAMBIA algo del equipo pasa por las Cloud Functions de
/// functions/equipo.js: firestore.rules no deja escribir membresias,
/// invitaciones ni equipos desde la app. Acá solo se leen, siempre con los
/// mismos filtros que exigen las reglas (si una consulta pudiera traer algo
/// que no se puede leer, Firestore la rechaza entera).
///
/// La membresía NO es un rol: no se guarda en `usuarios.roles` y no cambia
/// qué pantalla de inicio ve la persona. Es un contexto aparte ("Mi equipo").
class EquipoRepository {
  EquipoRepository({FirebaseFirestore? db, LlamarFuncion? llamar})
    : _db = db ?? FirebaseFirestore.instance,
      _llamar = llamar ?? _llamarFuncion;

  final FirebaseFirestore _db;
  final LlamarFuncion _llamar;

  // Misma región que el resto de las Functions (ver CuentaRepository.region).
  static Future<Object?> _llamarFuncion(String nombre, Map<String, dynamic> datos) async {
    final r = await FirebaseFunctions.instanceFor(region: CuentaRepository.region)
        .httpsCallable(nombre)
        .call(datos)
        .timeout(const Duration(seconds: 30));
    return r.data;
  }

  // ── Lecturas ───────────────────────────────────────────────────────────

  /// La membresía de [uid], o null si nunca fue de un equipo.
  Stream<Membresia?> miMembresia(String uid) => _db
      .collection('membresias')
      .doc(uid)
      .snapshots()
      .map((d) => d.exists ? Membresia.desde(d.id, d.data()!) : null);

  /// Miembros activos del albergue [albergueId] (solo lo lee su responsable).
  Stream<List<Membresia>> miembrosDe(String albergueId) => _db
      .collection('membresias')
      .where('albergueId', isEqualTo: albergueId)
      .where('estado', isEqualTo: 'activa')
      .snapshots()
      .map((s) => s.docs.map((d) => Membresia.desde(d.id, d.data())).toList()
        ..sort((a, b) => a.nombreVisible.toLowerCase().compareTo(b.nombreVisible.toLowerCase())));

  /// Invitaciones pendientes y vigentes que mandó el albergue [albergueId].
  Stream<List<InvitacionEquipo>> invitacionesDe(String albergueId, {DateTime Function()? ahora}) => _db
      .collection('invitaciones')
      .where('albergueId', isEqualTo: albergueId)
      .where('estado', isEqualTo: 'pendiente')
      .snapshots()
      .map((s) => _vigentes(s, ahora));

  /// Invitaciones pendientes y vigentes para el correo [email]. Las reglas
  /// solo dejan leerlas con el correo verificado de la sesión.
  Stream<List<InvitacionEquipo>> invitacionesPara(String email, {DateTime Function()? ahora}) {
    final correo = normalizarEmail(email);
    if (correo.isEmpty) return Stream.value(const []);
    return _db
        .collection('invitaciones')
        .where('emailDestino', isEqualTo: correo)
        .where('estado', isEqualTo: 'pendiente')
        .snapshots()
        .map((s) => _vigentes(s, ahora));
  }

  List<InvitacionEquipo> _vigentes(QuerySnapshot<Map<String, dynamic>> s, DateTime Function()? ahora) {
    final t = (ahora ?? DateTime.now)();
    return s.docs.map((d) => InvitacionEquipo.desde(d.id, d.data())).where((i) => i.vigente(t)).toList()
      ..sort((a, b) => (a.expiraEn ?? t).compareTo(b.expiraEn ?? t));
  }

  static String normalizarEmail(String? email) => (email ?? '').trim().toLowerCase();

  /// Nombre público del albergue (usuarios/{albergueId}.albergueNombre, que
  /// cualquier cuenta con sesión ya puede leer: es su perfil público).
  Stream<String> nombreDeAlbergue(String albergueId) => _db
      .collection('usuarios')
      .doc(albergueId)
      .snapshots()
      .map((d) => (d.data()?['albergueNombre'] as String?)?.trim() ?? '')
      .map((n) => n.isEmpty ? 'El albergue' : n);

  // ── Acciones (Cloud Functions) ─────────────────────────────────────────

  Future<void> invitar(String email) => _ejecutar('invitarMiembro', {'email': normalizarEmail(email)});

  /// Devuelve el id del albergue al que se sumó.
  Future<String?> aceptar(String invitacionId) async {
    final r = await _ejecutar('aceptarInvitacion', {'invitacionId': invitacionId});
    return r is Map ? r['albergueId'] as String? : null;
  }

  Future<void> rechazar(String invitacionId) => _ejecutar('rechazarInvitacion', {'invitacionId': invitacionId});

  Future<void> cancelar(String invitacionId) => _ejecutar('cancelarInvitacion', {'invitacionId': invitacionId});

  Future<void> revocar(String miembroUid) => _ejecutar('revocarMiembro', {'miembroUid': miembroUid});

  Future<void> salir() => _ejecutar('salirDelEquipo', {});

  Future<Object?> _ejecutar(String funcion, Map<String, dynamic> datos) async {
    try {
      return await _llamar(funcion, datos);
    } on FirebaseFunctionsException catch (e) {
      throw EquipoError.desde(e.code, e.message);
    } on TimeoutException {
      throw const EquipoError(
        'Está tardando más de lo normal. Revisá tu conexión: puede que se haya hecho igual.',
      );
    }
  }
}

typedef LlamarFuncion = Future<Object?> Function(String nombre, Map<String, dynamic> datos);

/// Error para mostrar tal cual. Los mensajes de negocio ya vienen armados
/// por el servidor (equipo_logica.js); los técnicos se traducen acá.
class EquipoError implements Exception {
  const EquipoError(this.mensaje, {this.codigo});
  final String mensaje;
  final String? codigo;

  // Estos códigos los usa equipo_logica.js con mensajes pensados para la
  // persona. Cualquier otro (internal, unavailable...) es técnico.
  static const _deNegocio = {
    'invalid-argument', 'permission-denied', 'not-found', 'already-exists',
    'failed-precondition', 'resource-exhausted', 'unauthenticated',
  };

  factory EquipoError.desde(String codigo, String? mensaje) {
    if (_deNegocio.contains(codigo) && (mensaje ?? '').trim().isNotEmpty) {
      return EquipoError(mensaje!.trim(), codigo: codigo);
    }
    if (codigo == 'unavailable' || codigo == 'deadline-exceeded') {
      return EquipoError('No hay conexión con el servidor. Probá de nuevo en un momento.', codigo: codigo);
    }
    return EquipoError('No se pudo completar. Probá de nuevo en un momento.', codigo: codigo);
  }

  static String mensajeDe(Object e) =>
      e is EquipoError ? e.mensaje : 'No se pudo completar. Probá de nuevo en un momento.';

  @override
  String toString() => mensaje;
}

DateTime? _fecha(Object? v) => v is Timestamp ? v.toDate() : null;

class Membresia {
  const Membresia({
    required this.uid,
    required this.albergueId,
    required this.estado,
    this.nombre = '',
    this.email = '',
    this.desde,
  });

  factory Membresia.desde(String uid, Map<String, dynamic> d) => Membresia(
    uid: uid,
    albergueId: d['albergueId'] as String? ?? '',
    estado: d['estado'] as String? ?? '',
    nombre: d['nombre'] as String? ?? '',
    email: d['email'] as String? ?? '',
    desde: _fecha(d['desde']),
  );

  final String uid;
  final String albergueId;
  final String estado;
  final String nombre;
  final String email;
  final DateTime? desde;

  bool get activa => estado == 'activa' && albergueId.isNotEmpty;
  String get nombreVisible => nombre.trim().isNotEmpty ? nombre.trim() : email;
}

class InvitacionEquipo {
  const InvitacionEquipo({
    required this.id,
    required this.albergueId,
    required this.emailDestino,
    required this.estado,
    this.albergueNombre = '',
    this.expiraEn,
  });

  factory InvitacionEquipo.desde(String id, Map<String, dynamic> d) => InvitacionEquipo(
    id: id,
    albergueId: d['albergueId'] as String? ?? '',
    emailDestino: d['emailDestino'] as String? ?? '',
    estado: d['estado'] as String? ?? '',
    albergueNombre: d['albergueNombre'] as String? ?? '',
    expiraEn: _fecha(d['expiraEn']),
  );

  final String id;
  final String albergueId;
  final String emailDestino;
  final String estado;
  final String albergueNombre;
  final DateTime? expiraEn;

  /// Mismo criterio que invitacionVigente en functions/equipo_logica.js.
  bool vigente(DateTime ahora) => estado == 'pendiente' && expiraEn != null && expiraEn!.isAfter(ahora);

  /// "Vence en 3 días", "Vence hoy".
  String venceEnTexto(DateTime ahora) {
    if (expiraEn == null) return '';
    final horas = expiraEn!.difference(ahora).inHours;
    if (horas < 24) return 'Vence hoy';
    // Redondeado, no truncado: recién creada (6 días y 23 horas) dice 7.
    final dias = (horas / 24).round();
    return dias == 1 ? 'Vence en 1 día' : 'Vence en $dias días';
  }

  /// Lo que ve la persona invitada: cuánto tiempo tiene para responder.
  String plazoParaResponder(DateTime ahora) {
    if (expiraEn == null) return '';
    final horas = expiraEn!.difference(ahora).inHours;
    if (horas < 24) return 'Respondé hoy: después vence';
    final dias = (horas / 24).round();
    return dias == 1 ? 'Tenés 1 día para responder' : 'Tenés $dias días para responder';
  }
}
