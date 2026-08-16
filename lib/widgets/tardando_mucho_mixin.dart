import 'dart:async';
import 'package:flutter/widgets.dart';

// ─── Aviso de "esto está tardando" ────────────────────────────────────────────
// El trío bool + Timer + cancelar-en-dispose se copiaba en 3 pantallas de
// publicar/editar (hallazgo de auditoría de código) — cada una sigue
// dibujando su propio aviso (se ven distinto a propósito, según dónde
// aparece), este mixin solo centraliza CUÁNDO mostrarlo.
mixin TardandoMuchoMixin<T extends StatefulWidget> on State<T> {
  bool tardandoMucho = false;
  Timer? _tardandoTimer;

  void iniciarTimerTardando(Duration umbral) {
    _tardandoTimer?.cancel();
    tardandoMucho = false;
    _tardandoTimer = Timer(umbral, () {
      if (mounted) setState(() => tardandoMucho = true);
    });
  }

  void cancelarTimerTardando() => _tardandoTimer?.cancel();

  @override
  void dispose() {
    _tardandoTimer?.cancel();
    super.dispose();
  }
}
