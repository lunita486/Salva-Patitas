import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/screens/editar_rescate_screen.dart';

void main() {
  group(
    'descripcionSinNombreDePlantillaVieja() — migra al formato nuevo (sin '
    'nombre repetido) las descripciones publicadas antes de ese cambio. '
    'Hallazgo real de Eliza: editó "lino" (antes "Hermoso") y la '
    'descripción seguía "Hermoso fue encontrado/a...".',
    () {
      test(
        'la descripción tiene la plantilla vieja intacta (con el nombre '
        'adelante): le saca el nombre',
        () {
          final resultado = descripcionSinNombreDePlantillaVieja(
            descripcion:
                'Hermoso fue encontrado/a en la calle. Lo hace único su '
                'ronroneo.',
            nombreOriginal: 'Hermoso',
          );
          expect(
            resultado,
            'Fue encontrado/a en la calle. Lo hace único su ronroneo.',
          );
        },
      );

      test(
        'da igual si el nombre cambió o no en este guardado — se migra '
        'en cualquier caso, con tal de que la plantilla siga intacta',
        () {
          final resultado = descripcionSinNombreDePlantillaVieja(
            descripcion: 'loquito fue encontrado/a en la calle.',
            nombreOriginal: 'loquito',
          );
          expect(resultado, 'Fue encontrado/a en la calle.');
        },
      );

      test(
        'la persona reescribió la descripción a mano (ya no empieza con '
        'la plantilla): no toca nada, aunque el nombre viejo aparezca en '
        'otra parte del texto — mejor no arriesgar un recorte equivocado '
        'en medio de una frase real',
        () {
          final resultado = descripcionSinNombreDePlantillaVieja(
            descripcion:
                'Un gatito precioso. Antes se llamaba loquito pero ya no.',
            nombreOriginal: 'loquito',
          );
          expect(
            resultado,
            'Un gatito precioso. Antes se llamaba loquito pero ya no.',
          );
        },
      );

      test(
        'una descripción que ya está en el formato nuevo (sin nombre) '
        'queda igual — no hay nada que migrar',
        () {
          final resultado = descripcionSinNombreDePlantillaVieja(
            descripcion: 'Fue encontrado/a en la calle.',
            nombreOriginal: 'loquito',
          );
          expect(resultado, 'Fue encontrado/a en la calle.');
        },
      );

      test(
        'descripción vacía o de un animal sin plantilla: no rompe, '
        'devuelve tal cual',
        () {
          final resultado = descripcionSinNombreDePlantillaVieja(
            descripcion: '',
            nombreOriginal: 'loquito',
          );
          expect(resultado, '');
        },
      );

      test(
        'nombreOriginal vacío (animal que nunca tuvo nombre): no intenta '
        'sacar nada',
        () {
          final resultado = descripcionSinNombreDePlantillaVieja(
            descripcion: ' fue encontrado/a en la calle.',
            nombreOriginal: '',
          );
          expect(resultado, ' fue encontrado/a en la calle.');
        },
      );
    },
  );

  group(
    'hayQueResolverCiudad() — cuándo aparece la lista de ciudades. Antes la '
    'lista salía recién al tocar Guardar, así que elegir una de la lista '
    'era, sin que se notara, aceptar el guardado entero: la pantalla se '
    'cerraba y volvías a Mis rescates. Hallazgo real de Eliza en Medellín.',
    () {
      test('escribió algo distinto: hay que verificarlo', () {
        expect(
          hayQueResolverCiudad(
            texto: 'Medellín Antioquia',
            original: 'Los Olivos',
            tocadaAMano: true,
          ),
          isTrue,
        );
      });

      // Resolver de más pisa lo que la persona escribió, y se siente como
      // "siempre me lo reemplaza".
      test('no tocó el campo: no se toca nada', () {
        expect(
          hayQueResolverCiudad(
            texto: 'Los Olivos',
            original: 'Los Olivos',
            tocadaAMano: false,
          ),
          isFalse,
        );
      });

      test('escribió lo mismo que ya estaba: el mapa ya lo confirmó', () {
        expect(
          hayQueResolverCiudad(
            texto: 'Medellín',
            original: 'Medellín',
            tocadaAMano: true,
          ),
          isFalse,
        );
      });

      test('y los espacios no lo hacen parecer distinto', () {
        expect(
          hayQueResolverCiudad(
            texto: '  Medellín  ',
            original: 'Medellín',
            tocadaAMano: true,
          ),
          isFalse,
        );
      });

      // Hay animalitos sin ubicación, y borrarla tiene que poder hacerse.
      // Antes un campo vacío bloqueaba el guardado entero: hallazgo real de
      // Eliza editando un animalito sin ciudad.
      test('lo dejó vacío: es válido, no hay nada que resolver', () {
        expect(
          hayQueResolverCiudad(
            texto: '',
            original: 'Medellín',
            tocadaAMano: true,
          ),
          isFalse,
        );
        expect(
          hayQueResolverCiudad(
            texto: '   ',
            original: 'Medellín',
            tocadaAMano: true,
          ),
          isFalse,
        );
      });

      // Resolver de menos deja guardar un texto que el mapa nunca confirmó,
      // y entonces el animalito dice una ciudad y aparece en otra.
      test('un animalito que no tenía ciudad y ahora sí: se verifica', () {
        expect(
          hayQueResolverCiudad(
            texto: 'Medellín',
            original: '',
            tocadaAMano: true,
          ),
          isTrue,
        );
      });
    },
  );
}
