import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../data/hogares_de_paso_repository.dart';

/// Roster de personas de confianza para hogar de paso — solo para
/// albergues (decisión de producto, mejoras_albergue.html). Las filas se
/// agregan solas al aprobar una solicitud de hogar de paso
/// (ver HogaresDePasoRepository.registrarAyuda en solicitudes_rescatista_screen.dart),
/// o a mano acá para alguien de confianza que el albergue ya conoce fuera
/// de la app.
class HogaresDePasoScreen extends StatefulWidget {
  const HogaresDePasoScreen({super.key});
  @override
  State<HogaresDePasoScreen> createState() => _HogaresDePasoScreenState();
}

class _HogaresDePasoScreenState extends State<HogaresDePasoScreen> {
  final _repo = HogaresDePasoRepository();
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> _agregarManual() async {
    final resultado = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => const _AgregarHogarSheet(),
    );
    if (resultado == null || _uid.isEmpty) return;
    await _repo.agregarManual(
      albergueId: _uid,
      nombre: resultado['nombre'] ?? '',
      telefono: resultado['telefono'] ?? '',
      notas: resultado['notas'] ?? '',
      email: resultado['email'] ?? '',
    );
  }

  Future<void> _editarContacto(
      String docId, String telefonoActual, String notasActuales, String emailActual) async {
    final resultado = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _EditarContactoSheet(
          telefonoInicial: telefonoActual, notasIniciales: notasActuales, emailInicial: emailActual),
    );
    if (resultado == null) return;
    await _repo.actualizarContacto(docId,
        telefono: resultado['telefono'] ?? '', notas: resultado['notas'] ?? '', email: resultado['email'] ?? '');
  }

  Future<void> _eliminar(String docId, String nombre) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Quitar de la red'),
        content: Text('¿Seguro que querés quitar a $nombre de tu red de hogares de paso?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: const Text('Quitar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    await _repo.eliminar(docId);
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appBg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _agregarManual,
        backgroundColor: appTeal,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Agregar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
      body: Stack(fit: StackFit.expand, children: [
        const LeafOverlay(),
        SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                tooltip: 'Volver',
                  onPressed: () => Navigator.pop(context),
                ),
                const Expanded(
                  child: Text('Red de hogares de paso',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: appInk,
                          fontFamily: 'Baloo2')),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Personas de confianza que ya te ayudaron con hogar de paso. Se agregan solas cuando aprobás una solicitud.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _repo.deAlbergue(_uid),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: appTeal));
                  }
                  if (snap.hasError) return errorFeedState();
                  final docs = (snap.data?.docs ?? []).toList()
                    ..sort((a, b) {
                      final va = a.data()['vecesAyudo'] as int? ?? 0;
                      final vb = b.data()['vecesAyudo'] as int? ?? 0;
                      return vb.compareTo(va);
                    });
                  if (docs.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Text('🏡', style: TextStyle(fontSize: 48)),
                          const SizedBox(height: 12),
                          Text(
                            'Todavía no tenés hogares de paso en tu red.\nCuando apruebes una solicitud, la persona se agrega acá sola.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                          ),
                        ]),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final d = docs[i].data();
                      final docId = docs[i].id;
                      final nombre = d['nombre'] as String? ?? 'Sin nombre';
                      final adoptanteId = d['adoptanteId'] as String? ?? '';
                      final veces = d['vecesAyudo'] as int? ?? 0;
                      final telefono = d['telefono'] as String? ?? '';
                      final notas = d['notas'] as String? ?? '';
                      final email = d['email'] as String? ?? '';
                      final ultimaVez = (d['ultimaVez'] as Timestamp?)?.toDate();
                      final linkWhatsapp = whatsappUrl(telefono);

                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            AvatarUsuario(
                              userId: adoptanteId.isEmpty ? null : adoptanteId,
                              inicial: nombre.isNotEmpty ? nombre[0].toUpperCase() : '?',
                              radius: 22,
                              backgroundColor: appTeal.withValues(alpha: 0.12),
                              textColor: appTeal,
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              const SizedBox(height: 2),
                              Text(veces == 1 ? 'Ayudó 1 vez' : 'Ayudó $veces veces',
                                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
                            ])),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(color: appTeal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.favorite, size: 12, color: appTeal),
                                const SizedBox(width: 4),
                                Text('$veces', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: appTeal)),
                              ]),
                            ),
                          ]),
                          if (ultimaVez != null || notas.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            if (ultimaVez != null)
                              Text('Última vez: ${formatearFecha(ultimaVez)}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                            if (notas.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(notas, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
                            ],
                          ],
                          const SizedBox(height: 10),
                          Row(children: [
                            if (linkWhatsapp != null)
                              GestureDetector(
                                onTap: () => launchUrl(Uri.parse(linkWhatsapp), mode: LaunchMode.externalApplication),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF25D366).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: const [
                                    Icon(Icons.chat, size: 13, color: Color(0xFF25D366)),
                                    SizedBox(width: 5),
                                    Text('WhatsApp', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF25D366))),
                                  ]),
                                ),
                              ),
                            const Spacer(),
                            Tooltip(
                              message: 'Editar contacto',
                              child: GestureDetector(
                                onTap: () => _editarContacto(docId, telefono, notas, email),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
                                  child: Icon(Icons.edit_outlined, size: 16, color: Colors.grey.shade600),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Tooltip(
                              message: 'Quitar',
                              child: GestureDetector(
                                onTap: () => _eliminar(docId, nombre),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(20)),
                                  child: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFD32F2F)),
                                ),
                              ),
                            ),
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
      ]),
    );
  }
}


