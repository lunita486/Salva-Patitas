import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/chats_repository.dart';

// ─── Fecha ────────────────────────────────────────────────────────────────────
// El mismo arreglo de meses abreviados en español se copiaba, con leves
// variaciones, en 6 pantallas distintas (hallazgo de auditoría de código) —
// se centraliza acá para que un cambio de formato (o de idioma, algún día)
// se aplique en un solo lugar.
const _mesesAbreviados = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

/// "15 jul" o "15 jul 2026" según [conAnio]. Pantallas con lógica propia de
/// fecha relativa (ej. chat_screen.dart, que también muestra "Hoy"/"Ayer" y
/// solo agrega el año si difiere del actual) siguen resolviendo esa parte
/// ellas mismas y llaman a esta función solo para el "día mes [año]" final.
String formatearFecha(DateTime d, {bool conAnio = true}) =>
    '${d.day} ${_mesesAbreviados[d.month - 1]}${conAnio ? ' ${d.year}' : ''}';

// ─── WhatsApp ─────────────────────────────────────────────────────────────────
// Compartido entre albergue_publico_screen.dart y aliado_publico_screen.dart
// (los dos muestran el mismo botón "Escribir por WhatsApp" si el perfil
// cargó un teléfono).
//
/// Arma el link de WhatsApp a partir de lo que la persona haya escrito en
/// "Teléfono/WhatsApp". Los números guardados con [CampoTelefono] ya vienen
/// con su indicativo real adelante ("+52 55 1234 5678", por ejemplo) y se
/// usan tal cual.
///
/// Para números viejos, guardados en el formato libre de antes de que
/// existiera el selector de país, se asume Colombia si quedan 10 dígitos
/// al limpiar todo lo que no sea número — eso cubre tanto un celular
/// (empieza en 3) como un fijo con el prefijo "60" que el plan de
/// numeración de Colombia le agregó a todos los fijos del país (ej. un fijo
/// de Medellín: "604 444 4444"). Antes solo se cubría el caso celular, así
/// que un fijo escrito tal como lo sugiere el propio campo (sin +57
/// delante) armaba un link roto — bug real reportado por Eliza.
///
/// Esa adivinanza SOLO se aplica si el texto no viene ya con un "+"
/// adelante — un número armado por [CampoTelefono] siempre lo tiene, así
/// que nunca necesita que se le adivine nada. Sin este chequeo, un
/// celular cubano (indicativo 53 + 8 dígitos) o un fijo panameño
/// (indicativo 507 + 7 dígitos) TAMBIÉN dan 10 dígitos en total, y aunque
/// la persona hubiera elegido bien su país en el selector, terminaban con
/// un 57 de más pegado adelante — regresión de esta misma sesión, hallazgo
/// de auditoría de código.
String? whatsappUrl(String telefono) {
  final yaTieneIndicativo = telefono.trim().startsWith('+');
  final digitos = telefono.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitos.isEmpty) return null;
  final conIndicativo = (!yaTieneIndicativo && digitos.length == 10)
      ? '57$digitos'
      : digitos;
  return 'https://wa.me/$conIndicativo';
}

/// Normaliza lo que la persona haya escrito en "Página web" (con o sin
/// "http(s)://", con o sin "www.") a una URL abrible — si no escribió nada
/// con esquema, se le antepone "https://" antes de abrirla.
String sitioWebUrl(String sitioWeb) {
  final limpio = sitioWeb.trim();
  return limpio.startsWith('http://') || limpio.startsWith('https://')
      ? limpio
      : 'https://$limpio';
}

