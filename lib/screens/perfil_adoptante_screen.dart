import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../routing/app_router.dart';
import '../theme/salva_patitas_theme.dart';
import '../routing/pagina_pestana.dart';
import '../widgets/adoptante_tab_bar.dart';
import '../widgets/sp_widgets.dart';
import '../widgets/apariencia_sheet.dart';
import '../data/favoritos_repository.dart';
import '../widgets/avatares.dart';
import '../widgets/dialogo_cerrar_sesion.dart';
import '../widgets/roles_sheet.dart';
import '../data/rescates_repository.dart';
import '../services/ubicacion_service.dart';
import '../services/ubicacion_lifecycle.dart';
import 'eliminar_cuenta_dialog.dart';

class PerfilAdoptanteScreen extends StatefulWidget {
  // home_screen.dart (la pantalla de atrás, que nunca se cierra mientras
  // esta se empuja encima) ya detecta su propia ciudad apenas arranca la
  // sesión — pasarla acá evita repetir GPS + geocoding desde cero cada vez
  // que se entra a Perfil (varios segundos reales de espera, no un
  // adorno), cuando lo más probable es que ya se sepa. Sigue siendo
  // opcional: si no llega (o llegó vacía porque el GPS todavía no había
  // resuelto), esta pantalla detecta la suya propia, igual que antes.
  final String? ciudadConocida;
  const PerfilAdoptanteScreen({super.key, this.ciudadConocida});
  @override
  State<PerfilAdoptanteScreen> createState() => _PerfilAdoptanteScreenState();
}

