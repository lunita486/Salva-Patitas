// Piezas visuales de una solicitud, compartidas por la lista completa
// (solicitudes_rescatista_screen.dart) y la vista previa del panel
// (solicitudes_preview.dart). Antes cada archivo dibujaba su propia copia
// de las píldoras, el bloque de compatibilidad y las fechas del hogar de
// paso. Solo dibujan: los datos y los cálculos llegan de afuera.
import 'package:flutter/material.dart';

import '../domain/compatibilidad.dart';
import '../theme/salva_patitas_theme.dart';
import 'sp_widgets.dart';

/// "Adopción" (mantequilla) u "Hogar de paso" (cielo).
class SolicitudTipoPill extends StatelessWidget {
  const SolicitudTipoPill({super.key, required this.esHogar});
  final bool esHogar;

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    return esHogar
        ? SpPill(
            'Hogar de paso',
            fondo: c.sky,
            tinta: c.skyInk,
            icon: Icons.night_shelter_outlined,
          )
        : SpPill(
            'Adopción',
            fondo: c.butter,
            tinta: c.butterInk,
            icon: Icons.home_outlined,
          );
  }
}

/// Pendiente (durazno), Aprobada (menta) o Rechazada (rojo suave).
class SolicitudEstadoPill extends StatelessWidget {
  const SolicitudEstadoPill({super.key, required this.estado});
  final String estado;

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    return switch (estado) {
      'aprobada' => SpPill(
        'Aprobada',
        fondo: c.primarySoft,
        tinta: c.primaryStrong,
        icon: Icons.check_rounded,
      ),
      'rechazada' => SpPill(
        'Rechazada',
        fondo: c.dangerSoft,
        tinta: c.danger,
        icon: Icons.close_rounded,
      ),
      _ => SpPill(
        'Pendiente',
        fondo: c.peach,
        tinta: c.peachInk,
        icon: Icons.hourglass_empty_rounded,
      ),
    };
  }
}

/// Fechas pedidas para un hogar de paso, con la cantidad de días.
class SolicitudFechasHogar extends StatelessWidget {
  const SolicitudFechasHogar({
    super.key,
    required this.inicio,
    required this.fin,
    required this.dias,
  });
  final DateTime inicio;
  final DateTime fin;
  final int? dias;

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    return SpNotice(
      fondo: c.sky,
      tinta: c.skyInk,
      child: Row(
        children: [
          const Icon(Icons.calendar_today_rounded),
          const SizedBox(width: 8),
          Text(
            '${inicio.day}/${inicio.month}/${inicio.year} → ${fin.day}/${fin.month}/${fin.year}',
          ),
          const Spacer(),
          Text(
            '$dias días',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// Compatibilidad del adoptante con el animal (`.compat` del prototipo):
/// barra con el porcentaje, el veredicto y la lista de puntos.
class SolicitudCompatibilidad extends StatelessWidget {
  const SolicitudCompatibilidad({super.key, required this.solicitud});
  final Map<String, dynamic> solicitud;

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    final score = calcularCompatibilidad(solicitud);
    // Mismos tres cortes de siempre (80 / 60).
    final (tinta, titulo) = score >= 80
        ? (c.primaryStrong, 'Perfil ideal')
        : score >= 60
        ? (c.accentInk, 'Perfil aceptable')
        : (c.danger, 'No recomendado');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: tinta,
                  ),
                ),
              ),
              Text(
                '$score%',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: tinta,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Barra hundida (`.meter`).
          Container(
            height: 10,
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(SpRadius.full),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: (score / 100).clamp(.04, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: tinta,
                  borderRadius: BorderRadius.circular(SpRadius.full),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...explicarCompatibilidad(solicitud).map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: r.$2 ? c.primarySoft : c.dangerSoft,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: r.$2 ? c.mintDeep : c.edge,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      r.$2 ? Icons.check_rounded : Icons.close_rounded,
                      size: 14,
                      color: r.$2 ? c.primaryStrong : c.danger,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      r.$1,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Inicial del adoptante en un círculo pastel (`.initial`). Alterna tonos
/// entre filas, como antes alternaba verde y naranja.
(Color, Color) colorInicialAdoptante(SpColors c, int i) =>
    i.isEven ? (c.lilac, c.lilacInk) : (c.peach, c.peachInk);
