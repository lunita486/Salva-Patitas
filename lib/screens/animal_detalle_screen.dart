import 'package:flutter/material.dart';
import '../theme.dart';
import 'visor_foto_completa.dart';
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
    final fotoUrl      = animal['fotoUrl']  as String?;
    final fotoUrl2     = animal['fotoUrl2'] as String?;
    final nombre      = animal['nombre']      as String;
    final edad        = (animal['edad']   as String?) ?? '';
    final genero      = (animal['genero'] as String?) ?? '';
    final raza        = animal['raza']        as String;
    final ubicacion   = animal['ubicacion']   as String;
    final descripcion = animal['descripcion'] as String;
    final tags        = (animal['tags'] as List).cast<String>();
    final emoji       = animal['especie'] == 'Gato' ? '🐱' : '🐶';
    final vacunado      = (animal['vacunado']      as String?) ?? 'Aún no lo sé';
    final desparasitado = (animal['desparasitado'] as String?) ?? 'Aún no lo sé';

    final fotos          = [?fotoUrl, ?fotoUrl2];
    final estadoAdopcion = animal['estadoAdopcion'] as String? ?? '';
    final enHogar        = estadoAdopcion == 'Hogar de paso';

    return Scaffold(
      backgroundColor: appBg,
      body: SafeArea(
        child: Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              _circleBtn(Icons.arrow_back_ios_new, () => Navigator.pop(context), label: 'Volver'),
              Expanded(child: Text(nombre,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: appInk,
                      fontFamily: 'Baloo2'))),
              const SizedBox(width: 36),
            ]),
          ),
          // Photo carousel — FUERA del scroll para que el swipe no compita
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            // Tocar la foto la abre completa, sin recortar y con zoom —
            // igual que en la tarjeta del feed. El carrusel de acá recorta
            // con BoxFit.cover exactamente igual, pero este toque nunca
            // estuvo conectado: el ítem del checklist ("tocar la foto en el
            // feed o en el detalle → se abre completa") lo prometía y en el
            // detalle no pasaba nada.
            child: GestureDetector(
              onTap: fotos.isEmpty ? null : () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => VisorFotoCompleta(fotos: fotos, indiceInicial: _paginaFoto),
              )),
              child: Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: fotos.isEmpty
                  ? Container(
                      height: 380, width: double.infinity,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF3D7A52), Color(0xFF1F4A30)],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                      ),
                      child: Center(child: Text(emoji, style: const TextStyle(fontSize: 90))),
                    )
                  : SizedBox(
                      height: 380,
                      child: PageView.builder(
                        controller: _pageCtrl,
                        itemCount: fotos.length,
                        onPageChanged: (i) => setState(() => _paginaFoto = i),
                        // FotoAnimal en vez de recorte — mismo motivo que
                        // en la tarjeta del feed: la foto entera sobre un
                        // fondo de sí misma desenfocado (caso "Tobyiii").
                        itemBuilder: (_, i) => FotoAnimal(
                          url: fotos[i],
                          width: double.infinity,
                          fallback: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFF3D7A52), Color(0xFF1F4A30)],
                                begin: Alignment.topLeft, end: Alignment.bottomRight,
                              ),
                            ),
                            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 90))),
                          ),
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
              // Misma señal visual que en la tarjeta del feed: sin el
              // ícono, la única forma de descubrir que la foto se puede
              // tocar era por casualidad.
              if (fotos.isNotEmpty)
                Positioned(
                  bottom: 12, right: 12,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.38),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.zoom_out_map, color: Colors.white, size: 16),
                    ),
                  ),
                ),
            ]),
            ),
          ),
          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 12),
                // Badges
                Row(children: [
                  if (ubicacion.isNotEmpty) _pill(Icons.location_on, ubicacion),
                  if (ubicacion.isNotEmpty && edad.isNotEmpty) const SizedBox(width: 8),
                  if (edad.isNotEmpty) _pill(null, edad),
                ]),
                const SizedBox(height: 16),
                // Name
                Text(nombre,
                    style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Color(0xFF1B3A1F))),
                const SizedBox(height: 4),
                Text([raza, if (genero.isNotEmpty && genero != 'No sé') genero, if (edad.isNotEmpty) edad].join(' · '),
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
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
                // Salud — sugerencia real de un tester: el adoptante
                // necesita saber esto de antemano porque va a tener que
                // asumir esos gastos si todavía falta. "Aún no lo sé" se
                // muestra igual que Sí/No (no se oculta): es información
                // real y honesta, no un dato faltante.
                const Text('SALUD',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: appTeal)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  _pill(null, 'Vacunado: $vacunado'),
                  _pill(null, 'Desparasitado: $desparasitado'),
                ]),
                const SizedBox(height: 22),
                // Historia
                if (descripcion.isNotEmpty) ...[
                  const Text('MI HISTORIA',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: appTeal)),
                  const SizedBox(height: 10),
                  Text(descripcion,
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
                    padding: EdgeInsets.symmetric(vertical: enHogar ? 8 : 14),
                    decoration: BoxDecoration(color: appOrange, borderRadius: BorderRadius.circular(30)),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.favorite, size: 18, color: Colors.white),
                        const SizedBox(width: 8),
                        const Text('Solicitar adopción',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                      ]),
                      if (enHogar) ...[
                        const SizedBox(height: 2),
                        Text('Actualmente en hogar de paso',
                            style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.85))),
                      ],
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

  Widget _circleBtn(IconData icon, VoidCallback onTap, {String? label}) => Tooltip(
    message: label ?? '',
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 6)]),
        child: Icon(icon, size: 16, color: const Color(0xFF444444)),
      ),
    ),
  );

  Widget _pill(IconData? icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[const Icon(Icons.location_on, size: 12, color: appTeal), const SizedBox(width: 4)],
      Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ]),
  );
}
