import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import '../theme.dart';
import '../compatibilidad.dart';
import '../data/creator_role.dart';
import '../data/solicitudes_repository.dart';
import '../data/rescates_repository.dart';
import '../data/chats_repository.dart';
import '../data/hogares_de_paso_repository.dart';
import 'chat_screen.dart';

// ── Funciones top-level reutilizables por home_screen y solicitudes_screen ──

Future<bool> enviarMensajeChat(String adoptanteId, String animalNombre, String texto,
    {String? fotoUrl, String? adoptanteNombre, String? tipoSolicitud, String? rescateId,
     String? creadoPor, String? especie}) async {
  try {
    final rescatistaId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final n    = DateTime.now();
    final hora = '${n.hour}:${n.minute.toString().padLeft(2, '0')}';

    // Con rescateId se apunta directo al chat de ese animal puntual (id determinístico
    // animal+adoptante); sin él (dato legado) se cae al viejo match por nombre.
    DocumentReference<Map<String, dynamic>> chatRef;
    DocumentSnapshot<Map<String, dynamic>>? existing;
    if (rescateId != null && rescateId.isNotEmpty) {
      chatRef = FirebaseFirestore.instance.collection('chats')
          .doc(ChatsRepository().idAnimal(rescateId: rescateId, adoptanteId: adoptanteId));
      // Mismo caso que asegurarChatNegocio (ver chats_repository.dart): leer
      // un chat que TODAVÍA no existe da permission-denied con nuestras
      // reglas (no pueden probar "sos participante" de un doc que no está)
      // — no es que falte permiso de verdad. Sin este try/catch, esa
      // excepción se colaba hasta el catch general de más abajo y todo el
      // aviso por chat fallaba en silencio justo en el caso más común: la
      // primera vez que se aprueba/rechaza una solicitud, cuando adoptante
      // y rescatista todavía no habían chateado antes — el bug real: "sale
      // siempre el mensaje de que no pudimos avisarle al adoptante".
      try {
        final snap = await chatRef.get();
        if (snap.exists) existing = snap;
      } catch (_) {
        existing = null;
      }
    } else {
      final chats = await FirebaseFirestore.instance.collection('chats')
          .where('adoptanteId', isEqualTo: adoptanteId)
          .where('animalNombre', isEqualTo: animalNombre)
          .limit(1).get();
      if (chats.docs.isNotEmpty) {
        existing = chats.docs.first;
        chatRef = existing.reference;
      } else {
        chatRef = FirebaseFirestore.instance.collection('chats').doc();
      }
    }

    final userDoc = await FirebaseFirestore.instance.collection('usuarios').doc(rescatistaId).get();
    final userData = userDoc.data() ?? {};
    final rescatistaNombre =
        (userData['albergueNombre'] as String?)?.isNotEmpty == true
            ? userData['albergueNombre'] as String
            : (userData['nombre'] as String?)?.isNotEmpty == true
                ? userData['nombre'] as String
                : FirebaseAuth.instance.currentUser?.displayName ?? 'Rescatista';

    if (existing == null) {
      if (rescateId != null && rescateId.isNotEmpty) {
        // Mismo método que usa el resto de la app para crear un chat de
        // animal, así los campos (creadoPor, especie, etc.) no divergen
        // entre quién crea el chat primero. Todo en una sola escritura
        // (via `extra`) para que no pueda quedar un chat a medio crear si
        // la app se cierra justo entre pasos.
        await ChatsRepository().asegurarChatAnimal(
          adoptanteId: adoptanteId,
          adoptanteNombre: adoptanteNombre ?? 'Adoptante',
          rescateId: rescateId,
          rescatistaId: rescatistaId,
          rescatista: rescatistaNombre,
          creadoPor: creadoPor ?? 'rescatista',
          animalNombre: animalNombre,
          especie: especie,
          fotoUrl: fotoUrl,
          extra: {
            'ultimoMensaje': texto, 'ultimaHora': hora,
            'ultimoMensajeEn': FieldValue.serverTimestamp(),
            'noLeidosAdoptante': 1,
            if (tipoSolicitud != null) 'tipoSolicitud': tipoSolicitud,
          },
        );
      } else {
        await chatRef.set({
          'adoptanteId':     adoptanteId,
          'adoptanteNombre': adoptanteNombre ?? 'Adoptante',
          'animalNombre':    animalNombre,
          'creadoPor':       creadoPor ?? 'rescatista',
          'rescatistaId':    rescatistaId,
          'rescatista':      rescatistaNombre,
          if (fotoUrl        != null) 'fotoUrl':        fotoUrl,
          if (tipoSolicitud  != null) 'tipoSolicitud':  tipoSolicitud,
          if (especie        != null) 'especie':        especie,
          'ultimoMensaje': texto, 'ultimaHora': hora,
          'ultimoMensajeEn': FieldValue.serverTimestamp(),
          'noLeidosAdoptante': 1,
        });
      }
    } else {
      final existingData = existing.data() ?? {};
      await chatRef.update({
        'ultimoMensaje': texto, 'ultimaHora': hora,
        'ultimoMensajeEn': FieldValue.serverTimestamp(),
        'noLeidosAdoptante': FieldValue.increment(1),
        if (fotoUrl != null && existingData['fotoUrl'] == null)
          'fotoUrl': fotoUrl,
      });
    }
    await chatRef.collection('mensajes').add({
      'texto': texto, 'emisor': 'rescatista', 'hora': hora,
      'creadoEn': FieldValue.serverTimestamp(),
    });
    return true;
  } catch (_) {
    return false;
  }
}

