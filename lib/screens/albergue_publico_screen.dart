import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import 'animal_detalle_screen.dart';

class AlberguePublicoScreen extends StatelessWidget {
  final String rescatistaId;
  const AlberguePublicoScreen({super.key, required this.rescatistaId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('usuarios')
          .doc(rescatistaId)
          .snapshots(),
      builder: (context, userSnap) {
        final data     = userSnap.data?.data() as Map<String, dynamic>? ?? {};
        final nombre   = data['albergueNombre'] as String? ?? data['displayName'] as String? ?? 'Albergue';
        final tipo     = data['albergueTipo']   as String? ?? '';
        final capacidad= (data['capacidadTotal'] as int?) ?? 0;
        final foto64   = data['fotoBase64']     as String?;
        final iniciales= nombre.trim().split(' ')
            .take(2).map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('rescates')
              .where('rescatistaId', isEqualTo: rescatistaId)
              .snapshots(),
          builder: (context, rSnap) {
            final all        = (rSnap.data?.docs ?? []).where((d) =>
                (d.data() as Map)['creadoPor'] == 'albergue').toList();
            final disponibles= all.where((d) {
              final e = (d.data() as Map)['estadoAdopcion'] as String? ?? 'Rescatado';
              return e != 'Adoptado' && e != 'Fallecido';
            }).toList()..sort((a, b) {
              final ta = ((a.data() as Map)['creadoEn'] as Timestamp?);
              final tb = ((b.data() as Map)['creadoEn'] as Timestamp?);
              if (ta == null || tb == null) return 0;
              return tb.compareTo(ta);
            });
            final totalAdoptados = all.where((d) =>
                (d.data() as Map)['estadoAdopcion'] == 'Adoptado').length;

            return Scaffold(
              backgroundColor: appBg,
              body: CustomScrollView(
                slivers: [
                  // ── Header ──────────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Stack(children: [
                      Container(
                        height: 230,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF0A5C40), Color(0xFF1F8A62)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                      SafeArea(
                        child: Column(children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 4, top: 4),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: IconButton(
                                icon: const Icon(Icons.arrow_back_ios_new,
                                    color: Colors.white, size: 20),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  width: 3),
                            ),
                            child: Builder(builder: (_) {
                              final fotoBytes = bytesFotoSegura(foto64);
                              return CircleAvatar(
                                radius: 42,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.2),
                                backgroundImage: fotoBytes != null
                                    ? MemoryImage(fotoBytes)
                                    : null,
                                onBackgroundImageError:
                                    fotoBytes != null ? (_, __) {} : null,
                                child: fotoBytes == null
                                    ? Text(iniciales,
                                        style: const TextStyle(
                                            fontSize: 26,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white))
                                    : null,
                              );
                            }),
                          ),
                          const SizedBox(height: 10),
                          Text(nombre,
                              style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                          if (tipo.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              tipo,
                              style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      Colors.white.withValues(alpha: 0.78)),
                            ),
                          ],
                        ]),
                      ),
                    ]),
                  ),

                  // ── Stats ────────────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                      child: Row(children: [
                        _statChip('${disponibles.length}',
                            'disponibles', appTeal),
                        const SizedBox(width: 10),
                        _statChip('$totalAdoptados',
                            'adoptados', const Color(0xFF2196F3)),
                        if (capacidad > 0) ...[
                          const SizedBox(width: 10),
                          _statChip('$capacidad',
                              'capacidad', Colors.grey.shade500),
                        ],
                      ]),
                    ),
                  ),

                  // ── Sección ──────────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
                      child: Text('Animales disponibles',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A))),
                    ),
                  ),

                  // ── Grid ─────────────────────────────────────────────────────
                  if (disponibles.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(48),
                        child: Center(
                          child: Text('No hay animales disponibles por ahora.',
                              style: TextStyle(color: Colors.grey)),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.78,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) => _animalCard(
                              ctx,
                              disponibles[i].data() as Map<String, dynamic>,
                              disponibles[i].id),
                          childCount: disponibles.length,
                        ),
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

  Widget _statChip(String valor, String label, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Column(children: [
            Text(valor,
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: color,
                    height: 1)),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  Widget _animalCard(
      BuildContext ctx, Map<String, dynamic> d, String docId) {
    final nombre        = (d['nombre'] as String?)?.isNotEmpty == true
        ? d['nombre'] as String : 'Sin nombre';
    final especie       = d['especie']        as String? ?? 'Perro';
    final edad          = d['edad']           as String? ?? '';
    final fotoUrl       = d['fotoUrl']        as String?;
    final urgencia      = d['urgencia']       as String? ?? '';
    final estadoAdopcion= d['estadoAdopcion'] as String? ?? 'Rescatado';
    final emoji         = especie == 'Gato' ? '🐱' : '🐶';
    final estadoColor   = cicloColor(estadoAdopcion);

    final animalMap = {
      'nombre':              nombre,
      'especie':             especie,
      'edad':                edad,
      'raza':                d['raza']        ?? 'Criolla',
      'tamano':              d['tamano']      ?? 'Mediano',
      'ubicacion':           d['ubicacion']   ?? '',
      'descripcion':         d['descripcion'] ?? '',
      'tags': <String>[
        if (d['okConNinos']    == true) 'Amigable con niños',
        if (d['okConMascotas'] == true) 'Es sociable',
        if ((d['energia'] as String?)?.isNotEmpty == true) d['energia'] as String,
      ],
      'rescatista':          d['rescatistaNombre'] ?? '',
      'rescatistaId':        d['rescatistaId']     ?? '',
      'rescateId':           docId,
      'estadoAdopcion':      estadoAdopcion,
      'fotoUrl':             fotoUrl,
      'fotoUrl2':            d['fotoUrl2'],
      'latitud':             d['latitud'],
      'longitud':            d['longitud'],
      'energia':             d['energia'],
      'okConNinos':          d['okConNinos'],
      'okConMascotas':       d['okConMascotas'],
      'requiereExperiencia': d['requiereExperiencia'],
      'verificado':          d['verificado'] ?? false,
      'urgencia':            urgencia,
      'creadoPor':           d['creadoPor'] ?? 'albergue',
    };

    return GestureDetector(
      onTap: () => Navigator.push(ctx, MaterialPageRoute(
          builder: (_) => AnimalDetalleScreen(animal: animalMap))),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(children: [
          Column(children: [
            Expanded(
              child: fotoUrl != null
                  ? FotoUrl(
                      url: fotoUrl,
                      width: double.infinity,
                      fallback: Container(
                          width: double.infinity,
                          color: const Color(0xFFD8F0E4),
                          child: Center(
                              child: Text(emoji,
                                  style: const TextStyle(fontSize: 40)))),
                    )
                  : Container(
                      width: double.infinity,
                      color: const Color(0xFFD8F0E4),
                      child: Center(
                          child: Text(emoji,
                              style: const TextStyle(fontSize: 40)))),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(nombre,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A)),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text([especie, if (edad.isNotEmpty) edad].join(' · '),
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: estadoColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: estadoColor.withValues(alpha: 0.35)),
                  ),
                  child: Text(estadoAdopcion,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: estadoColor)),
                ),
              ]),
            ),
          ]),
          if (urgencia == 'Alta')
            Positioned(
              top: 8, left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                    color: const Color(0xFFD32F2F),
                    borderRadius: BorderRadius.circular(8)),
                child: const Text('URGENTE',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
            ),
        ]),
      ),
    );
  }
}