// ─── Umbral de "animal estancado" ────────────────────────────────────────────
// Cuántos días sin encontrar hogar antes de mostrar el aviso naranja en
// mis_rescates_screen.dart. Configurable por cada rescatista/albergue desde
// su perfil (pedido explícito de Eliza — antes eran 30 días fijos para
// todos). El umbral "urgente" (rojo) no es una segunda configuración: se
// deriva como el doble del elegido, misma proporción 30/60 que tenía el
// valor fijo.
//
// Guardado en DOS campos separados de `usuarios/{uid}`
// (`umbralEstancadoDiasRescatista`/`umbralEstancadoDiasAlbergue`), no uno
// solo — una cuenta con doble rol (rescatista + albergue) comparte el mismo
// documento, y con un solo campo genérico, configurar "15 días" del lado
// rescatista también le cambiaba el umbral al albergue (y viceversa) sin
// que la persona lo pidiera. Mismo motivo por el que
// albergueTelefono/albergueEmail tienen su propio prefijo en vez de usar
// telefono/email genéricos (ver albergue_perfil_screen.dart). Hallazgo real
// de Eliza: "pone ese mismo valor en el albergue y viceversa".
const umbralEstancadoDefault = 30;
const umbralEstancadoOpciones = [
  (15, '15 días'),
  (30, '30 días'),
  (60, '2 meses'),
  (90, '3 meses'),
  (180, '6 meses'),
  (365, '1 año y más'),
];

int umbralEstancadoDe(
  Map<String, dynamic>? datosUsuario, {
  required bool esAlbergue,
}) =>
    (datosUsuario?[esAlbergue
            ? 'umbralEstancadoDiasAlbergue'
            : 'umbralEstancadoDiasRescatista']
        as int?) ??
    umbralEstancadoDefault;

/// "En cuidado" = físicamente presente en tu espacio, no "animal del que
/// sos responsable en total" — única fuente de esta regla, antes copiada
/// a mano en el panel del albergue (albergue_home_screen.dart) y en el
/// filtro "En cuidado" de mis_rescates_screen.dart, cada una con su
/// propio comentario prometiendo mantenerse igual que la otra. `Regresado`
/// SÍ cuenta (volvió de verdad a estar con vos, ocupando capacidad real —
/// antes no se contaba acá, y el % de ocupación mentía hacia abajo apenas
/// alguien devolvía un animal: hallazgo real de Eliza, "regresaron 2
/// animalitos y la app sigue mostrando solo 1"). `Hogar de paso` NO cuenta
/// (está en la casa de otra persona, libera capacidad real aunque sigas
/// siendo responsable de ese caso — pedido explícito de Eliza).
bool cuentaComoEnCuidado(String? estadoAdopcion) {
  final e = estadoAdopcion ?? 'Rescatado';
  return e == 'Rescatado' || e == 'Regresado';
}

/// ¿Este animal está "estancado" — esperando desde hace [umbral] días o
/// más, todavía sin resolución? Única fuente de esta regla, antes copiada
/// a mano en el filtro "Estancados" y en el aviso de la tarjeta de
/// mis_rescates_screen.dart (mismo comentario "mismo criterio que..." en
/// los dos, sin nada que garantizara que siguieran iguales). `Regresado`
/// cuenta — de hecho es el caso más urgente, ya falló una vez en
/// encontrar hogar definitivo.
bool esEstancado({
  required int? diasEsperando,
  required String? estadoAdopcion,
  required int umbral,
}) {
  if (diasEsperando == null || diasEsperando < umbral) return false;
  final e = estadoAdopcion ?? 'Rescatado';
  return e == 'Rescatado' || e == 'Hogar de paso' || e == 'Regresado';
}

/// El aviso de estancado se pinta más grave (rojo en vez de naranja) al
/// doble del umbral — única fuente de ese segundo corte, antes solo vivía
/// como un cálculo inline en mis_rescates_screen.dart.
bool esEstancadoGrave({required int? diasEsperando, required int umbral}) =>
    (diasEsperando ?? 0) >= umbral * 2;

/// Orden de atención para listas de "mis rescates" (carrusel de
/// home_screen.dart y albergue_home_screen.dart): primero lo que el
/// rescatista/albergue necesita mirar activamente (una adopción en curso,
/// un hogar de paso con fecha de vencimiento), después lo disponible sin
/// trámite pendiente, y al final lo que ya se cerró (adoptado/fallecido) y
/// no necesita ninguna acción más. Pedido real de Eliza: "así le facilitamos
/// el trabajo al rescatista y también al albergue". Menor número = primero.
int prioridadEstado(String? estadoAdopcion) => switch (estadoAdopcion) {
  'En proceso de adopción' => 0,
  'Hogar de paso' => 1,
  'Adoptado' || 'Fallecido' => 3,
  _ => 2, // Rescatado, Regresado, legado sin estado
};

