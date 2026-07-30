import 'package:flutter_test/flutter_test.dart';
import 'package:patitas_medellin/data/auth_helper.dart';

// auth_helper.dart NO tiene fake_cloud_firestore de por medio (no es lo que
// prueba): iniciarSesionGoogle()/cerrarSesion() son funciones de nivel de
// archivo que hablan directo con GoogleSignIn.instance/FirebaseAuth.instance
// — singletons reales del SDK, sin ningún punto de inyección para
// reemplazarlos por un fake (a diferencia de los repositorios de
// lib/data/*_repository.dart, que sí reciben su FirebaseFirestore por
// constructor). authenticate() además abre un selector de cuenta nativo,
// imposible de accionar en un test.
//
// Cubrir el camino feliz/las ramas de error de verdad requeriría
// refactorizar este archivo para inyectar esas dependencias — un cambio de
// arquitectura más grande que el bug que motivó esta prueba. Mientras tanto,
// esto deja cubierto lo único que SÍ es accionable desde afuera del archivo:
// el estado expuesto y el contrato del enum que el resto de la app consume.
void main() {
  group('auth_helper', () {
    test('hayOperacionDeSesionEnCurso arranca en false (sin ninguna operación real disparada)', () {
      expect(hayOperacionDeSesionEnCurso, isFalse);
    });

    test('ResultadoLogin conserva sus 3 valores esperados — login_screen.dart '
        'depende de un switch exhaustivo sobre estos 3; que alguno cambie de '
        'nombre sin querer rompería esa pantalla en silencio', () {
      expect(ResultadoLogin.values, [
        ResultadoLogin.ok,
        ResultadoLogin.cancelado,
        ResultadoLogin.ocupado,
      ]);
    });
  });
}
