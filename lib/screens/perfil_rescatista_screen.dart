import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../domain/reglas_negocio.dart';
import '../widgets/dialogo_cerrar_sesion.dart';
import '../widgets/fondo_decorativo.dart';
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
    final user = FirebaseAuth.instance.currentUser;
    final nombre = user?.displayName ?? 'Rescatista';
    final foto = user?.photoURL;
    final email = user?.email ?? '';

    return Scaffold(
      backgroundColor: appBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const LeafOverlay(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                        tooltip: 'Volver',
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 8),
                  foto != null
                      ? CircleAvatar(
                          backgroundImage: CachedNetworkImageProvider(foto),
                          radius: 44,
                        )
                      : CircleAvatar(
                          backgroundColor: appTeal,
                          radius: 44,
                          child: Text(
                            nombre.isNotEmpty ? nombre[0].toUpperCase() : 'R',
                            style: const TextStyle(
                              fontSize: 36,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                  const SizedBox(height: 14),
                  Text(
                    nombre,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: appInk,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    email,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: appTeal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Rescatista 🦺',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: appTeal,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _StatsRescatista(uid: user?.uid ?? ''),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () =>
                        gestionarRoles(context, rolFallback: 'rescatista'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.switch_account_outlined,
                            color: appTeal,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Gestionar mis roles',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: Colors.grey.shade400,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => _configurarUmbralEstancado(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.schedule, color: appOrange, size: 20),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Aviso sin adoptar',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: Colors.grey.shade400,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Cerrar sesión
                  GestureDetector(
                    onTap: () => mostrarDialogoCerrarSesion(context),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.logout,
                            color: Colors.red.shade400,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Cerrar sesión',
                            style: TextStyle(
                              color: Colors.red.shade400,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Eliminar mi cuenta
                  GestureDetector(
                    onTap: () => mostrarEliminarCuentaDialog(context),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.delete_outline,
                            color: Colors.red.shade700,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Eliminar mi cuenta',
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Estandarizado con perfil_adoptante_screen.dart: mismo
                  // widget, misma posición (al final, después de "Eliminar mi
                  // cuenta") en los dos roles — antes vivía arriba, entre
                  // "Aviso de animal sin adoptar" y "Cerrar sesión", posición
                  // distinta a la del adoptante. Pedido real de Eliza.
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
      _statTile(total, 'Animales\nrescatados', appTeal),
      const SizedBox(width: 12),
      // "Adopciones aprobadas" son animalitos cuyo estadoAdopcion ACTUAL es
      // 'Adoptado'. NO son las solicitudes con estado 'aprobada': eso suma
      // los hogares de paso aprobados y nunca resta cuando uno termina, así
      // que el número no bajaba nunca. Hallazgo real de Eliza: "11
      // aprobadas" con 1 solo animal adoptado. La definición no cambió al
      // pasar a contadores guardados.
      _statTile(adoptados, 'Adopciones\naprobadas', appOrange),
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

Widget _statTile(String n, String lbl, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8),
        ],
      ),
      child: Column(
        children: [
          Text(
            n,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            lbl,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
