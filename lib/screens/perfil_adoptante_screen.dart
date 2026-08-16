import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../routing/app_router.dart';
import '../theme.dart';
import '../widgets/avatares.dart';
import '../widgets/fondo_decorativo.dart';
import '../widgets/texto_sin_desborde.dart';
import '../data/auth_helper.dart';
import '../data/usuarios_repository.dart';
import '../data/rescates_repository.dart';
import '../data/firestore_resiliencia.dart';
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

  Widget _settingsCard(List<Widget> items) => Container(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
      ],
    ),
    child: Column(children: items),
  );

  Widget _settingsRow(
    String label,
    IconData icon, {
    Color? color,
    VoidCallback? onTap,
    bool last = false,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color ?? Colors.grey.shade600),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 15, color: color ?? appInk),
            ),
          ),
          Icon(Icons.chevron_right, size: 20, color: Colors.grey.shade400),
        ],
      ),
    ),
  );

  Future<void> _gestionarRoles(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .get();
    final roles = List<String>.from(
      (doc.data()?['roles'] as List?) ?? ['adoptante'],
    );
    if (!context.mounted) return;

    final seleccion = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _RolesSheet(rolesActuales: roles),
    );
    if (seleccion == null || seleccion.isEmpty) return;
    // guardarConAviso, no un await directo suelto (lo que había acá
    // antes, sin try/catch ni aviso de ningún tipo): la hoja ya se cerró
    // para cuando esto corre, así que si la escritura fallaba de verdad
    // (ej. offline, o un permission-denied que ni siquiera reintenta más
    // que una vez), la persona quedaba creyendo que cambió de rol —
    // desbloqueando o escondiendo partes enteras de la app — sin que
    // nada se hubiera guardado. Hallazgo de auditoría de código.
    final resultado = await guardarConAviso(
      () => UsuariosRepository().actualizarRoles(uid, seleccion),
    );
    if (!context.mounted) return;
    switch (resultado) {
      case ResultadoGuardado.confirmado:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Roles actualizados'),
            backgroundColor: msgExito,
          ),
        );
      case ResultadoGuardado.siguePendiente:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Esto está tardando. Se va a guardar solo apenas vuelva la señal.',
            ),
            backgroundColor: msgAdvertencia,
          ),
        );
      case ResultadoGuardado.fallo:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo guardar. Revisá tu conexión e intentá de nuevo.',
            ),
            backgroundColor: msgError,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const LeafOverlay(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Tooltip(
                        message: 'Volver',
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Icon(
                            Icons.arrow_back_ios_new,
                            size: 20,
                            color: appInk,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'PERFIL',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: appTeal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Avatar + nombre + stats
                  Builder(
                    builder: (context) {
                      final user = FirebaseAuth.instance.currentUser;
                      final nombre = user?.displayName ?? 'Tú';
                      final foto = user?.photoURL;
                      final inicial = nombre.isNotEmpty
                          ? nombre[0].toUpperCase()
                          : 'T';
                      return Row(
                        children: [
                          // AvatarPersona (widgets/avatares.dart), no un CircleAvatar armado a
                          // mano — antes, si la foto de perfil de Google fallaba al
                          // cargar (sin señal, link vencido), se veía un círculo
                          // gris vacío en vez de caer a la inicial, justo en el
                          // propio perfil de la persona. Hallazgo de auditoría de
                          // código.
                          AvatarPersona(
                            fotoUrl: foto,
                            inicial: inicial,
                            radius: 32,
                            backgroundColor: appOrange,
                            textColor: Colors.white,
                          ),
                          const SizedBox(width: 16),
                          // Expanded: sin esto, esta Column tomaba su ancho
                          // natural dentro del Row, y un nombre largo (los
                          // de Google traen nombre y apellido completos) se
                          // pasaba del borde de la pantalla. Mismo bug que
                          // el del encabezado del aliado.
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nombre,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: appInk,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    FutureBuilder<String>(
                                      future: _ciudadFuture,
                                      builder: (_, snap) {
                                        // También con ciudad vacía ('' cuando el GPS falla o
                                        // está bloqueado): sin este guard quedaba el pin y el
                                        // separador "·" flotando sin texto.
                                        if (!snap.hasData || snap.data!.isEmpty)
                                          return const SizedBox.shrink();
                                        // TextoSinDesborde (widgets/texto_sin_desborde.dart): una
                                        // ciudad larga empujaba el separador
                                        // "·" fuera de la fila.
                                        return TextoSinDesborde(
                                          texto: snap.data!,
                                          separacion: 2,
                                          mainAxisSize: MainAxisSize.min,
                                          antes: Icon(
                                            Icons.location_on,
                                            size: 13,
                                            color: Colors.grey.shade500,
                                          ),
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade700,
                                          ),
                                          despues: Padding(
                                            padding: const EdgeInsets.only(
                                              left: 4,
                                            ),
                                            child: Text(
                                              '·',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey.shade400,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    const _ContadorFavoritos(),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  // Configuración
                  const Text(
                    'CONFIGURACIÓN',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: appTeal,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Preferencias',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: appInk,
                      fontFamily: 'Baloo2',
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Cada opción en su propia tarjeta, no agrupadas — mismo
                  // espaciado que el resto de la lista (Gestionar mis roles,
                  // Cerrar sesión, etc.), antes estas dos quedaban pegadas
                  // como si fueran una sola tarjeta con dos filas, distinto al
                  // resto. Pedido real de Eliza.
                  _settingsCard([
                    _settingsRow(
                      'Mis solicitudes',
                      Icons.assignment_outlined,
                      last: true,
                      onTap: () => context.push(AppRoutes.misSolicitudes),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _settingsCard([
                    _settingsRow(
                      'Tipo de animal preferido',
                      Icons.pets,
                      last: true,
                      onTap: () => context.push(AppRoutes.tipoAnimal),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _settingsCard([
                    _settingsRow(
                      'Gestionar mis roles',
                      Icons.switch_account_outlined,
                      last: true,
                      onTap: () => _gestionarRoles(context),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _settingsCard([
                    _settingsRow(
                      'Cerrar sesión',
                      Icons.logout,
                      color: Colors.red.shade400,
                      last: true,
                      onTap: () => showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          title: const Text('Cerrar sesión'),
                          content: const Text(
                            '¿Seguro que quieres cerrar sesión?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancelar'),
                            ),
                            TextButton(
                              onPressed: () async {
                                Navigator.pop(context);
                                final ok = await cerrarSesion();
                                if (context.mounted) {
                                  if (ok) {
                                    Navigator.of(
                                      context,
                                    ).popUntil((route) => route.isFirst);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        backgroundColor: msgError,
                                        content: Text(
                                          'Esperá unos segundos e intentá de nuevo.',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                              child: const Text(
                                'Cerrar sesión',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _settingsCard([
                    _settingsRow(
                      'Eliminar mi cuenta',
                      Icons.delete_outline,
                      color: Colors.red.shade700,
                      last: true,
                      onTap: () => mostrarEliminarCuentaDialog(context),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  // Estandarizado con perfil_rescatista_screen.dart: mismo
                  // widget (link subrayado, no una card), misma posición (al
                  // final, después de "Eliminar mi cuenta") en los dos roles.
                  // Pedido real de Eliza.
                  GestureDetector(
                    onTap: () => launchUrl(
                      Uri.parse(
                        'https://lunita486.github.io/Salva-Patitas/privacidad.html',
                      ),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 16,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Política de Privacidad',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
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

class _RolesSheet extends StatefulWidget {
  final List<String> rolesActuales;
  const _RolesSheet({required this.rolesActuales});
  @override
  State<_RolesSheet> createState() => _RolesSheetState();
}

class _RolesSheetState extends State<_RolesSheet> {
  late List<String> _roles;

  @override
  void initState() {
    super.initState();
    _roles = List.from(widget.rolesActuales);
  }

  void _toggle(String rol) {
    setState(() {
      if (_roles.contains(rol)) {
        if (_roles.length > 1) _roles.remove(rol);
      } else {
        _roles.add(rol);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      // SingleChildScrollView a propósito: mismo motivo que
      // perfil_rescatista_screen.dart — en horizontal este Column no
      // entraba entero y el botón Guardar quedaba cortado, sin forma de
      // desplazarse para alcanzarlo. Hallazgo de prueba en teléfono real,
      // 2026-08-02.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Mis roles',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Podés tener los dos roles al mismo tiempo',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 20),
            _rolTile(
              'adoptante',
              '🐾 Adoptante',
              'Busco animales para adoptar',
            ),
            const SizedBox(height: 10),
            _rolTile(
              'rescatista',
              '🦺 Rescatista',
              'Rescato y publico animales',
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _roles.isNotEmpty
                    ? () => Navigator.pop(context, _roles)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: appTeal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Guardar',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rolTile(String rol, String titulo, String subtitulo) {
    final activo = _roles.contains(rol);
    return GestureDetector(
      onTap: () => _toggle(rol),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: activo ? appTeal.withValues(alpha: 0.08) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: activo ? appTeal : Colors.grey.shade200,
            width: activo ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: activo ? appTeal : appInk,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitulo,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            if (activo)
              const Icon(Icons.check_circle, color: appTeal, size: 22),
          ],
        ),
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
  late final Stream<QuerySnapshot> _favoritosStream = FirebaseFirestore.instance
      .collection('favoritos')
      .where(
        'adoptanteId',
        isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '',
      )
      .snapshots();

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
      final snap = await RescatesRepository().porIds(ids.toList()).first;
      if (!mounted) return;
      setState(() {
        _idsVerificados = ids;
        _idsExistentes = snap.docs.map((d) => d.id).toSet();
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
        // whereIn tiene tope de 30 — igual que favoritos_screen.dart, lo
        // que no entra en el lote no se puede confirmar y se sigue
        // contando (mejor de más que ocultar un favorito real).
        final ids = favDocs
            .map(
              (d) =>
                  (d.data() as Map<String, dynamic>)['rescateId'] as String? ??
                  '',
            )
            .where((id) => id.isNotEmpty)
            .toSet();
        final idsAVerificar = ids.length <= 30 ? ids : ids.take(30).toSet();

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

        return Row(
          children: [
            Icon(Icons.favorite_border, size: 13, color: Colors.grey.shade500),
            const SizedBox(width: 2),
            Text(
              '$count favorito${count == 1 ? "" : "s"}',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ],
        );
      },
    );
  }
}
