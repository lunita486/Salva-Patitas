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
