import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
// conReintento vive en data/firestore_resiliencia.dart por su origen (fallas
// transitorias de Firestore), pero la función en sí es genérica: "reintentá
// UNA vez tras una espera corta". Se reusa acá a propósito en vez de copiar
// la política — que haya UNA sola definición de "cuánto se reintenta" es
// justamente el punto de este archivo.
import '../data/firestore_resiliencia.dart' show conReintento;

/// Un lugar candidato para un texto escrito a mano — `desdeTexto()` puede
/// devolver más de uno cuando el texto es ambiguo, ver el comentario ahí.
typedef CandidatoUbicacion = ({
  double lat,
  double lng,
  String paisCodigo,
  String ciudadResuelta,
  String regionResuelta,
});

/// Localidad/provincia ya normalizadas desde la respuesta de Nominatim —
/// reemplaza al `Placemark` de `package:geocoding` (que ya no se usa). Los
/// mismos 2 campos que [UbicacionService.ciudadDe] necesita.
typedef DireccionResuelta = ({String locality, String administrativeArea});

/// Por qué no se pudo obtener la ubicación. Cada motivo tiene una acción
/// distinta del lado de la UI (abrir los ajustes del sistema vs. los de la
/// app vs. no decir nada), así que se distinguen en vez de devolver un
/// único `null` — antes cada pantalla re-derivaba esta distinción por su
/// cuenta, y la mitad se la salteaba.
enum FalloUbicacion {
  /// El servicio de ubicación del SISTEMA está apagado (no es el permiso de
  /// la app). Ofrecer `Geolocator.openLocationSettings()`.
  servicioApagado,

  /// La persona dijo que no ahora. Se le puede volver a preguntar más
  /// adelante, así que normalmente no se muestra nada.
  permisoDenegado,

  /// Bloqueado para siempre desde los ajustes del teléfono
  /// (`deniedForever`). Ofrecer `Geolocator.openAppSettings()`.
  permisoBloqueado,

  /// El GPS no contestó a tiempo, o falló. Ya se reintentó una vez.
  sinRespuesta,
}

/// Qué hacer con la última posición conocida (la que el sistema ya tiene
/// cacheada de cualquier app, sin encender el GPS). Los 3 modos salieron de
/// los 3 usos reales que había en las pantallas, y son decisiones distintas
/// de verdad, no copias divergidas:
enum UsoUltimaConocida {
  /// Ni preguntarla. Quien publica un rescate quiere dónde está el animal
  /// AHORA, no una posición cacheada de otra ciudad.
  ninguno,

  /// Avisar con ella apenas se tenga (ver `onAproximada`) y seguir pidiendo
  /// la actual igual, para refinar. Es lo que hace el feed: muestra algo al
  /// instante y corrige a los segundos.
  comoAnticipo,

  /// Si existe, quedarse con ella y NO encender el GPS. Alcanza de sobra
  /// para un pin a nivel ciudad, y evita el gasto de batería y la espera de
  /// un pedido real cada vez que se abre la pantalla.
  siAlcanza,
}

/// Lo que devolvió un pedido de ubicación. Si [ok] es true, [posicion] no es
/// null; [ciudad] y [paisCodigo] pueden venir vacíos igual (hubo
/// coordenadas, pero el geocoding inverso no las pudo traducir a un nombre
/// — es una falla distinta y NO invalida las coordenadas).
class ResultadoUbicacion {
  const ResultadoUbicacion.ok({
    required this.posicion,
    this.ciudad = '',
    this.paisCodigo = '',
  }) : fallo = null;

  const ResultadoUbicacion.fallo(this.fallo)
    : posicion = null,
      ciudad = '',
      paisCodigo = '';

  final Position? posicion;
  final String ciudad;
  final String paisCodigo;
  final FalloUbicacion? fallo;

  bool get ok => fallo == null;

