import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/salva_patitas_theme.dart';
import '../widgets/sp_widgets.dart';
import '../domain/reglas_negocio.dart';
import '../widgets/avatares.dart';
import '../widgets/campo_pais_telefono.dart';
import '../widgets/estado_error_feed.dart';
import '../widgets/resultado_guardado_snackbar.dart';
import '../data/equipo_repository.dart';
import '../data/hogares_de_paso_repository.dart';
import '../data/firestore_resiliencia.dart';

/// Roster de personas de confianza para hogar de paso — solo para
/// albergues (decisión de producto, mejoras_albergue.html). Las filas se
/// agregan solas al aprobar una solicitud de hogar de paso
/// (ver HogaresDePasoRepository.registrarAyuda en solicitudes_rescatista_screen.dart),
/// o a mano acá para alguien de confianza que el albergue ya conoce fuera
/// de la app.
class HogaresDePasoScreen extends StatefulWidget {
  const HogaresDePasoScreen({super.key});
  @override
  State<HogaresDePasoScreen> createState() => _HogaresDePasoScreenState();
}

class _HogaresDePasoScreenState extends State<HogaresDePasoScreen> {
  final _repo = HogaresDePasoRepository();
  final _equipo = EquipoRepository();
  // Hogar cuya decisión de equipo se está guardando (un toque a la vez).
  String? _revisando;

