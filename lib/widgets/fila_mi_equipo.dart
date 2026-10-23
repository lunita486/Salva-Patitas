import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import '../data/equipo_repository.dart';
import '../routing/app_router.dart';
import '../theme/salva_patitas_theme.dart';
import 'sp_widgets.dart';

/// Fila "Mi equipo de albergue" para la tarjeta "Cuenta" de los perfiles de
/// adoptante y rescatista. Solo aparece si la persona es miembro de un
/// equipo o tiene una invitación pendiente: al resto no le suma nada.
/// Trae su propio divisor debajo, así no queda una línea suelta cuando no
/// se muestra. Si la lectura falla o todavía no llegó, tampoco se muestra:
/// es un acceso extra, nunca bloquea el perfil.
class FilaMiEquipo extends StatefulWidget {
  const FilaMiEquipo({super.key, this.repo, this.uid, this.email});
  final EquipoRepository? repo;

  /// Solo para pruebas; en la app son los de la sesión actual.
  final String? uid;
  final String? email;

  @override
  State<FilaMiEquipo> createState() => _FilaMiEquipoState();
}

class _FilaMiEquipoState extends State<FilaMiEquipo> {
  late final EquipoRepository _repo = widget.repo ?? EquipoRepository();
  late final _uid = widget.uid ?? FirebaseAuth.instance.currentUser?.uid;
  late final _membresia = _repo.miMembresia(_uid ?? '');
  late final _invitaciones = _repo.invitacionesPara(widget.email ?? FirebaseAuth.instance.currentUser?.email ?? '');

  @override
  Widget build(BuildContext context) {
    if (_uid == null) return const SizedBox.shrink();
    return StreamBuilder<Membresia?>(
      stream: _membresia,
      builder: (context, sm) => StreamBuilder<List<InvitacionEquipo>>(
        stream: _invitaciones,
        builder: (context, si) {
          final esMiembro = sm.data?.activa ?? false;
          final invitaciones = si.data?.length ?? 0;
          if (!esMiembro && invitaciones == 0) return const SizedBox.shrink();
          final sub = esMiembro
              ? 'Sos parte de un equipo'
              : (invitaciones == 1 ? '1 invitación pendiente' : '$invitaciones invitaciones pendientes');
          return Column(
            children: [
              SpFilaCuenta(
                icono: Icons.groups_2_outlined,
                texto: 'Mi equipo de albergue',
                sub: sub,
                tono: !esMiembro ? SpTone.peach : SpTone.mint,
                onTap: () => context.push(AppRoutes.miEquipo),
              ),
              const SpDivisorFilas(),
            ],
          );
        },
      ),
    );
  }
}
