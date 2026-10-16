// Hoja "Apariencia" del Perfil (`.sheet` + `.looks` del prototipo):
// Claro · Oscuro (sin "Sistema", pedido de Eliza).
//
// Tocar una tarjeta cambia el tema al instante y lo guarda en el teléfono
// (lib/theme/apariencia.dart). La hoja misma se repinta con el tema nuevo,
// así se ve el cambio antes de cerrarla.
import 'package:flutter/material.dart';

import '../theme/apariencia.dart';
import '../theme/salva_patitas_theme.dart';
import 'sp_widgets.dart';

Future<void> mostrarApariencia(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    // Los colores salen del contexto de la hoja (no del de quien la abre):
    // al elegir Oscuro la hoja se repinta con el tema nuevo.
    builder: (ctx) => ValueListenableBuilder<ThemeMode>(
      valueListenable: Apariencia.modo,
      builder: (ctx, modo, _) => _HojaApariencia(ctx: ctx, modo: modo),
    ),
  );
}

class _HojaApariencia extends StatelessWidget {
  const _HojaApariencia({required this.ctx, required this.modo});
  final BuildContext ctx;
  final ThemeMode modo;

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: c.line,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Apariencia',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Elige cómo quieres ver Salva Patitas.',
              style: TextStyle(fontSize: 14, color: c.inkMuted),
            ),
            const SizedBox(height: 16),
            // Las dos tarjetas del mismo alto.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _Look(
                      titulo: 'Claro',
                      detalle: 'Fondo blanco',
                      dibujo: _Dibujo.claro,
                      elegido: modo != ThemeMode.dark,
                      onTap: () => Apariencia.elegir(ThemeMode.light),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Look(
                      titulo: 'Oscuro',
                      detalle: 'Fondo oscuro',
                      dibujo: _Dibujo.oscuro,
                      elegido: modo == ThemeMode.dark,
                      onTap: () => Apariencia.elegir(ThemeMode.dark),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: SpButton(label: 'Listo', onTap: () => Navigator.pop(ctx)),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Dibujo { claro, oscuro }

class _Look extends StatelessWidget {
  const _Look({
    required this.titulo,
    required this.detalle,
    required this.dibujo,
    this.elegido = false,
    required this.onTap,
  });
  final String titulo;
  final String detalle;
  final _Dibujo dibujo;
  final bool elegido;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    final tarjeta = Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
      decoration: SpDeco.soft(c, radius: 22).copyWith(
        border: elegido ? Border.all(color: c.primary, width: 3) : null,
      ),
      child: Column(
        children: [
          _Miniatura(dibujo),
          const SizedBox(height: 8),
          Text(
            titulo,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: c.ink,
            ),
          ),
          Text(
            detalle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: c.inkMuted,
            ),
          ),
        ],
      ),
    );
    return Stack(
      clipBehavior: Clip.none,
      // passthrough: la tarjeta toma el ancho y alto de su columna.
      fit: StackFit.passthrough,
      children: [
        Semantics(
          button: true,
          selected: elegido,
          label: '$titulo, $detalle',
          child: GestureDetector(onTap: onTap, child: tarjeta),
        ),
        if (elegido)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 24,
              height: 24,
              decoration: SpDeco.primary(c, radius: SpRadius.full),
              child: Icon(Icons.check_rounded, size: 15, color: c.onPrimary),
            ),
          ),
      ],
    );
  }
}

/// Pantallita dibujada con los colores reales de cada tema: una barra verde
/// (el héroe) y dos tarjetas.
class _Miniatura extends StatelessWidget {
  const _Miniatura(this.dibujo);
  final _Dibujo dibujo;

  @override
  Widget build(BuildContext context) {
    const claro = SpColors.light;
    const oscuro = SpColors.dark;
    Widget pantalla(SpColors t) => Container(
      color: t.bg,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 26,
            decoration: BoxDecoration(
              color: t.primary,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          for (var i = 0; i < 2; i++) ...[
            const SizedBox(height: 6),
            Container(
              height: 14,
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(color: t.edge, offset: const Offset(0, 2)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
    final contenido = switch (dibujo) {
      _Dibujo.claro => pantalla(claro),
      _Dibujo.oscuro => pantalla(oscuro),
    };
    return Container(
      width: 64,
      height: 84,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.sp.line, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: contenido,
    );
  }
}
