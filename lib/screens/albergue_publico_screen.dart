import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../widgets/campos_perfil.dart';
import '../domain/reglas_negocio.dart';
import '../routing/app_router.dart';
import '../widgets/avatares.dart';
import '../widgets/estado_error_feed.dart';
import '../widgets/fotos.dart';
import '../data/creator_role.dart';
import '../data/rescates_repository.dart';

class AlberguePublicoScreen extends StatefulWidget {
  final String rescatistaId;
  const AlberguePublicoScreen({super.key, required this.rescatistaId});

  @override
  State<AlberguePublicoScreen> createState() => _AlberguePublicoScreenState();
}

class _AlberguePublicoScreenState extends State<AlberguePublicoScreen> {
  // `late final`, no streams armados dentro de build(): están ANIDADOS (el
  // perfil del albergue por fuera, sus animales por dentro), así que inline
  // cada cambio en el doc del albergue desuscribía y reiniciaba el de los
  // animales — la grilla volvía al spinner y se repintaba sola. Mismo patrón
  // que la lista de chats y el perfil del aliado. Hallazgo de auditoría.
  late final Stream<DocumentSnapshot> _perfilStream = FirebaseFirestore.instance
      .collection('usuarios')
      .doc(widget.rescatistaId)
      .snapshots();
  // Una página y un contador, no la colección. Este perfil es público: lo
  // puede abrir cualquiera, sobre un albergue de cualquier tamaño. Antes
  // descargaba TODOS los animales del albergue para mostrar los primeros y
  // un número; con un refugio grande eso es megabytes por visita.
  //
  // sePuedeAdoptar (domain/reglas_negocio.dart) sigue siendo la única fuente
  // de qué animal está disponible; acá se traduce a la consulta con
  // estadosDisponibles, que es la misma lista.
  late final Future<PaginaDeRescates> _disponibles = RescatesRepository()
      .paginaDeMisRescates(
        uid: widget.rescatistaId,
        role: CreatorRole.albergue,
        estados: estadosDisponibles,
        porPagina: 30,
      );
  /// El TOTAL de disponibles, no los de la página.
  ///
  /// Antes este número salía de `disponibles.length`, o sea de contar los
  /// documentos de UNA página, que pide 30. Un albergue con 55 disponibles
  /// mostraba "30", y no por lentitud: estaba mal. Lo introduje al paginar
  /// esta pantalla. Hallazgo de Eliza, que comprobó un albergue con 55.
  ///
  /// Mismo mecanismo que [_totalAdoptados], y con la MISMA lista de estados
  /// (`estadosDisponibles`) que alimenta la página de abajo, para que el
  /// número y la lista no puedan contradecirse.
  ///
  /// De paso llega mucho antes: `contar()` es una agregación del servidor y
  /// no baja ningún documento, mientras que la página baja hasta 31.
  late final Future<int> _totalDisponibles = RescatesRepository().contar(
    uid: widget.rescatistaId,
    role: CreatorRole.albergue,
    estados: estadosDisponibles,
  );
  late final Future<int> _totalAdoptados = RescatesRepository().contar(
    uid: widget.rescatistaId,
    role: CreatorRole.albergue,
    estados: const ['Adoptado'],
  );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _perfilStream,
      builder: (context, userSnap) {
        final data = userSnap.data?.data() as Map<String, dynamic>? ?? {};
        final nombre =
            data['albergueNombre'] as String? ??
            data['displayName'] as String? ??
            'Albergue';
        final tipo = data['albergueTipo'] as String? ?? '';
        final capacidad = (data['capacidadTotal'] as int?) ?? 0;
        final ciudad = data['ciudad'] as String? ?? '';
        final telefono = data['albergueTelefono'] as String? ?? '';
        final direccion = data['albergueDireccion'] as String? ?? '';
        final email = data['albergueEmail'] as String? ?? '';
        final sitioWeb = data['albergueSitioWeb'] as String? ?? '';
        final foto64 = data['fotoBase64'] as String?;
        final iniciales = nombre
            .trim()
            .split(' ')
            .take(2)
            .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
            .join();

        return FutureBuilder<PaginaDeRescates>(
          // Pasa por RescatesRepository (no una consulta armada a mano acá)
          // por la misma regla que el resto de la app: sin CreatorRole
          // obligatorio es fácil olvidarse el filtro por sub-rol y mezclar
          // los animales que esta cuenta publicó como rescatista con los
          // que publicó como albergue — ver ARCHITECTURE.md. El filtro
          // local de `creadoPor == 'albergue'` que había acá hacía lo mismo
          // a mano; ahora lo hace el repositorio, así el hook de pre-commit
          // cubre esta pantalla también.
          future: _disponibles,
          builder: (context, rSnap) {
            // Sin esto, un error real se veía igual que "este albergue no
            // tiene animales publicados".
            if (rSnap.hasError) return errorFeedState();
            // Mientras la consulta no volvió, esta lista está vacía porque
            // NO SE SABE, no porque el albergue no tenga animales. Sin
            // distinguir las dos cosas, la pantalla mostraba "0
            // disponibles" y "No hay animales disponibles por ahora" como
            // si fueran datos ciertos, y recién después aparecía el número
            // real. Hallazgo de Eliza: "el 0 inicial es especialmente
            // molesto porque no significa que haya 0 animales".
            final cargando = !rSnap.hasData;
            final disponibles = [...?rSnap.data?.docs];

            return Scaffold(
              backgroundColor: appBg,
              body: CustomScrollView(
                slivers: [
                  // ── Header ──────────────────────────────────────────────────
                  // Un solo Container con la decoración, que envuelve
                  // directo al contenido — NO un Stack con un fondo de
                  // alto FIJO (230) por debajo de un SafeArea/Column con
                  // alto libre, como estaba antes. Con alto fijo, un
                  // nombre de albergue largo (el campo permite hasta 50
                  // caracteres) envolvía a 2 o 3 líneas y el Column
                  // terminaba midiendo más que esos 230 — el verde de
                  // fondo se cortaba ahí, pero el texto seguía
                  // dibujándose más abajo, superpuesto con la sección
                  // blanca de estadísticas que arranca después en el
                  // CustomScrollView. Así SÍ se ajusta solo al contenido
                  // real, sin importar cuántas líneas ocupe el nombre —
                  // mismo patrón que ya usaba bien aliado_publico_screen.
                  // dart, que nunca tuvo este problema. Hallazgo real de
                  // Eliza con "Diga mire y vea.. venga axa por su mascota
                  // y sea f...".
                  SliverToBoxAdapter(
                    child: Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF0A5C40), appTeal],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: SafeArea(
                        bottom: false,
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 4, top: 4),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.arrow_back_ios_new,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  tooltip: 'Volver',
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  width: 3,
                                ),
                              ),
                              child: AvatarPersona(
                                fotoBase64: foto64,
                                inicial: iniciales,
                                radius: 42,
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.2,
                                ),
                                textColor: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              child: Text(
                                nombre,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            if (tipo.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                tipo,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white.withValues(alpha: 0.78),
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ── Stats ────────────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                      child: Row(
                        children: [
                          FutureBuilder<int>(
                            future: _totalDisponibles,
                            builder: (_, s) => _statChip(
                              s.hasData ? '${s.data}' : _cargandoValor,
                              'disponibles',
                              appTeal,
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Un contador del lado del servidor: antes salía
                          // de filtrar en Dart todos los animales del
                          // albergue.
                          FutureBuilder<int>(
                            future: _totalAdoptados,
                            builder: (_, s) => _statChip(
                              s.hasData ? '${s.data}' : _cargandoValor,
                              'adoptados',
                              const Color(0xFF2196F3),
                            ),
                          ),
                          if (capacidad > 0) ...[
                            const SizedBox(width: 10),
                            _statChip(
                              '$capacidad',
                              'capacidad',
                              Colors.grey.shade700,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // ── Contacto (opcional) ─────────────────────────────────────
                  if (ciudad.isNotEmpty ||
                      telefono.isNotEmpty ||
                      direccion.isNotEmpty ||
                      email.isNotEmpty ||
                      sitioWeb.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // La ciudad se geocodifica al guardar el perfil,
                            // pero esta pantalla nunca la mostraba — mismo
                            // hallazgo real de Eliza que en el perfil
                            // público del Aliado (aliado_publico_screen.
                            // dart), arreglado igual acá.
                            if (ciudad.isNotEmpty)
                              filaContacto(
                                Icons.location_city_outlined,
                                ciudad,
                              ),
                            if (direccion.isNotEmpty)
                              filaContacto(
                                Icons.location_on_outlined,
                                direccion,
                              ),
                            if (email.isNotEmpty)
                              filaContacto(
                                Icons.email_outlined,
                                email,
                                onTap: () =>
                                    launchUrl(Uri.parse('mailto:$email')),
                              ),
                            if (sitioWeb.isNotEmpty)
                              filaContacto(
                                Icons.language_outlined,
                                sitioWeb,
                                onTap: () => launchUrl(
                                  Uri.parse(sitioWebUrl(sitioWeb)),
                                  mode: LaunchMode.externalApplication,
                                ),
                              ),
                            if (telefono.isNotEmpty)
                              Padding(
                                padding: EdgeInsets.only(
                                  top:
                                      (ciudad.isNotEmpty ||
                                          direccion.isNotEmpty ||
                                          email.isNotEmpty ||
                                          sitioWeb.isNotEmpty)
                                      ? 4
                                      : 0,
                                ),
                                child: GestureDetector(
                                  onTap: () {
                                    final url = whatsappUrl(telefono);
                                    if (url != null) {
                                      launchUrl(
                                        Uri.parse(url),
                                        mode: LaunchMode.externalApplication,
                                      );
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF25D366,
                                      ).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: const Color(
                                          0xFF25D366,
                                        ).withValues(alpha: 0.35),
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.chat_bubble_outline,
                                          size: 15,
                                          color: Color(0xFF1E9E56),
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          'Escribir por WhatsApp',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF1E9E56),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                  // ── Sección ──────────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
                      child: Text(
                        'Animales disponibles',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: appInk,
                        ),
                      ),
                    ),
                  ),

                  // ── Grid ─────────────────────────────────────────────────────
                  // Mismo motivo que el contador: mientras carga no se
                  // afirma que no hay animales, porque todavía no se sabe.
                  if (cargando)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(48),
                        child: Center(
                          child: CircularProgressIndicator(color: appTeal),
                        ),
                      ),
                    )
                  else if (disponibles.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(48),
                        child: Center(
                          child: Text(
                            'No hay animales disponibles por ahora.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      sliver: SliverGrid(
                        // MaxCrossAxisExtent en vez de FixedCrossAxisCount(2):
                        // mismo motivo que aliados_screen.dart — con conteo
                        // fijo, en horizontal cada columna se estiraba mucho
                        // más allá de su ancho de vertical, dejando la
                        // tarjeta con su contenido centrado y mucho espacio
                        // en blanco arriba y abajo.
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 180,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.78,
                            ),
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) => _animalCard(
                            ctx,
                            disponibles[i].data(),
                            disponibles[i].id,
                          ),
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

  /// Una línea de contacto (dirección/email/sitio web): ícono + texto,
  /// tappable si se pasa [onTap] (email abre el cliente de correo, sitio
  /// web abre el navegador — dirección no tiene onTap, es solo texto).

  /// Lo que se muestra en un contador mientras el dato todavía no llegó.
  /// Un guion largo y no un "0": un cero se lee como un dato cierto.
  static const _cargandoValor = '—';

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
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            valor,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _animalCard(BuildContext ctx, Map<String, dynamic> d, String docId) {
    final nombre = nombreDeAnimal(d['nombre'] as String?);
    final especie = d['especie'] as String? ?? 'Perro';
    final edad = d['edad'] as String? ?? '';
    final fotoUrl = d['fotoUrl'] as String?;
    final urgencia = d['urgencia'] as String? ?? '';
    final estadoAdopcion = d['estadoAdopcion'] as String? ?? 'Rescatado';
    final emoji = especie == 'Gato' ? '🐱' : '🐶';
    final estadoColor = cicloColor(estadoAdopcion);

    final animalMap = {
      'nombre': nombre,
      'especie': especie,
      'edad': edad,
      'raza': d['raza'] ?? 'Criolla',
      'tamano': d['tamano'] ?? 'Mediano',
      'ubicacion': d['ubicacion'] ?? '',
      'descripcion': d['descripcion'] ?? '',
      'tags': <String>[
        if (d['okConNinos'] == true) 'Amigable con niños',
        if (d['okConMascotas'] == true) 'Es sociable',
        if ((d['energia'] as String?)?.isNotEmpty == true)
          d['energia'] as String,
      ],
      'rescatista': d['rescatistaNombre'] ?? '',
      'rescatistaId': d['rescatistaId'] ?? '',
      'rescateId': docId,
      'estadoAdopcion': estadoAdopcion,
      'fotoUrl': fotoUrl,
      'fotoUrl2': d['fotoUrl2'],
      'latitud': d['latitud'],
      'longitud': d['longitud'],
      'energia': d['energia'],
      'okConNinos': d['okConNinos'],
      'okConMascotas': d['okConMascotas'],
      'requiereExperiencia': d['requiereExperiencia'],
      'vacunado': d['vacunado'],
      'desparasitado': d['desparasitado'],
      'urgencia': urgencia,
      'creadoPor': d['creadoPor'] ?? 'albergue',
    };

    return GestureDetector(
      onTap: () => ctx.push(AppRoutes.animalDetalle, extra: animalMap),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  // FotoAnimal en vez de recorte — mismo caso "Tobyiii": esta
                  // tarjeta del perfil público del albergue es grande y el
                  // recorte fijo podía dejar afuera al animal entero en fotos
                  // verticales (ver solicitud_adopcion_screen.dart).
                  child: fotoUrl != null
                      ? FotoAnimal(
                          url: fotoUrl,
                          width: double.infinity,
                          fallback: Container(
                            width: double.infinity,
                            color: const Color(0xFFD8F0E4),
                            child: Center(
                              child: Text(
                                emoji,
                                style: const TextStyle(fontSize: 40),
                              ),
                            ),
                          ),
                        )
                      : Container(
                          width: double.infinity,
                          color: const Color(0xFFD8F0E4),
                          child: Center(
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 40),
                            ),
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: appInk,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [especie, if (edad.isNotEmpty) edad].join(' · '),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: estadoColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: estadoColor.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          estadoAdopcion,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: estadoColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (urgencia == 'Alta')
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD32F2F),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'URGENTE',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
