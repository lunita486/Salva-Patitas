import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import '../theme.dart';
import '../widgets/campos_perfil.dart';
import '../domain/reglas_negocio.dart';
import '../routing/app_router.dart';
import '../widgets/avatares.dart';
import '../widgets/estado_error_feed.dart';
import '../data/chats_repository.dart';
import '../data/servicios_repository.dart';
import '../data/usuarios_repository.dart';

// A nivel de archivo, no de la instancia — evita que un doble toque en
// "Contactar" dispare dos llamadas en paralelo y empuje DOS ChatScreen a la
// pila de navegación (la persona tendría que tocar "atrás" dos veces para
// salir). Sigue acá afuera aunque la pantalla ya sea StatefulWidget: así el
// candado también cubre el caso de dos instancias distintas de esta pantalla
// abiertas sobre el mismo negocio, que un campo de instancia no vería. Con
// clave por aliadoId, no global: cada negocio tiene su propio candado. Mismo
// patrón que _solicitudesEnProceso en solicitudes_rescatista_screen.dart.
// Hallazgo de auditoría de código.
final Set<String> _contactandoAliados = {};

class AliadoPublicoScreen extends StatefulWidget {
  final String aliadoId;
  final bool esRescatista;
  final bool esAlbergue;
  const AliadoPublicoScreen({
    super.key,
    required this.aliadoId,
    this.esRescatista = false,
    this.esAlbergue = false,
  });

  @override
  State<AliadoPublicoScreen> createState() => _AliadoPublicoScreenState();
}

class _AliadoPublicoScreenState extends State<AliadoPublicoScreen> {
  // `late final`, no streams armados dentro de build(). Acá los dos
  // StreamBuilder están ANIDADOS (perfil del negocio por fuera, sus
  // servicios por dentro), así que con los streams inline cada cambio en el
  // doc del aliado hacía que el de adentro se desuscribiera y arrancara de
  // cero: la lista de servicios volvía al spinner y se repintaba sola.
  // Mismo patrón —y misma causa— que el parpadeo de la lista de chats.
  // Hallazgo de auditoría de código.
  late final Stream<DocumentSnapshot> _perfilStream = FirebaseFirestore.instance
      .collection('usuarios')
      .doc(widget.aliadoId)
      .snapshots();
  // ServiciosRepository.activosDeAliado — solo los ACTIVOS, que es lo que
  // ve un cliente. El filtro de "activo" lo aplica el repositorio con
  // servicioEstaActivo(), no una condición escrita acá.
  late final Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _serviciosStream = ServiciosRepository().activosDeAliado(widget.aliadoId);

  static const _categoriaEmoji = {
    'Baño y peluquería': '🛁',
    'Veterinaria': '🩺',
    'Tienda': '🛍️',
    'Adiestramiento': '🎓',
    'Transporte': '🚗',
    'Otro': '🐾',
  };

