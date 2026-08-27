import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/ubicacion_service.dart';
import '../theme.dart';
import 'aviso_ubicacion.dart';

// ─── Ciudad ─────────────────────────────────────────────────────────────────
// Los 3 lugares de la app donde una ubicación se escribe a mano en vez de
// detectarse por GPS: el perfil de albergue, el de aliado (negocio), y la
// ubicación de un rescate al EDITARLO (editar_rescate_screen.dart — al
// publicar por primera vez solo viene del GPS, ver subir_rescate_screen.
// dart). Adoptante y rescatista siempre toman su propia ciudad del GPS (ver
// perfil_adoptante_screen.dart/seleccion_rol_screen.dart), así que nunca
// necesitan esto.
//
// Antes cada uno de esos 3 lugares resolvía "¿esto es un lugar real?" a su
// manera, y las tres formas eran distintas: editar_rescate_screen.dart SÍ
// bloqueaba bien ante "no encontré nada" (era la más completa, y la base
// de esta función), pero trataba CUALQUIER excepción — incluida la falta
// de señal — exactamente igual que "no es un lugar real", así que sin
// conexión no dejaba guardar NINGÚN cambio de esa pantalla, aunque el
// texto escrito fuera una ciudad perfectamente válida. albergue_perfil_
// screen.dart geocodificaba pero trataba "no encontré nada" exactamente
// igual que "no hay señal" — en los dos casos guardaba la ciudad tal cual
// sin avisar nada, así que cualquier texto ("verduras", lo que sea) quedaba
// guardado como ciudad válida. aliado_perfil_screen.dart ni siquiera lo
// intentaba. Hallazgo real de Eliza probando el campo de ciudad del
// albergue. Con una sola función, los 3 lugares validan exactamente igual
// y no pueden volver a divergir en esto.

/// El campo de ciudad de TODA la app: texto editable a mano MÁS un ícono
/// para detectarla por GPS. El ícono es un atajo, no un reemplazo.
///
/// **Antes eran dos.** Este servía a los perfiles de albergue y aliado, y
/// las pantallas de publicar/editar un animalito tenían su propia versión
/// con otra regla: la de publicar era GPS y nada más, sin forma de
/// escribir. La idea era que un rescate se publica desde donde está el
/// animal, así que el GPS alcanzaba.
///
/// No alcanza. En Medellín el mapa devuelve el barrio ("Los Olivos") o
/// "Perímetro Urbano Medellín" en vez de "Medellín", así que quien publica
/// queda atrapada con un nombre por el que nadie va a buscar, sin ninguna
/// forma de corregirlo hasta ir a editar. Hallazgo real de Eliza.
///
/// [onDetectado] es lo que hacía falta para que este widget sirviera
/// también a los animalitos: un perfil solo necesita el TEXTO (sus
/// coordenadas se resuelven al guardar), pero un animalito necesita
/// además las coordenadas del GPS, que son las que después le calculan la
/// distancia a quien mira el feed. Sin esto, este widget las tenía en la
/// mano y las tiraba.
/// Para pedirle al campo que detecte la ciudad desde AFUERA.
///
/// Hace falta porque la detección no siempre la dispara el ícono: al
/// publicar arranca sola al abrir la pantalla, se reintenta al volver de
/// los Ajustes del teléfono, y el diálogo de "publicar sin ubicación"
/// ofrece "Volver y detectar de nuevo".
///
/// Sin esto, esas pantallas necesitaban su PROPIA copia de la detección
/// —permiso, GPS, geocoding, los cuatro casos de falla— y eso es
/// exactamente lo que había: tres copias de la misma secuencia, en el
/// widget y en las dos pantallas de animalitos.
class CampoCiudadControlador {
  VoidCallback? _pedirDeteccion;

  /// Si hay una detección en curso. Lo necesita el mixin de ciclo de vida
  /// (services/ubicacion_lifecycle.dart) para no reintentar encima de una
  /// que ya está corriendo, y ahora que la detección vive en el widget, la
  /// pantalla no tiene otra forma de saberlo.
  bool detectando = false;

  /// Dispara la detección por GPS, igual que tocar el ícono. No hace nada
  /// si ya hay una en curso, o si el campo todavía no está en pantalla.
  void detectar() => _pedirDeteccion?.call();
}

class CampoCiudad extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final int? maxLength;
  final void Function(String)? onChanged;

  /// Se llama solo cuando la ciudad vino del GPS, con el resultado
  /// completo. Ver el doc de arriba: los perfiles lo dejan en null.
  final void Function(ResultadoUbicacion)? onDetectado;

  /// Para que la pantalla pueda reaccionar a que se salga del campo (ver
  /// editar_rescate_screen: ahí es cuando se va al mapa a confirmar la
  /// ciudad escrita, en vez de hacerlo recién al guardar).
  final FocusNode? focusNode;

  /// Para disparar la detección desde afuera. Ver [CampoCiudadControlador].
  final CampoCiudadControlador? controlador;

  /// Se llama justo antes de mandar a la persona a los Ajustes del
  /// teléfono, para que la pantalla pueda reintentar sola cuando vuelva.
  /// Los perfiles lo dejan en null.
  final VoidCallback? antesDeAbrirAjustes;
  const CampoCiudad({
    super.key,
    required this.controller,
    required this.hint,
    this.maxLength,
    this.onChanged,
    this.onDetectado,
    this.focusNode,
    this.controlador,
    this.antesDeAbrirAjustes,
  });
  @override
  State<CampoCiudad> createState() => _CampoCiudadState();
}

