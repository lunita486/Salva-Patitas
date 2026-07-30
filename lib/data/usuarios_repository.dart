import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firestore_resiliencia.dart';

/// Centraliza las escrituras del campo `roles` en `usuarios/{uid}`
/// (antes se escribía suelto desde ~7 pantallas de debug distintas, sin
/// validar qué valores eran válidos).
class UsuariosRepository {
  UsuariosRepository({FirebaseFirestore? db, FirebaseAuth? auth})
      : _db = db ?? FirebaseFirestore.instance,
        _authOverride = auth;
  final FirebaseFirestore _db;
  // Lazy, mismo motivo que en RescatesRepository: evaluar FirebaseAuth.instance
  // en el constructor rompe cualquier test que no pase un auth mockeado.
  final FirebaseAuth? _authOverride;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  static const rolesValidos = {'adoptante', 'rescatista', 'albergue', 'aliado'};

  Future<void> actualizarRoles(String uid, List<String> roles) {
    assert(roles.every(rolesValidos.contains), 'rol inválido en $roles');
    // Un permission-denied acá casi siempre es un token vencido, no falta
    // de permiso real (ver conReintentoSiTokenVencido en
    // firestore_resiliencia.dart) — mismo patrón que
    // RescatesRepository.eliminar(). El bug real: justo después de un
    // borrado masivo de cuentas de prueba, una cuenta que recién inicia
    // sesión puede traer un token viejo, y antes esto se mostraba como
    // "revisá tu conexión" dejando a la persona trabada sin poder elegir rol.
    return conReintentoSiTokenVencido(() => _auth,
        () => _db.collection('usuarios').doc(uid).update({'roles': roles}));
  }

  /// Crea el perfil inicial de la cuenta (onboarding). `SetOptions(merge: true)`
  /// a propósito: si el doc ya existía — por ejemplo porque la pantalla de
  /// selección de rol se mostró por un falso "no existe" de la caché — NO
  /// pisa campos que no son suyos (fcmToken, fotoBase64, albergueNombre,
  /// perfilAdopcion...). Antes esto era un `set()` sin merge directo en la
  /// pantalla y borraba el perfil entero de un usuario existente.
  Future<void> crearPerfil({
    required String uid,
    required String nombre,
    String? email,
    String? foto,
    required List<String> roles,
    String ciudad = '',
  }) {
    assert(roles.every(rolesValidos.contains), 'rol inválido en $roles');
    return conReintentoSiTokenVencido(() => _auth, () => _db.collection('usuarios').doc(uid).set({
      'nombre':   nombre,
      'email':    email,
      'foto':     foto,
      'roles':    roles,
      'ciudad':   ciudad,
      'creadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)));
  }

  /// Asegura que el doc usuarios/{uid} EXISTA apenas la cuenta inicia
  /// sesión, con sus datos básicos pero SIN roles — se llama desde el flujo
  /// de login (auth_helper.dart), antes de que la persona elija rol.
  ///
  /// Por qué existe: AuthWrapper (main.dart) solo puede mandar a una cuenta
  /// al onboarding cuando el SERVIDOR le confirma "este perfil no existe" —
  /// confiar en la caché mandaría a usuarios existentes a pisarse el perfil.
  /// Pero esa confirmación depende de que el canal de escucha de Firestore
  /// esté sano justo en ese momento, y tras un cambio de cuenta puede
  /// quedar mudo un rato — el bug real: una cuenta nueva (sin perfil) se
  /// quedaba en el spinner de arranque para siempre, mientras las cuentas
  /// CON perfil entraban al toque porque a ellas la caché les alcanza. Toda
  /// persona nueva pasa por ese camino frágil en su primer ingreso.
  ///
  /// Con este write el camino frágil desaparece: la escritura queda en la
  /// caché local al instante (ni siquiera necesita señal), el stream de
  /// AuthWrapper emite "existe" de inmediato, y el guard de roles vacíos lo
  /// manda a elegir rol sin esperar ninguna confirmación del servidor.
  ///
  /// merge: true y sin tocar `roles`, a propósito — sobre una cuenta
  /// existente esto solo refresca nombre/email/foto y no pisa nada más.
  Future<void> asegurarPerfilBase({
    required String uid,
    String? nombre,
    String? email,
    String? foto,
  }) {
    return _db.collection('usuarios').doc(uid).set({
      if (nombre != null && nombre.isNotEmpty) 'nombre': nombre,
      if (email != null && email.isNotEmpty) 'email': email,
      if (foto != null && foto.isNotEmpty) 'foto': foto,
    }, SetOptions(merge: true));
  }
}
