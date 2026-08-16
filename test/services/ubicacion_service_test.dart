import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding_platform_interface/geocoding_platform_interface.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:salva_patitas/services/ubicacion_service.dart';

// Mismo patrón que test/theme_test.dart: se reemplaza el backend de
// plataforma de geolocator/geocoding por un fake, así se puede probar cada
// rama (GPS apagado, permiso bloqueado, tropiezo transitorio del GPS,
// geocoding caído) sin hardware ni red reales. Extienden la clase base (no
// la implementan) porque su constructor registra el token que
// PlatformInterface exige.
class _FakeGeolocator extends GeolocatorPlatform {
  _FakeGeolocator({this.posicion});

  /// Todos mutables y con default: cada test ajusta solo la rama que le
  /// interesa (`geo.servicioActivo = false`) sin repetir el resto.
  bool servicioActivo = true;
  LocationPermission permiso = LocationPermission.always;
  Position? posicion;
  Position? ultimaConocida;

  /// Cuántas veces seguidas falla `getCurrentPosition` antes de andar — para
  /// probar el reintento sin depender de un GPS real intermitente.
  int fallasSeguidasDeGps = 0;

  /// Simula que el sistema se cuelga al preguntarle si el servicio está
  /// prendido (el Future nunca completa).
  bool servicioNuncaContesta = false;

  /// Qué contesta el diálogo del sistema. Por defecto lo mismo que ya había
  /// (o sea, "dijo que no otra vez"); poniéndolo en whileInUse se simula que
  /// la persona concede el permiso en ese momento.
  LocationPermission? permisoTrasPedirlo;

  int vecesQuePidioPosicion = 0;
  int vecesQuePidioUltimaConocida = 0;

  /// Cuántas veces se abrió el diálogo del sistema. Es LA medida del bug del
  /// bucle (nunca debería abrirse en un reintento) y del arranque en frío
  /// (dos pantallas a la vez tienen que abrir uno solo).
  int vecesQuePidioPermiso = 0;

  @override
  Future<bool> isLocationServiceEnabled() => servicioNuncaContesta
      ? Completer<bool>().future
      : Future.value(servicioActivo);

  @override
  Future<LocationPermission> checkPermission() async => permiso;

  @override
  Future<LocationPermission> requestPermission() async {
    vecesQuePidioPermiso++;
    // Un pedido real tarda: sin esta espera los dos pedidos "simultáneos"
    // del test se resolverían uno después del otro y no probarían nada.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return permiso = permisoTrasPedirlo ?? permiso;
  }

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async {
    vecesQuePidioUltimaConocida++;
    return ultimaConocida;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    vecesQuePidioPosicion++;
    if (vecesQuePidioPosicion <= fallasSeguidasDeGps) {
      throw Exception('GPS sin señal (simulado)');
    }
    return posicion!;
  }
}

class _FakeGeocoding extends GeocodingPlatform {
  List<Placemark> marcas = const [];
  List<Location> ubicaciones = const [];
  bool falla = false;
  Object? errorAlBuscarDireccion;
  bool nuncaResponde = false;

  @override
  Future<List<Location>> locationFromAddress(String address) {
    if (nuncaResponde) return Completer<List<Location>>().future;
    if (errorAlBuscarDireccion != null) throw errorAlBuscarDireccion!;
    return Future.value(ubicaciones);
  }

  @override
  Future<List<Placemark>> placemarkFromCoordinates(
    double lat,
    double lng,
  ) async {
    if (falla) throw Exception('geocoding caído (simulado)');
    return marcas;
  }
}

Location _ubicacion(double lat, double lng) =>
    Location(latitude: lat, longitude: lng, timestamp: DateTime.now());

