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
}