class _CampoCiudadState extends State<CampoCiudad> {
  bool _detectando = false;

  @override
  void initState() {
    super.initState();
    widget.controlador?._pedirDeteccion = _detectarSiSePuede;
  }

  /// Ignora el pedido si ya hay una detección en curso: al publicar puede
  /// llegar uno automático al abrir y otro del ícono casi a la vez.
  void _detectarSiSePuede() {
    if (!_detectando) _detectar();
  }
  // Mismo motivo que subir_rescate_screen.dart/editar_rescate_screen.dart:
  // un SnackBar de _avisar (8s) queda visible sobre la pantalla de ATRÁS si
  // se sale de este perfil antes de que se cierre solo — un solo
  // ScaffoldMessenger para toda la app por default. Capturado acá (no
  // directo en dispose) porque ScaffoldMessenger.of(context) necesita un
  // context todavía válido en el árbol.
  ScaffoldMessengerState? _scaffoldMessenger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scaffoldMessenger = ScaffoldMessenger.of(context);
  }

  @override
  void dispose() {
    widget.controlador?._pedirDeteccion = null;
    _scaffoldMessenger?.clearSnackBars();
    super.dispose();
  }

  // Limpia cualquier aviso de un intento anterior antes de mostrar el de
  // este — sin esto, reintentar varias veces apilaba un SnackBar atrás de
  // otro. `mounted` acá (no dentro de un helper compartido): esta State
  // sigue siendo la única dueña de saber si todavía está en pantalla.
  void _avisar(String mensaje, {Future<bool> Function()? accionAjustes}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    avisarErrorUbicacion(
      context,
      mensaje,
      accionAjustes: accionAjustes,
      // Solo tiene sentido cuando hay a dónde ir: quien lo pasa es la
      // pantalla que sabe reintentar sola al volver.
      antesDeAbrirAjustes: accionAjustes == null
          ? null
          : widget.antesDeAbrirAjustes,
    );
  }

  /// El GPS y sus reintentos los resuelve UbicacionService; lo único que
  /// queda acá es traducir cada motivo de falla al aviso correcto, que es
  /// justamente la parte que NO se puede compartir (cada pantalla avisa
  /// distinto, y el servicio no toca la UI a propósito).
  ///
  /// `precision: high` porque quien configura la ciudad de un negocio suele
  /// estar parado en el local; una ciudad equivocada le rompe la distancia
  /// a todos los que lo busquen.
  Future<void> _detectar() async {
    setState(() => _detectando = true);
    widget.controlador?.detectando = true;
    try {
      final resultado = await UbicacionService.actual(
        conCiudad: true,
        precision: LocationAccuracy.high,
      );
      if (!resultado.ok) {
        switch (resultado.fallo!) {
          case FalloUbicacion.servicioApagado:
            _avisar(
              mensajeGpsApagado,
              accionAjustes: Geolocator.openLocationSettings,
            );
          case FalloUbicacion.permisoBloqueado:
            _avisar(
              mensajePermisoBloqueado,
              accionAjustes: Geolocator.openAppSettings,
            );
          case FalloUbicacion.permisoDenegado:
            // Recién dijo que no: se le puede volver a preguntar tocando el
            // ícono otra vez. Un aviso rojo acá sería regañarla por una
            // decisión que acaba de tomar a propósito.
            break;
          case FalloUbicacion.sinRespuesta:
            _avisar(
              'No se pudo detectar tu ubicación. Podés escribirla a mano.',
            );
        }
        return;
      }
      // Hubo coordenadas pero el geocoding no las supo traducir a un nombre
      // — distinto de no tener ubicación, y con su propio mensaje.
      if (resultado.sinNombre) {
        _avisar(avisoCiudadSinNombre);
        return;
      }
      if (!mounted) return;
      widget.controller.text = resultado.ciudad;
      widget.onChanged?.call(resultado.ciudad);
      widget.onDetectado?.call(resultado);
    } finally {
      widget.controlador?.detectando = false;
      if (mounted) setState(() => _detectando = false);
    }
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: widget.controller,
    focusNode: widget.focusNode,
    maxLength: widget.maxLength,
    onChanged: widget.onChanged,
    decoration: InputDecoration(
      hintText: widget.hint,
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: appTeal, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      suffixIcon: Tooltip(
        message: 'Detectar mi ciudad actual',
        child: IconButton(
          onPressed: _detectando ? null : _detectar,
          icon: _detectando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: appTeal,
                  ),
                )
              : const Icon(Icons.my_location, color: appTeal),
        ),
      ),
    ),
  );
}