// ─── Tiempo relativo ──────────────────────────────────────────────────────────
// "hace 5min"/"hace 3h"/"hace 2d" — antes copiada byte a byte en
// solicitudes_preview.dart y solicitudes_rescatista_screen.dart, cada una con
// su propia función `_tiempoRelativo` idéntica a la otra, sin nada que
// avisara si alguna cambiaba los cortes (60min/24h) y la otra no. Hallazgo de
// auditoría de código, 2026-08-16 — todavía no habían divergido, pero es el
// mismo mecanismo que sí llegó a causar bugs reales acá (vocabulario de
// salud, scoring de compatibilidad): dos copias sin dueño único.
String tiempoRelativo(DateTime fecha) {
  final diff = DateTime.now().difference(fecha);
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}min';
  if (diff.inHours < 24) return 'hace ${diff.inHours}h';
  return 'hace ${diff.inDays}d';
}

/// Cuenta chats con mensajes sin leer para el lado rescatista o albergue de
/// una cuenta — suma lo RECIBIDO (chats de animal, `rescatistaId == uid`) y
/// lo ENVIADO (consultas a un negocio aliado, `adoptanteId == uid`). Antes
/// el badge de "mensajes sin leer" (home_screen.dart,
/// albergue_home_screen.dart) solo miraba lo recibido: una respuesta a una
/// consulta que la propia cuenta le mandó a un negocio aliado (veterinaria,
/// peluquería) nunca aparecía contada acá, aunque SÍ aparecía en la lista
/// de Chats — auditoría de reglas de negocio, hallazgo real de Eliza
/// (2026-08-06): "que no pase lo de los 11 animales rescatados que no era
/// real".
///
/// `recibidos` excluye consultas a un aliado aunque `rescatistaId == uid`
/// (pasa cuando esta MISMA cuenta también es el negocio consultado) — esas
/// pertenecen al badge propio del aliado (aliado_home_screen.dart), no a
/// este. `consultasEnviadas` solo cuenta las mandadas CON ESE sombrero
/// puntual (`creadoPor` exacto) — una consulta mandada como adoptante
/// (sin `creadoPor`) no es ni del rescatista ni del albergue.
int contarMensajesSinLeer({
  required List<QueryDocumentSnapshot>? recibidos,
  required List<QueryDocumentSnapshot>? consultasEnviadas,
  required bool esAlbergue,
  required String uid,
}) {
  // Qué campo mirar (`noLeidosRescatista` vs `noLeidosAdoptante`) lo decide
  // ChatsRepository.noLeidosPara — ÚNICA fuente de esa pregunta para toda la
  // app, la misma que usa AdoptanteChatsScreen para pintar el badge de cada
  // fila. Antes esta función tenía su propia copia de esa lógica, y una
  // divergencia entre las dos copias (un filtro que una tenía y la otra no)
  // podía dejar un "sin leer" que el panel contaba pero la lista escondía
  // por completo, así que nunca bajaba a cero. Con una sola fuente, los dos
  // lugares miran exactamente el mismo campo para exactamente el mismo chat.
  final deRecibidos = (recibidos ?? []).where((doc) {
    final d = doc.data() as Map<String, dynamic>;
    if ((d['tipoSolicitud'] as String? ?? '') == 'consulta_aliado')
      return false;
    final creadoPor = d['creadoPor'] as String? ?? 'rescatista';
    return (esAlbergue ? creadoPor == 'albergue' : creadoPor != 'albergue') &&
        ChatsRepository.noLeidosPara(d, uid: uid, esRescatista: true) > 0;
  }).length;

  final hatEsperado = esAlbergue ? 'albergue' : 'rescatista';
  final deEnviados = (consultasEnviadas ?? []).where((doc) {
    final d = doc.data() as Map<String, dynamic>;
    return (d['creadoPor'] as String?) == hatEsperado &&
        ChatsRepository.noLeidosPara(d, uid: uid, esRescatista: true) > 0;
  }).length;

  return deRecibidos + deEnviados;
}
