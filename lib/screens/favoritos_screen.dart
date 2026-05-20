import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import '../theme.dart';
import 'solicitud_adopcion_screen.dart';

class FavoritosScreen extends StatelessWidget {
  const FavoritosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appBg,
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('favoritos')
              .where('adoptanteId', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
              .snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: appTeal));
            }
            final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
            final allDocs = snap.data?.docs ?? [];
            final seen = <String>{};
            final docs = allDocs.where((doc) {
              final d = doc.data() as Map<String, dynamic>;
              final nombre = (d['animalNombre'] as String? ?? '').toLowerCase();
              return seen.add(nombre);
            }).toList();
            for (final doc in allDocs) {
              final d = doc.data() as Map<String, dynamic>;
              final nombre = (d['animalNombre'] as String? ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
              final expectedId = '${uid}_$nombre';
              if (doc.id != expectedId) doc.reference.delete();
            }

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          docs.isEmpty ? 'SIN GUARDADOS' : '${docs.length} GUARDADO${docs.length == 1 ? "" : "S"}',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                              letterSpacing: 1.2, color: Colors.grey.shade500),
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
                          final fotoBase64   = d['fotoBase64']   as String?;
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
                            'fotoBase64': fotoBase64,
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
                                    child: fotoBase64 != null
                                      ? Image.memory(base64Decode(fotoBase64),
                                          width: double.infinity, fit: BoxFit.cover)
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
                                      StreamBuilder<DocumentSnapshot>(
                                        stream: rescateId.isNotEmpty
                                            ? FirebaseFirestore.instance.collection('rescates').doc(rescateId).snapshots()
                                            : const Stream.empty(),
                                        builder: (_, rescSnap) {
                                          final rData  = rescateId.isNotEmpty ? (rescSnap.data?.data() as Map<String, dynamic>?) : null;
                                          final estado = rData?['estadoAdopcion'] as String? ?? '';
                                          final enProceso = estado == 'En proceso de adopción';
                                          final adoptado  = estado == 'Adoptado';
                                          final devuelto  = estado == 'Regresado';
                                          final noDisponible = enProceso || adoptado;
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
                                                  color: enProceso ? const Color(0xFFE65100).withValues(alpha: 0.1) : Colors.grey.shade100,
                                                  borderRadius: BorderRadius.circular(20),
                                                  border: Border.all(color: enProceso ? const Color(0xFFE65100).withValues(alpha: 0.5) : Colors.grey.shade300),
                                                ),
                                                child: Text(
                                                  enProceso ? 'En proceso de adopción 🔄' : 'Ya adoptado 🏠',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    fontSize: 12, fontWeight: FontWeight.w700,
                                                    color: enProceso ? const Color(0xFFE65100) : const Color(0xFF888888),
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
                                onTap: () => docs[i].reference.delete(),
                                child: Container(
                                  width: 30, height: 30,
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
          },
        ),
      ),
    );
  }
}