Position _posicion(double lat, double lng) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime.now(),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  late _FakeGeolocator geo;
  late _FakeGeocoding geocoding;

  setUp(() {
    geo = _FakeGeolocator(posicion: _posicion(-31.4, -64.2));
    geocoding = _FakeGeocoding();
    GeolocatorPlatform.instance = geo;
    GeocodingPlatform.instance = geocoding;
  });

  group('UbicacionService.actual() — permisos y servicio del sistema', () {
    test(
      'con el servicio de ubicación APAGADO no pide la posición ni una sola vez — '
      'pedirla es lo que dispara el diálogo nativo de Android "Precisión de la '
      'ubicación", y como las pantallas reintentan al volver a primer plano, '
      'cerrarlo disparaba otro sin fin (bug real de Eliza: "presiono varias veces '
      'no, gracias y ahí me deja")',
      () async {
        geo.servicioActivo = false;

        final r = await UbicacionService.actual();

        expect(r.ok, false);
        expect(r.fallo, FalloUbicacion.servicioApagado);
        expect(geo.vecesQuePidioPosicion, 0);
      },
    );

    test(
      'si el sistema NO contesta si el servicio está prendido, se rinde a los 3s '
      'en vez de dejar la pantalla esperando para siempre',
      () async {
        geo.servicioNuncaContesta = true;

        final r = await UbicacionService.actual();

        expect(r.fallo, FalloUbicacion.servicioApagado);
        expect(geo.vecesQuePidioPosicion, 0);
      },
    );

    test('permiso denegado (se puede volver a pedir) se distingue de permiso '
        'bloqueado para siempre — cada uno lleva a un ajuste distinto del teléfono, '
        'y la UI necesita saber cuál ofrecer', () async {
      geo.permiso = LocationPermission.denied;
      expect(
        (await UbicacionService.actual()).fallo,
        FalloUbicacion.permisoDenegado,
      );

      geo.permiso = LocationPermission.deniedForever;
      expect(
        (await UbicacionService.actual()).fallo,
        FalloUbicacion.permisoBloqueado,
      );

      expect(geo.vecesQuePidioPosicion, 0);
    });

    test(
      'con whileInUse alcanza — no hace falta el permiso "always"',
      () async {
        geo.permiso = LocationPermission.whileInUse;

        final r = await UbicacionService.actual();

        expect(r.ok, true);
        expect(r.posicion!.latitude, -31.4);
      },
    );
  });

  group('UbicacionService.actual() — tolerancia a fallas del GPS', () {
    test(
      'un tropiezo transitorio del GPS se reintenta UNA vez y sale bien — sin '
      'esto, una sola falla dejaba el pin vacío la visita entera (antes solo el '
      'geocoding se reintentaba, aunque el GPS es el que más falla)',
      () async {
        geo.fallasSeguidasDeGps = 1;

        final r = await UbicacionService.actual();

        expect(r.ok, true);
        expect(geo.vecesQuePidioPosicion, 2);
      },
    );

    test(
      'si el GPS falla las DOS veces devuelve sinRespuesta (no reintenta para '
      'siempre)',
      () async {
        geo.fallasSeguidasDeGps = 99;

        final r = await UbicacionService.actual();

        expect(r.ok, false);
        expect(r.fallo, FalloUbicacion.sinRespuesta);
        expect(geo.vecesQuePidioPosicion, 2);
      },
    );

    test('si el GPS falla del todo pero había una última posición conocida, se '
        'devuelve ESA en vez de nada — mostrar una ubicación de hace un rato es '
        'mejor que no mostrar ninguna', () async {
      geo.fallasSeguidasDeGps = 99;
      geo.ultimaConocida = _posicion(10, 20);

      final r = await UbicacionService.actual(
        ultimaConocida: UsoUltimaConocida.comoAnticipo,
      );

      expect(r.ok, true);
      expect(r.posicion!.latitude, 10);
    });
  });

  group('UbicacionService.actual() — los 3 usos de la última posición conocida', () {
    test(
      'ninguno (el default) ni la consulta — quien publica un rescate quiere '
      'dónde está el animal AHORA, no una posición cacheada de otra ciudad',
      () async {
        await UbicacionService.actual();

        expect(geo.vecesQuePidioUltimaConocida, 0);
        expect(geo.vecesQuePidioPosicion, 1);
      },
    );

    test(
      'comoAnticipo avisa primero con la aproximada y termina devolviendo la '
      'actual, más precisa — es lo que hace el feed: muestra algo al instante y '
      'corrige a los segundos',
      () async {
        geo.ultimaConocida = _posicion(10, 20);
        final avisadas = <Position>[];

        final r = await UbicacionService.actual(
          ultimaConocida: UsoUltimaConocida.comoAnticipo,
          onAproximada: avisadas.add,
        );

        expect(
          avisadas.single.latitude,
          10,
          reason: 'la aproximada llega primero',
        );
        expect(
          r.posicion!.latitude,
          -31.4,
          reason: 'el resultado final es la actual',
        );
        expect(geo.vecesQuePidioPosicion, 1, reason: 'sí refina con el GPS');
      },
    );

    test(
      'siAlcanza se queda con la cacheada y NO enciende el GPS — para un pin a '
      'nivel ciudad alcanza de sobra, y evita la espera y la batería de un '
      'pedido real en cada visita a la pantalla',
      () async {
        geo.ultimaConocida = _posicion(10, 20);

        final r = await UbicacionService.actual(
          ultimaConocida: UsoUltimaConocida.siAlcanza,
        );

        expect(r.posicion!.latitude, 10);
        expect(geo.vecesQuePidioPosicion, 0, reason: 'no se encendió el GPS');
      },
    );

    test(
      'siAlcanza SÍ enciende el GPS si no hay ninguna cacheada (primer arranque '
      'del teléfono, o app recién instalada)',
      () async {
        geo.ultimaConocida = null;

        final r = await UbicacionService.actual(
          ultimaConocida: UsoUltimaConocida.siAlcanza,
        );

        expect(r.posicion!.latitude, -31.4);
        expect(geo.vecesQuePidioPosicion, 1);
      },
    );

    test(
      'siAlcanza con conCiudad igual traduce la cacheada a nombre de ciudad — '
      'no se saltea el geocoding por haber usado el atajo',
      () async {
        geo.ultimaConocida = _posicion(10, 20);
        geocoding.marcas = [
          const Placemark(locality: 'Rosario', isoCountryCode: 'AR'),
        ];

        final r = await UbicacionService.actual(
          ultimaConocida: UsoUltimaConocida.siAlcanza,
          conCiudad: true,
        );

        expect(r.ciudad, 'Rosario');
        expect(r.paisCodigo, 'AR');
      },
    );
  });

  group('UbicacionService.actual() — nombre de ciudad (conCiudad)', () {
    test(
      'por defecto NO llama al geocoding: quien solo necesita coordenadas (el '
      'feed, para ordenar por distancia) no debería pagar una llamada de red de '
      'más',
      () async {
        geocoding.falla = true; // si lo llamara, este test explotaría

        final r = await UbicacionService.actual();

        expect(r.ok, true);
        expect(r.ciudad, '');
      },
    );

    test('conCiudad devuelve ciudad y código de país', () async {
      geocoding.marcas = [
        const Placemark(locality: 'Córdoba', isoCountryCode: 'AR'),
      ];

      final r = await UbicacionService.actual(conCiudad: true);

      expect(r.ciudad, 'Córdoba');
      expect(r.paisCodigo, 'AR');
    });

    test('si el geocoding falla, las COORDENADAS siguen siendo válidas — se '
        'devuelve ok con ciudad vacía, no un error: el pin no se dibuja pero la '
        'distancia sí se puede calcular', () async {
      geocoding.falla = true;

      final r = await UbicacionService.actual(conCiudad: true);

      expect(r.ok, true);
      expect(r.posicion!.latitude, -31.4);
      expect(r.ciudad, '');
    });

    test(
      'si el geocoding no encuentra ningún lugar, mismo criterio: ok con ciudad '
      'vacía',
      () async {
        geocoding.marcas = [];

        final r = await UbicacionService.actual(conCiudad: true);

        expect(r.ok, true);
        expect(r.ciudad, '');
      },
    );
  });

  group('UbicacionService.desdeTexto() — el camino inverso: lo que alguien '
      'escribió a mano resuelto a coordenadas. Única fuente de "¿esto es un '
      'lugar real?" de toda la app. Bug real que esto arregla: antes cada '
      'pantalla trataba "el servicio no encontró nada" (texto inválido, ej. '
      '"verduras") exactamente igual que "no hay señal" — algunas guardaban '
      'cualquier texto sin avisar, otra bloqueaba hasta un cambio de nombre '
      'sin relación solo porque no había señal para verificar la ciudad.', () {
    test(
      'devuelve coordenadas y país cuando el servicio encuentra el lugar',
      () async {
        geocoding.ubicaciones = [_ubicacion(6.25184, -75.56359)];
        geocoding.marcas = [
          const Placemark(
            locality: 'Medellín',
            administrativeArea: 'Antioquia',
            isoCountryCode: 'CO',
          ),
        ];

        final r = await UbicacionService.desdeTexto('Medellín');

        expect(r!.lat, 6.25184);
        expect(r.lng, -75.56359);
        expect(r.paisCodigo, 'CO');
        expect(r.ciudadResuelta, 'Medellín');
        expect(r.regionResuelta, 'Antioquia');
      },
    );

    test('dos ciudades con el MISMO nombre en el MISMO país: regionResuelta '
        'trae la provincia/estado, que es lo único que las distingue — el '
        'nombre solo (y hasta la bandera) sería idéntico para las dos, así '
        'que sin esto el diálogo de confirmación no alcanzaría a delatar que '
        'el geocoder eligió la ciudad equivocada. Pregunta real de Eliza: '
        '"qué pasa si dos rescatistas... están en ciudades que tienen el '
        'mismo nombre"', () async {
      geocoding.ubicaciones = [_ubicacion(9.9, -75.2)];
      geocoding.marcas = [
        const Placemark(
          locality: 'San José',
          administrativeArea: 'Córdoba',
          isoCountryCode: 'CO',
        ),
      ];

      final r = await UbicacionService.desdeTexto('San José');

      expect(r!.ciudadResuelta, 'San José');
      expect(r.regionResuelta, 'Córdoba');
      // Otra "San José" real, en OTRO departamento del mismo país, daría el
      // mismo ciudadResuelta pero una regionResuelta distinta — es esa
      // diferencia la que el diálogo puede mostrar.
    });

    test(
      'regionResuelta viene vacía cuando ciudadDe() ya tuvo que caer a '
      'administrativeArea (zona rural, sin locality) — mostrar la misma '
      'región dos veces en el diálogo de confirmación no aportaría nada',
      () async {
        geocoding.ubicaciones = [_ubicacion(1.0, 2.0)];
        geocoding.marcas = [
          const Placemark(
            locality: '',
            administrativeArea: 'Córdoba',
            isoCountryCode: 'AR',
          ),
        ];

        final r = await UbicacionService.desdeTexto('zona rural de Córdoba');

        expect(r!.ciudadResuelta, 'Córdoba'); // cayó a administrativeArea
        expect(r.regionResuelta, ''); // no se repite
      },
    );

    test('un texto mal escrito que por casualidad coincide con OTRO lugar '
        'real no da null — el servicio contesta con total confianza, así que '
        'devuelve el nombre que REALMENTE resolvió (no el que se escribió) '
        'para que el llamador pueda mostrárselo a la persona y que sea ella '
        'quien note el error. Caso real de Eliza: escribió "Nedellin" y '
        'quedó guardado a 9077km de Medellín', () async {
      geocoding.ubicaciones = [
        _ubicacion(55.0, 40.0),
      ]; // en otra parte del mundo
      geocoding.marcas = [
        const Placemark(locality: 'Nedelino', isoCountryCode: 'RU'),
      ];

      final r = await UbicacionService.desdeTexto('Nedellin');

      // Las coordenadas SÍ son las que el servicio devolvió — desdeTexto no
      // puede saber que están mal, esa es justamente la limitación real.
      expect(r!.lat, 55.0);
      // Pero el nombre resuelto es distinto de lo que se escribió: es la
      // señal que el llamador necesita para mostrar la confirmación.
      expect(r.ciudadResuelta, 'Nedelino');
      expect(r.ciudadResuelta, isNot('Nedellin'));
    });

    test('da null (no una excepción) cuando el servicio no encuentra nada — el '
        'caso real de escribir "verduras" en el campo de ciudad', () async {
      geocoding.errorAlBuscarDireccion = const NoResultFoundException();

      expect(await UbicacionService.desdeTexto('verduras'), isNull);
    });

    test(
      'también da null si el servicio responde con una lista vacía en vez de '
      'lanzar NoResultFoundException — no todos los backends de geocoding se '
      'comportan igual ante "no encontrado"',
      () async {
        geocoding.ubicaciones = [];

        expect(await UbicacionService.desdeTexto('verduras'), isNull);
      },
    );

    test('CUALQUIER OTRA excepción (sin señal, servicio caído) se propaga tal '
        'cual, no se confunde con "no es un lugar real" — el llamador necesita '
        'distinguir los dos casos para no bloquear un guardado por un problema '
        'de conexión', () async {
      geocoding.errorAlBuscarDireccion = Exception('sin señal');

      await expectLater(
        UbicacionService.desdeTexto('Medellín'),
        throwsA(isA<Exception>()),
      );
    });

    test('si el servicio nunca responde, corta con TimeoutException en vez de '
        'dejar el guardado esperando para siempre', () async {
      geocoding.nuncaResponde = true;

      await expectLater(
        UbicacionService.desdeTexto(
          'Medellín',
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test(
      'si falla SOLO la búsqueda del país, las coordenadas se devuelven igual '
      'con paisCodigo vacío — el país es un extra, la distancia depende de las '
      'coordenadas y esas ya se resolvieron bien',
      () async {
        geocoding.ubicaciones = [_ubicacion(6.25, -75.56)];
        geocoding.falla = true; // falla el reverse geocoding del país

        final r = await UbicacionService.desdeTexto('Medellín');

        expect(r!.lat, 6.25);
        expect(r.paisCodigo, '');
        expect(r.ciudadResuelta, '');
      },
    );
  });

  group('UbicacionService.ciudadDe()', () {
    test('usa locality (la ciudad propiamente dicha) cuando viene', () {
      expect(
        UbicacionService.ciudadDe(
          const Placemark(
            locality: 'Schiffdorf',
            administrativeArea: 'Baja Sajonia',
          ),
        ),
        'Schiffdorf',
      );
    });

    test(
      'cae a administrativeArea si locality viene vacía — pasa de verdad en '
      'zonas rurales y en países donde el geocoder no devuelve localidad',
      () {
        expect(
          UbicacionService.ciudadDe(
            const Placemark(locality: '', administrativeArea: 'Córdoba'),
          ),
          'Córdoba',
        );
      },
    );

    test(
      'string vacío (nunca null) si no hay ninguno de los dos — el llamador solo '
      'chequea isEmpty para decidir si dibuja el pin',
      () {
        expect(UbicacionService.ciudadDe(const Placemark()), '');
      },
    );
  });

  group('UbicacionService — el permiso, la parte que rompió el primer arranque '
      'del APK53', () {
    test('pedirPermisoSiFalta:false NO abre el diálogo del sistema — es lo que '
        'hace seguro reintentar al volver a primer plano: un diálogo mandaría la '
        'app a segundo plano y la devolvería, y ese "resumed" dispararía otro '
        'reintento, sin fin (el crash del Samsung Z Flip 6)', () async {
      geo.permiso = LocationPermission.denied;

      final r = await UbicacionService.actual(pedirPermisoSiFalta: false);

      expect(r.fallo, FalloUbicacion.permisoDenegado);
      expect(geo.vecesQuePidioPermiso, 0, reason: 'no se abrió ningún diálogo');
    });

    test(
      'pedirPermisoSiFalta:true (el default) sí lo pide — el primer arranque '
      'tiene que poder preguntar alguna vez',
      () async {
        geo.permiso = LocationPermission.denied;

        await UbicacionService.actual();

        expect(geo.vecesQuePidioPermiso, 1);
      },
    );

    test(
      'si el permiso YA está dado no se pide de nuevo, ni con el default',
      () async {
        geo.permiso = LocationPermission.whileInUse;

        await UbicacionService.actual();

        expect(geo.vecesQuePidioPermiso, 0);
      },
    );

    test('dos pantallas pidiendo ubicación A LA VEZ abren UN SOLO diálogo — '
        'Android solo admite un pedido de permiso simultáneo y el segundo falla '
        'en el acto. Inicio y el feed de Adoptar se montan juntos, así que en el '
        'primer arranque tras instalar (la única vez que el permiso no está dado) '
        'una de las dos quedaba sin ubicación: el bug real de Eliza estrenando el '
        'APK53, "para el rescatista no muestra el pin"', () async {
      geo.permiso = LocationPermission.denied;
      geo.permisoTrasPedirlo = LocationPermission.whileInUse;

      final resultados = await Future.wait([
        UbicacionService.actual(),
        UbicacionService.actual(),
      ]);

      expect(
        geo.vecesQuePidioPermiso,
        1,
        reason: 'un solo diálogo entre las dos',
      );
      expect(resultados[0].ok, true, reason: 'las DOS reciben la respuesta');
      expect(resultados[1].ok, true);
    });

    test(
      'tras conceder el permiso, un pedido POSTERIOR vuelve a poder pedirlo si '
      'hiciera falta — el candado es solo para los simultáneos, no se queda '
      'trabado para siempre',
      () async {
        geo.permiso = LocationPermission.denied;
        await UbicacionService.actual();
        expect(geo.vecesQuePidioPermiso, 1);

        await UbicacionService.actual();

        expect(geo.vecesQuePidioPermiso, 2);
      },
    );
  });
}
