import 'package:flutter/material.dart';

import '../data/sandbox.dart';
import 'cambiar_rol_debug.dart';

/// El botón morado que deja entrar a cualquier rol con la misma cuenta.
///
/// **Por qué existe como widget.** Estaba escrito cinco veces (home,
/// aliado_home, aliado_perfil, albergue_home, albergue_perfil), idéntico
/// salvo el `heroTag`, y las cinco copias preguntaban por `kDebugMode` a
/// secas. Eso lo dejaba afuera de las builds de PROFILE, que son las únicas
/// que corren a velocidad usable en el emulador de Android — así que el
/// botón desaparecía justo donde más falta hacía. Con una sola definición,
/// arreglar el criterio es cambiar [enModoPruebas] en un lugar; con cinco,
/// era acordarse de cinco.
///
/// Devuelve `null` en release, que es lo que espera `floatingActionButton`.
/// Como [enModoPruebas] es una constante de compilación, en un APK de
/// release este archivo entero se elimina del binario.
///
/// [heroTag] hace falta cuando la pantalla ya tiene otro FAB: dos
/// FloatingActionButton sin tag distinto en la misma ruta hacen explotar la
/// animación de Hero.
Widget? botonCambiarRol(
  BuildContext context, {
  Object? heroTag,
  VoidCallback? alVolver,
}) {
  if (!enModoPruebas) return null;
  return FloatingActionButton.small(
    heroTag: heroTag,
    onPressed: () async {
      await mostrarCambiarRolDebug(context);
      alVolver?.call();
    },
    backgroundColor: Colors.purple.shade100,
    elevation: 4,
    tooltip: 'Cambiar rol',
    child: Icon(Icons.developer_mode, color: Colors.purple.shade700),
  );
}

/// La misma función, con forma de círculo suelto en vez de FAB.
///
/// Las dos pantallas de albergue no pueden colgar un `floatingActionButton`
/// donde lo necesitan (una lo mete adentro de una Column, la otra lo apoya
/// sobre un Stack), así que usan esta forma. El contenido es el mismo y por
/// eso vive al lado de [botonCambiarRol]: si mañana cambia el ícono o el
/// color, cambia para las cinco pantallas de una vez.
///
/// Devuelve `null` en release, igual que [botonCambiarRol]. Quien lo use
/// tiene que aceptar un `Widget?` en su lista de hijos (con `if (x != null)`
/// o `?? const SizedBox.shrink()`).
Widget? chipCambiarRol(BuildContext context, {VoidCallback? alVolver}) {
  if (!enModoPruebas) return null;
  return Tooltip(
    message: 'Cambiar rol',
    child: GestureDetector(
      onTap: () async {
        await mostrarCambiarRolDebug(context);
        alVolver?.call();
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.purple.shade100,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          Icons.developer_mode,
          color: Colors.purple.shade700,
          size: 18,
        ),
      ),
    ),
  );
}