/// Candado compartido por TODO el proceso, no por pantalla — a propósito
/// a nivel de archivo, no un campo de un State. [aprobarSolicitud] y
/// [rechazarSolicitud] las llaman tanto solicitudes_rescatista_screen.dart
/// (la lista completa) como solicitudes_preview.dart (la vista previa de
/// los paneles de rescatista y albergue), y esas dos pantallas pueden
/// estar montadas a la vez sin saber una de la otra. Antes cada pantalla
/// tenía (o no tenía) su propio candado local, así que aprobar/rechazar
/// la MISMA solicitud desde la vista previa Y la lista completa —o tocar
/// Aprobar y después Rechazar casi juntos, ninguno de los dos protegido
/// contra el otro— no tenía ningún seguro real (hallazgo de auditoría de
/// código): se disparaba el mensaje de chat dos veces, se inflaba
/// `vecesAyudo` de hogares de paso dos veces, o el animal y la solicitud
/// quedaban en estados contradictorios.
final Set<String> _solicitudesEnProceso = {};

/// [aprobada]: false si perdió la carrera contra otra solicitud del mismo
/// animal, o si el animal ya no existe (ver
/// [SolicitudesRepository.aprobarSiDisponible]) — en cualquiera de los dos
/// casos esta solicitud quedó auto-rechazada, no aprobada.
/// [animalEliminado]: distingue cuál de esos dos motivos fue, para que el
/// llamador le muestre al rescatista el mensaje correcto.
/// [avisoOk]: si el mensaje de chat correspondiente (aprobación, o el aviso
/// de "ya no disponible" si perdió la carrera) se pudo enviar. La
/// aprobación/rechazo en sí ya quedó guardada aunque el aviso falle; el
/// llamador decide cómo informarle al rescatista que el chat no salió.
///
/// Devuelve `null` si [docId] ya se está aprobando/rechazando en este
/// mismo momento (desde esta pantalla, la otra, o el mismo botón tocado
/// dos veces) — el llamador lo trata como "no hacer nada", no como un
/// error.
Future<({bool aprobada, bool animalEliminado, bool avisoOk})?> aprobarSolicitud(String docId, Map<String, dynamic> d) async {
  // Set.add() devuelve false si el elemento YA estaba — no hace falta que
  // sea atómico "a mano": Dart es de un solo hilo, no hay ningún await
  // entre este chequeo y el agregado, así que no existe una ventana donde
  // dos llamadas lean "libre" a la vez.
  if (!_solicitudesEnProceso.add(docId)) return null;
  try {
    return await _aprobarSolicitudImpl(docId, d);
  } finally {
    _solicitudesEnProceso.remove(docId);
  }
}

