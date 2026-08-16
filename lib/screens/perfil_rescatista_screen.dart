import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../domain/reglas_negocio.dart';
import '../widgets/fondo_decorativo.dart';
import '../widgets/umbral_estancado_sheet.dart';
import '../data/auth_helper.dart';
import '../data/creator_role.dart';
import '../data/firestore_resiliencia.dart';
import '../data/rescates_repository.dart';
import '../data/usuarios_repository.dart';
import 'eliminar_cuenta_dialog.dart';

class PerfilRescatistaScreen extends StatelessWidget {
  const PerfilRescatistaScreen({super.key});

  Future<void> _gestionarRoles(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .get();
    final roles = List<String>.from(
      (doc.data()?['roles'] as List?) ?? ['rescatista'],
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
    // guardarConAviso, no un await directo suelto (lo que había acá antes):
    // la hoja ya se cerró para cuando esto corre, así que sin esto, si la
    // escritura fallaba de verdad, la persona quedaba creyendo que cambió
    // de rol sin que nada se hubiera guardado — sin ningún aviso, ni de
    // éxito ni de error. Mismo arreglo que ya tiene _configurarUmbralEstancado
    // acá abajo, que antes nunca se replicó acá (hallazgo de auditoría de
    // código).
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
    switch (resultado) {
      case ResultadoGuardado.confirmado:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Umbral actualizado'),
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
                          backgroundImage: NetworkImage(foto),
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
                  // Stats
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: RescatesRepository().misRescates(
                      uid: user?.uid ?? '',
                      role: CreatorRole.rescatista,
                    ),
                    builder: (context, snap) {
                      final total = snap.data?.docs.length ?? 0;
                      return Row(
                        children: [
                          _statTile('$total', 'Animales\nrescatados', appTeal),
                          const SizedBox(width: 12),
                          // Antes contaba solicitudes con estado 'aprobada' — eso
                          // suma tanto adopciones como hogares de paso aprobados,
                          // y nunca resta cuando un hogar de paso termina y el
                          // animal vuelve a estar disponible: la solicitud queda
                          // aprobada para siempre en esa colección aunque el
                          // animal ya no esté adoptado. El número no bajaba nunca
                          // y no reflejaba la realidad. Hallazgo real de Eliza:
                          // "11 aprobadas" con solo 1 animal realmente en estado
                          // Adoptado. Ahora cuenta animales cuyo estadoAdopcion
                          // ACTUAL es 'Adoptado' — mismo campo que ya usa el resto
                          // de la app (mis_rescates_screen.dart, albergue_home_screen.dart)
                          // para decidir qué animal está adoptado de verdad.
                          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: RescatesRepository().misRescates(
                              uid: user?.uid ?? '',
                              role: CreatorRole.rescatista,
                              estadoAdopcion: 'Adoptado',
                            ),
                            builder: (context, snap2) {
                              final adoptados = snap2.data?.docs.length ?? 0;
                              return _statTile(
                                '$adoptados',
                                'Adopciones\naprobadas',
                                appOrange,
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => _gestionarRoles(context),
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
                    onTap: () => showDialog(
                      context: context,
                      builder: (dlgCtx) => AlertDialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        title: const Text('Cerrar sesión'),
                        content: const Text(
                          '¿Seguro que quieres cerrar sesión?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dlgCtx),
                            child: const Text('Cancelar'),
                          ),
                          TextButton(
                            onPressed: () async {
                              Navigator.pop(dlgCtx);
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
      // SingleChildScrollView a propósito: en horizontal hay mucha menos
      // altura disponible y este Column (título + 2 tiles + botón) no
      // entraba entero — sin scroll, lo que sobraba quedaba cortado en
      // silencio (ni error ni aviso), y con eso el botón Guardar
      // directamente no se podía tocar. Hallazgo de prueba en teléfono
      // real, 2026-08-02: la hoja "se quedaba ahí" sin poder subir ni
      // bajar apenas se rotaba a horizontal.
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
