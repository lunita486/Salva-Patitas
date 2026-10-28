import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/equipo_repository.dart';
import '../domain/reglas_negocio.dart';
import '../theme/salva_patitas_theme.dart';
import '../widgets/avatares.dart';
import '../widgets/estado_error_feed.dart';
import '../widgets/sp_widgets.dart';

/// "Equipo del albergue" de la responsable: quién está, a quién invitó y el
/// botón para invitar. Solo la ve la cuenta dueña del albergue (se abre
/// desde su Perfil). Todo cambio pasa por una Cloud Function; las reglas no
/// dejan escribir el equipo desde la app. Ver PLAN-EQUIPO-ALBERGUE.md.
class EquipoAlbergueScreen extends StatefulWidget {
  const EquipoAlbergueScreen({super.key, this.repo, this.uid});
  final EquipoRepository? repo;

  /// Solo para pruebas; en la app es la sesión actual.
  final String? uid;

  @override
  State<EquipoAlbergueScreen> createState() => _EquipoAlbergueScreenState();
}

class _EquipoAlbergueScreenState extends State<EquipoAlbergueScreen> {
  late final EquipoRepository _repo = widget.repo ?? EquipoRepository();
  late final _uid = widget.uid ?? FirebaseAuth.instance.currentUser?.uid ?? '';
  late final _miembros = _repo.miembrosDe(_uid);
  late final _invitaciones = _repo.invitacionesDe(_uid);

  // Una acción a la vez (quitar o cancelar): evita dos toques seguidos que
  // mandarían dos llamadas.
  String? _ocupado;

  void _aviso(String texto, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: error ? context.sp.msgError : context.sp.msgExito,
      ),
    );
  }

  Future<bool> _confirmar(String titulo, String texto, String accion) async {
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
            child: Text(accion, style: TextStyle(color: context.sp.danger)),
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

  Future<void> _quitar(Membresia m) async {
    final ok = await _confirmar(
      'Quitar del equipo',
      '${m.nombreVisible} va a dejar de ver los chats y los hogares de paso del albergue. '
          'Podés volver a invitarla cuando quieras.',
      'Quitar',
    );
    if (!ok) return;
    await _accion(m.uid, () => _repo.revocar(m.uid), '${m.nombreVisible} ya no está en tu equipo.');
  }

  Future<void> _cancelar(InvitacionEquipo i) async {
    final ok = await _confirmar(
      'Cancelar invitación',
      'La invitación a ${i.emailDestino} deja de valer y se libera su lugar.',
      'Cancelar invitación',
    );
    if (!ok) return;
    await _accion(i.id, () => _repo.cancelar(i.id), 'Invitación cancelada.');
  }

  Future<void> _invitar() async {
    final enviada = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _InvitarSheet(repo: _repo),
    );
    if (enviada != null) _aviso('Invitación enviada a $enviada. Vence en 7 días.');
  }

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
            child: StreamBuilder<List<Membresia>>(
              stream: _miembros,
              builder: (context, sm) => StreamBuilder<List<InvitacionEquipo>>(
                stream: _invitaciones,
                builder: (context, si) {
                  final cargando = !sm.hasData && !sm.hasError || !si.hasData && !si.hasError;
                  final miembros = sm.data ?? const <Membresia>[];
                  final invitaciones = si.data ?? const <InvitacionEquipo>[];
                  return ListView(
                    padding: const EdgeInsets.only(bottom: 40),
                    children: [
                      const SpScreenHeader(
                        title: 'Equipo del albergue',
                        subtitle: 'Personas que te ayudan a gestionarlo',
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SpNotice(
                              fondo: c.lilac,
                              tinta: c.lilacInk,
                              child: _QuePuedeVer(tinta: c.lilacInk),
                            ),
                            if (sm.hasError || si.hasError)
                              errorFeedState()
                            else if (cargando)
                              Padding(
                                padding: const EdgeInsets.all(SpSpace.s6),
                                child: Center(child: CircularProgressIndicator(color: c.primary)),
                              )
                            else ...[
                              SizedBox(
                                width: double.infinity,
                                child: SpButton(
                                  label: 'Invitar a alguien',
                                  icon: Icons.person_add_alt_1_rounded,
                                  onTap: _invitar,
                                ),
                              ),
                              const SizedBox(height: SpSpace.s6),
                              SpSectionTitle('Miembros (${miembros.length})'),
                              const SizedBox(height: SpSpace.s3),
                              if (miembros.isEmpty)
                                const SpEmpty(
                                  title: 'Todavía no hay nadie en tu equipo',
                                  subtitle: 'Invitá con su correo a quien te ayuda con el albergue.',
                                  animal: SpAnimalKind.gato,
                                )
                              else
                                for (final m in miembros) ...[
                                  _filaMiembro(c, m),
                                  const SizedBox(height: SpSpace.s3),
                                ],
                              if (invitaciones.isNotEmpty) ...[
                                const SizedBox(height: SpSpace.s4),
                                SpSectionTitle('Invitaciones pendientes (${invitaciones.length})'),
                                const SizedBox(height: SpSpace.s3),
                                for (final i in invitaciones) ...[
                                  _filaInvitacion(c, i),
                                  const SizedBox(height: SpSpace.s3),
                                ],
                              ],
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

  Widget _filaMiembro(SpColors c, Membresia m) => Container(
    key: ValueKey('miembro_${m.uid}'),
    padding: const EdgeInsets.all(SpSpace.s3),
    decoration: SpDeco.card(c),
    child: Row(
      children: [
        AvatarUsuario(
          userId: m.uid,
          inicial: m.nombreVisible.isNotEmpty ? m.nombreVisible[0].toUpperCase() : '?',
          radius: 22,
          backgroundColor: c.lilac,
          textColor: c.lilacInk,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                m.nombreVisible,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: c.ink),
              ),
              if (m.email.isNotEmpty && m.email != m.nombreVisible)
                Text(m.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: SpText.caption.copyWith(color: c.inkMuted)),
              if (m.desde != null)
                Text('En el equipo desde ${formatearFecha(m.desde!)}', style: SpText.caption.copyWith(color: c.inkMuted)),
            ],
          ),
        ),
        _ocupado == m.uid
            ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: c.primary))
            : SpMiniButton(
                icon: Icons.person_remove_alt_1_outlined,
                tooltip: 'Quitar del equipo',
                danger: true,
                onTap: () => _quitar(m),
              ),
      ],
    ),
  );

  Widget _filaInvitacion(SpColors c, InvitacionEquipo i) => Container(
    key: ValueKey('invitacion_${i.id}'),
    padding: const EdgeInsets.all(SpSpace.s3),
    decoration: SpDeco.card(c),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: c.butter, borderRadius: BorderRadius.circular(SpRadius.sm)),
          child: Icon(Icons.mark_email_unread_outlined, color: c.butterInk),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(i.emailDestino, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: c.ink)),
              Text(i.venceEnTexto(DateTime.now()), style: SpText.caption.copyWith(color: c.inkMuted)),
            ],
          ),
        ),
        _ocupado == i.id
            ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: c.primary))
            : SpMiniButton(
                icon: Icons.close_rounded,
                tooltip: 'Cancelar invitación',
                danger: true,
                onTap: () => _cancelar(i),
              ),
      ],
    ),
  );
}

