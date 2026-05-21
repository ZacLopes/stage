// ────────────────────────────────────────────────────────────────────────────
// Utilitários de normalização e comparação de texto compartilhados pelas
// edge functions de adaptação (adapt-resume-to-job) e parsing (parse-cv).
//
// Extraído de adapt-resume-to-job/index.ts na F2 da reformulação. Antes
// existia duplicado quando precisava ser usado em outra função.
// ────────────────────────────────────────────────────────────────────────────

/** Normaliza string pra comparação (lower + remove acentos + trim). */
export function normalize(s: string | null | undefined): string {
  if (!s) return ''
  return s
    .toLowerCase()
    .trim()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
}

/**
 * Normalize + colapsa QUALQUER whitespace (newlines, tabs, espaços múltiplos)
 * em um único espaço. Usar pra comparar contra raw_text extraído de PDF, que
 * costuma vir com cada palavra numa linha separada (`Liga\nde\nMercado`),
 * fazendo `normalize()` simples falhar nas comparações `.includes(...)`.
 */
export function flatten(s: string | null | undefined): string {
  return normalize(s).replace(/\s+/g, ' ').trim()
}

/** True se duas strings batem após normalização. */
export function eq(a: string | null | undefined, b: string | null | undefined): boolean {
  return normalize(a) === normalize(b)
}

/**
 * Comparação tolerante a pontuação alucinada pela IA em nomes próprios
 * (company, institution, role, degree). O GPT-4o-mini ocasionalmente insere
 * caracteres extras como `@`, `&`, `-`, `.`, `:`, `/`, `,` em meio a nomes,
 * frequentemente "vazando" pontuação de outros campos do CV (ex.: o `@` do
 * email aparece dentro do nome da instituição). Esses caracteres são
 * removidos antes da comparação — palavras inteiras continuam exigindo
 * match exato, então a proteção anti-invenção fica intacta.
 *
 * Exemplos:
 *   eqInstitutional("Link @ School of Business", "Link School of Business") → true
 *   eqInstitutional("Procter & Gamble", "Procter Gamble") → true
 *   eqInstitutional("Apple Inc.", "Apple Inc") → true
 *   eqInstitutional("Apple", "Microsoft") → false (proteção preservada)
 */
export function eqInstitutional(
  a: string | null | undefined,
  b: string | null | undefined,
): boolean {
  const strip = (s: string | null | undefined): string =>
    normalize(s).replace(/[@&\-.,:/]+/g, ' ').replace(/\s+/g, ' ').trim()
  return strip(a) === strip(b)
}

export const STOP_WORDS = new Set<string>([
  'a', 'o', 'e', 'de', 'do', 'da', 'dos', 'das', 'em', 'no', 'na', 'um', 'uma',
  'para', 'por', 'com', 'sem', 'que', 'se', 'ou', 'mas', 'ser', 'ter', 'estar',
  'mais', 'menos', 'muito', 'pouco', 'também', 'já', 'sobre', 'após', 'antes',
  'the', 'and', 'or', 'of', 'to', 'in', 'for', 'on', 'at', 'by', 'with', 'as',
  'is', 'are', 'was', 'were', 'be', 'been', 'being', 'have', 'has', 'had',
  'will', 'would', 'should', 'could',
  // Termos genéricos comuns em resumos profissionais (não-concretos):
  // são "ruído" pro check anti-invenção — IA usa pra encadear ideias, não
  // são afirmações sobre o candidato. Excluir reduz falso-positivos.
  'onde', 'possa', 'possam', 'possuir', 'possui', 'possuo',
  'buscando', 'busco', 'buscar', 'busca',
  'visando', 'vislumbrando', 'almejando',
  'atuando', 'atuar', 'atuação', 'atuante',
  'desenvolver', 'desenvolvendo', 'desenvolvimento',
  'aplicar', 'aplicando', 'aplicação',
  'contribuir', 'contribuindo', 'contribuição',
  'aprimorar', 'aprimorando', 'aprimoramento',
  'ampliar', 'ampliando', 'aprender', 'aprendendo', 'aprendizado',
  'área', 'areas', 'áreas',
  'capacidade', 'capacidades', 'capaz',
  'competência', 'competencias', 'competências',
  'habilidade', 'habilidades',
  'conhecimento', 'conhecimentos',
  'experiência', 'experiencias', 'experiências',
  'interesse', 'interesses', 'interessado', 'interessada',
  'forte', 'fortes', 'sólida', 'sólido', 'solida', 'solido',
  'profissional', 'profissionais',
  'oportunidade', 'oportunidades',
  'objetivo', 'objetivos',
  'foco', 'focado', 'focada',
  'ambiente', 'ambientes',
  'desafio', 'desafios', 'desafiador', 'desafiante',
  'novo', 'nova', 'novos', 'novas',
  'tornar', 'tornando',
  'colaborar', 'colaborando', 'colaboração', 'colaborativo', 'colaborativa',
  'time', 'times', 'equipe', 'equipes',
  'sempre', 'sendo', 'enquanto', 'assim', 'desta', 'deste', 'esta', 'este',
  'minhas', 'meus', 'minha', 'meu', 'nossa', 'nosso',
])

/**
 * Tokeniza texto removendo stop words e tokens muito curtos/numéricos.
 * Usado pra validação anti-invenção (cada token claimed pela IA precisa
 * aparecer em algum lugar do input verificado).
 */
export function tokenize(text: string): string[] {
  if (!text) return []
  return text
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .split(/[\s,.;:!?()\[\]{}<>"/\\\-•|]+/)
    .filter((w) => w.length >= 3 && !STOP_WORDS.has(w) && !/^\d+$/.test(w))
}
