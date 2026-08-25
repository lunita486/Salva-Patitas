import 'dart:convert';

import 'package:image_picker/image_picker.dart';

import '../data/foto_normalizador.dart';

/// Elige una foto de la galería para un perfil o logo de negocio, la
/// normaliza (redimensiona, corrige orientación EXIF, recomprime) y la
/// devuelve en base64, lista para guardar. `null` si se canceló la
/// elección o algo falló al procesar la foto.
///
/// **Existía tres veces, y las tres habían divergido** — el mismo patrón
/// que `elegirFotoAnimal()`, en otro subsistema: `aliado_perfil_screen.dart`
/// sí pasaba la foto por `normalizarFoto()`; `albergue_home_screen.dart` y
/// `albergue_perfil_screen.dart` no, así que una foto tomada con el celular
/// en la orientación "equivocada" (la que corrige `normalizarFoto()`
/// leyendo el EXIF) se guardaba rotada. `albergue_perfil_screen.dart`
/// tampoco tenía ningún try/catch: un fallo al leer los bytes de la foto
/// tiraba una excepción sin atrapar. Hallazgo de auditoría de código.
///
/// Solo galería, sin opción de cámara — a diferencia de un rescate, un
/// logo/perfil no se toma "ahí mismo, ahora": se elige una foto que ya
/// existe. Por eso tampoco hace falta el aviso de "cámara no disponible"
/// que sí tiene `elegirFotoAnimal()`.
///
/// Lo que NO hace, a propósito: decidir dónde guardar el resultado — cada
/// pantalla lo maneja distinto (guardarlo en el estado local para
/// confirmarlo después, o escribirlo directo a Firestore).
/// Los tres llamadores usaban el default; el parámetro solo daba lugar a
/// que divergieran.
const _calidadPerfil = 80;

Future<String?> elegirFotoPerfil({int maxWidth = 512}) async {
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: maxWidth.toDouble(),
    maxHeight: maxWidth.toDouble(),
    // q90: normalizarFoto() recomprime a [quality] después igual — mismo
    // motivo que elegirFotoAnimal(), entrar con más calidad solo evita
    // comprimir dos veces seguidas.
    imageQuality: 90,
  );
  if (picked == null) return null;
  try {
    final bytes = await normalizarFoto(
      picked.path,
      maxWidth: maxWidth,
      quality: _calidadPerfil,
    );
    return base64Encode(bytes);
  } catch (_) {
    return null;
  }
}
