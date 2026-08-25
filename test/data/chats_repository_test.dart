import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salva_patitas/data/chats_repository.dart';

// fake_cloud_firestore siempre resuelve al toque — para probar que una
// escritura que NUNCA resuelve (sin señal) se corta sola con timeout hace
// falta controlar la respuesta a mano (mismo patrón que
// rescates_repository_test.dart).
class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class MockCollectionReference extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class MockDocumentReference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class MockDocumentSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

class MockWriteBatch extends Mock implements WriteBatch {}

void main() {
  group('ChatsRepository', () {
    late FakeFirebaseFirestore firestore;
    late ChatsRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = ChatsRepository(db: firestore);
    });

    test(
      'idAnimal es el mismo sin importar quién lo pida (rescateId+adoptanteId)',
      () {
        final id1 = repo.idAnimal(rescateId: 'animal-1', adoptanteId: 'user-1');
        final id2 = repo.idAnimal(rescateId: 'animal-1', adoptanteId: 'user-1');
        expect(id1, id2);
      },
    );

    test(
      'idAnimal distingue animales aunque tengan el mismo nombre (este era el bug real)',
      () async {
        // Dos animales llamados "Eduardo" con distinto rescateId nunca deben
        // compartir chat, aunque los publique la misma cuenta.
        final idEduardo1 = repo.idAnimal(
          rescateId: 'rescate-eduardo-1',
          adoptanteId: 'adoptante-1',
        );
        final idEduardo2 = repo.idAnimal(
          rescateId: 'rescate-eduardo-2',
          adoptanteId: 'adoptante-1',
        );
        expect(idEduardo1, isNot(idEduardo2));
      },
    );

    test(
      'asegurarChatAnimal crea el chat con creadoPor y no lo duplica si se llama de nuevo',
      () async {
        final id1 = await repo.asegurarChatAnimal(
          adoptanteId: 'adoptante-1',
          adoptanteNombre: 'Ana',
          rescateId: 'rescate-1',
          rescatistaId: 'rescatista-1',
          rescatista: 'Refugio Norte',
          creadoPor: 'albergue',
          animalNombre: 'Eduardo',
        );
        final id2 = await repo.asegurarChatAnimal(
          adoptanteId: 'adoptante-1',
          adoptanteNombre: 'Ana',
          rescateId: 'rescate-1',
          rescatistaId: 'rescatista-1',
          rescatista: 'Refugio Norte',
          creadoPor: 'albergue',
          animalNombre: 'Eduardo',
        );

        expect(id1, id2);
        final docs = await firestore.collection('chats').get();
        expect(docs.docs.length, 1);
        expect(docs.docs.first['creadoPor'], 'albergue');
      },
    );

    test(
      'asegurarChatAnimal guarda la foto como fotoUrl (Storage), no fotoBase64 — '
      'a diferencia de asegurarChatNegocio, que sigue en base64 (logo del aliado)',
      () async {
        final chatId = await repo.asegurarChatAnimal(
          adoptanteId: 'adoptante-2',
          adoptanteNombre: 'Bea',
          rescateId: 'rescate-2',
          rescatistaId: 'rescatista-2',
          rescatista: 'Refugio Sur',
          creadoPor: 'rescatista',
          fotoUrl: 'https://firebasestorage.googleapis.com/foto.jpg',
        );
        final doc = await firestore.collection('chats').doc(chatId).get();
        expect(
          doc['fotoUrl'],
          'https://firebasestorage.googleapis.com/foto.jpg',
        );
        expect(doc.data()!.containsKey('fotoBase64'), false);
      },
    );

    // campoLogoRescatista / campoLogoAdoptante son LA única fuente de "qué
    // campo de usuarios/{uid} mirar para el logo de negocio de cada lado de
    // un chat". Antes cada pantalla derivaba esto por su cuenta y cada
    // combinación de roles nueva encontraba una pantalla equivocada — tres
    // bugs de "foto equivocada en el chat" en una sola sesión. Derivan de
    // campos que todos los chats tienen desde siempre, así que también
    // cubren los documentos viejos sin migración.
    group('campoLogo* (única fuente del logo por lado, los 4 roles)', () {
      test('chat de animal publicado como albergue: lado dueño → logo de '
          'albergue; lado adoptante → foto personal', () {
        final chat = {'creadoPor': 'albergue'};
        expect(ChatsRepository.campoLogoRescatista(chat), 'fotoBase64');
        expect(ChatsRepository.campoLogoAdoptante(chat), null);
      });

      test('chat de animal publicado como rescatista: ambos lados son '
          'personas, sin logo', () {
        final chat = {'creadoPor': 'rescatista'};
        expect(ChatsRepository.campoLogoRescatista(chat), null);
        expect(ChatsRepository.campoLogoAdoptante(chat), null);
      });

      test('chat de animal legado sin creadoPor ni tipoSolicitud: foto '
          'personal en ambos lados, nunca crashea', () {
        expect(ChatsRepository.campoLogoRescatista({}), null);
        expect(ChatsRepository.campoLogoAdoptante({}), null);
      });

      test('consulta a un aliado: el lado del aliado usa SIEMPRE su logo de '
          'negocio (aliadoFotoBase64), sin importar con qué sombrero lo '
          'contactaron — el bug real: pedía el campo del logo de albergue, '
          'que el aliado no tiene, y caía a la foto personal de la cuenta', () {
        for (final creadoPor in ['albergue', 'rescatista', null]) {
          final chat = <String, dynamic>{
            'tipoSolicitud': 'consulta_aliado',
            'creadoPor': ?creadoPor,
          };
          expect(
            ChatsRepository.campoLogoRescatista(chat),
            'aliadoFotoBase64',
            reason: 'contactado con sombrero: ${creadoPor ?? "adoptante"}',
          );
        }
      });

      test('consulta a un aliado: el lado de quien contactó depende de su '
          'sombrero — albergue muestra su logo, rescatista y adoptante su '
          'foto personal', () {
        expect(
          ChatsRepository.campoLogoAdoptante({
            'tipoSolicitud': 'consulta_aliado',
            'creadoPor': 'albergue',
          }),
          'fotoBase64',
        );
        expect(
          ChatsRepository.campoLogoAdoptante({
            'tipoSolicitud': 'consulta_aliado',
            'creadoPor': 'rescatista',
          }),
          null,
        );
        expect(
          ChatsRepository.campoLogoAdoptante({
            'tipoSolicitud': 'consulta_aliado',
          }),
          null,
        );
      });
    });

    // noLeidosPara es la ÚNICA fuente de "qué campo mirar para saber si ESTE
    // chat tiene mensajes sin leer para quien lo mira" — usada tanto por el
    // contador del panel/badge (contarMensajesSinLeer, theme.dart) como por
    // la lista de Chats (AdoptanteChatsScreen). El bug real que esto evita:
    // las dos pantallas tenían su propia copia de esta lógica, y divergieron
    // (una escondía chats sin vista previa que la otra sí contaba), así que
    // el panel decía "2 mensajes sin leer" que nunca bajaban de dos.
    group('noLeidosPara (única fuente de qué campo cuenta como sin leer)', () {
      test(
        'chat de animal: rescatista mira noLeidosRescatista, adoptante mira noLeidosAdoptante',
        () {
          final chat = {'noLeidosRescatista': 3, 'noLeidosAdoptante': 5};
          expect(
            ChatsRepository.noLeidosPara(chat, uid: 'yo', esRescatista: true),
            3,
          );
          expect(
            ChatsRepository.noLeidosPara(chat, uid: 'yo', esRescatista: false),
            5,
          );
        },
      );

      test(
        'consulta a un aliado: quien mandó la consulta (adoptanteId == uid) mira '
        'noLeidosAdoptante sin importar esRescatista',
        () {
          final chat = {
            'tipoSolicitud': 'consulta_aliado',
            'adoptanteId': 'yo',
            'noLeidosRescatista': 1,
            'noLeidosAdoptante': 7,
          };
          expect(
            ChatsRepository.noLeidosPara(chat, uid: 'yo', esRescatista: true),
            7,
          );
        },
      );

      test(
        'consulta a un aliado: el aliado que la recibió (adoptanteId != uid) mira '
        'noLeidosRescatista',
        () {
          final chat = {
            'tipoSolicitud': 'consulta_aliado',
            'adoptanteId': 'otra-cuenta',
            'noLeidosRescatista': 2,
            'noLeidosAdoptante': 9,
          };
          expect(
            ChatsRepository.noLeidosPara(chat, uid: 'yo', esRescatista: true),
            2,
          );
        },
      );

      test(
        'consulta a un aliado en soloConsultas (bandeja propia del aliado): siempre '
        'noLeidosRescatista, aunque adoptanteId == uid (autoconsulta)',
        () {
          final chat = {
            'tipoSolicitud': 'consulta_aliado',
            'adoptanteId': 'yo',
            'noLeidosRescatista': 4,
            'noLeidosAdoptante': 6,
          };
          expect(
            ChatsRepository.noLeidosPara(
              chat,
              uid: 'yo',
              esRescatista: true,
              soloConsultas: true,
            ),
            4,
          );
        },
      );

      test('chat sin campos de conteo nunca crashea, cuenta 0', () {
        expect(
          ChatsRepository.noLeidosPara({}, uid: 'yo', esRescatista: true),
          0,
        );
      });
    });

    // perteneceALaLista es la única fuente de "¿este chat va en ESTA
    // bandeja?" — antes vivía como un closure inline dentro de
    // AdoptanteChatsScreen._listaChats, sin ningún test directo posible
    // (dependía de FirebaseAuth.instance.currentUser en el medio). Es la
    // pieza que evita que una cuenta con doble rol (rescatista + albergue)
    // vea los chats de un rol mezclados con los del otro — el riesgo real
    // de "mensajería cruzada" que preocupaba a Eliza al auditar los roles.
    group('perteneceALaLista (única fuente de "a qué bandeja pertenece este chat")', () {
      group(
        'chat de animal — separa rescatista de albergue en una cuenta con doble rol',
        () {
          test(
            'rescatista ve sus propios chats de animal (creadoPor rescatista, o legado sin el campo)',
            () {
              for (final chat in [
                {'creadoPor': 'rescatista', 'ultimoMensaje': 'hola'},
                {'ultimoMensaje': 'hola'}, // legado, sin creadoPor
              ]) {
                expect(
                  ChatsRepository.perteneceALaLista(
                    chat,
                    uid: 'yo',
                    esRescatista: true,
                  ),
                  true,
                  reason: 'chat: $chat',
                );
              }
            },
          );

          test(
            'rescatista NO ve los chats de animal creados como albergue de la misma cuenta',
            () {
              final chat = {'creadoPor': 'albergue', 'ultimoMensaje': 'hola'};
              expect(
                ChatsRepository.perteneceALaLista(
                  chat,
                  uid: 'yo',
                  esRescatista: true,
                ),
                false,
              );
            },
          );

          test(
            'albergue ve solo sus propios chats de animal (creadoPor == albergue), no los del rescatista',
            () {
              final propio = {'creadoPor': 'albergue', 'ultimoMensaje': 'hola'};
              final delOtroRol = {
                'creadoPor': 'rescatista',
                'ultimoMensaje': 'hola',
              };
              expect(
                ChatsRepository.perteneceALaLista(
                  propio,
                  uid: 'yo',
                  esRescatista: true,
                  esAlbergue: true,
                ),
                true,
              );
              expect(
                ChatsRepository.perteneceALaLista(
                  delOtroRol,
                  uid: 'yo',
                  esRescatista: true,
                  esAlbergue: true,
                ),
                false,
              );
            },
          );

          test(
            'adoptante ve cualquier chat de animal propio, sin importar creadoPor',
            () {
              final chat = {'creadoPor': 'albergue', 'ultimoMensaje': 'hola'};
              expect(
                ChatsRepository.perteneceALaLista(
                  chat,
                  uid: 'yo',
                  esRescatista: false,
                ),
                true,
              );
            },
          );
        },
      );

      group('consulta a un aliado', () {
        test(
          'bandeja propia del aliado (soloConsultas): cualquier consulta que le llegó, '
          'sin discriminar por adoptanteId ni creadoPor',
          () {
            final chat = {
              'tipoSolicitud': 'consulta_aliado',
              'adoptanteId': 'otra-cuenta',
              'ultimoMensaje': 'hola',
            };
            expect(
              ChatsRepository.perteneceALaLista(
                chat,
                uid: 'yo',
                esRescatista: true,
                soloConsultas: true,
              ),
              true,
            );
          },
        );

        test(
          'adoptante ve las que mandó CON ESE sombrero (sin creadoPor) en su lista general',
          () {
            final chat = {
              'tipoSolicitud': 'consulta_aliado',
              'adoptanteId': 'yo',
              'ultimoMensaje': 'hola',
            };
            expect(
              ChatsRepository.perteneceALaLista(
                chat,
                uid: 'yo',
                esRescatista: false,
              ),
              true,
            );
          },
        );

        test(
          'adoptante NO ve en su lista general una consulta que mandó con sombrero '
          'rescatista/albergue — el bug real: antes cualquiera con creadoPor caía en '
          '"rescatista" por default y se colaba acá',
          () {
            final chat = {
              'tipoSolicitud': 'consulta_aliado',
              'adoptanteId': 'yo',
              'creadoPor': 'rescatista',
              'ultimoMensaje': 'hola',
            };
            expect(
              ChatsRepository.perteneceALaLista(
                chat,
                uid: 'yo',
                esRescatista: false,
              ),
              false,
            );
          },
        );

        test(
          'rescatista/albergue ve en su lista SOLO las consultas que mandó con ESE sombrero',
          () {
            final comoRescatista = {
              'tipoSolicitud': 'consulta_aliado',
              'adoptanteId': 'yo',
              'creadoPor': 'rescatista',
              'ultimoMensaje': 'hola',
            };
            final comoAlbergue = {
              'tipoSolicitud': 'consulta_aliado',
              'adoptanteId': 'yo',
              'creadoPor': 'albergue',
              'ultimoMensaje': 'hola',
            };
            expect(
              ChatsRepository.perteneceALaLista(
                comoRescatista,
                uid: 'yo',
                esRescatista: true,
              ),
              true,
            );
            expect(
              ChatsRepository.perteneceALaLista(
                comoAlbergue,
                uid: 'yo',
                esRescatista: true,
              ),
              false,
              reason:
                  'la mandé como albergue, no debería aparecer en la bandeja de rescatista',
            );
            expect(
              ChatsRepository.perteneceALaLista(
                comoAlbergue,
                uid: 'yo',
                esRescatista: true,
                esAlbergue: true,
              ),
              true,
            );
          },
        );

        test('nadie ve la consulta de OTRA cuenta que no le pertenece', () {
          final chat = {
            'tipoSolicitud': 'consulta_aliado',
            'adoptanteId': 'otra-cuenta',
            'ultimoMensaje': 'hola',
          };
          expect(
            ChatsRepository.perteneceALaLista(
              chat,
              uid: 'yo',
              esRescatista: false,
            ),
            false,
          );
          expect(
            ChatsRepository.perteneceALaLista(
              chat,
              uid: 'yo',
              esRescatista: true,
            ),
            false,
          );
        });
      });

      group(
        'vista previa vacía — no depende de si hay mensaje visible, depende de si hay sin leer',
        () {
          test(
            'se esconde si no tiene vista previa NI mensajes sin leer (chat vacío real)',
            () {
              final chat = {'creadoPor': 'rescatista', 'ultimoMensaje': ''};
              expect(
                ChatsRepository.perteneceALaLista(
                  chat,
                  uid: 'yo',
                  esRescatista: true,
                ),
                false,
              );
            },
          );

          test(
            'NO se esconde si no tiene vista previa pero SÍ tiene mensajes sin leer — '
            'mismo hallazgo real de Eliza que motivó noLeidosPara',
            () {
              final chat = {
                'creadoPor': 'rescatista',
                'ultimoMensaje': '',
                'noLeidosRescatista': 2,
              };
              expect(
                ChatsRepository.perteneceALaLista(
                  chat,
                  uid: 'yo',
                  esRescatista: true,
                ),
                true,
              );
            },
          );
        },
      );
    });

    group('emisorPara (única fuente de qué emisor manda un mensaje '
        'automático — tiene que coincidir con firestore.rules o el mensaje '
        'se rechaza entero). Bug real: enviarMensajeChat y '
        '_avisarAdoptanteFallecido mandaban "rescatista" fijo, así que en '
        'una autoconsulta (adoptanteId == rescatistaId, ej. un albergue '
        'que pidió hogar de paso para su propio animal) la regla rechazaba '
        'el mensaje — pero el chat.update() de la vista previa/"sin leer" '
        'ya había pasado antes, así que el chat quedaba mostrando un '
        'mensaje que en realidad nunca se guardó (hallazgo real: como '
        'adoptante, ver el aviso de vencimiento en la vista previa pero el '
        'chat vacío al abrirlo)', () {
      test(
        'el rescatista/albergue que manda ve su propio mensaje como "rescatista"',
        () {
          expect(
            ChatsRepository.emisorPara(
              adoptanteId: 'adoptante-1',
              miUid: 'rescatista-1',
            ),
            'rescatista',
          );
        },
      );

      test(
        'autoconsulta (adoptanteId == miUid): SIEMPRE "adoptante", aunque quien '
        'manda esté actuando con sombrero de rescatista/albergue',
        () {
          expect(
            ChatsRepository.emisorPara(
              adoptanteId: 'misma-cuenta',
              miUid: 'misma-cuenta',
            ),
            'adoptante',
          );
        },
      );
    });

    group('rolParaRecontactar (única fuente de "con qué sombrero volver a '
        'abrir Contactar desde un chat de consulta ya existente"). Bug '
        'real: sin esto, tocar "Conversando sobre X" y después "Contactar" '
        'de nuevo armaba un chat nuevo con contexto "general", '
        'fragmentando la conversación en un documento aparte del original', () {
      test(
        'quien contactó como albergue conserva el sombrero al recontactar',
        () {
          final rol = ChatsRepository.rolParaRecontactar(
            esRescatistaEnEsteChat: false,
            creadoPor: 'albergue',
          );
          expect(rol.esRescatista, true);
          expect(rol.esAlbergue, true);
        },
      );

      test(
        'quien contactó como rescatista conserva el sombrero al recontactar',
        () {
          final rol = ChatsRepository.rolParaRecontactar(
            esRescatistaEnEsteChat: false,
            creadoPor: 'rescatista',
          );
          expect(rol.esRescatista, true);
          expect(rol.esAlbergue, false);
        },
      );

      test(
        'quien contactó como adoptante puro (sin creadoPor) recontacta igual, sin sombrero',
        () {
          final rol = ChatsRepository.rolParaRecontactar(
            esRescatistaEnEsteChat: false,
            creadoPor: null,
          );
          expect(rol.esRescatista, false);
          expect(rol.esAlbergue, false);
        },
      );

      test('el aliado viendo su propio negocio no hereda ningún sombrero — '
          'no hay conversación previa que preservar en ese sentido', () {
        for (final creadoPor in ['albergue', 'rescatista', null]) {
          final rol = ChatsRepository.rolParaRecontactar(
            esRescatistaEnEsteChat: true,
            creadoPor: creadoPor,
          );
          expect(rol.esRescatista, false, reason: 'creadoPor: $creadoPor');
          expect(rol.esAlbergue, false, reason: 'creadoPor: $creadoPor');
        }
      });
    });

    test(
      'asegurarChatNegocio guarda tipoSolicitud consulta_aliado (el campo que faltaba)',
      () async {
        final chatId = await repo.asegurarChatNegocio(
          adoptanteId: 'adoptante-1',
          adoptanteNombre: 'Ana',
          aliadoId: 'aliado-1',
          aliadoNombre: 'Veterinaria la 30',
        );
        final doc = await firestore.collection('chats').doc(chatId).get();
        expect(doc['tipoSolicitud'], 'consulta_aliado');
        expect(doc['rescatistaId'], 'aliado-1');
      },
    );

    test(
      'idNegocio distingue contexto rescatista vs adoptante para el mismo par de cuentas',
      () {
        final idComoRescatista = repo.idNegocio(
          aliadoId: 'aliado-1',
          adoptanteId: 'user-1',
          contexto: 'rescatista',
        );
        final idComoAdoptante = repo.idNegocio(
          aliadoId: 'aliado-1',
          adoptanteId: 'user-1',
          contexto: 'general',
        );
        expect(idComoRescatista, isNot(idComoAdoptante));
      },
    );

    test(
      'idNegocio también distingue rescatista de albergue (el bug real: se mezclaban '
      'en una sola conversación porque contexto solo distinguía 2 casos, no 3)',
      () {
        final idComoRescatista = repo.idNegocio(
          aliadoId: 'aliado-1',
          adoptanteId: 'user-1',
          contexto: 'rescatista',
        );
        final idComoAlbergue = repo.idNegocio(
          aliadoId: 'aliado-1',
          adoptanteId: 'user-1',
          contexto: 'albergue',
        );
        expect(idComoRescatista, isNot(idComoAlbergue));
      },
    );

    test(
      'asegurarChatNegocio guarda creadoPor cuando contexto es rescatista o albergue, '
      'para que cada uno pueda filtrar su propia bandeja de chats enviados',
      () async {
        final idRescatista = await repo.asegurarChatNegocio(
          adoptanteId: 'user-1',
          adoptanteNombre: 'Ana',
          aliadoId: 'aliado-1',
          aliadoNombre: 'Veterinaria la 30',
          contexto: 'rescatista',
        );
        final idAlbergue = await repo.asegurarChatNegocio(
          adoptanteId: 'user-1',
          adoptanteNombre: 'Ana',
          aliadoId: 'aliado-1',
          aliadoNombre: 'Veterinaria la 30',
          contexto: 'albergue',
        );
        expect(
          (await firestore
              .collection('chats')
              .doc(idRescatista)
              .get())['creadoPor'],
          'rescatista',
        );
        expect(
          (await firestore
              .collection('chats')
              .doc(idAlbergue)
              .get())['creadoPor'],
          'albergue',
        );
      },
    );

    test(
      'asegurarChatNegocio NO guarda creadoPor cuando contexto es general (adoptante)',
      () async {
        final chatId = await repo.asegurarChatNegocio(
          adoptanteId: 'adoptante-1',
          adoptanteNombre: 'Ana',
          aliadoId: 'aliado-1',
          aliadoNombre: 'Veterinaria la 30',
        );
        final doc = await firestore.collection('chats').doc(chatId).get();
        expect(doc.data()!.containsKey('creadoPor'), false);
      },
    );

    test('un chat de consulta recién creado por asegurarChatNegocio produce, '
        'vía campoLogo*, el logo del aliado de un lado y el sombrero real de '
        'quien contactó del otro (integración creación → lectura)', () async {
      final chatId = await repo.asegurarChatNegocio(
        adoptanteId: 'user-1',
        adoptanteNombre: 'Ana',
        aliadoId: 'aliado-1',
        aliadoNombre: 'Veterinaria la 30',
        contexto: 'albergue',
      );
      final d = (await firestore.collection('chats').doc(chatId).get()).data()!;
      expect(ChatsRepository.campoLogoRescatista(d), 'aliadoFotoBase64');
      expect(ChatsRepository.campoLogoAdoptante(d), 'fotoBase64');
    });

    test('asegurarChatNegocio no pisa datos si ya existe el chat', () async {
      final id1 = await repo.asegurarChatNegocio(
        adoptanteId: 'adoptante-1',
        adoptanteNombre: 'Ana',
        aliadoId: 'aliado-1',
        aliadoNombre: 'Veterinaria la 30',
      );
      await firestore.collection('chats').doc(id1).update({
        'ultimoMensaje': 'Hola',
      });

      final id2 = await repo.asegurarChatNegocio(
        adoptanteId: 'adoptante-1',
        adoptanteNombre: 'Ana',
        aliadoId: 'aliado-1',
        aliadoNombre: 'Veterinaria la 30',
      );

      expect(id1, id2);
      final doc = await firestore.collection('chats').doc(id1).get();
      expect(doc['ultimoMensaje'], 'Hola');
    });

    // El bug real que esto arregla: sin señal, un .set()/.get() de Firestore
    // no falla, se queda esperando al servidor para siempre — el
    // try/catch que YA tienen chat_screen.dart, aliado_publico_screen.dart
    // y solicitudes_rescatista_screen.dart nunca llegaba a dispararse
    // porque nunca había ninguna excepción que atrapar. El timeout vive
    // ACÁ ADENTRO (no envuelto desde afuera en cada llamador) para que
    // ningún caller nuevo pueda volver a olvidarse de ponerlo.
    group('timeout — sin señal, no se cuelga para siempre', () {
      setUpAll(() {
        registerFallbackValue(SetOptions(merge: true));
      });

      test('asegurarChatAnimal: si el .set() nunca resuelve, se corta con '
          'TimeoutException en vez de colgarse para siempre', () async {
        final db = MockFirebaseFirestore();
        final col = MockCollectionReference();
        final ref = MockDocumentReference();
        when(() => db.collection('chats')).thenReturn(col);
        when(() => col.doc(any())).thenReturn(ref);
        when(
          () => ref.set(any(), any()),
        ).thenAnswer((_) => Completer<void>().future);

        final repoConMock = ChatsRepository(db: db);
        await expectLater(
          repoConMock.asegurarChatAnimal(
            adoptanteId: 'a',
            adoptanteNombre: 'Ana',
            rescateId: 'r',
            rescatistaId: 'rid',
            rescatista: 'Refugio',
            creadoPor: 'albergue',
            timeout: const Duration(milliseconds: 50),
          ),
          throwsA(isA<TimeoutException>()),
        );
      });

      test('asegurarChatNegocio: si el .get() nunca resuelve, se corta con '
          'TimeoutException — y esa excepción se PROPAGA en vez de tratarse '
          'como "no existe" (un timeout no significa que el chat no exista: '
          'tratarlo así arriesgaba sobrescribir uno real que sí tiene '
          'historial)', () async {
        final db = MockFirebaseFirestore();
        final col = MockCollectionReference();
        final ref = MockDocumentReference();
        when(() => db.collection('chats')).thenReturn(col);
        when(() => col.doc(any())).thenReturn(ref);
        when(() => ref.get()).thenAnswer(
          (_) => Completer<DocumentSnapshot<Map<String, dynamic>>>().future,
        );
        when(() => ref.set(any())).thenAnswer((_) async {});

        final repoConMock = ChatsRepository(db: db);
        await expectLater(
          repoConMock.asegurarChatNegocio(
            adoptanteId: 'a',
            adoptanteNombre: 'Ana',
            aliadoId: 'alid',
            aliadoNombre: 'Veterinaria',
            timeout: const Duration(milliseconds: 50),
          ),
          throwsA(isA<TimeoutException>()),
        );
        // Y no llegó a ejecutar el .set() de "chat nuevo" — nunca se trató
        // como "no existe".
        verifyNever(() => ref.set(any()));
      });

      test(
        'asegurarChatNegocio: un error real del .get() (no permission-denied, '
        'no timeout) SE PROPAGA — antes cualquier error se tapaba como "no '
        'existe" y sobrescribía sin merge un chat que sí existía, borrando su '
        'vista previa de mensaje y sus contadores de no-leídos',
        () async {
          final db = MockFirebaseFirestore();
          final col = MockCollectionReference();
          final ref = MockDocumentReference();
          when(() => db.collection('chats')).thenReturn(col);
          when(() => col.doc(any())).thenReturn(ref);
          when(() => ref.get()).thenThrow(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
          );
          when(() => ref.set(any())).thenAnswer((_) async {});

          final repoConMock = ChatsRepository(db: db);
          await expectLater(
            repoConMock.asegurarChatNegocio(
              adoptanteId: 'a',
              adoptanteNombre: 'Ana',
              aliadoId: 'alid',
              aliadoNombre: 'Veterinaria',
            ),
            throwsA(isA<FirebaseException>()),
          );
          verifyNever(() => ref.set(any()));
        },
      );

      test(
        'asegurarChatNegocio: si el .set() nunca resuelve (chat nuevo), '
        'se corta con TimeoutException en vez de colgarse para siempre',
        () async {
          final db = MockFirebaseFirestore();
          final col = MockCollectionReference();
          final ref = MockDocumentReference();
          when(() => db.collection('chats')).thenReturn(col);
          when(() => col.doc(any())).thenReturn(ref);
          when(() => ref.get()).thenThrow(
            FirebaseException(
              plugin: 'cloud_firestore',
              code: 'permission-denied',
            ),
          );
          when(
            () => ref.set(any()),
          ).thenAnswer((_) => Completer<void>().future);

          final repoConMock = ChatsRepository(db: db);
          await expectLater(
            repoConMock.asegurarChatNegocio(
              adoptanteId: 'a',
              adoptanteNombre: 'Ana',
              aliadoId: 'alid',
              aliadoNombre: 'Veterinaria',
              timeout: const Duration(milliseconds: 50),
            ),
            throwsA(isA<TimeoutException>()),
          );
        },
      );
    });

    Future<void> sembrar(String id, Map<String, dynamic> datos) =>
        firestore.collection('chats').doc(id).set(datos);

    test(
      'mios(esRescatista: true) trae los chats RECIBIDOS (donde esta cuenta '
      'es rescatistaId) y no los que ella misma inició como adoptante',
      () async {
        await sembrar('c1', {'rescatistaId': 'yo', 'adoptanteId': 'otro'});
        await sembrar('c2', {'rescatistaId': 'otro', 'adoptanteId': 'yo'});

        final snap = await repo.mios(uid: 'yo', esRescatista: true).first;

        expect(snap.docs.map((d) => d.id), ['c1']);
      },
    );

    test(
      'mios(esRescatista: false) es la consulta espejo: los chats donde esta '
      'cuenta es el adoptante',
      () async {
        await sembrar('c1', {'rescatistaId': 'yo', 'adoptanteId': 'otro'});
        await sembrar('c2', {'rescatistaId': 'otro', 'adoptanteId': 'yo'});

        final snap = await repo.mios(uid: 'yo', esRescatista: false).first;

        expect(snap.docs.map((d) => d.id), ['c2']);
      },
    );

    test(
      'consultasEnviadas trae solo las consultas a negocios que ESTA cuenta '
      'mandó — el bug real que cubre: un rescatista que le escribe a un aliado '
      'queda como adoptanteId en ese chat (rescatistaId es siempre el aliado), '
      'así que su bandeja, que filtra por rescatistaId, nunca lo encontraba',
      () async {
        await sembrar('consulta', {
          'adoptanteId': 'yo',
          'rescatistaId': 'aliado',
          'tipoSolicitud': 'consulta_aliado',
        });
        await sembrar('animal', {'adoptanteId': 'yo', 'rescatistaId': 'r1'});

        final snap = await repo.consultasEnviadas(uid: 'yo').first;

        expect(snap.docs.map((d) => d.id), ['consulta']);
      },
    );

    test(
      'buscarDeAnimal con rescateId + adoptanteId usa el id determinístico',
      () async {
        await sembrar('resc1_ana', {'animalNombre': 'Luna'});

        final doc = await repo.buscarDeAnimal(
          rescateId: 'resc1',
          adoptanteId: 'ana',
        );

        expect(doc!.id, 'resc1_ana');
      },
    );

    test(
      'buscarDeAnimal devuelve null (no una excepción) si el chat todavía no '
      'existe — leer un chat inexistente da permission-denied con nuestras '
      'reglas, y dejar escapar esa excepción hacía que "Contactar" no hiciera '
      'absolutamente nada',
      () async {
        expect(
          await repo.buscarDeAnimal(rescateId: 'noexiste', adoptanteId: 'ana'),
          isNull,
        );
      },
    );

    test(
      'buscarDeAnimal sin rescateId cae al match por nombre acotado por '
      'adoptante (chats viejos, de antes de que existiera rescateId)',
      () async {
        await sembrar('viejo', {'animalNombre': 'Luna', 'adoptanteId': 'ana'});

        final doc = await repo.buscarDeAnimal(
          animalNombre: 'Luna',
          adoptanteId: 'ana',
        );

        expect(doc!.id, 'viejo');
      },
    );

    test(
      'buscarDeAnimal por nombre también sabe acotar por rescatistaId — es la '
      'variante que usa el panel del rescatista cuando no conoce al adoptante',
      () async {
        await sembrar('mio', {'animalNombre': 'Luna', 'rescatistaId': 'yo'});
        await sembrar('ajeno', {
          'animalNombre': 'Luna',
          'rescatistaId': 'otro',
        });

        final doc = await repo.buscarDeAnimal(
          animalNombre: 'Luna',
          rescatistaId: 'yo',
        );

        expect(doc!.id, 'mio');
      },
    );

    test('buscarDeAnimal NO devuelve el chat de otra persona con un animal del '
        'mismo nombre — acotar por dueño no es cosmético', () async {
      await sembrar('ajeno', {'animalNombre': 'Luna', 'adoptanteId': 'otra'});

      expect(
        await repo.buscarDeAnimal(animalNombre: 'Luna', adoptanteId: 'ana'),
        isNull,
      );
    });

    test(
      'buscarDeAnimal sin datos suficientes (ni id ni nombre) devuelve null en '
      'vez de traer un chat cualquiera',
      () async {
        await sembrar('alguno', {'animalNombre': 'Luna', 'adoptanteId': 'ana'});

        expect(await repo.buscarDeAnimal(), isNull);
      },
    );

    test(
      'buscarDeAnimal con nombre pero SIN ningún dueño con qué acotar devuelve '
      'null — pasa con datos corruptos (una solicitud sin adoptanteId), y una '
      'búsqueda por nombre suelto traería el chat de cualquier otra persona '
      'con un animal así',
      () async {
        await sembrar('ajeno', {'animalNombre': 'Luna', 'adoptanteId': 'otra'});

        expect(await repo.buscarDeAnimal(animalNombre: 'Luna'), isNull);
      },
    );
  });

  group('ChatsRepository — escritura de mensajes (antes duplicada entre '
      'chat_screen._send y enviarMensajeChat)', () {
    late FakeFirebaseFirestore firestore;
    late ChatsRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = ChatsRepository(db: firestore);
    });

    Future<Map<String, dynamic>> chat(String id) async =>
        (await firestore.collection('chats').doc(id).get()).data()!;

    Future<List<Map<String, dynamic>>> mensajesDe(String id) async =>
        (await firestore
                .collection('chats')
                .doc(id)
                .collection('mensajes')
                .get())
            .docs
            .map((d) => d.data())
            .toList();

    test(
      'registrarMensaje deja la vista previa Y el mensaje — el chat queda con '
      'ultimoMensaje/ultimaHora y el mensaje en la subcolección',
      () async {
        await repo.registrarMensaje(
          chatId: 'c1',
          texto: 'Hola',
          emisor: 'adoptante',
          paraAdoptante: false,
        );

        expect((await chat('c1'))['ultimoMensaje'], 'Hola');
        final msgs = await mensajesDe('c1');
        expect(msgs.single['texto'], 'Hola');
        expect(msgs.single['emisor'], 'adoptante');
      },
    );

    test(
      'el primer mensaje de un chat que NO existía lo crea igual — '
      'set(merge:true) en vez de update(), para que no falle con "no '
      'encontrado" cuando el otro lado nunca llegó a crear el chat',
      () async {
        await repo.registrarMensaje(
          chatId: 'nuevo',
          texto: 'Primero',
          emisor: 'rescatista',
          paraAdoptante: true,
        );

        expect((await chat('nuevo'))['ultimoMensaje'], 'Primero');
      },
    );

    test('el contador de no leídos arranca en 1 sin ningún caso especial — '
        'increment(1) sobre un campo que no existe lo deja en 1', () async {
      await repo.registrarMensaje(
        chatId: 'c1',
        texto: 'Hola',
        emisor: 'rescatista',
        paraAdoptante: true,
      );

      expect((await chat('c1'))['noLeidosAdoptante'], 1);
    });

    test('paraAdoptante decide A QUIÉN se le suma el no leído, y no toca el '
        'contador del otro lado', () async {
      await repo.registrarMensaje(
        chatId: 'c1',
        texto: 'a',
        emisor: 'rescatista',
        paraAdoptante: true,
      );
      await repo.registrarMensaje(
        chatId: 'c1',
        texto: 'b',
        emisor: 'rescatista',
        paraAdoptante: true,
      );
      await repo.registrarMensaje(
        chatId: 'c1',
        texto: 'c',
        emisor: 'adoptante',
        paraAdoptante: false,
      );

      final d = await chat('c1');
      expect(d['noLeidosAdoptante'], 2);
      expect(d['noLeidosRescatista'], 1);
    });

    test('avisoParaAmbosLados suma el "sin leer" de LOS DOS lados, no solo el '
        'de paraAdoptante — para avisos automáticos (vencimiento de hogar de '
        'paso, seguimiento post-adopción) que el rescatista/albergue no '
        'disparó a propósito: sin esto quedaban invisibles para él, ni en el '
        'badge ni en el ícono de Chats. Hallazgo real de Eliza: "queda en el '
        'mensaje pero no se da cuenta para nada"', () async {
      await repo.registrarMensaje(
        chatId: 'c1',
        texto: 'Venció el hogar de paso',
        emisor: 'adoptante',
        paraAdoptante: true,
        avisoParaAmbosLados: true,
      );

      final d = await chat('c1');
      expect(d['noLeidosAdoptante'], 1);
      expect(d['noLeidosRescatista'], 1);
    });

    test('avisoParaAmbosLados en false (el default) NO toca el otro lado — '
        'un aviso que sí dispara una acción consciente del rescatista '
        '(aprobar/rechazar una solicitud) no debe marcarle "sin leer" un '
        'mensaje que él mismo generó', () async {
      await repo.registrarMensaje(
        chatId: 'c1',
        texto: 'Tu solicitud fue aprobada',
        emisor: 'adoptante',
        paraAdoptante: true,
      );

      final d = await chat('c1');
      expect(d['noLeidosAdoptante'], 1);
      expect(d['noLeidosRescatista'], null);
    });

    test(
      'camposChat se escriben en la MISMA operación que la vista previa — no '
      'en una escritura aparte, para que un corte no deje el chat a medio '
      'crear (caso de un chat legado que se crea al mandarle el primer '
      'mensaje)',
      () async {
        await repo.registrarMensaje(
          chatId: 'legado',
          texto: 'Hola',
          emisor: 'rescatista',
          paraAdoptante: true,
          camposChat: {'adoptanteId': 'ana', 'animalNombre': 'Luna'},
        );

        final d = await chat('legado');
        expect(d['adoptanteId'], 'ana');
        expect(d['animalNombre'], 'Luna');
        expect(d['ultimoMensaje'], 'Hola');
      },
    );

    test('agregarMensaje escribe SOLO el mensaje, sin tocar la vista previa — '
        'para cuando el chat ya se creó con su preview en el mismo paso '
        '(asegurarChatAnimal con extra)', () async {
      await firestore.collection('chats').doc('c1').set({
        'ultimoMensaje': 'viejo',
      });

      await repo.agregarMensaje(
        chatId: 'c1',
        texto: 'nuevo',
        emisor: 'rescatista',
      );

      expect((await chat('c1'))['ultimoMensaje'], 'viejo');
      expect((await mensajesDe('c1')).single['texto'], 'nuevo');
    });

    test(
      'escritoPorRescatista guarda el SOMBRERO real, aparte de emisor — en una '
      'autoconsulta (la misma cuenta es las dos partes del chat) la regla de '
      'Firestore obliga a que emisor valga siempre "adoptante", así que sin '
      'este campo la pantalla dibujaba TODAS las burbujas del mismo lado y no '
      'se distinguía la respuesta del rescatista. Hallazgo real de Eliza '
      'probando con su cuenta en los dos roles',
      () async {
        await repo.registrarMensaje(
          chatId: 'auto',
          texto: 'respondo como rescatista',
          emisor: 'adoptante', // lo que la regla exige en autoconsulta
          paraAdoptante: true,
          escritoPorRescatista: true, // el sombrero real
        );

        final msg = (await mensajesDe('auto')).single;
        expect(msg['emisor'], 'adoptante', reason: 'la regla sigue satisfecha');
        expect(
          msg['escritoPorRescatista'],
          true,
          reason: 'y el sombrero se guarda',
        );
      },
    );

    test(
      'sin escritoPorRescatista el campo NO se escribe — los mensajes viejos no '
      'lo tienen y se siguen dibujando por emisor, igual que antes',
      () async {
        await repo.registrarMensaje(
          chatId: 'c1',
          texto: 'hola',
          emisor: 'adoptante',
          paraAdoptante: false,
        );

        expect(
          (await mensajesDe('c1')).single.containsKey('escritoPorRescatista'),
          false,
        );
      },
    );

    test('agregarMensaje también lo guarda — es el camino de los avisos '
        'automáticos (aprobar/rechazar una solicitud), que los manda siempre el '
        'rescatista', () async {
      await repo.agregarMensaje(
        chatId: 'c1',
        texto: 'Tu solicitud fue aprobada',
        emisor: 'adoptante',
        escritoPorRescatista: true,
      );

      expect((await mensajesDe('c1')).single['escritoPorRescatista'], true);
    });

    test('marcarLeido pone en cero SOLO el lado que abrió el chat', () async {
      await firestore.collection('chats').doc('c1').set({
        'noLeidosAdoptante': 3,
        'noLeidosRescatista': 5,
      });

      await repo.marcarLeido(chatId: 'c1', esRescatista: true);

      final d = await chat('c1');
      expect(d['noLeidosRescatista'], 0);
      expect(d['noLeidosAdoptante'], 3);
    });

    test(
      'marcarLeido sobre un chat que no existe no lanza — es best-effort, el '
      'peor caso es un badge que sigue mostrando un número, nunca vale romper '
      'la pantalla por eso',
      () async {
        await expectLater(
          repo.marcarLeido(chatId: 'noexiste', esRescatista: false),
          completes,
        );
      },
    );

    test(
      'horaAhora formatea con minutos de 2 dígitos — estaba calculado a mano '
      'en los 2 lugares que escriben mensajes',
      () {
        expect(ChatsRepository.horaAhora(DateTime(2026, 1, 1, 14, 5)), '14:05');
        expect(ChatsRepository.horaAhora(DateTime(2026, 1, 1, 9, 30)), '9:30');
      },
    );

    test('mensajes() los devuelve del más viejo al más nuevo', () async {
      await repo.registrarMensaje(
        chatId: 'c1',
        texto: 'primero',
        emisor: 'adoptante',
        paraAdoptante: false,
      );
      await repo.registrarMensaje(
        chatId: 'c1',
        texto: 'segundo',
        emisor: 'adoptante',
        paraAdoptante: false,
      );

      final snap = await repo.mensajes('c1').first;

      expect(snap.docs.map((d) => d.data()['texto']), ['primero', 'segundo']);
    });
  });

  // Auditoría de arquitectura, riesgo 🟡 "contador de sin leer denormalizado,
  // sin reconciliación": antes registrarMensaje() hacía un .set() del chat
  // (vista previa + contador) y DESPUÉS un .add() del mensaje, como dos
  // llamadas separadas — si el proceso moría entre una y otra, el contador
  // quedaba incrementado sin que el mensaje existiera de verdad, un "sin
  // leer" fantasma para siempre. Ahora las dos van en el mismo WriteBatch,
  // que Firestore confirma entero o nada. fake_cloud_firestore no puede
  // simular un corte real a mitad de un commit (no hay mitad de camino que
  // observar), así que estas pruebas verifican lo que SÍ se puede verificar
  // desde acá: que las dos escrituras viajan en el mismo batch (no dos
  // llamadas independientes), y que si el batch falla, la falla se propaga
  // completa — nunca queda un estado a medio escribir para reconciliar.
  group('_escribirChatYMensaje (interna, usada por registrarMensaje y '
      'avisarSobreAnimal) — las dos escrituras van atómicas', () {
    setUpAll(() {
      registerFallbackValue(SetOptions(merge: true));
    });

    test('registrarMensaje pide UN batch a Firestore y mete ahí las dos '
        'escrituras (chat + mensaje), en vez de dos llamadas .set()/.add() '
        'independientes', () async {
      final db = MockFirebaseFirestore();
      final col = MockCollectionReference();
      final chatRef = MockDocumentReference();
      final mensajesCol = MockCollectionReference();
      final mensajeRef = MockDocumentReference();
      final batch = MockWriteBatch();
      when(() => db.collection('chats')).thenReturn(col);
      when(() => col.doc(any())).thenReturn(chatRef);
      when(() => chatRef.collection('mensajes')).thenReturn(mensajesCol);
      when(() => mensajesCol.doc()).thenReturn(mensajeRef);
      when(() => db.batch()).thenReturn(batch);
      when(() => batch.set(chatRef, any(), any())).thenReturn(batch);
      when(() => batch.set(mensajeRef, any())).thenReturn(batch);
      when(() => batch.commit()).thenAnswer((_) async {});

      final repoConMock = ChatsRepository(db: db);
      await repoConMock.registrarMensaje(
        chatId: 'c1',
        texto: 'hola',
        emisor: 'adoptante',
        paraAdoptante: true,
      );

      // Un solo batch pedido y confirmado — si esto usara dos llamadas
      // .set()/.add() independientes (como antes), db.batch() nunca se
      // llamaría. mensajesCol.doc() (sin argumento) es cómo se genera el id
      // del mensaje SIN escribir nada todavía — recién el batch.commit()
      // manda las dos escrituras juntas al servidor.
      verify(() => db.batch()).called(1);
      verify(() => mensajesCol.doc()).called(1);
      verify(() => batch.commit()).called(1);
    });

    test('si el commit del batch falla, la excepción se propaga tal cual — '
        'no queda ningún estado a mitad de camino que reconciliar después, '
        'porque con WriteBatch ninguna de las dos escrituras llegó a '
        'aplicarse', () async {
      final db = MockFirebaseFirestore();
      final col = MockCollectionReference();
      final chatRef = MockDocumentReference();
      final mensajesCol = MockCollectionReference();
      final mensajeRef = MockDocumentReference();
      final batch = MockWriteBatch();
      when(() => db.collection('chats')).thenReturn(col);
      when(() => col.doc(any())).thenReturn(chatRef);
      when(() => chatRef.collection('mensajes')).thenReturn(mensajesCol);
      when(() => mensajesCol.doc()).thenReturn(mensajeRef);
      when(() => db.batch()).thenReturn(batch);
      when(() => batch.set(chatRef, any(), any())).thenReturn(batch);
      when(() => batch.set(mensajeRef, any())).thenReturn(batch);
      when(() => batch.commit()).thenThrow(Exception('sin señal'));

      final repoConMock = ChatsRepository(db: db);
      await expectLater(
        repoConMock.registrarMensaje(
          chatId: 'c1',
          texto: 'hola',
          emisor: 'adoptante',
          paraAdoptante: true,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('avisarSobreAnimal() — ÚNICA fuente de "avisar automáticamente por '
      'chat" para toda la app. Antes existía dos veces con comportamiento '
      'DISTINTO: una creaba el chat si hacía falta, la otra no — y esa '
      'diferencia dejaba sin ningún aviso a un adoptante con una solicitud '
      'todavía PENDIENTE (sin chat abierto todavía) cuando el animal moría. '
      'Hallazgo real de Eliza: pidió adoptar, el rescatista marcó el animal '
      'como fallecido, y nunca le llegó nada', () {
    late FakeFirebaseFirestore firestore;
    late ChatsRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = ChatsRepository(db: firestore);
    });

    // Aprobar o rechazar hacía DOS cosas que notifican: cambiaba el
    // estado de la solicitud (onCambioEstadoSolicitud → push) y escribía
    // el mensaje del aviso (onNuevoMensaje → otra push). Llegaban las dos,
    // con textos distintos, por un solo hecho. La marca deja que el
    // servidor se saltee la segunda.
    test('avisoDeEstado marca el mensaje para que el servidor no mande la '
        'push repetida', () async {
      await repo.avisarSobreAnimal(
        adoptanteId: 'ana',
        adoptanteNombre: 'Ana',
        rescatistaId: 'refugio1',
        rescatista: 'Refugio Uno',
        texto: '✅ ¡Tu solicitud de adopción fue aprobada!',
        rescateId: 'r1',
        animalNombre: 'Rocky',
        avisoDeEstado: true,
      );

      final msgs = await firestore
          .collection('chats')
          .doc('r1_ana')
          .collection('mensajes')
          .get();
      expect(msgs.docs.single.data()['avisoDeEstado'], isTrue);
    });

    // Un mensaje normal NO lleva la marca: si la llevara, el servidor
    // dejaría de avisar de los mensajes de verdad — el bug opuesto, y
    // mucho peor que una notificación de más.
    test('un mensaje común NO queda marcado', () async {
      await repo.avisarSobreAnimal(
        adoptanteId: 'ana',
        adoptanteNombre: 'Ana',
        rescatistaId: 'refugio1',
        rescatista: 'Refugio Uno',
        texto: '¿Cómo se está adaptando Rocky?',
        rescateId: 'r1',
        animalNombre: 'Rocky',
      );

      final msgs = await firestore
          .collection('chats')
          .doc('r1_ana')
          .collection('mensajes')
          .get();
      expect(msgs.docs.single.data().containsKey('avisoDeEstado'), isFalse);
    });

    test('sin chat previo: LO CREA y deja el mensaje adentro — el caso real '
        'que fallaba: una solicitud recién mandada, nunca aprobada, no '
        'siempre tiene un chat abierto todavía', () async {
      final ok = await repo.avisarSobreAnimal(
        adoptanteId: 'ana',
        adoptanteNombre: 'Ana',
        rescatistaId: 'refugio1',
        rescatista: 'Refugio Uno',
        texto: 'Lamentamos informarte que Rocky falleció.',
        rescateId: 'r1',
        animalNombre: 'Rocky',
      );

      expect(ok, isTrue);
      final chatId = 'r1_ana'; // idAnimal(rescateId, adoptanteId)
      final chat = (await firestore.collection('chats').doc(chatId).get())
          .data()!;
      expect(chat['adoptanteId'], 'ana');
      expect(chat['rescatistaId'], 'refugio1');
      expect(
        chat['ultimoMensaje'],
        'Lamentamos informarte que Rocky falleció.',
      );
      final msgs = await firestore
          .collection('chats')
          .doc(chatId)
          .collection('mensajes')
          .get();
      expect(
        msgs.docs.single.data()['texto'],
        'Lamentamos informarte que Rocky falleció.',
      );
    });

    test(
      'con chat previo: NO crea uno nuevo, escribe en el que ya existía',
      () async {
        await firestore.collection('chats').doc('r1_ana').set({
          'adoptanteId': 'ana',
          'rescatistaId': 'refugio1',
          'rescateId': 'r1',
          'ultimoMensaje': 'charla anterior',
        });

        final ok = await repo.avisarSobreAnimal(
          adoptanteId: 'ana',
          adoptanteNombre: 'Ana',
          rescatistaId: 'refugio1',
          rescatista: 'Refugio Uno',
          texto: 'Lamentamos informarte que Rocky falleció.',
          rescateId: 'r1',
          animalNombre: 'Rocky',
        );

        expect(ok, isTrue);
        // Sigue siendo UN solo chat, no dos.
        expect((await firestore.collection('chats').get()).docs.length, 1);
        final msgs = await firestore
            .collection('chats')
            .doc('r1_ana')
            .collection('mensajes')
            .get();
        expect(
          msgs.docs.single.data()['texto'],
          'Lamentamos informarte que Rocky falleció.',
        );
      },
    );

    test('avisoParaAmbosLados también le suma "sin leer" al rescatista, '
        'incluso al crear el chat de cero', () async {
      await repo.avisarSobreAnimal(
        adoptanteId: 'ana',
        adoptanteNombre: 'Ana',
        rescatistaId: 'refugio1',
        rescatista: 'Refugio Uno',
        texto: 'aviso',
        rescateId: 'r1',
        animalNombre: 'Rocky',
        avisoParaAmbosLados: true,
      );

      final chat = (await firestore.collection('chats').doc('r1_ana').get())
          .data()!;
      expect(chat['noLeidosAdoptante'], 1);
      expect(chat['noLeidosRescatista'], 1);
    });
  });

  group('esMiBurbuja() — de qué lado se dibuja cada mensaje. La regla que más '
      'veces se rompió: "todos los mensajes se ven del mismo lado", encontrada '
      'por separado en chats de animal y en consultas a un negocio. Vivía '
      'inline en el widget, sin test posible', () {
    // ── Chat normal (dos personas distintas) ───────────────────────────────
    test('chat entre dos personas: manda `emisor`, que es la autoridad — mi '
        'propio mensaje va a mi lado', () {
      expect(
        ChatsRepository.esMiBurbuja(
          {'emisor': 'adoptante'},
          miEmisor: 'adoptante',
          esRescatista: false,
          esAutoconsulta: false,
        ),
        isTrue,
      );
    });

    test('chat entre dos personas: el mensaje del otro va del otro lado', () {
      expect(
        ChatsRepository.esMiBurbuja(
          {'emisor': 'rescatista'},
          miEmisor: 'adoptante',
          esRescatista: false,
          esAutoconsulta: false,
        ),
        isFalse,
      );
    });

    test('chat entre dos personas: `escritoPorRescatista` se IGNORA aunque '
        'venga — fuera de autoconsulta `emisor` es lo único infalsificable, y '
        'confiar en el otro campo dejaría mandar un mensaje marcado como si lo '
        'hubiera escrito el otro', () {
      expect(
        ChatsRepository.esMiBurbuja(
          // Un mensaje del rescatista que MIENTE diciendo que lo escribió el
          // adoptante: se sigue dibujando según emisor, del lado del otro.
          {'emisor': 'rescatista', 'escritoPorRescatista': false},
          miEmisor: 'adoptante',
          esRescatista: false,
          esAutoconsulta: false,
        ),
        isFalse,
      );
    });

    // ── Autoconsulta (la misma cuenta es las dos partes) ───────────────────
    test('AUTOCONSULTA vista como adoptante: lo que escribí como adoptante va '
        'a mi lado', () {
      expect(
        ChatsRepository.esMiBurbuja(
          // emisor SIEMPRE es 'adoptante' acá, lo exige la regla.
          {'emisor': 'adoptante', 'escritoPorRescatista': false},
          miEmisor: 'adoptante',
          esRescatista: false,
          esAutoconsulta: true,
        ),
        isTrue,
      );
    });

    test(
      'AUTOCONSULTA vista como adoptante: la respuesta que escribí con el '
      'sombrero de rescatista va del OTRO lado — el bug exacto que reportó '
      'Eliza ("los 3 últimos son del rescatista y todos están a la derecha")',
      () {
        expect(
          ChatsRepository.esMiBurbuja(
            {'emisor': 'adoptante', 'escritoPorRescatista': true},
            miEmisor: 'adoptante',
            esRescatista: false,
            esAutoconsulta: true,
          ),
          isFalse,
        );
      },
    );

    test('AUTOCONSULTA vista como rescatista: se invierte — lo que escribí con '
        'ese sombrero va a mi lado, y lo del adoptante al otro', () {
      expect(
        ChatsRepository.esMiBurbuja(
          {'emisor': 'adoptante', 'escritoPorRescatista': true},
          miEmisor: 'adoptante',
          esRescatista: true,
          esAutoconsulta: true,
        ),
        isTrue,
      );
      expect(
        ChatsRepository.esMiBurbuja(
          {'emisor': 'adoptante', 'escritoPorRescatista': false},
          miEmisor: 'adoptante',
          esRescatista: true,
          esAutoconsulta: true,
        ),
        isFalse,
      );
    });

    test('AUTOCONSULTA con un mensaje VIEJO (sin escritoPorRescatista): cae al '
        'camino de `emisor`. No se puede hacer otra cosa con ese dato — es por '
        'esto que los chats viejos se siguen viendo mal aunque el arreglo esté '
        'puesto, y por eso hay que probar con mensajes nuevos', () {
      expect(
        ChatsRepository.esMiBurbuja(
          {'emisor': 'adoptante'},
          miEmisor: 'adoptante',
          esRescatista: true,
          esAutoconsulta: true,
        ),
        isTrue,
      );
    });

    test('los avisos automáticos (aprobar/rechazar, "falleció") se guardan con '
        'escritoPorRescatista: true, así que en autoconsulta caen del lado del '
        'rescatista y no del adoptante — el punto 8 del checklist', () {
      final aviso = {'emisor': 'adoptante', 'escritoPorRescatista': true};
      // Mirando como adoptante: el aviso NO es mío, viene del otro lado.
      expect(
        ChatsRepository.esMiBurbuja(
          aviso,
          miEmisor: 'adoptante',
          esRescatista: false,
          esAutoconsulta: true,
        ),
        isFalse,
      );
      // Mirando como rescatista: sí es mío, yo lo generé al aprobar/rechazar.
      expect(
        ChatsRepository.esMiBurbuja(
          aviso,
          miEmisor: 'adoptante',
          esRescatista: true,
          esAutoconsulta: true,
        ),
        isTrue,
      );
    });
  });
}
