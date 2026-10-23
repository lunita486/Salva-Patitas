import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/apariencia.dart';
import '../theme/salva_patitas_theme.dart';
import '../widgets/rescatista_tab_bar.dart';
import '../widgets/apariencia_sheet.dart';
import '../widgets/avatares.dart';
import '../widgets/sp_widgets.dart';
import '../widgets/fila_mi_equipo.dart';
import '../domain/reglas_negocio.dart';
import '../widgets/dialogo_cerrar_sesion.dart';
import '../widgets/resultado_guardado_snackbar.dart';
import '../widgets/roles_sheet.dart';
import '../widgets/umbral_estancado_sheet.dart';
import '../data/creator_role.dart';
import '../data/firestore_resiliencia.dart';
import '../data/rescates_repository.dart';
import '../data/usuarios_repository.dart';
import 'eliminar_cuenta_dialog.dart';

class PerfilRescatistaScreen extends StatelessWidget {
  const PerfilRescatistaScreen({super.key});

  void _gestionarRoles(BuildContext context) =>
      gestionarRoles(context, rolFallback: 'rescatista');

  Future<void> _configurarUmbralEstancado(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .get();
    if (!context.mounted) return;
    final seleccion = await showModalBottomSheet<int>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => UmbralEstancadoSheet(
        actual: umbralEstancadoDe(doc.data(), esAlbergue: false),
      ),
    );
    if (seleccion == null) return;
    // guardarConAviso, no un try/catch a mano sin timeout (lo que había
    // acá antes): sin límite de tiempo, estando sin señal de verdad (no
    // un error que se pueda atrapar, un `await` que simplemente no
    // vuelve) esto se quedaba esperando indefinidamente igual, con la
    // hoja abierta — el mismo problema de fondo, solo que a medio
    // arreglar.
    final resultado = await guardarConAviso(
      () => FirebaseFirestore.instance.collection('usuarios').doc(uid).update({
        'umbralEstancadoDiasRescatista': seleccion,
      }),
    );
    if (!context.mounted) return;
    mostrarResultadoGuardado(context, resultado, exito: 'Umbral actualizado');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    final user = FirebaseAuth.instance.currentUser;
    final nombre = user?.displayName ?? 'Rescatista';
    final email = user?.email ?? '';
    final inicial = nombre.isNotEmpty ? nombre[0].toUpperCase() : 'R';

