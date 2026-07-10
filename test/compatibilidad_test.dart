import 'package:flutter_test/flutter_test.dart';
import 'package:patitas_medellin/compatibilidad.dart';

void main() {
  group('calcularCompatibilidad', () {
    test('mapa vacío usa los defaults optimistas de cada campo (score perfecto)', () {
      // energia→Tranquilo(+20), tamano→Mediano con vivienda=''(+20),
      // tieneNinos/tieneMascotas→false(+20 c/u), requiereExp→false(+20).
      // Documenta el comportamiento actual: sin datos del adoptante, el
      // score no penaliza — vale la pena saberlo si alguna pantalla asume
      // que "sin perfil" da un score bajo.
      expect(calcularCompatibilidad({}), 100);
    });

    test('coincidencia perfecta en todos los criterios da 100', () {
      expect(calcularCompatibilidad({
        'animalEnergia': 'Tranquilo',
        'animalTamano': 'Pequeño',
        'animalOkConNinos': true,
        'animalOkConMascotas': true,
        'animalRequiereExp': false,
        'vivienda': 'Casa con jardín',
        'horasFuera': 2,
        'tieneNinos': true,
        'tieneMascotas': true,
        'experienciaPrevia': false,
      }), 100);
    });

    test('peor caso posible en todos los criterios da 0', () {
      expect(calcularCompatibilidad({
        'animalEnergia': 'Muy activo',
        'animalTamano': 'Grande',
        'animalOkConNinos': false,
        'animalOkConMascotas': false,
        'animalRequiereExp': true,
        'vivienda': 'Apartamento sin área exterior',
        'horasFuera': 10,
        'tieneNinos': true,
        'tieneMascotas': true,
        'experienciaPrevia': false,
      }), 0);
    });

    group('energía', () {
      test('Activo con 8 horas o menos suma 20', () {
        final score = calcularCompatibilidad({'animalEnergia': 'Activo', 'horasFuera': 8});
        expect(score, greaterThanOrEqualTo(20));
      });

      test('Activo con más de 8 horas solo suma 10 (penaliza, no descarta)', () {
        final conPoco = calcularCompatibilidad({'animalEnergia': 'Activo', 'horasFuera': 8});
        final conMucho = calcularCompatibilidad({'animalEnergia': 'Activo', 'horasFuera': 9});
        expect(conMucho, conPoco - 10);
      });

      test('Muy activo con patio y 6 horas o menos suma el máximo (20)', () {
        final base = calcularCompatibilidad({
          'animalEnergia': 'Muy activo', 'vivienda': 'Casa con jardín', 'horasFuera': 6,
        });
        final sinPatioNiTiempo = calcularCompatibilidad({
          'animalEnergia': 'Muy activo', 'vivienda': '', 'horasFuera': 10,
        });
        expect(base, sinPatioNiTiempo + 20);
      });

      test('Muy activo con solo UNO de los dos factores (patio u horas) suma la mitad (10)', () {
        final soloPatio = calcularCompatibilidad({
          'animalEnergia': 'Muy activo', 'vivienda': 'Casa con jardín', 'horasFuera': 10,
        });
        final soloHoras = calcularCompatibilidad({
          'animalEnergia': 'Muy activo', 'vivienda': '', 'horasFuera': 6,
        });
        final ninguno = calcularCompatibilidad({
          'animalEnergia': 'Muy activo', 'vivienda': '', 'horasFuera': 10,
        });
        expect(soloPatio, ninguno + 10);
        expect(soloHoras, ninguno + 10);
      });
    });

    group('tamaño', () {
      test('Mediano en apartamento sin área exterior suma solo 10, no 20', () {
        final conEspacio = calcularCompatibilidad({
          'animalTamano': 'Mediano', 'vivienda': 'Apartamento con balcón',
        });
        final sinEspacio = calcularCompatibilidad({
          'animalTamano': 'Mediano', 'vivienda': 'Apartamento sin área exterior',
        });
        expect(sinEspacio, conEspacio - 10);
      });

      test('Grande sin patio pero con balcón suma 10; sin nada suma 0', () {
        final conPatio = calcularCompatibilidad({
          'animalTamano': 'Grande', 'vivienda': 'Casa con jardín',
        });
        final conBalcon = calcularCompatibilidad({
          'animalTamano': 'Grande', 'vivienda': 'Apartamento con balcón',
        });
        final sinNada = calcularCompatibilidad({
          'animalTamano': 'Grande', 'vivienda': 'Apartamento sin área exterior',
        });
        expect(conBalcon, conPatio - 10);
        expect(sinNada, conPatio - 20);
      });
    });

    group('niños, mascotas y experiencia (mismo patrón en los tres)', () {
      test('si el adoptante no tiene niños/mascotas, el requisito del animal no importa', () {
        final animalNoApto = calcularCompatibilidad({
          'animalOkConNinos': false, 'tieneNinos': false,
        });
        final animalApto = calcularCompatibilidad({
          'animalOkConNinos': true, 'tieneNinos': false,
        });
        expect(animalNoApto, animalApto);
      });

      test('si hay niños y el animal no es apto, penaliza 20 puntos', () {
        final apto = calcularCompatibilidad({'animalOkConNinos': true, 'tieneNinos': true});
        final noApto = calcularCompatibilidad({'animalOkConNinos': false, 'tieneNinos': true});
        expect(noApto, apto - 20);
      });

      test('si el animal requiere experiencia y el adoptante no tiene, penaliza 20 puntos', () {
        final conExp = calcularCompatibilidad({
          'animalRequiereExp': true, 'experienciaPrevia': true,
        });
        final sinExp = calcularCompatibilidad({
          'animalRequiereExp': true, 'experienciaPrevia': false,
        });
        expect(sinExp, conExp - 20);
      });
    });

    test('horasFuera llega como String desde Firestore (dato legado) y se interpreta igual que int', () {
      final comoInt = calcularCompatibilidad({'animalEnergia': 'Activo', 'horasFuera': 9});
      final comoString = calcularCompatibilidad({'animalEnergia': 'Activo', 'horasFuera': '9'});
      expect(comoString, comoInt);
    });

    test('horasFuera no numérico cae a 0 en vez de romper', () {
      expect(
        () => calcularCompatibilidad({'animalEnergia': 'Activo', 'horasFuera': 'mucho'}),
        returnsNormally,
      );
      final invalido = calcularCompatibilidad({'animalEnergia': 'Activo', 'horasFuera': 'mucho'});
      final cero = calcularCompatibilidad({'animalEnergia': 'Activo', 'horasFuera': 0});
      expect(invalido, cero);
    });
  });

  group('explicarCompatibilidad', () {
    test('siempre devuelve exactamente 5 razones (energía, tamaño, niños, mascotas, experiencia)', () {
      expect(explicarCompatibilidad({}).length, 5);
      expect(explicarCompatibilidad({
        'animalEnergia': 'Muy activo', 'animalTamano': 'Grande',
        'tieneNinos': true, 'tieneMascotas': true, 'experienciaPrevia': false,
      }).length, 5);
    });

    test('energía Tranquilo da una razón positiva', () {
      final razones = explicarCompatibilidad({'animalEnergia': 'Tranquilo'});
      expect(razones[0].$2, true);
      expect(razones[0].$1, contains('tranquilo'));
    });

    test('energía Activo con muchas horas solo da razón negativa con las horas reales interpoladas', () {
      final razones = explicarCompatibilidad({'animalEnergia': 'Activo', 'horasFuera': 12});
      expect(razones[0].$2, false);
      expect(razones[0].$1, contains('12 h/día'));
    });

    test('energía Muy activo sin patio y muchas horas da la razón más negativa de las cuatro variantes', () {
      final razones = explicarCompatibilidad({
        'animalEnergia': 'Muy activo', 'vivienda': '', 'horasFuera': 10,
      });
      expect(razones[0].$2, false);
      expect(razones[0].$1, contains('necesita jardín y menos horas solo'));
    });

    test('tamaño Grande con balcón da razón negativa distinta a sin nada', () {
      final conBalcon = explicarCompatibilidad({
        'animalTamano': 'Grande', 'vivienda': 'Apartamento con balcón',
      });
      final sinNada = explicarCompatibilidad({
        'animalTamano': 'Grande', 'vivienda': '',
      });
      expect(conBalcon[1].$2, false);
      expect(sinNada[1].$2, false);
      expect(conBalcon[1].$1, isNot(equals(sinNada[1].$1)));
    });

    test('niños: sin niños en casa es siempre positivo sin importar si el animal es apto', () {
      final razones = explicarCompatibilidad({'animalOkConNinos': false, 'tieneNinos': false});
      expect(razones[2].$2, true);
      expect(razones[2].$1, 'Sin niños en casa');
    });

    test('niños: con niños y animal no apto es negativo', () {
      final razones = explicarCompatibilidad({'animalOkConNinos': false, 'tieneNinos': true});
      expect(razones[2].$2, false);
    });

    test('mascotas: con mascotas y animal que convive bien es positivo', () {
      final razones = explicarCompatibilidad({'animalOkConMascotas': true, 'tieneMascotas': true});
      expect(razones[3].$2, true);
      expect(razones[3].$1, contains('convive bien'));
    });

    test('experiencia: el animal la requiere y el adoptante no tiene es negativo', () {
      final razones = explicarCompatibilidad({
        'animalRequiereExp': true, 'experienciaPrevia': false,
      });
      expect(razones[4].$2, false);
      expect(razones[4].$1, 'El animal requiere experiencia previa');
    });

    test('experiencia: no se requiere es siempre positivo sin importar el adoptante', () {
      final razones = explicarCompatibilidad({
        'animalRequiereExp': false, 'experienciaPrevia': false,
      });
      expect(razones[4].$2, true);
      expect(razones[4].$1, 'No se requiere experiencia previa');
    });
  });
}
