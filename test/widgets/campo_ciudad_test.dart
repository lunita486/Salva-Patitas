import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding_platform_interface/geocoding_platform_interface.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:salva_patitas/widgets/campo_ciudad.dart';

Widget _envolver(Widget child) => MaterialApp(home: Scaffold(body: child));

// Fakes del backend de geocoding/GPS para probar CampoCiudad sin red ni
// hardware real (la lógica de GPS/geocoding en sí ya vive en
// UbicacionService, con sus propios tests) — mismo patrón que
// fake_cloud_firestore para Firestore. Extienden GeocodingPlatform/
// GeolocatorPlatform (no las implementan) a propósito: el constructor de
// la clase base ya registra el token interno que PlatformInterface exige,
// así que un fake por `extends` queda válido sin ningún mixin extra.
class _FakeGeocodingPlatform extends GeocodingPlatform {
  _FakeGeocodingPlatform({
    Future<List<Location>> Function(String)? locationFromAddress,
    Future<List<Placemark>> Function(double, double)? placemarkFromCoordinates,
  }) : _locationFromAddress = locationFromAddress,
       _placemarkFromCoordinates = placemarkFromCoordinates;
  final Future<List<Location>> Function(String)? _locationFromAddress;
  final Future<List<Placemark>> Function(double, double)?
  _placemarkFromCoordinates;

  @override
  Future<List<Location>> locationFromAddress(String address) =>
      (_locationFromAddress ?? (_) async => <Location>[])(address);

  @override
  Future<List<Placemark>> placemarkFromCoordinates(
    double latitude,
    double longitude,
  ) => (_placemarkFromCoordinates ?? (_, _) async => <Placemark>[])(
    latitude,
    longitude,
  );
}

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

      expect(find.text('Activa el GPS en tu dispositivo'), findsOneWidget);
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

      expect(find.text('Permiso de ubicación bloqueado.'), findsOneWidget);
    });

    testWidgets('camino feliz: detecta posición, la resuelve a ciudad y '
        'llena el controlador — el mismo texto que hasta ahora solo se '
        'podía escribir a mano', (tester) async {
      GeolocatorPlatform.instance = _FakeGeolocatorPlatform(
        posicion: _posicion(6.25184, -75.56359),
      );
      GeocodingPlatform.instance = _FakeGeocodingPlatform(
        placemarkFromCoordinates: (_, _) async => [
          const Placemark(locality: 'Medellín'),
        ],
      );
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
      GeolocatorPlatform.instance = _FakeGeolocatorPlatform(
        posicion: _posicion(0, 0),
      );
      GeocodingPlatform.instance = _FakeGeocodingPlatform(
        placemarkFromCoordinates: (_, _) async => const [],
      );
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
