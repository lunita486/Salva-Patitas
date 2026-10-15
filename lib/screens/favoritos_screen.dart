import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../routing/app_router.dart';
import '../theme/salva_patitas_theme.dart';
import '../widgets/sp_widgets.dart';
import '../domain/reglas_negocio.dart';
import '../widgets/estado_error_feed.dart';
import '../widgets/fotos.dart';
import '../data/favoritos_repository.dart';
import '../data/rescates_repository.dart';

class FavoritosScreen extends StatefulWidget {
  const FavoritosScreen({super.key});

  @override
  State<FavoritosScreen> createState() => _FavoritosScreenState();
}

class _FavoritosScreenState extends State<FavoritosScreen> {
  // `late final`, no armado dentro de build(): un `.snapshots()` creado en
  // build() es un objeto nuevo en cada redibujado, y el StreamBuilder se
  // desuscribe del anterior y arranca de cero (vuelve al spinner y recarga).
  // Mismo patrón que ya estaba documentado en home_screen y compañía, del
  // que esta pantalla se había quedado afuera. Hallazgo de auditoría.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _favoritosStream =
      FavoritosRepository().mios(FirebaseAuth.instance.currentUser?.uid ?? '');

  // El stream de los animales guardados NO puede ser un `late final` como
  // el de arriba: depende de la lista de ids, que cambia de verdad cuando
  // se agrega o se quita un favorito. Pero tampoco puede armarse en cada
  // build (el problema de siempre: resuscribirse muestra un instante de
  // caché vieja y hace parpadear la grilla) — y el stream de favoritos de
  // arriba emite también por cambios que NO tocan la lista de ids.
  //
  // Punto medio: se guarda el último stream junto con los ids con los que
  // se armó, y solo se rehace cuando esos ids cambian de verdad. Es la
  // versión honesta del `late final` para un stream que sí depende de
  // datos que cambian.
  List<String>? _idsDelStream;
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? _rescatesStream;

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _streamDeRescates(
    List<String> ids,
  ) {
    final mismos =
        _idsDelStream != null &&
        _idsDelStream!.length == ids.length &&
        _idsDelStream!.every(ids.contains);
    if (!mismos || _rescatesStream == null) {
      _idsDelStream = List.of(ids);
      _rescatesStream = RescatesRepository().porIdsSinTope(ids);
    }
    return _rescatesStream!;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: SpPawBackground()),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // El botón de volver vive acá afuera, siempre visible, para que
                // si falla la carga de abajo el usuario no quede atrapado sin
                // forma de salir de la pantalla.
                const SpScreenHeader(
                  title: 'Tus favoritos',
                  subtitle: 'Los animalitos que guardaste',
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _favoritosStream,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return Center(
                          child: CircularProgressIndicator(color: c.primary),
                        );
                      }
                      if (snap.hasError) return errorFeedState();
                      final docs = snap.data?.docs ?? [];
                      // Un solo listener con el estado de todos los animales guardados,
                      // en vez de uno por tarjeta (antes N conexiones, ahora 1).
                      final rescateIds = docs
                          .map(
                            (d) =>
                                (d.data() as Map<String, dynamic>)['rescateId']
                                    as String? ??
                                '',
                          )
                          .where((id) => id.isNotEmpty)
                          .toSet()
                          .toList();

