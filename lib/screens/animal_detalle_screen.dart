import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../routing/app_router.dart';
import '../theme/salva_patitas_theme.dart';
import '../widgets/sp_widgets.dart';
import '../domain/reglas_negocio.dart';
import '../widgets/fotos.dart';

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
    final animal = widget.animal;
    final fotoUrl = animal['fotoUrl'] as String?;
    final fotoUrl2 = animal['fotoUrl2'] as String?;
    // `?? ...` en vez de un cast directo (lo que había antes) — nombre,
    // raza, ubicación, descripción y tags son los únicos 5 campos de este
    // mapa que se casteaban sin red de seguridad, a diferencia de todos
    // los demás en esta misma función. Hoy no pasa nada porque las 3
    // pantallas que abren esta ficha siempre mandan el mapa completo,
    // pero cualquier forma NUEVA de llegar acá (un link, una notificación,
    // un mapa armado a mano en otra pantalla) que se olvide uno de estos
    // 5 campos hace crashear la ficha entera en vez de mostrarla con un
    // valor vacío. Hallazgo de auditoría de código.
    final nombre = nombreDeAnimal(animal['nombre'] as String?);
    final edad = (animal['edad'] as String?) ?? '';
    final genero = (animal['genero'] as String?) ?? '';
    final raza = (animal['raza'] as String?) ?? 'Criolla';
    final ubicacion = (animal['ubicacion'] as String?) ?? '';
    final descripcion = (animal['descripcion'] as String?) ?? '';
    final tags = ((animal['tags'] as List?) ?? const []).cast<String>();
    final vacunado = (animal['vacunado'] as String?) ?? 'Aún no lo sé';
    final desparasitado =
        (animal['desparasitado'] as String?) ?? 'Aún no lo sé';

    final fotos = [?fotoUrl, ?fotoUrl2];
    final estadoAdopcion = animal['estadoAdopcion'] as String? ?? '';
    final enHogar = estadoAdopcion == 'Hogar de paso';
    // sePuedeAdoptar (domain/reglas_negocio.dart) — la misma regla que el
    // feed, Favoritos, el perfil público del albergue y la aprobación.
    // Esta ficha NO miraba el estado: ofrecía "Solicitar adopción" para
    // cualquier animal, incluso uno ya adoptado o fallecido. Se llega acá
    // desde el perfil público de un albergue y desde "Mis solicitudes"
    // (que abre la ficha a propósito sin importar el estado, para poder
    // volver a ver las fotos), así que el botón quedaba accesible igual.
    final puedeAdoptarse = sePuedeAdoptar(estadoAdopcion);
    // En horizontal el alto de pantalla completo puede ser menor a 380 —
    // header + foto + botones fijos ya no entran y el Expanded del scroll
    // se queda sin espacio.
    final screenSize = MediaQuery.of(context).size;
    final fotoHeight = screenSize.height < screenSize.width ? 180.0 : 380.0;

    final c = context.sp;
    const tonosRasgos = [
      SpTone.mint,
      SpTone.peach,
      SpTone.lilac,
      SpTone.sky,
      SpTone.butter,
    ];

    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: SpPawBackground()),
          SafeArea(
            child: Column(
              children: [
                SpScreenHeader(
                  title: nombre,
                  subtitle: [
                    if ((animal['especie'] as String?)?.isNotEmpty == true)
                      animal['especie'] as String,
                    if (ubicacion.isNotEmpty) ubicacion,
                  ].join(' · '),
                ),
                // Carrusel de fotos — FUERA del scroll para que el swipe no
                // compita.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  // Tocar la foto la abre completa, sin recortar y con zoom —
                  // igual que en la tarjeta del feed (el checklist lo
                  // prometía y en el detalle no pasaba nada).
                  child: GestureDetector(
                    onTap: fotos.isEmpty
                        ? null
                        : () => context.push(
                            AppRoutes.visorFoto,
                            extra: (fotos: fotos, indiceInicial: _paginaFoto),
                          ),
                    child: Container(
                      height: fotoHeight,
                      decoration: SpDeco.card(c, radius: SpRadius.xl),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (fotos.isEmpty)
                            SpFotoVacia(
                              especie: animal['especie'] as String?,
                              size: 120,
                            )
                          else
                            PageView.builder(
                              controller: _pageCtrl,
                              itemCount: fotos.length,
                              onPageChanged: (i) =>
                                  setState(() => _paginaFoto = i),
                              // FotoAnimal en vez de recorte — la foto entera
                              // sobre un fondo de sí misma desenfocado (caso
                              // "Tobyiii").
                              itemBuilder: (_, i) => FotoAnimal(
                                url: fotos[i],
                                width: double.infinity,
                                fallback: SpFotoVacia(
                                  especie: animal['especie'] as String?,
                                  size: 120,
                                ),
                              ),
                            ),
                          if (fotos.length > 1)
                            Positioned(
                              bottom: 12,
                              left: 0,
                              right: 0,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(
                                  fotos.length,
                                  (i) => AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                    ),
                                    width: _paginaFoto == i ? 18 : 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: SpDeco.shine.withValues(
                                        alpha: _paginaFoto == i ? 1 : .55,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          // Misma señal que en la tarjeta del feed: sin el
                          // ícono, descubrir que la foto se toca era casualidad.
                          if (fotos.isNotEmpty)
                            Positioned(
                              bottom: 12,
                              right: 12,
                              child: IgnorePointer(
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: SpDeco.soft(
                                    c,
                                    radius: SpRadius.full,
                                  ),
                                  child: Icon(
                                    Icons.zoom_out_map_rounded,
                                    color: c.ink,
                                    size: 17,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (ubicacion.isNotEmpty)
                              _pill(Icons.place_outlined, ubicacion),
                            if (edad.isNotEmpty) _pill(null, edad),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          nombre,
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.5,
                            color: c.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            raza,
                            if (genero.isNotEmpty && genero != 'No sé') genero,
                            if (edad.isNotEmpty) edad,
                          ].join(' · '),
                          style: SpText.label.copyWith(color: c.inkMuted),
                        ),
                        if (tags.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          // Rasgos en pastel, cada uno de un color.
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final (i, t) in tags.indexed)
                                SpPill(
                                  t,
                                  fondo: SpToneColors.of(
                                    c,
                                    tonosRasgos[i % tonosRasgos.length],
                                  ).fill,
                                  tinta: SpToneColors.of(
                                    c,
                                    tonosRasgos[i % tonosRasgos.length],
                                  ).ink,
                                ),
                            ],
                          ),
                        ],
                        // Salud — sugerencia real de un tester: el adoptante
                        // necesita saber esto de antemano porque va a asumir
                        // esos gastos si falta. "Aún no lo sé" se muestra
                        // igual que Sí/No: es información real y honesta.
                        const SizedBox(height: SpSpace.s6),
                        const SpSectionTitle('Salud'),
                        const SizedBox(height: SpSpace.s3),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _pill(
                              Icons.vaccines_outlined,
                              'Vacunado: $vacunado',
                            ),
                            _pill(
                              Icons.medication_outlined,
                              'Desparasitado: $desparasitado',
                            ),
                          ],
                        ),
                        if (descripcion.isNotEmpty) ...[
                          const SizedBox(height: SpSpace.s6),
                          const SpSectionTitle('Mi historia'),
                          const SizedBox(height: SpSpace.s3),
                          SpCard(
                            child: Text(
                              descripcion,
                              style: TextStyle(
                                fontSize: 15,
                                color: c.ink,
                                height: 1.6,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                // Botones de abajo
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    children: [
                      if (enHogar)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Actualmente en hogar de paso',
                            style: SpText.caption.copyWith(
                              color: c.butterInk,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      Row(
                        children: [
                          // Solo el ícono: con el texto "Mensaje" al lado de
                          // "Solicitar adopción" no entraban los dos y se
                          // cortaba ("Mensa…").
                          Tooltip(
                            message: 'Mensaje',
                            child: SpPressable(
                              onTap: () => context.push(
                                AppRoutes.chat,
                                extra: (
                                  animal: animal,
                                  esRescatista: false,
                                  chatId: null,
                                ),
                              ),
                              child: Container(
                                width: 56,
                                height: 48,
                                decoration: SpDeco.soft(c, radius: SpRadius.md),
                                child: Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  color: c.ink,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SpButton(
                              label: puedeAdoptarse
                                  ? 'Solicitar adopción'
                                  : estadoAdopcion == 'Fallecido'
                                  ? 'Ya no está con nosotros'
                                  : 'Ya no está disponible',
                              icon: Icons.favorite_rounded,
                              onTap: puedeAdoptarse
                                  ? () => context.push(
                                      AppRoutes.solicitudAdopcion,
                                      extra: animal,
                                    )
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(IconData? icon, String text) {
    final c = context.sp;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: SpDeco.soft(c, radius: SpRadius.full),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: c.primary),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}
