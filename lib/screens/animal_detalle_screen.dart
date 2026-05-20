import 'package:flutter/material.dart';
import 'dart:convert';
import '../theme.dart';
import 'chat_screen.dart';
import 'solicitud_adopcion_screen.dart';

class AnimalDetalleScreen extends StatefulWidget {
  final Map<String, dynamic> animal;
  const AnimalDetalleScreen({super.key, required this.animal});

  @override
  State<AnimalDetalleScreen> createState() => _AnimalDetalleScreenState();
}

class _AnimalDetalleScreenState extends State<AnimalDetalleScreen> {
  final _pageCtrl = PageController();
  int _paginaFoto = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animal       = widget.animal;
    final fotoBase64   = animal['fotoBase64']   as String?;
    final fotoBase64_2 = animal['fotoBase64_2'] as String?;
    final nombre      = animal['nombre']      as String;
    final edad        = (animal['edad']   as String?) ?? '';
    final genero      = (animal['genero'] as String?) ?? '';
    final raza        = animal['raza']        as String;
    final ubicacion   = animal['ubicacion']   as String;
    final descripcion = animal['descripcion'] as String;
    final tags        = (animal['tags'] as List).cast<String>();
    final emoji       = animal['especie'] == 'Gato' ? '🐱' : '🐶';

    final fotos = [?fotoBase64, ?fotoBase64_2];

    return Scaffold(
      backgroundColor: appBg,
      body: SafeArea(
        child: Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              _circleBtn(Icons.arrow_back_ios_new, () => Navigator.pop(context)),
              Expanded(child: Text(nombre,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)))),
              _circleBtn(Icons.favorite_border, () {}),
            ]),
          ),
          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Photos carousel
                Stack(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: fotos.isEmpty
                      ? Container(
                          height: 260, width: double.infinity,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF3D7A52), Color(0xFF1F4A30)],
                              begin: Alignment.topLeft, end: Alignment.bottomRight,
                            ),
                          ),
                          child: Center(child: Text(emoji, style: const TextStyle(fontSize: 90))),
                        )
                      : SizedBox(
                          height: 260,
                          child: PageView.builder(
                            controller: _pageCtrl,
                            itemCount: fotos.length,
                            onPageChanged: (i) => setState(() => _paginaFoto = i),
                            itemBuilder: (_, i) => Image.memory(
                              base64Decode(fotos[i]),
                              width: double.infinity, fit: BoxFit.cover,
                            ),
                          ),
                        ),
                  ),
                  if (fotos.length > 1)
                    Positioned(
                      bottom: 10, left: 0, right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(fotos.length, (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width:  _paginaFoto == i ? 18 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: _paginaFoto == i ? Colors.white : Colors.white.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        )),
                      ),
                    ),
                ]),
                const SizedBox(height: 12),
                // Badges
                Row(children: [
                  _pill(Icons.location_on, ubicacion),
                  if (edad.isNotEmpty) ...[const SizedBox(width: 8), _pill(null, edad)],
                ]),
                const SizedBox(height: 16),
                // Name
                Text(nombre,
                    style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Color(0xFF1B3A1F))),
                const SizedBox(height: 4),
                Text([raza, if (genero.isNotEmpty && genero != 'No sé') genero, if (edad.isNotEmpty) edad].join(' · '),
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                const SizedBox(height: 12),
                // Chips
                if (tags.isNotEmpty) Wrap(spacing: 8, runSpacing: 6,
                  children: tags.map((t) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF9DDD5), borderRadius: BorderRadius.circular(20)),
                    child: Text(t,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF8B3A1F), fontWeight: FontWeight.w500)),
                  )).toList()),
                const SizedBox(height: 22),
                // Historia
                if (descripcion.isNotEmpty) ...[
                  const Text('MI HISTORIA',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: appTeal)),
                  const SizedBox(height: 10),
                  Text('"$descripcion"',
                      style: const TextStyle(fontSize: 15, fontStyle: FontStyle.italic,
                          color: Color(0xFF2A2A2A), height: 1.65, fontWeight: FontWeight.w500)),
                ],
                const SizedBox(height: 100),
              ]),
            ),
          ),
          // Bottom buttons
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            color: appBg,
            child: Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ChatScreen(animal: animal))),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                        color: Colors.white, borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.grey.shade200)),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.chat_bubble_outline, size: 18),
                      SizedBox(width: 8),
                      Text('Mensaje', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => SolicitudAdopcionScreen(animal: animal))),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(color: appOrange, borderRadius: BorderRadius.circular(30)),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.favorite, size: 18, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Solicitar adopción',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36, height: 36,
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.85), shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 6)]),
      child: Icon(icon, size: 16, color: const Color(0xFF444444)),
    ),
  );

  Widget _pill(IconData? icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[const Icon(Icons.location_on, size: 12, color: appTeal), const SizedBox(width: 4)],
      Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ]),
  );
}