                      return StreamBuilder<
                        List<QueryDocumentSnapshot<Map<String, dynamic>>>
                      >(
                        // SinTope, no porIds(): con más de 30 favoritos (pasa de
                        // verdad, ver el doc de porIdsSinTope), recortar acá
                        // dejaba a los que quedaban afuera pegados para siempre
                        // en la copia vieja del favorito. Hallazgo real de Eliza,
                        // con 62 favoritos guardados.
                        stream: _streamDeRescates(rescateIds),
                        builder: (context, rescatesSnap) {
                          // hasData es distinto de "llegó un evento" — es
                          // específicamente "recibimos una respuesta real del
                          // servidor" (con datos, no null). El PRIMER build de
                          // cualquier StreamBuilder recién suscripto es siempre
                          // así (ningún stream entrega de forma sincrónica), y si
                          // esta consulta puntual nunca llega a responder (token
                          // vencido tras la app en segundo plano toda la noche,
                          // sin conexión), se queda así para siempre. Antes eso
                          // hacía que TODOS los favoritos con rescateId parecieran
                          // huérfanos (huboRespuesta acá abajo controla eso) —
                          // "no llegó respuesta todavía" y "llegó, y esto no está"
                          // se trataban como lo mismo, y la pantalla se veía vacía
                          // aunque hubiera favoritos reales, sin ningún aviso.
                          final huboRespuesta = rescatesSnap.hasData;
                          final rescatesDocs = rescatesSnap.data ?? const [];
                          final estadoPorRescateId = <String, String>{
                            if (huboRespuesta)
                              for (final r in rescatesDocs)
                                r.id:
                                    (r.data())['estadoAdopcion'] as String? ??
                                    '',
                          };
                          // `favoritos.fotoUrl` es una foto de una sola vez tomada
                          // al guardar el favorito — si el rescate se guardó en
                          // ese instante justo entre "se creó el doc" y "se le
                          // linkeó la foto" (dos animales subiéndose a la vez es
                          // el caso real que lo disparó), el favorito queda para
                          // siempre con fotoUrl null aunque el rescate después sí
                          // tenga foto. Este mapa de respaldo, con la foto ACTUAL
                          // del rescate, evita que ese favorito se vea roto.
                          final fotoPorRescateId = <String, String?>{
                            for (final r in rescatesDocs)
                              r.id: r.data()['fotoUrl'] as String?,
                          };
                          // `favoritos` nunca guardó las etiquetas del animal
                          // (tamaño, energía, etc.) — el botón "Adoptar" de acá
                          // armaba la solicitud sin ellas, y compatibilidad.dart
                          // las completaba con sus valores por defecto (ej.
                          // "Mediano" aunque el animal fuera "Pequeño"). Se leen
                          // del rescate en vivo, igual que fotoPorRescateId.
                          final rescatePorId = <String, Map<String, dynamic>>{
                            for (final r in rescatesDocs) r.id: r.data(),
                          };
                          return _FavoritosGrid(
                            docs: docs,
                            // Vacío mientras no haya respuesta real — el filtro de
                            // huérfanos de _FavoritosGrid ya sabe tratar "no
                            // consultado" como "no ocultar" (antes era el mismo
                            // camino que usaban los favoritos que superaban el
                            // tope de 30 de whereIn; ese tope ya no existe, ver
                            // porIdsSinTope, pero el camino sigue sirviendo para
                            // "todavía esperando la primera respuesta" y "la
                            // consulta falló y nunca hubo ninguna") — no hace
                            // falta un camino nuevo.
                            rescateIdsConsultados: huboRespuesta
                                ? rescateIds.toSet()
                                : const {},
                            estadoPorRescateId: estadoPorRescateId,
                            fotoPorRescateId: fotoPorRescateId,
                            rescatePorId: rescatePorId,
                            // Para avisar (no silencio) si la consulta falló y
                            // nunca hubo ninguna respuesta previa que mostrar en
                            // su lugar — ver el aviso en _FavoritosGrid.
                            sinConfirmarPorError:
                                rescatesSnap.hasError && !huboRespuesta,
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
}

class _FavoritosGrid extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  final Set<String> rescateIdsConsultados;
  final Map<String, String> estadoPorRescateId;
  final Map<String, String?> fotoPorRescateId;
  final Map<String, Map<String, dynamic>> rescatePorId;
  final bool sinConfirmarPorError;
  const _FavoritosGrid({
    required this.docs,
    required this.rescateIdsConsultados,
    required this.estadoPorRescateId,
    required this.fotoPorRescateId,
    required this.rescatePorId,
    this.sinConfirmarPorError = false,
  });

  @override
  Widget build(BuildContext context) {
    // Un rescate borrado desaparece de rescatesSnap, pero el favorito que
    // lo apuntaba puede seguir existiendo (limpiarlo es best-effort desde
    // el lado del rescatista — ver RescatesRepository.eliminar). Si el id
    // SÍ se consultó y no vino en la respuesta, está borrado de verdad: se
    // oculta acá para no mostrar un "Adoptar" fantasma sobre un animal que
    // ya no existe. Si el id no llegó a consultarse (la respuesta del
    // servidor todavía no llegó, o falló del todo — porIdsSinTope() ya no
    // tiene el tope de 30 que tenía antes), no se puede saber con certeza
    // — se sigue mostrando con los datos guardados en el propio favorito,
    // como siempre.
    final docs = this.docs.where((d) {
      final rescateId =
          (d.data() as Map<String, dynamic>)['rescateId'] as String? ?? '';
      if (rescateId.isEmpty) return true;
      final fueConsultado = rescateIdsConsultados.contains(rescateId);
      final existeTodavia = estadoPorRescateId.containsKey(rescateId);
      return !fueConsultado || existeTodavia;
    }).toList();

    final c = context.sp;
    return CustomScrollView(
      slivers: [
        if (docs.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SpSectionTitle(
                '${docs.length} guardado${docs.length == 1 ? "" : "s"}',
              ),
            ),
          ),
        // Aviso, no silencio: no reemplaza la lista (los favoritos
        // guardados igual se muestran, con sus datos propios) — solo
        // avisa que el estado más reciente (en proceso/adoptado/
        // etc.) no se pudo confirmar, para que no parezca que la
        // pantalla "sabe" algo que en realidad no pudo verificar.
        if (sinConfirmarPorError && docs.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: SpNotice(
                fondo: c.accentSoft,
                tinta: c.accentInk,
                child: const Row(
                  children: [
                    Icon(Icons.wifi_off_rounded),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No pudimos confirmar el estado más reciente de tus favoritos. Revisá tu conexión.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (docs.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: SpEmpty(
                title: 'Aún no tienes favoritos',
                subtitle:
                    'Toca el corazón en las tarjetas para guardar animalitos que te gusten.',
                animal: SpAnimalKind.gato,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverGrid(
              // MaxCrossAxisExtent en vez de FixedCrossAxisCount(2):
              // mismo motivo que aliados_screen.dart — con conteo
              // fijo, en horizontal cada columna se estiraba mucho
              // más allá de su ancho de vertical, dejando la tarjeta
              // con su contenido centrado y mucho espacio en blanco
              // arriba y abajo.
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 190,
                crossAxisSpacing: 12,
                mainAxisSpacing: 14,
                childAspectRatio: 0.6,
              ),
              delegate: SliverChildBuilderDelegate((_, i) {
                final d = docs[i].data() as Map<String, dynamic>;
                final rescateId = d['rescateId'] as String? ?? '';
                final rescate =
                    rescatePorId[rescateId] ?? const <String, dynamic>{};
                // El resto de los campos de acá abajo (nombre, edad,
                // ubicación, género, rescatista) son la MISMA foto de una
                // sola vez que fotoUrl: se copiaron al favorito el
                // instante en que se guardó, y quedaban congelados ahí
                // para siempre — si el rescatista después le cambiaba el
                // nombre al animal (o la foto, ver más abajo), quien lo
                // tenía en favoritos nunca se enteraba. El rescate en vivo
                // (`rescate`, ya armado arriba en RescatesRepository().
                // porIdsSinTope) gana siempre que esté disponible; si no
                // (fue borrado, o la respuesta todavía no llegó), se sigue
                // usando lo guardado en el favorito, como antes. Hallazgo
                // real de Eliza: "los animales que están en favoritos no
                // se actualizan nunca cuando se cambian las fotos o el
                // nombre".
                final nombre = rescate.isNotEmpty
                    ? RescatesRepository.nombreDe(rescate)
                    : nombreDeAnimal(d['animalNombre'] as String?);
                final especie =
                    (rescate['especie'] as String?) ??
                    (d['especie'] as String? ?? '');
                final edad =
                    (rescate['edad'] as String?) ??
                    (d['edad'] as String? ?? '');
                final ubicacion =
                    (rescate['ubicacion'] as String?) ??
                    (d['ubicacion'] as String? ?? '');
                final rescatista =
                    (rescate['rescatistaNombre'] as String?) ??
                    (d['rescatista'] as String? ?? 'Rescatista');
                final rescatistaId = d['rescatistaId'] as String? ?? '';
                // La foto EN VIVO del rescate gana siempre que esté
                // disponible — la del favorito es una foto de una
                // sola vez tomada al guardarlo, y queda rota apenas
                // el rescatista edita las fotos después (el mismo
                // path de Storage se sobreescribe con un token
                // nuevo). Antes solo se recurría a la foto en vivo
                // cuando el campo del favorito estaba vacío — pero
                // "vacío" y "roto" no son lo mismo: un campo con una
                // URL vieja no está vacío, así que nunca se corregía
                // solo.
                final fotoUrl =
                    fotoPorRescateId[rescateId] ?? (d['fotoUrl'] as String?);

                final animalMap = {
                  'nombre': nombre,
                  'especie': especie,
                  'edad': edad,
                  'genero': rescate['genero'] ?? d['genero'] ?? '',
                  'ubicacion': ubicacion,
                  'rescatista': rescatista,
                  'rescatistaId': rescatistaId,
                  'rescateId': rescateId,
                  'fotoUrl': fotoUrl,
                  'tamano': rescate['tamano'],
                  'energia': rescate['energia'],
                  'okConNinos': rescate['okConNinos'],
                  'okConMascotas': rescate['okConMascotas'],
                  'requiereExperiencia': rescate['requiereExperiencia'],
                  'creadoPor': d['creadoPor'] ?? 'rescatista',
                };

                final estado = estadoPorRescateId[rescateId] ?? '';
                final devuelto = estado == 'Regresado';
                // sePuedeAdoptar (domain/reglas_negocio.dart) — única fuente.
                // Acá vivía una lista de estados escrita a mano que
                // CONTRADECÍA a la del feed justo en 'Hogar de paso'.
                final noDisponible = !sePuedeAdoptar(estado);
                final textoNoDisponible = switch (estado) {
                  'Fallecido' => 'Falleció',
                  'Hogar de paso' => 'En hogar de paso',
                  'En proceso de adopción' => 'En proceso de adopción',
                  _ => 'Ya adoptado',
                };
                final tonoNoDisponible = spToneEstado(
                  estado == '' ? 'Adoptado' : estado,
                );

                return Container(
                  padding: const EdgeInsets.all(SpSpace.s2),
                  decoration: SpDeco.card(c),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // FotoAnimal en vez de recorte — mismo motivo
                              // que el feed y el detalle: la foto entera sobre
                              // fondo desenfocado (caso "Tobyiii").
                              if (fotoUrl != null)
                                FotoAnimal(
                                  url: fotoUrl,
                                  width: double.infinity,
                                  fallback: SpFotoVacia(especie: especie),
                                )
                              else
                                SpFotoVacia(especie: especie),
                              // Quitar favorito — sin confirmación: no es
                              // destructivo (el animal vuelve a aparecer en el
                              // carrusel principal) y se revierte con un toque.
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Tooltip(
                                  message: 'Quitar de favoritos',
                                  child: GestureDetector(
                                    onTap: () => docs[i].reference.delete(),
                                    child: Container(
                                      width: 34,
                                      height: 34,
                                      decoration: SpDeco.soft(
                                        c,
                                        radius: SpRadius.full,
                                      ),
                                      child: Icon(
                                        Icons.favorite_rounded,
                                        color: c.accent,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (devuelto)
                                const Positioned(
                                  top: 8,
                                  left: 8,
                                  child: SpBadge('Fue devuelto'),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                        child: Text(
                          nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: c.ink,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          '${edad.isNotEmpty ? "$edad · " : ""}$ubicacion',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SpText.caption.copyWith(color: c.inkMuted),
                        ),
                      ),
                      // El nombre del rescatista/albergue (en vivo) se
                      // muestra para que "renombrar el albergue actualiza
                      // Favoritos" se pueda ver. Hallazgo real de Eliza.
                      if (rescatista.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            rescatista,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SpText.caption.copyWith(
                              color: c.primaryStrong,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      if (noDisponible)
                        Container(
                          width: double.infinity,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: tonoNoDisponible == null
                                ? c.surfaceSunken
                                : SpToneColors.of(c, tonoNoDisponible).fill,
                            borderRadius: BorderRadius.circular(SpRadius.full),
                          ),
                          child: Text(
                            textoNoDisponible,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: tonoNoDisponible == null
                                  ? c.inkMuted
                                  : SpToneColors.of(c, tonoNoDisponible).ink,
                            ),
                          ),
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          child: SpButton(
                            label: 'Quiero adoptar',
                            icon: Icons.favorite_border_rounded,
                            compacto: true,
                            onTap: () => context.push(
                              AppRoutes.solicitudAdopcion,
                              extra: animalMap,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }, childCount: docs.length),
            ),
          ),
      ],
    );
  }
}