  /// Hubo coordenadas, pero el geocoding inverso no las supo traducir a un
  /// nombre de ciudad.
  ///
  /// Vale la pena tener nombre propio porque este caso se resolvía de tres
  /// formas distintas en las tres pantallas que piden ubicación, y una de
  /// las tres estaba mal de una manera que no se ve en pantalla:
  /// editar_rescate se quedaba con el texto de ciudad VIEJO (un lugar real,
  /// distinto), movía las coordenadas al lugar nuevo, y dejaba el país
  /// vacío. Tres campos describiendo tres lugares, con el tilde en verde
  /// porque solo miraba que hubiera latitud.
  ///
  /// La regla, ahora una sola: ciudad, coordenadas y país salen del mismo
  /// punto o no se toca ninguno. Sin nombre no hay nada que mostrarle a
  /// quien lo lea, y unas coordenadas que contradicen el texto son peores
  /// que no tener coordenadas.
  bool get sinNombre => ok && ciudad.isEmpty;
}

/// El aviso de [ResultadoUbicacion.sinNombre]. Es un fallo distinto de "no
/// pude ubicarte" y por eso tiene su propio texto: el GPS anduvo, lo que
/// no se pudo fue ponerle nombre, y la salida es escribirla a mano.
const avisoCiudadSinNombre =
    'No pudimos identificar tu ciudad. Podés escribirla a mano.';

/// Única puerta de entrada a GPS + geocoding de toda la app.
///
/// **Por qué existe:** esta misma secuencia (chequear servicio → pedir
/// permiso → obtener posición → traducirla a nombre de ciudad) estaba
/// copiada a mano en SIETE lugares — home_screen, perfil_adoptante_screen,
/// adoptante_feed_screen, subir_rescate_screen, editar_rescate_screen,
/// seleccion_rol_screen y CampoCiudad (widgets/campo_ciudad.dart). Las copias fueron
/// divergiendo, y cada bug de ubicación aparecía tantas veces como copias
/// hubiera sin arreglar. Casos reales, todos del mismo día:
///
/// - Sin chequear `isLocationServiceEnabled()` antes de pedir la posición,
///   Android abre su diálogo "Precisión de la ubicación" — y como las
///   pantallas con `didChangeAppLifecycleState` reintentan al volver a
///   primer plano, cerrar ese diálogo disparaba otro, sin fin ("presiono
///   varias veces no, gracias y ahí me deja"). Faltaba en 3 copias.
/// - Un solo tropiezo del GPS dejaba el pin vacío toda la visita, porque
///   solo el geocoding se reintentaba, no la posición. Faltaba en 2 copias.
/// - `seleccion_rol_screen` (¡el registro!) seguía sin el chequeo de
///   servicio Y sin `timeLimit`: el pedido de GPS quedaba corriendo de
///   fondo aunque el llamador ya se hubiera rendido.
///
/// **Este servicio nunca hace UI a propósito.** Devuelve [ResultadoUbicacion]
/// y cada pantalla decide qué mostrar, porque esa parte sí difiere de
/// verdad: publicar un rescate muestra un SnackBar con "Abrir Ajustes",
/// mientras que el pin de ciudad del perfil simplemente no se dibuja. Meter
/// el SnackBar acá adentro habría forzado un `BuildContext` en el servicio
/// y con él toda la familia de bugs de "aviso pegado sobre otra pantalla".
///
/// **El geocoding (texto ↔ coordenadas) habla con Nominatim (OpenStreetMap),
/// no con el geocodificador que trae Android.** El de Android devuelve
/// resultados pobres o directamente equivocados para textos en
/// Latinoamérica bastante seguido — el caso real que lo cambió: "medellin
/// antioquia" (con provincia y todo) resolvía SIEMPRE a "Los Olivos, un
/// barrio real de Medellín, sin que la ciudad de verdad apareciera nunca
/// entre los candidatos, ni agregando más texto. No era un bug de esta
/// app (la lista de candidatos funcionaba bien) sino de la fuente de datos
/// por debajo. Nominatim es gratis, no pide clave ni tarjeta, y tiene mejor
/// cobertura de la región — a cambio, pide como máximo 1 pedido por
/// segundo y un User-Agent que identifique la app (ver `_headers`), reglas
/// que este archivo ya respeta por diseño: cada operación pública hace UN
/// solo pedido HTTP (antes hacían falta hasta 6 para una sola búsqueda:
/// una por el texto y una más por cada candidato para resolver su nombre —
/// Nominatim devuelve el nombre resuelto en la MISMA respuesta de la
/// búsqueda, `addressdetails=1`, así que ese viaje de más ya no hace
/// falta).
class UbicacionService {
  /// El pedido de permiso que está en curso ahora mismo, si hay alguno.
  ///
  /// **Android admite UN solo pedido de permiso a la vez**: si llega un
  /// segundo mientras el primero sigue abierto, falla en el acto. Y varias
  /// pantallas de esta app piden ubicación al mismo tiempo al arrancar —
  /// Inicio y el feed de Adoptar se montan juntos (viven los dos en el
  /// IndexedStack de home_screen.dart, ver el comentario ahí), así que en
  /// el primerísimo arranque tras instalar, que es la única vez que el
  /// permiso todavía no está dado, las dos pedían a la vez y una perdía.
  ///
  /// Esa perdedora quedaba sin ubicación, y como el reintento al volver a
  /// primer plano estaba restringido, el pin no aparecía hasta reconstruir
  /// la pantalla. Hallazgo real de Eliza estrenando el APK53: "para el
  /// rescatista no muestra el pin... me voy al home del teléfono, entro de
  /// nuevo y ahí sí".
  ///
  /// Con esto, la segunda pantalla no lanza un pedido nuevo: se cuelga del
  /// mismo que ya está abierto y las dos reciben la misma respuesta.
  static Future<LocationPermission>? _permisoEnCurso;

