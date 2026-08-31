import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/ubicacion_service.dart' show CandidatoUbicacion;
import 'firestore_resiliencia.dart';

/// Los contadores de perfil guardados en `usuarios/{uid}`.
///
/// **Los escribe únicamente el servidor**, desde el trigger de
/// `functions/contadores.js`. La app solo los lee, y `firestore.rules` lo
/// hace cumplir: un intento de escribirlos desde acá se rechaza (hay tests
/// negativos en `test_rules/`).
///
/// **Por qué existen.** Dos pantallas muestran números sobre la colección
/// de animalitos: el perfil del rescatista ("Animales rescatados" /
/// "Adopciones aprobadas") y el perfil público del albergue ("En cuidado"
/// / "Adoptados"). Salían de `count()`, que es una agregación y solo puede
/// leer del SERVIDOR: no hay caché posible, así que cada apertura pagaba
/// un viaje de red entero.
///
/// La prueba más limpia de eso la trajo Eliza sin buscarla: en el perfil
/// del albergue, la CAPACIDAD aparece al instante y los otros dos números
/// tardan. Misma pantalla, mismo momento. La capacidad es un campo de este
/// mismo documento y se sirve del caché; los otros dos no podían.
///
/// Guardados acá, viajan en el MISMO snapshot que `capacidadTotal`, sin
/// una consulta nueva.
///
/// Los nombres dicen de qué rol hablan a propósito: una misma cuenta puede
/// ser rescatista Y albergue a la vez. Tienen que decir lo mismo que
/// `DEFINICIONES` en `functions/contadores_logica.js`; hay un test que
/// compara los dos archivos, porque nada más los ata.
const campoContadorRescatistaTotal = 'contadorRescatistaTotal';
const campoContadorRescatistaAdoptados = 'contadorRescatistaAdoptados';
const campoContadorAlbergueEnCuidado = 'contadorAlbergueEnCuidado';
const campoContadorAlbergueAdoptados = 'contadorAlbergueAdoptados';

/// El par de contadores que trae el documento del perfil, o `null` si ese
/// documento todavía no los tiene.
///
/// `null` NO quiere decir cero: quiere decir que este perfil todavía no
/// fue sembrado (cuenta recién creada que aún no publicó nada, o cuenta
/// vieja antes del backfill). Quien llama tiene que distinguir esos dos
/// casos, porque mostrar un 0 ahí sería afirmar algo que no se sabe.
///
/// Es una función y no dos lecturas sueltas en cada pantalla para que la
/// decisión "¿hay contador guardado o hay que contar a mano?" se pueda
/// probar sola, y para que las dos pantallas la tomen igual. Si esa rama
/// se invirtiera, el perfil volvería a pagar un `count()` en cada apertura
/// sin que se note en la UI.
({int principal, int adoptados})? contadoresGuardadosDe(
  Map<String, dynamic>? datos, {
  required String campoPrincipal,
  required String campoAdoptados,
}) {
  final principal = datos?[campoPrincipal];
  final adoptados = datos?[campoAdoptados];
  // `is int` y no `as int?`: un campo escrito a mano desde la consola
  // podría venir con otro tipo, y en ese caso conviene caer al conteo real
  // en vez de reventar la pantalla.
  if (principal is int && adoptados is int) {
    return (principal: principal, adoptados: adoptados);
  }
  return null;
}

/// Los del perfil del rescatista: "Animales rescatados" (todos los
/// estados) y "Adopciones aprobadas".
({int principal, int adoptados})? contadoresRescatistaDe(
  Map<String, dynamic>? datos,
) => contadoresGuardadosDe(
  datos,
  campoPrincipal: campoContadorRescatistaTotal,
  campoAdoptados: campoContadorRescatistaAdoptados,
);

/// Los del perfil público del albergue: "En cuidado" (Rescatado +
/// Regresado, la misma lista que la grilla) y "Adoptados".
({int principal, int adoptados})? contadoresAlbergueDe(
  Map<String, dynamic>? datos,
) => contadoresGuardadosDe(
  datos,
  campoPrincipal: campoContadorAlbergueEnCuidado,
  campoAdoptados: campoContadorAlbergueAdoptados,
);

