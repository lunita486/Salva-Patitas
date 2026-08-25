/// Distingue con qué "sombrero" se creó un documento (rescates/solicitudes),
/// no qué puede hacer la cuenta en general (eso es `usuarios.roles`).
///
/// Una misma cuenta puede tener ambos roles de cuenta (rescatista y
/// albergue) a la vez — por eso este valor tiene que venir siempre
/// explícito en las consultas de "mis animales"/"mis solicitudes", nunca
/// inferido solo del uid. Ver ARCHITECTURE.md.
enum CreatorRole { rescatista, albergue }

extension CreatorRoleValue on CreatorRole {
  String get firestoreValue => switch (this) {
    CreatorRole.rescatista => 'rescatista',
    CreatorRole.albergue => 'albergue',
  };
}

/// Los documentos de `solicitudes` creados antes de que este campo
/// existiera no tienen `creadoPor` — se tratan como 'rescatista' porque
/// esa era la única variante posible en ese momento.
CreatorRole creatorRoleFromFirestore(String? value) => switch (value) {
  'albergue' => CreatorRole.albergue,
  _ => CreatorRole.rescatista,
};

/// Un rescate de albergue hereda ciudad/coordenadas/país del PERFIL del
/// albergue (subir_rescate_screen.dart:_cargarCiudadAlbergue) — no se
/// edita animal por animal. Única fuente de esa pregunta para toda la UI
/// que decide si mostrar/ocultar el campo de ubicación de un rescate
/// puntual (editar_rescate_screen.dart, mis_rescates_screen.dart): antes
/// de esto, esa misma comparación (`creadoPor == 'albergue'`) se hubiera
/// repetido en cada pantalla que necesitara la misma respuesta.
bool esRescateDeAlbergue(Map<String, dynamic> rescate) =>
    esCreadoPorAlbergue(rescate['creadoPor'] as String?);

/// Lo mismo que [esRescateDeAlbergue], pero para cuando ya se tiene el
/// valor de `creadoPor` a mano (no el documento entero) — mismo criterio
/// vía [creatorRoleFromFirestore], sin que cada pantalla arme su propia
/// comparación contra el string `'albergue'`. Antes de consolidar esto
/// (hallazgo de auditoría de código, disparado por el bug real de "La
/// Perla" en `UsuariosRepository.nombrePropioParaAnimal`, un caso
/// DISTINTO de la misma familia), esa comparación vivía repetida a mano
/// en 6+ archivos — ninguna estaba mal, pero cada una era una oportunidad
/// de que una corrección futura se aplicara en una copia y no en las
/// demás.
bool esCreadoPorAlbergue(String? creadoPor) =>
    creatorRoleFromFirestore(creadoPor) == CreatorRole.albergue;

/// El rótulo visible de "con qué sombrero te escribió esta persona", a
/// partir del `creadoPor` de un chat de consulta a un negocio: 'Albergue',
/// 'Rescatista' o 'Adoptante'.
///
/// Existe por la misma razón que [esCreadoPorAlbergue]: esta cadena de
/// condiciones estaba copiada a mano, idéntica, en chat_screen.dart (el
/// encabezado del chat abierto) y en aliado_home_screen.dart (la lista de
/// conversaciones recientes del panel del aliado) — dos pantallas que
/// muestran EL MISMO dato al mismo aliado sobre la misma conversación, y
/// que por lo tanto no pueden permitirse contestar distinto. Con dos
/// copias, cualquier corrección futura (agregar un rol, cambiar un texto)
/// se aplicaba en una y se olvidaba en la otra: exactamente cómo nacieron
/// los bugs de "muestra la foto/el rótulo equivocado" que costaron toda
/// esta sesión.
///
/// `creadoPor` ausente = contactó como adoptante: ese campo solo se guarda
/// cuando alguien escribe con rol de rescatista o albergue (ver
/// `ChatsRepository.asegurarChatNegocio`).
String rotuloDeQuienContacto(String? creadoPor) {
  if (esCreadoPorAlbergue(creadoPor)) return 'Albergue';
  // Comparación directa contra el string, NO creatorRoleFromFirestore():
  // esa función mapea "cualquier cosa que no sea albergue" a rescatista
  // (para los documentos viejos sin el campo), y acá hace falta la
  // distinción contraria — sin `creadoPor` es un adoptante, no un
  // rescatista.
  if (creadoPor == 'rescatista') return 'Rescatista';
  return 'Adoptante';
}
