import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import 'fotos.dart';

/// Avatar de una persona (foto de perfil en base64 o URL). Si la foto falla
/// al cargar, cae a la inicial en vez de romper con una excepción sin
/// manejar o quedar en blanco. Antes esta lógica vivía duplicada como
/// `_AvatarPublicador` solo en el feed del adoptante — el mismo problema
/// (foto que no carga = pantalla rota) aplica a cualquier avatar de foto
/// real, así que se promovió acá para reutilizarla (ej. en el chat).
class AvatarPersona extends StatefulWidget {
  final String? fotoBase64;
  final String? fotoUrl;
  final String inicial;
  final double radius;
  final Color backgroundColor;
  final Color textColor;
  const AvatarPersona({
    super.key,
    this.fotoBase64,
    this.fotoUrl,
    required this.inicial,
    this.radius = 20,
    this.backgroundColor = appTeal,
    this.textColor = Colors.white,
  });

  @override
  State<AvatarPersona> createState() => _AvatarPersonaState();
}

class _AvatarPersonaState extends State<AvatarPersona> {
  bool _falloCarga = false;

  Widget _inicial() => Center(
    child: Text(
      widget.inicial,
      style: TextStyle(
        color: widget.textColor,
        fontSize: widget.radius * 0.65,
        fontWeight: FontWeight.bold,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final fotoBytes = bytesFotoSegura(widget.fotoBase64);
    final ImageProvider? foto = fotoBytes != null
        ? MemoryImage(fotoBytes)
        : widget.fotoUrl != null
        ? NetworkImage(widget.fotoUrl!)
        : null;
    final mostrarFoto = foto != null && !_falloCarga;
    final size = widget.radius * 2;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: ColoredBox(
          color: widget.backgroundColor,
          child: mostrarFoto
              ? Image(
                  image: foto,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) {
                    // postFrameCallback, no un setState directo acá: este
                    // callback puede dispararse en la misma pasada de build
                    // si la imagen falla apenas se intenta resolver (bytes
                    // corruptos), y un setState ahí mismo tira "setState
                    // called during build".
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _falloCarga = true);
                    });
                    return _inicial();
                  },
                  // Fundido de entrada: sin esto, la foto aparecía de golpe
                  // recién en el frame en que terminaba de decodificarse —
                  // con varios avatares en la misma pantalla (ej. la grilla
                  // de negocios aliados), cada uno termina de decodificar en
                  // un instante levemente distinto, y se veía como si
                  // cargaran "de a uno" aunque los datos de los dos ya
                  // habían llegado juntos desde el principio. Hallazgo real
                  // de Eliza en teléfono real, 2026-08-03.
                  frameBuilder:
                      (context, child, frame, wasSynchronouslyLoaded) {
                        if (wasSynchronouslyLoaded) return child;
                        return AnimatedOpacity(
                          opacity: frame == null ? 0 : 1,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          child: child,
                        );
                      },
                )
              : _inicial(),
        ),
      ),
    );
  }
}

/// Avatar de OTRO usuario de la app, identificado por su uid — busca su foto
/// en usuarios/{userId}.foto (Google Auth photoURL, sincronizado en
/// main.dart). Si [campoLogoNegocio] no es null, prioriza ese campo (el logo
/// que un albergue/aliado sube a propósito desde su perfil) sobre esa foto
/// personal.
///
/// [campoLogoNegocio] es el NOMBRE del campo a leer, no un booleano, porque
/// cada rol de negocio guarda su logo en un campo propio dentro del MISMO
/// doc usuarios/{uid}: 'fotoBase64' es el logo de albergue,
/// 'aliadoFotoBase64' el de aliado — una cuenta puede tener varios roles de
/// negocio a la vez (ver ARCHITECTURE.md), así que "mostrar el logo" no
/// alcanza, hay que decir CUÁL. Pasar el campo equivocado (o forzar siempre
/// 'fotoBase64') es cómo un chat de consulta a un aliado terminaba
/// mostrando la foto personal de la cuenta en vez del logo del negocio: ese
/// logo vivía en 'aliadoFotoBase64' y nadie lo estaba pidiendo. null =
/// mostrar siempre la foto personal.
///
/// Antes cada pantalla que necesitaba mostrar la foto de una contraparte
/// (encabezado del chat, tarjeta de solicitud, fila de la lista de
/// conversaciones) usaba la foto de la cuenta ACTUALMENTE logueada por
/// error — se centraliza acá para no repetir el mismo bug en cada pantalla
/// nueva.
class AvatarUsuario extends StatefulWidget {
  final String? userId;
  final String inicial;
  final double radius;
  final Color backgroundColor;
  final Color textColor;
  final String? campoLogoNegocio;
  const AvatarUsuario({
    super.key,
    required this.userId,
    required this.inicial,
    this.radius = 20,
    this.backgroundColor = appTeal,
    this.textColor = Colors.white,
    this.campoLogoNegocio,
  });

  @override
  State<AvatarUsuario> createState() => _AvatarUsuarioState();
}

class _AvatarUsuarioState extends State<AvatarUsuario> {
  late Future<(String?, String?)> _foto = _cargar();

  // Sin esto, un widget reusado para OTRA persona (mismo lugar en una
  // lista sin `key` propia, ej. hogares_de_paso_screen.dart, que se
  // reordena sola cuando cambia `vecesAyudo`) seguía mostrando la foto de
  // quien tenía ese lugar antes — el nombre se actualiza (viene directo
  // del `build()` de quien usa este widget), pero la foto quedaba
  // pegada a la primera carga de la vida de este State. Arreglo de raíz
  // acá adentro (no "agregarle una key a cada lista que lo use") para que
  // blinde a CUALQUIER lista que use este widget, no solo a la que lo
  // destapó. Hallazgo de auditoría de código.
  @override
  void didUpdateWidget(covariant AvatarUsuario oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.campoLogoNegocio != widget.campoLogoNegocio) {
      setState(() => _foto = _cargar());
    }
  }

  Future<(String?, String?)> _cargar() async {
    final id = widget.userId;
    if (id == null || id.isEmpty) return (null, null);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(id)
          .get();
      final data = doc.data();
      final campo = widget.campoLogoNegocio;
      final fotoBase64 = campo != null ? (data?[campo] as String?) : null;
      return (fotoBase64, data?['foto'] as String?);
    } catch (_) {
      return (null, null);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<(String?, String?)>(
    future: _foto,
    builder: (context, snap) => AvatarPersona(
      fotoBase64: snap.data?.$1,
      fotoUrl: snap.data?.$2,
      inicial: widget.inicial,
      radius: widget.radius,
      backgroundColor: widget.backgroundColor,
      textColor: widget.textColor,
    ),
  );
}
