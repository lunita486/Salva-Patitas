import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import '../theme.dart';
import 'editar_rescate_screen.dart';

class TodosLosRescatesScreen extends StatefulWidget {
  final String? filtroInicial;
  final bool esAlbergue;
  const TodosLosRescatesScreen({super.key, this.filtroInicial, this.esAlbergue = false});
  @override
  State<TodosLosRescatesScreen> createState() => _TodosLosRescatesScreenState();
}

class _TodosLosRescatesScreenState extends State<TodosLosRescatesScreen> {
  String? _filtroEstado;
  String? _filtroEspecie;

  static const _estadosFiltroRescatista = [
    'Rescatado',
    'Hogar de paso',
    'En proceso de adopción',
    'Adoptado',
    'Regresado',
    'Fallecido',
  ];


  static const _especiesFiltro = ['Perro', 'Gato', 'Otro'];

  Future<void> _eliminar(BuildContext context, String docId, String nombre) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Eliminar publicación'),
        content: Text('¿Seguro que quieres eliminar a $nombre? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await FirebaseFirestore.instance.collection('rescates').doc(docId).delete();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Publicación eliminada'), backgroundColor: appTeal));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  void initState() {
    super.initState();
    _filtroEstado = widget.filtroInicial;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appBg,
      body: Stack(
        children: [
          Positioned.fill(child: Container(color: appBg)),
          SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
                child: Row(children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.esAlbergue ? 'Mis animales' : 'Mis rescates',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                      if (widget.esAlbergue && _filtroEstado != null)
                        Text(_filtroEstado!,
                            style: TextStyle(fontSize: 12, color: cicloColor(_filtroEstado!), fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ]),
              ),
              // Chips de estado: rescatista siempre, albergue solo sin filtroInicial
              if (!widget.esAlbergue || widget.filtroInicial == null) ...[
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _chip('Todos', null, _filtroEstado, (v) => setState(() => _filtroEstado = v)),
                      ..._estadosFiltroRescatista
                          .map((e) => _chip(e, e, _filtroEstado, (v) => setState(() => _filtroEstado = v))),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
              ],
              // Chips de especie
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _chip('Todas las especies', null, _filtroEspecie,
                        (v) => setState(() => _filtroEspecie = v), small: true),
                    ..._especiesFiltro.map((e) => _chip(e, e, _filtroEspecie,
                        (v) => setState(() => _filtroEspecie = v), small: true)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('rescates')
                      .where('rescatistaId', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
                      .snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: appTeal));
                    }
                    final rolFiltro = widget.esAlbergue ? 'albergue' : 'rescatista';
                    var allDocs = (snap.data?.docs ?? []).where((d) {
                      final cp = (d.data() as Map)['creadoPor'] as String?;
                      return cp == rolFiltro;
                    }).toList()..sort((a, b) {
                      final ta = (a.data() as Map)['creadoEn'] as Timestamp?;
                      final tb = (b.data() as Map)['creadoEn'] as Timestamp?;
                      if (ta == null || tb == null) return 0;
                      return tb.compareTo(ta);
                    });
                    if (_filtroEstado != null) {
                      allDocs = allDocs.where((doc) {
                        final ea = (doc.data() as Map<String, dynamic>)['estadoAdopcion'] as String? ?? 'Rescatado';
                        if (_filtroEstado == 'En cuidado') {
                          return ea == 'Rescatado' || ea == 'Hogar de paso';
                        }
                        return ea == _filtroEstado;
                      }).toList();
                    }
                    if (_filtroEspecie != null) {
                      allDocs = allDocs.where((doc) {
                        final esp = (doc.data() as Map<String, dynamic>)['especie'] as String? ?? '';
                        if (_filtroEspecie == 'Otro') return esp != 'Perro' && esp != 'Gato';
                        return esp == _filtroEspecie;
                      }).toList();
                    }
                    if (allDocs.isEmpty) {
                      return Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Text('🐾', style: TextStyle(fontSize: 48)),
                          const SizedBox(height: 12),
                          Text(
                            _filtroEstado == null
                                ? 'Aún no has publicado rescates'
                                : 'No hay animales en estado "$_filtroEstado"',
                            style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
                            textAlign: TextAlign.center,
                          ),
                        ]),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      itemCount: allDocs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        final d = allDocs[i].data() as Map<String, dynamic>;
                        final docId         = allDocs[i].id;
                        final nombre        = (d['nombre'] as String?)?.isNotEmpty == true ? d['nombre'] : 'Sin nombre';
                        final especie       = d['especie']       ?? '';
                        final estado        = d['estado']        ?? '';
                        final urgencia      = d['urgencia']      ?? '';
                        final ubicacion     = d['ubicacion']     ?? '';
                        final fotoBase64    = d['fotoBase64']    as String?;
                        final estadoAdopcion= d['estadoAdopcion'] as String? ?? 'Rescatado';
                        final motivoRegreso = d['motivoRegreso']  as String?;
                        final emoji = especie == 'Gato' ? '🐱' : '🐶';
                        final urgColor = urgencia == 'Alta'
                            ? const Color(0xFFD32F2F)
                            : urgencia == 'Media' ? const Color(0xFFE65100) : appTeal;

                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: fotoBase64 != null
                                  ? Image.memory(base64Decode(fotoBase64),
                                      width: 64, height: 64, fit: BoxFit.cover)
                                  : Container(width: 64, height: 64,
                                      color: const Color(0xFFD8F0E4),
                                      child: Center(child: Text(emoji, style: const TextStyle(fontSize: 32)))),
                              ),
                              const SizedBox(width: 14),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 4),
                                Text('$especie · $estado', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                                const SizedBox(height: 4),
                                Row(children: [
                                  const Icon(Icons.location_on, size: 13, color: appTeal),
                                  const SizedBox(width: 2),
                                  Text(ubicacion, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                ]),
                              ])),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(color: urgColor.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                                child: Text(urgencia, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: urgColor)),
                              ),
                            ]),
                            const SizedBox(height: 12),
                            if (estadoAdopcion == 'Regresado' && motivoRegreso != null && motivoRegreso.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFEBEE),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFD32F2F).withOpacity(0.3)),
                                ),
                                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  const Icon(Icons.info_outline, size: 14, color: Color(0xFFD32F2F)),
                                  const SizedBox(width: 6),
                                  Expanded(child: Text('Motivo: $motivoRegreso',
                                      style: const TextStyle(fontSize: 12, color: Color(0xFFD32F2F)))),
                                ]),
                              ),
                            Row(children: [
                              GestureDetector(
                                onTap: () => showModalBottomSheet(
                                  context: context,
                                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                                  builder: (_) => CambiarEstadoSheet(docId: docId, estadoActual: estadoAdopcion),
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: cicloColor(estadoAdopcion).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: cicloColor(estadoAdopcion).withOpacity(0.3)),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Text(estadoAdopcion, style: TextStyle(fontSize: 12,
                                        fontWeight: FontWeight.w700, color: cicloColor(estadoAdopcion))),
                                    const SizedBox(width: 4),
                                    Icon(Icons.expand_more, size: 14, color: cicloColor(estadoAdopcion)),
                                  ]),
                                ),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: () => _eliminar(context, docId, nombre),
                                child: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFEBEE),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: const Color(0xFFD32F2F).withValues(alpha: 0.3)),
                                  ),
                                  child: const Icon(Icons.delete_outline, size: 15, color: Color(0xFFD32F2F)),
                                ),
                              ),
                              if (estadoAdopcion != 'Adoptado' && estadoAdopcion != 'Fallecido') ...[
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => Navigator.push(context, MaterialPageRoute(
                                      builder: (_) => EditarRescateScreen(docId: docId, data: d))),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Colors.grey.shade300),
                                    ),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      Icon(Icons.edit_outlined, size: 13, color: Colors.grey.shade600),
                                      const SizedBox(width: 4),
                                      Text('Editar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                                    ]),
                                  ),
                                ),
                              ],
                            ]),
                          ]),
                        );
                      },
                    );
                  },
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String? valor, String? filtroActivo,
      ValueChanged<String?> onTap, {bool small = false}) {
    final activo = filtroActivo == valor;
    final color  = valor == null ? appTeal : cicloColor(valor);
    return GestureDetector(
      onTap: () => onTap(activo ? null : valor),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: EdgeInsets.symmetric(horizontal: small ? 12 : 14, vertical: small ? 5 : 7),
        decoration: BoxDecoration(
          color: activo ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: activo ? color : Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: small ? 11 : 12,
            fontWeight: FontWeight.w600,
            color: activo ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }
}
