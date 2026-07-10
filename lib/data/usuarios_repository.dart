import 'package:cloud_firestore/cloud_firestore.dart';

/// Centraliza las escrituras del campo `roles` en `usuarios/{uid}`
/// (antes se escribía suelto desde ~7 pantallas de debug distintas, sin
/// validar qué valores eran válidos).
class UsuariosRepository {
  UsuariosRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  static const rolesValidos = {'adoptante', 'rescatista', 'albergue', 'aliado'};

  Future<void> actualizarRoles(String uid, List<String> roles) {
    assert(roles.every(rolesValidos.contains), 'rol inválido en $roles');
    return _db.collection('usuarios').doc(uid).update({'roles': roles});
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
    return _db.collection('usuarios').doc(uid).set({
      'nombre':   nombre,
      'email':    email,
      'foto':     foto,
      'roles':    roles,
      'ciudad':   ciudad,
      'creadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