/// Centraliza las escrituras del campo `roles` en `usuarios/{uid}`
/// (antes se escribía suelto desde ~7 pantallas de debug distintas, sin
/// validar qué valores eran válidos).
class UsuariosRepository {
  UsuariosRepository({FirebaseFirestore? db, FirebaseAuth? auth})
    : _db = db ?? FirebaseFirestore.instance,
      _authOverride = auth;
  final FirebaseFirestore _db;
  // Lazy, mismo motivo que en RescatesRepository: evaluar FirebaseAuth.instance
  // en el constructor rompe cualquier test que no pase un auth mockeado.
  final FirebaseAuth? _authOverride;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  static const rolesValidos = {'adoptante', 'rescatista', 'albergue', 'aliado'};

  /// Todos los negocios aliados (`aliadoNombre` cargado), UNA sola vez —
  /// no en vivo.
  ///
  /// Por qué no `.snapshots()`: un stream en vivo primero pinta lo que haya
  /// en la CACHÉ local del teléfono (a veces vacía, a veces con apenas uno
  /// de una sesión anterior) y recién después el snapshot real del
  /// servidor con la lista completa — el efecto es ver aparecer un negocio
  /// y "al ratito" el resto. La lista de negocios no necesita vivir
  /// actualizada en tiempo real mientras la persona la mira (no es un chat),
  /// así que no vale la pena pagar ese parpadeo por algo que no hace falta.
  ///
  /// Esta consulta estaba copiada en 2 pantallas (adoptante_feed_screen.dart
  /// y aliados_screen.dart) — una se arregló primero, y la otra se quedó
  /// con la versión en vivo hasta que Eliza encontró el mismo síntoma ahí
  /// también. Que sea UN método achica ese riesgo a "un lugar para revisar",
  /// no "acordarse de buscar todas las copias" cada vez.
  ///
  /// Filtra por ROL y no por `aliadoNombre`, aunque el nombre sea lo que de
  /// verdad interesa. El motivo es de seguridad, no de datos: `usuarios` ya
  /// no se puede listar entero (ver firestore.rules, P0-2), y Firestore
  /// solo deja pasar un listado si puede DEMOSTRAR desde los filtros de la
  /// consulta que todo lo que devolvería cumple la regla. Esa demostración
  /// la sabe hacer con igualdad y con `array-contains`, no con rangos: la
  /// versión anterior (`isGreaterThan: ''`) daba permission-denied contra
  /// la regla nueva, probado en el emulador.
  ///
  /// Como el rol lo tiene también quien se registró de aliado pero nunca
  /// completó el nombre de su negocio, el filtro por nombre se hace acá
  /// abajo. Es el mismo criterio de antes, movido de lugar.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> aliados() async {
    final snap = await _db
        .collection('usuarios')
        .where('roles', arrayContains: 'aliado')
        .get();
    return snap.docs
        .where((d) => (d.data()['aliadoNombre'] as String?)?.isNotEmpty == true)
        .toList();
  }

  /// Completa las coordenadas del perfil a partir de su ciudad ya guardada.
  ///
  /// Existe para reparar perfiles de albergue creados antes de que guardar
  /// la ciudad exigiera geocodificarla: tienen `ciudad` pero no
  /// `latitud`/`longitud`, y como los animales de un albergue copian esas
  /// coordenadas del perfil (no del GPS, porque se publican desde el
  /// albergue), NINGUNO de sus animales podía mostrar distancia. Hallazgo
  /// real de Eliza: "todos los cargados desde albergues no muestran la
  /// distancia".
  ///
  /// Se escribe con merge y solo los campos de la ubicación: es una
  /// reparación de fondo, nunca debe pisar nada más de lo que la persona
  /// tenga guardado.
  ///
  /// [paisCodigo] va JUNTO con las coordenadas, no aparte: los tres datos
  /// (ciudad, coordenadas, país) describen un solo lugar y tienen que
  /// viajar juntos — es el invariante que cuida confirmar_ciudad_resuelta.
  /// dart, y romperlo fue el bug de "cordoba verduras 🇪🇸".
  ///
  /// Antes esta función recibía y escribía SOLO las coordenadas, aunque
  /// quien la llama ya tenía el país en la mano (lo acababa de resolver en
  /// la misma operación). El resultado era una reparación a medias: el
  /// perfil quedaba con ciudad + coordenadas pero sin país, así que todos
  /// los animales que ese albergue publicara después salían sin bandera —
  /// hasta que alguien volviera a guardar el perfil a mano.
  ///
  /// Se omite si viene vacío en vez de escribir `''`: un país vacío es
  /// justamente la señal que usa el perfil para saber que le falta ese
  /// dato y volver a resolverlo.
  Future<void> completarCoordenadas({
    required String uid,
    required double latitud,
    required double longitud,
    String paisCodigo = '',
  }) => _db.collection('usuarios').doc(uid).set({
    'latitud': latitud,
    'longitud': longitud,
    if (paisCodigo.isNotEmpty) 'paisCodigo': paisCodigo,
  }, SetOptions(merge: true));

  /// La ubicación del perfil de un albergue, lista para que sus animales
  /// la hereden: ciudad, coordenadas y país.
  ///
  /// Incluye la RED DE SEGURIDAD para los perfiles viejos: si tienen ciudad
  /// pero no coordenadas (se crearon antes de que guardar la ciudad exigiera
  /// geocodificarla), acá se resuelven una vez y se guardan de vuelta en el
  /// perfil, así el arreglo es permanente y nadie tiene que ir a editar su
  /// perfil a mano.
  ///
  /// Existe compartida porque esa red de seguridad estaba SOLO en el alta
  /// individual (`subir_rescate_screen.dart`). La pantalla de publicar en
  /// LOTE leía los mismos campos pero sin repararlos, así que el mismo
  /// albergue, con el mismo perfil, terminaba con animales distintos según
  /// por dónde los publicara: los de a uno reparaban el perfil y salían con
  /// distancia y bandera, los del lote salían sin nada — y como el lote no
  /// reparaba, seguían saliendo así siempre.
  ///
  /// Silenciosa a propósito: si el geocodificador falla (sin señal, o una
  /// ciudad vieja que ya no resuelve) devuelve lo que haya sin coordenadas
  /// en vez de tirar. Publicar nunca debe trabarse por un dato que es un
  /// extra.
  Future<
    ({String ciudad, double? latitud, double? longitud, String paisCodigo})
  >
  ubicacionDeAlbergue({
    required String uid,
    required Future<List<CandidatoUbicacion>?> Function(String) geocodificar,
  }) async {
    final data = (await _db.collection('usuarios').doc(uid).get()).data();
    final ciudad = (data?['ciudad'] as String?) ?? '';
    var lat = (data?['latitud'] as num?)?.toDouble();
    var lng = (data?['longitud'] as num?)?.toDouble();
    var pais = (data?['paisCodigo'] as String?) ?? '';

    if (lat == null && ciudad.isNotEmpty) {
      try {
        // Se queda con el primer candidato, sin diálogo: acá no hay a
        // quién preguntarle cuál es el correcto (esto corre solo, al abrir
        // la pantalla de publicar).
        final candidatos = await geocodificar(ciudad);
        if (candidatos != null && candidatos.isNotEmpty) {
          final resuelta = candidatos.first;
          lat = resuelta.lat;
          lng = resuelta.lng;
          if (resuelta.paisCodigo.isNotEmpty) pais = resuelta.paisCodigo;
          await completarCoordenadas(
            uid: uid,
            latitud: resuelta.lat,
            longitud: resuelta.lng,
            paisCodigo: resuelta.paisCodigo,
          );
        }
      } catch (_) {
        // Se devuelve lo que haya: sin coordenadas, ese animal queda sin
        // distancia, igual que antes de esta reparación.
      }
    }
    return (ciudad: ciudad, latitud: lat, longitud: lng, paisCodigo: pais);
  }

  /// La REGLA pura de [nombrePropioParaAnimal], sin tocar la red: dado el
  /// contenido de `usuarios/{uid}` que quien llama ya tenga en la mano,
  /// cuál es el nombre con el que corresponde firmar.
  ///
  /// Existe separada porque tres pantallas (publicar un animal, publicar en
  /// lote, y contactar a un negocio) YA leen ese documento para otra cosa
  /// —la ciudad, la foto— y tenían cada una su propia copia de esta regla
  /// escrita a mano: "si hay albergueNombre y no está vacío, usalo". Eran
  /// tres copias de la decisión que [nombrePropioParaAnimal] ya centraliza,
  /// y que existe porque equivocarse acá fue un bug real (un rechazo de un
  /// animal de rescatista firmado "La Perla pruebas", el albergue de la
  /// misma cuenta).
  ///
  /// Usarlas la versión con red habría agregado una SEGUNDA lectura del
  /// mismo documento en cada una. Con la regla separada, hay una sola
  /// fuente y ninguna lectura de más.
  static String nombrePropioDesde({
    required Map<String, dynamic>? datosUsuario,
    required String? creadoPor,
    required String? nombreDeLaCuenta,
  }) {
    final data = datosUsuario ?? const <String, dynamic>{};
    final albergueNombre = data['albergueNombre'] as String?;
    final nombre = data['nombre'] as String?;
    if (creadoPor == 'albergue' && (albergueNombre?.isNotEmpty ?? false)) {
      return albergueNombre!;
    }
    if (nombre?.isNotEmpty ?? false) return nombre!;
    if (albergueNombre?.isNotEmpty ?? false) return albergueNombre!;
    return (nombreDeLaCuenta?.isNotEmpty ?? false)
        ? nombreDeLaCuenta!
        : 'Rescatista';
  }

  /// El nombre propio (de quien está logueado) que corresponde firmarle a
  /// un aviso automático sobre UN animal puntual — "Eliza Casas" si ese
  /// animal es de rescatista, "La Perla" si es de albergue.
  ///
  /// Existe porque una cuenta puede tener las dos identidades a la vez
  /// (`nombre` Y `albergueNombre` en el mismo doc de `usuarios`), y dos
  /// copias de esta lógica (rechazar una solicitud, avisar que un animal
  /// falleció) preferían `albergueNombre` SIEMPRE que existiera, sin mirar
  /// de qué animal se trataba — un rescatista que también tiene rol de
  /// albergue veía sus propios mensajes automáticos de un animal SUYO
  /// (rescatista) firmados con el nombre del albergue. Hallazgo real de
  /// Eliza: rechazó una solicitud de "Gato coco loco" (suyo, como
  /// rescatista, "Eliza Casas") y el chat le llegó al adoptante firmado
  /// "La Perla pruebas" — el albergue de esa misma cuenta.
  ///
  /// [creadoPor] es del ANIMAL en cuestión ('albergue' o cualquier otra
  /// cosa se trata como rescatista), no del rol activo en la pantalla que
  /// llama a esto — son cosas distintas, quien mira Aprobar/Rechazar puede
  /// tener el toggle de rol en cualquier lado.
  Future<String> nombrePropioParaAnimal({
    required String uid,
    required String? creadoPor,
  }) async {
    // `_auth.currentUser` recién se toca si de verdad hace falta (más
    // abajo) — evaluarlo siempre, aunque el camino feliz de Firestore
    // nunca lo necesite, rompía cualquier test que no pasara un auth
    // mockeado (FirebaseAuth.instance exige Firebase.initializeApp()).
    Map<String, dynamic>? datos;
    try {
      datos = (await _db.collection('usuarios').doc(uid).get()).data();
    } catch (_) {
      // datos queda null: se cae al mismo respaldo que "no había ningún
      // nombre cargado".
    }
    // `nombreDeLaCuenta: null` primero, y recién se mira `_auth` si el
    // resultado quedó en el respaldo — mantiene la evaluación perezosa que
    // ya tenía esta función (ver el comentario de arriba): tocar
    // `_auth.currentUser` en el camino feliz rompe cualquier test que no
    // pase un auth mockeado, porque FirebaseAuth.instance exige un
    // Firebase.initializeApp() que `flutter test` no corre.
    final resuelto = nombrePropioDesde(
      datosUsuario: datos,
      creadoPor: creadoPor,
      nombreDeLaCuenta: null,
    );
    if (resuelto != 'Rescatista') return resuelto;
    return _auth.currentUser?.displayName ?? 'Rescatista';
  }

  Future<void> actualizarRoles(String uid, List<String> roles) {
    if (!roles.every(rolesValidos.contains)) {
      throw ArgumentError('rol inválido en $roles');
    }
    // Un permission-denied acá casi siempre es un token vencido, no falta
    // de permiso real (ver conReintentoSiTokenVencido en
    // firestore_resiliencia.dart) — mismo patrón que
    // RescatesRepository.eliminar(). El bug real: justo después de un
    // borrado masivo de cuentas de prueba, una cuenta que recién inicia
    // sesión puede traer un token viejo, y antes esto se mostraba como
    // "revisá tu conexión" dejando a la persona trabada sin poder elegir rol.
    return conReintentoSiTokenVencido(
      () => _auth,
      () => _db.collection('usuarios').doc(uid).update({'roles': roles}),
    );
  }

  /// Crea el perfil inicial de la cuenta (onboarding). `SetOptions(merge: true)`
  /// a propósito: si el doc ya existía — por ejemplo porque la pantalla de
  /// selección de rol se mostró por un falso "no existe" de la caché — NO
  /// pisa campos que no son suyos (fcmToken, fotoBase64, albergueNombre,
  /// perfilAdopcion...). Antes esto era un `set()` sin merge directo en la
  /// pantalla y borraba el perfil entero de un usuario existente.
  Future<void> crearPerfil({
    required String uid,
    required String nombre,
    String? email,
    String? foto,
    required List<String> roles,
    String ciudad = '',
  }) {
    if (!roles.every(rolesValidos.contains)) {
      throw ArgumentError('rol inválido en $roles');
    }
    return conReintentoSiTokenVencido(
      () => _auth,
      () => _db.collection('usuarios').doc(uid).set({
        'nombre': nombre,
        'email': email,
        'foto': foto,
        'roles': roles,
        'ciudad': ciudad,
        'creadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
    );
  }

  /// Asegura que el doc usuarios/{uid} EXISTA apenas la cuenta inicia
  /// sesión, con sus datos básicos pero SIN roles — se llama desde el flujo
  /// de login (auth_helper.dart), antes de que la persona elija rol.
  ///
  /// Por qué existe: AuthWrapper (main.dart) solo puede mandar a una cuenta
  /// al onboarding cuando el SERVIDOR le confirma "este perfil no existe" —
  /// confiar en la caché mandaría a usuarios existentes a pisarse el perfil.
  /// Pero esa confirmación depende de que el canal de escucha de Firestore
  /// esté sano justo en ese momento, y tras un cambio de cuenta puede
  /// quedar mudo un rato — el bug real: una cuenta nueva (sin perfil) se
  /// quedaba en el spinner de arranque para siempre, mientras las cuentas
  /// CON perfil entraban al toque porque a ellas la caché les alcanza. Toda
  /// persona nueva pasa por ese camino frágil en su primer ingreso.
  ///
  /// Con este write el camino frágil desaparece: la escritura queda en la
  /// caché local al instante (ni siquiera necesita señal), el stream de
  /// AuthWrapper emite "existe" de inmediato, y el guard de roles vacíos lo
  /// manda a elegir rol sin esperar ninguna confirmación del servidor.
  ///
  /// merge: true y sin tocar `roles`, a propósito — sobre una cuenta
  /// existente esto solo refresca nombre/email/foto y no pisa nada más.
  Future<void> asegurarPerfilBase({
    required String uid,
    String? nombre,
    String? email,
    String? foto,
  }) {
    return _db.collection('usuarios').doc(uid).set({
      if (nombre != null && nombre.isNotEmpty) 'nombre': nombre,
      if (email != null && email.isNotEmpty) 'email': email,
      if (foto != null && foto.isNotEmpty) 'foto': foto,
    }, SetOptions(merge: true));
  }
}
