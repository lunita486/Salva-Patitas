import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/data/rescates_repository.dart';
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

  group(
    'esEmailValido() — bloquea el guardado del perfil de Aliado, mismo '
    'criterio que ya tiene la ciudad geocodificada del mismo perfil. '
    'Hallazgo real de Eliza: "sjejdj" se guardaba igual que un email de '
    'verdad',
    () {
      test('un email con forma real es válido', () {
        expect(esEmailValido('contacto@negocio.com'), true);
      });

      test('espacios alrededor no lo invalidan (se recorta antes)', () {
        expect(esEmailValido('  contacto@negocio.com  '), true);
      });

      test('sin arroba es inválido', () {
        expect(esEmailValido('sjejdj'), false);
      });

      test('sin dominio (nada después de la arroba) es inválido', () {
        expect(esEmailValido('contacto@'), false);
      });

      test('sin punto en el dominio es inválido', () {
        expect(esEmailValido('contacto@negociocom'), false);
      });

      test('vacío es inválido — el llamador decide si eso bloquea o no, '
          'acá no es su trabajo (email es opcional, un campo vacío es '
          'válido para GUARDAR, no para "tiene forma de email")', () {
        expect(esEmailValido(''), false);
      });
    },
  );

  group(
    'esSitioWebValido() — mismo criterio que esEmailValido(), para "Página '
    'web". Hallazgo real de Eliza: "sjejdj" también pasaba acá',
    () {
      test('un dominio simple, sin esquema, es válido (lo que sugiere el '
          'propio campo: "www.tunegocio.com")', () {
        expect(esSitioWebValido('www.tunegocio.com'), true);
      });

      test('con esquema (http o https) también es válido', () {
        expect(esSitioWebValido('https://tunegocio.com'), true);
        expect(esSitioWebValido('http://tunegocio.com'), true);
      });

      test('con una ruta después del dominio también es válido', () {
        expect(esSitioWebValido('tunegocio.com/contacto'), true);
      });

      test('sin ningún punto es inválido', () {
        expect(esSitioWebValido('sjejdj'), false);
      });

      // ── El TLD demasiado largo para ser real ────────────────────────
      //
      // "www.casitahogar" y "a.djsfdsf" pasaban: los dos tienen forma de
      // dominio y su última parte es solo letras, así que la regla anterior
      // (solo letras, mínimo 2) los daba por buenos. Sintácticamente son
      // indistinguibles de "tunegocio.com"; lo único que los separa es que
      // "casitahogar" y "djsfdsf" son demasiado largos para ser un dominio
      // de primer nivel. Hallazgo real de Eliza en el perfil del albergue y
      // en el del aliado.
      test('escribir el nombre del negocio en vez del TLD es inválido', () {
        expect(esSitioWebValido('www.casitahogar'), false);
        expect(esSitioWebValido('a.djsfdsf'), false);
      });

      test('los TLD que se usan de verdad siguen siendo válidos', () {
        for (final tld in [
          'com', 'co', 'org', 'net', 'es', 'ar', 'mx', 'de', 'io', 'app',
          'vet', 'pet', 'online', 'travel', 'museum',
        ]) {
          expect(
            esSitioWebValido('tunegocio.$tld'),
            true,
            reason: '.$tld quedó afuera y es un dominio real',
          );
        }
      });

      test('un dominio compuesto sigue valiendo: manda el último segmento', () {
        expect(esSitioWebValido('www.casitahogar.com.co'), true);
      });

      test('el corte es por LARGO, no por una lista de dominios', () {
        // Un TLD inventado pero corto pasa, y está bien que pase: una lista
        // de dominios válidos se desactualizaría sola y bloquearía a quien
        // escribió bien. Acá se prefiere aceptar de más antes que rechazar
        // de más — lo peor que pasa si se cuela es que el enlace no abra.
        expect(esSitioWebValido('tunegocio.zzz'), true);
      });

      test('vacío es inválido — mismo criterio que esEmailValido(): el '
          'llamador decide si un campo opcional vacío bloquea el guardado, '
          'acá solo se responde si TIENE forma de sitio web', () {
        expect(esSitioWebValido(''), false);
      });

      test(
        'un TLD con números es inválido, aunque tenga forma de dominio — '
        'ningún dominio de primer nivel real (.com, .org, .co...) lleva '
        'números. Hallazgo real de Eliza probando el perfil del aliado: '
        '"www.veterinariola30" pasaba porque SÍ tiene forma de dominio '
        '(palabra.palabra), pero "la30" no puede ser un TLD real',
        () {
          expect(esSitioWebValido('www.veterinariola30'), false);
        },
      );

      test(
        'un TLD real con números en el nombre ANTES del punto sigue '
        'siendo válido — el chequeo es solo sobre el último segmento',
        () {
          expect(esSitioWebValido('www.tunegocio24horas.com'), true);
        },
      );

      test('un TLD compuesto (.com.co) sigue siendo válido', () {
        expect(esSitioWebValido('www.tunegocio.com.co'), true);
      });

      test('un TLD de una sola letra es inválido — no existen TLDs de '
          'menos de 2 caracteres', () {
        expect(esSitioWebValido('tunegocio.c'), false);
      });
    },
  );

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

  group(
    'formatearFecha() — "15 jul" o "15 jul 2026" según conAnio. El '
    'contrato importante NO es esta función (nunca cambió), es que quien '
    'la llama con una fecha de vida larga (la de ingreso de un animal, no '
    'un timestamp de chat) decida conAnio comparando contra el año '
    'actual, no fijándolo en `false` para siempre — hallazgo real de '
    'Eliza: "el año que viene, ¿cómo distingo una fecha vieja?". Sin esa '
    'comparación, un animal ingresado el año pasado se ve idéntico a uno '
    'de ayer. mis_rescates_screen.dart y albergue_home_screen.dart tenían '
    'exactamente ese bug (conAnio: false fijo); chat_screen.dart ya lo '
    'hacía bien y es el criterio que las otras dos copiaron.',
    () {
      test('conAnio:true (el default) agrega el año', () {
        expect(formatearFecha(DateTime(2026, 7, 15)), '15 jul 2026');
      });

      test('conAnio:false lo omite', () {
        expect(
          formatearFecha(DateTime(2026, 7, 15), conAnio: false),
          '15 jul',
        );
      });

      test(
        'el patrón correcto para una fecha de vida larga: comparar el año '
        'de la fecha contra el año ACTUAL, no contra un valor fijo — año '
        'igual al de hoy, sin año en el texto',
        () {
          final hoy = DateTime.now();
          final mismoAnio = DateTime(hoy.year, 3, 10);
          expect(
            formatearFecha(mismoAnio, conAnio: mismoAnio.year != hoy.year),
            '10 mar',
          );
        },
      );

      test(
        'mismo patrón, año DISTINTO al actual: sí muestra el año — es la '
        'diferencia real entre el bug ("18 ago" para siempre) y el '
        'arreglo ("18 ago 2026" una vez que estemos en 2027)',
        () {
          final hoy = DateTime.now();
          final anioPasado = DateTime(hoy.year - 1, 8, 18);
          expect(
            formatearFecha(anioPasado, conAnio: anioPasado.year != hoy.year),
            '18 ago ${hoy.year - 1}',
          );
        },
      );
    },
  );

  group(
    'sePuedeAdoptar() — el feed de adopción y Favoritos contestaban esta '
    'MISMA pregunta con dos listas de estados escritas a mano, y se '
    'contradecían en "Hogar de paso": el mismo animal salía adoptable en '
    'el feed y "ya no disponible" en Favoritos.',
    () {
      test('recién publicado (Rescatado) se puede adoptar', () {
        expect(sePuedeAdoptar('Rescatado'), true);
      });

      test('sin estado guardado (dato viejo) cuenta como Rescatado', () {
        expect(sePuedeAdoptar(null), true);
      });

      test('Regresado se puede adoptar — de hecho es el más urgente', () {
        expect(sePuedeAdoptar('Regresado'), true);
      });

      // EL caso de la contradicción. Un hogar de paso es temporal,
      // justamente mientras el animal espera adopción definitiva — y
      // cuentaComoEnCuidado() ya lo trata así al no contarlo como
      // capacidad ocupada del albergue.
      test('Hogar de paso SÍ se puede adoptar (acá se contradecían)', () {
        expect(sePuedeAdoptar('Hogar de paso'), true);
      });

      test('En proceso de adopción NO — ya hay alguien esperando', () {
        expect(sePuedeAdoptar('En proceso de adopción'), false);
      });

      test('Adoptado NO', () {
        expect(sePuedeAdoptar('Adoptado'), false);
      });

      test('Fallecido NO', () {
        expect(sePuedeAdoptar('Fallecido'), false);
      });
    },
  );

  group(
    'servicioEstaActivo() — se contestaba de dos formas: `== true` en el '
    'perfil público y en el contador, `?? true` en la lista propia del '
    'aliado. Un servicio sin el campo se veía activo para su dueño pero '
    'era invisible para los clientes.',
    () {
      test('activo: true está activo', () {
        expect(servicioEstaActivo({'activo': true}), true);
      });

      test('activo: false NO está activo (apagarlo es explícito)', () {
        expect(servicioEstaActivo({'activo': false}), false);
      });

      // El caso que divergía: un servicio creado antes de que existiera
      // el campo. Gana "activo" — se publicó y nunca se apagó a propósito.
      test('sin el campo (servicio viejo) está activo', () {
        expect(servicioEstaActivo({'nombre': 'Baño'}), true);
      });
    },
  );

  group(
    'diasHastaVencimiento / hogarDePasoVencido — el panel del rescatista '
    'comparaba CON hora y "Mis solicitudes" solo por fecha. Como la fecha '
    'de fin se guarda a medianoche, el día del vencimiento el adoptante '
    'leía "vence hoy" mientras al rescatista la app ya le había mandado '
    '"ha vencido, coordiná la devolución".',
    () {
      final ahora = DateTime(2026, 8, 24, 15, 30);

      test('vence dentro de 3 días', () {
        expect(
          diasHastaVencimiento(fechaFin: DateTime(2026, 8, 27), ahora: ahora),
          3,
        );
      });

      test('vence mañana', () {
        expect(
          diasHastaVencimiento(fechaFin: DateTime(2026, 8, 25), ahora: ahora),
          1,
        );
      });

      // EL caso donde diferían. La fecha de fin llega a medianoche, y son
      // las 15:30 — con hora, `fechaFin.isAfter(ahora)` daba false y el
      // rescatista ya lo veía vencido.
      test('vence HOY: da 0, y NO está vencido todavía', () {
        final hoy = DateTime(2026, 8, 24);
        expect(diasHastaVencimiento(fechaFin: hoy, ahora: ahora), 0);
        expect(hogarDePasoVencido(fechaFin: hoy, ahora: ahora), false);
      });

      test('venció ayer: negativo, y sí está vencido', () {
        final ayer = DateTime(2026, 8, 23);
        expect(diasHastaVencimiento(fechaFin: ayer, ahora: ahora), -1);
        expect(hogarDePasoVencido(fechaFin: ayer, ahora: ahora), true);
      });

      test('la hora del día no cambia el resultado — a las 00:01 y a las '
          '23:59 del mismo día, un período que vence hoy sigue sin vencer', () {
        final hoy = DateTime(2026, 8, 24);
        expect(
          hogarDePasoVencido(
            fechaFin: hoy,
            ahora: DateTime(2026, 8, 24, 0, 1),
          ),
          false,
        );
        expect(
          hogarDePasoVencido(
            fechaFin: hoy,
            ahora: DateTime(2026, 8, 24, 23, 59),
          ),
          false,
        );
      });
    },
  );

  group(
    'coordenadasDe() — el feed leía las coordenadas con `as double?` y sin '
    'descartar (0,0), mientras el servicio de ubicación ya rechazaba (0,0) '
    'al guardar. El guard estaba solo del lado de la escritura.',
    () {
      test('coordenadas normales se devuelven tal cual', () {
        final c = coordenadasDe({'latitud': 6.24, 'longitud': -75.58});
        expect(c?.lat, 6.24);
        expect(c?.lng, -75.58);
      });

      // El caso que Eliza vio: "Se encuentra a 8875.1 km de ti" en un
      // animal sin ubicación. (0,0) es lo que devuelve Android cuando el
      // GPS todavía no tiene lectura.
      test('(0,0) NO es una ubicación: devuelve null', () {
        expect(coordenadasDe({'latitud': 0, 'longitud': 0}), isNull);
      });

      test('sin coordenadas guardadas: null', () {
        expect(coordenadasDe({'nombre': 'Toby'}), isNull);
        expect(coordenadasDe({'latitud': 6.24}), isNull);
      });

      // Una coordenada legítima PUEDE tener un cero: el meridiano de
      // Greenwich y el ecuador existen. Solo el par (0,0) es basura.
      test('un solo cero sí es válido (Greenwich, el ecuador)', () {
        expect(coordenadasDe({'latitud': 51.47, 'longitud': 0})?.lng, 0);
        expect(coordenadasDe({'latitud': 0, 'longitud': -78.5})?.lat, 0);
      });

      // El trigger del servidor serializa los enteros de JS como enteros,
      // y `as double?` sobre un entero revienta — llevándose puesta la
      // pestaña Adoptar entera, porque el orden por distancia corre dentro
      // del builder de la lista.
      test('una coordenada guardada como ENTERO no revienta', () {
        final c = coordenadasDe({'latitud': 6, 'longitud': -75});
        expect(c?.lat, 6.0);
        expect(c?.lng, -75.0);
      });
    },
  );

  group(
    'nombreDeAnimal() — la misma pregunta se respondía en 7 lugares con 4 '
    'respuestas distintas, dos de ellas dentro de la MISMA pantalla.',
    () {
      test('con nombre: lo devuelve tal cual', () {
        expect(nombreDeAnimal('Pacolin'), 'Pacolin');
        expect(nombreDeAnimal('Pacolin', enFrase: true), 'Pacolin');
      });

      test('sin nombre: un solo texto para títulos', () {
        expect(nombreDeAnimal(null), 'Sin nombre');
        expect(nombreDeAnimal(''), 'Sin nombre');
        expect(nombreDeAnimal('   '), 'Sin nombre');
      });

      // "Para Sin nombre" no se lee como español. Caso real reportado.
      test('sin nombre, dentro de una frase: otro texto', () {
        expect(nombreDeAnimal(null, enFrase: true), 'un animalito');
        expect(nombreDeAnimal('', enFrase: true), 'un animalito');
      });

      // El texto de pantalla se coló a la base: una pantalla copió a
      // `solicitudes` el nombre ya resuelto en vez del dato real.
      test('el literal "Sin nombre" GUARDADO cuenta como no tener nombre', () {
        expect(nombreDeAnimal('Sin nombre', enFrase: true), 'un animalito');
        expect(nombreDeAnimal('Sin nombre'), 'Sin nombre');
      });

      // Un animal que de verdad se llama así no debe caer en el caso de
      // arriba: la comparación es exacta, no "contiene".
      test('un nombre que solo se PARECE al placeholder se respeta', () {
        expect(nombreDeAnimal('Sin nombre aún'), 'Sin nombre aún');
      });
    },
  );

  group(
    'sePuedeSerHogarDePaso() — el panel "¿cómo querés ayudar?" decidía esto '
    'con una comparación escrita a mano, y ofrecía dos de las tres formas '
    'de ayudar: faltaba justo Adoptar.',
    () {
      test('un animalito disponible admite las dos cosas', () {
        for (final estado in ['Rescatado', 'Regresado', null]) {
          expect(sePuedeAdoptar(estado), isTrue, reason: '$estado');
          expect(sePuedeSerHogarDePaso(estado), isTrue, reason: '$estado');
        }
      });

      // El matiz que se leía mal escrito a mano: quien ya lo tiene en hogar
      // de paso puede querer quedárselo, así que Adoptar SÍ. Pero ofrecerle
      // otro hogar de paso encima no tiene sentido.
      test('ya en hogar de paso: se adopta, pero no se le da otro hogar', () {
        expect(sePuedeAdoptar('Hogar de paso'), isTrue);
        expect(sePuedeSerHogarDePaso('Hogar de paso'), isFalse);
      });

      // Lo que NO puede pasar: que el panel ofrezca hogar de paso sobre un
      // animalito que ni siquiera está disponible. Se define SOBRE
      // sePuedeAdoptar justamente para que esto sea imposible por
      // construcción, no por acordarse.
      test('si no se puede adoptar, tampoco se puede dar hogar de paso', () {
        for (final estado in [
          'En proceso de adopción',
          'Adoptado',
          'Fallecido',
        ]) {
          expect(sePuedeAdoptar(estado), isFalse, reason: '$estado');
          expect(sePuedeSerHogarDePaso(estado), isFalse, reason: '$estado');
        }
      });

      // Y la invariante entera, para que no haga falta acordarse de sumar
      // el caso nuevo acá si mañana se agrega un estado.
      test('nunca hay hogar de paso sin adopción posible', () {
        for (final estado in [
          'Rescatado', 'Regresado', 'Hogar de paso',
          'En proceso de adopción', 'Adoptado', 'Fallecido', null, 'inventado',
        ]) {
          if (sePuedeSerHogarDePaso(estado)) {
            expect(sePuedeAdoptar(estado), isTrue, reason: '$estado');
          }
        }
      });
    },
  );

  // ── No quedar trabada después de tocar "No, corregir" ──────────────────
  //
  // Los perfiles de Aliado y de Albergue preguntaban esto mismo con su
  // propia condición escrita a mano. Las dos tienen dos patas: "cambió el
  // texto" O "este perfil viene de antes de que la validación existiera".
  // La segunda es la delicada: NO se apaga sola cuando el texto vuelve al
  // original, hay que apagarla a propósito al cancelar.
  //
  // Albergue se acordaba. Aliado no. En Aliado, tocar "No, corregir" te
  // dejaba trabada: el segundo "Guardar" volvía a pedir la ciudad, y el
  // tercero también, sin forma de guardar el nombre o el teléfono que sí
  // habías cambiado. Hallazgo real de Eliza probando las dos seguidas.
  group('hayQueVerificarCiudadDePerfil', () {
    test('una ciudad nueva se verifica', () {
      expect(
        hayQueVerificarCiudadDePerfil(
          ciudad: 'Bogotá',
          original: 'Medellín',
          yaVerificada: true,
          seRechazoEnEstaPantalla: false,
        ),
        isTrue,
      );
    });

    test('la misma ciudad ya verificada no se vuelve a preguntar', () {
      expect(
        hayQueVerificarCiudadDePerfil(
          ciudad: 'Medellín',
          original: 'Medellín',
          yaVerificada: true,
          seRechazoEnEstaPantalla: false,
        ),
        isFalse,
      );
    });

    test('un perfil viejo sin verificar sí se pregunta, aunque no cambie', () {
      expect(
        hayQueVerificarCiudadDePerfil(
          ciudad: 'Medellín',
          original: 'Medellín',
          yaVerificada: false,
          seRechazoEnEstaPantalla: false,
        ),
        isTrue,
      );
    });

    // EL test de esta sesión: el estado exacto en el que queda la pantalla
    // después de tocar "No, corregir". Si esto vuelve a dar true, se
    // reintrodujo el bucle que dejaba a Eliza sin poder guardar nada.
    test('después de cancelar, el siguiente Guardar NO vuelve a preguntar', () {
      expect(
        hayQueVerificarCiudadDePerfil(
          ciudad: 'Medellín', // ya revertida al original por el cancelar
          original: 'Medellín',
          yaVerificada: false, // sigue sin verificarse de verdad
          seRechazoEnEstaPantalla: true, // y eso es lo que lo destraba
        ),
        isFalse,
        reason: 'si esto es true, no se puede guardar nada nunca más',
      );
    });

    // Pero rechazarla no la vuelve válida: si después escribe OTRA ciudad,
    // esa sí hay que verificarla.
    test('haber cancelado no deja pasar una ciudad nueva sin verificar', () {
      expect(
        hayQueVerificarCiudadDePerfil(
          ciudad: 'cordoba',
          original: 'Medellín',
          yaVerificada: false,
          seRechazoEnEstaPantalla: true,
        ),
        isTrue,
      );
    });

    test('una ciudad vacía no se verifica: la ubicación es opcional', () {
      expect(
        hayQueVerificarCiudadDePerfil(
          ciudad: '   ',
          original: 'Medellín',
          yaVerificada: false,
          seRechazoEnEstaPantalla: false,
        ),
        isFalse,
      );
    });
  });

  // ── Borrar la ubicación tiene que borrarla de verdad ───────────────────
  //
  // Eliza guardó a "Lindurita" borrándole la ubicación. En el feed salía sin
  // pin y sin bandera (correcto, no hay ciudad) pero decía "se encuentra a
  // 2 m de ti". Los 2 metros eran las coordenadas viejas, de donde ella misma
  // había publicado el animalito: el guardado escribía la ciudad vacía pero
  // NO tocaba latitud/longitud, y un update que no menciona un campo no lo
  // borra.
  group('ubicacionParaGuardar', () {
    test('sin ciudad, se borran también las coordenadas y el país', () {
      final campos = ubicacionParaGuardar(
        ciudad: '',
        latitud: 6.24,
        longitud: -75.58,
        paisCodigo: 'CO',
      );
      expect(campos['ubicacion'], '');
      expect(campos['latitud'], isNull);
      expect(campos['longitud'], isNull);
      expect(campos['paisCodigo'], '');
    });

    // Lo que de verdad importa: que las claves ESTÉN. Omitirlas es lo que
    // dejaba el dato viejo vivo en la base.
    test('las claves se escriben, no se omiten', () {
      final campos = ubicacionParaGuardar(
        ciudad: '   ',
        latitud: 6.24,
        longitud: -75.58,
        paisCodigo: 'CO',
      );
      expect(campos.keys, containsAll(['latitud', 'longitud', 'paisCodigo']));
    });

    test('con ciudad, van los tres datos del mismo punto', () {
      final campos = ubicacionParaGuardar(
        ciudad: '  Medellín ',
        latitud: 6.24,
        longitud: -75.58,
        paisCodigo: 'CO',
      );
      expect(campos['ubicacion'], 'Medellín');
      expect(campos['latitud'], 6.24);
      expect(campos['longitud'], -75.58);
      expect(campos['paisCodigo'], 'CO');
    });

    // Una ciudad escrita a mano que el mapa no pudo ubicar: se guarda el
    // nombre y no se inventan coordenadas, pero tampoco se pisan las que
    // pudiera haber.
    test('con ciudad pero sin coordenadas, no se escriben nulos', () {
      final campos = ubicacionParaGuardar(
        ciudad: 'Medellín',
        latitud: null,
        longitud: null,
        paisCodigo: '',
      );
      expect(campos['ubicacion'], 'Medellín');
      expect(campos.containsKey('latitud'), isFalse);
      expect(campos.containsKey('paisCodigo'), isFalse);
    });
  });

  // ── La lista de estados y el predicado no pueden divergir ──────────────
  //
  // Las listas de "mis rescates" ahora se piden paginadas y filtradas del
  // lado del servidor, así que la CONSULTA necesita los mismos estados que
  // el predicado usa en Dart. Si alguien agrega un estado a la lista y se
  // olvida del predicado (o al revés), el filtro empieza a mostrar cosas
  // distintas de las que dice mostrar, y en una lista paginada eso es
  // invisible: parece que simplemente no hay más animales.
  group('estados: la lista manda, el predicado la usa', () {
    test('cuentaComoEnCuidado acepta exactamente estadosEnCuidado', () {
      for (final e in estadosEnCuidado) {
        expect(cuentaComoEnCuidado(e), isTrue, reason: '$e debería contar');
      }
      for (final e in RescatesRepository.estados) {
        expect(
          cuentaComoEnCuidado(e),
          estadosEnCuidado.contains(e),
          reason: 'el predicado y la lista discrepan en "$e"',
        );
      }
    });

    test('un estado ausente cuenta como recién publicado', () {
      expect(cuentaComoEnCuidado(null), isTrue);
    });

    test('esEstancado acepta exactamente estadosQuePuedenEstancarse', () {
      for (final e in estadosQuePuedenEstancarse) {
        expect(
          esEstancado(diasEsperando: 99, estadoAdopcion: e, umbral: 30),
          isTrue,
          reason: '$e debería poder estancarse',
        );
      }
      for (final e in ['Adoptado', 'Fallecido', 'En proceso de adopción']) {
        expect(
          esEstancado(diasEsperando: 99, estadoAdopcion: e, umbral: 30),
          isFalse,
          reason: '$e NO debería aparecer en Estancados',
        );
      }
    });

    test('el umbral sigue mandando por encima del estado', () {
      expect(
        esEstancado(diasEsperando: 5, estadoAdopcion: 'Rescatado', umbral: 30),
        isFalse,
      );
    });
  });
}
