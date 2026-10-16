import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart' show aliadoTipoIcono;
import '../theme/salva_patitas_theme.dart';
import '../widgets/apariencia_sheet.dart';
import '../widgets/sp_widgets.dart';
import '../widgets/boton_cambiar_rol.dart';
import '../domain/reglas_negocio.dart';
import '../widgets/avatares.dart';
import '../widgets/dialogo_cerrar_sesion.dart';
import '../widgets/estado_error_feed.dart';
import '../widgets/resultado_guardado_snackbar.dart';
import '../widgets/texto_sin_desborde.dart';
import '../services/notificaciones_service.dart';
import '../data/chats_repository.dart';
import '../data/creator_role.dart';
import '../data/firestore_resiliencia.dart';
import '../data/servicios_repository.dart';
import 'package:go_router/go_router.dart';
import '../routing/app_router.dart';
import 'eliminar_cuenta_dialog.dart';

class AliadoHomeScreen extends StatefulWidget {
  const AliadoHomeScreen({super.key});
  @override
  State<AliadoHomeScreen> createState() => _AliadoHomeScreenState();
}

class _AliadoHomeScreenState extends State<AliadoHomeScreen> {
  int _nav = 0;
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  // Antes cada uno de estos 3 streams se armaba de nuevo (nueva instancia
  // de Stream) cada vez que build() corría — lo que pasa con CUALQUIER
  // setState de esta pantalla, incluido simplemente tocar el menú de
  // abajo (_nav). Como el body usa IndexedStack (mantiene las 3 pestañas
  // vivas a la vez, no las arma de nuevo al cambiar), esto tiraba abajo y
  // volvía a levantar los listeners de las 3 pestañas juntas en cada
  // toque, con el parpadeo visible de "cargando" que eso genera — para
  // datos que ya estaban cargados y no habían cambiado. De yapa, dos de
  // estas 3 consultas estaban DUPLICADAS (misma consulta armada en dos
  // lugares distintos, cada una con su propio listener): ahora es un solo
  // listener compartido. `late final`: se arman una sola vez, la primera
  // vez que hacen falta. Hallazgo de auditoría de código.
  late final Stream<DocumentSnapshot> _perfilStream = FirebaseFirestore.instance
      .collection('usuarios')
      .doc(_uid)
      .snapshots();
  // ServiciosRepository.deAliado — TODOS los servicios, activos y
  // apagados: esta es la lista propia del negocio, donde ver los apagados
  // es el punto (están ahí para poder volver a encenderlos).
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _serviciosStream =
      ServiciosRepository().deAliado(_uid);
  late final Stream<QuerySnapshot> _consultasStream = ChatsRepository()
      .consultasRecibidas(uid: _uid);

