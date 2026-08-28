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
  // contar() y no misRescates(): antes estos dos números salían de
  // `snapshot.docs.length` sobre la consulta COMPLETA, o sea que mostrar
  // "12 animales rescatados" descargaba los 12 documentos... y con 1.000
  // habría descargado los 1.000, y con 100.000 los 100.000. El costo de
  // pintar un contador no puede depender de cuántos animales haya.
  //
  // Se piden UNA vez, al montar. Es un perfil: se abre, se mira, se sale.
  // Ver el doc de RescatesRepository.contar() para qué se pierde con esto
  // (dejan de ser números en vivo) y cuándo convendría pasar a un contador
  // guardado en el documento de usuario.
  late final Future<List<int>> _numeros = Future.wait([
    RescatesRepository().contar(
      uid: widget.uid,
      role: CreatorRole.rescatista,
    ),
    RescatesRepository().contar(
      uid: widget.uid,
      role: CreatorRole.rescatista,
      estados: const ['Adoptado'],
    ),
  ]);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<int>>(
      future: _numeros,
      builder: (context, snap) {
        // Sin datos todavía (o si la consulta falló) se muestra 0, igual que
        // hacía el StreamBuilder de antes mientras esperaba.
        final total = snap.data?.elementAtOrNull(0) ?? 0;
        // Antes contaba solicitudes con estado 'aprobada' — eso suma tanto
        // adopciones como hogares de paso aprobados, y nunca resta cuando un
        // hogar de paso termina: la solicitud queda aprobada para siempre
        // aunque el animal ya no esté adoptado. Hallazgo real de Eliza: "11
        // aprobadas" con 1 solo animal en estado Adoptado. Ahora cuenta
        // animales cuyo estadoAdopcion ACTUAL es 'Adoptado'.
        final adoptados = snap.data?.elementAtOrNull(1) ?? 0;
        return Row(
          children: [
            _statTile('$total', 'Animales\nrescatados', appTeal),
            const SizedBox(width: 12),
            _statTile('$adoptados', 'Adopciones\naprobadas', appOrange),
          ],
        );
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
