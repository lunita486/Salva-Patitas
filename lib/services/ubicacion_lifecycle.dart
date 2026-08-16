import 'package:flutter/widgets.dart';

// Los dos patrones de "reintentar la ubicación al volver de segundo
// plano" que existían copiados en 5 pantallas — cada uno resuelve un
// problema distinto, y la diferencia entre los dos es la que evita el
// bucle infinito que crasheaba el Samsung Z Flip 6 (ver ARCHITECTURE.md).
// NO son intercambiables: usar el mixin equivocado en la pantalla
// equivocada reabre ese bucle.
//
// ReintentoUbicacionAlVolver es para cuando el reintento en sí NUNCA
// puede abrir el diálogo del sistema (llama a UbicacionService con
// `pedirPermisoSiFalta: false`) — sin diálogo no hay transición de
// ventana que dispare otro 'resumed', así que es seguro reintentar en
// CUALQUIER 'resumed', sin condición extra. Antes vivía copiado, letra
// por letra, en home_screen.dart, perfil_adoptante_screen.dart y
// adoptante_feed_screen.dart.
//
// ReintentoUbicacionTrasAjustes es para cuando el reintento SÍ puede
// pedir permiso de verdad (la persona tocó el botón de GPS a propósito).
// Reintentar en cualquier 'resumed' acá se cuelga: pedir permiso abre un
// diálogo, que manda la app a segundo plano y la devuelve, y ese nuevo
// 'resumed' vuelve a pedir permiso — sin fin (hallazgo real de Eliza,
// 2026-08-06: "parpadeaba sin parar y la pantalla quedaba inusable").
// Por eso este mixin solo reintenta UNA vez, y únicamente cuando la
// persona tocó "Abrir Ajustes" a propósito. Antes vivía copiado en
// subir_rescate_screen.dart y editar_rescate_screen.dart, con el mismo
// nombre de campo (`_volviendoDeAjustes`) en las dos copias.
//
// Las dos requieren `with WidgetsBindingObserver` ANTES de este mixin en
// la declaración de la clase — quien de verdad recibe el evento del
// sistema operativo es WidgetsBindingObserver; estos mixins solo deciden
// qué hacer con él. Las dos también se encargan de
// addObserver/removeObserver — la pantalla no tiene que llamarlos.

/// Reintenta mientras el recurso siga sin resolver, en cualquier
/// `resumed` — seguro solo porque [reintentarSinPedirPermiso] nunca abre
/// el diálogo del sistema. Ver el comentario al principio del archivo.
mixin ReintentoUbicacionAlVolver<T extends StatefulWidget>
    on State<T>, WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// true si el recurso (ciudad o posición) ya está resuelto — no hace
  /// falta reintentar. Cada pantalla decide qué mira (home_screen: _ciudad,
  /// adoptante_feed_screen: _userPosition).
  bool get yaTieneUbicacion;

  /// true mientras una detección ya está en curso — evita pisarla con otra
  /// en paralelo si el 'resumed' llega antes de que la primera termine.
  bool get detectandoUbicacion;

  /// Vuelve a intentar. Tiene que llamar a UbicacionService con
  /// `pedirPermisoSiFalta: false` — ese es el contrato que hace seguro a
  /// este mixin, y no se puede verificar desde acá, así que queda en el
  /// nombre del método a propósito.
  void reintentarSinPedirPermiso();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (yaTieneUbicacion || detectandoUbicacion) return;
    reintentarSinPedirPermiso();
  }
}

/// Reintenta UNA sola vez, solo tras [marcarVolviendoDeAjustes] — seguro
/// aunque [reintentarConPermiso] SÍ pueda abrir el diálogo del sistema,
/// porque no se dispara en cualquier `resumed`. Ver el comentario al
/// principio del archivo.
mixin ReintentoUbicacionTrasAjustes<T extends StatefulWidget>
    on State<T>, WidgetsBindingObserver {
  bool _volviendoDeAjustes = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Llamalo en el mismo momento en que se abre Ajustes (el `onPressed`
  /// del botón del SnackBar, justo antes de
  /// `Geolocator.openLocationSettings`/`openAppSettings`) — arma el
  /// reintento para cuando la persona vuelva. Si no se llama, volver de
  /// Ajustes no dispara nada (es la diferencia con
  /// [ReintentoUbicacionAlVolver]: acá el reintento es la EXCEPCIÓN, no la
  /// regla, a propósito).
  void marcarVolviendoDeAjustes() => _volviendoDeAjustes = true;

  /// true si ya no hace falta reintentar — resuelto, o esta pantalla ni
  /// siquiera necesita ubicación en su estado actual (ej. `esAlbergue` en
  /// subir_rescate_screen.dart, que carga la ciudad del perfil en vez de
  /// GPS).
  bool get yaTieneUbicacion;

  bool get detectandoUbicacion;

  /// Vuelve a intentar. A diferencia del otro mixin, ESTE sí puede terminar
  /// abriendo el diálogo del sistema — es seguro acá porque solo se llama
  /// una vez, tras `marcarVolviendoDeAjustes()`.
  void reintentarConPermiso();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_volviendoDeAjustes) return;
    _volviendoDeAjustes = false;
    if (yaTieneUbicacion || detectandoUbicacion) return;
    reintentarConPermiso();
  }
}