  static Future<LocationPermission> _pedirPermisoUnaSolaVez() async {
    final yaEnCurso = _permisoEnCurso;
    if (yaEnCurso != null) return yaEnCurso;
    final pedido = Geolocator.requestPermission();
    _permisoEnCurso = pedido;
    try {
      return await pedido;
    } finally {
      _permisoEnCurso = null;
    }
  }

  /// Cuánto se espera a que el sistema conteste si el servicio de ubicación
  /// está prendido. Corto a propósito: es una consulta local, si tarda más
  /// que esto algo anda mal y conviene seguir sin ubicación antes que
  /// trabar la pantalla.
  static const _limiteChequeoServicio = Duration(seconds: 3);

  /// [conCiudad]: además de las coordenadas, traduce a nombre de ciudad y
  /// código de país (una llamada de red aparte, con su propio reintento).
  ///
  /// [precision]: `low` alcanza para un pin de ciudad o para ordenar por
  /// distancia, y prende menos el GPS; `high` para publicar dónde está un
  /// animal, que sí necesita exactitud.
  ///
  /// [ultimaConocida]: ver [UsoUltimaConocida]. Con `comoAnticipo`, además,
  /// [onAproximada] se llama apenas se tiene esa primera posición, antes de
  /// que termine el pedido real.
  ///
  /// [pedirPermisoSiFalta]: si el permiso está en `denied`, ¿se le puede
  /// abrir el diálogo del sistema para pedirlo? En `false` el servicio solo
  /// MIRA el permiso que ya hay y se rinde si falta, sin abrir nada.
  ///
  /// Esa distinción es la que hace seguro reintentar al volver a primer
  /// plano: pedir permiso abre un diálogo que manda la app a segundo plano
  /// y la devuelve, y ese 'resumed' dispararía otro pedido, sin fin (el
  /// bucle que en el Samsung Z Flip 6 se ve como la barra de estado
  /// parpadeando hasta que el sistema mata la app). Un reintento con
  /// `pedirPermisoSiFalta: false` no puede abrir ningún diálogo, así que
  /// **por construcción** no puede entrar en ese bucle — y sí recupera
  /// cualquier caso donde la situación cambió de verdad mientras la app
  /// estaba en segundo plano (prendieron el GPS, dieron el permiso desde
  /// Ajustes, o el primer intento se cruzó con otro).
  static Future<ResultadoUbicacion> actual({
    bool conCiudad = false,
    LocationAccuracy precision = LocationAccuracy.low,
    Duration limite = const Duration(seconds: 12),
    UsoUltimaConocida ultimaConocida = UsoUltimaConocida.ninguno,
    void Function(Position posicion)? onAproximada,
    bool pedirPermisoSiFalta = true,
  }) async {
    // Paso 1 — servicio del sistema. SIEMPRE primero: pedir la posición con
    // el servicio apagado es lo que dispara el diálogo nativo de Android
    // (ver el comentario de la clase). Ninguna pantalla puede saltearse
    // este paso, que era justamente el problema de tenerlo copiado.
    final bool servicioActivo;
    try {
      servicioActivo = await Geolocator.isLocationServiceEnabled().timeout(
        _limiteChequeoServicio,
        onTimeout: () => false,
      );
    } catch (_) {
      return const ResultadoUbicacion.fallo(FalloUbicacion.servicioApagado);
    }
    if (!servicioActivo) {
      return const ResultadoUbicacion.fallo(FalloUbicacion.servicioApagado);
    }

    // Paso 2 — permiso de la app. `denied` y `deniedForever` se devuelven
    // por separado: el primero se puede volver a pedir, el segundo solo se
    // arregla desde los ajustes del teléfono.
    LocationPermission permiso;
    try {
      permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied && pedirPermisoSiFalta) {
        permiso = await _pedirPermisoUnaSolaVez();
      }
    } catch (_) {
      return const ResultadoUbicacion.fallo(FalloUbicacion.sinRespuesta);
    }
    if (permiso == LocationPermission.deniedForever) {
      return const ResultadoUbicacion.fallo(FalloUbicacion.permisoBloqueado);
    }
    if (permiso == LocationPermission.denied) {
      return const ResultadoUbicacion.fallo(FalloUbicacion.permisoDenegado);
    }

