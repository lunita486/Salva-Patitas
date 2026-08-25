import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:salva_patitas/services/ubicacion_service.dart';
import 'package:salva_patitas/widgets/campo_ciudad.dart';

import '../helpers/mock_nominatim.dart';

Widget _envolver(Widget child) => MaterialApp(home: Scaffold(body: child));

// Fake de GeolocatorPlatform — service/permission/posición configurables
// por test, para simular cada rama de CampoCiudad._detectar() (GPS
// apagado, permiso denegado/bloqueado, éxito, error) sin depender del
// dispositivo real donde corran los tests.
class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  _FakeGeolocatorPlatform({
    this.serviceEnabled = true,
    this.permiso = LocationPermission.always,
    this.posicion,
    this.errorAlObtenerPosicion,
  });
  bool serviceEnabled;
  LocationPermission permiso;
  Position? posicion;
  Object? errorAlObtenerPosicion;
  bool seAbrieronAjustesUbicacion = false;
  bool seAbrieronAjustesApp = false;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permiso;

  @override
  Future<LocationPermission> requestPermission() async => permiso;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    if (errorAlObtenerPosicion != null) throw errorAlObtenerPosicion!;
    return posicion!;
  }

  @override
  Future<bool> openLocationSettings() async {
    seAbrieronAjustesUbicacion = true;
    return true;
  }

  @override
  Future<bool> openAppSettings() async {
    seAbrieronAjustesApp = true;
    return true;
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
  group('CampoCiudad — atajo de GPS del perfil de albergue/aliado (pedido '
      'real de Eliza: "que la gente no escriba verduras", con un ícono '
      'para detectar la ciudad en vez de bloquear el texto libre)', () {
    testWidgets('servicio de ubicación apagado: avisa con botón para abrir '
        'Ajustes, no toca el controlador', (tester) async {
      GeolocatorPlatform.instance = _FakeGeolocatorPlatform(
        serviceEnabled: false,
      );
      final ctl = TextEditingController();
      await tester.pumpWidget(
        _envolver(CampoCiudad(controller: ctl, hint: 'ciudad')),
      );

      await tester.tap(find.byIcon(Icons.my_location));
      await tester.pumpAndSettle();

      expect(find.text('Activá el GPS'), findsOneWidget);
      expect(ctl.text, isEmpty);
    });

    testWidgets('permiso denegado (no para siempre): no avisa nada ni '
        'crashea — mismo criterio silencioso que ya usan subir_rescate_'
        'screen.dart/editar_rescate_screen.dart para este caso', (
      tester,
    ) async {
      GeolocatorPlatform.instance = _FakeGeolocatorPlatform(
        permiso: LocationPermission.denied,
      );
      final ctl = TextEditingController();
      await tester.pumpWidget(
        _envolver(CampoCiudad(controller: ctl, hint: 'ciudad')),
      );

      await tester.tap(find.byIcon(Icons.my_location));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      expect(ctl.text, isEmpty);
    });

    testWidgets('permiso bloqueado para siempre: avisa con botón para abrir '
        'Ajustes de la app', (tester) async {
      GeolocatorPlatform.instance = _FakeGeolocatorPlatform(
        permiso: LocationPermission.deniedForever,
      );
      final ctl = TextEditingController();
      await tester.pumpWidget(
        _envolver(CampoCiudad(controller: ctl, hint: 'ciudad')),
      );

      await tester.tap(find.byIcon(Icons.my_location));
      await tester.pumpAndSettle();

      expect(find.text('Ubicación bloqueada.'), findsOneWidget);
    });

    testWidgets('camino feliz: detecta posición, la resuelve a ciudad y '
        'llena el controlador — el mismo texto que hasta ahora solo se '
        'podía escribir a mano', (tester) async {
      GeolocatorPlatform.instance = _FakeGeolocatorPlatform(
        posicion: _posicion(6.25184, -75.56359),
      );
      final nominatim = MockNominatim()..configurarReversa(city: 'Medellín');
      UbicacionService.httpClient = nominatim.client;
      final ctl = TextEditingController();
      String? ultimoOnChanged;
      await tester.pumpWidget(
        _envolver(
          CampoCiudad(
            controller: ctl,
            hint: 'ciudad',
            onChanged: (v) => ultimoOnChanged = v,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.my_location));
      await tester.pumpAndSettle();

      expect(ctl.text, 'Medellín');
      expect(ultimoOnChanged, 'Medellín');
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('posición detectada pero sin localidad identificable: avisa '
        'y deja el campo tal como estaba, para que la persona lo escriba a '
        'mano', (tester) async {
      // (1, 1), no (0, 0): (0, 0) es "Null Island" y UbicacionService la
      // descarta como si no hubiera posición (ver ubicacion_service_test.
      // dart) — acá lo que se quiere simular es una posición VÁLIDA cuyo
      // reverse geocoding no resolvió ninguna ciudad, dos cosas distintas.
      GeolocatorPlatform.instance = _FakeGeolocatorPlatform(
        posicion: _posicion(1, 1),
      );
      UbicacionService.httpClient = MockNominatim().client;
      final ctl = TextEditingController(text: 'lo que ya había');
      await tester.pumpWidget(
        _envolver(CampoCiudad(controller: ctl, hint: 'ciudad')),
      );

      await tester.tap(find.byIcon(Icons.my_location));
      await tester.pumpAndSettle();

      expect(
        find.text('No pudimos identificar tu ciudad. Podés escribirla a mano.'),
        findsOneWidget,
      );
      expect(ctl.text, 'lo que ya había');
    });

    testWidgets('error inesperado al obtener la posición: avisa en vez de '
        'crashear o quedarse girando para siempre', (tester) async {
      GeolocatorPlatform.instance = _FakeGeolocatorPlatform(
        errorAlObtenerPosicion: Exception('falla de GPS'),
      );
      final ctl = TextEditingController();
      await tester.pumpWidget(
        _envolver(CampoCiudad(controller: ctl, hint: 'ciudad')),
      );

      await tester.tap(find.byIcon(Icons.my_location));
      await tester.pumpAndSettle();

      expect(
        find.text('No se pudo detectar tu ubicación. Podés escribirla a mano.'),
        findsOneWidget,
      );
    });
  });
}