  static const _catEmoji = {
    'Baño y peluquería': '🛁',
    'Veterinaria': '🩺',
    'Tienda': '🛍️',
    'Adiestramiento': '🎓',
    'Transporte': '🚗',
    'Otro': '🐾',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        NotificacionesService.guardarToken();
        NotificacionesService.escucharEnPrimerPlano(context);
      }
    });
  }

  // guardarConAviso, no un await directo suelto (lo que había acá antes,
  // sin try/catch ni aviso de ningún tipo): mismo bug encontrado y
  // arreglado ya 3 veces en otras pantallas de esta colección/app
  // (albergue_perfil_screen.dart, aliado_perfil_screen.dart,
  // subir_servicio_screen.dart) y nunca replicado acá — si esto fallaba de
  // verdad (offline, permission-denied), el switch se veía cambiar en la
  // UI pero nada se guardaba, sin ningún aviso. Hallazgo de auditoría de
  // código.
  Future<void> _toggleActivo(String docId, bool actual) async {
    final resultado = await guardarConAviso(
      () => ServiciosRepository().alternarActivo(
        servicioId: docId,
        activoAhora: actual,
      ),
    );
    if (!mounted) return;
    mostrarResultadoGuardado(context, resultado);
  }

  Future<void> _eliminarServicio(String docId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Eliminar servicio'),
        content: const Text('¿Seguro que querés eliminar este servicio?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: ctx.sp.danger),
            child: const Text(
              'Eliminar',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final resultado = await guardarConAviso(
      () => ServiciosRepository().eliminar(docId),
    );
    if (!mounted) return;
    mostrarResultadoGuardado(
      context,
      resultado,
      pendiente:
          'Esto está tardando. Se va a eliminar solo apenas vuelva la señal.',
      fallo: 'No se pudo eliminar. Revisá tu conexión e intentá de nuevo.',
    );
  }

  String _fmt(int precio) {
    final s = precio.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _perfilStream,
      builder: (context, userSnap) {
        final data = userSnap.data?.data() as Map<String, dynamic>? ?? {};
        final nombre = data['aliadoNombre'] as String? ?? 'Mi negocio';
        final tipo = data['aliadoTipo'] as String? ?? '';
        final foto = data['aliadoFotoBase64'] as String?;
        final iniciales = nombre
            .trim()
            .split(' ')
            .take(2)
            .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
            .join();

        // Único lugar que calcula "mensajes nuevos" de este aliado — el
        // panel (_statCard más abajo) y el ícono de Chats de _bottomNav
        // reciben el mismo número ya calculado en vez de suscribirse cada
        // uno por su cuenta a _consultasStream y recalcularlo por separado.
        // Antes cada uno tenía su propio StreamBuilder, y el del panel
        // aplicaba un filtro (solo chats con vista previa) que el de
        // _bottomNav no tenía — mismo bug real que ya se encontró y
        // arregló del lado del rescatista/albergue (home_screen.dart,
        // ChatsRepository.noLeidosPara): un chat con mensajes sin leer
        // pero sin vista previa podía contar distinto en el panel que en
        // el ícono de abajo. `soloConsultas: true` porque esta es la
        // bandeja propia del aliado — sin eso, una autoconsulta (el aliado
        // contactándose a sí mismo) haría mirar el campo equivocado.
        return StreamBuilder<QuerySnapshot>(
          stream: _consultasStream,
          builder: (context, chatSnap) {
            final consultaDocs = chatSnap.data?.docs ?? [];
            final chatsNuevos = consultaDocs.where((d) {
              final data = d.data() as Map<String, dynamic>;
              return ChatsRepository.noLeidosPara(
                    data,
                    uid: _uid,
                    esRescatista: true,
                    soloConsultas: true,
                  ) >
                  0;
            }).length;

            return Scaffold(
              backgroundColor: context.sp.bg,
              floatingActionButton: botonCambiarRol(
                context,
                heroTag: 'debug_rol',
              ),
              bottomNavigationBar: _bottomNav(chatsNuevos),
              body: Stack(
                children: [
                  const Positioned.fill(child: SpPawBackground()),
                  SafeArea(
                    child: IndexedStack(
                      index: _nav,
                      children: [
                        _panelTab(
                          nombre,
                          tipo,
                          foto,
                          iniciales,
                          consultaDocs,
                          chatsNuevos,
                        ),
                        _catalogoTab(nombre, foto, iniciales),
                        _perfilTab(nombre, tipo, foto, iniciales),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── Panel ────────────────────────────────────────────────────────────────────

  Widget _panelTab(
    String nombre,
    String tipo,
    String? foto,
    String iniciales,
    List<QueryDocumentSnapshot> consultaDocs,
    int chatsNuevos,
  ) {
    return StreamBuilder<QuerySnapshot>(
      stream: _serviciosStream,
      builder: (context, svcSnap) {
        final servicios = svcSnap.data?.docs ?? [];
        final activos = servicios
            // servicioEstaActivo (domain/reglas_negocio.dart) — misma
            // fuente que la lista de abajo, que usaba otro criterio.
            .where(
              (d) =>
                  servicioEstaActivo((d.data() as Map).cast<String, dynamic>()),
            )
            .length;

        // Sin vista previa (chat creado pero nunca escrito) no vale la
        // pena mostrarlo en "Conversaciones recientes" — a diferencia de
        // `chatsNuevos` (arriba en build()), esto es solo para decidir QUÉ
        // MOSTRAR acá, no cuánto contar, así que si el conteo y esta lista
        // usaran el mismo filtro, un chat con mensajes sin leer pero sin
        // preview podía contarse arriba y no aparecer nunca acá abajo.
        final chats =
            consultaDocs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                return ((data['ultimoMensaje'] as String?) ?? '').isNotEmpty;
              }).toList()
              // consultasRecibidas() no trae los docs ordenados (sin
              // orderBy, para no depender de un índice compuesto) — sin
              // este sort, `.take(3)` de más abajo se quedaba con lo que
              // Firestore devolviera en cualquier orden, no con las 3
              // conversaciones más nuevas. Mismo criterio que
              // adoptante_chats_screen.dart._listaChats(). Hallazgo real de
              // Eliza: mandó 3 consultas nuevas (como adoptante, rescatista
              // y albergue) y "Conversaciones recientes" mostró solo 2,
              // más una conversación vieja ya leída en el lugar de la
              // tercera — el contador de arriba (que sí cuenta bien) decía
              // 3, pero la lista no las mostraba a las 3.
              ..sort((a, b) {
                final ta = (a.data() as Map)['ultimoMensajeEn'] as Timestamp?;
                final tb = (b.data() as Map)['ultimoMensajeEn'] as Timestamp?;
                if (ta == null && tb == null) return 0;
                if (ta == null) return 1;
                if (tb == null) return -1;
                return tb.compareTo(ta);
              });
        {
          final c = context.sp;
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Héroe: el negocio ───────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(SpSpace.s4),
                    decoration: SpDeco.primary(
                      c,
                      radius: SpRadius.xl,
                      gradient: true,
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: SpDeco.soft(c, radius: SpRadius.full),
                          // AvatarPersona (widgets/avatares.dart), no un
                          // CircleAvatar armado a mano: con
                          // onBackgroundImageError vacío, si la foto fallaba
                          // al cargar quedaba un círculo vacío en vez de caer
                          // a las iniciales. Hallazgo de auditoría de código.
                          child: AvatarPersona(
                            fotoBase64: foto,
                            inicial: iniciales,
                            radius: 34,
                            backgroundColor: c.mint,
                            textColor: c.primaryStrong,
                          ),
                        ),
                        const SizedBox(width: SpSpace.s4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Tu negocio hoy',
                                style: SpText.label.copyWith(
                                  color: c.onPrimary.withValues(alpha: .85),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextoSinDesborde(
                                texto: nombre,
                                style: SpText.title.copyWith(
                                  color: c.onPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                                despues: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: SpDeco.shine,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              if (tipo.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: SpDeco.shine.withValues(alpha: .55),
                                    borderRadius: BorderRadius.circular(
                                      SpRadius.full,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        aliadoTipoIcono(tipo),
                                        size: 14,
                                        color: c.onPrimary,
                                      ),
                                      const SizedBox(width: 5),
                                      Flexible(
                                        child: Text(
                                          tipo,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: SpText.caption.copyWith(
                                            color: c.onPrimary,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Cifras ───────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: SpMiniStat(
                          tone: SpTone.mint,
                          animal: SpAnimalKind.huella,
                          value: '$activos',
                          label: 'Activos',
                          onTap: () => setState(() => _nav = 1),
                        ),
                      ),
                      const SizedBox(width: SpSpace.s3),
                      Expanded(
                        child: SpMiniStat(
                          tone: SpTone.sky,
                          animal: SpAnimalKind.conejo,
                          value: '${servicios.length}',
                          label: 'En total',
                          onTap: () => setState(() => _nav = 1),
                        ),
                      ),
                      const SizedBox(width: SpSpace.s3),
                      Expanded(
                        child: SpMiniStat(
                          tone: SpTone.peach,
                          animal: SpAnimalKind.gato,
                          value: '$chatsNuevos',
                          label: 'Mensajes',
                          onTap: () => context.push(
                            AppRoutes.adoptanteChats,
                            extra: (
                              esRescatista: true,
                              soloConsultas: true,
                              esAlbergue: false,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Acciones rápidas ─────────────────────────────────────────
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
                  child: SpSectionTitle('Acciones rápidas'),
                ),
                const SizedBox(height: SpSpace.s3),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _quickAction(
                        Icons.add_rounded,
                        'Nuevo\nservicio',
                        SpTone.mint,
                        () {
                          context.push(AppRoutes.subirServicio);
                        },
                      ),
                      const SizedBox(width: SpSpace.s3),
                      _quickAction(
                        Icons.list_alt_rounded,
                        'Ver\nservicios',
                        SpTone.sky,
                        () {
                          setState(() => _nav = 1);
                        },
                      ),
                      const SizedBox(width: SpSpace.s3),
                      _quickAction(
                        Icons.chat_bubble_outline_rounded,
                        'Ver\nchats',
                        SpTone.peach,
                        () {
                          context.push(
                            AppRoutes.adoptanteChats,
                            extra: (
                              esRescatista: true,
                              soloConsultas: true,
                              esAlbergue: false,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                // ── Últimos chats ─────────────────────────────────────────────
                if (chats.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
                    child: SpSectionTitle(
                      'Conversaciones recientes',
                      trailing: SpLink(
                        'Ver todas',
                        onTap: () => context.push(
                          AppRoutes.adoptanteChats,
                          extra: (
                            esRescatista: true,
                            soloConsultas: true,
                            esAlbergue: false,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: SpSpace.s3),
                  ...chats.take(3).map((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    final quien = d['adoptanteNombre'] as String? ?? 'Usuario';
                    final ultimo = d['ultimoMensaje'] as String? ?? '';
                    final hora = d['ultimaHora'] as String? ?? '';
                    // ChatsRepository.noLeidosPara, NO leer
                    // `noLeidosRescatista` a mano — que es como estaba, y
                    // dejaba a ESTA MISMA PANTALLA usando dos criterios
                    // distintos para la misma pregunta: el contador de
                    // arriba (chatsNuevos) ya usaba la función compartida.
                    // La diferencia no es teórica: en una autoconsulta (el
                    // aliado escribiéndose a sí mismo, que pasa probando
                    // con una sola cuenta) la función mira el OTRO campo, y
                    // la lectura cruda contaba mal. Es exactamente el bug
                    // que la propia función documenta haber arreglado entre
                    // el panel y la lista de chats.
                    final noLeidos = ChatsRepository.noLeidosPara(
                      d,
                      uid: _uid,
                      esRescatista: true,
                      soloConsultas: true,
                    );
                    final ini = quien.isNotEmpty ? quien[0].toUpperCase() : 'U';
                    // Con qué sombrero te escribió — sin esto, la misma
                    // persona contactándote como adoptante, rescatista y
                    // albergue aparece 3 veces con el mismo nombre y sin
                    // forma de distinguirlas.
                    // rotuloDeQuienContacto (data/creator_role.dart) es la
                    // única fuente de este rótulo — el encabezado del chat
                    // abierto (chat_screen.dart) muestra ESTE MISMO dato
                    // sobre la misma conversación, y antes cada uno tenía
                    // su propia copia de la cadena de condiciones.
                    final rotulo = rotuloDeQuienContacto(
                      d['creadoPor'] as String?,
                    );
                    return Container(
                      key: ValueKey(doc.id),
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      padding: const EdgeInsets.all(14),
                      decoration: SpDeco.card(c, radius: SpRadius.lg),
                      child: Row(
                        children: [
                          AvatarUsuario(
                            userId: d['adoptanteId'] as String?,
                            inicial: ini,
                            radius: 22,
                            backgroundColor: c.sky,
                            textColor: c.skyInk,
                            // ChatsRepository.campoLogoAdoptante es la única
                            // fuente de "qué campo mirar para el logo de quien
                            // contactó" — no volver a derivarlo acá a mano.
                            campoLogoNegocio:
                                ChatsRepository.campoLogoAdoptante(d),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        quien,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: c.ink,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: c.lilac,
                                        borderRadius: BorderRadius.circular(
                                          SpRadius.full,
                                        ),
                                      ),
                                      child: Text(
                                        rotulo,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: c.lilacInk,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (ultimo.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    ultimo,
                                    style: SpText.caption.copyWith(
                                      color: c.inkMuted,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (hora.isNotEmpty)
                                Text(
                                  hora,
                                  style: SpText.caption.copyWith(
                                    color: c.inkFaint,
                                  ),
                                ),
                              if (noLeidos > 0) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: c.accent,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '$noLeidos',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: c.onAccent,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          );
        }
      },
    );
  }

  /// Acceso rápido: tarjeta blanca 3D con una baldosa pastel y el texto.
  Widget _quickAction(
    IconData icon,
    String label,
    SpTone tono,
    VoidCallback onTap,
  ) {
    final c = context.sp;
    final k = SpToneColors.of(c, tono);
    return Expanded(
      child: SpCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: SpDeco.tone(c, tono, radius: SpRadius.sm),
              child: Icon(icon, size: 22, color: k.ink),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: SpText.caption.copyWith(
                color: c.ink,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Catálogo ─────────────────────────────────────────────────────────────────

  Widget _catalogoTab(String nombre, String? foto, String iniciales) {
    return StreamBuilder<QuerySnapshot>(
      stream: _serviciosStream,
      builder: (context, snap) {
        final c = context.sp;
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: c.primary));
        }
        // Sin esto, un error real se veía igual que "todavía no publicaste
        // ningún servicio" — mismo patrón ya arreglado en
        // favoritos_screen.dart y otras pantallas (errorFeedState,
        // widgets/estado_error_feed.dart), acá en el catálogo del aliado (hallazgo de
        // auditoría de código).
        if (snap.hasError) return errorFeedState();
        final docs = (snap.data?.docs ?? [])
          ..sort((a, b) {
            final tA = (a.data() as Map)['creadoEn'] as Timestamp?;
            final tB = (b.data() as Map)['creadoEn'] as Timestamp?;
            if (tA == null) return 1;
            if (tB == null) return -1;
            return tB.compareTo(tA);
          });

        return Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mis servicios',
                          style: SpText.screen.copyWith(color: c.ink),
                        ),
                        Text(
                          'Lo que ofrece tu negocio',
                          style: SpText.label.copyWith(
                            color: c.inkMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SpButton(
                    label: 'Nuevo',
                    icon: Icons.add_rounded,
                    compacto: true,
                    onTap: () => context.push(AppRoutes.subirServicio),
                  ),
                ],
              ),
            ),

            // Lista
            Expanded(
              child: docs.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: SpEmpty(
                          title: 'Sin servicios publicados',
                          subtitle: 'Toca "Nuevo" para agregar el primero',
                          animal: SpAnimalKind.huella,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      itemCount: docs.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: SpSpace.s3),
                      itemBuilder: (_, i) {
                        final doc = docs[i];
                        final d = doc.data() as Map<String, dynamic>;
                        final sNombre = d['nombre'] as String? ?? '';
                        final precio = d['precio'] as int? ?? 0;
                        final desc = d['descripcion'] as String? ?? '';
                        final activo = servicioEstaActivo(d);
                        final cat = d['categoria'] as String? ?? '';
                        final tono = spToneCategoriaServicio(cat);
                        final k = SpToneColors.of(c, tono);
                        final catEmoji = _catEmoji[cat] ?? '🐾';

                        return Container(
                          key: ValueKey(doc.id),
                          padding: const EdgeInsets.all(SpSpace.s4),
                          decoration: SpDeco.card(c),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: SpDeco.tone(
                                      c,
                                      tono,
                                      radius: SpRadius.sm,
                                    ),
                                    child: Center(
                                      child: Text(
                                        catEmoji,
                                        style: const TextStyle(fontSize: 24),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          sNombre,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            color: c.ink,
                                          ),
                                        ),
                                        if (desc.isNotEmpty) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            desc,
                                            style: SpText.caption.copyWith(
                                              color: c.inkMuted,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '\$${_fmt(precio)}',
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                          color: k.ink,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      // Toggle
                                      GestureDetector(
                                        onTap: () =>
                                            _toggleActivo(doc.id, activo),
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          width: 44,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            color: activo
                                                ? c.primary
                                                : c.surfaceSunken,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: activo
                                                    ? c.primaryEdge
                                                    : c.edge,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: AnimatedAlign(
                                            duration: const Duration(
                                              milliseconds: 200,
                                            ),
                                            alignment: activo
                                                ? Alignment.centerRight
                                                : Alignment.centerLeft,
                                            child: Padding(
                                              padding: const EdgeInsets.all(2),
                                              child: Container(
                                                width: 20,
                                                height: 20,
                                                decoration: BoxDecoration(
                                                  color: c.surface,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  SpMiniButton(
                                    icon: Icons.edit_outlined,
                                    tooltip: 'Editar',
                                    onTap: () => context.push(
                                      AppRoutes.subirServicio,
                                      extra: (docId: doc.id, data: d),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SpMiniButton(
                                    icon: Icons.delete_outline_rounded,
                                    tooltip: 'Eliminar',
                                    danger: true,
                                    onTap: () => _eliminarServicio(doc.id),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  // ── Perfil ────────────────────────────────────────────────────────────────────

  Widget _perfilTab(
    String nombre,
    String tipo,
    String? foto,
    String iniciales,
  ) {
    final c = context.sp;
    final k = SpToneColors.of(c, spToneAliado(tipo));
    // Mismo diseño que el perfil del adoptante y del rescatista.
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SpScreenHeader(
            title: 'Perfil',
            subtitle: 'Tu negocio',
            conVolver: false,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: SpDeco.soft(c, radius: SpRadius.full),
                    child: AvatarPersona(
                      fotoBase64: foto,
                      inicial: iniciales,
                      radius: 54,
                      backgroundColor: k.fill,
                      textColor: k.ink,
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
                if (tipo.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: SpDeco.soft(c, radius: SpRadius.full),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(aliadoTipoIcono(tipo), size: 16, color: k.ink),
                          const SizedBox(width: 6),
                          Text(
                            tipo,
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
                ],
                const SizedBox(height: SpSpace.s6),
                const SpSectionTitle('Cuenta'),
                const SizedBox(height: SpSpace.s3),
                SpCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      SpFilaCuenta(
                        icono: Icons.storefront_outlined,
                        texto: 'Editar perfil del negocio',
                        tono: SpTone.mint,
                        onTap: () => context.push(AppRoutes.aliadoPerfil),
                      ),
                      // Acá NO va "Gestionar mis roles", y es a propósito.
                      //
                      // Estuvo un rato y había que sacarlo: la hoja de roles
                      // (widgets/roles_sheet.dart) solo ofrece Adoptante y
                      // Rescatista. No tiene casilla para Albergue ni para
                      // Aliado, y arranca copiando los roles que ya están,
                      // así que desde acá solo se podían AGREGAR roles, nunca
                      // salir de este.
                      //
                      // Y agregarlos no cambiaba nada: resolverPantallaPerfil
                      // (domain/resolucion_perfil.dart) manda a albergue y a
                      // aliado antes que a cualquier otro rol, así que
                      // después de guardar se volvía a aterrizar exactamente
                      // acá. Un botón que promete una salida y no la da es
                      // peor que no tenerlo.
                      //
                      // La salida de verdad sigue sin existir: quien tiene
                      // rol de negocio no puede volver al lado de
                      // adoptante/rescatista desde la app. Queda como trabajo
                      // para después del lanzamiento, y la forma que tiene
                      // más sentido es un cambio de VISTA (como el
                      // interruptor Adoptante/Rescatista que ya existe en el
                      // inicio), no tocar los roles guardados.
                      //
                      // Si estás por volver a poner este botón: no alcanza con
                      // ponerlo. Hay que hacer que la hoja o el enrutado
                      // permitan salir, o vuelve a no hacer nada.
                      const SpDivisorFilas(),
                      // Por ahora solo deja elegir Claro: el modo oscuro se
                      // habilita cuando esté revisado (ver
                      // widgets/apariencia_sheet.dart).
                      SpFilaCuenta(
                        icono: Icons.dark_mode_outlined,
                        texto: 'Apariencia',
                        sub: 'Claro',
                        tono: SpTone.lilac,
                        onTap: () => mostrarApariencia(context),
                      ),
                      const SpDivisorFilas(),
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
                    onPressed: () => mostrarEliminarCuentaDialog(
                      context,
                      mostrarParrafoAdopciones: false,
                    ),
                    style: TextButton.styleFrom(foregroundColor: c.danger),
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
    );
  }

  // ── Barra de abajo ───────────────────────────────────────────────────────────

  // Barra flotante 3D (SpTabBar), como la del resto de la app. Cada ítem
  // conserva su misma acción de siempre.
  Widget _bottomNav(int chatsNuevos) => SpTabBar(
    children: [
      _navItem(Icons.dashboard_rounded, 'Panel', 0),
      _navItem(Icons.spa_outlined, 'Servicios', 1),
      SpTabItem(
        icon: Icons.chat_bubble_outline_rounded,
        label: 'Chats',
        active: false,
        badge: chatsNuevos,
        onTap: () => context.push(
          AppRoutes.adoptanteChats,
          extra: (esRescatista: true, soloConsultas: true, esAlbergue: false),
        ),
      ),
      _navItem(Icons.person_outline_rounded, 'Perfil', 2),
    ],
  );

  Widget _navItem(IconData icon, String label, int idx) => SpTabItem(
    icon: icon,
    label: label,
    active: _nav == idx,
    onTap: () => setState(() => _nav = idx),
  );
}
