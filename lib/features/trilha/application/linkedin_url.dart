// Normalização leve de URL do LinkedIn (PLANO-FASE-6 — canonização).
//
// Objetivo: deixar o link utilizável (com https) sem DESCARTAR o que o usuário
// digitou — perder o dado é pior que ter um link levemente fora do padrão.
// Permissivo de propósito (vanity, /company, m.linkedin.com, sem https…).

/// Normaliza um link do LinkedIn. Retorna null só pra string vazia.
/// - contém 'linkedin.com' → garante https://;
/// - handle/vanity simples (ex.: 'in/joao', 'joao-silva') → monta /in/;
/// - não reconheceu → devolve o texto cru (não descarta).
String? normalizeLinkedinUrl(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;

  final low = t.toLowerCase();
  if (low.contains('linkedin.com')) {
    return low.startsWith('http') ? t : 'https://$t';
  }

  // Vanity/handle sem domínio: 'in/joao', '/in/joao', 'joao-silva'.
  if (!t.contains(' ') &&
      !t.contains('.') &&
      RegExp(r'^[A-Za-z0-9\-_/]+$').hasMatch(t)) {
    final handle = t.replaceFirst(RegExp(r'^/?(in/)?', caseSensitive: false), '');
    if (handle.length >= 3) return 'https://linkedin.com/in/$handle';
  }

  // Não parece LinkedIn — guarda o cru (melhor que descartar).
  return t;
}
