import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../domain/reglas_negocio.dart';
import '../routing/app_router.dart';
import '../theme/salva_patitas_theme.dart';
import 'sp_widgets.dart';

/// El panel de "¿cómo querés ayudar a X?" del feed del adoptante.
///
/// Vivía adentro de adoptante_feed_screen.dart, que pasa las 2000 líneas.
/// Se movió acá (movido, no copiado) por un motivo concreto: era privado, y
/// por eso ninguna prueba podía mirarlo. Justamente este panel ofrecía dos
/// de las tres formas de ayudar y le faltaba Adoptar, y eso solo se
/// descubrió usando la app a mano. Ahora hay un test que lo revisa solo.

class MeInteresaSheet extends StatelessWidget {
  final String nombre,
      especie,
      edad,
      ubicacion,
      rescatistaId,
      rescatista,
      rescateId,
      estadoAdopcion,
      creadoPor,
      tamano;
  final List<String> tags;
  final String? fotoUrl;
  final String? energia;
  final bool? okConNinos, okConMascotas, requiereExperiencia;

  const MeInteresaSheet({
    required this.nombre,
    required this.especie,
    required this.edad,
    required this.ubicacion,
    required this.rescatistaId,
    required this.rescatista,
    required this.rescateId,
    required this.tags,
    required this.estadoAdopcion,
    required this.creadoPor,
    required this.tamano,
    this.fotoUrl,
    this.energia,
    this.okConNinos,
    this.okConMascotas,
    this.requiereExperiencia,
  });

  /// Abre la pantalla de solicitud con [tipo] ('adopcion' u
  /// 'hogar_de_paso').
  ///
  /// Los dos caminos mandan EXACTAMENTE los mismos datos del animal: es un
  /// solo mapa y no uno por opción, para que no puedan volver a divergir.
  /// Ya pasó una vez con las etiquetas de compatibilidad —faltaban acá, y
  /// entonces compatibilidad.dart las completaba con sus valores por
  /// defecto: el puntaje salía calculado contra un animal "Mediano" aunque
  /// el de verdad fuera "Pequeño"— y no se notaba, porque un puntaje
  /// equivocado se ve igual de convincente que uno correcto.
  void _pedir(BuildContext context, String tipo) {
    Navigator.pop(context);
    context.push(
      AppRoutes.solicitudAdopcion,
      extra: {
        'nombre': nombre,
        'especie': especie,
        'edad': edad,
        'ubicacion': ubicacion,
        'rescatista': rescatista,
        'rescatistaId': rescatistaId,
        'rescateId': rescateId,
        'fotoUrl': fotoUrl,
        'tipoSolicitud': tipo,
        'creadoPor': creadoPor,
        'tamano': tamano,
        'energia': energia,
        'okConNinos': okConNinos,
        'okConMascotas': okConMascotas,
        'requiereExperiencia': requiereExperiencia,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      // SingleChildScrollView a propósito: mismo motivo que
      // perfil_rescatista_screen.dart/perfil_adoptante_screen.dart — en
      // horizontal, en un teléfono real (menos alto disponible que el
      // emulador con el que lo había probado), este Column no entraba
      // entero y "Hacer una pregunta" quedaba cortado. Hallazgo de prueba
      // en teléfono real, 2026-08-03.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SpAgarradera(),
            const SizedBox(height: 14),
            SpHojaTitulo(
              '¿Cómo querés ayudar a ${nombreDeAnimal(nombre, enFrase: true)}?',
              centrado: true,
            ),
            const SizedBox(height: 20),
            // Adoptar va PRIMERO y por eso existe: este panel pregunta
            // "¿cómo querés ayudar?" y hasta ahora ofrecía dos de las tres
            // formas, justo sin la principal. Para adoptar desde el feed
            // había que entrar por "Ser hogar de paso" y recién en la
            // pantalla siguiente cambiar el botón a "Adoptar", o salir del
            // panel e ir por la ficha. Quien tocaba "Me interesa ayudar"
            // con ganas de adoptar no encontraba la palabra en ningún lado.
            //
            // sePuedeAdoptar() decide si mostrarlo, la misma función que ya
            // usan el feed, la ficha, favoritos, el perfil público del
            // albergue y el repositorio al aprobar. No hay una lista de
            // estados nueva acá: un animalito en "Hogar de paso" SÍ se
            // puede adoptar (por eso la opción de abajo se esconde y esta
            // no), y ese matiz vive en un solo lugar a propósito.
            if (sePuedeAdoptar(estadoAdopcion)) ...[
              _opcion(
                context,
                icono: Icons.home_rounded,
                tono: SpTone.butter,
                titulo: 'Adoptar',
                subtitulo: 'Querés que sea parte de tu familia para siempre',
                onTap: () => _pedir(context, 'adopcion'),
              ),
              const SizedBox(height: 10),
            ],
            // sePuedeSerHogarDePaso(), no una comparación a mano: está
            // definida sobre sePuedeAdoptar() para que las dos opciones de
            // arriba no puedan contradecirse entre sí.
            if (sePuedeSerHogarDePaso(estadoAdopcion)) ...[
              _opcion(
                context,
                icono: Icons.night_shelter_outlined,
                tono: SpTone.sky,
                titulo: 'Ser hogar de paso',
                subtitulo:
                    'Lo/la cuidás temporalmente mientras encuentra familia',
                onTap: () => _pedir(context, 'hogar_de_paso'),
              ),
              const SizedBox(height: 10),
            ],
            _opcion(
              context,
              icono: Icons.chat_bubble_outline_rounded,
              tono: SpTone.lilac,
              titulo: 'Hacer una pregunta',
              subtitulo: 'Escribile directamente al rescatista',
              onTap: () {
                Navigator.pop(context);
                // Abre el chat vacío (sin mensaje enlatado) para que el adoptante
                // escriba su propia pregunta. ChatScreen ya sabe crear/encontrar
                // el chat solo, usando el mismo id determinístico (rescateId+uid)
                // que el resto de la app — así este chat es uno más normal y
                // aparece en la bandeja del rescatista como cualquier otro.
                context.push(
                  AppRoutes.chat,
                  extra: (
                    esRescatista: false,
                    chatId: null,
                    animal: {
                      'nombre': nombre,
                      'rescatista': rescatista,
                      'rescatistaId': rescatistaId,
                      'fotoUrl': fotoUrl,
                      'rescateId': rescateId,
                      'especie': especie,
                      'ubicacion': ubicacion,
                      'descripcion': '',
                      'tags': tags,
                      'edad': edad,
                      'creadoPor': creadoPor,
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _opcion(
    BuildContext context, {
    required IconData icono,
    required SpTone tono,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
  }) {
    final c = context.sp;
    final k = SpToneColors.of(c, tono);
    return SpPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: SpDeco.soft(c, radius: 18),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: k.fill,
                borderRadius: BorderRadius.circular(SpRadius.sm),
              ),
              child: Icon(icono, size: 21, color: k.ink),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitulo,
                    style: TextStyle(fontSize: 12.5, color: c.inkMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.inkFaint),
          ],
        ),
      ),
    );
  }
}