/// Hoja para invitar por correo. Muestra el error del servidor ahí mismo
/// (ya invitada, correo inválido) sin cerrar la hoja.
class _InvitarSheet extends StatefulWidget {
  const _InvitarSheet({required this.repo});
  final EquipoRepository repo;

  @override
  State<_InvitarSheet> createState() => _InvitarSheetState();
}

class _InvitarSheetState extends State<_InvitarSheet> {
  final _emailCtl = TextEditingController();
  bool _enviando = false;
  EquipoError? _error;

  String get _email => _emailCtl.text.trim();
  bool get _valido => _email.isNotEmpty && esEmailValido(_email);

  @override
  void dispose() {
    _emailCtl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (!_valido || _enviando) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await widget.repo.invitar(_email);
      if (mounted) Navigator.pop(context, EquipoRepository.normalizarEmail(_email));
    } on EquipoError catch (e) {
      if (mounted) setState(() => _error = e);
    } catch (e) {
      if (mounted) setState(() => _error = EquipoError(EquipoError.mensajeDe(e)));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SpAgarradera(),
            const SizedBox(height: 16),
            const SpHojaTitulo(
              'Invitar al equipo',
              subtitulo: 'La persona entra a Salva Patitas con este correo y acepta la invitación desde su perfil.',
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _emailCtl,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _enviar(),
              decoration: InputDecoration(
                labelText: 'Correo de la persona',
                errorText: _email.isNotEmpty && !esEmailValido(_email) ? avisoEmailCorto : null,
              ),
            ),
            const SizedBox(height: 6),
            // Las invitaciones se reconocen por el correo de la cuenta de
            // Google con la que la persona entra; con otro correo no la ve.
            Text(
              'Usá el correo con el que esa persona entra a Salva Patitas.',
              style: SpText.caption.copyWith(color: c.inkMuted),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              SpNotice(
                fondo: c.dangerSoft,
                tinta: c.danger,
                child: Text(_error!.mensaje, style: SpText.label.copyWith(color: c.danger, fontWeight: FontWeight.w600)),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: SpButton(
                label: 'Enviar invitación',
                icon: Icons.send_rounded,
                cargando: _enviando,
                onTap: _valido ? _enviar : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Qué ve y qué no ve el equipo, en tres bloques cortos (pedido de Eliza:
/// el texto corrido no se entendía).
class _QuePuedeVer extends StatelessWidget {
  const _QuePuedeVer({required this.tinta});
  final Color tinta;

  @override
  Widget build(BuildContext context) {
    final normal = SpText.label.copyWith(color: tinta, fontWeight: FontWeight.w500, height: 1.35);
    final fuerte = normal.copyWith(fontWeight: FontWeight.w800);
    Widget linea(String texto) => Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('✓ ', style: fuerte),
          Expanded(child: Text(texto, style: normal)),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Qué puede hacer tu equipo', style: fuerte),
        linea('Cargar y editar animalitos, a nombre del albergue.'),
        linea('Responder los chats del albergue.'),
        linea('Ver, agregar, editar y borrar hogares de paso.'),
        linea('Borrar solo los animalitos que cargó cada persona.'),
        const SizedBox(height: 8),
        Text.rich(TextSpan(children: [
          TextSpan(text: 'Lo que es solo tuyo: ', style: fuerte),
          TextSpan(
            text: 'aprobar o rechazar solicitudes, marcar un animalito como fallecido, editar el perfil e invitar o quitar personas.',
            style: normal,
          ),
        ])),
        const SizedBox(height: 8),
        Text.rich(TextSpan(children: [
          TextSpan(text: 'Qué no ve: ', style: fuerte),
          TextSpan(text: 'tus chats personales ni tus consultas a negocios aliados.', style: normal),
        ])),
      ],
    );
  }
}