Future<({bool aprobada, bool animalEliminado, bool avisoOk})> _aprobarSolicitudImpl(
    String docId, Map<String, dynamic> d) async {
  final rescateId     = d['rescateId']     as String? ?? '';
  final adoptanteId   = d['adoptanteId']   as String? ?? '';
  final animalNombre  = d['animalNombre']  as String? ?? '';
  final rescatistaId  = d['rescatistaId']  as String? ?? '';
  final creadoPor     = d['creadoPor']     as String? ?? 'rescatista';
  final tipoSolicitud = d['tipoSolicitud'] as String? ?? 'adopcion';
  final nuevoEstado   = tipoSolicitud == 'hogar_de_paso'
      ? 'Hogar de paso'
      : 'En proceso de adopción';

  final fechaInicio = d['fechaInicioHogar'] as Timestamp?;
  final fechaFin    = d['fechaFinHogar']    as Timestamp?;
  final camposExtra = <String, dynamic>{
    if (tipoSolicitud == 'hogar_de_paso') ...{
      if (fechaInicio != null) 'fechaInicioHogar': fechaInicio,
      if (fechaFin    != null) 'fechaFinHogar':    fechaFin,
      'vencimientoAvisado': false,
    },
  };

  bool aprobada;
  bool animalEliminado = false;
  if (rescateId.isNotEmpty) {
    // Camino atómico (todas las solicitudes nuevas tienen rescateId): la
    // transacción verifica que el animal siga disponible antes de aprobar.
    final resultado = await SolicitudesRepository().aprobarSiDisponible(
      solicitudId: docId,
      rescateId: rescateId,
      adoptanteId: adoptanteId,
      nuevoEstadoAdopcion: nuevoEstado,
      camposExtra: camposExtra,
    );
    aprobada = resultado.aprobada;
    animalEliminado = resultado.animalEliminado;
  } else {
    // Dato legado sin rescateId: no hay documento puntual contra el cual
    // transaccionar (la búsqueda por nombre es una query, y las queries no
    // son transaccionales del lado del cliente). Best-effort, como antes —
    // caso cada vez más raro, son solicitudes de antes de que este campo
    // existiera.
    await SolicitudesRepository().cambiarEstado(docId, 'aprobada');
    if (animalNombre.isNotEmpty && rescatistaId.isNotEmpty) {
      await RescatesRepository().actualizarPorNombre(
        nombre: animalNombre,
        rescatistaId: rescatistaId,
        cambios: {
          'estadoAdopcion': nuevoEstado,
          'adoptanteIdEnProceso': adoptanteId,
          ...camposExtra,
        },
      );
    }
    aprobada = true;
  }

  if (aprobada) {
    FirebaseAnalytics.instance.logEvent(
      name: 'solicitud_aprobada',
      parameters: {'tipo': tipoSolicitud, 'rescatista_id': rescatistaId},
    ).catchError((_) {});
  }

  if (!aprobada) {
    // Perdió la carrera, o el animal ya no existe: se le avisa a ESTE
    // adoptante que ya no pudo ser, igual que se les avisa a las
    // competidoras más abajo.
    FirebaseAnalytics.instance.logEvent(
      name: 'solicitud_rechazada',
      parameters: {
        'tipo': tipoSolicitud,
        'rescatista_id': rescatistaId,
        'motivo': animalEliminado ? 'animal_eliminado' : 'perdio_carrera',
      },
    ).catchError((_) {});
    if (adoptanteId.isEmpty || animalNombre.isEmpty) {
      return (aprobada: false, animalEliminado: animalEliminado, avisoOk: true);
    }
    final mensaje = animalEliminado
        ? '🐾 $animalNombre ya no está disponible en la plataforma. ¡No te desanimes, hay más amiguitos esperándote!'
        : '🐾 $animalNombre ya tiene un proceso de adopción activo. ¡No te desanimes, hay más amiguitos esperándote!';
    final avisoOk = await enviarMensajeChat(adoptanteId, animalNombre, mensaje,
        fotoUrl: d['fotoUrl'] as String?,
        rescateId: rescateId,
        creadoPor: creadoPor,
        especie: d['especie'] as String?);
    return (aprobada: false, animalEliminado: animalEliminado, avisoOk: avisoOk);
  }

  if (tipoSolicitud == 'hogar_de_paso' && creadoPor == 'albergue' && adoptanteId.isNotEmpty) {
    // Red de hogares de paso — solo para albergues (decisión de producto).
    // Best-effort: el roster es una mejora secundaria, si falla no debe
    // tumbar la aprobación real que la persona pidió.
    try {
      await HogaresDePasoRepository().registrarAyuda(
        albergueId: rescatistaId,
        adoptanteId: adoptanteId,
        nombre: d['nombre'] as String? ?? '',
        email: d['email'] as String?,
      );
    } catch (_) {}
  }

  if (animalNombre.isNotEmpty) {
    // Se agrega rescateId cuando está disponible para no confundir animales
    // con el mismo nombre publicados por la misma cuenta bajo distinto rol
    // (ej. un "Rocky" como rescatista y otro "Rocky" como albergue).
    final rechazadas = await SolicitudesRepository().rechazarCompetidoras(
      animalNombre: animalNombre,
      rescatistaId: rescatistaId,
      excluirDocId: docId,
      rescateId: rescateId.isNotEmpty ? rescateId : null,
    );
    for (final otra in rechazadas) {
      final otroAdoptanteId = otra['adoptanteId'] as String? ?? '';
      if (otroAdoptanteId.isNotEmpty) {
        await enviarMensajeChat(otroAdoptanteId, animalNombre,
            '🐾 $animalNombre ya tiene un proceso de adopción activo. ¡No te desanimes, hay más amiguitos esperándote!',
            fotoUrl: otra['fotoUrl'] as String?,
            rescateId: otra['rescateId'] as String? ?? rescateId,
            creadoPor: otra['creadoPor'] as String? ?? creadoPor,
            especie: otra['especie'] as String? ?? d['especie'] as String?);
      }
    }
  }

  if (adoptanteId.isNotEmpty && animalNombre.isNotEmpty) {
    final msg = tipoSolicitud == 'hogar_de_paso'
        ? '✅ ¡Tu solicitud de hogar de paso fue aprobada! Pronto me pongo en contacto contigo para coordinar los detalles. 🐾'
        : '✅ ¡Tu solicitud de adopción fue aprobada! Pronto me pongo en contacto contigo para coordinar el encuentro. 🐾';
    final avisoOk = await enviarMensajeChat(adoptanteId, animalNombre, msg,
        fotoUrl: d['fotoUrl'] as String?,
        adoptanteNombre: d['nombre'] as String?,
        tipoSolicitud: tipoSolicitud,
        rescateId: rescateId,
        creadoPor: creadoPor,
        especie: d['especie'] as String?);
    return (aprobada: true, animalEliminado: false, avisoOk: avisoOk);
  }
  return (aprobada: true, animalEliminado: false, avisoOk: true);
}

/// Devuelve `true` si el aviso por chat al adoptante se pudo enviar, o
/// `null` si [docId] ya se está aprobando/rechazando en este mismo
/// momento — mismo candado compartido que [aprobarSolicitud], ver ese
/// comentario.
Future<bool?> rechazarSolicitud(String docId, Map<String, dynamic> d, String motivo) async {
  if (!_solicitudesEnProceso.add(docId)) return null;
  try {
    return await _rechazarSolicitudImpl(docId, d, motivo);
  } finally {
    _solicitudesEnProceso.remove(docId);
  }
}

Future<bool> _rechazarSolicitudImpl(String docId, Map<String, dynamic> d, String motivo) async {
  final animalNombre = d['animalNombre'] as String? ?? '';
  final texto = motivo.trim().isNotEmpty ? motivo.trim()
      : 'Hola, gracias por tu interés en adoptar a $animalNombre. '
        'Luego de revisar tu solicitud, en esta ocasión no podemos continuar con el proceso. '
        '¡Esperamos que pronto encuentres a tu compañero perfecto! 🐾';
  await SolicitudesRepository().rechazar(docId, texto);
  FirebaseAnalytics.instance.logEvent(
    name: 'solicitud_rechazada',
    parameters: {
      'tipo': d['tipoSolicitud'] as String? ?? 'adopcion',
      'rescatista_id': d['rescatistaId'] as String? ?? '',
      'motivo': 'explicito',
    },
  ).catchError((_) {});
  final adoptanteId = d['adoptanteId'] as String? ?? '';
  final fotoUrl     = d['fotoUrl']     as String?;
  final rescateId   = d['rescateId']   as String? ?? '';
  if (adoptanteId.isNotEmpty && animalNombre.isNotEmpty) {
    return enviarMensajeChat(adoptanteId, animalNombre, texto,
        fotoUrl: fotoUrl, adoptanteNombre: d['nombre'] as String?,
        rescateId: rescateId, creadoPor: d['creadoPor'] as String?,
        especie: d['especie'] as String?);
  }
  return true;
}

