import 'package:flutter/material.dart';
import '../theme.dart';

/// Foto completa, sin recortar (BoxFit.contain) y con zoom — la tarjeta del
/// feed recorta la foto a propósito para que se vea prolija y llamativa
/// (ver alignment: Alignment.topCenter en adoptante_feed_screen.dart), pero
/// eso a veces deja afuera al animal entero; esto le da a quien quiera verlo
/// completo una forma de hacerlo con un toque, sin cambiar cómo se ve la
/// tarjeta.
///
/// Extraído de adoptante_feed_screen.dart (que llegó a 1642 líneas) — es
/// autocontenido y también lo usa animal_detalle_screen.dart, así que vivir
/// en su propio archivo es más claro que dentro de la del feed.
class VisorFotoCompleta extends StatefulWidget {
  final List<String> fotos;
  final int indiceInicial;
  const VisorFotoCompleta({super.key, required this.fotos, required this.indiceInicial});
  @override
  State<VisorFotoCompleta> createState() => _VisorFotoCompletaState();
}

class _VisorFotoCompletaState extends State<VisorFotoCompleta> {
  late final _ctrl = PageController(initialPage: widget.indiceInicial);
  late int _idx = widget.indiceInicial;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: PageView.builder(
              controller: _ctrl,
              itemCount: widget.fotos.length,
              onPageChanged: (i) => setState(() => _idx = i),
              itemBuilder: (_, i) => InteractiveViewer(
                minScale: 1, maxScale: 4,
                child: Center(
                  child: FotoUrl(
                    url: widget.fotos[i],
                    fit: BoxFit.contain,
                    fallback: const Icon(Icons.pets, color: Colors.white54, size: 80),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 4, right: 4,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              tooltip: 'Cerrar',
              onPressed: () => Navigator.pop(context),
            ),
          ),
          if (widget.fotos.length > 1)
            Positioned(
              bottom: 20, left: 0, right: 0,
              child: Row(mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(widget.fotos.length, (i) => Container(
                    width: 8, height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(shape: BoxShape.circle,
                        color: i == _idx ? Colors.white : Colors.white38),
                  ))),
            ),
        ]),
      ),
    );
  }
}