    // Mismo diseño que el perfil del adoptante (pedido de Eliza).
    return Scaffold(
      // Misma barra que el inicio del rescatista (ver RescatistaTabBar).
      bottomNavigationBar: RescatistaTabBar(
        actual: RescatistaTab.perfil,
        onTap: RescatistaTabBar.volverAlInicio(context, RescatistaTab.perfil),
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
                        // ── Foto, nombre, correo y rol ──
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: SpDeco.soft(c, radius: SpRadius.full),
                            // AvatarPersona: si la foto de Google no carga,
                            // cae a la inicial en vez de un círculo vacío.
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
                        if (email.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Center(
                            child: Text(
                              email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SpText.label.copyWith(color: c.inkMuted),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Center(
                          child: Container(
                            height: 34,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: SpDeco.soft(c, radius: SpRadius.full),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.volunteer_activism_rounded,
                                  size: 16,
                                  color: c.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Rescatista',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: c.inkMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // ── Cifras ───────────────────────────────────────
                        const SizedBox(height: SpSpace.s6),
                        _StatsRescatista(uid: user?.uid ?? ''),

                        // ── Cuenta ───────────────────────────────────────
                        const SizedBox(height: SpSpace.s6),
                        const SpSectionTitle('Cuenta'),
                        const SizedBox(height: SpSpace.s3),
                        SpCard(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            children: [
                              // Solo aparece con un equipo o una invitación
                              // (equipo del albergue, PLAN-EQUIPO-ALBERGUE.md).
                              const FilaMiEquipo(),
                              SpFilaCuenta(
                                icono: Icons.switch_account_outlined,
                                texto: 'Gestionar mis roles',
                                tono: SpTone.mint,
                                onTap: () => _gestionarRoles(context),
                              ),
                              const SpDivisorFilas(),
                              SpFilaCuenta(
                                icono: Icons.schedule_rounded,
                                texto: 'Aviso sin adoptar',
                                tono: SpTone.peach,
                                onTap: () =>
                                    _configurarUmbralEstancado(context),
                              ),
                              const SpDivisorFilas(),
                              // Claro u Oscuro, según lo elegido en la hoja (ver
                              // lib/theme/apariencia.dart).
                              SpFilaCuenta(
                                icono: Icons.dark_mode_outlined,
                                texto: 'Apariencia',
                                sub: Apariencia.etiqueta,
                                tono: SpTone.lilac,
                                onTap: () => mostrarApariencia(context),
                              ),
                              const SpDivisorFilas(),
                              // Estandarizado con perfil_adoptante_screen.dart:
                              // la política de privacidad está en los dos
                              // roles, en el mismo lugar (pedido real de
                              // Eliza).
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

/// Los dos contadores de la parte de arriba del perfil ("Animales
/// rescatados" / "Adopciones aprobadas"). Separado de PerfilRescatistaScreen
/// (StatelessWidget) para poder guardar las dos consultas como `late final`
/// — mismo patrón, y mismo motivo, que el arreglo de mis_rescates_screen.dart:
/// armadas inline en build() (como estaban antes acá) se recrean en CADA
/// rebuild de la pantalla, y un rebuild justo después de editar/borrar un
/// animal podía mostrar el número viejo un instante, tomado de la caché
/// local de la resuscripción recién armada.
class _StatsRescatista extends StatefulWidget {
  final String uid;
  const _StatsRescatista({required this.uid});
  @override
  State<_StatsRescatista> createState() => _StatsRescatistaState();
}

class _StatsRescatistaState extends State<_StatsRescatista> {
  /// Lo que se muestra mientras el número todavía no se sabe. NO un cero:
  /// un cero se lee como un dato ya traído. Mismo criterio, y mismo
  /// carácter, que el perfil público del albergue.
  static const _cargandoValor = '—';

  /// El documento del perfil, en vivo.
  ///
  /// **Acá está el arreglo entero.** Los dos números salían de `count()`,
  /// que es una agregación y cuya única fuente posible es el servidor
  /// (`AggregateSource` tiene un solo valor, `server`). O sea: sin caché,
  /// un viaje de red completo en CADA apertura del perfil. Hasta el APK96
  /// salían de un stream, que sí entrega primero lo del caché local, y por
  /// eso el perfil se sentía inmediato; el APK97 ganó no descargar los
  /// documentos y perdió eso, sin que nos diéramos cuenta.
  ///
  /// Un DOCUMENTO normal sí sale del caché. Los mantiene al día el trigger
  /// `onRescateContado` (functions/contadores.js), así que la
  /// pantalla no tiene que contar nada: lee dos campos.
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _perfil;

  /// El plan B, y solo eso: se usa únicamente si el documento del perfil
  /// NO trae los contadores.
  ///
  /// Pasa en dos casos, los dos transitorios: una cuenta recién creada que
  /// todavía no publicó nada (el trigger no se despertó nunca), y las
  /// cuentas viejas hasta que se les corra el backfill. Sin esto, un
  /// rescatista nuevo vería un guion para siempre en vez del 0 que de
  /// verdad le corresponde.
  ///
  /// Se calcula UNA sola vez, y no se calcula en absoluto cuando los
  /// contadores existen.
  Future<List<int>>? _plazoB;

  @override
  void initState() {
    super.initState();
    _perfil = FirebaseFirestore.instance
        .collection('usuarios')
        .doc(widget.uid)
        .snapshots();
  }

  /// El cálculo viejo, con `count()`. Cuenta EXACTAMENTE lo mismo que el
  /// trigger del servidor: animalitos de este uid publicados como
  /// rescatista, y cuántos de esos están en 'Adoptado'.
  Future<List<int>> _contarAMano() => Future.wait([
    RescatesRepository().contar(uid: widget.uid, role: CreatorRole.rescatista),
    RescatesRepository().contar(
      uid: widget.uid,
      role: CreatorRole.rescatista,
      estados: const ['Adoptado'],
    ),
  ]);

  Widget _fila(String total, String adoptados) => Row(
    children: [
      Expanded(
        child: SpMiniStat(
          tone: SpTone.mint,
          animal: SpAnimalKind.huella,
          value: total,
          label: 'Rescatados',
        ),
      ),
      const SizedBox(width: SpSpace.s3),
      // "Adopciones aprobadas" son animalitos cuyo estadoAdopcion ACTUAL es
      // 'Adoptado'. NO son las solicitudes con estado 'aprobada': eso suma
      // los hogares de paso aprobados y nunca resta cuando uno termina, así
      // que el número no bajaba nunca. Hallazgo real de Eliza: "11
      // aprobadas" con 1 solo animal adoptado. La definición no cambió al
      // pasar a contadores guardados.
      Expanded(
        child: SpMiniStat(
          tone: SpTone.butter,
          animal: SpAnimalKind.casa,
          value: adoptados,
          label: 'Adoptados',
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _perfil,
      builder: (context, perfilSnap) {
        final guardados = contadoresRescatistaDe(perfilSnap.data?.data());

        // El camino normal: los dos números salen del documento, sin
        // contar nada y sin tocar la red si el documento ya está en caché.
        if (guardados != null) {
          return _fila('${guardados.principal}', '${guardados.adoptados}');
        }

        // Llegó el documento (o falló la lectura) y no trae los
        // contadores: recién ahí se cuenta a mano.
        if (perfilSnap.hasData || perfilSnap.hasError) {
          _plazoB ??= _contarAMano();
          return FutureBuilder<List<int>>(
            future: _plazoB,
            builder: (context, snap) => _fila(
              snap.hasData ? '${snap.data![0]}' : _cargandoValor,
              snap.hasData ? '${snap.data![1]}' : _cargandoValor,
            ),
          );
        }

        // Todavía no llegó nada. No se sabe, y no saber no es cero.
        return _fila(_cargandoValor, _cargandoValor);
      },
    );
  }
}