/// Abre (o crea) el chat con quien tiene este animal en proceso — "Hogar de
/// paso" o "En proceso de adopción" — desde cualquier tarjeta de animal del
/// rescatista/albergue. Antes esta búsqueda vivía copiada dentro de
/// home_screen.dart, y solo habilitada para 'En proceso de adopción' —
/// "Hogar de paso" se quedó afuera sin querer (el bug real que reportó
/// Eliza: aprobó un hogar de paso y no encontró forma de contactar a la
/// persona, ni en el panel principal ni en "Mis rescates", que nunca tuvo
/// este botón). Una sola copia evita que el próximo arreglo se aplique en
/// una pantalla y se olvide en las demás.
Future<void> contactarPersonaEnProceso(BuildContext context, {
  required String docId,
  required String nombre,
  required String especie,
  String? fotoUrl,
  String? creadoPor,
  required String adoptanteIdEnProceso,
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  QueryDocumentSnapshot<Map<String, dynamic>>? chatDoc;
  Map<String, dynamic>? d;
  // try/catch: leer un chat que NO existe da permission-denied con
  // nuestras reglas — sin esto la excepción mataba el onTap y "Contactar"
  // no hacía nada.
  try {
    if (adoptanteIdEnProceso.isNotEmpty) {
      final doc = await FirebaseFirestore.instance.collection('chats')
          .doc(ChatsRepository().idAnimal(rescateId: docId, adoptanteId: adoptanteIdEnProceso))
          .get();
      if (doc.exists) d = doc.data();
    } else {
      // Dato legado sin adoptanteIdEnProceso: se cae al viejo match por
      // nombre+dueño.
      final chats = await FirebaseFirestore.instance.collection('chats')
          .where('animalNombre', isEqualTo: nombre)
          .where('rescatistaId', isEqualTo: uid)
          .limit(1).get();
      if (chats.docs.isNotEmpty) {
        chatDoc = chats.docs.first;
        d = chatDoc.data();
      }
    }
  } catch (_) {
    d = null;
  }
  // Sin chat previo pero con adoptante conocido: se abre el chat igual con
  // chatId null y ChatScreen lo crea. Pero sin chat previo tampoco hay
  // adoptanteNombre denormalizado en ningún lado — sin este fallback, el
  // encabezado mostraba el literal "Adoptante" en vez del nombre real la
  // primera vez que se contacta a alguien recién aprobado.
  String? nombreAdoptanteFallback;
  if (d == null && adoptanteIdEnProceso.isNotEmpty) {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('usuarios').doc(adoptanteIdEnProceso).get();
      nombreAdoptanteFallback = userDoc.data()?['nombre'] as String?;
    } catch (_) {}
  }
  if (!context.mounted) return;
  if (d == null && adoptanteIdEnProceso.isEmpty) return;
  final dFinal = d ?? const <String, dynamic>{};
  final chatId = d == null
      ? null
      : adoptanteIdEnProceso.isNotEmpty
          ? ChatsRepository().idAnimal(rescateId: docId, adoptanteId: adoptanteIdEnProceso)
          : chatDoc!.id;
  Navigator.push(context, MaterialPageRoute(
    builder: (_) => ChatScreen(
      esRescatista: true,
      chatId: chatId,
      animal: {
        'nombre':          nombre,
        'rescatista':      FirebaseAuth.instance.currentUser?.displayName ?? 'Rescatista',
        'rescatistaId':    dFinal['rescatistaId'] as String? ?? uid,
        'rescateId':       docId,
        'adoptanteId':     adoptanteIdEnProceso,
        'adoptanteNombre': dFinal['adoptanteNombre'] as String? ?? nombreAdoptanteFallback,
        'especie':         especie,
        'creadoPor':       dFinal['creadoPor'] as String? ?? creadoPor ?? 'rescatista',
        'tipoSolicitud':   dFinal['tipoSolicitud'] as String? ?? 'adopcion',
        'fotoUrl':         dFinal['fotoUrl'] ?? fotoUrl,
      },
    ),
  ));
}

