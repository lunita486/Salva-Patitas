import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/chats_repository.dart';
import '../data/creator_role.dart';

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

/// Chequeo básico de FORMA de un email — no confirma que exista de
/// verdad (nada del lado del cliente puede), solo que tenga la pinta
/// mínima de uno (`algo@algo.algo`). Usado para bloquear el guardado del
/// perfil de Aliado, mismo criterio que ya tiene la ciudad geocodificada
/// del mismo perfil: un dato opcional puede quedar vacío, pero si se
/// escribe algo, tiene que tener forma real. Hallazgo real de Eliza:
/// "sjejdj" se guardaba igual que un email de verdad.
final RegExp _formaDeEmail = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
bool esEmailValido(String email) => _formaDeEmail.hasMatch(email.trim());

/// Mismo criterio que [esEmailValido], para "Página web". [sitioWebUrl]
/// ya sabe abrir cualquier texto con o sin esquema, pero "se puede armar
/// una URL con esto" no es lo mismo que "esto es un dominio real" — hace
/// falta al menos un punto con texto real a los dos lados. Hallazgo real
/// de Eliza: "sjejdj" también pasaba acá, sin ningún aviso.
final RegExp _formaDeSitioWeb = RegExp(
  r'^(https?:\/\/)?[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?'
  r'(\.[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?)+(\/.*)?$',
);
/// El último segmento (después del último punto, y antes de un posible
/// `/algo`) tiene que ser solo letras — ningún dominio de primer nivel
/// real (.com, .org, .co, .net...) lleva números. Sin esto, "www.
/// veterinariola30" pasaba: SÍ tiene forma de dominio (palabra.palabra),
/// pero "la30" no es un TLD que pueda existir. No hace falta una lista de
/// TLDs válidos (se desactualizaría sola) — esta única regla ya descarta
/// el error más común: escribir el nombre del negocio pegado al final en
/// vez de agregar el ".com". Hallazgo real de Eliza probando el perfil
/// del aliado.
final RegExp _tldSoloLetras = RegExp(r'\.([a-zA-Z]+)(?:\/.*)?$');
bool esSitioWebValido(String sitioWeb) {
  final texto = sitioWeb.trim();
  if (!_formaDeSitioWeb.hasMatch(texto)) return false;
  final tld = _tldSoloLetras.firstMatch(texto)?.group(1);
  return tld != null && tld.length >= 2;
}

/// Mensajes de aviso para [esEmailValido]/[esSitioWebValido], compartidos
/// entre aliado_perfil_screen.dart y albergue_perfil_screen.dart — antes
/// cada pantalla tenía su propia copia del texto, con guion largo y en
/// segunda persona imperativa ("Eso no tiene forma de email — dejalo
/// vacío..."), que sonaba a regaño. Pedido real de Eliza: sin guion largo,
/// tono más amable. Una sola versión evita que las dos pantallas vuelvan
/// a decir cosas distintas para el mismo aviso.
const avisoEmailInvalido =
    'Ese texto no parece un email. Podés dejarlo vacío o escribir uno real.';
const avisoSitioWebInvalido =
    'Ese texto no parece una página web. Podés dejarlo vacío o escribir una real.';

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

/// ¿Este animal todavía se puede adoptar? Única fuente de esta pregunta.
///
/// Existe porque el feed de adopción y Favoritos la contestaban DISTINTO
/// para el mismo animal, cada uno con su propia lista de estados escrita a
/// mano:
///
///   feed      → disponible si el estado es null, 'Rescatado', 'Regresado'
///               o 'Hogar de paso'
///   favoritos → NO disponible si es 'En proceso de adopción', 'Adoptado',
///               'Hogar de paso' o 'Fallecido'
///
/// Se contradecían justo en **'Hogar de paso'**: el mismo animal aparecía
/// como adoptable en el feed y como "ya no está disponible" en Favoritos.
/// Gana el criterio del feed, que es el que decide qué se puede pedir de
/// verdad: un animal en hogar de paso SÍ se puede adoptar (el hogar de
/// paso es temporal, justamente mientras espera adopción definitiva) —
/// mismo criterio que ya usa `cuentaComoEnCuidado` al no contarlo como
/// capacidad ocupada.
///
/// Un estado ausente es un animal recién publicado ('Rescatado'), así que
/// también está disponible.
bool sePuedeAdoptar(String? estadoAdopcion) {
  final e = estadoAdopcion ?? 'Rescatado';
  return e == 'Rescatado' || e == 'Regresado' || e == 'Hogar de paso';
}

/// Las coordenadas guardadas de un animal, o `null` si no tiene unas
/// usables. Única fuente de "¿este documento tiene ubicación?".
///
/// Hace DOS cosas que el feed no hacía, y las dos le costaron caro:
///
/// 1. **Descarta (0, 0).** "Null Island" no es una ubicación real: es lo
///    que devuelve Android cuando el GPS todavía no tiene lectura. El
///    servicio de ubicación ya la rechaza AL GUARDAR (ver
///    `UbicacionService._valida`, con el mismo hallazgo documentado), pero
///    los animales guardados antes de ese arreglo siguen teniéndola, y el
///    feed las trataba como coordenadas buenas: mostraba "Se encuentra a
///    8875.1 km de ti" y ordenaba por esa distancia inventada. El guard
///    estaba puesto solo del lado de la escritura; del lado de la lectura
///    nunca se tapó.
///
/// 2. **Lee `num`, no `double`.** El feed usaba `as double?` mientras el
///    resto de la app usa `(as num?)?.toDouble()`. Un valor guardado como
///    entero (tocado a mano en la consola, o escrito por el trigger del
///    servidor, que serializa los enteros de JS como `integerValue`) hacía
///    reventar el cast — y como el orden por distancia corre adentro del
///    builder de la lista, esa excepción no rompía una tarjeta: se llevaba
///    puesta la pestaña Adoptar entera, en cada redibujado.
({double lat, double lng})? coordenadasDe(Map<String, dynamic> datos) {
  final lat = (datos['latitud'] as num?)?.toDouble();
  final lng = (datos['longitud'] as num?)?.toDouble();
  if (lat == null || lng == null) return null;
  if (lat == 0 && lng == 0) return null;
  return (lat: lat, lng: lng);
}

