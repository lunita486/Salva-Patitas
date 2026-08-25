import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/data/creator_role.dart';

void main() {
  group('creatorRoleFromFirestore()', () {
    test("'albergue' da CreatorRole.albergue", () {
      expect(creatorRoleFromFirestore('albergue'), CreatorRole.albergue);
    });

    test("'rescatista' da CreatorRole.rescatista", () {
      expect(creatorRoleFromFirestore('rescatista'), CreatorRole.rescatista);
    });

    test(
      'null da CreatorRole.rescatista — documentos viejos, de antes de que '
      'este campo existiera, se tratan como rescatista porque esa era la '
      'única variante posible en ese momento',
      () {
        expect(creatorRoleFromFirestore(null), CreatorRole.rescatista);
      },
    );
  });

  group(
    'esRescateDeAlbergue() — única fuente de esta pregunta para toda la UI '
    'que decide si un rescate puntual muestra su propio campo de ubicación '
    '(la hereda del perfil del albergue) o no',
    () {
      test("creadoPor 'albergue' → true", () {
        expect(esRescateDeAlbergue({'creadoPor': 'albergue'}), true);
      });

      test("creadoPor 'rescatista' → false", () {
        expect(esRescateDeAlbergue({'creadoPor': 'rescatista'}), false);
      });

      test('sin creadoPor (rescate viejo) → false, mismo criterio que '
          'creatorRoleFromFirestore', () {
        expect(esRescateDeAlbergue({}), false);
      });
    },
  );

  group(
    'esCreadoPorAlbergue() — lo mismo que esRescateDeAlbergue() pero para '
    'cuando ya se tiene el valor de creadoPor a mano (no el documento '
    'entero). Consolida una comparación que vivía repetida a mano en '
    '6+ archivos (chat_screen.dart, chats_repository.dart, '
    'adoptante_feed_screen.dart, y otros) — hallazgo de auditoría, '
    'disparado por el bug real de "La Perla" (una copia DISTINTA de esta '
    'misma familia, en UsuariosRepository.nombrePropioParaAnimal)',
    () {
      test("'albergue' → true", () {
        expect(esCreadoPorAlbergue('albergue'), true);
      });

      test("'rescatista' → false", () {
        expect(esCreadoPorAlbergue('rescatista'), false);
      });

      test('null → false, mismo criterio que creatorRoleFromFirestore', () {
        expect(esCreadoPorAlbergue(null), false);
      });

      test(
        'esRescateDeAlbergue() y esCreadoPorAlbergue() dan la MISMA '
        'respuesta para el mismo dato — son la misma fuente de verdad, '
        'una solo recibe el mapa entero y la otra el campo ya extraído',
        () {
          for (final creadoPor in ['albergue', 'rescatista', null, 'x']) {
            expect(
              esRescateDeAlbergue({'creadoPor': creadoPor}),
              esCreadoPorAlbergue(creadoPor),
            );
          }
        },
      );
    },
  );

  group(
    'rotuloDeQuienContacto() — con qué sombrero te escribió alguien a tu '
    'negocio aliado. Consolidada porque esta MISMA cadena de condiciones '
    'vivía copiada en chat_screen.dart y en aliado_home_screen.dart: dos '
    'pantallas que le muestran el mismo dato al mismo aliado sobre la '
    'misma conversación, y que por lo tanto no pueden contestar distinto.',
    () {
      test('contactó como albergue', () {
        expect(rotuloDeQuienContacto('albergue'), 'Albergue');
      });

      test('contactó como rescatista', () {
        expect(rotuloDeQuienContacto('rescatista'), 'Rescatista');
      });

      // `creadoPor` SOLO se guarda cuando alguien escribe con rol de
      // rescatista o albergue (ver ChatsRepository.asegurarChatNegocio) —
      // su ausencia significa "me escribió como adoptante", no "es un
      // dato viejo que hay que asumir rescatista". Es justo al revés que
      // creatorRoleFromFirestore(), y confundir las dos fue un bug real:
      // una consulta mandada como adoptante aparecía en la bandeja del
      // rescatista.
      test('sin creadoPor: contactó como adoptante, NO como rescatista', () {
        expect(rotuloDeQuienContacto(null), 'Adoptante');
      });

      test('creadoPor vacío también es adoptante', () {
        expect(rotuloDeQuienContacto(''), 'Adoptante');
      });

      test('un valor inesperado no revienta: cae en adoptante', () {
        expect(rotuloDeQuienContacto('cualquier_cosa'), 'Adoptante');
      });
    },
  );
}
