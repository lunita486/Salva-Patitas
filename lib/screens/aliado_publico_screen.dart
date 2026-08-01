import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import '../theme.dart';
import '../data/chats_repository.dart';
import 'chat_screen.dart';

// A nivel de archivo, no de la instancia (esta pantalla es un
// StatelessWidget, sin estado propio donde guardar un candado) — evita que
// un doble toque en "Contactar" dispare dos llamadas en paralelo y empuje
// DOS ChatScreen a la pila de navegación (la persona tendría que tocar
// "atrás" dos veces para salir). Con clave por aliadoId, no global: cada
// negocio tiene su propio candado. Mismo patrón que _solicitudesEnProceso
// en solicitudes_rescatista_screen.dart. Hallazgo de auditoría de código.
final Set<String> _contactandoAliados = {};

class AliadoPublicoScreen extends StatelessWidget {
  final String aliadoId;
  final bool esRescatista;
  final bool esAlbergue;
  const AliadoPublicoScreen({super.key, required this.aliadoId, this.esRescatista = false, this.esAlbergue = false});

  static const _categoriaEmoji = {
    'Baño y peluquería': '🛁',
    'Veterinaria':       '🩺',
    'Tienda':            '🛍️',
    'Adiestramiento':    '🎓',
    'Transporte':        '🚗',
    'Otro':              '🐾',
  };

