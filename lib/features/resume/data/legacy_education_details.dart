/// Saneia o campo `detalhes` de formação vindo do conteúdo LEGADO.
///
/// Revisão UX 28/07, achado P1-11.
///
/// O mapper canônico (`ProfileResumeMapper.mapEducation`) nunca injeta os
/// sufixos artificiais ingleses — ele escreve "Ênfase em X" e "Formação
/// complementar em Y". Mas o caminho legado do `ResumeViewModel` não passa
/// pelo mapper: ele repassa `e.details` cru do conteúdo já gerado, e esse
/// conteúdo veio de um prompt que pedia literalmente "detalhes: APENAS
/// semestre/turno/Major/Minor" — em PT-BR
/// (`supabase/functions/generate-resume/index.ts:282`).
///
/// Resultado: um currículo em português com "Major in Finance, Minor in
/// Entrepreneurship" no meio, re-emitido a cada troca de template, porque o
/// conteúdo fica em cache local e não é regerado.
///
/// Este saneador roda na LEITURA, então conserta o cache que já existe sem
/// precisar de regeração paga. Ele troca **só o rótulo**, nunca o conteúdo:
/// "Major in Finance" vira "Ênfase em Finance", não "Ênfase em Finanças" —
/// traduzir o nome da ênfase seria inventar dado sobre a formação de alguém.
///
/// Em currículo EN o rótulo inglês está CERTO — por isso o `language` é
/// obrigatório e o saneamento só acontece fora do inglês.
library;

/// `Major in X` / `Major: X` → `Ênfase em X`.
final RegExp _major = RegExp(
  r'\bmajors?\s*(?:in\s+|:\s*)',
  caseSensitive: false,
);

/// `Minor in X` / `Minor: X` → `Formação complementar em X`.
final RegExp _minor = RegExp(
  r'\bminors?\s*(?:in\s+|:\s*)',
  caseSensitive: false,
);

String sanitizeLegacyEducationDetails(String raw, {required String language}) {
  if (language == 'en') return raw;
  if (raw.isEmpty) return raw;
  return raw
      .replaceAll(_major, 'Ênfase em ')
      .replaceAll(_minor, 'Formação complementar em ');
}