    // Paso 3 — posición.
    Position? aproximada;
    if (ultimaConocida != UsoUltimaConocida.ninguno) {
      try {
        aproximada = _valida(await Geolocator.getLastKnownPosition());
        if (aproximada != null &&
            ultimaConocida == UsoUltimaConocida.comoAnticipo) {
          onAproximada?.call(aproximada);
        }
      } catch (_) {
        // La última conocida es un atajo, no un requisito: si falla se
        // sigue con el pedido real de abajo.
      }
      // `siAlcanza`: no se enciende el GPS si ya hay algo servible.
      if (aproximada != null && ultimaConocida == UsoUltimaConocida.siAlcanza) {
        return _conCiudadSiHaceFalta(aproximada, conCiudad);
      }
    }

    Position? posicion;
    try {
      // Reintenta UNA vez: un solo tropiezo del GPS (señal débil un
      // instante, recién saliendo de un edificio) dejaba el pin vacío la
      // visita entera. Antes solo el geocoding de más abajo se reintentaba,
      // aunque el GPS es el paso que más falla de los dos.
      posicion = _valida(
        await conReintento<Position>(
          () => Geolocator.getCurrentPosition(
            locationSettings: LocationSettings(
              accuracy: precision,
              timeLimit: limite,
            ),
          ),
        ),
      );
    } catch (_) {
      posicion = null;
    }
    // Sin posición actual usable (excepción, O una lectura real pero
    // "Null Island") y ya había una aproximada: sirve, es peor no mostrar
    // nada que mostrar una posición de hace un rato. `??=` a propósito,
    // no un `if` adentro del catch de arriba — así cubre las DOS formas
    // de quedarse sin posición actual con el mismo camino, en vez de que
    // el caso (0, 0) se saltee el respaldo por no haber tirado excepción.
    posicion ??= aproximada;
    if (posicion == null) {
      return const ResultadoUbicacion.fallo(FalloUbicacion.sinRespuesta);
    }

