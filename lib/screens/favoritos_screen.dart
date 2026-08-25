import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../routing/app_router.dart';
import '../theme.dart';
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
      FavoritosRepository().mios(
        FirebaseAuth.instance.currentUser?.uid ?? '',
      );

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
    return Scaffold(
      backgroundColor: appBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // El botón de volver vive acá afuera, siempre visible, para que
            // si falla la carga de abajo el usuario no quede atrapado sin
            // forma de salir de la pantalla.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                        tooltip: 'Volver',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Text(
                      'Tus favoritos',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: appInk,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _favoritosStream,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: appTeal),
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
                            r.id: (r.data())['estadoAdopcion'] as String? ??
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

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              docs.isEmpty
                  ? 'SIN GUARDADOS'
                  : '${docs.length} GUARDADO${docs.length == 1 ? "" : "S"}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: Colors.grey.shade700,
              ),
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
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: msgAdvertencia.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.wifi_off_rounded,
                      size: 18,
                      color: msgAdvertencia,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No pudimos confirmar el estado más reciente de tus favoritos. Revisá tu conexión.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (docs.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.favorite_border,
                    size: 64,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Aún no tienes favoritos',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: appInk,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Toca ❤️ en las tarjetas para guardar\nanimalitos que te gusten.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                      height: 1.5,
                    ),
                  ),
                ],
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
                maxCrossAxisExtent: 180,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.72,
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
                    (rescate['edad'] as String?) ?? (d['edad'] as String? ?? '');
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
                final emoji = especie == 'Gato' ? '🐱' : '🐶';

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

                return Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.07),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            // FotoAnimal en vez de recorte — mismo
                            // motivo que el feed y el detalle: la
                            // foto entera sobre fondo desenfocado
                            // (caso "Tobyiii", mueble vacío).
                            child: fotoUrl != null
                                ? FotoAnimal(
                                    url: fotoUrl,
                                    width: double.infinity,
                                    fallback: Container(
                                      width: double.infinity,
                                      color: const Color(0xFFD8F0E4),
                                      child: Center(
                                        child: Text(
                                          emoji,
                                          style: const TextStyle(fontSize: 52),
                                        ),
                                      ),
                                    ),
                                  )
                                : Container(
                                    width: double.infinity,
                                    color: const Color(0xFFD8F0E4),
                                    child: Center(
                                      child: Text(
                                        emoji,
                                        style: const TextStyle(fontSize: 52),
                                      ),
                                    ),
                                  ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nombre,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: appInk,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${edad.isNotEmpty ? "$edad · " : ""}$ubicacion',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                // El nombre del rescatista/albergue se lee
                                // más arriba (`rescatista`, ya en vivo —
                                // ver el comentario sobre la foto) pero
                                // nunca se llegaba a MOSTRAR en esta
                                // tarjeta — se calculaba solo para el mapa
                                // que se pasa al abrir el chat. Sin esto,
                                // no había forma de que "renombrar el
                                // albergue actualiza Favoritos" se pudiera
                                // ver, porque el nombre no se veía ni
                                // antes ni después de renombrar. Hallazgo
                                // real de Eliza probando justo eso.
                                if (rescatista.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    rescatista,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Builder(
                                  builder: (_) {
                                    final estado =
                                        estadoPorRescateId[rescateId] ?? '';
                                    final enProceso =
                                        estado == 'En proceso de adopción';
                                    final devuelto = estado == 'Regresado';
                                    final enHogarDePaso =
                                        estado == 'Hogar de paso';
                                    final fallecido = estado == 'Fallecido';
                                    // sePuedeAdoptar (domain/reglas_negocio.dart)
                                    // — única fuente. Acá vivía una lista de
                                    // estados escrita a mano que CONTRADECÍA a
                                    // la del feed justo en 'Hogar de paso': el
                                    // mismo animal salía como adoptable en el
                                    // feed y como "ya no está disponible" acá.
                                    final noDisponible = !sePuedeAdoptar(estado);
                                    return Column(
                                      children: [
                                        if (devuelto) ...[
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFFF3E0),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: const Color(
                                                  0xFFE65100,
                                                ).withValues(alpha: 0.4),
                                              ),
                                            ),
                                            child: const Text(
                                              '🔁 Fue devuelto',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFFE65100),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                        ],
                                        if (noDisponible)
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: cicloColor(
                                                estado,
                                              ).withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: Border.all(
                                                color: cicloColor(
                                                  estado,
                                                ).withValues(alpha: 0.4),
                                              ),
                                            ),
                                            child: Text(
                                              fallecido
                                                  ? 'Falleció 🌈'
                                                  : enHogarDePaso
                                                  ? 'En hogar de paso 🏡'
                                                  : enProceso
                                                  ? 'En proceso de adopción 🔄'
                                                  : 'Ya adoptado 🏠',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: cicloColor(estado),
                                              ),
                                            ),
                                          )
                                        else
                                          SizedBox(
                                            width: double.infinity,
                                            child: ElevatedButton(
                                              onPressed: () => context.push(
                                                AppRoutes.solicitudAdopcion,
                                                extra: animalMap,
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: appTeal,
                                                foregroundColor: Colors.white,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 6,
                                                    ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                ),
                                                elevation: 0,
                                                textStyle: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              child: const Text('Adoptar'),
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Botón quitar favorito — sin confirmación: quitar un
                    // favorito no es destructivo (el animal vuelve a
                    // aparecer solo en el carrusel principal) y es
                    // reversible con un toque, no amerita el paso extra.
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => docs[i].reference.delete(),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.favorite,
                            color: appOrange,
                            size: 17,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }, childCount: docs.length),
            ),
          ),
      ],
    );
  }
}