class _PerfilAdoptanteScreenState extends State<PerfilAdoptanteScreen>
    with WidgetsBindingObserver, ReintentoUbicacionAlVolver {
  // No es `final`: se reasigna para reintentar (ver
  // reintentarSinPedirPermiso, más abajo). Guardado en un campo en vez de llamarse
  // desde el FutureBuilder de más abajo porque antes esto era
  // StatelessWidget y el future se creaba de nuevo en CADA build() (ej. al
  // cambiar de rol desde home_screen.dart) — cada rebuild volvía a pedir
  // permiso de ubicación, GPS y geocoding de nuevo, con el pin de ciudad
  // parpadeando al desaparecer y reaparecer.
  //
  // Si ya llega una ciudad conocida (ver widget.ciudadConocida), el
  // Future se resuelve de una con Future.value — sin esperar a un GPS que
  // ya no hace falta pedir de nuevo. Hallazgo real de Eliza: entraba a
  // Favoritos, volvía, iba a Perfil, y veía el número de favoritos (una
  // simple lectura de Firestore) segundos antes que la ciudad — porque la
  // ciudad se volvía a pedir por GPS desde cero en cada visita a esta
  // pantalla, aunque home_screen.dart ya la tuviera lista hacía rato.
  late Future<String> _ciudadFuture =
      (widget.ciudadConocida?.isNotEmpty ?? false)
      ? Future.value(widget.ciudadConocida!)
      : _detectarCiudad();
  // Espejo del resultado del Future de arriba, fuera del FutureBuilder:
  // ReintentoUbicacionAlVolver (yaTieneUbicacion) necesita saber "¿ya
  // tenemos ciudad?" sin depender de leer un AsyncSnapshot. Arranca ya con
  // la ciudad conocida (si llegó) — sin esto, yaTieneUbicacion vería
  // `_ciudad` vacía y volvería a pedir GPS de nuevo apenas la app pasa a
  // segundo plano y vuelve, aunque ya se supiera la ciudad de entrada.
  late String _ciudad = widget.ciudadConocida ?? '';
  // Evita que dos detecciones corran encima (el reintento al volver a
  // primer plano puede caer mientras la primera sigue en curso).
  bool _detectandoCiudad = false;

  // El reintento al volver de segundo plano vive en
  // ReintentoUbicacionAlVolver — acá solo queda decirle qué mirar y qué
  // hacer. Ver ese archivo para el hallazgo completo (real de Eliza
  // probando en el teléfono: el pin quedaba vacío para siempre aunque
  // prendiera el GPS sin reiniciar la app).
  @override
  bool get yaTieneUbicacion => _ciudad.isNotEmpty;
  @override
  bool get detectandoUbicacion => _detectandoCiudad;
  @override
  void reintentarSinPedirPermiso() =>
      setState(() => _ciudadFuture = _detectarCiudad(pedirPermiso: false));

  /// Todo el detalle de GPS/permisos/reintentos vive en UbicacionService —
  /// acá solo queda lo propio de esta pantalla: reflejar la ciudad en
  /// `_ciudad` (el espejo que mira ReintentoUbicacionAlVolver, ver arriba)
  /// además de devolverla para el FutureBuilder del pin.
  ///
  /// Ciudad vacía (GPS apagado, permiso denegado, geocoding caído) no es un
  /// caso especial acá: el pin simplemente no se dibuja, sin ningún aviso.
  Future<String> _detectarCiudad({bool pedirPermiso = true}) async {
    _detectandoCiudad = true;
    try {
      final resultado = await UbicacionService.actual(
        conCiudad: true,
        pedirPermisoSiFalta: pedirPermiso,
      );
      if (mounted && resultado.ciudad.isNotEmpty) {
        setState(() => _ciudad = resultado.ciudad);
      }
      return resultado.ciudad;
    } finally {
      _detectandoCiudad = false;
    }
  }

  void _gestionarRoles() => gestionarRoles(context, rolFallback: 'adoptante');

  /// Ciudad o favoritos debajo del nombre (`.sp-chip`).
  Widget _chipDato({required Widget icono, required Widget texto}) {
    final c = context.sp;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: SpDeco.soft(c, radius: SpRadius.full),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icono,
          const SizedBox(width: 6),
          Flexible(child: texto),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    final user = FirebaseAuth.instance.currentUser;
    final nombre = user?.displayName ?? 'Tú';
    final inicial = nombre.isNotEmpty ? nombre[0].toUpperCase() : 'T';
    final estiloDato = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: c.inkMuted,
    );
    return Scaffold(
      // Misma barra que el inicio del adoptante (ver AdoptanteTabBar).
      bottomNavigationBar: AdoptanteTabBar(
        actual: AdoptanteTab.perfil,
        onTap: AdoptanteTabBar.volverAlInicio(context, AdoptanteTab.perfil),
      ),
      backgroundColor: c.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const SpPawBackground(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SpScreenHeader(title: 'Perfil', subtitle: 'Tu cuenta'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Foto, nombre, ciudad y favoritos (`.hero2`) ──
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: SpDeco.soft(c, radius: SpRadius.full),
                            // AvatarPersona (widgets/avatares.dart), no un
                            // CircleAvatar armado a mano — si la foto de Google
                            // fallaba al cargar se veía un círculo gris vacío
                            // en vez de la inicial. Hallazgo de auditoría.
                            child: AvatarPersona(
                              fotoUrl: user?.photoURL,
                              inicial: inicial,
                              radius: 54,
                              backgroundColor: c.lilac,
                              textColor: c.lilacInk,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // maxLines: los nombres de Google traen nombre y
                        // apellido completos y se pasaban del borde.
                        Center(
                          child: Text(
                            nombre,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                              color: c.ink,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Center(
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FutureBuilder<String>(
                                future: _ciudadFuture,
                                builder: (_, snap) {
                                  // También con ciudad vacía ('' cuando el
                                  // GPS falla o está bloqueado): sin este
                                  // guard quedaba el chip sin texto.
                                  if (!snap.hasData || snap.data!.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  return _chipDato(
                                    icono: Icon(
                                      Icons.place_outlined,
                                      size: 16,
                                      color: c.primary,
                                    ),
                                    texto: Text(
                                      snap.data!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: estiloDato,
                                    ),
                                  );
                                },
                              ),
                              _chipDato(
                                icono: Icon(
                                  Icons.favorite_rounded,
                                  size: 15,
                                  color: c.accent,
                                ),
                                texto: const _ContadorFavoritos(),
                              ),
                            ],
                          ),
                        ),

                        // ── Cuenta ───────────────────────────────────────
                        const SizedBox(height: SpSpace.s6),
                        const SpSectionTitle('Cuenta'),
                        const SizedBox(height: SpSpace.s3),
                        SpCard(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            children: [
                              SpFilaCuenta(
                                icono: Icons.assignment_outlined,
                                texto: 'Mis solicitudes',
                                tono: SpTone.lilac,
                                // Si en la barra de Mis solicitudes se toca
                                // otra pestaña, se la pasa al inicio (la
                                // pila sigue siendo inicio + una sección).
                                onTap: () => context
                                    .push(AppRoutes.misSolicitudes)
                                    .then((t) {
                                      if (t is AdoptanteTab &&
                                          t != AdoptanteTab.perfil &&
                                          context.mounted) {
                                        SaltoDePestana.marcar();
                                        context.pop(t);
                                      }
                                    }),
                              ),
                              const SpDivisorFilas(),
                              SpFilaCuenta(
                                icono: Icons.pets_rounded,
                                texto: 'Animal preferido',
                                tono: SpTone.peach,
                                onTap: () => context.push(AppRoutes.tipoAnimal),
                              ),
                              const SpDivisorFilas(),
                              SpFilaCuenta(
                                icono: Icons.switch_account_outlined,
                                texto: 'Gestionar mis roles',
                                tono: SpTone.mint,
                                onTap: _gestionarRoles,
                              ),
                              const SpDivisorFilas(),
                              // Por ahora solo deja elegir Claro: el modo
                              // oscuro se habilita cuando esté revisado (ver
                              // widgets/apariencia_sheet.dart).
                              SpFilaCuenta(
                                icono: Icons.dark_mode_outlined,
                                texto: 'Apariencia',
                                sub: 'Claro',
                                tono: SpTone.lilac,
                                onTap: () => mostrarApariencia(context),
                              ),
                              const SpDivisorFilas(),
                              // Estandarizado con el rescatista: la política
                              // de privacidad está en los dos roles (pedido
                              // real de Eliza).
                              SpFilaCuenta(
                                icono: Icons.shield_outlined,
                                texto: 'Política de privacidad',
                                tono: SpTone.sky,
                                onTap: () => launchUrl(
                                  Uri.parse(
                                    'https://lunita486.github.io/Salva-Patitas/privacidad.html',
                                  ),
                                  mode: LaunchMode.externalApplication,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: SpButton(
                            label: 'Cerrar sesión',
                            icon: Icons.logout_rounded,
                            suave: true,
                            onTap: () => mostrarDialogoCerrarSesion(context),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Center(
                          child: TextButton(
                            onPressed: () =>
                                mostrarEliminarCuentaDialog(context),
                            style: TextButton.styleFrom(
                              foregroundColor: c.danger,
                            ),
                            child: const Text(
                              'Eliminar mi cuenta',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "X favoritos" del encabezado del perfil — cuenta la colección
/// `favoritos` pero descuenta los que apuntan a un rescate ya borrado
/// (mismo criterio que favoritos_screen.dart, para que los dos números
/// nunca se contradigan). Auditoría de reglas de negocio, hallazgo real de
/// Eliza (2026-08-06): "que no pase lo de los 11 animales rescatados que
/// no era real" — acá antes se contaba la colección `favoritos` tal cual,
/// sin descontar los huérfanos.
///
/// Widget aparte (no un StreamBuilder anidado inline) a propósito: la
/// verificación de "¿el rescateId sigue existiendo?" necesita su propia
/// consulta, y si esa consulta se rearmara en cada build (como pasaría
/// anidando StreamBuilders con una lista de ids recalculada al vuelo), se
/// re-suscribiría de cero cada vez que ALGO MÁS hiciera rebuildear esta
/// pantalla — mostrando 0 mientras la nueva consulta todavía no responde,
/// en vez de solo actualizarse cuando el conjunto de favoritos cambia de
/// verdad. Encontrado probando en el emulador: el número parpadeaba a 0
/// antes de asentarse.
class _ContadorFavoritos extends StatefulWidget {
  const _ContadorFavoritos();
  @override
  State<_ContadorFavoritos> createState() => _ContadorFavoritosState();
}

class _ContadorFavoritosState extends State<_ContadorFavoritos> {
  // "Último conjunto de ids que ya se verificó contra `rescates`" — mientras
  // no cambie, no hace falta volver a consultar. Arranca vacío: antes de la
  // primera verificación, el conteo de abajo trata todo como "no
  // verificado" y cuenta la colección `favoritos` tal cual (el
  // comportamiento de siempre), nunca 0 de arranque.
  Set<String> _idsVerificados = {};
  Set<String> _idsExistentes = {};
  bool _verificando = false;

  // `late final`, no armado dentro de build(): armarlo ahí lo recreaba en
  // cada redibujado y el StreamBuilder se resuscribía de cero. Acá pesa
  // extra porque este contador llama a setState() al verificar los ids, o
  // sea que se redibuja solo — cada verificación reiniciaba su propio
  // stream. Hallazgo de auditoría de código.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _favoritosStream =
      FavoritosRepository().mios(FirebaseAuth.instance.currentUser?.uid ?? '');

  Future<void> _verificarExistencia(Set<String> ids) async {
    if (_verificando) return;
    _verificando = true;
    try {
      if (ids.isEmpty) {
        if (mounted)
          setState(() {
            _idsVerificados = {};
            _idsExistentes = {};
          });
        return;
      }
      final docs = await RescatesRepository().porIdsSinTope(ids.toList()).first;
      if (!mounted) return;
      setState(() {
        _idsVerificados = ids;
        _idsExistentes = docs.map((d) => d.id).toSet();
      });
    } catch (_) {
      // Sin conexión o similar: se queda con la última verificación buena
      // (o sin verificar nada, contando todo) — no hace falta avisar, es
      // solo un número informativo en el encabezado del perfil.
    } finally {
      _verificando = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _favoritosStream,
      builder: (_, snap) {
        final favDocs = snap.data?.docs ?? [];
        final ids = favDocs
            .map(
              (d) =>
                  (d.data() as Map<String, dynamic>)['rescateId'] as String? ??
                  '',
            )
            .where((id) => id.isNotEmpty)
            .toSet();
        // porIdsSinTope ya parte esto en tandas de a 30 del lado del
        // repositorio — no hace falta recortar acá (antes sí, y una
        // cuenta con más de 30 favoritos nunca terminaba de confirmar los
        // que quedaban afuera del primer lote).
        final idsAVerificar = ids;

        if (!setEquals(idsAVerificar, _idsVerificados)) {
          // Se dispara DESPUÉS de este build (no durante) — llamar
          // setState desde acá adentro tiraría "setState() called during
          // build".
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _verificarExistencia(idsAVerificar);
          });
        }

        final count = favDocs.where((d) {
          final rid =
              (d.data() as Map<String, dynamic>)['rescateId'] as String? ?? '';
          if (rid.isEmpty || !_idsVerificados.contains(rid)) return true;
          return _idsExistentes.contains(rid);
        }).length;

        // El ícono del corazón lo pone el chip de afuera.
        return Text(
          '$count favorito${count == 1 ? "" : "s"}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.sp.inkMuted,
          ),
        );
      },
    );
  }
}
