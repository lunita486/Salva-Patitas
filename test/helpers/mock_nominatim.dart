import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

/// Simula el servidor de Nominatim entero con un `MockClient`, para probar
/// cualquier código que pase por `UbicacionService.httpClient` (el propio
/// servicio y todo lo que llama a `actual(conCiudad: true)`/`desdeTexto()`
/// por debajo — hoy `CampoCiudad` y `confirmar_ciudad_resuelta.dart`) sin
/// red real. Compartido a propósito: antes de Nominatim cada test file tenía
/// su propio fake de `GeocodingPlatform`, y esta clase es la versión única
/// que los reemplaza a todos.
class MockNominatim {
  /// Cada item es lo que `/search` devolvería para UN candidato — `null`
  /// en `city`/`state`/`countryCode` omite ese campo del JSON (igual que
  /// Nominatim, que no manda claves sin valor).
  List<Map<String, Object?>> resultadosBusqueda = [];
  int statusBusqueda = 200;
  Object? errorAlBuscar;
  bool nuncaResponde = false;
  int vecesBusqueda = 0;

  /// La dirección que devuelve `/reverse` (coordenadas → nombre), usada por
  /// `actual(conCiudad: true)`. `null` = Nominatim no resolvió nada para
  /// ese punto.
  Map<String, Object?>? direccionReversa;
  bool fallaReversa = false;

  /// Cuántas veces seguidas falla `/reverse` antes de andar — para probar
  /// el reintento sin depender de una red real intermitente.
  int fallasSeguidasReversa = 0;
  int vecesReversa = 0;

  static Map<String, Object?> _address({
    String? city,
    String? state,
    String? countryCode,
  }) => {
    if (city != null) 'city': city,
    if (state != null) 'state': state,
    if (countryCode != null) 'country_code': countryCode.toLowerCase(),
  };

  /// Atajo para armar un item de `resultadosBusqueda` sin escribir el mapa
  /// de `address` a mano en cada test.
  static Map<String, Object?> candidato({
    required double lat,
    required double lon,
    String? city,
    String? state,
    String? countryCode,
  }) => {
    'lat': '$lat',
    'lon': '$lon',
    'address': _address(city: city, state: state, countryCode: countryCode),
  };

  void configurarReversa({String? city, String? state, String? countryCode}) {
    direccionReversa = _address(
      city: city,
      state: state,
      countryCode: countryCode,
    );
  }

  http.Client get client => http_testing.MockClient((request) async {
    if (nuncaResponde) return Completer<http.Response>().future;
    if (request.url.path.endsWith('/search')) {
      vecesBusqueda++;
      if (errorAlBuscar != null) throw errorAlBuscar!;
      return http.Response(jsonEncode(resultadosBusqueda), statusBusqueda);
    }
    if (request.url.path.endsWith('/reverse')) {
      vecesReversa++;
      if (fallaReversa) throw Exception('geocoding caído (simulado)');
      if (fallasSeguidasReversa > 0) {
        fallasSeguidasReversa--;
        throw Exception('geocoding caído (simulado, transitorio)');
      }
      final address = direccionReversa;
      return http.Response(
        jsonEncode(address == null ? {} : {'address': address}),
        200,
      );
    }
    throw StateError('URL no esperada en el test: ${request.url}');
  });
}
