import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
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
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text('Tus favoritos',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
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
                  stream: rescateIds.isEmpty
                      ? const Stream.empty()
                      : FirebaseFirestore.instance
                          .collection('rescates')
                          .where(FieldPath.documentId, whereIn: rescateIds)
                          .snapshots(),
                  builder: (context, rescatesSnap) {
                    final estadoPorRescateId = <String, String>{
                      for (final r in rescatesSnap.data?.docs ?? [])
                        r.id: (r.data() as Map<String, dynamic>)['estadoAdopcion'] as String? ?? '',
                    };
                    return _FavoritosGrid(docs: docs, estadoPorRescateId: estadoPorRescateId);
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
  final Map<String, String> estadoPorRescateId;
  const _FavoritosGrid({required this.docs, required this.estadoPorRescateId});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      docs.isEmpty ? 'SIN GUARDADOS' : '${docs.length} GUARDADO${docs.length == 1 ? "" : "S"}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          letterSpacing: 1.2, color: Colors.grey.shade500),
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
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                        const SizedBox(height: 8),
                        Text('Toca ❤️ en las tarjetas para guardar\nanimalitos que te gusten.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade500, height: 1.5)),
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
                          final fotoUrl      = d['fotoUrl']      as String?;
                          final rescatista   = d['rescatista']   as String? ?? 'Rescatista';
                          final rescatistaId = d['rescatistaId'] as String? ?? '';
                          final rescateId    = d['rescateId']    as String? ?? '';
                          final emoji        = especie == 'Gato' ? '🐱' : '🐶';

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
                                    child: fotoUrl != null
                                      ? FotoUrl(
                                          url: fotoUrl,
                                          width: double.infinity, fit: BoxFit.cover,
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
                                              color: Color(0xFF1A1A1A)),
                                          overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${edad.isNotEmpty ? "$edad · " : ""}$ubicacion',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
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
                            // Botón quitar favorito
                            Positioned(
                              top: 8, right: 8,
                              child: GestureDetector(
                                onTap: () async {
                                  final confirmar = await showDialog<bool>(
                                    context: context,
                                    builder: (dlgCtx) => AlertDialog(
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      title: const Text('Quitar de favoritos'),
                                      content: Text('¿Seguro que quieres quitar a $nombre de tus favoritos?'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(dlgCtx, false),
                                            child: const Text('Cancelar')),
                                        TextButton(
                                          onPressed: () => Navigator.pop(dlgCtx, true),
                                          child: const Text('Quitar', style: TextStyle(color: Colors.red)),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmar == true) docs[i].reference.delete();
                                },
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
