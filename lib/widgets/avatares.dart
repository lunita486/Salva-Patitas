import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
    // CachedNetworkImageProvider, no NetworkImage: este widget se usa en
    // el encabezado del chat, tarjetas de solicitud y filas de la lista de
    // conversaciones — mismo motivo que FotoUrl en fotos.dart, NetworkImage
    // solo cachea en RAM y vuelve a descargar todo en cada apertura de la
    // app. Hallazgo real de Eliza: "cuando abro chats... las imágenes se
    // demoran en cargar".
    final ImageProvider? foto = fotoBytes != null
        ? MemoryImage(fotoBytes)
        : widget.fotoUrl != null
        ? CachedNetworkImageProvider(widget.fotoUrl!)
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

  /// El DOCUMENTO de cada perfil, pedido una sola vez por uid en toda la
  /// sesión.
  ///
  /// **Por qué existe.** El feed del adoptante muestra el avatar de quien
  /// publicó cada animalito. Hasta ahora esa foto viajaba copiada DENTRO de
  /// cada animalito (`rescatistaFotoBase64`), y para un albergue eso son 85
  /// KB de base64 por documento: la primera página del perfil de un albergue
  /// pesaba 2,7 MB, de los cuales 2,6 MB eran el mismo logo repetido 31
  /// veces. Medido contra producción.
  ///
  /// Sacando esa copia, el avatar tiene que salir de `usuarios/{uid}`. Sin
  /// este mapa serían tantas lecturas como tarjetas se pasen, y como el
  /// logo vive en ese documento, cada una costaría los mismos 85 KB: sería
  /// igual o peor que antes. Con el mapa son 3 lecturas por sesión si hay 3
  /// albergues, se pasen 50 tarjetas o 500.
  ///
  /// **Guarda el documento y NO el resultado, a propósito.** El par que
  /// devuelve [_cargar] depende de `campoLogoNegocio`, que es distinto en
  /// cada pantalla: las que no lo pasan verían `null` como logo. Cacheando
  /// el par indexado solo por uid, la primera pantalla que preguntara
  /// dejaría su respuesta fijada para las demás, y el feed mostraría la
  /// foto personal en vez del logo del albergue — silencioso y dependiente
  /// del orden en que se abrieran las pantallas. Guardando el documento,
  /// cada widget deriva lo suyo del mismo dato.
  ///
  /// **Lo que se pierde:** si un albergue cambia su logo, los avatares
  /// muestran el anterior hasta reiniciar la app. Antes pasaba lo mismo por
  /// otro motivo (la copia dentro del animalito también quedaba vieja hasta
  /// que el trigger la propagaba), así que no empeora.
  static final _perfiles = <String, Future<Map<String, dynamic>?>>{};

  static Future<Map<String, dynamic>?> _pedirPerfil(String id) {
    return FirebaseFirestore.instance
        .collection('usuarios')
        .doc(id)
        .get()
        .then<Map<String, dynamic>?>((doc) => doc.data())
        // Un fallo NO se cachea. Sin esto, una caída de red de un segundo
        // dejaría ese avatar sin foto por el resto de la sesión: la entrada
        // fallida quedaría fijada y nadie volvería a preguntar.
        //
        // Un documento SIN logo sí se cachea: "este albergue no subió
        // ninguno" es una respuesta, no un fallo.
        //
        // `onError` y NO un try/catch dentro de un `async`: el catch de una
        // función async que falla antes de su primer `await` corre en el
        // mismo turno, o sea ANTES de que `??=` guarde la entrada, y
        // borraría de un mapa donde todavía no está — dejando el fallo
        // cacheado, justo lo contrario de lo que se busca. `onError`
        // siempre corre en un microtask posterior a la asignación. Lo
        // encontró el test del memo.
        .onError((_, _) {
          _perfiles.remove(id);
          return null;
        });
  }

  Future<(String?, String?)> _cargar() async {
    final id = widget.userId;
    if (id == null || id.isEmpty) return (null, null);
    final data = await (_perfiles[id] ??= _pedirPerfil(id));
    final campo = widget.campoLogoNegocio;
    final fotoBase64 = campo != null ? (data?[campo] as String?) : null;
    return (fotoBase64, data?['foto'] as String?);
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
