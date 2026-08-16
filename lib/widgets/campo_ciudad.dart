import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/ubicacion_service.dart';
import '../theme.dart';

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

/// Campo de ciudad para los perfiles de albergue y aliado: texto editable
/// a mano (un negocio puede configurarse desde otro lugar, no
/// necesariamente desde donde está el local) MÁS un ícono para detectarla
/// automáticamente por GPS — atajo, no reemplazo. Mismo permiso/GPS/
/// timeout que ya usan subir_rescate_screen.dart/editar_rescate_screen.
/// dart para la ubicación de un animal (ahí sí es GPS-first porque un
/// rescate se publica desde donde está el animal), adaptado acá para
/// llenar el mismo campo de texto que la persona también puede escribir a
/// mano. No hace falta devolver coordenadas por separado: el texto que
/// deja acá (detectado o escrito) pasa igual por [geocodificarCiudad] al
/// guardar (ver _guardar() de cada pantalla), así que da lo mismo cuál
/// camino se haya usado — una sola fuente de coordenadas, no dos que
/// puedan quedar desincronizadas entre sí.
class CampoCiudad extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final int? maxLength;
  final bool autofocus;
  final void Function(String)? onChanged;
  const CampoCiudad({
    super.key,
    required this.controller,
    required this.hint,
    this.maxLength,
    this.autofocus = false,
    this.onChanged,
  });
  @override
  State<CampoCiudad> createState() => _CampoCiudadState();
}

class _CampoCiudadState extends State<CampoCiudad> {
  bool _detectando = false;
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
    _scaffoldMessenger?.clearSnackBars();
    super.dispose();
  }

  void _avisar(
    String mensaje, {
    Future<bool> Function()? accionAjustes,
    String? etiquetaAccion,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: msgError,
        duration: const Duration(seconds: 8),
        action: accionAjustes == null
            ? null
            : SnackBarAction(
                label: etiquetaAccion ?? 'Abrir Ajustes',
                textColor: Colors.white,
                onPressed: () {
                  accionAjustes();
                },
              ),
      ),
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
    try {
      final resultado = await UbicacionService.actual(
        conCiudad: true,
        precision: LocationAccuracy.high,
      );
      if (!resultado.ok) {
        switch (resultado.fallo!) {
          case FalloUbicacion.servicioApagado:
            _avisar(
              'Activa el GPS en tu dispositivo',
              accionAjustes: Geolocator.openLocationSettings,
            );
          case FalloUbicacion.permisoBloqueado:
            _avisar(
              'Permiso de ubicación bloqueado.',
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
      if (resultado.ciudad.isEmpty) {
        _avisar('No pudimos identificar tu ciudad. Podés escribirla a mano.');
        return;
      }
      if (!mounted) return;
      widget.controller.text = resultado.ciudad;
      widget.onChanged?.call(resultado.ciudad);
    } finally {
      if (mounted) setState(() => _detectando = false);
    }
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: widget.controller,
    autofocus: widget.autofocus,
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
