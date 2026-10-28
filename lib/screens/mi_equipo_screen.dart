import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/equipo_repository.dart';
import '../domain/reglas_negocio.dart';
import '../theme/salva_patitas_theme.dart';
import '../widgets/estado_error_feed.dart';
import '../widgets/sp_widgets.dart';

/// "Mi equipo de albergue" de una persona invitada o miembro: sus
/// invitaciones pendientes (aceptar o rechazar) y, si ya es miembro, a qué
/// albergue pertenece y el botón para salir (la Function avisa al albergue).
///
/// La membresía no es un rol: esta pantalla se abre desde el perfil de
/// adoptante o rescatista, y nada de lo personal de la persona cambia.
class MiEquipoScreen extends StatefulWidget {
  const MiEquipoScreen({super.key, this.repo, this.uid, this.email});
  final EquipoRepository? repo;

  /// Solo para pruebas; en la app son los de la sesión actual.
  final String? uid;
  final String? email;

  @override
  State<MiEquipoScreen> createState() => _MiEquipoScreenState();
}

class _MiEquipoScreenState extends State<MiEquipoScreen> {
  late final EquipoRepository _repo = widget.repo ?? EquipoRepository();
  late final _membresia = _repo.miMembresia(widget.uid ?? FirebaseAuth.instance.currentUser?.uid ?? '');
  late final _invitaciones = _repo.invitacionesPara(widget.email ?? FirebaseAuth.instance.currentUser?.email ?? '');
  String? _ocupado;

