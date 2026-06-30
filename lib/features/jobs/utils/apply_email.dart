/// Montagem do `mailto:` de candidatura por email (Polifinance e similares,
/// `applicationMethod == 'email'`).
///
/// Objetivo: quando o usuário aperta "Enviar CV por email", o app abre o
/// cliente de email JÁ com assunto e uma mensagem padrão personalizada — ele
/// só anexa o currículo e envia. A mensagem (definida pelo fundador) preenche
/// o nome da vaga e o nome do candidato.
///
/// Tudo aqui é puro (sem Flutter/IO) pra ser testável e reusado pelo único
/// call site de apply (liked_jobs_screen::_resolveApplyAction, branch email).
library;

/// Placeholder mantido quando não há dado real, sinalizando ao user que ele
/// deve preencher antes de enviar.
const _placeholderVaga = '[Nome da Vaga]';
const _placeholderCandidato = '[Nome do candidato]';

/// `true` se o nome resolvido é um nome real (não vazio e não o fallback
/// genérico "Usuário" do [resolveDisplayName]).
bool _isRealName(String name) =>
    name.isNotEmpty && name.toLowerCase() != 'usuário';

/// Corpo (body) padrão do email de candidatura. Substitui o nome da vaga e o
/// nome do candidato; mantém o placeholder quando o dado não existe.
String buildApplicationEmailBody({
  required String jobTitle,
  String? userName,
}) {
  final vaga = jobTitle.trim().isEmpty ? _placeholderVaga : jobTitle.trim();
  final name = userName?.trim() ?? '';
  final candidato = _isRealName(name) ? name : _placeholderCandidato;
  // \r\n (CRLF) é a quebra de linha recomendada pelo RFC 6068 pra mailto.
  return [
    'Olá,',
    '',
    'Estou me candidatando à vaga de $vaga.',
    '',
    'Segue meu currículo em anexo para avaliação.',
    '',
    'Fico à disposição para fornecer mais informações.',
    '',
    'Atenciosamente,',
    '',
    candidato,
  ].join('\r\n');
}

/// Assunto do email. Prioriza o assunto sugerido da vaga (Polifinance et al.,
/// com placeholders "[SEU NOME]"/"(SEU NOME)" trocados pelo nome real); na
/// ausência, usa um padrão `Candidatura — <vaga>`.
String buildApplicationEmailSubject({
  required String jobTitle,
  String? suggestedSubject,
  String? userName,
}) {
  final name = userName?.trim() ?? '';
  final suggested = suggestedSubject?.trim() ?? '';
  if (suggested.isNotEmpty) {
    if (_isRealName(name)) {
      return suggested.replaceAll(
        RegExp(r'[\[\(]\s*seu\s+nome\s*[\]\)]', caseSensitive: false),
        name,
      );
    }
    return suggested;
  }
  final vaga = jobTitle.trim().isEmpty ? _placeholderVaga : jobTitle.trim();
  return 'Candidatura — $vaga';
}

/// Monta o `mailto:` completo com assunto + corpo personalizados.
///
/// RFC 6068: os parâmetros usam percent-encoding (%20 pra espaço, %0D%0A pra
/// quebra de linha). NÃO usar `Uri(queryParameters: ...)`: ele aplica
/// form-urlencoded (`+` pra espaço), que clientes de email iOS/Android mostram
/// literalmente como "+". Por isso montamos a query manualmente com
/// [Uri.encodeComponent].
Uri buildApplyMailtoUri({
  required String email,
  required String jobTitle,
  String? suggestedSubject,
  String? userName,
}) {
  final subject = buildApplicationEmailSubject(
    jobTitle: jobTitle,
    suggestedSubject: suggestedSubject,
    userName: userName,
  );
  final body = buildApplicationEmailBody(jobTitle: jobTitle, userName: userName);
  final query =
      'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}';
  return Uri.parse('mailto:$email?$query');
}