    return _conCiudadSiHaceFalta(posicion, conCiudad);
  }

  /// (0, 0) — "Null Island" — no es una coordenada real para un animal
  /// rescatado en ningún lugar donde se usa esta app: es lo que Android
  /// devuelve cuando el GPS todavía no tiene una lectura de verdad (o el
  /// emulador sin una ubicación configurada, pero también pasa en
  /// dispositivos reales con un tropiezo del chip GPS). Aceptarla como
  /// posición válida guarda coordenadas que después no se pueden
  /// geocodificar (no hay ninguna ciudad en medio del océano) — el
  /// nombre de la ciudad queda vacío, pero las coordenadas SÍ se
  /// guardan, y el feed termina mostrando una distancia absurda sin
  /// ningún nombre de lugar al lado. Se trata igual que "no hubo
  /// posición": mejor ninguna ubicación que una a miles de km de la
  /// real. Hallazgo real de Eliza: un animal con "Ubicación" vacía en
  /// el formulario de editar mostraba "Se encuentra a 8875.1 km de ti"
  /// en el feed del adoptante.
  static Position? _valida(Position? p) =>
      (p != null && (p.latitude != 0 || p.longitude != 0)) ? p : null;

  /// Paso 4 — nombre de ciudad + país, si el llamador los pidió. Una falla
  /// acá NO invalida las coordenadas: se devuelve ok igual, con ciudad
  /// vacía, y el llamador decide qué hacer (el pin no se dibuja, pero la
  /// distancia sí se puede seguir calculando).
  static Future<ResultadoUbicacion> _conCiudadSiHaceFalta(
    Position coords,
    bool conCiudad,
  ) async {
    if (!conCiudad) return ResultadoUbicacion.ok(posicion: coords);
    try {
      // Reintenta UNA vez, igual que el GPS: el geocoding inverso es una
      // llamada de red aparte, con su propio punto de falla (típico al
      // salir de modo avión, con el GPS andando perfecto).
      final direccion = await conReintento<Map<String, dynamic>?>(
        () => _reverseGeocode(coords.latitude, coords.longitude),
      );
      if (direccion == null) return ResultadoUbicacion.ok(posicion: coords);
      return ResultadoUbicacion.ok(
        posicion: coords,
        ciudad: ciudadDe(_direccionDe(direccion)),
        paisCodigo: _paisCodigoDe(direccion),
      );
    } catch (_) {
      return ResultadoUbicacion.ok(posicion: coords);
    }
  }

  /// El camino inverso de [actual]: un lugar ESCRITO A MANO resuelto a
  /// coordenadas + código de país. Es la única fuente de "¿esto es un lugar
  /// real?" de toda la app — lo usan los perfiles de albergue y aliado al
  /// guardar su ciudad, y publicar/editar un rescate cuando la ubicación se
  /// tocó a mano en vez de detectarse por GPS.
  ///
  /// **La distinción entre `null` y excepción es load-bearing, no un
  /// detalle:** `null` significa que el servicio contestó y NO encontró
  /// ningún lugar así (escribió "verduras"); cualquier excepción (sin
  /// señal, servicio caído, el timeout de acá) se propaga tal cual para que
  /// el llamador la trate como "no se pudo verificar todavía". Aplanar las
  /// dos cosas hacía que un problema de conexión bloqueara guardar una
  /// ciudad perfectamente válida.
  ///
  /// El país y el NOMBRE resuelto son best-effort aparte: si esa segunda
  /// llamada falla, las coordenadas —que es lo que de verdad importa para
  /// la distancia— siguen siendo válidas y se devuelven igual, con
  /// `paisCodigo`/`ciudadResuelta` vacíos.
  ///
  /// `ciudadResuelta` existe para un problema DISTINTO del que resuelve el
  /// `null` de arriba: un texto mal escrito que por casualidad coincide con
  /// OTRO lugar real en cualquier parte del mundo no da `null` — el
  /// servicio contesta con total confianza, coordenadas incluidas, solo que
  /// no es el lugar que la persona quiso escribir. No hay forma de detectar
  /// eso programáticamente (no existe una lista de "todas las ciudades del
  /// mundo, bien escritas" contra la cual comparar) — hallazgo real de
  /// Eliza escribiendo "Nedellin" y quedando guardado a 9077km de Medellín.
  /// La única defensa realista es mostrarle a la persona QUÉ se resolvió
  /// (nombre + país) antes de guardar, para que lo confirme o lo corrija
  /// ella misma — por eso este dato viaja junto con las coordenadas en vez
  /// de quedar enterrado en el placemark.
  ///
  /// `regionResuelta` (provincia/estado/departamento) cubre un segundo
  /// problema que "nombre + país" solo no alcanza a mostrar: dos ciudades
  /// con el MISMO nombre en el MISMO país (pasa seguido — "San José",
  /// "Santa Rosa", "La Unión" se repiten en decenas de departamentos
  /// distintos en más de un país de la región). Ahí el nombre resuelto
  /// coincide exactamente con lo esperado y el diálogo de confirmación no
  /// alcanzaría a delatar que el geocoder eligió el lugar equivocado —
  /// pregunta real de Eliza. Con la provincia/estado a la vista, dos
  /// ciudades homónimas en regiones distintas SÍ se distinguen.
  ///
  /// Devuelve una LISTA, no un único candidato: un texto ambiguo puede
  /// resolver a varios lugares reales distintos, y mostrar solo el primero
  /// dejaba a la persona sin forma de llegar al que sí buscaba si ese
  /// primero estaba mal — escribir el mismo texto de nuevo siempre daba el
  /// mismo primero. Hasta 5 candidatos, deduplicados por nombre+país más
  /// abajo.
  static Future<List<CandidatoUbicacion>?> desdeTexto(
    String lugar, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': lugar,
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': '5',
      'accept-language': 'es',
    });
    List<dynamic> resultados;
    // Reintenta UNA vez, mismo criterio que el resto de este archivo: un
    // tropiezo transitorio de red no debería obligar a retipear la ciudad
    // desde cero.
    resultados = await conReintento<List<dynamic>>(
      () => _pedirLista(uri, timeout),
    );
    if (resultados.isEmpty) return null;

    final candidatos = <CandidatoUbicacion>[];
    for (final item in resultados) {
      if (candidatos.length >= 5) break;
      final mapa = item as Map<String, dynamic>;
      final lat = double.tryParse(mapa['lat'] as String? ?? '');
      final lng = double.tryParse(mapa['lon'] as String? ?? '');
      if (lat == null || lng == null) continue;
      final address = mapa['address'] as Map<String, dynamic>? ?? const {};
      final direccion = _direccionDe(address);
      final ciudadResuelta = ciudadDe(direccion);
      // Un candidato sin nombre resuelto no sirve para elegir en la lista.
      if (ciudadResuelta.isEmpty) continue;
      final paisCodigo = _paisCodigoDe(address);
      // Solo tiene sentido como dato ADICIONAL cuando el nombre vino de una
      // localidad de verdad — si ciudadDe() ya cayó a la provincia (zona
      // rural, sin ciudad propiamente dicha), mostrarla nuevamente acá
      // repetiría el mismo texto dos veces.
      final regionResuelta = direccion.locality.isNotEmpty
          ? direccion.administrativeArea
          : '';
      final yaEsta = candidatos.any(
        (c) => c.ciudadResuelta == ciudadResuelta && c.paisCodigo == paisCodigo,
      );
      if (yaEsta) continue;
      candidatos.add((
        lat: lat,
        lng: lng,
        paisCodigo: paisCodigo,
        ciudadResuelta: ciudadResuelta,
        regionResuelta: regionResuelta,
      ));
    }
    return candidatos.isEmpty ? null : candidatos;
  }

  /// `Nominatim` (OpenStreetMap) pide como máximo 1 pedido por segundo y un
  /// User-Agent que identifique la app — no una clave ni una tarjeta, es
  /// gratis. https://operations.osmfoundation.org/policies/nominatim/
  static const _headers = {
    'User-Agent': 'SalvaPatitasApp/1.0 (+https://lunita486.github.io/Salva-Patitas/)',
  };

  /// El cliente HTTP real, salvo en los tests — `@visibleForTesting` porque
  /// es la única puerta para inyectar un `MockClient` sin cambiar la firma
  /// pública de ninguna función de esta clase (las 7 pantallas que la usan
  /// no se enteran del cambio).
  static http.Client httpClient = http.Client();

  static Future<List<dynamic>> _pedirLista(Uri uri, Duration timeout) async {
    final respuesta = await httpClient.get(uri, headers: _headers).timeout(timeout);
    if (respuesta.statusCode != 200) {
      throw FalloDeGeocoding('Nominatim respondió ${respuesta.statusCode}');
    }
    return jsonDecode(respuesta.body) as List<dynamic>;
  }

  /// Coordenadas → dirección. `null` si Nominatim no resolvió nada para ese
  /// punto (rarísimo, en medio del mar); cualquier excepción real se
  /// propaga tal cual, mismo criterio que [desdeTexto].
  static Future<Map<String, dynamic>?> _reverseGeocode(
    double lat,
    double lng, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'lat': '$lat',
      'lon': '$lng',
      'format': 'jsonv2',
      'addressdetails': '1',
      'accept-language': 'es',
    });
    final respuesta = await httpClient.get(uri, headers: _headers).timeout(timeout);
    if (respuesta.statusCode != 200) {
      throw FalloDeGeocoding('Nominatim respondió ${respuesta.statusCode}');
    }
    final cuerpo = jsonDecode(respuesta.body) as Map<String, dynamic>;
    final address = cuerpo['address'];
    if (address == null) return null;
    return address as Map<String, dynamic>;
  }

  /// Localidad de un `address` de Nominatim — no tiene un único campo
  /// "ciudad" como el geocodificador viejo (`locality`): según qué tan
  /// urbano sea el lugar, el dato viene en `city`, `town`, `village` o
  /// `municipality`. Se prueban en ese orden, el primero que aparezca.
  static DireccionResuelta _direccionDe(Map<String, dynamic> address) {
    final localidad =
        address['city'] as String? ??
        address['town'] as String? ??
        address['village'] as String? ??
        address['municipality'] as String? ??
        '';
    return (
      locality: localidad,
      administrativeArea: address['state'] as String? ?? '',
    );
  }

  static String _paisCodigoDe(Map<String, dynamic> address) =>
      (address['country_code'] as String?)?.toUpperCase() ?? '';

  /// `locality` (la ciudad propiamente dicha) y, si viene vacía,
  /// `administrativeArea` (la provincia/estado) — pasa de verdad en zonas
  /// rurales y en algunos países donde el geocoder no devuelve localidad.
  /// Estaba escrito idéntico en las 7 copias.
  static String ciudadDe(DireccionResuelta marca) =>
      marca.locality.isNotEmpty ? marca.locality : marca.administrativeArea;
}

/// Falla real del servidor de geocoding (código de estado inesperado) — no
/// es lo mismo que "no encontró nada" (eso es una lista/objeto vacío, no
/// una excepción). Ver el comentario de [UbicacionService.desdeTexto].
class FalloDeGeocoding implements Exception {
  const FalloDeGeocoding(this.mensaje);
  final String mensaje;
  @override
  String toString() => mensaje;
}
