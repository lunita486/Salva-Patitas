import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/domain/resolucion_perfil.dart';

void main() {
  group('resolverPantallaPerfil — sin roles', () {
    test('lista de roles vacía manda a seleccionar rol', () {
      expect(
        resolverPantallaPerfil({'roles': <String>[]}),
        PantallaPerfil.seleccionRol,
      );
    });

    test('sin la clave roles siquiera (doc a medio crear) manda a '
        'seleccionar rol', () {
      expect(resolverPantallaPerfil({}), PantallaPerfil.seleccionRol);
    });
  });

  group('resolverPantallaPerfil — albergue', () {
    test('rol albergue sin albergueNombre: falta completar perfil', () {
      expect(
        resolverPantallaPerfil({
          'roles': ['albergue'],
        }),
        PantallaPerfil.alberguePerfil,
      );
    });

    test('rol albergue con albergueNombre vacío: sigue faltando perfil', () {
      expect(
        resolverPantallaPerfil({
          'roles': ['albergue'],
          'albergueNombre': '',
        }),
        PantallaPerfil.alberguePerfil,
      );
    });

    test('rol albergue con albergueNombre cargado: a su home', () {
      expect(
        resolverPantallaPerfil({
          'roles': ['albergue'],
          'albergueNombre': 'Patitas Felices',
        }),
        PantallaPerfil.albergueHome,
      );
    });
  });

  group('resolverPantallaPerfil — aliado', () {
    test('rol aliado sin aliadoNombre: falta completar perfil', () {
      expect(
        resolverPantallaPerfil({
          'roles': ['aliado'],
        }),
        PantallaPerfil.aliadoPerfil,
      );
    });

    test('rol aliado con aliadoNombre cargado: a su home', () {
      expect(
        resolverPantallaPerfil({
          'roles': ['aliado'],
          'aliadoNombre': 'Veterinaria Sur',
        }),
        PantallaPerfil.aliadoHome,
      );
    });
  });

  group('resolverPantallaPerfil — rescatista/adoptante', () {
    test('rol rescatista (sin albergue ni aliado): a HomeScreen', () {
      expect(
        resolverPantallaPerfil({
          'roles': ['rescatista'],
        }),
        PantallaPerfil.home,
      );
    });

    test('rol adoptante: a HomeScreen', () {
      expect(
        resolverPantallaPerfil({
          'roles': ['adoptante'],
        }),
        PantallaPerfil.home,
      );
    });
  });

  group('resolverPantallaPerfil — doble rol', () {
    test('albergue + aliado a la vez: albergue gana, mismo orden que el '
        'código original', () {
      expect(
        resolverPantallaPerfil({
          'roles': ['aliado', 'albergue'],
          'aliadoNombre': 'Veterinaria Sur',
        }),
        PantallaPerfil.alberguePerfil,
      );
    });

    test('albergue + rescatista: albergue gana', () {
      expect(
        resolverPantallaPerfil({
          'roles': ['rescatista', 'albergue'],
          'albergueNombre': 'Patitas Felices',
        }),
        PantallaPerfil.albergueHome,
      );
    });
  });
}
