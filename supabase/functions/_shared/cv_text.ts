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
 * Em F6: se match estrito falha, tenta similarity (Jaro-Winkler >= 0.88)
 * como fallback. Pega typos de 1-2 chars que a IA introduz por engano
 * ("Universadade" vs "Universidade"). Threshold alto (0.88) garante que
 * nomes diferentes não casam ("Apple" vs "Microsoft" = ~0.0).
 *
 * Exemplos:
 *   eqInstitutional("Link @ School of Business", "Link School of Business") → true
 *   eqInstitutional("Procter & Gamble", "Procter Gamble") → true
 *   eqInstitutional("Universadade do Brasil", "Universidade do Brasil") → true (typo, similarity ~0.93)
 *   eqInstitutional("Apple", "Microsoft") → false
 */
export function eqInstitutional(
  a: string | null | undefined,
  b: string | null | undefined,
): boolean {
  const strip = (s: string | null | undefined): string =>
    normalize(s).replace(/[@&\-.,:/]+/g, ' ').replace(/\s+/g, ' ').trim()
  const sa = strip(a)
  const sb = strip(b)
  if (sa === sb) return true
  // Fallback fuzzy: típico de typos da IA. Threshold 0.88 pega 1-2 char
  // diff em palavras de 8+ chars sem aceitar nomes completamente
  // diferentes (rejeita 0.4-0.6 que seriam "parecidos mas distintos").
  if (sa.length < 4 || sb.length < 4) return false
  return jaroWinklerSimilarity(sa, sb) >= 0.88
}

/**
 * Jaro-Winkler similarity (0-1). Versão inline pra evitar dependência
 * externa. Implementação clássica + bônus de prefixo até 4 chars.
 * Otimizada para strings curtas (nomes próprios, ≤100 chars).
 */
export function jaroWinklerSimilarity(s1: string, s2: string): number {
  if (s1 === s2) return 1.0
  if (s1.length === 0 || s2.length === 0) return 0.0

  const matchWindow = Math.max(0, Math.floor(Math.max(s1.length, s2.length) / 2) - 1)
  const s1Matches: boolean[] = new Array(s1.length).fill(false)
  const s2Matches: boolean[] = new Array(s2.length).fill(false)

  let matches = 0
  for (let i = 0; i < s1.length; i++) {
    const start = Math.max(0, i - matchWindow)
    const end = Math.min(i + matchWindow + 1, s2.length)
    for (let j = start; j < end; j++) {
      if (s2Matches[j]) continue
      if (s1[i] !== s2[j]) continue
      s1Matches[i] = true
      s2Matches[j] = true
      matches++
      break
    }
  }

  if (matches === 0) return 0.0

  let k = 0
  let transpositions = 0
  for (let i = 0; i < s1.length; i++) {
    if (!s1Matches[i]) continue
    while (!s2Matches[k]) k++
    if (s1[i] !== s2[k]) transpositions++
    k++
  }
  transpositions = Math.floor(transpositions / 2)

  const jaro = (matches / s1.length + matches / s2.length +
                (matches - transpositions) / matches) / 3

  // Winkler boost: prefixo comum até 4 chars, scaling factor 0.1.
  let prefix = 0
  const maxPrefix = Math.min(4, s1.length, s2.length)
  for (let i = 0; i < maxPrefix; i++) {
    if (s1[i] === s2[i]) prefix++
    else break
  }
  return jaro + prefix * 0.1 * (1 - jaro)
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
