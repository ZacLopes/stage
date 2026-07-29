/// Nome é válido para avançar no onboarding?
///
/// O gate era `trim().isEmpty`, então UMA letra já habilitava "Continuar" —
/// e o nome vai direto pro cabeçalho do currículo que a pessoa manda pra vaga
/// (backlog SEC.5; revisão UX 28/07, achado P3-35).
///
/// Duas letras é o piso deliberado: barra o toque acidental e o "a" de teste,
/// sem inventar regra sobre nome de gente. Nada de exigir sobrenome composto,
/// acento ou capitalização — nome é dado de identidade, não de formulário.
bool isValidOnboardingName(String value) => value.trim().length >= 2;
