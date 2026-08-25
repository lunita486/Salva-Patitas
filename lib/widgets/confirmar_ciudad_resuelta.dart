import 'package:flutter/material.dart';

import 'campo_pais_telefono.dart';
import '../theme.dart';
import '../services/ubicacion_service.dart'
    show CandidatoUbicacion, UbicacionService;

/// Resuelve un texto de ciudad escrito a mano a un lugar real y confirmado,
/// listo para guardar. Devuelve `null` cuando NO hay que guardar ubicación
/// nueva — y en ese caso ya se le explicó a la persona por qué (o fue ella
/// quien canceló), así que el llamador solo tiene que abortar su guardado.
///
/// **Existe porque las 4 pantallas que piden una ciudad tenían esta misma
/// secuencia copiada a mano, y ya habían divergido.** Publicar un animal,
/// editar un animal, el perfil del albergue y el perfil del aliado hacían
/// los mismos 4 pasos (geocodificar → distinguir "no existe" de "no hay
/// señal" → confirmar cuál de los candidatos es → aplicar los datos), pero:
///
/// - el perfil del **aliado** trataba un error de red con un `catch` vacío
///   que dejaba seguir, o sea que un tropiezo de señal guardaba el texto
///   crudo tal cual ("cordoba verduras") como si fuera una ciudad válida —
///   exactamente el agujero que las otras 3 pantallas ya tenían tapado. Su
///   propio comentario decía "mismo criterio que albergue_perfil_screen",
///   que era falso: albergue bloquea.
/// - los mensajes de error estaban escritos con palabras distintas en cada
///   pantalla para la misma situación.
///
/// Es el mismo problema, y la misma solución, que `UbicacionService` para
/// el GPS: mientras esta secuencia viva copiada N veces, arreglar una copia
/// deja las otras rotas esperando a que alguien las encuentre probando.
/// Pedido explícito de Eliza: "fijate que el albergue y el aliado tomen
/// exactamente la misma lógica que el ingreso de la ubicación de un
/// animalito".
///
/// Lo único que sigue siendo decisión de cada pantalla es CUÁNDO llamar a
/// esto (el animal, si se tocó el campo a mano; los perfiles, si el texto
/// cambió) y QUÉ campos persistir del resultado — el perfil del aliado, por
/// ejemplo, no guarda coordenadas porque nada calcula distancia a un
/// negocio.
Future<CandidatoUbicacion?> resolverCiudadEscrita(
  BuildContext context,
  String texto,
) async {
  List<CandidatoUbicacion>? candidatos;
  String? error;
  try {
    // null y excepción significan cosas distintas (ver desdeTexto): lo
    // primero es "eso no existe como lugar" y bloquea con un mensaje
    // puntual; lo segundo es "no se pudo verificar", que bloquea con otro
    // texto para no confundir un problema de señal con un dato inventado.
    candidatos = await UbicacionService.desdeTexto(texto);
    if (candidatos == null) {
      error = 'No encontramos "$texto" como ciudad. Revisá cómo la escribiste.';
    }
  } catch (_) {
    error =
        'No pudimos verificar esa ciudad. Revisá tu conexión e intentá de nuevo.';
  }
  if (!context.mounted) return null;
  if (error != null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error), backgroundColor: msgError));
    return null;
  }
  // Un texto mal escrito puede coincidir con OTRO lugar real del mundo (no
  // da null) — hallazgo real de Eliza escribiendo "Nedellin" y quedando
  // guardado a 9077km de Medellín. Acá se le muestra qué se encontró para
  // que elija ella.
  return confirmarCiudadResuelta(
    context,
    escribiste: texto,
    candidatos: candidatos!,
  );
}

