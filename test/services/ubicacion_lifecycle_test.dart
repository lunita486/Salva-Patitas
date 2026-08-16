import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/services/ubicacion_lifecycle.dart';

// Widgets mínimos que mezclan cada mixin, con el estado que hace falta
// controlar expuesto como parámetros configurables — mismo patrón que los
// fakes de plataforma en ubicacion_service_test.dart, pero acá lo que se
// prueba es el mixin en sí, no UbicacionService.

class _PantallaAlVolver extends StatefulWidget {
  final bool yaTiene;
  final bool detectando;
  final VoidCallback onReintentar;
  const _PantallaAlVolver({
    required this.yaTiene,
    required this.detectando,
    required this.onReintentar,
  });
  @override
  State<_PantallaAlVolver> createState() => _PantallaAlVolverState();
}

class _PantallaAlVolverState extends State<_PantallaAlVolver>
    with WidgetsBindingObserver, ReintentoUbicacionAlVolver {
  @override
  bool get yaTieneUbicacion => widget.yaTiene;
  @override
  bool get detectandoUbicacion => widget.detectando;
  @override
  void reintentarSinPedirPermiso() => widget.onReintentar();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _PantallaTrasAjustes extends StatefulWidget {
  final bool yaTiene;
  final bool detectando;
  final VoidCallback onReintentar;
  const _PantallaTrasAjustes({
    required this.yaTiene,
    required this.detectando,
    required this.onReintentar,
  });
  @override
  State<_PantallaTrasAjustes> createState() => _PantallaTrasAjustesState();
}

class _PantallaTrasAjustesState extends State<_PantallaTrasAjustes>
    with WidgetsBindingObserver, ReintentoUbicacionTrasAjustes {
  @override
  bool get yaTieneUbicacion => widget.yaTiene;
  @override
  bool get detectandoUbicacion => widget.detectando;
  @override
  void reintentarConPermiso() => widget.onReintentar();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  group('ReintentoUbicacionAlVolver — el patrón "seguro por construcción": '
      'nunca abre el diálogo del sistema, así que puede reintentar en '
      'CUALQUIER resumed sin condición extra. Antes vivía copiado en '
      'home_screen.dart, perfil_adoptante_screen.dart y '
      'adoptante_feed_screen.dart', () {
    testWidgets('resumed sin ubicación y sin detección en curso: reintenta', (
      tester,
    ) async {
      var veces = 0;
      await tester.pumpWidget(
        _PantallaAlVolver(
          yaTiene: false,
          detectando: false,
          onReintentar: () => veces++,
        ),
      );
      final state = tester.state<_PantallaAlVolverState>(
        find.byType(_PantallaAlVolver),
      );

      state.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(veces, 1);
    });

    testWidgets('ya tiene ubicación: NO reintenta', (tester) async {
      var veces = 0;
      await tester.pumpWidget(
        _PantallaAlVolver(
          yaTiene: true,
          detectando: false,
          onReintentar: () => veces++,
        ),
      );
      final state = tester.state<_PantallaAlVolverState>(
        find.byType(_PantallaAlVolver),
      );

      state.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(veces, 0);
    });

    testWidgets('ya hay una detección en curso: NO reintenta encima — '
        'evita pisar el pedido que ya está en vuelo', (tester) async {
      var veces = 0;
      await tester.pumpWidget(
        _PantallaAlVolver(
          yaTiene: false,
          detectando: true,
          onReintentar: () => veces++,
        ),
      );
      final state = tester.state<_PantallaAlVolverState>(
        find.byType(_PantallaAlVolver),
      );

      state.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(veces, 0);
    });

    testWidgets('estados que no son resumed (paused, inactive, detached, '
        'hidden) nunca disparan el reintento', (tester) async {
      var veces = 0;
      await tester.pumpWidget(
        _PantallaAlVolver(
          yaTiene: false,
          detectando: false,
          onReintentar: () => veces++,
        ),
      );
      final state = tester.state<_PantallaAlVolverState>(
        find.byType(_PantallaAlVolver),
      );

      for (final s in [
        AppLifecycleState.paused,
        AppLifecycleState.inactive,
        AppLifecycleState.detached,
        AppLifecycleState.hidden,
      ]) {
        state.didChangeAppLifecycleState(s);
      }

      expect(veces, 0);
    });

    testWidgets('SIN condición extra: dos resumed seguidos, todavía sin '
        'ubicación, reintentan las DOS veces — es justo lo que lo hace '
        'seguro (a diferencia del otro mixin), porque nunca abre un '
        'diálogo que pudiera generar un resumed en bucle', (tester) async {
      var veces = 0;
      await tester.pumpWidget(
        _PantallaAlVolver(
          yaTiene: false,
          detectando: false,
          onReintentar: () => veces++,
        ),
      );
      final state = tester.state<_PantallaAlVolverState>(
        find.byType(_PantallaAlVolver),
      );

      state.didChangeAppLifecycleState(AppLifecycleState.resumed);
      state.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(veces, 2);
    });
  });

  group('ReintentoUbicacionTrasAjustes — el patrón que SÍ puede abrir el '
      'diálogo del sistema, y por eso NO puede reintentar en cualquier '
      'resumed (ese bucle ya crasheó una vez, hallazgo real de Eliza '
      '2026-08-06: "parpadeaba sin parar y la pantalla quedaba '
      'inusable"). Antes vivía copiado en subir_rescate_screen.dart y '
      'editar_rescate_screen.dart', () {
    testWidgets('resumed SIN haber llamado marcarVolviendoDeAjustes: NO '
        'reintenta, aunque falte la ubicación — es el corazón de la '
        'diferencia con el otro mixin', (tester) async {
      var veces = 0;
      await tester.pumpWidget(
        _PantallaTrasAjustes(
          yaTiene: false,
          detectando: false,
          onReintentar: () => veces++,
        ),
      );
      final state = tester.state<_PantallaTrasAjustesState>(
        find.byType(_PantallaTrasAjustes),
      );

      state.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(veces, 0);
    });

    testWidgets('tras marcarVolviendoDeAjustes(), el próximo resumed SÍ '
        'reintenta', (tester) async {
      var veces = 0;
      await tester.pumpWidget(
        _PantallaTrasAjustes(
          yaTiene: false,
          detectando: false,
          onReintentar: () => veces++,
        ),
      );
      final state = tester.state<_PantallaTrasAjustesState>(
        find.byType(_PantallaTrasAjustes),
      );

      state.marcarVolviendoDeAjustes();
      state.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(veces, 1);
    });

    testWidgets('el reintento es UNA sola vez — un segundo resumed después '
        'ya no dispara nada, aunque siga sin ubicación. Esto es lo que '
        'evita el bucle: pedir permiso puede abrir un diálogo, que genera '
        'su propio resumed al cerrarse, y ese resumed no puede volver a '
        'disparar el pedido', (tester) async {
      var veces = 0;
      await tester.pumpWidget(
        _PantallaTrasAjustes(
          yaTiene: false,
          detectando: false,
          onReintentar: () => veces++,
        ),
      );
      final state = tester.state<_PantallaTrasAjustesState>(
        find.byType(_PantallaTrasAjustes),
      );

      state.marcarVolviendoDeAjustes();
      state.didChangeAppLifecycleState(AppLifecycleState.resumed); // dispara
      state.didChangeAppLifecycleState(AppLifecycleState.resumed); // no

      expect(veces, 1);
    });

    testWidgets('ya tiene ubicación al volver: el flag se consume pero NO '
        'reintenta — no hace falta si ya se resolvió por otro camino '
        'mientras la persona estaba en Ajustes', (tester) async {
      var veces = 0;
      await tester.pumpWidget(
        _PantallaTrasAjustes(
          yaTiene: true,
          detectando: false,
          onReintentar: () => veces++,
        ),
      );
      final state = tester.state<_PantallaTrasAjustesState>(
        find.byType(_PantallaTrasAjustes),
      );

      state.marcarVolviendoDeAjustes();
      state.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(veces, 0);
    });

    testWidgets('una detección ya en curso al volver: no reintenta encima', (
      tester,
    ) async {
      var veces = 0;
      await tester.pumpWidget(
        _PantallaTrasAjustes(
          yaTiene: false,
          detectando: true,
          onReintentar: () => veces++,
        ),
      );
      final state = tester.state<_PantallaTrasAjustesState>(
        find.byType(_PantallaTrasAjustes),
      );

      state.marcarVolviendoDeAjustes();
      state.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(veces, 0);
    });

    testWidgets('estados que no son resumed no consumen el flag ni '
        'reintentan', (tester) async {
      var veces = 0;
      await tester.pumpWidget(
        _PantallaTrasAjustes(
          yaTiene: false,
          detectando: false,
          onReintentar: () => veces++,
        ),
      );
      final state = tester.state<_PantallaTrasAjustesState>(
        find.byType(_PantallaTrasAjustes),
      );

      state.marcarVolviendoDeAjustes();
      state.didChangeAppLifecycleState(AppLifecycleState.paused);
      state.didChangeAppLifecycleState(AppLifecycleState.inactive);
      // El flag sigue armado — recién ahora llega el resumed real.
      state.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(veces, 1);
    });
  });
}
