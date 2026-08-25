import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/services/ubicacion_service.dart';
import 'package:salva_patitas/widgets/confirmar_ciudad_resuelta.dart';

import '../helpers/mock_nominatim.dart';

CandidatoUbicacion _candidato({
  double lat = 6.25,
  double lng = -75.56,
  String paisCodigo = 'CO',
  String ciudadResuelta = '',
  String regionResuelta = '',
}) => (
  lat: lat,
  lng: lng,
  paisCodigo: paisCodigo,
  ciudadResuelta: ciudadResuelta,
  regionResuelta: regionResuelta,
);

/// Objeto mutable, no un valor de retorno: el diálogo puede seguir abierto
/// cuando `_abrir()` ya devolvió el control al test (para que este pueda
/// tocar una opción) — `elegida` se actualiza recién cuando el test
/// interactúa con el diálogo, después de que `_abrir()` ya terminó.
class _Harness {
  CandidatoUbicacion? elegida;
  bool completado = false;
}

Future<_Harness> _abrir(
  WidgetTester tester, {
  required String escribiste,
  required List<CandidatoUbicacion> candidatos,
}) async {
  final harness = _Harness();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              harness.elegida = await confirmarCiudadResuelta(
                ctx,
                escribiste: escribiste,
                candidatos: candidatos,
              );
              harness.completado = true;
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return harness;
}

