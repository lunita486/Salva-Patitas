import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../domain/reglas_negocio.dart';
import '../widgets/avatares.dart';
import '../widgets/cambiar_rol_debug.dart';
import '../widgets/dialogo_cerrar_sesion.dart';
import '../widgets/estado_error_feed.dart';
import '../widgets/fondo_decorativo.dart';
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

  static const _catColor = {
    'Baño y peluquería': Color(0xFF1565C0),
    'Veterinaria': Color(0xFFB71C1C),
    'Tienda': Color(0xFF6A1B9A),
    'Adiestramiento': Color(0xFFF57F17),
    'Transporte': Color(0xFFE65100),
    'Otro': appTeal,
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

  // El diálogo/escritura viven en mostrarCambiarRolDebug (widgets/cambiar_rol_debug.dart,
  // compartida entre 5 pantallas que antes cada una tenía su propia copia
  // — hallazgo de auditoría de código).
  Future<void> _cambiarRolDebug() => mostrarCambiarRolDebug(context);

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
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
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
      pendiente: 'Esto está tardando. Se va a eliminar solo apenas vuelva la señal.',
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
              backgroundColor: appBg,
              floatingActionButton: kDebugMode
                  ? FloatingActionButton.small(
                      heroTag: 'debug_rol',
                      onPressed: _cambiarRolDebug,
                      backgroundColor: Colors.purple.shade100,
                      elevation: 4,
                      tooltip: 'Cambiar rol (debug)',
                      child: Icon(
                        Icons.developer_mode,
                        color: Colors.purple.shade700,
                      ),
                    )
                  : null,
              bottomNavigationBar: _bottomNav(chatsNuevos),
              body: Stack(
                children: [
                  const Positioned.fill(child: LeafOverlay()),
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
              (d) => servicioEstaActivo(
                (d.data() as Map).cast<String, dynamic>(),
              ),
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
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──────────────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF0A5C40), appTeal],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    children: [
                      // Avatar grande
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.5),
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        // AvatarPersona (widgets/avatares.dart), no un
                        // CircleAvatar armado a mano: con
                        // onBackgroundImageError vacío, si la foto fallaba
                        // al cargar quedaba un círculo vacío en vez de caer
                        // a las iniciales. Hallazgo de auditoría de código.
                        child: AvatarPersona(
                          fotoBase64: foto,
                          inicial: iniciales,
                          radius: 52,
                          backgroundColor: Colors.white.withValues(
                            alpha: 0.2,
                          ),
                          textColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextoSinDesborde(
                        texto: nombre,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                        mainAxisAlignment: MainAxisAlignment.center,
                        despues: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Color(0xFF4ADE80),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      if (tipo.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          tipo,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // ── Stats ────────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: Row(
                    children: [
                      _statCard(
                        '$activos',
                        'Servicios\nactivos',
                        const Color(0xFFD8F0E4),
                        appTeal,
                        Icons.spa_outlined,
                        onTap: () => setState(() => _nav = 1),
                      ),
                      const SizedBox(width: 12),
                      _statCard(
                        '${servicios.length}',
                        'Servicios\ntotales',
                        Colors.white,
                        const Color(0xFF444444),
                        Icons.list_alt_outlined,
                        onTap: () => setState(() => _nav = 1),
                      ),
                      const SizedBox(width: 12),
                      _statCard(
                        '$chatsNuevos',
                        'Mensajes\nnuevos',
                        const Color(0xFFFFF0E6),
                        appOrange,
                        Icons.chat_bubble_outline,
                        onTap: () => context.push(
                          AppRoutes.adoptanteChats,
                          extra: (
                            esRescatista: true,
                            soloConsultas: true,
                            esAlbergue: false,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Acceso rápido ─────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                  child: Text(
                    'ACCIONES RÁPIDAS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _quickAction(
                        Icons.add_circle_outline,
                        'Nuevo\nservicio',
                        appTeal,
                        () {
                          context.push(AppRoutes.subirServicio);
                        },
                      ),
                      const SizedBox(width: 12),
                      _quickAction(
                        Icons.list_alt_outlined,
                        'Ver\nservicios',
                        const Color(0xFF444444),
                        () {
                          setState(() => _nav = 1);
                        },
                      ),
                      const SizedBox(width: 12),
                      _quickAction(
                        Icons.chat_bubble_outline,
                        'Ver\nchats',
                        appOrange,
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
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'CONVERSACIONES RECIENTES',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => context.push(
                            AppRoutes.adoptanteChats,
                            extra: (
                              esRescatista: true,
                              soloConsultas: true,
                              esAlbergue: false,
                            ),
                          ),
                          child: const Text(
                            'Ver todas',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: appTeal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
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
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          AvatarUsuario(
                            userId: d['adoptanteId'] as String?,
                            inicial: ini,
                            radius: 20,
                            backgroundColor: appTeal.withValues(alpha: 0.12),
                            textColor: appTeal,
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
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: appInk,
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
                                        color: appTeal.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        rotulo,
                                        style: const TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: appTeal,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (ultimo.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    ultimo,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
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
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                              if (noLeidos > 0) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: appOrange,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '$noLeidos',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
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

  Widget _statCard(
    String valor,
    String label,
    Color bg,
    Color color,
    IconData icon, {
    VoidCallback? onTap,
  }) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color.withValues(alpha: 0.7)),
            const SizedBox(height: 8),
            Text(
              valor,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color.withValues(alpha: 0.75),
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _quickAction(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  // ── Catálogo ─────────────────────────────────────────────────────────────────

  Widget _catalogoTab(String nombre, String? foto, String iniciales) {
    return StreamBuilder<QuerySnapshot>(
      stream: _serviciosStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: appTeal));
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
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'MIS SERVICIOS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                            color: appTeal,
                          ),
                        ),
                        const Text(
                          'Servicios activos',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: appInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.push(AppRoutes.subirServicio),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: appTeal,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, color: Colors.white, size: 16),
                          SizedBox(width: 4),
                          Text(
                            'Nuevo',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Lista
            Expanded(
              child: docs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.spa_outlined,
                            size: 56,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Sin servicios publicados',
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Toca "Nuevo" para agregar el primero',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      itemCount: docs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final doc = docs[i];
                        final d = doc.data() as Map<String, dynamic>;
                        final sNombre = d['nombre'] as String? ?? '';
                        final precio = d['precio'] as int? ?? 0;
                        final desc = d['descripcion'] as String? ?? '';
                        final activo = servicioEstaActivo(d);
                        final cat = d['categoria'] as String? ?? '';
                        final catColor = _catColor[cat] ?? appTeal;
                        final catEmoji = _catEmoji[cat] ?? '🐾';

                        return Container(
                          key: ValueKey(doc.id),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: catColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
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
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: appInk,
                                          ),
                                        ),
                                        if (desc.isNotEmpty) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            desc,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade700,
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
                                          fontWeight: FontWeight.bold,
                                          color: catColor,
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
                                                ? appTeal
                                                : Colors.grey.shade300,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
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
                                                decoration: const BoxDecoration(
                                                  color: Colors.white,
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
                                  _miniBtn(
                                    Icons.edit_outlined,
                                    'Editar',
                                    Colors.grey.shade700,
                                    Colors.grey.shade50,
                                    Colors.grey.shade200,
                                    () => context.push(
                                      AppRoutes.subirServicio,
                                      extra: (docId: doc.id, data: d),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _miniBtn(
                                    Icons.delete_outline,
                                    'Eliminar',
                                    Colors.red.shade400,
                                    Colors.red.shade50,
                                    Colors.red.shade100,
                                    () => _eliminarServicio(doc.id),
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

  Widget _miniBtn(
    IconData icon,
    String label,
    Color fg,
    Color bg,
    Color border,
    VoidCallback onTap,
  ) => Tooltip(
    message: label,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: Icon(icon, size: 16, color: fg),
      ),
    ),
  );

  // ── Perfil ────────────────────────────────────────────────────────────────────

  Widget _perfilTab(
    String nombre,
    String tipo,
    String? foto,
    String iniciales,
  ) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Header verde
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0A5C40), appTeal],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.5),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: AvatarPersona(
                    fotoBase64: foto,
                    inicial: iniciales,
                    radius: 52,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    textColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  nombre,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (tipo.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    tipo,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => context.push(AppRoutes.aliadoPerfil),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Editar perfil del negocio'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: appTeal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => mostrarDialogoCerrarSesion(context),
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Cerrar sesión'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade400,
                      side: BorderSide(color: Colors.red.shade200),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => mostrarEliminarCuentaDialog(
                      context,
                      mostrarParrafoAdopciones: false,
                    ),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Eliminar mi cuenta'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade200),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
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
        ],
      ),
    );
  }

  // ── Bottom Nav ───────────────────────────────────────────────────────────────

  Widget _bottomNav(int chatsNuevos) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.07),
          blurRadius: 12,
          offset: const Offset(0, -2),
        ),
      ],
    ),
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(Icons.dashboard_outlined, Icons.dashboard, 'Panel', 0),
            _navItem(Icons.spa_outlined, Icons.spa, 'Servicios', 1),
            _navTapBadge(
              Icons.chat_bubble_outline,
              Icons.chat_bubble,
              'Chats',
              chatsNuevos,
              () => context.push(
                AppRoutes.adoptanteChats,
                extra: (
                  esRescatista: true,
                  soloConsultas: true,
                  esAlbergue: false,
                ),
              ),
            ),
            _navItem(Icons.person_outline, Icons.person, 'Perfil', 2),
          ],
        ),
      ),
    ),
  );

  Widget _navItem(IconData icon, IconData iconActive, String label, int idx) {
    final active = _nav == idx;
    return GestureDetector(
      onTap: () => setState(() => _nav = idx),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? iconActive : icon,
            color: active ? appTeal : Colors.grey.shade400,
            size: 24,
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: active ? appTeal : Colors.grey.shade400,
              fontWeight: active ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _navTapBadge(
    IconData icon,
    IconData iconActive,
    String label,
    int badge,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, color: Colors.grey.shade400, size: 24),
              if (badge > 0)
                Positioned(
                  top: -4,
                  right: -6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    decoration: const BoxDecoration(
                      color: appOrange,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      badge > 9 ? '9+' : '$badge',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }
}
