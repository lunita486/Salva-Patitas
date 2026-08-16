import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme.dart';

// ─── Elegir la foto de un animal ───────────────────────────────────────────
/// Muestra la hoja "Tomar foto / Elegir de la galería" y devuelve el
/// archivo elegido, o `null` si se canceló o la cámara falló.
///
/// **Existía dos veces, y las dos copias habían divergido** — el mismo
/// patrón que venimos persiguiendo todo el día:
///
///  · `subir_rescate_screen.dart` envolvía la cámara en un try/catch y
///    avisaba "Cámara no disponible, usa la galería".
///  · `editar_rescate_screen.dart` NO — en un dispositivo sin cámara (o
///    con el permiso denegado, o un emulador sin cámara configurada),
///    `pickImage` lanza una excepción que nadie atrapaba: tocar "Tomar
///    foto" al EDITAR no hacía absolutamente nada, sin ningún aviso.
///
/// Además la calidad del picker era distinta entre las dos (90 vs 80).
/// Acá queda en 90 para las dos: `normalizarFoto()` recomprime todo a q80
/// después igual, así que entrar con más calidad solo evita comprimir dos
/// veces seguidas — mismo peso final, mejor imagen.
///
/// Lo que NO hace, a propósito: decidir dónde guardar el archivo ni si
/// todavía hay lugar para otra foto. Eso depende del estado propio de cada
/// pantalla (una lista en publicar, dos slots en editar), así que se queda
/// del lado del llamador.
Future<XFile?> elegirFotoAnimal(BuildContext context) async {
  final fuente = await showModalBottomSheet<ImageSource>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.camera_alt, color: appTeal),
            title: const Text('Tomar foto'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, color: appTeal),
            title: const Text('Elegir de la galería'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (fuente == null) return null;
  try {
    return await ImagePicker().pickImage(
      source: fuente,
      imageQuality: 90,
      maxWidth: 1000,
      maxHeight: 1000,
    );
  } catch (_) {
    // Cámara no disponible / permiso denegado / emulador sin cámara. La
    // galería casi siempre sigue funcionando, así que se sugiere eso en
    // vez de dejar el toque sin ninguna respuesta.
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cámara no disponible, usa la galería'),
          backgroundColor: msgAdvertencia,
        ),
      );
    }
    return null;
  }
}