/// Cuántos días faltan para que venza un hogar de paso: 0 = vence HOY,
/// negativo = ya venció. Única fuente de esta cuenta.
///
/// Compara solo la FECHA, sin la hora, y eso es justamente el punto. El
/// panel del rescatista usaba `fechaFin.isAfter(ahora)` —con hora—, y como
/// la fecha de fin se guarda a medianoche, el día del vencimiento ya
/// contaba como vencido desde las 00:00. "Mis solicitudes" (del lado del
/// adoptante) comparaba solo por fecha, así que el mismo día decía "vence
/// hoy".
///
/// Resultado real: el día exacto de fin, al adoptante le aparecía
/// "⚠️ El período vence hoy" mientras al rescatista la app ya le había
/// mandado por chat "El período de hogar de paso ha vencido, por favor
/// coordina la devolución". Gana el criterio por fecha: un hogar de paso
/// que termina hoy no está vencido hasta que hoy termine.
int diasHastaVencimiento({required DateTime fechaFin, required DateTime ahora}) {
  final fin = DateTime(fechaFin.year, fechaFin.month, fechaFin.day);
  final hoy = DateTime(ahora.year, ahora.month, ahora.day);
  return fin.difference(hoy).inDays;
}

/// ¿El período de hogar de paso YA venció? Ver [diasHastaVencimiento] para
/// el porqué de comparar solo la fecha.
bool hogarDePasoVencido({
  required DateTime fechaFin,
  required DateTime ahora,
}) => diasHastaVencimiento(fechaFin: fechaFin, ahora: ahora) < 0;

/// ¿Este servicio de un negocio aliado está activo (visible para quien
/// busca)? Única fuente de esta pregunta.
///
/// Existe porque se contestaba de DOS formas distintas, y la diferencia
/// era invisible hasta que aparecía un servicio sin el campo:
///
///   perfil público del aliado y contador "Servicios activos"
///                        → `activo == true`   (ausente = INACTIVO)
///   lista propia del aliado, con su interruptor
///                        → `activo ?? true`   (ausente = ACTIVO)
///
/// O sea: un servicio sin el campo (los creados antes de que existiera) se
/// le mostraba a su dueño como activo, con el interruptor encendido, pero
/// no aparecía en su perfil público ni contaba en su propio panel. Un
/// servicio invisible para los clientes sin que el negocio tuviera forma
/// de notarlo.
///
/// Gana `?? true`: un servicio que se publicó y nunca se apagó a propósito
/// está activo — apagarlo es una acción explícita del interruptor, y hoy
/// `subir_servicio_screen.dart` siempre escribe `activo: true` al crear.
bool servicioEstaActivo(Map<String, dynamic> servicio) =>
    servicio['activo'] as bool? ?? true;

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
    return (esAlbergue
            ? esCreadoPorAlbergue(creadoPor)
            : !esCreadoPorAlbergue(creadoPor)) &&
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

/// Lo que se guarda cuando un animal no tiene nombre puesto.
///
/// No debería existir como DATO — es un texto de pantalla — pero se coló a
/// la base: alguna pantalla copió a `solicitudes` el nombre ya resuelto
/// para mostrar en vez del dato real, y quedó escrito así para siempre en
/// las solicitudes de ese momento. Por eso [nombreDeAnimal] lo trata como
/// ausencia de nombre en vez de como un nombre: sin eso salía "Para Sin
/// nombre" (reportado por Eliza).
const _placeholderNombreAnimal = 'Sin nombre';

/// El nombre de un animal, listo para mostrar.
///
/// La misma pregunta se respondía en 7 lugares con 4 respuestas distintas
/// —'Sin nombre', 'Animal', 'un animalito', y la cadena vacía— y dos de
/// ellas convivían en la MISMA pantalla (mis_solicitudes_screen), así que
/// un animal sin nombre se llamaba distinto en el encabezado y en la lista
/// de abajo.
///
/// [enFrase] elige entre las dos formas que sí son legítimamente distintas:
/// un título de tarjeta se rotula "Sin nombre", pero dentro de una oración
/// eso da "Para Sin nombre", que no se lee como español. La decisión de
/// cuál usar sigue siendo de quien llama; lo que ya no se decide de nuevo
/// cada vez es QUÉ texto es cada una y qué cuenta como "no tiene nombre".
String nombreDeAnimal(String? nombre, {bool enFrase = false}) {
  final limpio = nombre?.trim() ?? '';
  if (limpio.isEmpty || limpio == _placeholderNombreAnimal) {
    return enFrase ? 'un animalito' : _placeholderNombreAnimal;
  }
  return limpio;
}
