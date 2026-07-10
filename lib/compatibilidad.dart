/// Puntaje y explicación de compatibilidad entre un adoptante y un animal,
/// usados por el feed de adopción, el panel del rescatista y la pantalla de
/// solicitudes. Antes esta lógica estaba copiada en esos 3 lugares.
int calcularCompatibilidad(Map<String, dynamic> solicitud) {
  int score = 0;

  final energia    = solicitud['animalEnergia']  as String? ?? 'Tranquilo';
  final horas      = int.tryParse(solicitud['horasFuera']?.toString() ?? '0') ?? 0;
  final vivienda   = solicitud['vivienda']       as String? ?? '';
  final tienePatio = vivienda == 'Casa con jardín';

  if (energia == 'Tranquilo') {
    score += 20;
  } else if (energia == 'Activo') {
    score += horas <= 8 ? 20 : 10;
  } else {
    if (tienePatio && horas <= 6) score += 20;
    else if (tienePatio || horas <= 6) score += 10;
  }

  final tamano = solicitud['animalTamano'] as String? ?? 'Mediano';
  if (tamano == 'Pequeño') {
    score += 20;
  } else if (tamano == 'Mediano') {
    score += vivienda != 'Apartamento sin área exterior' ? 20 : 10;
  } else {
    score += tienePatio ? 20 : (vivienda == 'Apartamento con balcón' ? 10 : 0);
  }

  final okNinos    = solicitud['animalOkConNinos']   as bool? ?? true;
  final tieneNinos = solicitud['tieneNinos']         as bool? ?? false;
  score += (!tieneNinos || okNinos) ? 20 : 0;

  final okMascotas    = solicitud['animalOkConMascotas'] as bool? ?? true;
  final tieneMascotas = solicitud['tieneMascotas']       as bool? ?? false;
  score += (!tieneMascotas || okMascotas) ? 20 : 0;

  final requiereExp = solicitud['animalRequiereExp']   as bool? ?? false;
  final tieneExp    = solicitud['experienciaPrevia']   as bool? ?? false;
  score += (!requiereExp || tieneExp) ? 20 : 0;

  return score;
}

List<(String, bool)> explicarCompatibilidad(Map<String, dynamic> sol) {
  final reasons = <(String, bool)>[];

  final energia    = sol['animalEnergia']  as String? ?? 'Tranquilo';
  final horas      = int.tryParse(sol['horasFuera']?.toString() ?? '0') ?? 0;
  final vivienda   = sol['vivienda']       as String? ?? '';
  final tienePatio = vivienda == 'Casa con jardín';
  final tamano     = sol['animalTamano']       as String? ?? 'Mediano';
  final okNinos    = sol['animalOkConNinos']   as bool?   ?? true;
  final tieneNinos = sol['tieneNinos']         as bool?   ?? false;
  final okMascotas    = sol['animalOkConMascotas'] as bool? ?? true;
  final tieneMascotas = sol['tieneMascotas']       as bool? ?? false;
  final requiereExp   = sol['animalRequiereExp']   as bool? ?? false;
  final tieneExp      = sol['experienciaPrevia']   as bool? ?? false;

  // Energía
  if (energia == 'Tranquilo') {
    reasons.add(('Animal tranquilo, se adapta bien al hogar', true));
  } else if (energia == 'Activo') {
    reasons.add(horas <= 8
        ? ('Animal activo, horas fuera son aceptables', true)
        : ('Animal activo pero pasa demasiadas horas solo ($horas h/día)', false));
  } else {
    if (tienePatio && horas <= 6)  reasons.add(('Animal muy activo, tiene jardín y poco tiempo solo', true));
    else if (tienePatio)           reasons.add(('Animal muy activo, tiene jardín pero $horas h solo', false));
    else if (horas <= 6)           reasons.add(('Animal muy activo, necesita jardín', false));
    else                           reasons.add(('Animal muy activo, necesita jardín y menos horas solo', false));
  }

  // Tamaño
  if (tamano == 'Pequeño') {
    reasons.add(('Animal pequeño, se adapta a cualquier espacio', true));
  } else if (tamano == 'Mediano') {
    reasons.add(vivienda != 'Apartamento sin área exterior'
        ? ('Animal mediano, el espacio es adecuado', true)
        : ('Animal mediano en apartamento sin área exterior', false));
  } else {
    if (tienePatio)                              reasons.add(('Animal grande, tiene jardín suficiente', true));
    else if (vivienda == 'Apartamento con balcón') reasons.add(('Animal grande, el espacio es limitado', false));
    else                                          reasons.add(('Animal grande, necesita más espacio', false));
  }

  // Niños
  if (!tieneNinos)      reasons.add(('Sin niños en casa', true));
  else if (okNinos)     reasons.add(('Hay niños y el animal los acepta bien', true));
  else                  reasons.add(('Hay niños pero el animal no es apto con ellos', false));

  // Mascotas
  if (!tieneMascotas)   reasons.add(('Sin otras mascotas en casa', true));
  else if (okMascotas)  reasons.add(('Hay mascotas y el animal convive bien', true));
  else                  reasons.add(('Hay mascotas pero el animal no convive con ellas', false));

  // Experiencia
  if (!requiereExp)     reasons.add(('No se requiere experiencia previa', true));
  else if (tieneExp)    reasons.add(('El animal requiere experiencia, adoptante la tiene', true));
  else                  reasons.add(('El animal requiere experiencia previa', false));

  return reasons;
}