  Future<void> _contactar(BuildContext context, String nombre, String? fotoBase64) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    if (!_contactandoAliados.add(aliadoId)) return;
    try {
      final contexto = !esRescatista ? 'general' : (esAlbergue ? 'albergue' : 'rescatista');
      // Al contactar "como albergue" hay que mostrar el nombre DEL ALBERGUE
      // (ej. "La Perla"), no el nombre personal de Google de quien lo
      // administra — el avatar de esa fila ya muestra el logo del albergue
      // (AvatarUsuario con esNegocio), así que el nombre tiene que ser
      // consistente con eso. Para rescatista/adoptante sí corresponde el
      // nombre personal — no existe un "nombre de negocio" para un
      // rescatista individual.
      var nombreContacto = FirebaseAuth.instance.currentUser?.displayName ?? 'Usuario';
      if (contexto == 'albergue') {
        try {
          final userDoc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
          final albergueNombre = userDoc.data()?['albergueNombre'] as String?;
          if (albergueNombre != null && albergueNombre.isNotEmpty) nombreContacto = albergueNombre;
        } catch (_) {}
      }

      String chatId;
      try {
        chatId = await ChatsRepository().asegurarChatNegocio(
          adoptanteId: uid,
          adoptanteNombre: nombreContacto,
          aliadoId: aliadoId,
          aliadoNombre: nombre,
          contexto: contexto,
          fotoBase64: fotoBase64,
        );
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              backgroundColor: msgError,
              content: Text('No se pudo abrir el chat. Intentá de nuevo.')));
        }
        return;
      }

      FirebaseAnalytics.instance.logEvent(
        name: 'aliado_contactado',
        parameters: {'aliado_id': aliadoId},
      ).catchError((_) {});

      if (!context.mounted) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChatScreen(
          esRescatista: false,
          chatId: chatId,
          animal: {
            'nombre':       nombre,
            'rescatista':   nombre,
            'rescatistaId': aliadoId,
            'fotoBase64':   fotoBase64,
            'tipoSolicitud': 'consulta_aliado',
          },
        ),
      ));
    } finally {
      _contactandoAliados.remove(aliadoId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('usuarios').doc(aliadoId).snapshots(),
      builder: (context, userSnap) {
        final data     = userSnap.data?.data() as Map<String, dynamic>? ?? {};
        final nombre   = data['aliadoNombre'] as String? ?? 'Aliado';
        final tipo     = data['aliadoTipo']   as String? ?? '';
        final telefono = data['aliadoTelefono']  as String? ?? '';
        final direccion= data['aliadoDireccion'] as String? ?? '';
        final email    = data['aliadoEmail']     as String? ?? '';
        final sitioWeb = data['aliadoSitioWeb']  as String? ?? '';
        final foto     = data['aliadoFotoBase64'] as String?;
        final iniciales = nombre.trim().split(' ')
            .take(2).map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();

        return Scaffold(
          backgroundColor: appBg,
          body: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('servicios')
                .where('aliadoId', isEqualTo: aliadoId)
                .snapshots(),
            builder: (context, svcSnap) {
              // Sin esto, un error real se veía igual que "Sin servicios
              // publicados" — mismo patrón ya arreglado en
              // favoritos_screen.dart y otras pantallas (errorFeedState,
              // theme.dart), acá en el perfil público del aliado
              // (hallazgo de auditoría de código).
              if (svcSnap.hasError) return errorFeedState();
              final servicios = (svcSnap.data?.docs ?? [])
                  .where((d) => (d.data() as Map)['activo'] == true)
                  .toList();

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
                      child: Column(children: [
                        Builder(builder: (_) {
                          final fotoBytes = bytesFotoSegura(foto);
                          return CircleAvatar(
                            radius: 44,
                            backgroundColor: Colors.white.withValues(alpha: 0.2),
                            backgroundImage: fotoBytes != null ? MemoryImage(fotoBytes) : null,
                            onBackgroundImageError: fotoBytes != null ? (_, __) {} : null,
                            child: fotoBytes == null
                                ? Text(iniciales, style: const TextStyle(
                                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24))
                                : null,
                          );
                        }),
                        const SizedBox(height: 12),
                        Text(nombre, style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                        if (tipo.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          // Mismo ícono por tipo que la grilla de "Negocios
                          // aliados" (theme.dart) — acá en blanco porque el
                          // fondo ya es un degradado oscuro, no una tarjeta
                          // clara con pastel.
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(aliadoTipoIcono(tipo), size: 14, color: Colors.white.withValues(alpha: 0.8)),
                            const SizedBox(width: 5),
                            Text(tipo, style: TextStyle(
                                fontSize: 13, color: Colors.white.withValues(alpha: 0.8))),
                          ]),
                        ],
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _contactar(context, nombre, foto),
                            icon: const Icon(Icons.chat_bubble_outline, size: 18),
                            label: const Text('Contactar',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: appTeal,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),

                  // Back button overlay
                  SliverToBoxAdapter(child: const SizedBox.shrink()),

                  // Contacto (opcional)
                  if (telefono.isNotEmpty || direccion.isNotEmpty || email.isNotEmpty || sitioWeb.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (direccion.isNotEmpty)
                            _filaContacto(Icons.location_on_outlined, direccion),
                          if (email.isNotEmpty)
                            _filaContacto(Icons.email_outlined, email,
                                onTap: () => launchUrl(Uri.parse('mailto:$email'))),
                          if (sitioWeb.isNotEmpty)
                            _filaContacto(Icons.language_outlined, sitioWeb,
                                onTap: () => launchUrl(Uri.parse(sitioWebUrl(sitioWeb)),
                                    mode: LaunchMode.externalApplication)),
                          if (telefono.isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(top: (direccion.isNotEmpty || email.isNotEmpty || sitioWeb.isNotEmpty) ? 4 : 0),
                              child: GestureDetector(
                                onTap: () {
                                  final url = whatsappUrl(telefono);
                                  if (url != null) {
                                    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF25D366).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.35)),
                                  ),
                                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.chat_bubble_outline, size: 15, color: Color(0xFF1E9E56)),
                                    SizedBox(width: 6),
                                    Text('Escribir por WhatsApp', style: TextStyle(
                                        fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF1E9E56))),
                                  ]),
                                ),
                              ),
                            ),
                        ]),
                      ),
                    ),

                  // Servicios
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                      child: Text(
                        servicios.isEmpty ? 'Sin servicios publicados' : 'SERVICIOS DISPONIBLES',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                            letterSpacing: 1.2, color: Colors.grey.shade700),
                      ),
                    ),
                  ),

                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) {
                          final d      = servicios[i].data() as Map<String, dynamic>;
                          final sNombre = d['nombre']      as String? ?? '';
                          final precio  = d['precio']      as int?    ?? 0;
                          final desc    = d['descripcion'] as String? ?? '';
                          final cat     = d['categoria']   as String? ?? '';
                          final emoji   = _categoriaEmoji[cat] ?? '🐾';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 8, offset: const Offset(0, 2))],
                            ),
                            child: Row(children: [
                              Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  color: appTeal.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(child: Text(emoji,
                                    style: const TextStyle(fontSize: 22))),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(sNombre, style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700,
                                    color: appInk)),
                                if (desc.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(desc, style: TextStyle(fontSize: 12,
                                      color: Colors.grey.shade700),
                                      maxLines: 2, overflow: TextOverflow.ellipsis),
                                ],
                              ])),
                              const SizedBox(width: 8),
                              Text('\$${_fmt(precio)}',
                                  style: const TextStyle(fontSize: 16,
                                      fontWeight: FontWeight.bold, color: appTeal)),
                            ]),
                          );
                        },
                        childCount: servicios.length,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          // Back button
          floatingActionButtonLocation: FloatingActionButtonLocation.miniStartTop,
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
  Widget _filaContacto(IconData icono, String texto, {VoidCallback? onTap}) {
    final fila = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icono, size: 17, color: appTeal),
        const SizedBox(width: 8),
        Expanded(child: Text(texto,
            style: TextStyle(fontSize: 13.5,
                color: onTap != null ? appTeal : appInk))),
      ]),
    );
    return onTap == null ? fila : GestureDetector(onTap: onTap, child: fila);
  }
}
