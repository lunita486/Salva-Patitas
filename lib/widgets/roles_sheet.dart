import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import '../data/firestore_resiliencia.dart';
import '../data/usuarios_repository.dart';
import 'resultado_guardado_snackbar.dart';

/// Flujo completo de "Gestionar mis roles": lee los roles actuales, abre
/// la hoja de selección, guarda, avisa el resultado y cierra ESTA pantalla
/// de perfil para que HomeScreen recalcule qué panel mostrar. Vivía
/// duplicado byte a byte en perfil_rescatista_screen.dart y
/// perfil_adoptante_screen.dart (142 líneas, sin ninguna diferencia real
/// más que el rol de respaldo) — hallazgo de auditoría de código.
///
/// [rolFallback] es el único punto real donde las dos pantallas
/// difieren: qué rol asumir si el documento todavía no tiene `roles`
/// guardado (dato legado).
Future<void> gestionarRoles(
  BuildContext context, {
  required String rolFallback,
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final doc = await FirebaseFirestore.instance
      .collection('usuarios')
      .doc(uid)
      .get();
  final roles = List<String>.from(
    (doc.data()?['roles'] as List?) ?? [rolFallback],
  );
  if (!context.mounted) return;
  final seleccion = await showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => RolesSheet(rolesActuales: roles),
  );
  if (seleccion == null || seleccion.isEmpty) return;
  // guardarConAviso, no un await directo suelto: la hoja ya se cerró para
  // cuando esto corre, así que sin esto, si la escritura fallaba de
  // verdad, la persona quedaba creyendo que cambió de rol sin que nada se
  // hubiera guardado — sin ningún aviso, ni de éxito ni de error.
  final resultado = await guardarConAviso(
    () => UsuariosRepository().actualizarRoles(uid, seleccion),
  );
  if (!context.mounted) return;
  mostrarResultadoGuardado(context, resultado, exito: 'Roles actualizados');
  // Esta pantalla no tiene ningún listener propio sobre el rol activo —
  // HomeScreen es quien cachea el rol y solo lo vuelve a calcular cuando
  // esta página se cierra (ver el .then(_cargarRol) que le puso al
  // context.push que trajo hasta acá). Sin este pop, "Guardar" quitaba el
  // rol actual en Firestore pero la persona seguía viendo esta misma
  // pantalla, sin ningún error ni cartel — solo se corregía si tocaba la
  // flechita de volver. Hallazgo real de Eliza cambiando de rol desde acá
  // adentro.
  if (resultado == ResultadoGuardado.confirmado && context.mounted) {
    Navigator.pop(context);
  }
}

/// La hoja de "Mis roles".
///
/// **Solo ofrece Adoptante y Rescatista, y eso limita a quién le sirve.**
/// No hay casilla para Albergue ni para Aliado, y `_roles` arranca copiando
/// los que ya están, así que esos dos nunca se pueden sacar desde acá: una
/// cuenta con rol de negocio solo podría AGREGAR adoptante/rescatista.
///
/// Y agregarlos no cambiaría nada, porque `resolverPantallaPerfil`
/// (domain/resolucion_perfil.dart) manda a albergue y a aliado antes que a
/// cualquier otro rol: después de guardar se vuelve a aterrizar en la misma
/// pantalla de negocio.
///
/// Por eso este flujo se ofrece ÚNICAMENTE desde los perfiles de adoptante y
/// de rescatista. Estuvo un rato también en los home de albergue y de
/// aliado, con la idea de darles una salida, y hubo que sacarlo: no la daba.
/// Un botón que promete algo y no lo cumple es peor que no tenerlo.
///
/// **Queda pendiente, a propósito.** Hoy quien tiene rol de negocio no puede
/// volver al lado de adoptante/rescatista desde la app. La forma que tiene
/// más sentido para resolverlo es un cambio de VISTA (como el interruptor
/// Adoptante/Rescatista que ya existe en el inicio), no tocar los roles
/// guardados: 'albergue' lleva verificación oficial y no debería poder
/// ponérselo cualquiera. Es trabajo para después del lanzamiento.
class RolesSheet extends StatefulWidget {
  final List<String> rolesActuales;
  const RolesSheet({super.key, required this.rolesActuales});
  @override
  State<RolesSheet> createState() => _RolesSheetState();
}

class _RolesSheetState extends State<RolesSheet> {
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
      // SingleChildScrollView a propósito: en horizontal este Column no
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
