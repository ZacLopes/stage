import 'contact_email.dart';

/// Política única para o NOME DO ARQUIVO do PDF de currículo.
///
/// Defesa de última linha para uma saída pública — é o arquivo que o candidato
/// anexa numa vaga e que o recrutador vê antes de abrir. Mesmo espírito do
/// [ContactEmail], que protege o e-mail impresso DENTRO do documento.
///
/// ## O defeito que originou (B1/D1 do device-test de 24/07)
///
/// O código fazia `(user?.name ?? 'profissional')`. Mas `UserProfile.name` é
/// não-nulável e o desserializador coage NULL para `''`, então o `??` só
/// dispara quando o OBJETO é nulo — nunca quando o nome está vazio. Resultado
/// medido em produção: `curriculo_.pdf` e `curriculo__1eee2f.pdf`
/// (underscore duplo), para **110 de 2.137 usuários**.
///
/// ## Por que nunca derivar de e-mail (decisão 6, 26/07)
///
/// Medido em prod: **109 dos 110 usuários sem nome entraram por login por
/// telefone**, cujo e-mail sintético é `phone_<numero>@stage.app`. Derivar nome
/// do e-mail poria **o telefone da pessoa no nome do PDF que ela anexa numa
/// vaga**. O mesmo vale para o alias privado da Apple (345 usuários). Qualquer
/// candidato com `@` — ou reprovado por [ContactEmail.isPrivateOrSynthetic] —
/// é descartado antes do fallback.
class ResumeFilename {
  ResumeFilename._();

  /// Usado quando não há nenhum nome utilizável. Decisão do fundador (26/07):
  /// `curriculo.pdf`, e não `curriculo_profissional.pdf` — "profissional" lê
  /// como texto de preenchimento para quem recebe o anexo.
  static const String base = 'curriculo';

  /// Teto do trecho de nome. Nomes completos brasileiros passam folgados;
  /// evita filename patológico sem cortar gente real.
  static const int maxNameLength = 60;

  /// Acentos são removidos (decisão 6): o nome fiel, com acentos, já é impresso
  /// DENTRO do documento, onde renderiza corretamente. O nome do arquivo é
  /// otimizado para chegar íntegro em ATS e servidores de e-mail legados.
  static const Map<String, String> _foldings = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n', 'ý': 'y', 'ÿ': 'y',
    'Á': 'A', 'À': 'A', 'Â': 'A', 'Ã': 'A', 'Ä': 'A', 'Å': 'A',
    'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E',
    'Í': 'I', 'Ì': 'I', 'Î': 'I', 'Ï': 'I',
    'Ó': 'O', 'Ò': 'O', 'Ô': 'O', 'Õ': 'O', 'Ö': 'O',
    'Ú': 'U', 'Ù': 'U', 'Û': 'U', 'Ü': 'U',
    'Ç': 'C', 'Ñ': 'N', 'Ý': 'Y',
  };

  /// True quando o valor pode virar nome de arquivo público.
  ///
  /// Rejeita vazio e **qualquer coisa com `@`** — o que cobre e-mail comum,
  /// alias da Apple (`privaterelay.appleid.com`, `private.icloud.com`) e o
  /// sintético do login por telefone (`phone_*@stage.app`). A checagem de
  /// [ContactEmail.isPrivateOrSynthetic] fica junto de propósito: documenta a
  /// intenção e sobrevive caso a regra do `@` seja afrouxada um dia.
  static bool isUsableName(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.contains('@')) return false;
    if (ContactEmail.isPrivateOrSynthetic(trimmed)) return false;
    return true;
  }

  static String _fold(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_foldings[char] ?? char);
    }
    return buffer.toString();
  }

  /// Normaliza um nome para uso em filename: sem acento, sem caractere de
  /// path, espaços viram `_`, sem `_` repetido nem nas pontas, truncado.
  static String sanitize(String? value) {
    if (!isUsableName(value)) return '';
    var out = _fold(value!.trim());
    // Só letras ASCII, dígitos, espaço, hífen e underscore sobrevivem. Mata
    // `/`, `\`, `..`, aspas e qualquer coisa que possa escapar do filename.
    out = out.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), ' ');
    out = out.replaceAll(RegExp(r'\s+'), '_');
    out = out.replaceAll(RegExp(r'_+'), '_');
    out = out.replaceAll(RegExp(r'^[_-]+|[_-]+$'), '');
    if (out.length > maxNameLength) {
      out = out.substring(0, maxNameLength);
      out = out.replaceAll(RegExp(r'[_-]+$'), '');
    }
    return out;
  }

  /// Monta o nome final do arquivo.
  ///
  /// [preferredName] é a fonte mais confiável (o nome que vai impresso no
  /// próprio currículo); [accountName] é o da conta. [suffix] é um marcador
  /// opcional (ex.: prefixo do id da vaga no CV adaptado).
  ///
  /// Junta só os pedaços não-vazios com `_`, o que elimina o underscore duplo
  /// de `curriculo__1eee2f.pdf`.
  static String build({
    String? preferredName,
    String? accountName,
    String? suffix,
  }) {
    final name = [preferredName, accountName].map(sanitize).firstWhere(
          (candidate) => candidate.isNotEmpty,
          orElse: () => '',
        );
    final cleanSuffix = sanitize(suffix);
    final parts = [
      base,
      if (name.isNotEmpty) name,
      if (cleanSuffix.isNotEmpty) cleanSuffix,
    ];
    return '${parts.join('_')}.pdf';
  }
}
