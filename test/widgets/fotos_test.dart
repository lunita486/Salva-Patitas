import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/widgets/fotos.dart';

Widget _envolver(Widget hijo) =>
    MaterialApp(home: Scaffold(body: Center(child: hijo)));

void main() {
  group(
    'FotoAnimal.fondoBorroso — el relleno de las franjas sobrantes. El '
    'desenfoque obliga a Flutter a abrir una capa aparte (saveLayer) por '
    'cada foto, y eso en una LISTA que se desplaza se paga en cada cuadro '
    'y por cada fila visible. En una miniatura de 64px ese desenfoque ni '
    'se distingue de un color plano, así que se paga por algo que nadie ve.',
    () {
      testWidgets(
        'por defecto SÍ desenfoca — es lo que hace que una foto de '
        'cualquier proporción llene una tarjeta grande sin bordes muertos',
        (tester) async {
          await tester.pumpWidget(
            _envolver(
              const FotoAnimal(
                url: 'https://example.com/foto.jpg',
                fallback: SizedBox.shrink(),
                width: 300,
                height: 200,
              ),
            ),
          );
          expect(find.byType(ImageFiltered), findsOneWidget);
        },
      );

      testWidgets(
        'con fondoBorroso:false no queda NINGÚN ImageFiltered — es el '
        'saveLayer por fila que se quería sacar de las listas',
        (tester) async {
          await tester.pumpWidget(
            _envolver(
              const FotoAnimal(
                url: 'https://example.com/foto.jpg',
                fallback: SizedBox.shrink(),
                width: 64,
                height: 64,
                fondoBorroso: false,
              ),
            ),
          );
          expect(find.byType(ImageFiltered), findsNothing);
        },
      );

      testWidgets(
        'sin fondo borroso se sigue mostrando la foto ENTERA (contain), no '
        'recortada — el recorte fijo es el bug que trajo a estas listas a '
        'usar FotoAnimal en primer lugar ("Chanchis", "Tobyiii": animales '
        'que no quedan cerca del borde de la foto desaparecían del '
        'encuadre), así que eso no puede volver',
        (tester) async {
          await tester.pumpWidget(
            _envolver(
              const FotoAnimal(
                url: 'https://example.com/foto.jpg',
                fallback: SizedBox.shrink(),
                width: 64,
                height: 64,
                fondoBorroso: false,
              ),
            ),
          );
          final fotos = tester
              .widgetList<FotoUrl>(find.byType(FotoUrl))
              .toList();
          // Una sola capa de imagen (antes eran dos: fondo + frente).
          expect(fotos.length, 1);
          expect(fotos.single.fit, BoxFit.contain);
        },
      );

      testWidgets('con fondo borroso son dos capas: la de fondo recorta '
          '(cover) y la de adelante muestra la foto entera (contain)', (
        tester,
      ) async {
        await tester.pumpWidget(
          _envolver(
            const FotoAnimal(
              url: 'https://example.com/foto.jpg',
              fallback: SizedBox.shrink(),
              width: 300,
              height: 200,
            ),
          ),
        );
        final fits = tester
            .widgetList<FotoUrl>(find.byType(FotoUrl))
            .map((f) => f.fit)
            .toList();
        expect(fits, [BoxFit.cover, BoxFit.contain]);
      });

      testWidgets(
        'sin fondo borroso, el emoji de repuesto NO se pinta mientras la '
        'foto todavía puede cargar bien — regresión real: la primera '
        'versión de fondoBorroso:false ponía el fallback como `child` fijo '
        'del Container de fondo, así que quedaba visible SIEMPRE (foto Y '
        'emoji al mismo tiempo, en las franjas que deja BoxFit.contain), '
        'no solo cuando la foto de verdad fallaba. Hallazgo real de Eliza '
        'en "Mis rescates": "veo la foto y debajo el emoji de gato/perro"',
        (tester) async {
          const marcaFallback = Key('marca-fallback-emoji');
          await tester.pumpWidget(
            _envolver(
              const FotoAnimal(
                url: 'https://example.com/foto.jpg',
                fallback: SizedBox(key: marcaFallback),
                width: 64,
                height: 64,
                fondoBorroso: false,
              ),
            ),
          );
          // Un solo pump (no pumpAndSettle): la imagen todavía está
          // intentando cargar, no tuvo tiempo de fallar. En este instante
          // el fallback no tiene ningún motivo real para estar en pantalla.
          await tester.pump();
          expect(find.byKey(marcaFallback), findsNothing);
        },
      );
    },
  );

  group(
    'bytesFotoSegura() — cachea por string de entrada. Hallazgo real de '
    'Eliza: "cada vez que escribo el nombre del aliado, la foto se pone a '
    'titilar" — base64Decode arma un Uint8List NUEVO en cada llamada, y '
    'MemoryImage compara por identidad de esa lista, no por contenido: '
    'sin cachear, cada tecla escrita en un campo vecino (que redibuja la '
    'pantalla entera) hacía que Flutter tratara la MISMA foto como si '
    'fuera una distinta, la decodificaba y la pintaba de nuevo — el '
    'parpadeo.',
    () {
      test(
        'pedir la misma foto dos veces devuelve el MISMO Uint8List '
        '(identidad, no solo contenido igual) — es justo lo que hace que '
        'MemoryImage no la trate como una imagen distinta',
        () {
          const b64 = 'aGVsbG8='; // "hello"
          final primera = bytesFotoSegura(b64);
          final segunda = bytesFotoSegura(b64);
          expect(identical(primera, segunda), true);
        },
      );

      test('un string corrupto sigue devolviendo null, sin lanzar, y en '
          'las dos llamadas', () {
        const invalido = 'no es base64 válido###';
        expect(bytesFotoSegura(invalido), isNull);
        expect(bytesFotoSegura(invalido), isNull);
      });

      test('null y string vacío siguen devolviendo null directo, sin '
          'pasar por la caché', () {
        expect(bytesFotoSegura(null), isNull);
        expect(bytesFotoSegura(''), isNull);
      });

      test(
        'strings DISTINTOS decodifican a bytes DISTINTOS — la caché es por '
        'contenido del string, no un valor pegado para siempre',
        () {
          final a = bytesFotoSegura('aGVsbG8='); // "hello"
          final b = bytesFotoSegura('d29ybGQ='); // "world"
          expect(identical(a, b), false);
        },
      );
    },
  );
}