  Future<void> _contactar(
    BuildContext context,
    String nombre,
    String? fotoBase64,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    if (!_contactandoAliados.add(widget.aliadoId)) return;
    try {
      final contexto = !widget.esRescatista
          ? 'general'
          : (widget.esAlbergue ? 'albergue' : 'rescatista');
      // Al contactar "como albergue" hay que mostrar el nombre DEL ALBERGUE
      // (ej. "La Perla"), no el nombre personal de Google de quien lo
      // administra — el avatar de esa fila ya muestra el logo del albergue
      // (AvatarUsuario con esNegocio), así que el nombre tiene que ser
      // consistente con eso. Para rescatista/adoptante sí corresponde el
      // nombre personal — no existe un "nombre de negocio" para un
      // rescatista individual.
      var nombreContacto =
          FirebaseAuth.instance.currentUser?.displayName ?? 'Usuario';
      if (contexto == 'albergue') {
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('usuarios')
              .doc(uid)
              .get();
          // UsuariosRepository.nombrePropioDesde — misma regla compartida
          // que usan publicar un animal y los avisos automáticos, en vez de
          // la copia a mano que había acá. Solo se lee el perfil cuando de
          // verdad hace falta (contactar COMO albergue): para los otros
          // sombreros el nombre de la cuenta ya alcanza y no se toca la red.
          nombreContacto = UsuariosRepository.nombrePropioDesde(
            datosUsuario: userDoc.data(),
            creadoPor: 'albergue',
            nombreDeLaCuenta: nombreContacto,
          );
        } catch (_) {}
      }

      String chatId;
      try {
        chatId = await ChatsRepository().asegurarChatNegocio(
          adoptanteId: uid,
          adoptanteNombre: nombreContacto,
          aliadoId: widget.aliadoId,
          aliadoNombre: nombre,
          contexto: contexto,
          fotoBase64: fotoBase64,
        );
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: msgError,
              content: Text('No se pudo abrir el chat. Intentá de nuevo.'),
            ),
          );
        }
        return;
      }

      FirebaseAnalytics.instance
          .logEvent(
            name: 'aliado_contactado',
            parameters: {'aliado_id': widget.aliadoId},
          )
          .catchError((_) {});

      if (!context.mounted) return;
      context.push(
        AppRoutes.chat,
        extra: (
          esRescatista: false,
          chatId: chatId,
          animal: {
            'nombre': nombre,
            'rescatista': nombre,
            'rescatistaId': widget.aliadoId,
            'fotoBase64': fotoBase64,
            'tipoSolicitud': 'consulta_aliado',
            // Mismo condicional que asegurarChatNegocio (ChatsRepository)
            // usa para decidir si guarda 'creadoPor' en el doc — sin esto,
            // ChatScreen._abrirFicha (tocar "Conversando sobre X" desde
            // este chat recién abierto, antes de salir y reabrirlo desde
            // la lista) no tenía forma de saber con qué sombrero se
            // contactó, y "Contactar" de nuevo desde ahí fragmentaba la
            // conversación en un chat aparte con contexto "general".
            if (contexto == 'rescatista' || contexto == 'albergue')
              'creadoPor': contexto,
          },
        ),
      );
    } finally {
      _contactandoAliados.remove(widget.aliadoId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _perfilStream,
      builder: (context, userSnap) {
        final data = userSnap.data?.data() as Map<String, dynamic>? ?? {};
        final nombre = data['aliadoNombre'] as String? ?? 'Aliado';
        final tipo = data['aliadoTipo'] as String? ?? '';
        // `aliadoCiudad` con respaldo en `ciudad` — ver el comentario en
        // aliado_perfil_screen.dart: la ciudad del negocio se separó de la
        // del albergue (una cuenta puede tener los dos roles), y los
        // perfiles viejos todavía la tienen en el campo compartido.
        final ciudad =
            data['aliadoCiudad'] as String? ?? data['ciudad'] as String? ?? '';
        final telefono = data['aliadoTelefono'] as String? ?? '';
        final direccion = data['aliadoDireccion'] as String? ?? '';
        final email = data['aliadoEmail'] as String? ?? '';
        final sitioWeb = data['aliadoSitioWeb'] as String? ?? '';
        final foto = data['aliadoFotoBase64'] as String?;
        final iniciales = nombre
            .trim()
            .split(' ')
            .take(2)
            .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
            .join();

        return Scaffold(
          backgroundColor: appBg,
          body: StreamBuilder<
            List<QueryDocumentSnapshot<Map<String, dynamic>>>
          >(
            stream: _serviciosStream,
            builder: (context, svcSnap) {
              // Sin esto, un error real se veía igual que "Sin servicios
              // publicados" — mismo patrón ya arreglado en
              // favoritos_screen.dart y otras pantallas (errorFeedState,
              // widgets/estado_error_feed.dart), acá en el perfil público del aliado
              // (hallazgo de auditoría de código).
              if (svcSnap.hasError) return errorFeedState();
              final servicios = svcSnap.data ?? const [];

              return CustomScrollView(
                slivers: [
                  // Header
                  SliverToBoxAdapter(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(20, 56, 20, 28),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF0A5C40), appTeal],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Column(
                        children: [
                          AvatarPersona(
                            fotoBase64: foto,
                            inicial: iniciales,
                            radius: 44,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.2,
                            ),
                            textColor: Colors.white,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            nombre,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          if (tipo.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            // Mismo ícono por tipo que la grilla de "Negocios
                            // aliados" (theme.dart) — acá en blanco porque el
                            // fondo ya es un degradado oscuro, no una tarjeta
                            // clara con pastel.
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  aliadoTipoIcono(tipo),
                                  size: 14,
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  tipo,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white.withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () =>
                                  _contactar(context, nombre, foto),
                              icon: const Icon(
                                Icons.chat_bubble_outline,
                                size: 18,
                              ),
                              label: const Text(
                                'Contactar',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: appTeal,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Back button overlay
                  SliverToBoxAdapter(child: const SizedBox.shrink()),

                  // Contacto (opcional)
                  if (ciudad.isNotEmpty ||
                      telefono.isNotEmpty ||
                      direccion.isNotEmpty ||
                      email.isNotEmpty ||
                      sitioWeb.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // La ciudad se geocodifica al guardar el perfil
                            // (mismo campo con detección por GPS que usa
                            // Albergue), pero esta pantalla nunca la
                            // mostraba — se veía dirección/email/web, pero
                            // nunca en qué ciudad está el negocio. Hallazgo
                            // real de Eliza.
                            if (ciudad.isNotEmpty)
                              filaContacto(
                                Icons.location_city_outlined,
                                ciudad,
                              ),
                            if (direccion.isNotEmpty)
                              filaContacto(
                                Icons.location_on_outlined,
                                direccion,
                              ),
                            if (email.isNotEmpty)
                              filaContacto(
                                Icons.email_outlined,
                                email,
                                onTap: () =>
                                    launchUrl(Uri.parse('mailto:$email')),
                              ),
                            if (sitioWeb.isNotEmpty)
                              filaContacto(
                                Icons.language_outlined,
                                sitioWeb,
                                onTap: () => launchUrl(
                                  Uri.parse(sitioWebUrl(sitioWeb)),
                                  mode: LaunchMode.externalApplication,
                                ),
                              ),
                            if (telefono.isNotEmpty)
                              Padding(
                                padding: EdgeInsets.only(
                                  top:
                                      (ciudad.isNotEmpty ||
                                          direccion.isNotEmpty ||
                                          email.isNotEmpty ||
                                          sitioWeb.isNotEmpty)
                                      ? 4
                                      : 0,
                                ),
                                child: GestureDetector(
                                  onTap: () {
                                    final url = whatsappUrl(telefono);
                                    if (url != null) {
                                      launchUrl(
                                        Uri.parse(url),
                                        mode: LaunchMode.externalApplication,
                                      );
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF25D366,
                                      ).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: const Color(
                                          0xFF25D366,
                                        ).withValues(alpha: 0.35),
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.chat_bubble_outline,
                                          size: 15,
                                          color: Color(0xFF1E9E56),
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          'Escribir por WhatsApp',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF1E9E56),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                  // Servicios
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                      child: Text(
                        servicios.isEmpty
                            ? 'Sin servicios publicados'
                            : 'SERVICIOS DISPONIBLES',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ),

                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((_, i) {
                        final d = servicios[i].data();
                        final sNombre = d['nombre'] as String? ?? '';
                        final precio = d['precio'] as int? ?? 0;
                        final desc = d['descripcion'] as String? ?? '';
                        final cat = d['categoria'] as String? ?? '';
                        final emoji = _categoriaEmoji[cat] ?? '🐾';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
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
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: appTeal.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    emoji,
                                    style: const TextStyle(fontSize: 22),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                      const SizedBox(height: 2),
                                      Text(
                                        desc,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '\$${_fmt(precio)}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: appTeal,
                                ),
                              ),
                            ],
                          ),
                        );
                      }, childCount: servicios.length),
                    ),
                  ),
                ],
              );
            },
          ),
          // Back button
          floatingActionButtonLocation:
              FloatingActionButtonLocation.miniStartTop,
          floatingActionButton: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: FloatingActionButton.small(
                heroTag: 'back',
                onPressed: () => Navigator.pop(context),
                backgroundColor: Colors.white,
                foregroundColor: appTeal,
                elevation: 2,
                tooltip: 'Volver',
                child: const Icon(Icons.arrow_back_ios_new, size: 16),
              ),
            ),
          ),
        );
      },
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

  /// Una línea de contacto (dirección/email/sitio web): ícono + texto,
  /// tappable si se pasa [onTap] (email abre el cliente de correo, sitio
  /// web abre el navegador — dirección no tiene onTap, es solo texto).
  /// Mismo widget que albergue_publico_screen.dart.
}
