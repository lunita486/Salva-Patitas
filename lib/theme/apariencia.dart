// Claro u Oscuro, elegido en la hoja "Apariencia" del Perfil.
//
// Se guarda en el teléfono (shared_preferences) y no en la cuenta: es una
// preferencia del aparato. Sin "Sistema" a propósito (pedido de Eliza): la
// app arranca en Claro hasta que la persona elija otra cosa.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Apariencia {
  static const _clave = 'apariencia';

  /// El modo actual. MaterialApp lo escucha y cambia de tema al instante.
  static final modo = ValueNotifier<ThemeMode>(ThemeMode.light);

  static bool get esOscuro => modo.value == ThemeMode.dark;

  /// Texto para la fila "Apariencia" de los perfiles.
  static String get etiqueta => esOscuro ? 'Oscuro' : 'Claro';

  /// Lee la elección guardada. Si no se puede leer (o nunca se eligió),
  /// queda en Claro: nunca traba el arranque de la app.
  static Future<void> cargar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      modo.value = prefs.getString(_clave) == 'oscuro'
          ? ThemeMode.dark
          : ThemeMode.light;
    } catch (_) {}
  }

  /// Cambia el modo ya mismo y lo guarda para la próxima vez. Si guardar
  /// falla, el cambio igual se ve en esta sesión.
  static Future<void> elegir(ThemeMode nuevo) async {
    modo.value = nuevo;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _clave,
        nuevo == ThemeMode.dark ? 'oscuro' : 'claro',
      );
    } catch (_) {}
  }
}