/// Avisos automáticos de "el hogar de paso vence mañana / ya venció" — antes
/// duplicado byte a byte entre home_screen.dart (rescatista) y
/// albergue_home_screen.dart (hallazgo de auditoría de código). [role] y
/// [creadoPor] son la única diferencia real entre las dos copias que
/// reemplaza; se llama una vez por panel, típicamente desde `initState`.
Future<void> verificarVencimientos(
  BuildContext context, {
  required String uid,
  required CreatorRole role,
  required String creadoPor,
}) async {
  if (uid.isEmpty) return;
  final ahora = DateTime.now();
  final hoySinHora = DateTime(ahora.year, ahora.month, ahora.day);
  final snap = await RescatesRepository().misRescatesPorEstado(
    uid: uid,
    role: role,
    estadoAdopcion: 'Hogar de paso',
  );
  // Nombres avisados en esta pasada — antes el mensaje solo entraba al chat
  // con el adoptante y quien publicó no se enteraba salvo que abriera esa
  // conversación puntual; ahora se le avisa acá mismo en su panel (pedido
  // de Eliza).
  final avisados = <String>[];
  // Aviso previo (1 día antes) — flag propio (`avisoPrevioAvisado`),
  // separado de `vencimientoAvisado`, para que las dos notificaciones
  // (antes/después) no se pisen entre sí. Pedido explícito de Eliza: antes
  // solo se avisaba DESPUÉS de vencido, sin ningún margen para coordinar
  // con tiempo la devolución.
  final porVencer = <String>[];
  for (final doc in snap.docs) {
    final d = doc.data();
    final fechaFin = (d['fechaFinHogar'] as Timestamp?)?.toDate();
    if (fechaFin == null) continue;
    final nombre      = d['nombre']            as String? ?? 'El animal';
    final adoptanteId = d['adoptanteIdEnProceso'] as String?;
    // Sin adoptanteId (dato legado/corrupto: un hogar de paso sin nadie
    // en proceso) no hay a quién avisarle — antes esto igual llamaba a
    // enviarMensajeChat('', ...), que arma un chat "fantasma" sin dueño
    // real y, si esa escritura llega a tener éxito, marcaba el flag de
    // avisado como si alguien de verdad se hubiera enterado. Hallazgo de
    // auditoría de código.
    if (adoptanteId == null || adoptanteId.isEmpty) continue;
    if (fechaFin.isAfter(ahora)) {
      final finSinHora = DateTime(fechaFin.year, fechaFin.month, fechaFin.day);
      final diasRestantes = finSinHora.difference(hoySinHora).inDays;
      if (diasRestantes == 1 && d['avisoPrevioAvisado'] != true) {
        final msg = '📋 El período de hogar de paso de $nombre vence mañana. '
            'Coordiná con tiempo la devolución o el proceso de adopción definitivo. 🐾';
        // Solo se marca "avisado" si el mensaje realmente se guardó — antes
        // se marcaba igual aunque enviarMensajeChat() fallara, y ese aviso
        // quedaba perdido para siempre (nunca se reintentaba en la próxima
        // apertura de la app). El bug real que encontró Eliza probando con
        // Sarita: el aviso figuraba como enviado pero el chat nunca tuvo
        // el mensaje.
        final avisoOk = await enviarMensajeChat(
          adoptanteId,
          nombre,
          msg,
          fotoUrl: d['fotoUrl'] as String?,
          rescateId: doc.id,
          creadoPor: creadoPor,
        );
        if (avisoOk) {
          await doc.reference.update({'avisoPrevioAvisado': true});
          porVencer.add(nombre);
        }
      }
      continue;
    }
    if (d['vencimientoAvisado'] == true) continue;
    final msg = '📋 El período de hogar de paso de $nombre ha vencido. '
        'Por favor coordina la devolución o el proceso de adopción definitivo. 🐾';
    final avisoOk = await enviarMensajeChat(
      adoptanteId,
      nombre,
      msg,
      fotoUrl: d['fotoUrl'] as String?,
      rescateId: doc.id,
      creadoPor: creadoPor,
    );
    if (avisoOk) {
      await doc.reference.update({'vencimientoAvisado': true});
      avisados.add(nombre);
    }
  }
  if (!context.mounted) return;
  if (avisados.isNotEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: msgAdvertencia,
      duration: const Duration(seconds: 6),
      content: Text(avisados.length == 1
          ? '📋 Venció el hogar de paso de ${avisados.first}. Le avisamos al adoptante por chat.'
          : '📋 Venció el hogar de paso de ${avisados.join(', ')}. Les avisamos a los adoptantes por chat.'),
    ));
  }
  if (porVencer.isNotEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: msgAdvertencia,
      duration: const Duration(seconds: 6),
      content: Text(porVencer.length == 1
          ? '📋 El hogar de paso de ${porVencer.first} vence mañana. Le avisamos al adoptante por chat.'
          : '📋 El hogar de paso de ${porVencer.join(', ')} vence mañana. Les avisamos a los adoptantes por chat.'),
    ));
  }
}

