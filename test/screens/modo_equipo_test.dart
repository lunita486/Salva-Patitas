import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/data/contexto_albergue.dart';
import 'package:salva_patitas/theme/salva_patitas_theme.dart';
import 'package:salva_patitas/widgets/cambiar_estado_sheet.dart';
import 'package:salva_patitas/widgets/tarjeta_jauria.dart';

// Modo equipo del albergue (fase 2, PLAN-EQUIPO-ALBERGUE.md): lo que cambia
// en pantalla cuando una miembro trabaja en el panel del albergue.

const _ana = ContextoAlbergue.equipo(
  albergueId: 'perla',
  autorUid: 'ana',
  autorNombre: 'Ana',
  albergueNombre: 'Refugio La Perla',
);

void main() {
  tearDown(() => SesionEquipo.actual.value = null);

  group('contexto de la sesión', () {
    test('en modo equipo, lo del albergue es del albergue de la responsable', () {
      SesionEquipo.actual.value = _ana;
      expect(SesionEquipo.activa, isTrue);
      expect(contextoAlbergue().albergueId, 'perla');
      expect(uidDueno(esAlbergue: true), 'perla');
      expect(contextoAlbergue().camposAutor, {'autorUid': 'ana', 'autorNombre': 'Ana'});
    });

    test('sin modo equipo no hay sesión de equipo', () {
      expect(SesionEquipo.activa, isFalse);
      expect(SesionEquipo.actual.value, isNull);
    });
  });

  group('tarjeta de la jauría', () {
    Future<void> tarjeta(WidgetTester tester, Map<String, dynamic> d, {bool esAlbergue = true}) async {
      await tester.pumpWidget(MaterialApp(
        theme: SpTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: TarjetaJauria(
              docId: 'r1',
              d: {'nombre': 'Tito', 'especie': 'Perro', 'estadoAdopcion': 'Rescatado', 'creadoPor': 'albergue', ...d},
              esAlbergue: esAlbergue,
              umbralEstancado: 60,
              onEliminar: (_) {},
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('la responsable ve "Cargado por Ana" y puede borrar', (tester) async {
      await tarjeta(tester, {'autorUid': 'ana', 'autorNombre': 'Ana'});
      expect(find.text('Cargado por Ana'), findsOneWidget);
      expect(find.byTooltip('Eliminar'), findsOneWidget);
    });

    testWidgets('lo que cargó la responsable no lleva rótulo', (tester) async {
      await tarjeta(tester, {});
      expect(find.textContaining('Cargado por'), findsNothing);
    });

    testWidgets('en modo equipo, el tacho solo en lo que cargó esa persona', (tester) async {
      SesionEquipo.actual.value = _ana;
      await tarjeta(tester, {'autorUid': 'ana', 'autorNombre': 'Ana'});
      expect(find.byTooltip('Eliminar'), findsOneWidget);
      await tarjeta(tester, {});
      expect(find.byTooltip('Eliminar'), findsNothing);
      await tarjeta(tester, {'autorUid': 'bea', 'autorNombre': 'Bea'});
      expect(find.byTooltip('Eliminar'), findsNothing);
      expect(find.text('Cargado por Bea'), findsOneWidget);
    });
  });

  group('cambiar estado', () {
    Future<void> hoja(WidgetTester tester, String estado) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CambiarEstadoSheet(docId: 'r1', estadoActual: estado, nombre: 'Tito', esAlbergue: true),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('en modo equipo no se ofrece "Fallecido" (rechaza solicitudes, es de la responsable)', (tester) async {
      SesionEquipo.actual.value = _ana;
      await hoja(tester, 'Rescatado');
      expect(find.text('Fallecido'), findsNothing);
      expect(find.text('Adoptado'), findsOneWidget);
    });

    testWidgets('la responsable sí lo tiene', (tester) async {
      await hoja(tester, 'Rescatado');
      expect(find.text('Fallecido'), findsOneWidget);
    });
  });
}
