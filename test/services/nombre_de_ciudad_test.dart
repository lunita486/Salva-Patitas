import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/services/ubicacion_service.dart';

/// Que el nombre de ciudad que guarda la app sea el que usa la gente.
///
/// **El bug.** Tocando el botón de GPS en Medellín, OpenStreetMap contesta
/// `city = "Perímetro Urbano Medellín"`, y eso quedaba guardado y salía en la
/// tarjeta del animalito. Nadie busca así. Hallazgo real de Eliza: "no puedo
/// poner Medellín, siempre me lo reemplaza".
///
/// Los valores de acá NO están inventados ni recordados: salieron de
/// consultarle al servicio de verdad punto por punto. Por eso la lista
/// incluye las ciudades que vienen BIEN — son la mitad que importa, la que
/// dice que el arreglo saca el envoltorio sin tocar el nombre.
void main() {
  group('lo que devuelve OpenStreetMap hoy, medido', () {
    // lat/lon consultados el 2026-08-27 contra nominatim.openstreetmap.org
    const casos = <String, String>{
      // Rotas, cada una a su manera
      'Perímetro Urbano Medellín': 'Medellín', // 6.2442, -75.5812
      'Perímetro Urbano Barranquilla': 'Barranquilla', // 10.9639, -74.7964
      'Cali ciudad': 'Cali', // 3.4516, -76.5320
      // Sanas: tienen que salir intactas
      'Bogotá': 'Bogotá', // 4.6097, -74.0817
      'Envigado': 'Envigado', // 6.1759, -75.5906
      'Bello': 'Bello', // 6.3379, -75.5580
      'Rionegro': 'Rionegro', // 6.1549, -75.3739
    };

    casos.forEach((crudo, esperado) {
      test('"$crudo" -> "$esperado"', () {
        expect(UbicacionService.limpiarNombreDeCiudad(crudo), esperado);
      });
    });
  });

  group('lo que NO se puede llevar puesto', () {
    // El error tentador es agregar "Ciudad de " a la lista de prefijos. Si
    // alguien lo hace, este test se lo dice antes de que la app deje a media
    // Ciudad de México guardada como "México", que es el país.
    test('Ciudad de México queda entera', () {
      expect(UbicacionService.limpiarNombreDeCiudad('Ciudad de México'),
          'Ciudad de México');
    });

    test('Ciudad Bolívar queda entera', () {
      expect(UbicacionService.limpiarNombreDeCiudad('Ciudad Bolívar'),
          'Ciudad Bolívar');
    });

    // "ciudad" se saca solo cuando es el envoltorio del final, nunca del
    // medio ni del principio.
    test('Ciudad del Este queda entera', () {
      expect(UbicacionService.limpiarNombreDeCiudad('Ciudad del Este'),
          'Ciudad del Este');
    });
  });

  group('bordes', () {
    test('un nombre vacío no explota', () {
      expect(UbicacionService.limpiarNombreDeCiudad(''), '');
    });

    test('si limpiar dejara la nada, se devuelve el original', () {
      // Preferible un nombre feo a ninguno: sin ciudad, el animalito no
      // aparece en ninguna búsqueda.
      expect(UbicacionService.limpiarNombreDeCiudad('Perímetro Urbano'),
          'Perímetro Urbano');
      expect(UbicacionService.limpiarNombreDeCiudad('ciudad'), 'ciudad');
    });

    test('los espacios de sobra se van', () {
      expect(UbicacionService.limpiarNombreDeCiudad('  Perímetro Urbano Medellín  '),
          'Medellín');
    });

    test('no importa cómo esté escrito en mayúsculas', () {
      expect(UbicacionService.limpiarNombreDeCiudad('PERÍMETRO URBANO Medellín'),
          'Medellín');
      expect(UbicacionService.limpiarNombreDeCiudad('Cali Ciudad'), 'Cali');
    });
  });
}
