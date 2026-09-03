import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/domain/reglas_negocio.dart';

/// Las dos puertas de la Red de hogares de paso validan la FORMA del email.
///
/// **El hueco.** `Agregar` y `Editar contacto` exigían que el email no
/// estuviera vacío y nada más: `_valido => _emailCtl.text.trim().isNotEmpty`.
/// Ni una ni otra importaba `esEmailValido`. Solo ponían
/// `keyboardType: emailAddress`, que es un teclado, no una validación.
///
/// Y ese campo no es un dato de contacto cualquiera: es la IDENTIDAD de la
/// persona en la red, lo que `buscarDuplicado` compara para decidir si dos
/// filas son la misma. Un email mal escrito rompe la fusión y deja una fila
/// que no se va a poder unir nunca. Medido en producción el 2026-09-03: de
/// 9 filas con email, 1 era `lunita486@gmail`, sin el `.com`.
///
/// La tercera puerta a la misma red (el diálogo de "Pedir hogar de paso"
/// del albergue, pedir_hogar_de_paso.dart) ya validaba. Por eso se podía
/// entrar un email correcto por ahí y arruinarlo editándolo por acá.
///
/// **Por qué se prueba leyendo el fuente.** `_AgregarHogarSheet` y
/// `_EditarContactoSheet` son clases privadas dentro de una pantalla que
/// arranca con `FirebaseAuth.instance` y un repositorio real, así que un
/// test de widget no las alcanza sin montar Firebase. La REGLA en sí
/// (`esEmailValido`) tiene sus propios tests de comportamiento en
/// test/domain/reglas_negocio_test.dart, con los mismos casos. Acá se fija
/// que las dos hojas la usen, que es lo que faltaba. Mismo patrón que las
/// guardas de prioridad_en_carruseles_test.dart.
void main() {
  final fuente = File('lib/screens/hogares_de_paso_screen.dart')
      .readAsStringSync()
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  /// El cuerpo de cada hoja, desde su `class` hasta la siguiente.
  String hoja(String clase) {
    final desde = fuente.indexOf('class ${clase}State');
    expect(desde, isNot(-1), reason: 'no está $clase: ¿la renombraron?');
    final hasta = fuente.indexOf('\nclass ', desde + 1);
    return fuente.substring(desde, hasta == -1 ? fuente.length : hasta);
  }

  /// SOLO el getter `_valido` de esa hoja, que es lo que apaga el botón.
  ///
  /// Mirar la clase entera no alcanzaba: `esEmailValido` aparece también en
  /// el `errorText` del campo, así que sacarlo del getter dejaba pasar el
  /// test igual. Lo encontré haciendo la contraprueba.
  String reglaDelBoton(String clase) {
    final cuerpo = hoja(clase);
    final desde = cuerpo.indexOf('bool get _valido');
    expect(desde, isNot(-1), reason: '$clase ya no decide con _valido');
    return cuerpo.substring(desde, cuerpo.indexOf(';', desde));
  }

  group('Red de hogares de paso — Agregar y Editar validan la forma del '
      'email, no solo que esté lleno', () {
    for (final clase in ['_AgregarHogarSheet', '_EditarContactoSheet']) {
      group(clase, () {
        test('el botón exige que el email tenga forma de email', () {
          expect(
            reglaDelBoton(clase),
            contains('esEmailValido(_emailCtl.text.trim())'),
            reason:
                '$clase volvió a aceptar cualquier texto como email, y ese '
                'campo es la identidad de la persona para buscarDuplicado',
          );
        });

        // Las dos reglas van separadas: la obligatoriedad la decide la
        // pantalla, la forma la decide reglas_negocio. Que
        // esEmailValido('') sea false es un detalle del validador, no algo
        // de lo que esta pantalla deba depender.
        test('y sigue exigiendo, aparte, que no esté vacío', () {
          expect(
            reglaDelBoton(clase),
            contains('_emailCtl.text.trim().isNotEmpty'),
            reason: 'en esta red el email es obligatorio',
          );
        });

        // El MISMO texto corto que el diálogo de "Pedir hogar de paso",
        // que es la tercera puerta a esta misma red: el mismo error no
        // puede explicarse distinto según por dónde se entre. Pedido de
        // Eliza. El largo (`avisoEmailInvalido`) sigue en los perfiles.
        test('avisa con el mismo texto corto que el resto del flujo', () {
          expect(
            hoja(clase),
            contains('avisoEmailCorto'),
            reason: 'sin aviso, el botón se apaga y nadie sabe por qué',
          );
          expect(
            hoja(clase),
            isNot(contains('avisoEmailInvalido')),
            reason: 'volvió el mensaje largo a un campo de esta red',
          );
        });

        // Un campo vacío ya lo bloquea el botón: poner ahí "eso no parece
        // un email" es un regaño gratis antes de que escriba nada.
        test('el aviso solo aparece si escribió algo', () {
          expect(hoja(clase), contains('_emailCtl.text.trim().isNotEmpty &&'));
        });
      });
    }

    test('ninguna de las dos inventó su propio criterio', () {
      expect(
        fuente,
        isNot(contains('RegExp')),
        reason: 'apareció un regex propio en vez de reutilizar esEmailValido',
      );
    });
  });

  // Los casos concretos que pidió Eliza, contra la regla real. Son los
  // mismos que evalúa el `_valido` de las dos hojas.
  group('los casos de la Red, contra esEmailValido', () {
    test(
      'vacío no tiene forma de email (y además el campo es obligatorio)',
      () {
        expect(esEmailValido(''), false);
        expect(esEmailValido('   '), false);
      },
    );

    test('"lunita486@gmail" (sin el punto) queda afuera — el que ya está '
        'guardado en producción', () {
      expect(esEmailValido('lunita486@gmail'), false);
    });

    test('"verdura" queda afuera', () {
      expect(esEmailValido('verdura'), false);
    });

    test('"ana@mail.com" entra', () {
      expect(esEmailValido('ana@mail.com'), true);
    });

    test('y el aviso es exactamente "Email inválido"', () {
      expect(avisoEmailCorto, 'Email inválido');
    });
  });
}
