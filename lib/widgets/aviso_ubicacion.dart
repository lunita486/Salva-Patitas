import 'package:flutter/material.dart';

import '../theme.dart';

/// Los dos mensajes que se repetían tal cual en las 3 pantallas que llaman
/// a [avisarErrorUbicacion] con un botón "Abrir Ajustes" — cortos a
/// propósito: con el botón al lado, un mensaje más largo ("Permiso de
/// ubicación bloqueado.", "Activa el GPS en tu dispositivo") no entraba en
/// una sola línea, Flutter apilaba el botón debajo del texto, y el
/// SnackBar quedaba más alto de lo necesario — con `floating` ya no se
/// come el borde de la pantalla, pero seguía siendo lo bastante alto como
/// para tapar el botón "Guardar" en formularios cortos. Hallazgo real de
/// Eliza: "el mensaje sigue tapando el botón guardar".
const mensajeGpsApagado = 'Activá el GPS';
const mensajePermisoBloqueado = 'Ubicación bloqueada.';

/// Aviso de error de ubicación (GPS apagado, permiso bloqueado, sin
/// respuesta...), con botón opcional que lleva directo al ajuste que hace
/// falta. Compartido entre subir_rescate_screen.dart, editar_rescate_screen.dart
/// y campo_ciudad.dart, que tenían esto escrito a mano 3 veces — y las 3
/// copias con el mismo problema visual (ver más abajo), porque estaba
/// copiado y no había un solo lugar para arreglarlo.
///
/// **`SnackBarBehavior.floating`, no el `fixed` por default.** Cuando el
/// texto más "Abrir Ajustes" no entran en una sola línea (pasa seguido con
/// "Permiso de ubicación bloqueado."), Flutter apila el botón debajo del
/// texto en vez de al lado — el SnackBar resultante es más alto de lo
/// normal, y en `fixed` (pegado al borde inferior, ancho completo) eso
/// alcanzaba a tapar campos reales del formulario de más abajo (ej.
/// "Descripción" en Subir un rescate). `floating` lo separa del borde con
/// un margen y lo redondea — sigue en dos líneas si el texto es largo, pero
/// deja de comerse la pantalla de abajo. Hallazgo real de Eliza: "es tan
/// grande el mensaje que tapa la opción".
void avisarErrorUbicacion(
  BuildContext context,
  String mensaje, {
  Future<bool> Function()? accionAjustes,
  VoidCallback? antesDeAbrirAjustes,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(mensaje),
      backgroundColor: msgError,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 8),
      action: accionAjustes == null
          ? null
          : SnackBarAction(
              label: 'Abrir Ajustes',
              textColor: Colors.white,
              onPressed: () {
                antesDeAbrirAjustes?.call();
                accionAjustes();
              },
            ),
    ),
  );
}