/// Recordatorio automático de seguimiento post-adopción — mismo patrón que
/// [verificarVencimientos] (mensaje por chat + flag para no repetirlo),
/// antes duplicado igual que ella. Dos checkpoints (7 y 30 días desde
/// `fechaAdopcion`), cada uno con su propio flag. Si la app se abre recién
/// después de los 30 días (el 7 se saltó de largo), se manda directo el de
/// 30 y se marcan los DOS flags — el checkpoint corto ya no tiene sentido
/// mandarlo tarde.
Future<void> verificarSeguimientoPostAdopcion({
  required String uid,
  required CreatorRole role,
  required String creadoPor,
}) async {
  if (uid.isEmpty) return;
  final ahora = DateTime.now();
  final snap = await RescatesRepository().misRescatesPorEstado(
    uid: uid,
    role: role,
    estadoAdopcion: 'Adoptado',
  );
  for (final doc in snap.docs) {
    final d = doc.data();
    final fechaAdopcion = (d['fechaAdopcion'] as Timestamp?)?.toDate();
    if (fechaAdopcion == null) continue;
    final dias        = ahora.difference(fechaAdopcion).inDays;
    final nombre       = d['nombre']              as String? ?? 'El animal';
    final adoptanteId  = d['adoptanteIdEnProceso'] as String?;
    // Solo se marca "avisado" si el mensaje realmente se guardó — mismo
    // arreglo que verificarVencimientos, mismo motivo (ver comentario ahí).
    // Sin adoptanteId tampoco hay a quién avisarle — mismo motivo que
    // verificarVencimientos (evita el chat "fantasma" sin dueño real que
    // podía marcarse como avisado sin haber avisado a nadie). Hallazgo de
    // auditoría de código.
    if (adoptanteId == null || adoptanteId.isEmpty) continue;
    if (dias >= 30 && d['seguimiento30Avisado'] != true) {
      final avisoOk = await enviarMensajeChat(
        adoptanteId,
        nombre,
        'Ya pasó un mes desde que $nombre encontró hogar con vos 🎉 ¿Cómo se está adaptando? Nos encantaría saber cómo le va.',
        fotoUrl: d['fotoUrl'] as String?,
        rescateId: doc.id,
        creadoPor: creadoPor,
      );
      if (avisoOk) {
        await doc.reference.update({'seguimiento30Avisado': true, 'seguimiento7Avisado': true});
      }
    } else if (dias >= 7 && d['seguimiento7Avisado'] != true) {
      final avisoOk = await enviarMensajeChat(
        adoptanteId,
        nombre,
        '¿Cómo le va a $nombre en su nuevo hogar? 🏡💚 Cualquier cosa que necesite, contános.',
        fotoUrl: d['fotoUrl'] as String?,
        rescateId: doc.id,
        creadoPor: creadoPor,
      );
      if (avisoOk) {
        await doc.reference.update({'seguimiento7Avisado': true});
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class SolicitudesRescatistaScreen extends StatefulWidget {
  final bool esAlbergue;
  const SolicitudesRescatistaScreen({super.key, this.esAlbergue = false});
  @override
  State<SolicitudesRescatistaScreen> createState() => _SolicitudesRescatistaScreenState();
}

class _SolicitudesRescatistaScreenState extends State<SolicitudesRescatistaScreen> {
  final Set<String> _procesando = {};
  final _solicitudesRepo = SolicitudesRepository();

  Future<void> _aprobar(String docId, Map<String, dynamic> d) async {
    if (_procesando.contains(docId)) return;
    setState(() => _procesando.add(docId));
    try {
      final resultado = await aprobarSolicitud(docId, d);
      if (!mounted) return;
      // null = ya se estaba procesando esta misma solicitud (desde acá
      // mismo con este candado local, o desde la vista previa del
      // dashboard con el candado compartido) — no es un error, no hay
      // nada más que avisar.
      if (resultado == null) return;
      if (!resultado.aprobada) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: msgError,
            content: Text(resultado.animalEliminado
                ? 'Este animal ya no existe (fue eliminado). La solicitud se rechazó automáticamente.'
                : 'Este animal ya tenía un proceso aprobado con otro adoptante. '
                    'Esta solicitud se rechazó automáticamente.')));
      } else if (!resultado.avisoOk) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            backgroundColor: msgAdvertencia,
            content: Text('Solicitud aprobada, pero no pudimos avisarle al adoptante por chat. Escribile manualmente.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: msgError, content: Text('No se pudo aprobar la solicitud: $e')));
      }
    } finally {
      if (mounted) setState(() => _procesando.remove(docId));
    }
  }

  Future<void> _rechazar(String docId, Map<String, dynamic> d, String motivo) async {
    // Antes _rechazar no tenía ningún candado local (a diferencia de
    // _aprobar) — reusa el mismo _procesando de acá, así los dos botones
    // se bloquean entre sí para la misma tarjeta, no solo cada uno consigo
    // mismo.
    if (_procesando.contains(docId)) return;
    setState(() => _procesando.add(docId));
    try {
      final avisoOk = await rechazarSolicitud(docId, d, motivo);
      if (!mounted) return;
      if (avisoOk == null) return; // ya se estaba procesando, ver aprobarSolicitud
      if (!avisoOk) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            backgroundColor: msgAdvertencia,
            content: Text('Solicitud rechazada, pero no pudimos avisarle al adoptante por chat.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: msgError, content: Text('No se pudo rechazar la solicitud: $e')));
      }
    } finally {
      if (mounted) setState(() => _procesando.remove(docId));
    }
  }

  String _tiempoRelativo(DateTime fecha) {
    final diff = DateTime.now().difference(fecha);
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}min';
    if (diff.inHours < 24)   return 'hace ${diff.inHours}h';
    return 'hace ${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appBg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 20, 12),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                tooltip: 'Volver',
                onPressed: () => Navigator.pop(context),
              ),
              const Expanded(child: Text('Solicitudes',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: appInk,
                      fontFamily: 'Baloo2'))),
            ]),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _solicitudesRepo.paraOwner(
                uid: FirebaseAuth.instance.currentUser?.uid ?? '',
                role: widget.esAlbergue ? CreatorRole.albergue : CreatorRole.rescatista,
              ),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: appTeal));
                }
                if (snap.hasError) return errorFeedState();
                final docs = [...(snap.data?.docs ?? [])]..sort((a, b) {
                    final ta = a.data()['creadoEn'] as Timestamp?;
                    final tb = b.data()['creadoEn'] as Timestamp?;
                    if (ta == null) return 1;
                    if (tb == null) return -1;
                    return tb.compareTo(ta);
                  });
                if (docs.isEmpty) {
                  return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('Aún no tienes solicitudes',
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 15, fontWeight: FontWeight.w600)),
                    ]),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                  itemCount: docs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final d           = docs[i].data();
                    final animal      = d['animalNombre'] as String? ?? 'Animal';
                    final nombre      = d['nombre']      as String? ?? 'Adoptante';
                    final integrantes = d['integrantes'] as String? ?? '';
                    final vivienda    = d['vivienda']    as String? ?? '';
                    final mascotas    = (d['tieneMascotas'] as bool? ?? false) ? 'con mascotas' : 'sin mascotas';
                    final ninos       = (d['tieneNinos']    as bool? ?? false) ? 'con niños' : 'sin niños';
                    final exp         = (d['experienciaPrevia'] as bool? ?? false) ? 'con experiencia' : 'sin experiencia';
                    final horas       = d['horasFuera'] as String? ?? '';
                    final ts          = d['creadoEn'] as Timestamp?;
                    final tiempo      = ts != null ? _tiempoRelativo(ts.toDate()) : '';
                    final ini         = nombre.isNotEmpty ? nombre[0].toUpperCase() : 'A';
                    final col         = i.isEven ? appTeal : appOrange;
                    final fotoUrl     = d['fotoUrl'] as String?;
                    final estado          = d['estado'] as String? ?? 'pendiente';
                    final tipo            = d['tipoSolicitud']    as String? ?? 'adopcion';
                    final esHogar         = tipo == 'hogar_de_paso';
                    final fechaInicioTs   = d['fechaInicioHogar'] as Timestamp?;
                    final fechaFinTs      = d['fechaFinHogar']    as Timestamp?;
                    final fechaInicio     = fechaInicioTs?.toDate();
                    final fechaFin        = fechaFinTs?.toDate();
                    final diasHogar       = (fechaInicio != null && fechaFin != null)
                        ? fechaFin.difference(fechaInicio).inDays
                        : null;
                    final score       = calcularCompatibilidad(d);
                    final scoreColor  = score >= 80 ? appTeal : score >= 60 ? const Color(0xFFE65100) : const Color(0xFFB71C1C);
                    final estadoColor = estado == 'aprobada'
                        ? appTeal
                        : estado == 'rechazada'
                        ? const Color(0xFFB71C1C)
                        : const Color(0xFFE65100);
                    final estadoLabel = estado == 'aprobada'  ? '✅  Aprobada'
                        : estado == 'rechazada' ? '❌  Rechazada'
                        : '⏳  Pendiente';
                    final detalle     = [
                      vivienda, if (integrantes.isNotEmpty) '$integrantes personas',
                      ninos, mascotas, exp,
                      if (horas.isNotEmpty) '$horas h fuera/día',
                    ].join(' · ');

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                        // ── Fila principal: animal ──────────────────────────
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          // Foto del animal
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            // FotoAnimal en vez de recorte — mismo arreglo
                            // que mis_rescates_screen.dart: el recorte fijo
                            // (topCenter) cortaba animales que no quedan
                            // cerca del borde superior de la foto.
                            child: fotoUrl != null
                              ? FotoAnimal(
                                  url: fotoUrl,
                                  width: 64, height: 64,
                                  fallback: Container(width: 64, height: 64,
                                      color: const Color(0xFFD8F0E4),
                                      child: const Center(child: Icon(Icons.pets, color: appTeal, size: 30))),
                                )
                              : Container(width: 64, height: 64,
                                  color: const Color(0xFFD8F0E4),
                                  child: const Center(child: Icon(Icons.pets, color: appTeal, size: 30))),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(
                                child: Text(animal,
                                    style: const TextStyle(fontWeight: FontWeight.bold,
                                        fontSize: 17, color: appInk)),
                              ),
                              Text(tiempo, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                            ]),
                            const SizedBox(height: 6),
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: esHogar ? appTeal.withValues(alpha: 0.12) : appOrange.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: esHogar ? appTeal.withValues(alpha: 0.4) : appOrange.withValues(alpha: 0.4)),
                                ),
                                child: Text(esHogar ? '🏡 Hogar de paso' : '🏠 Adopción',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                                        color: esHogar ? appTeal : appOrange)),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: estadoColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: estadoColor.withValues(alpha: 0.4)),
                                ),
                                child: Text(estadoLabel, style: TextStyle(fontSize: 10,
                                    fontWeight: FontWeight.w700, color: estadoColor)),
                              ),
                            ]),
                          ])),
                        ]),

                        // ── Fila adoptante ──────────────────────────────────
                        const SizedBox(height: 12),
                        Row(children: [
                          CircleAvatar(backgroundColor: col, radius: 14,
                            child: Text(ini, style: const TextStyle(color: Colors.white,
                                fontSize: 12, fontWeight: FontWeight.bold))),
                          const SizedBox(width: 8),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(nombre, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            Text(detalle, style: TextStyle(fontSize: 11, color: Colors.grey.shade700), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ])),
                        ]),

                        if (esHogar && fechaInicio != null && fechaFin != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: appTeal.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: appTeal.withValues(alpha: 0.3)),
                            ),
                            child: Row(children: [
                              const Icon(Icons.calendar_today, size: 13, color: appTeal),
                              const SizedBox(width: 8),
                              Text(
                                '${fechaInicio.day}/${fechaInicio.month}/${fechaInicio.year} → ${fechaFin.day}/${fechaFin.month}/${fechaFin.year}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: appTeal),
                              ),
                              const Spacer(),
                              Text('$diasHogar días', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: appTeal)),
                            ]),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: scoreColor.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: scoreColor.withValues(alpha: 0.35)),
                          ),
                          child: Row(children: [
                            Text(score >= 80 ? '✅' : score >= 60 ? '⚠️' : '❌',
                                style: const TextStyle(fontSize: 18)),
                            const SizedBox(width: 10),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(
                                score >= 80 ? 'Perfil ideal ($score%)'
                                    : score >= 60 ? 'Perfil aceptable ($score%)'
                                    : 'No recomendado ($score%)',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scoreColor),
                              ),
                              const SizedBox(height: 8),
                              ...explicarCompatibilidad(d).map((r) => Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(r.$2 ? '✓' : '✗',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                                          color: r.$2 ? appTeal : Colors.red.shade400)),
                                  const SizedBox(width: 5),
                                  Expanded(child: Text(r.$1,
                                      style: TextStyle(fontSize: 11,
                                          color: r.$2 ? Colors.grey.shade700 : Colors.red.shade600))),
                                ]),
                              )),
                            ])),
                          ]),
                        ),
                        if (estado == 'rechazada') ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF8F0),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFE65100).withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              (d['motivoRechazo'] as String?)?.isNotEmpty == true
                                  ? d['motivoRechazo'] as String
                                  : 'Hola, gracias por tu interés en adoptar a $animal. '
                                    'Luego de revisar tu solicitud, en esta ocasión no podemos continuar con el proceso. '
                                    '¡Esperamos que pronto encuentres a tu compañero perfecto! 🐾',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.5),
                            ),
                          ),
                        ],
                        if (estado == 'aprobada') ...[
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: () async {
                              final adoptanteId = d['adoptanteId'] as String? ?? '';
                              final rescateIdChat = d['rescateId'] as String? ?? '';
                              String? chatId;
                              // try/catch: leer un chat que NO existe da
                              // permission-denied con nuestras reglas (no
                              // pueden probar que te corresponde ver un doc
                              // que no está). Pasa cuando el mensaje
                              // automático de la aprobación no llegó a crear
                              // el chat — sin esto, la excepción mataba el
                              // onTap y el botón "Ir al chat" no hacía nada.
                              // Con chatId null, ChatScreen crea el chat.
                              try {
                                if (rescateIdChat.isNotEmpty) {
                                  final doc = await FirebaseFirestore.instance
                                      .collection('chats').doc(ChatsRepository()
                                          .idAnimal(rescateId: rescateIdChat, adoptanteId: adoptanteId)).get();
                                  if (doc.exists) chatId = doc.id;
                                } else {
                                  final snap = await FirebaseFirestore.instance
                                      .collection('chats')
                                      .where('adoptanteId', isEqualTo: adoptanteId)
                                      .where('animalNombre', isEqualTo: animal)
                                      .limit(1)
                                      .get();
                                  if (snap.docs.isNotEmpty) chatId = snap.docs.first.id;
                                }
                              } catch (_) {
                                chatId = null;
                              }
                              if (!context.mounted) return;
                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  esRescatista: true,
                                  chatId: chatId,
                                  animal: {
                                    'nombre':         animal,
                                    'rescatista':     FirebaseAuth.instance.currentUser?.displayName ?? 'Rescatista',
                                    'rescatistaId':   FirebaseAuth.instance.currentUser?.uid ?? '',
                                    'rescateId':      d['rescateId'] as String? ?? '',
                                    'adoptanteId':    adoptanteId,
                                    'adoptanteNombre': d['nombre'] as String? ?? 'Adoptante',
                                    'especie':        d['especie'] as String? ?? 'Perro',
                                    'fotoUrl':        d['fotoUrl'] as String?,
                                    'tipoSolicitud':  d['tipoSolicitud'] as String? ?? 'adopcion',
                                    'creadoPor':      d['creadoPor'] as String? ?? 'rescatista',
                                    'edad':           '',
                                    'ubicacion':      '',
                                    'descripcion':    '',
                                    'tags':           <String>[],
                                  },
                                ),
                              ));
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: appTeal,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(Icons.chat_bubble_outline, size: 15, color: Colors.white),
                                SizedBox(width: 6),
                                Text('Ir al chat', style: TextStyle(fontSize: 13,
                                    fontWeight: FontWeight.w700, color: Colors.white)),
                              ]),
                            ),
                          ),
                          // Solo lectura acá: quien acepta el compromiso es
                          // el adoptante (ver mis_solicitudes_screen.dart),
                          // el rescatista/albergue solo ve la constancia.
                          if ((d['tipoSolicitud'] as String? ?? 'adopcion') == 'adopcion') ...[
                            const SizedBox(height: 8),
                            Row(children: [
                              Icon(
                                d['acuerdoAceptado'] == true ? Icons.check_circle : Icons.hourglass_empty,
                                size: 13,
                                color: d['acuerdoAceptado'] == true ? appTeal : Colors.grey.shade400,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                d['acuerdoAceptado'] == true
                                    ? 'Compromiso de adopción aceptado'
                                    : 'Compromiso de adopción: aún no aceptado',
                                style: TextStyle(fontSize: 11.5,
                                    color: d['acuerdoAceptado'] == true ? appTeal : Colors.grey.shade700),
                              ),
                            ]),
                          ],
                        ],
                        if (estado == 'pendiente') ...[
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: _procesando.contains(docs[i].id)
                                    ? null
                                    : () => _aprobar(docs[i].id, d),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: _procesando.contains(docs[i].id)
                                        ? appTeal.withValues(alpha: 0.5)
                                        : appTeal,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: _procesando.contains(docs[i].id)
                                      ? const SizedBox(height: 16, width: 16,
                                          child: Center(child: SizedBox(height: 14, width: 14,
                                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))))
                                      : const Text('Aprobar', textAlign: TextAlign.center,
                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: GestureDetector(
                                // Antes se podía abrir este diálogo aunque ya
                                // se estuviera aprobando/rechazando esta misma
                                // tarjeta (con Aprobar, o con un Rechazar
                                // anterior) — mismo _procesando que ya usaba
                                // Aprobar, para que los dos botones se
                                // bloqueen entre sí.
                                onTap: _procesando.contains(docs[i].id) ? null : () {
                                  final motivoCtl = TextEditingController(
                                    text: 'Hola, gracias por tu interés en adoptar a $animal. '
                                        'Luego de revisar tu solicitud, en esta ocasión no podemos continuar con el proceso. '
                                        '¡Esperamos que pronto encuentres a tu compañero perfecto! 🐾',
                                  );
                                  // .then() en vez de un dispose() suelto: este
                                  // showDialog no se espera (el onTap no es
                                  // async), así que hay que liberar el
                                  // controller recién cuando el diálogo se
                                  // cierra de verdad (Cancelar o Confirmar).
                                  showDialog(context: context, builder: (dlg) => AlertDialog(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    title: const Text('Mensaje de rechazo'),
                                    content: TextField(
                                      controller: motivoCtl,
                                      maxLines: 5,
                                      decoration: InputDecoration(
                                        hintText: '',
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: const BorderSide(color: appTeal, width: 2),
                                        ),
                                      ),
                                    ),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(dlg), child: const Text('Cancelar')),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(dlg);
                                          _rechazar(docs[i].id, d, motivoCtl.text.trim());
                                        },
                                        child: const Text('Confirmar', style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  )).then((_) => motivoCtl.dispose());
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: _procesando.contains(docs[i].id)
                                        ? Colors.red.shade100 : Colors.red.shade300),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text('Rechazar', textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: _procesando.contains(docs[i].id)
                                              ? Colors.red.shade200 : Colors.red.shade400,
                                          fontWeight: FontWeight.bold, fontSize: 13)),
                                ),
                              ),
                            ),
                          ]),
                        ],
                      ]),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
