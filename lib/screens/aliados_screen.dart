import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:go_router/go_router.dart';
import '../theme.dart';
import '../widgets/avatares.dart';
import '../widgets/estado_error_feed.dart';
import '../data/usuarios_repository.dart';
import '../routing/app_router.dart';

// Extraído de adoptante_feed_screen.dart (que llegó a 1642 líneas mezclando
// varias responsabilidades) — esta pantalla no es parte del feed en sí,
// vivía ahí solo por conveniencia histórica. La usan home_screen.dart y
// albergue_home_screen.dart.
class AliadosScreen extends StatefulWidget {
  final bool esRescatista;
  final bool esAlbergue;
  const AliadosScreen({
    super.key,
    this.esRescatista = false,
    this.esAlbergue = false,
  });

  @override
  State<AliadosScreen> createState() => _AliadosScreenState();
}

class _AliadosScreenState extends State<AliadosScreen> {
  // UsuariosRepository.aliados() es la única fuente de esta consulta para
  // toda la app — esta pantalla (extraída de adoptante_feed_screen.dart,
  // ver el comentario de arriba) tenía su PROPIA copia con .snapshots() en
  // vivo, arreglada por separado la primera vez que apareció el síntoma en
  // el feed. Con un solo método, no hay una segunda copia que se pueda
  // quedar atrás.
  late final Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _aliadosFuture =
      UsuariosRepository().aliados();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appBg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 20, 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                    tooltip: 'Volver',
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Text(
                      'Negocios aliados',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: appInk,
                        fontFamily: 'Baloo2',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                future: _aliadosFuture,
                builder: (context, snap) {
                  // Sin esto, un error real del stream (sin conexión, permiso
                  // denegado) se veía IGUAL que "todavía no hay aliados" —
                  // mismo patrón ya arreglado en favoritos_screen.dart y
                  // otras 5 pantallas más (errorFeedState, widgets/estado_error_feed.dart), que
                  // esta pantalla se quedó sin cuando se extrajo de
                  // adoptante_feed_screen.dart (hallazgo de auditoría de
                  // código).
                  if (snap.hasError) return errorFeedState();
                  // Antes esto tampoco se revisaba: en frío (sin caché local
                  // — instalación nueva, o esta pantalla nunca abierta antes)
                  // por un instante snap.data viene vacío, y sin este chequeo
                  // se mostraba "Aún no hay negocios aliados" siendo mentira,
                  // justo mientras la lista real todavía estaba cargando.
                  // Hallazgo de auditoría de código.
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: appTeal),
                    );
                  }
                  // aliados() ya devuelve la lista filtrada, no un QuerySnapshot.
                  final aliados = snap.data ?? [];
                  if (aliados.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('🐾', style: TextStyle(fontSize: 48)),
                          const SizedBox(height: 16),
                          Text(
                            'Aún no hay negocios aliados',
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    // MaxCrossAxisExtent en vez de FixedCrossAxisCount(2): con
                    // un conteo fijo, en horizontal (pantalla mucho más ancha)
                    // cada columna se estiraba mucho más allá de su ancho de
                    // vertical, y childAspectRatio mantenía esa tarjeta
                    // angosta-pensada-para-vertical ahora mucho más ancha —
                    // resultado: una tarjeta enorme con su contenido (foto,
                    // nombre, botón) centrado y un montón de espacio en blanco
                    // arriba y abajo. Con un ancho máximo por columna, en
                    // horizontal aparecen más columnas en vez de 2 gigantes, y
                    // cada tarjeta mantiene el tamaño pensado originalmente.
                    // Hallazgo de prueba en teléfono real, 2026-08-02.
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 180,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      // 0.7, no 0.78: con un nombre de aliado largo que ocupa
                      // las 2 líneas permitidas (ej. "Veterinario Huellitas
                      // prueba"), 0.78 se quedaba corto por unos pocos
                      // píxeles en horizontal (RenderFlex overflow de 8.4px,
                      // hallazgo de la revisión final 2026-08-03) — la
                      // diferencia de ancho de columna entre orientaciones era
                      // suficiente para pasarse del límite. Un poco más de
                      // alto le da margen sin cambiar cómo se ve en vertical.
                      childAspectRatio: 0.7,
                    ),
                    itemCount: aliados.length,
                    itemBuilder: (_, i) {
                      final d = aliados[i].data();
                      final nombre = d['aliadoNombre'] as String? ?? 'Aliado';
                      final tipo = d['aliadoTipo'] as String? ?? '';
                      final foto = d['aliadoFotoBase64'] as String?;
                      final ini = nombre.isNotEmpty
                          ? nombre[0].toUpperCase()
                          : 'A';
                      final uid = aliados[i].id;
                      return GestureDetector(
                        onTap: () {
                          FirebaseAnalytics.instance
                              .logEvent(
                                name: 'vio_perfil_aliado',
                                parameters: {'aliado_id': uid},
                              )
                              .catchError((_) {});
                          context.push(
                            AppRoutes.aliadoPublico,
                            extra: (
                              aliadoId: uid,
                              esRescatista: widget.esRescatista,
                              esAlbergue: widget.esAlbergue,
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // AvatarPersona en vez de un CircleAvatar propio:
                              // mismo widget que ya usa el chat, con fundido de
                              // entrada — antes cada logo aparecía de golpe en
                              // el instante en que terminaba de decodificarse, y
                              // con dos negocios en la grilla eso se veía como
                              // si cargaran "de a uno" (hallazgo real de Eliza
                              // en teléfono real, 2026-08-03), aunque los datos
                              // de los dos ya habían llegado juntos.
                              AvatarPersona(
                                fotoBase64: foto,
                                inicial: ini,
                                radius: 34,
                                backgroundColor: appTeal.withValues(
                                  alpha: 0.12,
                                ),
                                textColor: appTeal,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                nombre,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: appInk,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (tipo.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                // Ícono + pastel por tipo en vez de texto gris
                                // plano — mismo mapeo que el encabezado del
                                // perfil público del aliado (theme.dart), para
                                // que un mismo tipo se vea igual en toda la app.
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: aliadoTipoColorPastel(tipo),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        aliadoTipoIcono(tipo),
                                        size: 11,
                                        color: aliadoTipoColorTexto(tipo),
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          tipo,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                            color: aliadoTipoColorTexto(tipo),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: appTeal.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'Ver servicios',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: appTeal,
                                  ),
                                ),
                              ),
                            ],
                          ),
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
    );
  }
}
