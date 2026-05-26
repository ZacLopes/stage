// Helpers para resolver o nome exibido na UI a partir das duas fontes
// possíveis (profile_personal do novo onboarding e user_profiles legacy).
//
// Centralizado aqui pra evitar drift entre as telas (Perfil, Configurações,
// Editar conta, futuras telas que mostrem nome do user).

import '../../features/profile/application/profile_editor_view_model.dart';

/// Resolve o nome a ser exibido. Ordem de prioridade:
///   1. profile_personal (firstName + lastName) — novo onboarding
///   2. legacyName (user_profiles.name) — se não for o placeholder "User"
///   3. "Usuário" — fallback genérico
String resolveDisplayName(ProfileEditorViewModel editorVM, String? legacyName) {
  final first = editorVM.personal?.firstName?.trim() ?? '';
  final last = editorVM.personal?.lastName?.trim() ?? '';
  final fromProfile = [first, last].where((s) => s.isNotEmpty).join(' ');
  if (fromProfile.isNotEmpty) return fromProfile;

  final legacy = legacyName?.trim() ?? '';
  if (legacy.isNotEmpty && legacy.toLowerCase() != 'user') return legacy;

  return 'Usuário';
}

/// Splitta "Maria Silva Souza" em ('Maria', 'Silva Souza').
/// Se o input for vazio/whitespace, retorna ('', '').
/// Se for uma palavra só, vira (palavra, '').
(String firstName, String lastName) splitFullName(String fullName) {
  final parts = fullName.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return ('', '');
  if (parts.length == 1) return (parts.first, '');
  return (parts.first, parts.sublist(1).join(' '));
}
