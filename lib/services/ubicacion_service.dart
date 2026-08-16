import 'dart:async';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
// conReintento vive en data/firestore_resiliencia.dart por su origen (fallas
// transitorias de Firestore), pero la función en sí es genérica: "reintentá
// UNA vez tras una espera corta". Se reusa acá a propósito en vez de copiar
// la política — que haya UNA sola definición de "cuánto se reintenta" es
// justamente el punto de este archivo.
import '../data/firestore_resiliencia.dart' show conReintento;

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
}

/// Única puerta de entrada a GPS + geocoding inverso de toda la app.
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
        aproximada = await Geolocator.getLastKnownPosition();
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
      posicion = await conReintento<Position>(
        () => Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: precision,
            timeLimit: limite,
          ),
        ),
      );
    } catch (_) {
      // Si ya había una aproximada, sirve: es peor no mostrar nada que
      // mostrar una posición de hace un rato.
      posicion = aproximada;
    }
    if (posicion == null) {
      return const ResultadoUbicacion.fallo(FalloUbicacion.sinRespuesta);
    }

    return _conCiudadSiHaceFalta(posicion, conCiudad);
  }

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
      final marcas = await conReintento<List<Placemark>>(
        () => placemarkFromCoordinates(coords.latitude, coords.longitude),
      );
      if (marcas.isEmpty) return ResultadoUbicacion.ok(posicion: coords);
      final marca = marcas.first;
      return ResultadoUbicacion.ok(
        posicion: coords,
        ciudad: ciudadDe(marca),
        paisCodigo: marca.isoCountryCode ?? '',
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
  static Future<
    ({
      double lat,
      double lng,
      String paisCodigo,
      String ciudadResuelta,
      String regionResuelta,
    })?
  >
  desdeTexto(
    String lugar, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    List<Location> resultados;
    try {
      resultados = await locationFromAddress(lugar).timeout(timeout);
    } on NoResultFoundException {
      return null;
    }
    if (resultados.isEmpty) return null;

    final lat = resultados.first.latitude;
    final lng = resultados.first.longitude;
    var paisCodigo = '';
    var ciudadResuelta = '';
    var regionResuelta = '';
    // Best-effort a propósito: lat/lng (lo que de verdad importa, ya
    // resuelto arriba) no depende de este reverse geocoding — es solo el
    // dato extra para el diálogo de confirmación. Si falla, se guarda
    // igual con los 3 campos de texto vacíos en vez de perder la
    // ubicación por un problema de un servicio secundario.
    try {
      final marcas = await placemarkFromCoordinates(lat, lng).timeout(timeout);
      if (marcas.isNotEmpty) {
        final marca = marcas.first;
        paisCodigo = marca.isoCountryCode ?? '';
        ciudadResuelta = ciudadDe(marca);
        // Solo tiene sentido como dato ADICIONAL cuando ciudadResuelta vino
        // de `locality` — si ciudadDe() ya cayó a administrativeArea (zona
        // rural, sin locality), mostrarlo de nuevo acá sería repetir el
        // mismo texto dos veces.
        if (marca.locality?.isNotEmpty == true) {
          regionResuelta = marca.administrativeArea ?? '';
        }
      }
    } catch (_) {}
    return (
      lat: lat,
      lng: lng,
      paisCodigo: paisCodigo,
      ciudadResuelta: ciudadResuelta,
      regionResuelta: regionResuelta,
    );
  }

  /// `locality` (la ciudad propiamente dicha) y, si viene vacía,
  /// `administrativeArea` (la provincia/estado) — pasa de verdad en zonas
  /// rurales y en algunos países donde el geocoder no devuelve localidad.
  /// Estaba escrito idéntico en las 7 copias.
  static String ciudadDe(Placemark marca) => marca.locality?.isNotEmpty == true
      ? marca.locality!
      : (marca.administrativeArea ?? '');
}
