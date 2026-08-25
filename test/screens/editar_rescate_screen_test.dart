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
}