  void _aviso(String texto, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), backgroundColor: error ? context.sp.msgError : context.sp.msgExito),
    );
  }

  Future<bool> _confirmar(String titulo, String texto, String accion, {bool peligro = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dlg) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlg, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(dlg, true),
            child: Text(accion, style: TextStyle(color: peligro ? context.sp.danger : context.sp.primaryStrong)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _accion(String clave, Future<void> Function() fn, String exito) async {
    if (_ocupado != null) return;
    setState(() => _ocupado = clave);
    try {
      await fn();
      _aviso(exito);
    } catch (e) {
      _aviso(EquipoError.mensajeDe(e), error: true);
    } finally {
      if (mounted) setState(() => _ocupado = null);
    }
  }

  Future<void> _aceptar(InvitacionEquipo i) async {
    final c = context.sp;
    final texto = TextStyle(fontSize: 15, color: c.inkMuted, height: 1.35);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dlg) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('¿Sumarte al equipo de ${_nombre(i)}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Vas a poder, a nombre del albergue:', style: texto.copyWith(color: c.ink, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('•  Cargar y editar animalitos', style: texto),
            Text('•  Responder los chats', style: texto),
            Text('•  Manejar los hogares de paso', style: texto),
            const SizedBox(height: 8),
            Text('Aprobar adopciones sigue siendo de la responsable.', style: texto),
            const SizedBox(height: 12),
            Text.rich(TextSpan(children: [
              TextSpan(text: 'Tu cuenta personal sigue separada: ', style: texto.copyWith(color: c.ink, fontWeight: FontWeight.w700)),
              TextSpan(text: 'el albergue no ve tus chats ni los animales que publicás por tu cuenta.', style: texto),
            ])),
            const SizedBox(height: 8),
            Text('Para entrar, elegí «Albergue» arriba en tu inicio.', style: texto),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlg, false), child: const Text('Ahora no')),
          TextButton(
            onPressed: () => Navigator.pop(dlg, true),
            child: Text('Sí, sumarme', style: TextStyle(color: c.primaryStrong, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _accion(i.id, () => _repo.aceptar(i.id), '¡Listo! Ya sos parte del equipo de ${_nombre(i)}. Elegí «Albergue» en tu inicio para entrar.');
  }

  Future<void> _rechazar(InvitacionEquipo i) async {
    final ok = await _confirmar('Rechazar invitación', 'El albergue ${_nombre(i)} no se entera del motivo.', 'Rechazar', peligro: true);
    if (!ok) return;
    await _accion(i.id, () => _repo.rechazar(i.id), 'Invitación rechazada.');
  }

  Future<void> _salir(String nombreAlbergue) async {
    final ok = await _confirmar(
      'Salir del equipo',
      'Dejás de ser parte del equipo de $nombreAlbergue y le avisamos al albergue. Para volver, te tienen que invitar de nuevo.',
      'Salir',
      peligro: true,
    );
    if (!ok) return;
    await _accion('salir', _repo.salir, 'Saliste del equipo de $nombreAlbergue.');
  }

  static String _nombre(InvitacionEquipo i) => i.albergueNombre.isNotEmpty ? i.albergueNombre : 'el albergue';

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const SpPawBackground(),
          SafeArea(
            child: StreamBuilder<Membresia?>(
              stream: _membresia,
              builder: (context, sm) => StreamBuilder<List<InvitacionEquipo>>(
                stream: _invitaciones,
                builder: (context, si) {
                  final cargando = sm.connectionState == ConnectionState.waiting ||
                      si.connectionState == ConnectionState.waiting;
                  final membresia = sm.data;
                  final esMiembro = membresia?.activa ?? false;
                  final invitaciones = si.data ?? const <InvitacionEquipo>[];
                  return ListView(
                    padding: const EdgeInsets.only(bottom: 40),
                    children: [
                      const SpScreenHeader(title: 'Mi equipo de albergue', subtitle: 'Ayudás a gestionar un albergue'),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (sm.hasError || si.hasError)
                              errorFeedState()
                            else if (cargando)
                              Padding(
                                padding: const EdgeInsets.all(SpSpace.s6),
                                child: Center(child: CircularProgressIndicator(color: c.primary)),
                              )
                            else ...[
                              if (esMiembro) _miAlbergue(c, membresia!),
                              if (invitaciones.isNotEmpty) ...[
                                if (esMiembro) const SizedBox(height: SpSpace.s6),
                                SpSectionTitle('Invitaciones (${invitaciones.length})'),
                                const SizedBox(height: SpSpace.s3),
                                if (esMiembro)
                                  SpNotice(
                                    fondo: c.butter,
                                    tinta: c.butterInk,
                                    child: const Text('Para aceptar otra invitación, primero salí de tu equipo actual.'),
                                  ),
                                for (final i in invitaciones) ...[
                                  _invitacion(c, i, puedeAceptar: !esMiembro),
                                  const SizedBox(height: SpSpace.s3),
                                ],
                              ],
                              if (!esMiembro && invitaciones.isEmpty)
                                const SpEmpty(
                                  title: 'No tenés invitaciones',
                                  subtitle: 'Cuando un albergue te invite a su equipo con tu correo, aparece acá.',
                                  animal: SpAnimalKind.conejo,
                                ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miAlbergue(SpColors c, Membresia m) => StreamBuilder<String>(
    stream: _repo.nombreDeAlbergue(m.albergueId),
    builder: (context, snap) {
      final nombre = snap.data ?? 'Tu albergue';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SpCard(
            padding: const EdgeInsets.all(SpSpace.s3),
            child: Row(
              children: [
                const SpBigTile(tone: SpTone.mint, animal: SpAnimalKind.casa),
                const SizedBox(width: SpSpace.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nombre, style: SpText.headline.copyWith(color: c.ink, fontWeight: FontWeight.w800)),
                      Text(
                        m.desde != null ? 'Sos parte del equipo desde el ${formatearFecha(m.desde!)}' : 'Sos parte del equipo',
                        style: SpText.caption.copyWith(color: c.inkMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SpSpace.s4),
          SizedBox(
            width: double.infinity,
            child: SpButton(
              label: 'Salir del equipo',
              icon: Icons.logout_rounded,
              peligro: true,
              cargando: _ocupado == 'salir',
              onTap: () => _salir(nombre),
            ),
          ),
        ],
      );
    },
  );

  Widget _invitacion(SpColors c, InvitacionEquipo i, {required bool puedeAceptar}) => Container(
    key: ValueKey('invitacion_${i.id}'),
    padding: const EdgeInsets.all(SpSpace.s4),
    decoration: SpDeco.card(c),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SpBigTile(tone: SpTone.peach, animal: SpAnimalKind.perro),
            const SizedBox(width: SpSpace.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_nombre(i)} te invitó a su equipo',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: c.ink)),
                  Text(i.plazoParaResponder(DateTime.now()), style: SpText.caption.copyWith(color: c.inkMuted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: SpSpace.s3),
        if (_ocupado == i.id)
          Center(child: CircularProgressIndicator(color: c.primary))
        else
          Row(
            children: [
              Expanded(child: SpButton(label: 'Rechazar', suave: true, compacto: true, onTap: () => _rechazar(i))),
              const SizedBox(width: SpSpace.s3),
              Expanded(
                child: SpButton(
                  label: 'Aceptar',
                  compacto: true,
                  icon: Icons.check_rounded,
                  onTap: puedeAceptar ? () => _aceptar(i) : null,
                ),
              ),
            ],
          ),
      ],
    ),
  );
}