// ─── Confirmar ciudad resuelta ─────────────────────────────────────────────
// Existe porque un texto mal escrito ("Nedellin") no siempre da `null` en
// UbicacionService.desdeTexto() — puede coincidir con OTRO lugar real en
// cualquier parte del mundo, y el servicio contesta con total confianza.
// No hay forma de detectar eso solo con código (no existe una lista de
// "todas las ciudades del mundo, bien escritas" contra la cual comparar);
// lo único realista es mostrarle a la persona QUÉ se resolvió antes de
// guardar, para que sea ELLA quien note el error, como con cualquier
// buscador de direcciones. Compartido entre los 4 lugares que llaman
// `desdeTexto()` al guardar.
//
// **EL INVARIANTE QUE ESTE ARCHIVO HACE CUMPLIR, Y POR QUÉ.** Lo que se
// guarda en `ubicacion` es SIEMPRE un nombre que devolvió el
// geocodificador, nunca el texto que la persona escribió; y `paisCodigo` +
// coordenadas salen SIEMPRE del MISMO candidato que ese nombre. Los tres
// datos describen un solo lugar o no se guarda ninguno.
//
// Esto existe porque romper ese invariante rompió la app de verdad. Una
// versión anterior de este diálogo tenía una opción "usar el texto tal
// cual la escribí" (para cuando ningún candidato parecía el correcto), y
// guardaba el texto crudo como nombre PERO las coordenadas y el país del
// primer candidato de la lista. Resultado real, encontrado por Eliza en el
// APK61: escribió "cordoba verduras", eligió "tal cual", y en el feed
// quedó "cordoba verduras 🇪🇸" — con la bandera de España, que nunca
// eligió, porque venía del primer candidato (Córdoba, Andalucía) mientras
// el nombre venía de lo que ella tecleó. Tres campos describiendo tres
// cosas distintas. En el mismo APK, "medellin antioquia" guardado "tal
// cual" se veía así de largo en la tarjeta, en vez de "Medellín 🇨🇴" — el
// feed muestra ciudad + bandera, la provincia escrita a mano sobraba.
//
// La distinción que faltaba: **lo que se teclea es una BÚSQUEDA, no el
// dato**. Escribir "medellin antioquia" para desambiguar está perfecto y
// hay que fomentarlo — mientras lo que se guarde sea el "Medellín" que el
// buscador resolvió, no la frase completa. Es exactamente cómo funciona
// cualquier buscador de direcciones: escribís lo que sea, elegís de la
// lista, y se guarda lo que elegiste.
//
// Por eso NO hay forma de guardar texto libre acá. Si ningún candidato es
// el correcto, el camino es "No, corregir" y buscar de otra manera — eso
// no puede ensuciar los datos. Y si no se puede describir ningún candidato
// (el reverse geocoding se cayó), este diálogo lo dice y no deja guardar,
// en vez de dejar pasar el texto crudo en silencio: ese silencio era un
// segundo agujero por el que entraba lo mismo, incluso sin la opción de
// texto libre.
//
// Devuelve el candidato elegido, o `null` si no hay que guardar nada
// (canceló, o no se pudo verificar — en ese caso este diálogo ya explicó
// por qué, el llamador solo tiene que abortar el guardado).
Future<CandidatoUbicacion?> confirmarCiudadResuelta(
  BuildContext context, {
  required String escribiste,
  required List<CandidatoUbicacion> candidatos,
}) async {
  // Un candidato sin nombre resuelto no se puede mostrar para elegir (no
  // hay qué leer) ni guardar (rompería el invariante de arriba).
  final elegibles = candidatos
      .where((c) => c.ciudadResuelta.isNotEmpty)
      .toList();

  if (elegibles.isEmpty) {
    // Las coordenadas SÍ se resolvieron (por eso hay candidatos), pero sin
    // un nombre que mostrar no hay forma de que la persona confirme que es
    // el lugar correcto — y guardar el texto crudo con esas coordenadas es
    // justamente el bug de "cordoba verduras 🇪🇸". Se avisa y no se guarda.
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('No pudimos verificar esa ciudad'),
        content: const Text(
          'Encontramos el lugar pero no pudimos confirmar su nombre. '
          'Revisá tu conexión e intentá de nuevo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
    return null;
  }

  return showDialog<CandidatoUbicacion>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        elegibles.length > 1 ? '¿Cuál es tu ciudad?' : '¿Es esta tu ciudad?',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Escribiste "$escribiste" y encontramos:'),
            const SizedBox(height: 8),
            for (final candidato in elegibles)
              _OpcionCiudad(
                candidato: candidato,
                onTap: () => Navigator.pop(ctx, candidato),
              ),
            const SizedBox(height: 12),
            // Sin opción de texto libre a propósito (ver el comentario de
            // arriba): si ninguna es la correcta, se busca de otra forma.
            // La pista es CONCRETA (con ejemplo) y no un genérico "probá de
            // otra manera": el caso real que la motiva es que el
            // geocodificador, ante "cordoba" a secas, puede devolver sus 5
            // resultados todos en España — y ahí no hay ninguna opción
            // argentina que elegir por más que se toque la lista. Lo único
            // que destraba eso es agregarle el país a la BÚSQUEDA, y hay
            // que decirlo con todas las letras. Hallazgo real de Eliza:
            // "si escribo cordoba toma por defecto españa".
            Text(
              'Si ninguna es tu ciudad, tocá "No, corregir" y agregale el '
              'país o la provincia (por ejemplo "Córdoba, Argentina"). Se '
              'guarda solo el nombre de la ciudad.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text(
            'No, corregir',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      ],
    ),
  );
}

class _OpcionCiudad extends StatelessWidget {
  final CandidatoUbicacion candidato;
  final VoidCallback onTap;
  const _OpcionCiudad({required this.candidato, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bandera = banderaPais(candidato.paisCodigo);
    // La provincia/estado, cuando se conoce, es lo que distingue dos
    // ciudades con el MISMO nombre en el MISMO país ("San José" se repite
    // en decenas de departamentos) — sin esto, dos lugares homónimos pero
    // distintos se verían exactamente igual en esta lista. Se muestra SOLO
    // acá, para elegir: lo que se guarda es la ciudad sola.
    final nombreCompleto = candidato.regionResuelta.isNotEmpty
        ? '${candidato.ciudadResuelta}, ${candidato.regionResuelta}'
        : candidato.ciudadResuelta;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$nombreCompleto${bandera.isNotEmpty ? ' $bandera' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}
