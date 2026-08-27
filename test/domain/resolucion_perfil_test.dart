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

  // ── La salida de la pantalla de aliado/albergue ────────────────────────
  //
  // Estas dos reglas juntas encerraban a una cuenta para siempre:
  //
  //   1. 'albergue' y 'aliado' ganan sobre cualquier otro rol acá abajo,
  //      así que una cuenta con ese rol aterriza SIEMPRE en esa pantalla;
  //   2. "Gestionar mis roles" solo existía en los perfiles de adoptante y
  //      de rescatista.
  //
  // O sea: quien alguna vez se registró como negocio aliado o como albergue
  // no tenía ninguna forma, dentro de la app, de volver a entrar como
  // adoptante. Ni siquiera teniendo los dos roles guardados. Lo encontró
  // Eliza con su propia cuenta: "entro con mi usuario de gmail y llego
  // siempre al aliado, por qué no puedo entrar con ese rol".
  //
  // El arreglo fue agregar "Gestionar mis roles" a las dos pantallas de
  // home que faltaban, no cambiar esta prioridad (un negocio que abre la
  // app espera ver su negocio). Lo que sigue documenta que la prioridad es
  // a propósito, para que quien la lea entienda por qué hace falta la
  // salida y no la borre creyendo que sobra.
  group('un rol de negocio gana, y por eso hace falta poder salir', () {
    test('aliado gana sobre adoptante y rescatista', () {
      expect(
        resolverPantallaPerfil({
          'roles': ['adoptante', 'rescatista', 'aliado'],
          'aliadoNombre': 'Veterinaria 30',
        }),
        PantallaPerfil.aliadoHome,
        reason: 'si esto cambia, revisá que la salida siga teniendo sentido',
      );
    });

    test('albergue gana incluso sobre aliado', () {
      expect(
        resolverPantallaPerfil({
          'roles': ['adoptante', 'aliado', 'albergue'],
          'albergueNombre': 'La Perla',
          'aliadoNombre': 'Veterinaria 30',
        }),
        PantallaPerfil.albergueHome,
      );
    });

    test('sacando el rol de negocio, se vuelve a la app normal', () {
      // Esto es lo que consigue "Gestionar mis roles": sin el rol de
      // negocio, la misma cuenta aterriza en la pantalla de siempre.
      expect(
        resolverPantallaPerfil({'roles': ['adoptante', 'rescatista']}),
        PantallaPerfil.home,
      );
    });
  });
}
