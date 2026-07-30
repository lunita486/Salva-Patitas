import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import '../data/rescates_repository.dart';
import 'solicitud_adopcion_screen.dart';

class FavoritosScreen extends StatelessWidget {
  const FavoritosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appBg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // El botón de volver vive acá afuera, siempre visible, para que
          // si falla la carga de abajo el usuario no quede atrapado sin
          // forma de salir de la pantalla.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                tooltip: 'Volver',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text('Tus favoritos',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: appInk)),
              ),
            ]),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('favoritos')
                  .where('adoptanteId', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: appTeal));
                }
                if (snap.hasError) return errorFeedState();
                final docs = snap.data?.docs ?? [];
                // Un solo listener con el estado de todos los animales guardados,
                // en vez de uno por tarjeta (antes N conexiones, ahora 1).
                final rescateIds = docs
                    .map((d) => (d.data() as Map<String, dynamic>)['rescateId'] as String? ?? '')
                    .where((id) => id.isNotEmpty)
                    .toSet()
                    .take(30) // límite de Firestore para whereIn
                    .toList();

                return StreamBuilder<QuerySnapshot>(
                  stream: RescatesRepository().porIds(rescateIds),
                  builder: (context, rescatesSnap) {
                    final estadoPorRescateId = <String, String>{
                      for (final r in rescatesSnap.data?.docs ?? [])
                        r.id: (r.data() as Map<String, dynamic>)['estadoAdopcion'] as String? ?? '',
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
                      for (final r in rescatesSnap.data?.docs ?? [])
                        r.id: (r.data() as Map<String, dynamic>)['fotoUrl'] as String?,
                    };
                    // `favoritos` nunca guardó las etiquetas del animal
                    // (tamaño, energía, etc.) — el botón "Adoptar" de acá
                    // armaba la solicitud sin ellas, y compatibilidad.dart
                    // las completaba con sus valores por defecto (ej.
                    // "Mediano" aunque el animal fuera "Pequeño"). Se leen
                    // del rescate en vivo, igual que fotoPorRescateId.
                    final rescatePorId = <String, Map<String, dynamic>>{
                      for (final r in rescatesSnap.data?.docs ?? [])
                        r.id: r.data() as Map<String, dynamic>,
                    };
                    return _FavoritosGrid(
                      docs: docs,
                      rescateIdsConsultados: rescateIds.toSet(),
                      estadoPorRescateId: estadoPorRescateId,
                      fotoPorRescateId: fotoPorRescateId,
                      rescatePorId: rescatePorId,
                    );
                  },
                );
              },
            ),
          ),
        ]),
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
  const _FavoritosGrid({
    required this.docs,
    required this.rescateIdsConsultados,
    required this.estadoPorRescateId,
    required this.fotoPorRescateId,
    required this.rescatePorId,
  });

  @override
  Widget build(BuildContext context) {
    // Un rescate borrado desaparece de rescatesSnap, pero el favorito que
    // lo apuntaba puede seguir existiendo (limpiarlo es best-effort desde
    // el lado del rescatista — ver RescatesRepository.eliminar). Si el id
    // SÍ se consultó y no vino en la respuesta, está borrado de verdad: se
    // oculta acá para no mostrar un "Adoptar" fantasma sobre un animal que
    // ya no existe. Si el id no llegó a consultarse (más de 30 favoritos,
    // tope de whereIn), no se puede saber con certeza — se sigue mostrando
    // con los datos guardados en el propio favorito, como siempre.
    final docs = this.docs.where((d) {
      final rescateId = (d.data() as Map<String, dynamic>)['rescateId'] as String? ?? '';
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
                      docs.isEmpty ? 'SIN GUARDADOS' : '${docs.length} GUARDADO${docs.length == 1 ? "" : "S"}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          letterSpacing: 1.2, color: Colors.grey.shade700),
                    ),
                  ),
                ),
                if (docs.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.favorite_border, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        const Text('Aún no tienes favoritos',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: appInk)),
                        const SizedBox(height: 8),
                        Text('Toca ❤️ en las tarjetas para guardar\nanimalitos que te gusten.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.5)),
                      ]),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.72,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (_, i) {
                          final d            = docs[i].data() as Map<String, dynamic>;
                          final nombre       = d['animalNombre'] as String? ?? 'Sin nombre';
                          final especie      = d['especie']      as String? ?? '';
                          final edad         = d['edad']         as String? ?? '';
                          final ubicacion    = d['ubicacion']    as String? ?? '';
                          final rescatista   = d['rescatista']   as String? ?? 'Rescatista';
                          final rescatistaId = d['rescatistaId'] as String? ?? '';
                          final rescateId    = d['rescateId']    as String? ?? '';
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
                          final fotoUrl      = fotoPorRescateId[rescateId] ?? (d['fotoUrl'] as String?);
                          final emoji        = especie == 'Gato' ? '🐱' : '🐶';
                          final rescate      = rescatePorId[rescateId] ?? const <String, dynamic>{};

                          final animalMap = {
                            'nombre': nombre,
                            'especie': especie,
                            'edad': edad,
                            'genero': d['genero'] ?? '',
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

                          return Stack(children: [
                            Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07),
                                      blurRadius: 10, offset: const Offset(0, 3))],
                                ),
                                clipBehavior: Clip.hardEdge,
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                                              child: Center(child: Text(emoji,
                                                  style: const TextStyle(fontSize: 52)))),
                                        )
                                      : Container(
                                          width: double.infinity,
                                          color: const Color(0xFFD8F0E4),
                                          child: Center(child: Text(emoji,
                                              style: const TextStyle(fontSize: 52)))),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(nombre,
                                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                                              color: appInk),
                                          overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${edad.isNotEmpty ? "$edad · " : ""}$ubicacion',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 8),
                                      Builder(builder: (_) {
                                          final estado = estadoPorRescateId[rescateId] ?? '';
                                          final enProceso     = estado == 'En proceso de adopción';
                                          final adoptado      = estado == 'Adoptado';
                                          final devuelto      = estado == 'Regresado';
                                          final enHogarDePaso = estado == 'Hogar de paso';
                                          final fallecido     = estado == 'Fallecido';
                                          final noDisponible  = enProceso || adoptado || enHogarDePaso || fallecido;
                                          return Column(children: [
                                            if (devuelto) ...[
                                              Container(
                                                width: double.infinity,
                                                padding: const EdgeInsets.symmetric(vertical: 5),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFFFF3E0),
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: const Color(0xFFE65100).withValues(alpha: 0.4)),
                                                ),
                                                child: const Text('🔁 Fue devuelto',
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(fontSize: 11, color: Color(0xFFE65100), fontWeight: FontWeight.w600)),
                                              ),
                                              const SizedBox(height: 6),
                                            ],
                                            if (noDisponible)
                                              Container(
                                                width: double.infinity,
                                                padding: const EdgeInsets.symmetric(vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: cicloColor(estado).withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(20),
                                                  border: Border.all(color: cicloColor(estado).withValues(alpha: 0.4)),
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
                                                    fontSize: 12, fontWeight: FontWeight.w700,
                                                    color: cicloColor(estado),
                                                  ),
                                                ),
                                              )
                                            else
                                              SizedBox(
                                                width: double.infinity,
                                                child: ElevatedButton(
                                                  onPressed: () => Navigator.push(context, MaterialPageRoute(
                                                    builder: (_) => SolicitudAdopcionScreen(animal: animalMap),
                                                  )),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: appTeal,
                                                    foregroundColor: Colors.white,
                                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                                    elevation: 0,
                                                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                                  ),
                                                  child: const Text('Adoptar'),
                                                ),
                                              ),
                                          ]);
                                        },
                                      ),
                                    ]),
                                  ),
                                ]),
                            ),
                            // Botón quitar favorito — sin confirmación: quitar un
                            // favorito no es destructivo (el animal vuelve a
                            // aparecer solo en el carrusel principal) y es
                            // reversible con un toque, no amerita el paso extra.
                            Positioned(
                              top: 8, right: 8,
                              child: GestureDetector(
                                onTap: () => docs[i].reference.delete(),
                                child: Container(
                                  width: 36, height: 36,
                                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                  child: const Icon(Icons.favorite, color: appOrange, size: 17),
                                ),
                              ),
                            ),
                          ]);
                        },
                        childCount: docs.length,
                      ),
                    ),
                  ),
              ],
            );
  }
}