class _AgregarHogarSheet extends StatefulWidget {
  const _AgregarHogarSheet();
  @override
  State<_AgregarHogarSheet> createState() => _AgregarHogarSheetState();
}

class _AgregarHogarSheetState extends State<_AgregarHogarSheet> {
  final _nombreCtl = TextEditingController();
  final _telefonoCtl = TextEditingController();
  final _notasCtl = TextEditingController();
  final _emailCtl = TextEditingController();

  bool get _valido => _nombreCtl.text.trim().isNotEmpty;

  @override
  void dispose() {
    _nombreCtl.dispose();
    _telefonoCtl.dispose();
    _notasCtl.dispose();
    _emailCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 16),
          const Text('Agregar a la red', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('Alguien de confianza que ya conocés, aunque todavía no haya pedido hogar de paso por la app.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          const SizedBox(height: 20),
          TextField(
            controller: _nombreCtl,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: _dec('Nombre *'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _telefonoCtl,
            keyboardType: TextInputType.phone,
            decoration: _dec('Teléfono / WhatsApp (opcional)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notasCtl,
            maxLines: 2,
            decoration: _dec('Notas (opcional)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailCtl,
            keyboardType: TextInputType.emailAddress,
            decoration: _dec('Email (opcional)'),
          ),
          const SizedBox(height: 6),
          Text('Si más adelante esta persona pide hogar de paso por la app con este mismo email, '
              'se suma acá en vez de crear una fila repetida.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _valido
                  ? () => Navigator.pop(context, {
                        'nombre': _nombreCtl.text.trim(),
                        'telefono': _telefonoCtl.text.trim(),
                        'notas': _notasCtl.text.trim(),
                        'email': _emailCtl.text.trim(),
                      })
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: appTeal,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: const Text('Agregar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      );
}

// Deja completar teléfono/notas después — pedido real de Eliza: las filas
// que se agregan solas al aprobar una solicitud nacen sin esos datos, y
// antes no había forma de cargarlos más tarde. No se edita el nombre acá
// a propósito: para las filas automáticas viene de la cuenta real de esa
// persona, no tiene sentido dejar que el albergue lo reescriba.
class _EditarContactoSheet extends StatefulWidget {
  final String telefonoInicial;
  final String notasIniciales;
  final String emailInicial;
  const _EditarContactoSheet(
      {required this.telefonoInicial, required this.notasIniciales, required this.emailInicial});
  @override
  State<_EditarContactoSheet> createState() => _EditarContactoSheetState();
}

class _EditarContactoSheetState extends State<_EditarContactoSheet> {
  late final _telefonoCtl = TextEditingController(text: widget.telefonoInicial);
  late final _notasCtl = TextEditingController(text: widget.notasIniciales);
  late final _emailCtl = TextEditingController(text: widget.emailInicial);

  @override
  void dispose() {
    _telefonoCtl.dispose();
    _notasCtl.dispose();
    _emailCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 16),
          const Text('Editar contacto', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          TextField(
            controller: _telefonoCtl,
            autofocus: true,
            keyboardType: TextInputType.phone,
            decoration: _dec('Teléfono / WhatsApp (opcional)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notasCtl,
            maxLines: 2,
            decoration: _dec('Notas (opcional)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailCtl,
            keyboardType: TextInputType.emailAddress,
            decoration: _dec('Email (opcional)'),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, {
                'telefono': _telefonoCtl.text.trim(),
                'notas': _notasCtl.text.trim(),
                'email': _emailCtl.text.trim(),
              }),
              style: ElevatedButton.styleFrom(
                backgroundColor: appTeal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: const Text('Guardar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      );
}
