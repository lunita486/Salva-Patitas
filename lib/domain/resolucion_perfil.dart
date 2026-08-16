/// Qué pantalla mostrar después del login, según el perfil de `usuarios`.
enum PantallaPerfil {
  seleccionRol,
  alberguePerfil,
  albergueHome,
  aliadoPerfil,
  aliadoHome,
  home,
}

/// Decide [PantallaPerfil] a partir del documento de `usuarios` ya
/// cargado — sin Firestore ni Flutter, así que se prueba con mapas a
/// mano. Antes esta decisión vivía inline en el `builder` de
/// `AuthWrapper.build()` (lib/main.dart), donde solo se podía probar
/// montando todo el widget con Firebase.
///
/// El orden importa: una cuenta con los dos roles a la vez
/// (`albergue` + `aliado`) manda a albergue primero — así se comportaba
/// el código original, se conserva tal cual acá.
PantallaPerfil resolverPantallaPerfil(Map<String, dynamic> perfil) {
  final roles = List<String>.from(perfil['roles'] as List? ?? []);
  if (roles.isEmpty) return PantallaPerfil.seleccionRol;

  if (roles.contains('albergue')) {
    final completo = (perfil['albergueNombre'] as String?)?.isNotEmpty == true;
    return completo
        ? PantallaPerfil.albergueHome
        : PantallaPerfil.alberguePerfil;
  }
  if (roles.contains('aliado')) {
    final completo = (perfil['aliadoNombre'] as String?)?.isNotEmpty == true;
    return completo ? PantallaPerfil.aliadoHome : PantallaPerfil.aliadoPerfil;
  }
  return PantallaPerfil.home;
}
