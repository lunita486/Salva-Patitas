// Puntaje y explicación de compatibilidad entre un adoptante y un animal,
// usados por el feed de adopción, el panel del rescatista y la pantalla de
// solicitudes. Antes esta lógica estaba copiada en esos 3 lugares.

/// Un criterio evaluado: el texto que se muestra, si cuenta como algo
/// bueno (✅ verde) o no (✗ rojo), y cuántos puntos suma al total.
///
/// [calcularCompatibilidad] y [explicarCompatibilidad] ANTES eran dos
/// funciones separadas que recalculaban cada una, por su cuenta, las
/// mismas reglas (energía, tamaño, niños, mascotas, experiencia) — dos
/// copias del mismo razonamiento, escritas dos veces. Ahí fue exactamente
/// donde se desincronizaron: 'Finca' se agregó como "tiene patio" al
/// puntaje pero no a la explicación, y un rescatista podía ver "✅ Perfil
/// ideal (100%)" arriba y "✗ necesita jardín" en rojo debajo, para la
/// misma solicitud (hallazgo de auditoría de código).
///
/// Ahora hay UN solo lugar ([_desglose]) que decide, por cada criterio, el
/// mensaje/color/puntaje juntos, en la misma rama — el puntaje total y la
/// lista de razones son dos vistas distintas del mismo resultado, nunca
/// dos cálculos distintos. Ya no es posible que se cuenten historias
/// distintas: si algún día se agrega otra opción de vivienda o cambia un
/// umbral, hay un solo lugar para tocar.
typedef _Criterio = (String mensaje, bool positivo, int puntos);

List<_Criterio> _desglose(Map<String, dynamic> sol) {
  final energia    = sol['animalEnergia']  as String? ?? 'Tranquilo';
  final horas      = int.tryParse(sol['horasFuera']?.toString() ?? '0') ?? 0;
  final vivienda   = sol['vivienda']       as String? ?? '';
  // 'Finca' cuenta como "tiene patio" — es más espacio todavía que una
  // casa con jardín, nunca menos.
  final tienePatio = vivienda == 'Casa con jardín' || vivienda == 'Finca';
  final tamano     = sol['animalTamano']       as String? ?? 'Mediano';
  final okNinos    = sol['animalOkConNinos']   as bool?   ?? true;
  final tieneNinos = sol['tieneNinos']         as bool?   ?? false;
  final okMascotas    = sol['animalOkConMascotas'] as bool? ?? true;
  final tieneMascotas = sol['tieneMascotas']       as bool? ?? false;
  final requiereExp   = sol['animalRequiereExp']   as bool? ?? false;
  final tieneExp      = sol['experienciaPrevia']   as bool? ?? false;

  final _Criterio energiaC;
  if (energia == 'Tranquilo') {
    energiaC = ('Animal tranquilo, se adapta bien al hogar', true, 20);
  } else if (energia == 'Activo') {
    energiaC = horas <= 8
        ? ('Animal activo, horas fuera son aceptables', true, 20)
        : ('Animal activo pero pasa demasiadas horas solo ($horas h/día)', false, 10);
  } else if (tienePatio && horas <= 6) {
    energiaC = ('Animal muy activo, tiene jardín y poco tiempo solo', true, 20);
  } else if (tienePatio) {
    energiaC = ('Animal muy activo, tiene jardín pero $horas h solo', false, 10);
  } else if (horas <= 6) {
    energiaC = ('Animal muy activo, necesita jardín', false, 10);
  } else {
    energiaC = ('Animal muy activo, necesita jardín y menos horas solo', false, 0);
  }

  final _Criterio tamanoC;
  if (tamano == 'Pequeño') {
    tamanoC = ('Animal pequeño, se adapta a cualquier espacio', true, 20);
  } else if (tamano == 'Mediano') {
    tamanoC = vivienda != 'Apartamento sin área exterior'
        ? ('Animal mediano, el espacio es adecuado', true, 20)
        : ('Animal mediano en apartamento sin área exterior', false, 10);
  } else if (tienePatio) {
    tamanoC = ('Animal grande, tiene jardín suficiente', true, 20);
  } else if (vivienda == 'Apartamento con balcón' || vivienda == 'Casa sin jardín') {
    // 'Casa sin jardín' entra en el mismo escalón que 'Apartamento con
    // balcón' — sin patio propio pero con más margen que uno cerrado.
    tamanoC = ('Animal grande, el espacio es limitado', false, 10);
  } else {
    tamanoC = ('Animal grande, necesita más espacio', false, 0);
  }

  final _Criterio ninosC = !tieneNinos
      ? ('Sin niños en casa', true, 20)
      : okNinos
          ? ('Hay niños y el animal los acepta bien', true, 20)
          : ('Hay niños pero el animal no es apto con ellos', false, 0);

  final _Criterio mascotasC = !tieneMascotas
      ? ('Sin otras mascotas en casa', true, 20)
      : okMascotas
          ? ('Hay mascotas y el animal convive bien', true, 20)
          : ('Hay mascotas pero el animal no convive con ellas', false, 0);

  final _Criterio expC = !requiereExp
      ? ('No se requiere experiencia previa', true, 20)
      : tieneExp
          ? ('El animal requiere experiencia, adoptante la tiene', true, 20)
          : ('El animal requiere experiencia previa', false, 0);

  return [energiaC, tamanoC, ninosC, mascotasC, expC];
}

int calcularCompatibilidad(Map<String, dynamic> solicitud) =>
    _desglose(solicitud).fold(0, (suma, c) => suma + c.$3);

List<(String, bool)> explicarCompatibilidad(Map<String, dynamic> sol) =>
    _desglose(sol).map((c) => (c.$1, c.$2)).toList();
