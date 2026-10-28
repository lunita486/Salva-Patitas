import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// A nombre de qué albergue trabaja el panel del albergue, y quién lo está
/// usando (PLAN-EQUIPO-ALBERGUE.md, "Fase 2").
///
/// - La responsable: [albergueId] es su propio uid y no hay autor aparte.
/// - Una miembro del equipo ("modo Albergue"): [albergueId] es el uid de la
///   responsable, y [autorUid]/[autorNombre] son los de la miembro. Todo lo
///   que escribe queda a nombre del albergue (`rescatistaId`, `albergueId`)
///   y, donde importa saber quién fue, con [camposAutor]: "Cargado por Ana"
///   en un animal, "Ana" debajo de un mensaje. firestore.rules exige que
///   `autorUid` sea el uid de la sesión y no deja cambiarlo después.
///
/// Las pantallas del albergue reciben esto en vez de leer el uid de la
/// sesión: para la responsable da exactamente lo mismo que antes.
class ContextoAlbergue {
  const ContextoAlbergue.responsable(this.albergueId)
    : autorUid = null,
      autorNombre = null,
      albergueNombre = '';

  const ContextoAlbergue.equipo({
    required this.albergueId,
    required String this.autorUid,
    required String this.autorNombre,
    this.albergueNombre = '',
  });

  /// uid de la responsable: el `rescatistaId` / `albergueId` de todo lo del
  /// albergue.
  final String albergueId;

  /// Solo en modo equipo: quién está usando el panel.
  final String? autorUid;
  final String? autorNombre;

  /// Solo en modo equipo: el nombre del albergue, para lo que ve el
  /// adoptante (el nombre del lado del albergue en un chat nuevo). Vacío si
  /// todavía no llegó.
  final String albergueNombre;

  bool get esEquipo => autorUid != null;

  /// Campos a sumar en lo que crea o escribe una miembro. Vacío para la
  /// responsable: sus animales y mensajes siguen exactamente como antes.
  Map<String, Object> get camposAutor => esEquipo
      ? {'autorUid': autorUid!, 'autorNombre': autorNombre!}
      : const {};

  /// "Cargado por Ana", "Ana": el nombre de quien escribió, para mostrarlo
  /// solo del lado del albergue. Null si no lo escribió una miembro (lo
  /// viejo, o lo de la responsable).
  static String? autorDe(Map<String, dynamic> datos) {
    final nombre = datos['autorNombre'];
    if (datos['autorUid'] is! String) return null;
    return nombre is String && nombre.trim().isNotEmpty ? nombre.trim() : 'Alguien del equipo';
  }
}

/// Si esta sesión está en "modo Albergue" de una miembro del equipo, su
/// contexto; null para todos los demás (la responsable, un rescatista, un
/// adoptante). Lo pone y lo saca SOLO AuthWrapper (main.dart), al mostrar u
/// ocultar el panel del albergue en modo equipo.
///
/// Por qué un valor de sesión y no un parámetro en cada ruta: las pantallas
/// del albergue (subir, editar, jauría, solicitudes, chats, hogares) se
/// abren desde muchos lugares con go_router, y todas tomaban el dueño de
/// `currentUser.uid`. En modo equipo la raíz de la app ES el panel del
/// albergue (no se puede estar a la vez en lo personal), así que mientras
/// esto no sea null, todo lo "del albergue" es de [ContextoAlbergue.albergueId].
/// Las pantallas lo leen con [contextoAlbergue], y solo en sus caminos de
/// albergue: lo personal (rescatista, adoptante) sigue con el uid propio.
class SesionEquipo {
  SesionEquipo._();
  static final actual = ValueNotifier<ContextoAlbergue?>(null);

  static bool get activa => actual.value != null;
}

/// El contexto del panel del albergue para esta sesión: el del equipo si se
/// entró en modo Albergue, o la responsable (el uid propio) si no.
ContextoAlbergue contextoAlbergue() =>
    SesionEquipo.actual.value ?? ContextoAlbergue.responsable(FirebaseAuth.instance.currentUser?.uid ?? '');

/// Dueño de lo que se lee o escribe en una pantalla compartida entre
/// rescatista y albergue: el albergue del contexto si [esAlbergue], el uid
/// propio si no.
String uidDueno({required bool esAlbergue}) =>
    esAlbergue ? contextoAlbergue().albergueId : (FirebaseAuth.instance.currentUser?.uid ?? '');
