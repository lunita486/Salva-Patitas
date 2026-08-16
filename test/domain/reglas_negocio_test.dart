import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/domain/reglas_negocio.dart';

void main() {
  group('contarMensajesSinLeer() — auditoría de reglas de negocio '
      '(2026-08-06): "que no pase lo de los 11 animales rescatados que no '
      'era real"', () {
    late FakeFirebaseFirestore firestore;
    const uid = 'mi-uid';

    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> agregar(
      List<Map<String, dynamic>> docs,
    ) async {
      for (final d in docs) {
        await firestore.collection('chats').add(d);
      }
      return (await firestore.collection('chats').get()).docs;
    }

    test(
      'suma lo recibido (chats de animal) y lo enviado (consultas a un '
      'aliado) — antes solo miraba lo recibido, así que una respuesta a '
      'una consulta que la propia cuenta le mandó a un negocio aliado '
      'nunca se contaba, aunque sí apareciera en la lista de Chats',
      () async {
        final todos = await agregar([
          {
            'rescatistaId': uid,
            'creadoPor': 'rescatista',
            'noLeidosRescatista': 2,
          },
          {
            'adoptanteId': uid,
            'tipoSolicitud': 'consulta_aliado',
            'creadoPor': 'rescatista',
            'noLeidosRescatista': 1,
          },
        ]);
        final recibidos = todos
            .where((d) => d.data()['rescatistaId'] == uid)
            .toList();
        final enviados = todos
            .where((d) => d.data()['tipoSolicitud'] == 'consulta_aliado')
            .toList();

        final n = contarMensajesSinLeer(
          recibidos: recibidos,
          consultasEnviadas: enviados,
          esAlbergue: false,
          uid: uid,
        );

        expect(n, 1); // solo el chat recibido — la consulta enviada de este
        // doc no cuenta: quien mandó la consulta (adoptanteId == uid) mira
        // noLeidosAdoptante, no noLeidosRescatista (ver noLeidosPara,
        // chats_repository.dart) — este doc de prueba no tiene ese campo.
      },
    );

    test('suma lo recibido (chats de animal) y lo enviado (consultas a un '
        'aliado) usando el campo correcto de cada lado — antes solo miraba '
        'lo recibido, así que una respuesta a una consulta que la propia '
        'cuenta le mandó a un negocio aliado nunca se contaba, aunque sí '
        'apareciera en la lista de Chats', () async {
      final todos = await agregar([
        {
          'rescatistaId': uid,
          'creadoPor': 'rescatista',
          'noLeidosRescatista': 2,
        },
        {
          'adoptanteId': uid,
          'tipoSolicitud': 'consulta_aliado',
          'creadoPor': 'rescatista',
          'noLeidosAdoptante': 1,
        },
      ]);
      final recibidos = todos
          .where((d) => d.data()['rescatistaId'] == uid)
          .toList();
      final enviados = todos
          .where((d) => d.data()['tipoSolicitud'] == 'consulta_aliado')
          .toList();

      final n = contarMensajesSinLeer(
        recibidos: recibidos,
        consultasEnviadas: enviados,
        esAlbergue: false,
        uid: uid,
      );

      expect(n, 2); // 1 chat recibido + 1 consulta enviada, no 1
    });

    test('una consulta a un aliado recibida (rescatistaId == uid, soy el '
        'negocio) NO se mezcla con los chats de animal — le pertenece al '
        'badge propio del aliado, no a este', () async {
      final todos = await agregar([
        {
          'rescatistaId': uid,
          'tipoSolicitud': 'consulta_aliado',
          'creadoPor': 'rescatista',
          'noLeidosRescatista': 5,
        },
      ]);

      final n = contarMensajesSinLeer(
        recibidos: todos,
        consultasEnviadas: const [],
        esAlbergue: false,
        uid: uid,
      );

      expect(n, 0);
    });

    test('una consulta enviada con OTRO sombrero (albergue) no cuenta para '
        'el badge de rescatista, y viceversa', () async {
      final todos = await agregar([
        {
          'adoptanteId': uid,
          'tipoSolicitud': 'consulta_aliado',
          'creadoPor': 'albergue',
          'noLeidosAdoptante': 3,
        },
      ]);

      expect(
        contarMensajesSinLeer(
          recibidos: const [],
          consultasEnviadas: todos,
          esAlbergue: false,
          uid: uid,
        ),
        0,
      );
      expect(
        contarMensajesSinLeer(
          recibidos: const [],
          consultasEnviadas: todos,
          esAlbergue: true,
          uid: uid,
        ),
        1,
      );
    });

    test('una consulta enviada como adoptante puro (sin creadoPor) no '
        'cuenta para ningún lado — no es ni rescatista ni albergue', () async {
      final todos = await agregar([
        {
          'adoptanteId': uid,
          'tipoSolicitud': 'consulta_aliado',
          'noLeidosAdoptante': 4,
        },
      ]);

      expect(
        contarMensajesSinLeer(
          recibidos: const [],
          consultasEnviadas: todos,
          esAlbergue: false,
          uid: uid,
        ),
        0,
      );
      expect(
        contarMensajesSinLeer(
          recibidos: const [],
          consultasEnviadas: todos,
          esAlbergue: true,
          uid: uid,
        ),
        0,
      );
    });

    test('sin nada sin leer, da 0 — no explota con listas nulas o vacías', () {
      expect(
        contarMensajesSinLeer(
          recibidos: null,
          consultasEnviadas: null,
          esAlbergue: false,
          uid: uid,
        ),
        0,
      );
    });

    // Regresión directa del bug real que reportó Eliza: el panel decía "2
    // mensajes sin leer" pero el ícono de Chats y la lista de conversaciones
    // no mostraban ninguno. Pasaba con un chat de animal cuya vista previa
    // (`ultimoMensaje`) había quedado vacía mientras `noLeidosRescatista`
    // seguía en positivo — contarMensajesSinLeer nunca miró `ultimoMensaje`,
    // así que lo seguía contando, pero AdoptanteChatsScreen sí lo escondía
    // por tener la vista previa vacía. Esta prueba fija el comportamiento
    // correcto: el conteo no depende de si hay vista previa, solo de si hay
    // mensajes sin leer — así, si la lista alguna vez vuelve a ocultar un
    // chat "sin preview", este número se mantiene como la fuente de verdad
    // a la que la lista tiene que ponerse de acuerdo (ver
    // ChatsRepository.noLeidosPara, la función que ambos comparten).
    test(
      'cuenta un chat con mensajes sin leer aunque su vista previa '
      '(ultimoMensaje) esté vacía — el conteo no depende de la preview',
      () async {
        final todos = await agregar([
          {
            'rescatistaId': uid,
            'creadoPor': 'rescatista',
            'ultimoMensaje': '',
            'noLeidosRescatista': 2,
          },
        ]);

        final n = contarMensajesSinLeer(
          recibidos: todos,
          consultasEnviadas: const [],
          esAlbergue: false,
          uid: uid,
        );

        expect(n, 1);
      },
    );
  });

  group('cuentaComoEnCuidado() — única fuente de "% de ocupación" del '
      'albergue. Bug real que esto arregla: antes copiado a mano en el '
      'panel del albergue y en el filtro "En cuidado" de mis_rescates_'
      'screen.dart — "regresaron 2 animalitos y la app seguía mostrando 1"', () {
    test('Rescatado y Regresado cuentan', () {
      expect(cuentaComoEnCuidado('Rescatado'), true);
      expect(cuentaComoEnCuidado('Regresado'), true);
    });

    test(
      'Hogar de paso NO cuenta — libera capacidad real aunque seas responsable',
      () {
        expect(cuentaComoEnCuidado('Hogar de paso'), false);
      },
    );

    test('Adoptado y Fallecido no cuentan', () {
      expect(cuentaComoEnCuidado('Adoptado'), false);
      expect(cuentaComoEnCuidado('Fallecido'), false);
    });

    test('sin estadoAdopcion (dato legado) asume Rescatado, cuenta', () {
      expect(cuentaComoEnCuidado(null), true);
    });
  });

  group('esEstancado()/esEstancadoGrave() — única fuente del filtro '
      '"Estancados" y el aviso de la tarjeta, antes copiados a mano por '
      'separado en mis_rescates_screen.dart', () {
    test('cuenta como estancado justo al llegar al umbral (no antes)', () {
      expect(
        esEstancado(diasEsperando: 30, estadoAdopcion: 'Rescatado', umbral: 30),
        true,
      );
      expect(
        esEstancado(diasEsperando: 29, estadoAdopcion: 'Rescatado', umbral: 30),
        false,
      );
    });

    test('Rescatado, Hogar de paso y Regresado cuentan — Regresado es el caso '
        'más urgente, ya falló una vez en encontrar hogar definitivo', () {
      for (final estado in ['Rescatado', 'Hogar de paso', 'Regresado']) {
        expect(
          esEstancado(diasEsperando: 40, estadoAdopcion: estado, umbral: 30),
          true,
          reason: estado,
        );
      }
    });

    test(
      'Adoptado y Fallecido no cuentan como estancados aunque pasen los días',
      () {
        expect(
          esEstancado(
            diasEsperando: 40,
            estadoAdopcion: 'Adoptado',
            umbral: 30,
          ),
          false,
        );
        expect(
          esEstancado(
            diasEsperando: 40,
            estadoAdopcion: 'Fallecido',
            umbral: 30,
          ),
          false,
        );
      },
    );

    test(
      'sin diasEsperando (dato legado sin creadoEn) nunca cuenta, no crashea',
      () {
        expect(
          esEstancado(
            diasEsperando: null,
            estadoAdopcion: 'Rescatado',
            umbral: 30,
          ),
          false,
        );
      },
    );

    test('esEstancadoGrave recién es true al doble del umbral', () {
      expect(esEstancadoGrave(diasEsperando: 59, umbral: 30), false);
      expect(esEstancadoGrave(diasEsperando: 60, umbral: 30), true);
    });

    test('esEstancadoGrave con diasEsperando null no crashea, da false', () {
      expect(esEstancadoGrave(diasEsperando: null, umbral: 30), false);
    });
  });

  group('whatsappUrl()', () {
    test('vacío o solo espacios da null', () {
      expect(whatsappUrl(''), isNull);
      expect(whatsappUrl('   '), isNull);
    });

    test('celular colombiano de 10 dígitos sin +57: se le antepone 57', () {
      expect(whatsappUrl('300 123 4567'), 'https://wa.me/573001234567');
    });

    test('fijo colombiano de 10 dígitos (prefijo 60, ej. un fijo de '
        'Medellín) sin +57: también se le antepone 57 — el bug real: antes '
        'solo se cubría el caso celular, así que un fijo tecleado tal como '
        'lo sugiere el propio campo armaba un link roto', () {
      expect(whatsappUrl('604 444 4444'), 'https://wa.me/576044444444');
    });

    test('ya viene con un indicativo (formato que arma CampoTelefono, o '
        'alguien que ya había puesto el suyo a mano): se usa tal cual, sin '
        'inventarle un 57 que no le corresponde', () {
      expect(whatsappUrl('+52 55 1234 5678'), 'https://wa.me/525512345678');
    });

    test('tolera espacios, guiones y paréntesis sueltos', () {
      expect(whatsappUrl('(300) 123-4567'), 'https://wa.me/573001234567');
    });

    // Regresión de esta misma sesión: un celular cubano (indicativo 53 +
    // 8 dígitos) o un fijo panameño (indicativo 507 + 7 dígitos) TAMBIÉN
    // dan 10 dígitos en total — la adivinanza de "10 dígitos sin + =
    // colombiano" los agarraba igual que a un número viejo sin país,
    // aunque la persona hubiera elegido bien su país en CampoTelefono.
    test('un celular cubano con indicativo (53 + 8 dígitos = 10 en total) '
        'NO se confunde con un número colombiano sin indicativo', () {
      expect(whatsappUrl('+53 12345678'), 'https://wa.me/5312345678');
    });

    test('un fijo panameño con indicativo (507 + 7 dígitos = 10 en total) '
        'NO se confunde con un número colombiano sin indicativo', () {
      expect(whatsappUrl('+507 1234567'), 'https://wa.me/5071234567');
    });
  });

  group('tiempoRelativo() — antes copiada byte a byte en '
      'solicitudes_preview.dart y solicitudes_rescatista_screen.dart, sin '
      'nada que avisara si una cambiaba de la otra (hallazgo de auditoría '
      'de código, 2026-08-16)', () {
    test('menos de 60 minutos: "hace Xmin"', () {
      final hace5min = DateTime.now().subtract(const Duration(minutes: 5));
      expect(tiempoRelativo(hace5min), 'hace 5min');
    });

    test('entre 1 y 24 horas: "hace Xh"', () {
      final hace3h = DateTime.now().subtract(const Duration(hours: 3));
      expect(tiempoRelativo(hace3h), 'hace 3h');
    });

    test('24 horas o más: "hace Xd"', () {
      final hace2d = DateTime.now().subtract(const Duration(days: 2));
      expect(tiempoRelativo(hace2d), 'hace 2d');
    });
  });
}