void main() {
  group(
    'confirmarCiudadResuelta() — hace cumplir el invariante de que lo '
    'guardado es SIEMPRE un lugar resuelto por el geocodificador, con su '
    'nombre, su país y sus coordenadas del MISMO candidato. Nunca el texto '
    'que se tecleó: eso es una búsqueda, no un dato.',
    () {
      testWidgets(
        'NO existe forma de guardar el texto tal cual se escribió — es la '
        'regresión exacta del APK61: esa opción guardaba el texto crudo '
        'como nombre PERO el país y las coordenadas del primer candidato, '
        'y en el feed quedaba "cordoba verduras 🇪🇸" con una bandera que '
        'Eliza nunca eligió',
        (tester) async {
          await _abrir(
            tester,
            escribiste: 'cordoba verduras',
            candidatos: [
              _candidato(
                ciudadResuelta: 'Córdoba',
                regionResuelta: 'Andalucía',
                paisCodigo: 'ES',
              ),
              _candidato(
                ciudadResuelta: 'Córdoba',
                regionResuelta: 'Córdoba',
                paisCodigo: 'AR',
              ),
            ],
          );
          expect(find.textContaining('tal cual'), findsNothing);
          expect(find.textContaining('cordoba verduras'), findsOneWidget);
          // Lo único que menciona el texto tecleado es la línea de
          // contexto ("Escribiste ... y encontramos"), no una opción.
          expect(
            find.text('Escribiste "cordoba verduras" y encontramos:'),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'elegir un candidato devuelve ESE candidato entero — nombre, país y '
        'coordenadas viajan juntos, así el llamador no puede mezclar el '
        'nombre de uno con la bandera de otro',
        (tester) async {
          final h = await _abrir(
            tester,
            escribiste: 'cordoba',
            candidatos: [
              _candidato(
                lat: 37.88,
                lng: -4.77,
                ciudadResuelta: 'Córdoba',
                regionResuelta: 'Andalucía',
                paisCodigo: 'ES',
              ),
              _candidato(
                lat: -31.42,
                lng: -64.18,
                ciudadResuelta: 'Córdoba',
                regionResuelta: 'Córdoba',
                paisCodigo: 'AR',
              ),
            ],
          );
          // Homónimas: la región y la bandera son lo único que las
          // distingue en la lista.
          expect(find.text('Córdoba, Andalucía 🇪🇸'), findsOneWidget);
          await tester.tap(find.text('Córdoba, Córdoba 🇦🇷'));
          await tester.pumpAndSettle();

          expect(h.elegida!.ciudadResuelta, 'Córdoba');
          expect(h.elegida!.paisCodigo, 'AR');
          expect(h.elegida!.lat, -31.42);
        },
      );

      testWidgets(
        'un solo candidato: título en singular, y tocarlo lo devuelve',
        (tester) async {
          final h = await _abrir(
            tester,
            escribiste: 'medellin antioquia',
            candidatos: [
              _candidato(
                ciudadResuelta: 'Medellín',
                regionResuelta: 'Antioquia',
              ),
            ],
          );
          expect(find.text('¿Es esta tu ciudad?'), findsOneWidget);
          await tester.tap(find.text('Medellín, Antioquia 🇨🇴'));
          await tester.pumpAndSettle();
          // Se guarda la ciudad SOLA, aunque se haya tecleado la provincia
          // para desambiguar: el feed muestra ciudad + bandera.
          expect(h.elegida!.ciudadResuelta, 'Medellín');
        },
      );

      testWidgets(
        'varios candidatos: título en plural y tocar el SEGUNDO lo '
        'devuelve — el caso de "medellin antioquia", donde el primero '
        '("los olivos", un barrio real) siempre venía equivocado',
        (tester) async {
          final h = await _abrir(
            tester,
            escribiste: 'medellin antioquia',
            candidatos: [
              _candidato(
                ciudadResuelta: 'Los Olivos',
                regionResuelta: 'Antioquia',
              ),
              _candidato(
                ciudadResuelta: 'Medellín',
                regionResuelta: 'Antioquia',
              ),
            ],
          );
          expect(find.text('¿Cuál es tu ciudad?'), findsOneWidget);
          await tester.tap(find.text('Medellín, Antioquia 🇨🇴'));
          await tester.pumpAndSettle();
          expect(h.elegida!.ciudadResuelta, 'Medellín');
        },
      );

      testWidgets(
        '"No, corregir" devuelve null — se vuelve al formulario a buscar de '
        'otra manera, que es el único escape cuando ninguna es la correcta',
        (tester) async {
          final h = await _abrir(
            tester,
            escribiste: 'verduras',
            candidatos: [_candidato(ciudadResuelta: 'Villa Verduras')],
          );
          await tester.tap(find.text('No, corregir'));
          await tester.pumpAndSettle();
          expect(h.completado, isTrue);
          expect(h.elegida, isNull);
        },
      );

      testWidgets(
        'un candidato sin nombre resuelto no se ofrece para elegir — no hay '
        'qué leer para confirmarlo, y guardarlo rompería el invariante',
        (tester) async {
          await _abrir(
            tester,
            escribiste: 'medellin',
            candidatos: [
              _candidato(ciudadResuelta: ''),
              _candidato(ciudadResuelta: 'Medellín'),
            ],
          );
          // Título en singular: quedó UNA sola opción elegible.
          expect(find.text('¿Es esta tu ciudad?'), findsOneWidget);
          expect(find.text('Medellín 🇨🇴'), findsOneWidget);
        },
      );

      testWidgets(
        'si NINGÚN candidato se puede describir (el reverse geocoding se '
        'cayó) avisa y devuelve null en vez de dejar pasar el texto crudo '
        'en silencio — ese silencio era el segundo agujero por el que '
        'entraba "cordoba verduras", incluso sin la opción de texto libre',
        (tester) async {
          final h = await _abrir(
            tester,
            escribiste: 'cordoba verduras',
            candidatos: [
              _candidato(ciudadResuelta: ''),
              _candidato(ciudadResuelta: ''),
            ],
          );
          expect(find.text('No pudimos verificar esa ciudad'), findsOneWidget);
          await tester.tap(find.text('Entendido'));
          await tester.pumpAndSettle();
          expect(h.elegida, isNull);
        },
      );

      testWidgets(
        'una lista vacía cae en el mismo camino seguro (avisa, no guarda) — '
        'defensivo: hoy desdeTexto() nunca devuelve una lista vacía sin ser '
        'null, pero el que no se guarde nada no puede depender de eso',
        (tester) async {
          final h = await _abrir(
            tester,
            escribiste: 'verduras',
            candidatos: const [],
          );
          expect(find.text('No pudimos verificar esa ciudad'), findsOneWidget);
          await tester.tap(find.text('Entendido'));
          await tester.pumpAndSettle();
          expect(h.elegida, isNull);
        },
      );
    },
  );

  group(
    'resolverCiudadEscrita() — la secuencia completa (geocodificar → '
    'distinguir "no existe" de "no hay señal" → confirmar cuál es), '
    'compartida por las 4 pantallas que piden una ciudad. Existe porque '
    'esa secuencia estaba copiada a mano en las 4 y ya había divergido.',
    () {
      late MockNominatim nominatim;

      setUp(() {
        nominatim = MockNominatim();
        UbicacionService.httpClient = nominatim.client;
      });

      // Devuelve un holder mutable, no el valor: cuando hay diálogo de por
      // medio este helper vuelve con el diálogo TODAVÍA abierto (para que
      // el test pueda tocar una opción), así que el resultado recién se
      // llena después.
      Future<_Harness> correr(WidgetTester tester, String texto) async {
        final harness = _Harness();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () async {
                    harness.elegida = await resolverCiudadEscrita(ctx, texto);
                    harness.completado = true;
                  },
                  child: const Text('guardar'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('guardar'));
        // UbicacionService.desdeTexto() reintenta UNA vez tras un tropiezo,
        // con una espera real de 1500ms (conReintento) — pumpAndSettle() solo
        // sigue bombeando mientras haya un FRAME agendado, así que un Timer
        // puro (sin animación de por medio) no alcanza a completarse sin
        // avanzar el reloj falso a mano primero.
        await tester.pump(const Duration(milliseconds: 1600));
        await tester.pumpAndSettle();
        return harness;
      }

      testWidgets(
        'un error de red NO deja pasar el texto crudo — es el agujero exacto '
        'que tenía el perfil del ALIADO: su `catch` vacío dejaba seguir el '
        'guardado, así que un tropiezo de señal grababa "cordoba verduras" '
        'como si fuera una ciudad válida. Las otras 3 pantallas ya '
        'bloqueaban; ahora las 4 comparten este mismo camino',
        (tester) async {
          nominatim.errorAlBuscar = Exception('sin señal');

          final h = await correr(tester, 'cordoba verduras');

          expect(h.completado, isTrue);
          expect(h.elegida, isNull);
          expect(
            find.text(
              'No pudimos verificar esa ciudad. Revisá tu conexión e '
              'intentá de nuevo.',
            ),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'un texto que no es ningún lugar real avisa con OTRO mensaje — "no '
        'existe" y "no hay señal" no se pueden confundir: uno se arregla '
        'escribiendo bien, el otro esperando a tener conexión',
        (tester) async {
          nominatim.resultadosBusqueda = const [];

          final h = await correr(tester, 'verduras');

          expect(h.completado, isTrue);
          expect(h.elegida, isNull);
          expect(
            find.text(
              'No encontramos "verduras" como ciudad. Revisá cómo la '
              'escribiste.',
            ),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'cuando encuentra el lugar muestra el diálogo, y lo elegido vuelve '
        'con nombre, país y coordenadas del mismo candidato',
        (tester) async {
          nominatim.resultadosBusqueda = [
            MockNominatim.candidato(
              lat: 6.25,
              lon: -75.56,
              city: 'Medellín',
              state: 'Antioquia',
              countryCode: 'CO',
            ),
          ];

          final h = await correr(tester, 'medellin antioquia');
          await tester.tap(find.text('Medellín, Antioquia 🇨🇴'));
          await tester.pumpAndSettle();

          expect(h.elegida!.ciudadResuelta, 'Medellín');
          expect(h.elegida!.paisCodigo, 'CO');
          expect(h.elegida!.lat, 6.25);
        },
      );
    },
  );
}