  /// Qué ve el equipo del albergue de este hogar. Lo decide solo la
  /// responsable, y lo guarda la Cloud Function revisarHogarEquipo (las
  /// reglas no dejan que la app escriba visibleEquipo/revisionEquipo).
  /// Ningún hogar se comparte por defecto.
  Future<void> _decidirEquipo(String docId, String nombre, bool? compartidoAhora) async {
    if (_revisando != null) return;
    final compartir = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (hoja) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SpAgarradera(),
            const SizedBox(height: 16),
            SpHojaTitulo(
              '¿Lo ve tu equipo?',
              subtitulo: 'Decidí si las personas de tu equipo pueden ver a $nombre y sus datos de contacto.',
            ),
            const SizedBox(height: 16),
            SpOpcionHoja(
              titulo: 'Compartir con mi equipo',
              detalle: 'Lo ven en "Hogares de paso compartidos"',
              icono: Icons.groups_2_outlined,
              tono: SpTone.mint,
              elegida: compartidoAhora == true,
              onTap: () => Navigator.pop(hoja, true),
            ),
            SpOpcionHoja(
              titulo: 'Solo yo',
              detalle: 'Tu equipo no lo ve',
              icono: Icons.lock_outline_rounded,
              tono: SpTone.lilac,
              elegida: compartidoAhora == false,
              onTap: () => Navigator.pop(hoja, false),
            ),
          ],
        ),
      ),
    );
    if (compartir == null || !mounted) return;
    setState(() => _revisando = docId);
    try {
      await _equipo.revisarHogar(docId, compartir: compartir);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(compartir ? 'Tu equipo ya puede ver a $nombre.' : 'Tu equipo no ve a $nombre.'),
          backgroundColor: context.sp.msgExito,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(EquipoError.mensajeDe(e)), backgroundColor: context.sp.msgError),
      );
    } finally {
      if (mounted) setState(() => _revisando = null);
    }
  }

  Widget _pillEquipo(SpColors c, String docId, String nombre, Map<String, dynamic> d) {
    final revisado = d['revisionEquipo'] is Map;
    final compartido = d['visibleEquipo'] == true;
    final estado = !revisado && !compartido ? null : compartido;
    if (_revisando == docId) {
      return SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: c.primary));
    }
    return GestureDetector(
      onTap: () => _decidirEquipo(docId, nombre, estado),
      child: SpPill(
        switch (estado) {
          true => 'Equipo: lo ve',
          false => 'Equipo: no lo ve',
          null => 'Equipo: sin decidir',
        },
        fondo: estado == true ? c.mint : (estado == false ? c.surfaceSunken : c.butter),
        tinta: estado == true ? c.primaryStrong : (estado == false ? c.inkMuted : c.butterInk),
        icon: estado == true ? Icons.groups_2_outlined : Icons.lock_outline_rounded,
      ),
    );
  }
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  // Sin este candado, dos toques en el botón "Agregar" (uno mientras la hoja
  // todavía está abriéndose, u otro porque la persona no vio ninguna
  // confirmación de que el primero funcionó — agregarManual() no avisaba
  // nada, ni éxito ni error) disparaban dos llamadas independientes a
  // agregarManual() con los mismos datos: dos filas separadas para la misma
  // persona. A diferencia de las filas automáticas (registrarAyuda(), que sí
  // fusiona por adoptanteId/email), una fila manual no tiene ninguna cuenta
  // real detrás con la que fusionarse después — el duplicado quedaba para
  // siempre. Bug real reportado, con foco explícito en que no se repita.
  bool _agregando = false;

  Future<void> _agregarManual() async {
    if (_agregando) return;
    setState(() => _agregando = true);
    try {
      final resultado = await showModalBottomSheet<Map<String, String>>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => const _AgregarHogarSheet(),
      );
      if (resultado == null || _uid.isEmpty) return;
      final nombreNuevo = resultado['nombre'] ?? '';
      final emailNuevo = resultado['email'] ?? '';
      // Aviso, no bloqueo. La identidad la decide el email (ver
      // buscarDuplicado): el nombre es texto libre y la misma persona lo
      // tipea distinto cada vez. Antes nada avisaba nada acá, así que
      // tocar "Agregar" y completar el formulario de nuevo por error (sin
      // ver ninguna confirmación clara de que ya había funcionado la
      // primera vez) dejaba la misma persona repetida en la red, sin
      // ninguna forma de fusionar esas filas después.
      final duplicado = await _repo.buscarDuplicado(
        albergueId: _uid,
        nombre: nombreNuevo,
        email: emailNuevo,
      );
      if (duplicado != null) {
        if (!mounted) return;
        final continuar = await showDialog<bool>(
          context: context,
          builder: (dlgCtx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Posible duplicado'),
            content: Text(
              // El nombre de la fila QUE YA ESTÁ, no el que se acaba de
              // tipear: con la identidad por email, la fila encontrada
              // puede llamarse distinto, y nombrar el texto nuevo decía
              // "ya tenés a X" señalando algo que no existe con ese
              // nombre.
              'Ya tenés a "${(duplicado.data()['nombre'] as String?) ?? nombreNuevo}" '
              'con este mismo email en tu red de hogares de paso. Si de '
              'verdad es una persona distinta, podés agregarla igual.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx, false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx, true),
                child: Text(
                  'Agregar igual',
                  style: TextStyle(color: context.sp.primaryStrong),
                ),
              ),
            ],
          ),
        );
        if (continuar != true) return;
      }
      if (!mounted) return;
      await _repo.agregarManual(
        albergueId: _uid,
        nombre: nombreNuevo,
        telefono: resultado['telefono'] ?? '',
        notas: resultado['notas'] ?? '',
        email: resultado['email'] ?? '',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${resultado['nombre']} se agregó a tu red.'),
            backgroundColor: context.sp.msgExito,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'No se pudo agregar. Revisá tu conexión e intentá de nuevo.',
            ),
            backgroundColor: context.sp.msgError,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _agregando = false);
    }
  }

  Future<void> _editarContacto(
    String docId,
    String telefonoActual,
    String notasActuales,
    String emailActual,
  ) async {
    final resultado = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _EditarContactoSheet(
        telefonoInicial: telefonoActual,
        notasIniciales: notasActuales,
        emailInicial: emailActual,
      ),
    );
    if (resultado == null) return;
    // guardarConAviso, no un await directo suelto (lo que había acá antes,
    // sin siquiera un try/catch): sin señal, actualizarContacto() no
    // fallaba, se quedaba esperando al servidor para siempre — y aunque
    // fallara de verdad, no había nada que avisara nada. Hallazgo de
    // auditoría de código.
    final r = await guardarConAviso(
      () => _repo.actualizarContacto(
        docId,
        telefono: resultado['telefono'] ?? '',
        notas: resultado['notas'] ?? '',
        email: resultado['email'] ?? '',
      ),
    );
    if (!mounted) return;
    mostrarResultadoGuardado(context, r, exito: 'Contacto actualizado');
  }

  Future<void> _eliminar(String docId, String nombre) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Quitar de la red'),
        content: Text(
          '¿Seguro que querés quitar a $nombre de tu red de hogares de paso?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: Text('Quitar', style: TextStyle(color: context.sp.danger)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    final r = await guardarConAviso(() => _repo.eliminar(docId));
    if (!mounted) return;
    switch (r) {
      // Mismo criterio que editar_rescate_screen.dart al borrar un animal:
      // un borrado que quedó encolado sin señal SÍ se va a aplicar solo —
      // para la persona esto ES un borrado exitoso, avisar "falló" sería
      // mentirle.
      case ResultadoGuardado.confirmado:
      case ResultadoGuardado.siguePendiente:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$nombre se quitó de tu red.'),
            backgroundColor: context.sp.msgExito,
          ),
        );
      case ResultadoGuardado.fallo:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'No se pudo quitar. Revisá tu conexión e intentá de nuevo.',
            ),
            backgroundColor: context.sp.msgError,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    return Scaffold(
      backgroundColor: c.bg,
      floatingActionButton: _botonAgregar(c),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const SpPawBackground(),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SpScreenHeader(
                  title: 'Hogares de paso',
                  subtitle: 'Tu red de confianza',
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SpNotice(
                    fondo: c.butter,
                    tinta: c.butterInk,
                    child: Text(
                      'Personas de confianza que ya te ayudaron con hogar de paso. Se agregan solas cuando aprobás una solicitud.',
                      style: SpText.label.copyWith(
                        color: c.butterInk,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: SpSpace.s4),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _repo.deAlbergue(_uid),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return Center(
                          child: CircularProgressIndicator(color: c.primary),
                        );
                      }
                      if (snap.hasError) return errorFeedState();
                      final docs = (snap.data?.docs ?? []).toList()
                        ..sort((a, b) {
                          final va = a.data()['vecesAyudo'] as int? ?? 0;
                          final vb = b.data()['vecesAyudo'] as int? ?? 0;
                          return vb.compareTo(va);
                        });
                      if (docs.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: SpEmpty(
                              title:
                                  'Todavía no tenés hogares de paso en tu red',
                              subtitle:
                                  'Cuando apruebes una solicitud, la persona se agrega acá sola.',
                              animal: SpAnimalKind.casa,
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                        itemCount: docs.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: SpSpace.s3),
                        itemBuilder: (_, i) {
                          final d = docs[i].data();
                          final docId = docs[i].id;
                          final nombre = d['nombre'] as String? ?? 'Sin nombre';
                          final adoptanteId = d['adoptanteId'] as String? ?? '';
                          final veces = d['vecesAyudo'] as int? ?? 0;
                          final telefono = d['telefono'] as String? ?? '';
                          final notas = d['notas'] as String? ?? '';
                          final email = d['email'] as String? ?? '';
                          final ultimaVez = (d['ultimaVez'] as Timestamp?)
                              ?.toDate();
                          final linkWhatsapp = whatsappUrl(telefono);

                          return Container(
                            key: ValueKey(docId),
                            padding: const EdgeInsets.all(SpSpace.s4),
                            decoration: SpDeco.card(c),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    AvatarUsuario(
                                      userId: adoptanteId.isEmpty
                                          ? null
                                          : adoptanteId,
                                      inicial: nombre.isNotEmpty
                                          ? nombre[0].toUpperCase()
                                          : '?',
                                      radius: 24,
                                      backgroundColor: c.butter,
                                      textColor: c.butterInk,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            nombre,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 16,
                                              color: c.ink,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            veces == 1
                                                ? 'Ayudó 1 vez'
                                                : 'Ayudó $veces veces',
                                            style: SpText.caption.copyWith(
                                              color: c.inkMuted,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SpPill(
                                      '$veces',
                                      fondo: c.butter,
                                      tinta: c.butterInk,
                                      icon: Icons.favorite_rounded,
                                    ),
                                  ],
                                ),
                                if (ultimaVez != null || notas.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  if (ultimaVez != null)
                                    Text(
                                      'Última vez: ${formatearFecha(ultimaVez)}',
                                      style: SpText.caption.copyWith(
                                        color: c.inkMuted,
                                      ),
                                    ),
                                  if (notas.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      notas,
                                      style: SpText.label.copyWith(
                                        color: c.inkMuted,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ],
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    if (linkWhatsapp != null)
                                      GestureDetector(
                                        onTap: () => launchUrl(
                                          Uri.parse(linkWhatsapp),
                                          mode: LaunchMode.externalApplication,
                                        ),
                                        child: SpPill(
                                          'WhatsApp',
                                          fondo: c.primarySoft,
                                          tinta: c.primaryStrong,
                                          icon: Icons.chat_rounded,
                                        ),
                                      ),
                                    if (linkWhatsapp != null)
                                      const SizedBox(width: 8),
                                    Flexible(
                                      child: _pillEquipo(c, docId, nombre, d),
                                    ),
                                    const Spacer(),
                                    SpMiniButton(
                                      icon: Icons.edit_outlined,
                                      tooltip: 'Editar contacto',
                                      onTap: () => _editarContacto(
                                        docId,
                                        telefono,
                                        notas,
                                        email,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    SpMiniButton(
                                      icon: Icons.delete_outline_rounded,
                                      tooltip: 'Quitar',
                                      danger: true,
                                      onTap: () => _eliminar(docId, nombre),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "Agregar": píldora verde 3D. Mientras la hoja está abierta se ve
  /// apagada y no se puede tocar de nuevo (ver `_agregando`).
  Widget _botonAgregar(SpColors c) {
    final caja = Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: SpDeco.primary(c, radius: SpRadius.full),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_rounded, color: c.onPrimary),
          const SizedBox(width: 6),
          Text(
            'Agregar',
            style: TextStyle(
              color: c.onPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      enabled: !_agregando,
      child: _agregando
          ? Opacity(opacity: .5, child: caja)
          : SpPressable(onTap: _agregarManual, child: caja),
    );
  }
}

class _AgregarHogarSheet extends StatefulWidget {
  const _AgregarHogarSheet();
  @override
  State<_AgregarHogarSheet> createState() => _AgregarHogarSheetState();
}

class _AgregarHogarSheetState extends State<_AgregarHogarSheet> {
  final _nombreCtl = TextEditingController();
  final _telefonoCtl = TextEditingController();
  final _notasCtl = TextEditingController();
  final _emailCtl = TextEditingController();

  // Email obligatorio a propósito (antes era opcional): es el único dato
  // que distingue a dos personas reales con el mismo nombre — sin él,
  // buscarDuplicado() (HogaresDePasoRepository) no tiene con qué comparar
  // además del nombre solo, y avisar por nombre solo hubiera sido un falso
  // positivo molesto cada vez que dos personas de confianza distintas
  // comparten nombre. Pedido explícito de Eliza.
  // Dos reglas separadas a propósito, aunque `esEmailValido('')` ya sea
  // false: la obligatoriedad la decide esta pantalla (`isNotEmpty`) y la
  // FORMA la decide reglas_negocio (`esEmailValido`). Mismo reparto que en
  // los perfiles de Albergue y Aliado, donde el email es opcional y la
  // primera mitad es justo la contraria. Depender de que el validador de
  // forma diga que "" no tiene forma de email seria mezclarlas.
  //
  // El formato NO se validaba: solo se pedia que no estuviera vacio, asi
  // que "lunita486@gmail" (sin .com) entro a la red y sigue ahi. Ese campo
  // es la IDENTIDAD de la persona para buscarDuplicado, asi que un email
  // mal escrito no queda solo feo: rompe la fusion y deja una fila que no
  // se va a poder unir nunca.
  bool get _valido =>
      _nombreCtl.text.trim().isNotEmpty &&
      _emailCtl.text.trim().isNotEmpty &&
      esEmailValido(_emailCtl.text.trim());

  @override
  void dispose() {
    _nombreCtl.dispose();
    _telefonoCtl.dispose();
    _notasCtl.dispose();
    _emailCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SpAgarradera(),
            const SizedBox(height: 16),
            const SpHojaTitulo(
              'Agregar a la red',
              subtitulo:
                  'Alguien de confianza que ya conocés, aunque todavía no haya pedido hogar de paso por la app.',
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nombreCtl,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: _dec('Nombre *'),
            ),
            const SizedBox(height: 12),
            CampoTelefono(
              controller: _telefonoCtl,
              decoracionLocal: _dec('Teléfono / WhatsApp (opcional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notasCtl,
              maxLines: 2,
              decoration: _dec('Notas (opcional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailCtl,
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) => setState(() {}),
              // Mismo aviso que los perfiles de Albergue y Aliado, para que
              // el mismo error no se explique de dos formas distintas. Solo
              // aparece si escribio algo: el campo vacio ya lo bloquea el
              // boton, y decirle "no parece un email" a un campo en blanco
              // seria un regano gratis.
              decoration: _dec('Email *').copyWith(
                errorText:
                    _emailCtl.text.trim().isNotEmpty &&
                        !esEmailValido(_emailCtl.text.trim())
                    ? avisoEmailCorto
                    : null,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Sirve para no confundirla con otra persona del mismo nombre, y para '
              'sumar acá si más adelante pide hogar de paso por la app con este mismo email.',
              style: SpText.caption.copyWith(color: context.sp.inkMuted),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: SpButton(
                label: 'Agregar',
                onTap: _valido
                    ? () => Navigator.pop(context, {
                        'nombre': _nombreCtl.text.trim(),
                        'telefono': _telefonoCtl.text.trim(),
                        'notas': _notasCtl.text.trim(),
                        'email': _emailCtl.text.trim(),
                      })
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // El relleno y los bordes vienen del tema (inputDecorationTheme).
  InputDecoration _dec(String label) => InputDecoration(labelText: label);
}

// Deja completar teléfono/notas después — pedido real de Eliza: las filas
// que se agregan solas al aprobar una solicitud nacen sin esos datos, y
// antes no había forma de cargarlos más tarde. No se edita el nombre acá
// a propósito: para las filas automáticas viene de la cuenta real de esa
// persona, no tiene sentido dejar que el albergue lo reescriba.
class _EditarContactoSheet extends StatefulWidget {
  final String telefonoInicial;
  final String notasIniciales;
  final String emailInicial;
  const _EditarContactoSheet({
    required this.telefonoInicial,
    required this.notasIniciales,
    required this.emailInicial,
  });
  @override
  State<_EditarContactoSheet> createState() => _EditarContactoSheetState();
}

class _EditarContactoSheetState extends State<_EditarContactoSheet> {
  late final _telefonoCtl = TextEditingController(text: widget.telefonoInicial);
  late final _notasCtl = TextEditingController(text: widget.notasIniciales);
  late final _emailCtl = TextEditingController(text: widget.emailInicial);

  // Mismo motivo que _AgregarHogarSheet._valido: el email es el único dato
  // que distingue a dos personas reales con el mismo nombre para
  // buscarDuplicado() — esta hoja lo dejaba editable a "opcional" y sin
  // ninguna validación, así que un contacto agregado con email obligatorio
  // se podía editar para quedar SIN email, perdiendo esa protección en
  // silencio. Hallazgo de auditoría de código.
  // Y tiene que tener FORMA de email, no solo estar lleno: sin eso, un
  // contacto agregado con un email valido se podia editar dejandolo en
  // "lunita486@gmail" y la fusion por email quedaba rota igual. Las dos
  // reglas van separadas a proposito, ver _AgregarHogarSheet._valido.
  bool get _valido =>
      _emailCtl.text.trim().isNotEmpty && esEmailValido(_emailCtl.text.trim());

  @override
  void dispose() {
    _telefonoCtl.dispose();
    _notasCtl.dispose();
    _emailCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SpAgarradera(),
            const SizedBox(height: 16),
            const SpHojaTitulo('Editar contacto'),
            const SizedBox(height: 20),
            CampoTelefono(
              controller: _telefonoCtl,
              autofocus: true,
              decoracionLocal: _dec('Teléfono / WhatsApp (opcional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notasCtl,
              maxLines: 2,
              decoration: _dec('Notas (opcional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailCtl,
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) => setState(() {}),
              // Mismo aviso que los perfiles de Albergue y Aliado, para que
              // el mismo error no se explique de dos formas distintas. Solo
              // aparece si escribio algo: el campo vacio ya lo bloquea el
              // boton, y decirle "no parece un email" a un campo en blanco
              // seria un regano gratis.
              decoration: _dec('Email *').copyWith(
                errorText:
                    _emailCtl.text.trim().isNotEmpty &&
                        !esEmailValido(_emailCtl.text.trim())
                    ? avisoEmailCorto
                    : null,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: SpButton(
                label: 'Guardar',
                onTap: _valido
                    ? () => Navigator.pop(context, {
                        'telefono': _telefonoCtl.text.trim(),
                        'notas': _notasCtl.text.trim(),
                        'email': _emailCtl.text.trim(),
                      })
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // El relleno y los bordes vienen del tema (inputDecorationTheme).
  InputDecoration _dec(String label) => InputDecoration(labelText: label);
}
