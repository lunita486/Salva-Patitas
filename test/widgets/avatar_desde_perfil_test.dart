import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/widgets/avatares.dart';

/// El avatar de quien publicó sale del documento del perfil, no de una copia
/// adentro de cada animalito.
///
/// **El problema.** Cada animalito llevaba `rescatistaFotoBase64`: una copia
/// del logo del albergue, en base64, de ~85 KB. Medido contra producción, la
/// primera página del perfil público de un albergue pesaba 2,7 MB, de los
/// cuales 2,6 MB (el 98,9%) eran el MISMO logo repetido 31 veces. Eliza:
/// "al entrar, la información de esos animalitos tarda mucho en aparecer".
///
/// Ahora el feed usa `AvatarUsuario`, que lee `usuarios/{uid}`. Para que eso
/// no se convierta en una lectura por tarjeta —y como el logo vive en ese
/// documento, cada lectura cuesta los mismos 85 KB— el widget memoriza el
/// DOCUMENTO por uid.
///
/// **Qué prueba este archivo y qué no.** `AvatarUsuario` habla con
/// `FirebaseFirestore.instance` directamente, y ningún widget del proyecto
/// acepta una base inyectable, así que acá no se puede montar el camino
/// completo contra `fake_cloud_firestore`. Se prueba: el widget de pintado
/// (`AvatarPersona`, que es puro), la semántica del memo con un cargador
/// falso, y la forma del código real.
void main() {
  // Un PNG de 1x1 transparente, lo mínimo que `bytesFotoSegura` acepta.
  const logoValido =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
      'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

  Widget montar(Widget w) => MaterialApp(home: Scaffold(body: Center(child: w)));

  group('cómo se pinta el avatar', () {
    testWidgets('con logo del albergue, se muestra la imagen', (tester) async {
      await tester.pumpWidget(
        montar(const AvatarPersona(fotoBase64: logoValido, inicial: 'A')),
      );
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      expect(find.text('A'), findsNothing, reason: 'gana el logo');
    });

    testWidgets('sin logo pero con URL, se usa la URL', (tester) async {
      await tester.pumpWidget(
        montar(
          const AvatarPersona(
            fotoUrl: 'https://ejemplo.test/foto.jpg',
            inicial: 'R',
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      expect(find.text('R'), findsNothing);
    });

    // El caso del rescatista, que NO cambió: su foto siempre fue una URL.
    testWidgets('sin nada, queda la inicial y no se rompe', (tester) async {
      await tester.pumpWidget(montar(const AvatarPersona(inicial: 'A')));
      await tester.pump();

      expect(find.text('A'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('un base64 corrupto cae a la inicial, no revienta', (
      tester,
    ) async {
      await tester.pumpWidget(
        montar(const AvatarPersona(fotoBase64: 'no-es-base64', inicial: 'A')),
      );
      await tester.pump();

      expect(find.text('A'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // AvatarUsuario sin poder leer nada (no hay Firebase en un test) tiene
    // que degradar a la inicial, igual que si el perfil no tuviera foto.
    testWidgets('AvatarUsuario sin datos disponibles muestra la inicial', (
      tester,
    ) async {
      await tester.pumpWidget(
        montar(const AvatarUsuario(userId: 'refugio', inicial: 'A')),
      );
      await tester.pumpAndSettle();

      expect(find.text('A'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ── La semántica del memo ──────────────────────────────────────────────
  //
  // Se reproduce el idiom con un cargador falso, igual que hace
  // `prioridad_en_carruseles_test.dart` con el `.then` sin esperar: se
  // comprueba que la FORMA elegida haga lo que se afirma. Que el código real
  // use esa forma lo custodian los tests de más abajo.
  group('memorizar el documento por uid', () {
    late Map<String, Future<Map<String, dynamic>?>> memo;
    late int lecturas;

    setUp(() {
      memo = {};
      lecturas = 0;
    });

    /// Misma forma que `_pedirPerfil`: el borrado va en un `onError`, no en
    /// un catch sincrónico. Con un `async` que falla antes de su primer
    /// `await`, el borrado corre ANTES de que `??=` guarde la entrada y el
    /// fallo termina cacheado. Este test lo destapó en la primera versión
    /// del arreglo.
    Future<Map<String, dynamic>?> pedir(
      String id, {
      bool falla = false,
      Map<String, dynamic>? datos,
    }) {
      lecturas++;
      return Future<Map<String, dynamic>?>(() {
        if (falla) throw StateError('sin señal');
        return datos;
      }).onError((_, _) {
        memo.remove(id);
        return null;
      });
    }

    Future<Map<String, dynamic>?> cargar(
      String id, {
      bool falla = false,
      Map<String, dynamic>? datos,
    }) => memo[id] ??= pedir(id, falla: falla, datos: datos);

    test('el mismo uid se lee UNA vez, aunque lo pidan muchas tarjetas', () async {
      final datos = {'fotoBase64': logoValido, 'foto': null};
      await Future.wait([
        for (var i = 0; i < 50; i++) cargar('refugio', datos: datos),
      ]);
      expect(
        lecturas,
        1,
        reason: 'sin el memo serían 50 lecturas de 85 KB: peor que antes',
      );
    });

    test('uids distintos se leen por separado', () async {
      await cargar('refugio');
      await cargar('otro');
      await cargar('refugio');
      expect(lecturas, 2, reason: 'una por albergue distinto, no una por tarjeta');
    });

    test('un fallo NO queda cacheado: el siguiente reintenta', () async {
      await cargar('refugio', falla: true);
      expect(memo.containsKey('refugio'), isFalse);

      await cargar('refugio', datos: {'fotoBase64': logoValido});
      expect(lecturas, 2, reason: 'una caída de red no puede dejar el avatar '
          'sin logo por el resto de la sesión');
    });

    test('un perfil SIN logo sí queda cacheado: es una respuesta, no un fallo',
        () async {
      await cargar('refugio', datos: {'nombre': 'Refugio'});
      await cargar('refugio', datos: {'nombre': 'Refugio'});
      expect(lecturas, 1);
    });

    // EL error que casi cometo: si se cacheara el RESULTADO indexado solo por
    // uid, la primera pantalla que preguntara fijaría su respuesta para las
    // demás. Las 5 pantallas que ya usan AvatarUsuario no pasan
    // campoLogoNegocio, así que el feed habría recibido `null` como logo y
    // mostrado la foto personal en vez del logo del albergue. Silencioso y
    // dependiente del orden en que se abrieran las pantallas.
    test('del MISMO documento, cada pantalla deriva su propio campo', () async {
      final doc = {'fotoBase64': logoValido, 'foto': 'https://x.test/p.jpg'};
      final datos = await cargar('refugio', datos: doc);

      String? derivar(String? campoLogoNegocio) =>
          campoLogoNegocio != null
              ? (datos?[campoLogoNegocio] as String?)
              : null;

      expect(derivar('fotoBase64'), logoValido, reason: 'el feed, como albergue');
      expect(derivar(null), isNull, reason: 'las otras pantallas');
      expect(lecturas, 1, reason: 'y las dos con una sola lectura');
    });
  });

  // ── Que el código real siga escrito así ────────────────────────────────
  group('el código real', () {
    String leer(String ruta) => File(ruta)
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///'))
        .join('\n');

    final avatares = leer('lib/widgets/avatares.dart');
    final feed = leer('lib/screens/adoptante_feed_screen.dart');

    test('el memo guarda el DOCUMENTO, no el par derivado', () {
      expect(
        avatares,
        contains('static final _perfiles = <String, Future<Map<String, dynamic>?>>{}'),
        reason: 'cacheando el par, campoLogoNegocio quedaría fijado por quien '
            'preguntara primero',
      );
      expect(avatares, contains('_perfiles[id] ??= _pedirPerfil(id)'));
    });

    test('un fallo no queda cacheado', () {
      expect(
        avatares,
        contains('_perfiles.remove(id)'),
        reason: 'sin esto una caída de red fija el avatar sin foto',
      );
    });

    test('sigue estando el blindaje de didUpdateWidget', () {
      expect(avatares, contains('void didUpdateWidget'));
      expect(avatares, contains('oldWidget.campoLogoNegocio != widget.campoLogoNegocio'));
    });

    test('el feed ya no lee la copia de adentro del animalito', () {
      expect(
        feed,
        isNot(contains('rescatistaFotoBase64')),
        reason: 'volvió a arrastrar 85 KB por animalito',
      );
    });

    test('el feed usa AvatarUsuario, y el logo solo para albergue', () {
      expect(feed, contains('AvatarUsuario('));
      expect(feed, contains('userId: rescatistaId'));
      expect(
        feed,
        contains("campoLogoNegocio: esCreadoPorAlbergue(creadoPor)"),
        reason: 'sin la condición, un animalito publicado como rescatista '
            'mostraría el logo del propio albergue de esa cuenta',
      );
    });

    test('la rama del rescatista no se tocó', () {
      expect(
        feed,
        contains("final rescatistaFotoUrl = a['rescatistaFotoUrl'] as String?"),
        reason: 'su foto sigue saliendo de la URL de siempre',
      );
      final publicar = leer('lib/screens/subir_rescate_screen.dart');
      expect(publicar, contains("'rescatistaFotoUrl': fotoPublicadorUrl"));
      expect(publicar, isNot(contains('rescatistaFotoBase64')));
    });

    test('ninguna pantalla vuelve a escribir el blob', () {
      for (final ruta in [
        'lib/screens/subir_rescate_screen.dart',
        'lib/screens/subir_lote_screen.dart',
      ]) {
        expect(leer(ruta), isNot(contains('rescatistaFotoBase64')), reason: ruta);
      }
    });

    // Los animalitos, su orden, su límite y su paginación no cambian: esto
    // era un cambio de dónde sale UNA imagen, no de qué se muestra.
    test('los animalitos, el orden, el límite y la paginación no cambian', () {
      final repo = leer('lib/data/rescates_repository.dart');
      expect(repo, contains('static const feedPageSize = 50'));
      expect(repo, contains("Query<Map<String, dynamic>> q = _col.orderBy('creadoEn')"));
      expect(repo, contains('if (despuesDe != null) q = q.startAfterDocument(despuesDe)'));
      expect(feed, contains('FeedPaginado('));
    });
  });
}
