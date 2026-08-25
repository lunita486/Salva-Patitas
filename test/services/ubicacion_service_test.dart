import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart' as http_testing;
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:salva_patitas/services/ubicacion_service.dart';

import '../helpers/mock_nominatim.dart';

// Mismo patrón que test/theme_test.dart: se reemplaza el backend de
// plataforma de geolocator por un fake, así se puede probar cada rama (GPS
// apagado, permiso bloqueado, tropiezo transitorio del GPS) sin hardware
// real. Extiende la clase base (no la implementa) porque su constructor
// registra el token que PlatformInterface exige.
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
  late MockNominatim nominatim;

  setUp(() {
    geo = _FakeGeolocator(posicion: _posicion(-31.4, -64.2));
    nominatim = MockNominatim();
    GeolocatorPlatform.instance = geo;
    UbicacionService.httpClient = nominatim.client;
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

    test(
      'una posición (0, 0) — "Null Island", lo que devuelve el GPS cuando no '
      'tiene una lectura real (o el emulador sin ubicación configurada) — se '
      'trata como si no hubiera posición, no se acepta como si fuera real. '
      'Hallazgo real de Eliza: un animal con "Ubicación" vacía en el '
      'formulario mostraba "Se encuentra a 8875.1 km de ti" en el feed — las '
      'coordenadas (0, 0) SÍ se habían guardado, sin ciudad porque no hay '
      'nada que geocodificar en medio del océano',
      () async {
        geo.posicion = _posicion(0, 0);

        final r = await UbicacionService.actual();

        expect(r.ok, false);
        expect(r.fallo, FalloUbicacion.sinRespuesta);
      },
    );

    test(
      '(0, 0) con una última posición conocida real disponible: se usa esa '
      'en vez de descartar todo — mismo criterio que un GPS que tira '
      'excepción, (0, 0) no es un caso especial que se salte el respaldo',
      () async {
        geo.posicion = _posicion(0, 0);
        geo.ultimaConocida = _posicion(10, 20);

        final r = await UbicacionService.actual(
          ultimaConocida: UsoUltimaConocida.comoAnticipo,
        );

        expect(r.ok, true);
        expect(r.posicion!.latitude, 10);
      },
    );
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
        nominatim.configurarReversa(city: 'Rosario', countryCode: 'AR');

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
        nominatim.fallaReversa = true; // si lo llamara, este test explotaría

        final r = await UbicacionService.actual();

        expect(r.ok, true);
        expect(r.ciudad, '');
        expect(nominatim.vecesReversa, 0);
      },
    );

    test('conCiudad devuelve ciudad y código de país', () async {
      nominatim.configurarReversa(city: 'Córdoba', countryCode: 'AR');

      final r = await UbicacionService.actual(conCiudad: true);

      expect(r.ciudad, 'Córdoba');
      expect(r.paisCodigo, 'AR');
    });

    test('si el geocoding falla, las COORDENADAS siguen siendo válidas — se '
        'devuelve ok con ciudad vacía, no un error: el pin no se dibuja pero la '
        'distancia sí se puede calcular', () async {
      nominatim.fallaReversa = true;

      final r = await UbicacionService.actual(conCiudad: true);

      expect(r.ok, true);
      expect(r.posicion!.latitude, -31.4);
      expect(r.ciudad, '');
    });

    test(
      'si el geocoding no encuentra ningún lugar, mismo criterio: ok con ciudad '
      'vacía',
      () async {
        nominatim.direccionReversa = null;

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
        nominatim.resultadosBusqueda = [
          MockNominatim.candidato(
            lat: 6.25184,
            lon: -75.56359,
            city: 'Medellín',
            state: 'Antioquia',
            countryCode: 'CO',
          ),
        ];

        final r = await UbicacionService.desdeTexto('Medellín');

        expect(r!.first.lat, 6.25184);
        expect(r.first.lng, -75.56359);
        expect(r.first.paisCodigo, 'CO');
        expect(r.first.ciudadResuelta, 'Medellín');
        expect(r.first.regionResuelta, 'Antioquia');
      },
    );

    test('dos ciudades con el MISMO nombre en el MISMO país: regionResuelta '
        'trae la provincia/estado, que es lo único que las distingue — el '
        'nombre solo (y hasta la bandera) sería idéntico para las dos, así '
        'que sin esto el diálogo de confirmación no alcanzaría a delatar que '
        'el geocoder eligió la ciudad equivocada. Pregunta real de Eliza: '
        '"qué pasa si dos rescatistas... están en ciudades que tienen el '
        'mismo nombre"', () async {
      nominatim.resultadosBusqueda = [
        MockNominatim.candidato(
          lat: 9.9,
          lon: -75.2,
          city: 'San José',
          state: 'Córdoba',
          countryCode: 'CO',
        ),
      ];

      final r = await UbicacionService.desdeTexto('San José');

      expect(r!.first.ciudadResuelta, 'San José');
      expect(r.first.regionResuelta, 'Córdoba');
      // Otra "San José" real, en OTRO departamento del mismo país, daría el
      // mismo ciudadResuelta pero una regionResuelta distinta — es esa
      // diferencia la que el diálogo puede mostrar.
    });

    test(
      'regionResuelta viene vacía cuando ciudadDe() ya tuvo que caer a '
      'administrativeArea (zona rural, sin locality) — mostrar la misma '
      'región dos veces en el diálogo de confirmación no aportaría nada',
      () async {
        nominatim.resultadosBusqueda = [
          MockNominatim.candidato(
            lat: 1.0,
            lon: 2.0,
            state: 'Córdoba',
            countryCode: 'AR',
          ),
        ];

        final r = await UbicacionService.desdeTexto('zona rural de Córdoba');

        expect(r!.first.ciudadResuelta, 'Córdoba'); // cayó a administrativeArea
        expect(r.first.regionResuelta, ''); // no se repite
      },
    );

    test('un texto mal escrito que por casualidad coincide con OTRO lugar '
        'real no da null — el servicio contesta con total confianza, así que '
        'devuelve el nombre que REALMENTE resolvió (no el que se escribió) '
        'para que el llamador pueda mostrárselo a la persona y que sea ella '
        'quien note el error. Caso real de Eliza: escribió "Nedellin" y '
        'quedó guardado a 9077km de Medellín', () async {
      nominatim.resultadosBusqueda = [
        MockNominatim.candidato(
          lat: 55.0,
          lon: 40.0, // en otra parte del mundo
          city: 'Nedelino',
          countryCode: 'RU',
        ),
      ];

      final r = await UbicacionService.desdeTexto('Nedellin');

      // Las coordenadas SÍ son las que el servicio devolvió — desdeTexto no
      // puede saber que están mal, esa es justamente la limitación real.
      expect(r!.first.lat, 55.0);
      // Pero el nombre resuelto es distinto de lo que se escribió: es la
      // señal que el llamador necesita para mostrar la confirmación.
      expect(r.first.ciudadResuelta, 'Nedelino');
      expect(r.first.ciudadResuelta, isNot('Nedellin'));
    });

    test('da null (no una excepción) cuando el servicio responde con una '
        'lista vacía — el caso real de escribir "verduras" en el campo de '
        'ciudad', () async {
      nominatim.resultadosBusqueda = [];

      expect(await UbicacionService.desdeTexto('verduras'), isNull);
    });

    test(
      'también da null si todos los candidatos que devolvió el servicio '
      'vienen sin ningún nombre usable — una lista para elegir con '
      'opciones en blanco no le sirve a nadie',
      () async {
        nominatim.resultadosBusqueda = [
          MockNominatim.candidato(lat: 1, lon: 1, countryCode: 'CO'),
        ];

        expect(await UbicacionService.desdeTexto('???'), isNull);
      },
    );

    test('CUALQUIER excepción real (sin señal, servicio caído, el servidor '
        'respondiendo mal DOS veces seguidas — la de después del reintento) '
        'se propaga tal cual, no se confunde con "no es un lugar real" — el '
        'llamador necesita distinguir los dos casos para no bloquear un '
        'guardado por un problema de conexión', () async {
      nominatim.errorAlBuscar = Exception('sin señal');

      await expectLater(
        UbicacionService.desdeTexto('Medellín'),
        throwsA(isA<Exception>()),
      );
      expect(
        nominatim.vecesBusqueda,
        2,
        reason: 'se reintentó una vez antes de rendirse',
      );
    });

    test('si el servidor responde con un código de error (ej. Nominatim '
        'caído o limitando pedidos), también se trata como una falla real, '
        'no como "no encontrado"', () async {
      nominatim.statusBusqueda = 503;

      await expectLater(
        UbicacionService.desdeTexto('Medellín'),
        throwsA(isA<FalloDeGeocoding>()),
      );
    });

    test('si el servicio nunca responde, corta con TimeoutException en vez de '
        'dejar el guardado esperando para siempre', () async {
      nominatim.nuncaResponde = true;

      await expectLater(
        UbicacionService.desdeTexto(
          'Medellín',
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test(
      'un tropiezo transitorio de la búsqueda se reintenta UNA vez y sale '
      'bien — antes esto solo pasaba con el reverse geocoding del país, no '
      'con la búsqueda en sí; ahora los dos viajan en el mismo pedido, así '
      'que el mismo reintento cubre las dos cosas a la vez',
      () async {
        var primerIntento = true;
        nominatim.resultadosBusqueda = [
          MockNominatim.candidato(
            lat: -31.4,
            lon: -64.18,
            city: 'Córdoba',
            countryCode: 'AR',
          ),
        ];
        // El primer pedido tira, el reintento (mismo mock, misma lista ya
        // cargada) sale bien — se simula la falla forzando el mock a
        // lanzar en la primera llamada solamente.
        final clienteOriginal = nominatim.client;
        UbicacionService.httpClient = http_testing.MockClient((request) async {
          if (primerIntento) {
            primerIntento = false;
            throw Exception('tropiezo transitorio');
          }
          final resp = await clienteOriginal.get(request.url);
          return resp;
        });

        final r = await UbicacionService.desdeTexto('Córdoba, Argentina');

        expect(r!.first.paisCodigo, 'AR');
        expect(r.first.ciudadResuelta, 'Córdoba');
      },
    );

    test(
      'un texto ambiguo trae varios candidatos, no solo el primero — antes '
      'se descartaban en silencio los otros 4 que Android ya devolvía para '
      'este mismo pedido, así que si el primero resultaba ser un lugar real '
      'pero equivocado, la persona quedaba sin forma de llegar al que sí '
      'buscaba: escribir el mismo texto de nuevo siempre daba el mismo '
      'primero. Hallazgo real de Eliza en su teléfono (no el emulador): '
      '"medellin antioquia" resolvía siempre a "los olivos", un barrio '
      'real de Medellín',
      () async {
        nominatim.resultadosBusqueda = [
          MockNominatim.candidato(
            lat: 6.20,
            lon: -75.58,
            city: 'Los Olivos',
            state: 'Antioquia',
            countryCode: 'CO',
          ), // el primero, equivocado
          MockNominatim.candidato(
            lat: 6.25,
            lon: -75.56,
            city: 'Medellín',
            state: 'Antioquia',
            countryCode: 'CO',
          ), // Medellín centro — el que se busca
        ];

        final r = await UbicacionService.desdeTexto('medellin antioquia');

        expect(r!.length, 2);
        expect(r[0].ciudadResuelta, 'Los Olivos');
        expect(r[1].ciudadResuelta, 'Medellín');
      },
    );

    test(
      'se aprovechan hasta 5 candidatos — esta lista ES la única salida '
      'cuando el primer candidato está mal (no hay opción de escribir la '
      'ciudad a mano, ver confirmar_ciudad_resuelta.dart), así que '
      'recortarla de más deja a la persona sin opciones. Un sexto '
      'candidato (que Nominatim no debería mandar, se le pide limit=5, '
      'pero por las dudas) se ignora del lado del cliente también.',
      () async {
        nominatim.resultadosBusqueda = List.generate(
          6,
          (i) => MockNominatim.candidato(
            lat: (i + 1).toDouble(),
            lon: (i + 1).toDouble(),
            city: 'Ciudad${i + 1}',
            countryCode: 'CO',
          ),
        );

        final r = await UbicacionService.desdeTexto('texto ambiguo');

        expect(r!.length, 5);
        expect(r.last.ciudadResuelta, 'Ciudad5');
      },
    );

    test(
      'dos candidatos que resuelven a la misma ciudad y país no se '
      'muestran duplicados en la lista — no aportan nada mostrados dos '
      'veces',
      () async {
        nominatim.resultadosBusqueda = [
          MockNominatim.candidato(
            lat: 6.20,
            lon: -75.58,
            city: 'Medellín',
            countryCode: 'CO',
          ),
          MockNominatim.candidato(
            lat: 6.21,
            lon: -75.59, // coordenada distinta, misma ciudad
            city: 'Medellín',
            countryCode: 'CO',
          ),
        ];

        final r = await UbicacionService.desdeTexto('medellin');

        expect(r!.length, 1);
      },
    );

    test(
      'un candidato sin ningún nombre usable se salta, sin importar en qué '
      'posición de la lista venga — solo quedan los candidatos que de '
      'verdad se le pueden mostrar a la persona para elegir',
      () async {
        nominatim.resultadosBusqueda = [
          MockNominatim.candidato(
            lat: 6.20,
            lon: -75.58,
            city: 'Medellín',
            countryCode: 'CO',
          ),
          MockNominatim.candidato(
            lat: 9.9,
            lon: -75.2,
            countryCode: 'CO',
          ), // sin city/state/town: no se puede describir
        ];

        final r = await UbicacionService.desdeTexto('medellin');

        expect(r!.length, 1);
        expect(r.first.ciudadResuelta, 'Medellín');
      },
    );
  });

  group('UbicacionService.ciudadDe()', () {
    test('usa locality (la ciudad propiamente dicha) cuando viene', () {
      expect(
        UbicacionService.ciudadDe((
          locality: 'Schiffdorf',
          administrativeArea: 'Baja Sajonia',
        )),
        'Schiffdorf',
      );
    });

    test(
      'cae a administrativeArea si locality viene vacía — pasa de verdad en '
      'zonas rurales y en países donde el geocoder no devuelve localidad',
      () {
        expect(
          UbicacionService.ciudadDe((
            locality: '',
            administrativeArea: 'Córdoba',
          )),
          'Córdoba',
        );
      },
    );

    test(
      'string vacío (nunca null) si no hay ninguno de los dos — el llamador solo '
      'chequea isEmpty para decidir si dibuja el pin',
      () {
        expect(
          UbicacionService.ciudadDe((locality: '', administrativeArea: '')),
          '',
        );
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

  group(
    'ResultadoUbicacion.sinNombre — el GPS anduvo pero nadie le supo poner '
    'nombre al punto. Las tres pantallas que piden ubicación lo resolvían '
    'distinto; una dejaba ciudad, coordenadas y país en 3 lugares distintos.',
    () {
      test('con coordenadas y ciudad: no es sinNombre', () {
        const r = ResultadoUbicacion.ok(
          posicion: null,
          ciudad: 'Santiago de los Caballeros',
          paisCodigo: 'DO',
        );
        expect(r.sinNombre, isFalse);
      });

      test('con coordenadas pero sin ciudad: sinNombre', () {
        const r = ResultadoUbicacion.ok(posicion: null);
        expect(r.sinNombre, isTrue);
      });

      // sinNombre describe un ÉXITO parcial. Un fallo entero ya tiene su
      // propio camino (el switch sobre FalloUbicacion) y no debe caer acá
      // también, o se avisaría dos veces por lo mismo.
      test('un fallo de GPS NO es sinNombre', () {
        for (final f in FalloUbicacion.values) {
          expect(
            ResultadoUbicacion.fallo(f).sinNombre,
            isFalse,
            reason: '$f ya se avisa por su propia rama',
          );
        }
      });
    },
  );
}
