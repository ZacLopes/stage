// Edge Function: adapt-resume-to-job
//
// Adapta o currículo do usuário para uma vaga específica via GPT-4o-mini.
// PRINCÍPIO FUNDAMENTAL: zero invenção. O modelo só pode REORDENAR,
// REFORMULAR ou ENFATIZAR dados que já estão no input. Nome, email, datas,
// empresas, instituições e diplomas são imutáveis e validados pós-resposta.
//
// Input: { job_id: uuid, force?: boolean }
// Output: {
//   changes: [{ field, label, before, after, reason }, ...],
//   resume_data: { ...mesmo schema que ResumeData no client... },
//   match_score_before?: int,
//   match_score_after?: int,
//   cached: boolean,
//   model_used: string,
// }
//
// Cache: tabela adapted_resumes, único por (user, job). Invalida quando o
// usuário edita perfil ou currículo (via source_hash).
//
// Rate limit: 30 chamadas/dia por user. Cache hits NÃO contam.
// Custo: ~$0.001-0.003 por adaptação real.

import { serve } from 'std/http/server'
import { createClient } from 'supabase'
import { captureEvent, trackAIGeneration } from '../_shared/posthog.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// F5 da reformulação: pipeline em 2 etapas.
//   Step A (MODEL_DRAFT): rascunho estrutural completo. Cobre TODOS os
//                          campos do JSON_SCHEMA. Custo baixo, latência ~5s.
//   Step B (MODEL_REFINE): refina APENAS summary + bullets de experiences.
//                           Resto do step A passa direto. Custo ~10× maior
//                           mas só em 2 campos de texto. Latência +5s.
//
// Step B é controlado por ENABLE_REFINEMENT (env var). Default true. Pra
// rollback rápido: env REFINEMENT_ENABLED=false → cai pro pipeline antigo
// (single-shot mini). Latência total alvo: p50 ~10s, p95 ~25s.
const MODEL_DRAFT = 'gpt-4o-mini'
const MODEL_REFINE = 'gpt-4o'
const MODEL = MODEL_DRAFT // alias mantido para backward compat com logs/posthog
// v13: descrição de projeto não inclui mais o título+role do próximo —
// _findEndOfDescription corta no ". " seguido de Maiúscula. v12 deixava
// "Gerenciei... Link Finance. Desenvolvimento de Aplicativo Gamificado
// Desenvolvedor" como descrição do projeto 1.
// v14 (F0 da reformulação): invalida cache existente após introdução de
// eqInstitutional, auto-restore de achievements, e tolerância de location
// via cvFlat. Sem isso, adaptações cacheadas continuariam falhando com
// regras antigas. Bump também serve de marcador no PostHog para separar
// cohorts pré/pós-fix.
const PROMPT_VERSION = 'v14'
const RATE_LIMIT_PER_DAY = 30
// 50s cabe step A (mini, p95 ~8s) + step B (4o, p95 ~12s) + folga. Antes
// era 40s (F0); F5 adiciona o step B (~5-10s extras). Cliente Flutter
// timeout subiu pra 120s pra cobrir o overhead total do pipeline em 2
// etapas com retries. Sem isso, step B abortava no meio.
const OPENAI_TIMEOUT_MS = 50000
const MAX_BULLET_INFLATION = 1.3 // adapt não pode > 1.3x bullets do original

// ────────────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────────────

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

async function sha256Hex(input: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input))
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

/** Normaliza string pra comparação (lower + remove acentos + trim). */
function normalize(s: string | null | undefined): string {
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
function flatten(s: string | null | undefined): string {
  return normalize(s).replace(/\s+/g, ' ').trim()
}

/** True se duas strings batem após normalização. */
function eq(a: string | null | undefined, b: string | null | undefined): boolean {
  return normalize(a) === normalize(b)
}

/**
 * Comparação tolerante a pontuação alucinada pela IA em nomes próprios
 * (company, institution, role, degree). Em F6 ganhou fallback de
 * similarity (Jaro-Winkler ≥ 0.88) pra cobrir typos de 1-2 chars que a
 * IA introduz por engano ("Universadade" vs "Universidade").
 *
 * Versão idêntica à de `_shared/cv_text.ts:eqInstitutional` — duplicada
 * aqui porque alterar o caminho do import dentro do adapt-resume-to-job
 * (que já é ~2400 linhas) é alto risco. Mantém sincronizado manualmente.
 *
 * Exemplos:
 *   eqInstitutional("Link @ School of Business", "Link School of Business") → true
 *   eqInstitutional("Procter & Gamble", "Procter Gamble") → true
 *   eqInstitutional("Universadade do Brasil", "Universidade do Brasil") → true (typo)
 *   eqInstitutional("Apple", "Microsoft") → false (proteção preservada)
 */
function eqInstitutional(a: string | null | undefined, b: string | null | undefined): boolean {
  const strip = (s: string | null | undefined): string =>
    normalize(s).replace(/[@&\-.,:/]+/g, ' ').replace(/\s+/g, ' ').trim()
  const sa = strip(a)
  const sb = strip(b)
  if (sa === sb) return true
  if (sa.length < 4 || sb.length < 4) return false
  return jaroWinklerSimilarity(sa, sb) >= 0.88
}

/** Jaro-Winkler similarity (0-1). Veja _shared/cv_text.ts:jaroWinklerSimilarity. */
function jaroWinklerSimilarity(s1: string, s2: string): number {
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
      if (s2Matches[j] || s1[i] !== s2[j]) continue
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
  let prefix = 0
  const maxPrefix = Math.min(4, s1.length, s2.length)
  for (let i = 0; i < maxPrefix; i++) {
    if (s1[i] === s2[i]) prefix++
    else break
  }
  return jaro + prefix * 0.1 * (1 - jaro)
}

// ────────────────────────────────────────────────────────────────────────────
// Resume input building (lê do gamification_data + tabelas)
// ────────────────────────────────────────────────────────────────────────────

interface InputExperience {
  role: string
  company: string
  period: string
  description: string // bullets separados por \n
  location?: string
}

interface InputEducation {
  degree: string
  institution: string
  period: string
  details?: string
  location?: string
}

interface InputResume {
  fullName: string
  email: string
  phone: string
  linkedin: string
  location: string
  language: string
  summary: string
  skills: string[]
  experiences: InputExperience[]
  education: InputEducation[]
  achievements: string[]
  interests: string[]
  // Pool de palavras-chave do user (skills + CV importado tokenizado).
  // Usado pra validar que skills sugeridas pelo modelo NÃO foram inventadas.
  keywordPool: Set<string>
  // CV bruto (caso seja a única fonte). Não vai pro prompt cru — só pra
  // construir o keywordPool.
  importedCvText?: string
}

const STOP_WORDS = new Set<string>([
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

function tokenize(text: string): string[] {
  if (!text) return []
  return text
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .split(/[\s,.;:!?()\[\]{}<>"/\\\-•|]+/)
    .filter((w) => w.length >= 3 && !STOP_WORDS.has(w) && !/^\d+$/.test(w))
}

// ────────────────────────────────────────────────────────────────────────────
// Pre-parser do CV bruto (server-side regex).
//
// IA gpt-4o-mini não é confiável pra extrair seções de PDF word-per-line. Em
// testes ela retorna `experiences: []` mesmo com CV cheio de experiências.
// Solução: pré-parsear o raw_text aqui, populando input.experiences/education/
// skills/contact ANTES de chamar a IA. Aí a função usa o modo "structured"
// (mais rigoroso) em vez de "cv-only".
//
// Funciona via heurísticas sobre o output do Syncfusion PDF extractor:
// cada "linha" do CV vira uma palavra ou frase curta separada por \n.
// Seções são marcadas por headers em CAPS ("EXPERIÊNCIA PROFISSIONAL", "FORMAÇÃO").
// ────────────────────────────────────────────────────────────────────────────

interface PreParsedCv {
  fullName?: string
  email?: string
  phone?: string
  linkedin?: string
  location?: string
  summary?: string
  experiences: InputExperience[]
  education: InputEducation[]
  skills: string[]
  achievements: string[]
  interests: string[]
}

/** Reconstrói linhas do PDF achatando whitespace, mas preservando quebras
 * lógicas: linhas em branco no original viram separadores entre seções. */
function _splitParagraphs(rawText: string): string[] {
  // Quebra duplicada (linha em branco) = separador de seção
  return rawText.split(/\n\s*\n/).map((p) => p.trim()).filter(Boolean)
}

/** Junta palavra-por-linha em texto fluido. Heurística: se uma linha termina
 * com letra minúscula ou número e a próxima começa com minúscula, junta com
 * espaço; se a próxima começa com maiúscula, junta com espaço também (PDF
 * word-per-line). Só preserva \n entre bullets/items distintos. */
function _reflowLines(rawText: string): string {
  return rawText
    .split('\n')
    .map((l) => l.trim())
    .filter(Boolean)
    .join(' ')
    .replace(/\s+/g, ' ')
    .trim()
}

/** Headers reconhecidos (PT-BR e EN). Lookup case-insensitive. */
const _SECTION_HEADERS: Array<{ keys: string[]; section: string }> = [
  { keys: ['resumo profissional', 'resumo', 'summary', 'sumario', 'sumário', 'sobre mim', 'about'], section: 'summary' },
  { keys: ['experiência profissional', 'experiencia profissional', 'experiências', 'experiencias', 'professional experience', 'work experience', 'experience'], section: 'experiences' },
  { keys: ['formação', 'formacao', 'educação', 'educacao', 'education', 'academic'], section: 'education' },
  { keys: ['projetos', 'projects', 'projetos pessoais'], section: 'projects' },
  { keys: ['habilidades', 'skills', 'competências', 'competencias'], section: 'skills' },
  { keys: ['cursos e certificações', 'cursos', 'certificações', 'certificacoes', 'certifications', 'cursos e certificacoes'], section: 'certifications' },
  { keys: ['idiomas', 'languages', 'línguas', 'linguas'], section: 'languages' },
  { keys: ['interesses', 'interests', 'hobbies'], section: 'interests' },
]

/** Detecta seção de uma linha (header). Retorna nome canônico ou null. */
function _detectSection(line: string): string | null {
  const norm = normalize(line)
  for (const { keys, section } of _SECTION_HEADERS) {
    for (const k of keys) {
      if (norm === k || norm === k.replace(/\s/g, '')) return section
    }
  }
  return null
}

/** Regex de período (Mês Ano - Mês Ano | Mês Ano - Atual | Ano - Ano). Capture global. */
const PERIOD_REGEX_GLOBAL = /\b(?:jan|fev|mar|abr|mai|jun|jul|ago|set|out|nov|dez|january|february|march|april|may|june|july|august|september|october|november|december|janeiro|fevereiro|março|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro)\.?\s+20\d{2}\s*[-–—]\s*(?:(?:jan|fev|mar|abr|mai|jun|jul|ago|set|out|nov|dez|january|february|march|april|may|june|july|august|september|october|november|december|janeiro|fevereiro|março|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro)\.?\s+20\d{2}|atual|present|presente|current)|\b20\d{2}\s*[-–—]\s*(?:20\d{2}|atual|present|presente|current)\b/gi

/**
 * Parseia uma seção (texto flat) em experiências/formações.
 *
 * Estratégia: encontra TODAS as ocorrências de período (Mês Ano - Mês Ano).
 * Cada match demarca um item. Texto ANTES do período (entre o item anterior
 * e este período) = role/cargo + company/instituição. Texto DEPOIS = bullets/details.
 *
 * Heurística pra role+company: split por whitespace, primeiras 1-3 palavras = role,
 * resto = company. Ajusta baseado em conhecimento do template (PDF gera word-per-line).
 */
function _parsePeriodicalSection(
  flatSectionText: string,
  fieldA: 'role' | 'degree',
  fieldB: 'company' | 'institution',
): Array<{ a: string; b: string; period: string; description: string }> {
  if (!flatSectionText || flatSectionText.length < 20) return []
  const matches: Array<{ index: number; period: string; endIndex: number }> = []
  PERIOD_REGEX_GLOBAL.lastIndex = 0
  let m: RegExpExecArray | null
  while ((m = PERIOD_REGEX_GLOBAL.exec(flatSectionText)) !== null) {
    matches.push({ index: m.index, period: m[0], endIndex: m.index + m[0].length })
  }
  if (matches.length === 0) return []

  const items: Array<{ a: string; b: string; period: string; description: string }> = []
  for (let i = 0; i < matches.length; i++) {
    const cur = matches[i]
    const prevEnd = i > 0 ? matches[i - 1].endIndex : 0
    const nextStart = i + 1 < matches.length ? matches[i + 1].index : flatSectionText.length

    // Texto antes do período (entre item anterior e este) = role + company
    let beforeText = flatSectionText.slice(prevEnd, cur.index).trim()
    const beforeWords = beforeText.split(/\s+/).filter(Boolean)
    if (beforeWords.length === 0) continue
    // Pega só as últimas 8 palavras (role + company + possível location)
    const slice = beforeWords.slice(-Math.min(beforeWords.length, 8))

    // Heurística de split (role/degree vs company/institution):
    //
    // Default: PRIMEIRA palavra = role/degree, RESTO = company/institution.
    // Funciona pra:
    //   - "CEO Stage" → role="CEO", company="Stage"
    //   - "Administração Link School of Business" → degree="Administração", institution="Link School of Business"
    //   - "Estagiária XP Inc" → role="Estagiária", company="XP Inc"
    //
    // Casos especiais:
    //   - 1 palavra: usa como company/institution (role/degree vazio)
    //   - Role/degree composto (ex: "Financial Analyst" + "Amazon" = 3 palavras):
    //     se primeira palavra está em lista de "modificadores" (Senior, Junior,
    //     Pleno, Sr, Jr, Lead, Head, Chief, Vice, Estagiário/a, Assistente),
    //     pega 2 primeiras palavras como role.
    let aStr: string, bStr: string
    const roleModifiers = new Set([
      'senior', 'junior', 'sr', 'jr', 'lead', 'head', 'chief', 'vice',
      'estagiario', 'estagiaria', 'estagiário', 'estagiária',
      'assistente', 'analista', 'analyst', 'engenheiro', 'engenheira',
      'desenvolvedor', 'desenvolvedora', 'developer', 'gerente', 'manager',
      'diretor', 'diretora', 'director', 'coordenador', 'coordenadora',
      'consultor', 'consultora', 'consultant', 'designer', 'product',
      'project', 'tech', 'pleno', 'trainee',
    ])
    if (slice.length === 1) {
      aStr = ''
      bStr = slice[0]
    } else if (slice.length === 2) {
      aStr = slice[0]
      bStr = slice[1]
    } else {
      // Default: 1 palavra pra role, resto pra company
      let splitIdx = 1
      // Se primeira palavra é um modificador conhecido, pega 2 palavras pra role
      const firstNorm = normalize(slice[0])
      if (roleModifiers.has(firstNorm) && slice.length >= 3) {
        splitIdx = 2
      }
      aStr = slice.slice(0, splitIdx).join(' ')
      bStr = slice.slice(splitIdx).join(' ')
    }
    aStr = aStr.trim()
    bStr = bStr.trim()
    if (!bStr) continue

    // Texto depois do período até próximo período = description/bullets
    let afterText = flatSectionText.slice(cur.endIndex, nextStart).trim()
    // Cap description em 1500 chars
    if (afterText.length > 1500) afterText = afterText.slice(0, 1500)

    items.push({ a: aStr, b: bStr, period: cur.period, description: afterText })
  }
  return items
}

/**
 * Splita texto da seção PROJETOS em itens estruturados {title, role, description}.
 *
 * Estratégia: detecta verbos em 1ª pessoa do passado (Gerenciei, Desenvolvi,
 * Criei, Liderei, Realizei, Implementei, etc.) como marcadores de início de
 * descrição. Texto antes do verbo = title + role.
 *
 * Exemplo de input flat:
 *   "Diretor de Projetos na Liga de Mercado Financeiro Diretor de Projetos
 *    Gerenciei projetos... chamada Link Finance. Desenvolvimento de Aplicativo
 *    Gamificado Desenvolvedor Desenvolvi um aplicativo..."
 *
 * Output:
 *   [
 *     { title: "Diretor de Projetos na Liga de Mercado Financeiro", role: "Diretor de Projetos", description: "Gerenciei projetos... Link Finance." },
 *     { title: "Desenvolvimento de Aplicativo Gamificado", role: "Desenvolvedor", description: "Desenvolvi um aplicativo..." }
 *   ]
 */
function _parseProjectsStructured(sectionText: string): Array<{ title: string; role: string; description: string }> {
  // Verbos de ação típicos em 1ª pessoa do passado (PT-BR)
  // e em 3ª pessoa (já adaptado pela IA pra "Desenvolveu", "Gerenciou", etc.)
  const verbRegex = /\b(Gerenciei|Desenvolvi|Criei|Liderei|Realizei|Implementei|Coordenei|Apoiei|Conduzi|Construi|Participei|Atuei|Contribui|Executei|Estruturei|Estabeleci|Conquistei|Apresentei|Elabore[ei]|Otimizei|Reduzi|Aument(?:ei|ou)|Gerenciou|Desenvolveu|Criou|Liderou|Realizou|Implementou|Coordenou|Apoiou|Conduziu|Construiu|Atuou|Contribuiu|Executou|Estruturou|Estabeleceu|Conquistou|Apresentou|Elaborou|Otimizou|Trabalhei|Trabalhou)\b/g

  const matches: Array<{ index: number; verb: string }> = []
  let m: RegExpExecArray | null
  verbRegex.lastIndex = 0
  while ((m = verbRegex.exec(sectionText)) !== null) {
    matches.push({ index: m.index, verb: m[0] })
  }
  if (matches.length === 0) return []

  const projects: Array<{ title: string; role: string; description: string }> = []
  for (let i = 0; i < matches.length; i++) {
    const cur = matches[i]
    const prevDescEnd = i > 0 ? _findEndOfDescription(sectionText, matches[i - 1].index, cur.index) : 0
    const nextDescEnd = i + 1 < matches.length ? matches[i + 1].index : sectionText.length

    // Texto antes do verbo (e depois da descrição anterior) = title + role
    const beforeText = sectionText.slice(prevDescEnd, cur.index).trim()
    const beforeWords = beforeText.split(/\s+/).filter(Boolean)
    if (beforeWords.length === 0 && i === 0) continue

    let title = ''
    let role = ''
    // Lista de palavras tipicamente usadas como CARGO/ROLE em CVs brasileiros
    // (substantivos de profissão/posição). Detecção dessas palavras NO FINAL
    // do beforeText indica boundary entre title e role.
    const roleEndKeywords = new Set([
      'desenvolvedor', 'desenvolvedora', 'developer',
      'diretor', 'diretora', 'director',
      'gerente', 'manager', 'lead', 'líder', 'lider',
      'analista', 'analyst',
      'engenheiro', 'engenheira', 'engineer',
      'coordenador', 'coordenadora', 'coordinator',
      'consultor', 'consultora', 'consultant',
      'estagiario', 'estagiária', 'estagiária', 'intern', 'trainee',
      'assistente', 'assistant',
      'designer', 'designer', 'product',
      'ceo', 'cto', 'cfo', 'coo', 'cmo', 'cio',
      'presidente', 'president',
      'vice', 'sr', 'jr', 'senior', 'junior', 'pleno',
      'representante', 'representative',
      'voluntario', 'voluntária', 'volunteer',
      'mentor', 'tutor', 'monitor', 'professor',
      'embaixador', 'embaixadora', 'ambassador',
      'fundador', 'fundadora', 'founder', 'co-founder', 'cofounder',
    ])

    if (beforeWords.length === 1) {
      title = beforeWords[0]
      role = ''
    } else if (beforeWords.length === 2) {
      title = beforeWords[0]
      role = beforeWords[1]
    } else {
      // Estratégia: procura palavra que parece ROLE no final.
      // Verifica últimas 3 palavras de trás pra frente.
      let roleStartIdx = -1
      for (let j = beforeWords.length - 1; j >= Math.max(0, beforeWords.length - 3); j--) {
        const norm = normalize(beforeWords[j])
        if (roleEndKeywords.has(norm)) {
          roleStartIdx = j
          break
        }
      }
      if (roleStartIdx > 0) {
        // Encontrou role — separa
        role = beforeWords.slice(roleStartIdx).join(' ')
        title = beforeWords.slice(0, roleStartIdx).join(' ')
      } else {
        // Não achou role conhecido. Default: role = últimas 1-2 palavras
        // (depende do tamanho — pra textos curtos é provável que role
        // seja só 1 palavra; pra textos longos pode ser 2-3).
        if (beforeWords.length >= 6) {
          role = beforeWords.slice(-3).join(' ')
          title = beforeWords.slice(0, -3).join(' ')
        } else if (beforeWords.length >= 4) {
          role = beforeWords.slice(-2).join(' ')
          title = beforeWords.slice(0, -2).join(' ')
        } else {
          role = beforeWords.slice(-1).join(' ')
          title = beforeWords.slice(0, -1).join(' ')
        }
      }
      // Se title contém o role como substring final, remove duplicação
      const roleNorm = normalize(role)
      const titleNorm = normalize(title)
      if (titleNorm.endsWith(' ' + roleNorm) || titleNorm === roleNorm) {
        title = title.slice(0, title.length - role.length).trim()
      }
    }

    // Descrição: do verbo até o fim do PARÁGRAFO (não até o próximo verbo —
    // isso incluía o título+role do próximo projeto na descrição).
    // _findEndOfDescription procura ". " seguido de Maiúscula entre o verbo
    // atual e o próximo: esse é o ponto onde a sentença termina e o próximo
    // título começa.
    const descriptionEnd = i + 1 < matches.length
      ? _findEndOfDescription(sectionText, cur.index, nextDescEnd)
      : sectionText.length
    const description = sectionText.slice(cur.index, descriptionEnd > cur.index ? descriptionEnd : nextDescEnd).trim()

    if (title || description) {
      projects.push({
        title: title.trim(),
        role: role.trim(),
        description: description.replace(/\s+/g, ' ').trim(),
      })
    }
  }
  return projects
}

/** Acha onde a descrição "termina": após ponto final + espaço + nome capitalizado. */
function _findEndOfDescription(text: string, startIdx: number, maxIdx: number): number {
  // Procura "ponto + espaço + Maiúscula" entre startIdx e maxIdx
  const slice = text.slice(startIdx, maxIdx)
  const endMatch = slice.match(/\.\s+(?=[A-ZÁÉÍÓÚÂÊÔÃÕÇ])/)
  if (endMatch && endMatch.index !== undefined) {
    return startIdx + endMatch.index + endMatch[0].length
  }
  return startIdx
}

/**
 * Tenta extrair estrutura básica do raw_text de um CV importado.
 *
 * Estratégia: flatten (rejoin word-per-line PDF), split por headers ALL CAPS,
 * depois processa cada seção. Robusto contra a quebra de palavra por linha
 * que o Syncfusion PDF extractor produz.
 */
function preParseRawCv(rawText: string): PreParsedCv {
  const result: PreParsedCv = {
    experiences: [],
    education: [],
    skills: [],
    achievements: [],
    interests: [],
  }
  if (!rawText || rawText.length < 100) return result

  const lines = rawText.split('\n').map((l) => l.trim()).filter(Boolean)
  if (lines.length === 0) return result

  // === EXTRAÇÃO DE HEADER (primeiras 20 linhas: nome, contato) ===
  const header = lines.slice(0, 20)
  const headerText = header.join(' ')

  const emailMatch = headerText.match(/[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}/i)
  if (emailMatch) result.email = emailMatch[0]

  const phoneMatch = headerText.match(/\(?\d{2}\)?\s*\d{4,5}[\s\-]?\d{4}/)
  if (phoneMatch) result.phone = phoneMatch[0].trim()

  const linkedinMatch = headerText.match(/(?:linkedin\.com\/in\/|linkedin\.com\/)[\w\-/?=&%]+/i)
  if (linkedinMatch) result.linkedin = linkedinMatch[0]

  const locMatch = headerText.match(/([A-ZÁÉÍÓÚÂÊÔÃÕÇ][a-záéíóúâêôãõç]+(?:\s+[A-ZÁÉÍÓÚÂÊÔÃÕÇ][a-záéíóúâêôãõç]+)*)\s*[-–]\s*([A-Z]{2})\b/)
  if (locMatch) result.location = `${locMatch[1]} - ${locMatch[2]}`

  // Nome: primeiras linhas com palavras capitalizadas/CAPS antes de contato.
  const nameTokens: string[] = []
  for (const line of header.slice(0, 6)) {
    if (line.includes('@') || phoneMatch?.[0] === line) break
    const looksLikeName = /^([A-ZÁÉÍÓÚÂÊÔÃÕÇ][a-záéíóúâêôãõç]+\s*)+$/.test(line) ||
      /^([A-ZÁÉÍÓÚÂÊÔÃÕÇ]+\s*)+$/.test(line)
    if (looksLikeName && line.length >= 2 && line.length <= 30) {
      nameTokens.push(line)
      if (nameTokens.length >= 4) break
    }
  }
  if (nameTokens.length > 0) {
    result.fullName = nameTokens.join(' ').replace(/\s+/g, ' ').trim()
  }

  // === FLATTEN: junta tudo num texto fluido, preservando whitespace mínimo ===
  // Substitui \n por espaço, colapsa whitespace.
  const flat = lines.join(' ').replace(/\s+/g, ' ').trim()

  // === SPLIT POR HEADERS ===
  // Headers no template típico vêm em CAPS ("EXPERIÊNCIA PROFISSIONAL", "FORMAÇÃO").
  // CASE-SENSITIVE: sem flag `i`. Sem isso, "Experiência" minúscula em um texto
  // corrido ("Experiência em liderança de projetos") era detectada como header
  // e quebrava a divisão de seções. Headers em CVs PT-BR sempre vêm em CAPS.
  const sectionHeaderRegex = /\b(RESUMO PROFISSIONAL|RESUMO|SUMÁRIO|SUMARIO|SOBRE MIM|FORMAÇÃO|FORMACAO|EDUCAÇÃO|EDUCACAO|EDUCATION|ACADEMIC BACKGROUND|EXPERIÊNCIA PROFISSIONAL|EXPERIENCIA PROFISSIONAL|EXPERIÊNCIA|EXPERIENCIA|PROFESSIONAL EXPERIENCE|WORK EXPERIENCE|EXPERIENCE|PROJETOS|PROJECTS|HABILIDADES|SKILLS|COMPETÊNCIAS|COMPETENCIAS|CURSOS E CERTIFICAÇÕES|CURSOS E CERTIFICACOES|CURSOS|CERTIFICAÇÕES|CERTIFICACOES|CERTIFICATIONS|IDIOMAS|LANGUAGES|LÍNGUAS|LINGUAS|INTERESSES|INTERESTS|HOBBIES)\b/g

  // Encontra todas as posições dos headers no texto flat.
  const headerPositions: Array<{ idx: number; name: string; canonical: string }> = []
  let hMatch: RegExpExecArray | null
  sectionHeaderRegex.lastIndex = 0
  while ((hMatch = sectionHeaderRegex.exec(flat)) !== null) {
    const name = hMatch[0]
    const norm = normalize(name)
    let canonical: string | null = null
    if (norm.startsWith('resumo') || norm.startsWith('sumario') || norm.startsWith('sumário') || norm.startsWith('sobre')) canonical = 'summary'
    else if (norm.startsWith('formacao') || norm.startsWith('formação') || norm.startsWith('educacao') || norm.startsWith('educação') || norm.startsWith('education') || norm.startsWith('academic')) canonical = 'education'
    else if (norm.startsWith('experiencia') || norm.startsWith('experiência') || norm.includes('experience')) canonical = 'experiences'
    else if (norm.startsWith('projetos') || norm.startsWith('projects')) canonical = 'projects'
    else if (norm.startsWith('habilidades') || norm.startsWith('skills') || norm.startsWith('competencias') || norm.startsWith('competências')) canonical = 'skills'
    else if (norm.startsWith('cursos') || norm.startsWith('certifica')) canonical = 'certifications'
    else if (norm.startsWith('idiomas') || norm.startsWith('languages') || norm.startsWith('linguas') || norm.startsWith('línguas')) canonical = 'languages'
    else if (norm.startsWith('interesses') || norm.startsWith('interests') || norm.startsWith('hobbies')) canonical = 'hobbies'
    if (canonical) {
      headerPositions.push({ idx: hMatch.index, name, canonical })
    }
  }

  if (headerPositions.length === 0) return result

  // Constrói mapa: section → texto da seção (entre seu header e o próximo).
  const sections: Record<string, string> = {}
  for (let i = 0; i < headerPositions.length; i++) {
    const cur = headerPositions[i]
    const next = headerPositions[i + 1]
    const start = cur.idx + cur.name.length
    const end = next ? next.idx : flat.length
    const content = flat.slice(start, end).trim()
    sections[cur.canonical] = (sections[cur.canonical] ?? '') + ' ' + content
  }

  // === SUMÁRIO ===
  if (sections.summary) {
    result.summary = sections.summary.trim().slice(0, 800)
  }

  // === EXPERIÊNCIAS ===
  if (sections.experiences) {
    const exps = _parsePeriodicalSection(sections.experiences, 'role', 'company')
    result.experiences = exps.map((e) => ({
      role: e.a,
      company: e.b,
      period: e.period,
      description: e.description,
    })).filter((e) => e.role && e.company)
  }

  // === FORMAÇÃO ===
  if (sections.education) {
    const edus = _parsePeriodicalSection(sections.education, 'degree', 'institution')
    result.education = edus.map((e) => ({
      degree: e.a,
      institution: e.b,
      period: e.period,
      details: e.description,
    })).filter((e) => e.degree && e.institution)
  }

  // === SKILLS ===
  if (sections.skills) {
    // Skills no texto flat: separadas por padrões como "ItemA ItemB" onde
    // cada item começa com letra maiúscula. Heurística: split em pontos
    // onde encontra letra Maiúscula precedida por letra minúscula (boundary).
    // Ex: "Domínio do Pacote Office Conhecimento básico em Excel" →
    // ["Domínio do Pacote Office", "Conhecimento básico em Excel"]
    const flatSkills = sections.skills.trim()
    // Split em fronteiras (palavra minúscula seguida de espaço + palavra Maiúscula).
    // Cuidado: pode haver false-positives em proper nouns dentro de uma skill ("Pacote Office").
    // Estratégia conservadora: split em PADRÕES de início de skill ("Domínio do", "Conhecimento", "Habilidade", "Experiência com", "Capacidade", "Comunicação", "Gestão", "Negociação", verbos no infinitivo).
    const skillStarters = /(?<=[a-záéíóúâêôãõç])\s+(?=(?:Domínio|Conhecimento|Habilidade|Experiência|Experience|Capacidade|Comunicação|Gestão|Negociação|Inglês|Português|Espanhol|Francês|English|Portuguese|Spanish|French|Análise|Liderança|Liderança|Adaptabilidade|Proatividade|Resolução|Trabalho)\b)/g
    const skillItems = flatSkills.split(skillStarters)
    // Fallback se o split deu só 1 item: usa o texto inteiro como uma skill OU
    // tenta split por capitalização agressivo
    if (skillItems.length === 1) {
      // Tenta um split por: ". " ou ", " ou múltiplos espaços
      const altSplit = flatSkills.split(/(?:\.|;|,|  +)/).map((s) => s.trim()).filter(Boolean)
      result.skills = altSplit.filter((s) => s.length >= 3 && s.length <= 80).slice(0, 30)
    } else {
      result.skills = skillItems.map((s) => s.trim()).filter((s) => s.length >= 3 && s.length <= 80).slice(0, 30)
    }
  }

  // === CERTIFICAÇÕES → achievements ===
  // Formato: cada certificação separada por ponto/quebra. Usa marcador "▸"
  // pra separar título/instituição/ano dentro de cada item (renderização
  // bonita no template: título em negrito, resto em texto normal).
  if (sections.certifications) {
    const certText = sections.certifications.trim()
    if (certText.length > 5) {
      // Split por ano (4 dígitos) — cada certificação geralmente termina em ano
      const certItems = certText.split(/(?<=20\d{2})\s+(?=[A-ZÁÉÍÓÚÂÊÔÃÕÇ])/)
        .map((s) => s.trim())
        .filter((s) => s.length > 5)
        .slice(0, 8)
      if (certItems.length === 0) {
        result.achievements.push(certText.slice(0, 400))
      } else {
        for (const item of certItems) {
          // Tenta formatar: "Modelagem Financeira Wall Street Prep 2025" →
          // "Modelagem Financeira ▸ Wall Street Prep ▸ 2025"
          const yearMatch = item.match(/\b(20\d{2})\b\s*$/)
          if (yearMatch) {
            const year = yearMatch[1]
            const beforeYear = item.slice(0, item.length - yearMatch[0].length).trim()
            const words = beforeYear.split(/\s+/).filter(Boolean)
            // Lista de palavras que normalmente INICIAM nome de instituição
            // (split aqui se encontrar).
            const institutionStarters = new Set([
              'wall', 'fgv', 'usp', 'unicamp', 'insper', 'coursera', 'udemy',
              'fia', 'fiap', 'mackenzie', 'puc', 'esalq', 'esag', 'pucsp',
              'pucrj', 'pucrs', 'pucpr', 'unicid', 'fmu', 'sebrae', 'fiec',
              'fia', 'getulio', 'getúlio', 'fundacao', 'fundação',
              'harvard', 'mit', 'stanford', 'yale', 'princeton',
              'cambridge', 'oxford', 'imperial', 'lse',
            ])
            let splitAt = -1
            for (let i = 1; i < words.length; i++) {
              const norm = normalize(words[i])
              if (institutionStarters.has(norm)) {
                splitAt = i
                break
              }
            }
            if (splitAt === -1 && words.length >= 4) {
              // Fallback: split na metade pra baixo (floor) — funciona melhor
              // pra "Modelagem Financeira | Wall Street Prep" (2/3 split de 5
              // palavras) do que ceil que gera 3/2.
              splitAt = Math.floor(words.length / 2)
            } else if (splitAt === -1) {
              splitAt = Math.floor(words.length / 2)
            }
            if (splitAt >= 1 && splitAt < words.length) {
              const title = words.slice(0, splitAt).join(' ')
              const inst = words.slice(splitAt).join(' ')
              result.achievements.push(`${title} ▸ ${inst} ▸ ${year}`)
            } else {
              result.achievements.push(`${beforeYear} ▸ ${year}`)
            }
          } else {
            result.achievements.push(item.slice(0, 400))
          }
        }
      }
    }
  }

  // === PROJETOS → achievements ===
  // Estratégia: split por VERBO em primeira pessoa do passado (Gerenciei,
  // Desenvolvi, Criei, Liderei, etc.). Cada verbo marca o início de uma
  // descrição. Texto entre verbos = título + role do próximo projeto.
  if (sections.projects) {
    const projText = sections.projects.trim()
    if (projText.length > 10) {
      const projects = _parseProjectsStructured(projText)
      if (projects.length === 0) {
        // Fallback: dumb push of full content
        result.achievements.push(projText.slice(0, 600))
      } else {
        for (const p of projects) {
          // Marcador ▸ separa as 3 partes pro template renderizar bonito
          const parts = [p.title, p.role, p.description].filter((s) => s.trim().length > 0)
          result.achievements.push(parts.join(' ▸ '))
        }
      }
    }
  }

  // === IDIOMAS → adiciona em skills ===
  if (sections.languages) {
    const langText = sections.languages.trim()
    // Idiomas geralmente vêm em formato "Idioma - Nível" separados por linha/ponto
    const langItems = langText
      .split(/(?:\.|;|,|  +)/)
      .map((s) => s.trim())
      .filter((s) => s.length >= 3 && s.length <= 50)
      .slice(0, 5)
    for (const l of langItems) {
      if (!result.skills.some((s) => normalize(s) === normalize(l))) {
        result.skills.push(l)
      }
    }
  }

  // === INTERESSES ===
  if ((sections as any).hobbies) {
    const interestsText = (sections as any).hobbies.trim()
    if (interestsText.length > 3) {
      result.interests = interestsText
        .split(/[,;]/)
        .map((s) => s.trim())
        .filter((s) => s.length >= 3 && s.length <= 60)
        .slice(0, 8)
    }
  }

  return result
}

/**
 * Lê dados do user e monta o InputResume canônico.
 *
 * Sources:
 * - user_profiles.gamification_data.imported_resume.parsed (se vier do parser)
 * - user_profiles.gamification_data.whoIAm.derived (skills/summary/interests)
 * - user_profiles (name, email, etc.)
 * - PRE-PARSER do raw_text (fallback quando parsed/whoIAm não existem)
 *
 * Se o user não tem nada (perfil vazio), retorna null.
 */
function buildInputResume(profile: any): InputResume | null {
  const gd = profile?.gamification_data ?? {}
  const whoIAm = gd?.whoIAm?.derived ?? {}
  const imported = gd?.imported_resume ?? {}
  const parsed = imported?.parsed ?? {}
  const rawCvText: string = typeof imported.raw_text === 'string' ? imported.raw_text : ''

  // F2 da reformulação: prefere `parsed` (estruturado via parse-cv edge
  // function com GPT-4o-mini) sobre o pre-parser regex legacy. Quando o
  // parsed tem dados suficientes (>0 experiences OU >0 education OU
  // >=3 skills), PULA `preParseRawCv` completamente — evita rodar 255
  // linhas de regex frágeis sobre o raw_text e ganhar resultados
  // contaminados pelo pre-parser quando o parser estruturado já trouxe
  // dados limpos. Logamos `input_source` pra cohort comparison em
  // PostHog ($ai_generation extras.input_source).
  const parsedHasExperiences = Array.isArray(parsed.experiences) && parsed.experiences.length > 0
  const parsedHasEducation = Array.isArray(parsed.education) && parsed.education.length > 0
  const parsedHasSkills = Array.isArray(parsed.skills) && parsed.skills.length >= 3
  const useParsedAsPrimary = parsedHasExperiences || parsedHasEducation || parsedHasSkills

  const pre: PreParsedCv = useParsedAsPrimary
    ? { experiences: [], education: [], skills: [], achievements: [], interests: [] }
    : (rawCvText.length > 100 ? preParseRawCv(rawCvText) : {
        experiences: [], education: [], skills: [], achievements: [], interests: [],
      })

  const inputSource = useParsedAsPrimary
    ? 'parsed_v2'
    : (rawCvText.length > 100 ? 'pre_parser_legacy' : 'profile_only')
  console.log(`[adapt-resume] input_source=${inputSource} ` +
    `parsedExp=${(Array.isArray(parsed.experiences) ? parsed.experiences.length : 0)} ` +
    `parsedEdu=${(Array.isArray(parsed.education) ? parsed.education.length : 0)} ` +
    `parsedSkills=${(Array.isArray(parsed.skills) ? parsed.skills.length : 0)}`)

  // Nome: preferência pelo MAIS COMPLETO entre pre-parsed e profile.name.
  // Apple SignIn frequentemente dá só "primeiro último" sem nome do meio,
  // enquanto o CV bruto tem o nome completo. Pega o que tiver mais palavras.
  const candidateNames = [
    String(parsed.fullName ?? '').trim(),
    String(pre.fullName ?? '').trim(),
    String(profile?.name ?? '').trim(),
  ].filter(Boolean)
  let fullName = ''
  for (const n of candidateNames) {
    const words = n.split(/\s+/).filter(Boolean).length
    const curWords = fullName.split(/\s+/).filter(Boolean).length
    if (words > curWords) fullName = n
  }
  if (!fullName && candidateNames.length > 0) fullName = candidateNames[0]
  const email = String(parsed.email ?? pre.email ?? profile?.email ?? '').trim()
  const phone = String(parsed.phone ?? pre.phone ?? profile?.phone ?? '').trim()
  const linkedin = String(parsed.linkedin ?? pre.linkedin ?? '').trim()
  const location = String(parsed.location ?? pre.location ?? profile?.location ?? '').trim()
  const language = String(parsed.language ?? 'pt')

  // Resumo: prefere o do parser; depois pre-parser; depois whoIAm.summary.
  const summary = String(parsed.summary ?? pre.summary ?? whoIAm.summary ?? '').trim().slice(0, 600)

  // Skills: junta as estruturadas (whoIAm) com as do parser e do pre-parser, dedup.
  const skillsSet = new Set<string>()
  if (Array.isArray(parsed.skills)) parsed.skills.forEach((s: any) => s && skillsSet.add(String(s).trim()))
  for (const s of pre.skills) if (s) skillsSet.add(s.trim())
  if (whoIAm.skills) {
    String(whoIAm.skills)
      .split(/[,;\n]/)
      .map((s) => s.trim())
      .filter(Boolean)
      .forEach((s) => skillsSet.add(s))
  }
  const skills = Array.from(skillsSet).filter((s) => s.length > 0).slice(0, 30)

  const parsedExperiences: InputExperience[] = Array.isArray(parsed.experiences)
    ? parsed.experiences.map((e: any) => ({
        role: String(e?.role ?? '').trim(),
        company: String(e?.company ?? '').trim(),
        period: String(e?.period ?? '').trim(),
        description: String(e?.description ?? '').trim(),
        location: e?.location ? String(e.location).trim() : undefined,
      })).filter((e: InputExperience) => e.role && e.company)
    : []
  // Se parsed.experiences está vazio mas o pre-parser achou, usa o pre.
  const experiences: InputExperience[] = parsedExperiences.length > 0 ? parsedExperiences : pre.experiences

  const parsedEducation: InputEducation[] = Array.isArray(parsed.education)
    ? parsed.education.map((e: any) => ({
        degree: String(e?.degree ?? '').trim(),
        institution: String(e?.institution ?? '').trim(),
        period: String(e?.period ?? '').trim(),
        details: e?.details ? String(e.details).trim() : undefined,
        location: e?.location ? String(e.location).trim() : undefined,
      })).filter((e: InputEducation) => e.degree && e.institution)
    : []
  const education: InputEducation[] = parsedEducation.length > 0 ? parsedEducation : pre.education

  const parsedAchievements: string[] = Array.isArray(parsed.achievements)
    ? parsed.achievements.map((a: any) => String(a).trim()).filter(Boolean).slice(0, 10)
    : []
  const achievements: string[] = parsedAchievements.length > 0 ? parsedAchievements : pre.achievements

  const interestsRaw = parsed.interests ?? whoIAm.interests
  const interestsFromParsed: string[] = Array.isArray(interestsRaw)
    ? interestsRaw.map((s: any) => String(s).trim()).filter(Boolean)
    : (typeof interestsRaw === 'string'
        ? interestsRaw.split(/[,;\n]/).map((s: string) => s.trim()).filter(Boolean)
        : [])
  const interests: string[] = interestsFromParsed.length > 0 ? interestsFromParsed : pre.interests

  // Sanity: pra adaptar com qualidade, precisa ter NOME + alguma fonte de
  // conteúdo (experiência estruturada, skills, resumo, ou CV importado com
  // texto razoável). Só nome do auth não basta — a IA inventaria experiência
  // pra "preencher" e o validador rejeitaria. Melhor falhar cedo com
  // mensagem amigável.
  const rawCvLen = typeof imported.raw_text === 'string' ? imported.raw_text.length : 0
  const hasContent =
    experiences.length > 0 ||
    education.length > 0 ||
    skills.length >= 3 ||
    summary.length >= 50 ||
    rawCvLen >= 500
  const hasMinData = fullName.length > 0 && hasContent
  if (!hasMinData) return null

  // Keyword pool pra validar skills/conteúdo.
  const keywordPool = new Set<string>()
  for (const s of skills) tokenize(s).forEach((t) => keywordPool.add(t))
  for (const e of experiences) {
    tokenize(`${e.role} ${e.company} ${e.description}`).forEach((t) => keywordPool.add(t))
  }
  for (const e of education) {
    tokenize(`${e.degree} ${e.institution} ${e.details ?? ''}`).forEach((t) => keywordPool.add(t))
  }
  for (const a of achievements) tokenize(a).forEach((t) => keywordPool.add(t))
  if (summary) tokenize(summary).forEach((t) => keywordPool.add(t))
  if (typeof imported.raw_text === 'string') {
    tokenize(imported.raw_text.slice(0, 6000)).forEach((t) => keywordPool.add(t))
  }

  return {
    fullName,
    email,
    phone,
    linkedin,
    location,
    language,
    summary,
    skills,
    experiences,
    education,
    achievements,
    interests,
    keywordPool,
    importedCvText: typeof imported.raw_text === 'string' ? imported.raw_text : undefined,
  }
}

/// Normaliza string pra cache hash: lowercase + trim + collapse whitespace.
/// Por quê: pré-fix, cache_hit_rate era ~15% (5 hits de 33 adaptações totais
/// na janela analisada). Pequenas variações ("React.js" vs "react.js",
/// dois espaços vs um, espaço no fim) faziam usuários equivalentes
/// gerarem hashes diferentes e pagarem IA repetidamente.
function _normH(s: string | undefined | null): string {
  if (!s) return ''
  return s
    .toLowerCase()
    .trim()
    .replace(/\s+/g, ' ')
}

function pickInputForHash(input: InputResume): string {
  return JSON.stringify({
    n: _normH(input.fullName),
    e: _normH(input.email),
    // Skills sorted+normalized — order não importa pra cache key.
    sk: [...input.skills].map(_normH).filter((s) => s.length > 0).sort(),
    sm: _normH(input.summary),
    ex: input.experiences.map((e) => ({
      r: _normH(e.role),
      c: _normH(e.company),
      p: _normH(e.period),
      d: _normH(e.description),
    })),
    ed: input.education.map((e) => ({
      d: _normH(e.degree),
      i: _normH(e.institution),
      p: _normH(e.period),
    })),
    ac: [...input.achievements].map(_normH).filter((s) => s.length > 0).sort(),
    cvLen: input.importedCvText?.length ?? 0,
    cvHead: _normH((input.importedCvText ?? '').slice(0, 200)),
  })
}

// ────────────────────────────────────────────────────────────────────────────
// Prompt
// ────────────────────────────────────────────────────────────────────────────

const SYSTEM_PROMPT = `Você é um especialista em adaptar currículos brasileiros para vagas específicas. Seu trabalho é REORDENAR e REFORMULAR conteúdo para destacar o que é mais relevante pra vaga — NUNCA adicionar informação que não esteja no input.

REGRAS INVIOLÁVEIS:
1. NÃO INVENTE NADA. Se não está nos dados do candidato, NÃO existe.
2. Nome, email, telefone, LinkedIn, localização: copie EXATAMENTE como está.
3. Empresas, cargos, instituições, diplomas, períodos: copie EXATAMENTE.
4. Bullets de experiência: você pode REFORMULAR pra destacar palavras-chave da vaga, mas o FATO descrito tem que vir do bullet original. Não invente métricas, projetos, ou tecnologias que não estavam lá.
5. Skills: você pode REORDENAR (pôr as relevantes pra vaga primeiro) e REMOVER irrelevantes. NÃO pode adicionar skill que não está no pool original.
6. Resumo profissional: pode reescrever pra destacar fit com a vaga, mas só usando informação do input (área de formação, experiências reais, skills reais).
7. ARRAYS VAZIOS PERMANECEM VAZIOS, EXCETO quando há CV bruto: se "Experiências/Skills atuais" estão vazios mas "CV importado (texto bruto)" foi fornecido, EXTRAIA de lá os dados (empresas, cargos, períodos, skills, formação). Se NEM os campos estruturados NEM o CV bruto trazem informação sobre algo, output desse campo = []. NUNCA invente.
8. Quando extrair do CV bruto: copie nomes de empresas, instituições e cargos EXATAMENTE como aparecem no CV. Não traduza, não abrevie. Períodos: copie no formato em que aparecem.
9. Se o input tem pouca informação, retorne o que TEM, sem completar. Currículo curto e honesto > currículo cheio e inventado.
10. ÁREA DE FORMAÇÃO E STACK TECNOLÓGICO: NUNCA invente área de formação, curso ou stack tecnológico do candidato. Se o CV diz "Administração", o candidato NÃO é "Engenharia da Computação". Se o CV não menciona "Windows" ou "Java", você NÃO PODE incluir essas tecnologias em lugar nenhum (nem no resumo, nem nos bullets, nem nas skills). O resumo profissional DEVE refletir a área REAL do candidato — adaptar o "fit" com a vaga significa destacar como a área dele pode ser útil pra vaga, NÃO transformar ele em outra pessoa.
11. RESUMO PROFISSIONAL — cada substantivo concreto (área de estudo, tecnologia, ferramenta, indústria, idioma) que aparecer NO RESUMO precisa estar PRESENTE textualmente no CV original. Se o CV não fala em "Testes de Software", NÃO pode escrever "experiência em Testes de Software" no resumo. Pode escrever apenas "interesse em [área da vaga]" se quiser puxar pro fit — mas nunca afirmar experiência/conhecimento que não existe.
12. PRESERVE TODAS AS EXPERIÊNCIAS DO CV. Nunca remova, oculte ou substitua experiências. Se o CV traz "CEO @ Stage, Dez 2025-Atual" com bullets sobre app gamificado, a versão adaptada DEVE manter exatamente "CEO @ Stage, Dez 2025-Atual" como uma das experiências (com role, company E period preenchidos) — você pode REFORMULAR os bullets pra puxar fit com a vaga, mas o FATO (cargo, empresa, período, projeto descrito) tem que vir do CV. NUNCA crie uma experiência fake alinhada com a vaga pra "encaixar melhor". Se o CV tem 1 experiência só, retorne 1 experiência. Se tem 3, retorne 3 — com os mesmos cargos/empresas/períodos/datas.
13. PRESERVE TODAS AS SEÇÕES DO CV. Se o CV tem PROJETOS, FORMAÇÃO, CERTIFICAÇÕES, IDIOMAS, INTERESSES — todas devem aparecer no output. Achievements/Conquistas podem agregar projetos+certificações. Interests no output deve vir dos INTERESSES do CV. Educação deve vir da seção FORMAÇÃO. NÃO DROPE seções por achar que "não são relevantes pra vaga" — isso é decisão do recrutador, não sua.
14. PRESERVE DADOS DE CONTATO. Se o CV tem telefone, LinkedIn, localização — copie EXATAMENTE no output. Telefone, LinkedIn e localização do CV PRECISAM aparecer no output (phone, linkedin, location). NUNCA retorne esses campos vazios se o CV os contém.
15. BULLETS DE EXPERIÊNCIA: cada palavra concreta (substantivo, nome próprio, tecnologia, métrica) do bullet adaptado tem que vir de palavras presentes no CV (não da vaga). A vaga é só pra DESTACAR o que já existe — não pra INVENTAR métricas, projetos, tecnologias ou números. Se o CV diz "Desenvolvi app gamificado", você pode escrever "Desenvolveu app gamificado que ajudou candidatos a se prepararem pra entrevistas" SE o CV mencionar isso. NUNCA escreva "Apoiou análise de sell in/out" se o CV não mencionar sell in/out.

LIMITES:
- Bullets por experiência: no máximo o mesmo número que o original (pode ser menos, nunca mais).
- Skills: máximo 12 (priorize as relevantes pra vaga).
- Mudanças explicáveis (campo "changes"): no máximo 6 — só as mais impactantes. Cada change tem reason curto (≤80 chars).

OUTPUT JSON ESTRITO conforme schema fornecido.

Tom: PT-BR profissional. Bullets em português, método Harvard (verbo no pretérito ou gerúndio + ação + impacto/contexto).`

interface JobContext {
  title: string
  company: string
  area: string
  jobType: string
  workModel: string
  location: string
  description: string
  requirements: string[]
}

function buildUserPrompt(input: InputResume, job: JobContext, extraSkills: string[] = []): string {
  const lines: string[] = []

  // Detecta modo: structured (tem experiências/educação parseadas) ou
  // cv-only (só raw_text). No CV-only, o `profile.name` pode estar
  // desatualizado (ex: "da ava" placeholder) enquanto o CV traz o nome
  // real. Então NÃO impomos profile.fullName como imutável — instruímos
  // a IA a extrair tudo do CV.
  const hasStructured =
    input.experiences.length > 0 ||
    input.education.length > 0 ||
    input.skills.length > 0
  const cvOnly = !hasStructured && !!input.importedCvText && input.importedCvText.length > 100

  lines.push('## CURRÍCULO ORIGINAL DO CANDIDATO (fonte de verdade)')
  lines.push('')

  if (cvOnly) {
    // No modo CV-only, o CV bruto É a fonte de verdade. Tudo vem dele.
    lines.push('### CV importado (texto bruto extraído do PDF — fonte de verdade absoluta)')
    lines.push('EXTRAIA do texto abaixo: nome completo, email, telefone, LinkedIn, localização, resumo, skills, experiências (com bullets), formação. Não invente nada que não esteja aqui. Não use dados de outras fontes.')
    lines.push('')
    lines.push('REGRA CRÍTICA PARA SKILLS: Liste APENAS skills que aparecem TEXTUALMENTE no CV abaixo, palavra por palavra. NÃO infira skills correlatas (ex: se o CV diz "Gestão de projetos", você NÃO pode adicionar "Organização", "Liderança" ou "Planejamento" — só pode usar "Gestão de projetos" como está). Copie skills EXATAMENTE como escritas no CV.')
    lines.push('')
    lines.push('REGRA CRÍTICA PARA EXPERIÊNCIAS: Use APENAS empresas/cargos/períodos que aparecem TEXTUALMENTE no CV. Se o CV diz "CEO @ Stage", retorne EXATAMENTE "CEO" e "Stage" — não invente subtítulos nem mude palavras.')
    lines.push('')
    lines.push('REGRA CRÍTICA PARA LOCALIZAÇÃO/CONTATO: A localização, telefone, email, LinkedIn do CANDIDATO são os que estão no TOPO do CV abaixo. NUNCA copie a localização da VAGA pro candidato. Se o CV diz "Londrina - PR", a localização do candidato é "Londrina - PR" (NÃO a da vaga).')
    lines.push('')
    lines.push('🚨 CHECKLIST DE PRESERVAÇÃO OBRIGATÓRIA — antes de retornar, confirme que cada campo abaixo está PRESENTE no output, exatamente como aparece no CV:')
    lines.push('  ☐ fullName (nome completo, incluindo nome do meio se houver — ex: "Zac Kouri Lopes", NÃO "Zac Lopes")')
    lines.push('  ☐ email (o que está NO CV, não outro — se o CV mostra "joao@gmail.com", retorne "joao@gmail.com")')
    lines.push('  ☐ phone (telefone do CV — preservar formato "(43) 99126-0202")')
    lines.push('  ☐ linkedin (URL do CV)')
    lines.push('  ☐ location (cidade-UF do CV — ex: "Londrina - PR")')
    lines.push('  ☐ summary (resumo reformulado mas com a MESMA área/curso/empresa do CV)')
    lines.push('  ☐ skills (TODAS as skills do CV, reordenadas — não pode descartar nenhuma a menos que seja claramente irrelevante)')
    lines.push('  ☐ experiences (TODA experiência do CV preservada com role+company+period; bullets reformulados mas FATO original)')
    lines.push('  ☐ education (TODA formação do CV preservada com degree+institution+period)')
    lines.push('  ☐ achievements (projetos + certificações do CV agregados aqui)')
    lines.push('  ☐ interests (interesses do CV)')
    lines.push('Se algum item acima existe no CV mas você retornar vazio/diferente, sua resposta SERÁ REJEITADA. Currículo adaptado = MESMO conteúdo do original, reorganizado pra vaga.')
    lines.push('')
    lines.push('⚠️ IMPORTANTE: experiências que parecem "fora do tema" da vaga AINDA DEVEM aparecer no output. Você NÃO PODE remover experiências por achar que "não são relevantes" — adapte os bullets pra puxar fit com a vaga ou simplesmente preserve como está. Currículo sem experiência = adaptação inválida.')
    lines.push('')
    lines.push('📌 EXEMPLO de EXTRAÇÃO CORRETA — se o CV bruto contém este trecho (cada palavra em linha separada por causa do PDF extraction):')
    lines.push('```')
    lines.push('EXPERIÊNCIA')
    lines.push('PROFISSIONAL')
    lines.push('CEO')
    lines.push('Stage')
    lines.push('Dez 2025 - Atual')
    lines.push('• Desenvolvi um aplicativo gamificado para criação de currículos...')
    lines.push('• Consegui fechar uma venda para a maior faculdade de empreendedorismo do Brasil.')
    lines.push('FORMAÇÃO')
    lines.push('Administração')
    lines.push('Link School of Business')
    lines.push('Fev 2026 - Fev 2030')
    lines.push('```')
    lines.push('')
    lines.push('Você DEVE retornar (formato JSON):')
    lines.push('```json')
    lines.push('{')
    lines.push('  "experiences": [')
    lines.push('    {')
    lines.push('      "role": "CEO",')
    lines.push('      "company": "Stage",')
    lines.push('      "period": "Dez 2025 - Atual",')
    lines.push('      "description": "• Desenvolveu app gamificado para currículos, [bullet original reformulado pra puxar fit com vaga].\\n• Fechou venda para maior faculdade de empreendedorismo do Brasil.",')
    lines.push('      "location": ""')
    lines.push('    }')
    lines.push('  ],')
    lines.push('  "education": [')
    lines.push('    {')
    lines.push('      "degree": "Administração",')
    lines.push('      "institution": "Link School of Business",')
    lines.push('      "period": "Fev 2026 - Fev 2030",')
    lines.push('      "details": "",')
    lines.push('      "location": ""')
    lines.push('    }')
    lines.push('  ]')
    lines.push('}')
    lines.push('```')
    lines.push('NUNCA retorne `"experiences": []` se o CV tem uma seção EXPERIÊNCIA. NUNCA retorne `"education": []` se o CV tem FORMAÇÃO.')
    lines.push('')
    lines.push('---')
    lines.push(input.importedCvText!.slice(0, 5000))
    lines.push('---')
  } else {
    // Modo structured: dados pessoais do profile são fonte de verdade.
    lines.push('### Dados pessoais (IMUTÁVEIS — copie exato)')
    lines.push(`Nome: ${input.fullName}`)
    if (input.email) lines.push(`Email: ${input.email}`)
    if (input.phone) lines.push(`Telefone: ${input.phone}`)
    if (input.linkedin) lines.push(`LinkedIn: ${input.linkedin}`)
    if (input.location) lines.push(`Localização: ${input.location}`)

    if (input.summary) {
      lines.push('')
      lines.push('### Resumo atual')
      lines.push(input.summary)
    }

    if (input.skills.length > 0) {
      lines.push('')
      lines.push('### Skills atuais (você pode reordenar/remover, NÃO adicionar)')
      lines.push(input.skills.join(' | '))
    }

    if (input.experiences.length > 0) {
      lines.push('')
      lines.push('### Experiências (datas/empresas/cargos IMUTÁVEIS — bullets podem ser reformulados)')
      for (let i = 0; i < input.experiences.length; i++) {
        const e = input.experiences[i]
        lines.push(`[${i}] ${e.role} @ ${e.company} (${e.period}${e.location ? ', ' + e.location : ''})`)
        if (e.description) {
          const bullets = e.description.split('\n').map((b) => b.trim()).filter(Boolean)
          bullets.forEach((b) => lines.push(`    • ${b}`))
        }
      }
    }

    if (input.education.length > 0) {
      lines.push('')
      lines.push('### Formação (IMUTÁVEL)')
      input.education.forEach((e) => {
        lines.push(`- ${e.degree} @ ${e.institution} (${e.period}${e.location ? ', ' + e.location : ''})`)
        if (e.details) lines.push(`  ${e.details}`)
      })
    }

    if (input.achievements.length > 0) {
      lines.push('')
      lines.push('### Conquistas (IMUTÁVEL — pode reordenar/omitir)')
      input.achievements.forEach((a) => lines.push(`- ${a}`))
    }

    if (input.interests.length > 0) {
      lines.push('')
      lines.push(`### Interesses: ${input.interests.join(', ')}`)
    }
  }

  lines.push('')
  lines.push('## VAGA ALVO')
  lines.push(`Título: ${job.title}`)
  lines.push(`Empresa: ${job.company}`)
  lines.push(`Área: ${job.area}`)
  lines.push(`Tipo: ${job.jobType}`)
  lines.push(`Modelo: ${job.workModel}`)
  if (job.location) lines.push(`Localização: ${job.location}`)
  if (job.requirements.length > 0) {
    lines.push('Requisitos:')
    job.requirements.slice(0, 12).forEach((r) => lines.push(`  - ${r}`))
  }
  if (job.description) {
    lines.push('Descrição (resumida):')
    lines.push(job.description.slice(0, 1500))
  }

  if (extraSkills.length > 0) {
    lines.push('')
    lines.push('## SKILLS CONFIRMADAS PELO CANDIDATO (esqueceu de escrever no CV)')
    extraSkills.forEach((s) => lines.push(`- ${s}`))
    lines.push(
      'O candidato confirmou EXPLICITAMENTE que possui estas skills (ele as marcou na tela de confirmação antes desta adaptação). INCLUA cada uma em `resume.skills` exatamente como listadas (palavra por palavra). Estas skills SOBREPÕEM a regra "skills devem aparecer no CV" — elas vêm da confirmação direta do candidato. Mencione 1-2 delas em bullets de experiência quando fizer sentido pelo contexto, sem inventar nível de proficiência nem onde foi aplicada.',
    )
  }

  lines.push('')
  lines.push('## TAREFA')
  lines.push(
    'Adapte o currículo do candidato pra essa vaga. Reordene skills colocando as mais relevantes primeiro. Reformule bullets de experiência destacando palavras-chave dos requisitos quando possível (sem inventar). Ajuste o resumo pra puxar pra área da vaga (sem inventar). Liste em "changes" no máximo 6 mudanças (apenas as mais impactantes), cada uma com {field, label, before, after, reason}.',
  )
  lines.push('Retorne APENAS o JSON conforme o schema.')

  return lines.join('\n')
}

// ────────────────────────────────────────────────────────────────────────────
// JSON schema (response_format)
// ────────────────────────────────────────────────────────────────────────────

const JSON_SCHEMA = {
  name: 'adapted_resume',
  strict: true,
  schema: {
    type: 'object',
    additionalProperties: false,
    required: ['changes', 'resume'],
    properties: {
      changes: {
        type: 'array',
        maxItems: 6,
        items: {
          type: 'object',
          additionalProperties: false,
          required: ['field', 'label', 'before', 'after', 'reason'],
          properties: {
            field: { type: 'string' },
            label: { type: 'string' },
            before: { type: 'string' },
            after: { type: 'string' },
            reason: { type: 'string' },
          },
        },
      },
      resume: {
        type: 'object',
        additionalProperties: false,
        required: [
          'fullName', 'email', 'phone', 'linkedin', 'location', 'language',
          'summary', 'skills', 'experiences', 'education', 'achievements', 'interests',
        ],
        properties: {
          fullName: { type: 'string' },
          email: { type: 'string' },
          phone: { type: 'string' },
          linkedin: { type: 'string' },
          location: { type: 'string' },
          language: { type: 'string' },
          summary: { type: 'string' },
          skills: { type: 'array', items: { type: 'string' } },
          experiences: {
            type: 'array',
            items: {
              type: 'object',
              additionalProperties: false,
              required: ['role', 'company', 'period', 'description', 'location'],
              properties: {
                role: { type: 'string' },
                company: { type: 'string' },
                period: { type: 'string' },
                description: { type: 'string' },
                location: { type: 'string' },
              },
            },
          },
          education: {
            type: 'array',
            items: {
              type: 'object',
              additionalProperties: false,
              required: ['degree', 'institution', 'period', 'details', 'location'],
              properties: {
                degree: { type: 'string' },
                institution: { type: 'string' },
                period: { type: 'string' },
                details: { type: 'string' },
                location: { type: 'string' },
              },
            },
          },
          achievements: { type: 'array', items: { type: 'string' } },
          interests: { type: 'array', items: { type: 'string' } },
        },
      },
    },
  },
} as const

// ────────────────────────────────────────────────────────────────────────────
// OpenAI call
// ────────────────────────────────────────────────────────────────────────────

async function callOpenAI(
  systemPrompt: string,
  userPrompt: string,
  opts?: {
    model?: string
    maxTokens?: number
    temperature?: number
    schema?: unknown
  },
): Promise<{
  content: string
  totalTokens: number
  inputTokens: number
  outputTokens: number
  latencyMs: number
}> {
  const model = opts?.model ?? MODEL
  const maxTokens = opts?.maxTokens ?? 3500
  const temperature = opts?.temperature ?? 0.1
  const schema = opts?.schema ?? JSON_SCHEMA

  const ctrl = new AbortController()
  const timeout = setTimeout(() => ctrl.abort(), OPENAI_TIMEOUT_MS)
  const start = Date.now()

  try {
    const resp = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      signal: ctrl.signal,
      headers: {
        'Authorization': `Bearer ${Deno.env.get('OPENAI_API_KEY')}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model,
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userPrompt },
        ],
        temperature,
        max_tokens: maxTokens,
        response_format: { type: 'json_schema', json_schema: schema },
      }),
    })

    if (!resp.ok) {
      const errText = await resp.text()
      throw new Error(`OpenAI ${resp.status}: ${errText.slice(0, 400)}`)
    }
    const data = await resp.json()
    return {
      content: data.choices[0].message.content,
      totalTokens: data.usage?.total_tokens ?? 0,
      inputTokens: data.usage?.prompt_tokens ?? 0,
      outputTokens: data.usage?.completion_tokens ?? 0,
      latencyMs: Date.now() - start,
    }
  } finally {
    clearTimeout(timeout)
  }
}

// ────────────────────────────────────────────────────────────────────────────
// F5 da reformulação: step B — refinamento de summary + bullets via 4o
// ────────────────────────────────────────────────────────────────────────────

/**
 * Schema mínimo do step B: só os campos que serão reescritos. Todos os
 * outros (skills, experiences metadata, education, achievements, etc.)
 * passam direto do step A.
 */
const REFINE_JSON_SCHEMA = {
  name: 'refined_resume',
  strict: true,
  schema: {
    type: 'object',
    additionalProperties: false,
    required: ['summary', 'experience_descriptions'],
    properties: {
      summary: { type: 'string' },
      experience_descriptions: {
        type: 'array',
        items: {
          type: 'object',
          additionalProperties: false,
          required: ['index', 'description'],
          properties: {
            index: { type: 'integer' },
            description: { type: 'string' },
          },
        },
      },
    },
  },
} as const

const REFINE_SYSTEM_PROMPT = `Você é um editor sênior de currículos para vagas brasileiras. Recebe um currículo já adaptado por um modelo menor (rascunho) e refina APENAS dois campos: o "resumo profissional" (summary) e as descrições/bullets de cada experiência.

REGRAS INVIOLÁVEIS:
1. NÃO invente nada. Toda afirmação no summary ou bullets deve estar respaldada pelo CV original do candidato fornecido.
2. NÃO altere fatos: empresas, cargos, datas, instituições, números, métricas. Use exatamente o que está no rascunho.
3. Mantenha o MESMO número de bullets do rascunho em cada experiência. Não adicione, não remova.
4. Cada bullet deve começar com verbo de ação no passado (português) ou presente quando ongoing. Específico, mensurável quando possível.
5. Summary: 3-4 frases. Foco em fit com a vaga. Não repete bullets — sintetiza posicionamento.
6. Português natural, sem clichês ("dinâmico", "proativo", "team player").
7. Cada experiência tem um "index" no array original. Mantenha o index igual ao do rascunho.

OUTPUT: {summary, experience_descriptions: [{index, description}]}. NÃO inclua nenhum outro campo.`

/**
 * Constrói prompt do step B. Inclui:
 *  - vaga (contexto pra alinhar tom + palavras-chave)
 *  - CV bruto do candidato (referência anti-invenção)
 *  - rascunho do step A (summary + bullets pra refinar)
 */
function buildRefinePrompt(input: InputResume, job: JobContext, draft: any): string {
  const expBlock = (Array.isArray(draft.experiences) ? draft.experiences : [])
    .map((e: any, i: number) =>
      `[${i}] ${e.role ?? ''} @ ${e.company ?? ''} (${e.period ?? ''})\n${e.description ?? ''}`)
    .join('\n\n')

  const reqs = Array.isArray(job.requirements) ? job.requirements.join(' | ') : ''
  const rawCv = (input.importedCvText ?? '').slice(0, 4000)

  return `VAGA ALVO:
${job.title} @ ${job.company} (${job.area})
Requisitos: ${reqs}
Descrição: ${(job.description ?? '').slice(0, 800)}

CV ORIGINAL DO CANDIDATO (referência anti-invenção):
${rawCv}

RASCUNHO A REFINAR:

Summary atual:
"${draft.summary ?? ''}"

Experiências (numeradas):
${expBlock}

TAREFA: produza summary refinado (3-4 frases, foco em fit com a vaga) e descrições refinadas para CADA experiência. Mantenha o mesmo número de bullets de cada experiência. Não invente.`
}

/**
 * Step B: chama gpt-4o pra refinar summary + bullets do rascunho do step A.
 * Retorna o draft refinado OU null se falhou (caller usa o draft original).
 */
async function refineWithBigModel(
  input: InputResume,
  job: JobContext,
  draft: any,
  userId: string,
  fnStart: number,
): Promise<{ refined: any; tokensUsed: number; latencyMs: number } | null> {
  try {
    const userPrompt = buildRefinePrompt(input, job, draft)
    console.log(`[adapt-resume] step B calling ${MODEL_REFINE} (prompt ${userPrompt.length} chars)`)

    const ai = await callOpenAI(REFINE_SYSTEM_PROMPT, userPrompt, {
      model: MODEL_REFINE,
      maxTokens: 2000,
      temperature: 0.2,
      schema: REFINE_JSON_SCHEMA,
    })

    trackAIGeneration({
      userId,
      generationType: 'cv_adaptation_refine',
      model: MODEL_REFINE,
      inputTokens: ai.inputTokens,
      outputTokens: ai.outputTokens,
      latencyMs: ai.latencyMs,
      cached: false,
      extra: {
        prompt_chars: userPrompt.length,
        function_ms_so_far: Date.now() - fnStart,
        step: 'B',
      },
    }).catch(() => {})

    const parsed = JSON.parse(ai.content)
    if (typeof parsed?.summary !== 'string' || !Array.isArray(parsed?.experience_descriptions)) {
      console.warn('[adapt-resume] step B output shape inválido — usando step A direto')
      return null
    }

    // Aplica refinamentos no draft: substitui summary e descriptions.
    const refined = { ...draft }
    refined.summary = parsed.summary
    refined.experiences = Array.isArray(draft.experiences)
      ? draft.experiences.map((e: any, i: number) => {
          const match = parsed.experience_descriptions.find((d: any) => d.index === i)
          if (match && typeof match.description === 'string' && match.description.length > 10) {
            return { ...e, description: match.description }
          }
          return e
        })
      : draft.experiences

    return { refined, tokensUsed: ai.totalTokens, latencyMs: ai.latencyMs }
  } catch (e) {
    console.warn(`[adapt-resume] step B failed (non-fatal): ${(e as Error).message}`)
    return null
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Validador anti-invenção
// ────────────────────────────────────────────────────────────────────────────

class ValidationError extends Error {
  constructor(public field: string, msg: string) {
    super(`${field}: ${msg}`)
  }
}

function bulletCount(description: string): number {
  return description.split('\n').map((s) => s.trim()).filter(Boolean).length
}

/**
 * Garante que a resposta da IA não inventou nada que comprometa a integridade
 * do currículo. Throws ValidationError no primeiro problema encontrado.
 */
function validateAdaptation(input: InputResume, parsed: any, job?: JobContext): void {
  const r = parsed?.resume
  if (!r || typeof r !== 'object') throw new ValidationError('resume', 'objeto ausente')

  // Modo de validação:
  // - "structured": user tem experiências/educação estruturadas → matching
  //   estrito por (company, role) / (institution, degree).
  // - "cv-only": user só tem raw_text do CV → validamos que cada empresa /
  //   instituição / nome / email da resposta APARECE como substring
  //   (normalizada + whitespace flat) no CV. Isso evita invenção sem exigir
  //   parser perfeito.
  //
  // Usamos `flatten` (que colapsa whitespace) pra comparar contra raw_text
  // do PDF — o extractor costuma quebrar cada palavra em \n separado, então
  // `normalize()` puro não bateria em "Liga de Mercado Financeiro" vs
  // "Liga\nde\nMercado\nFinanceiro".
  const cvFlat = input.importedCvText ? flatten(input.importedCvText) : ''
  const hasStructuredExperiences = input.experiences.length > 0
  const hasStructuredEducation = input.education.length > 0
  const cvOnlyMode = !hasStructuredExperiences && !hasStructuredEducation && !!cvFlat

  // 0. INTEGRIDADE ESTRUTURAL — aplica em AMBOS os modos (cv-only e structured).
  //
  // Validator era cego pra "sumiço": se a IA retornasse arrays vazios e
  // campos em branco, passava. Resultado: usuário com CV completo (formação,
  // 3 experiências, certificações, idiomas, interesses) recebia um adaptado
  // só com "name + email + summary + 4 skills inventadas".
  //
  // Checks que valem em qualquer modo:
  // - Se input.experiences > 0, output.experiences > 0 (não dropar tudo)
  // - Se input.education > 0, output.education > 0
  // - Se input.achievements > 0, output.achievements > 0
  // - Auto-correct: experience/education location vazia no input força vazia no output
  if (Array.isArray(input.experiences) && input.experiences.length > 0) {
    if (!Array.isArray(r.experiences) || r.experiences.length === 0) {
      throw new ValidationError(
        'experiences',
        `input tinha ${input.experiences.length} experiência(s) mas output está vazio`,
      )
    }
  }
  if (Array.isArray(input.education) && input.education.length > 0) {
    if (!Array.isArray(r.education) || r.education.length === 0) {
      throw new ValidationError(
        'education',
        `input tinha ${input.education.length} formação(ões) mas output está vazio`,
      )
    }
  }
  // Achievements: auto-restore em vez de rejeitar. Mesmo tratamento de
  // interests (campo opcional). Pré-fix rejeitava com 422 quando o
  // pre-parser detectava 1 conquista no raw_text mas a IA não conseguia
  // identificá-la para reescrever — caso comum quando o pre-parser
  // tropeça em bullets ambíguos. Auto-restore mantém os achievements do
  // input no output, o pior caso é uma versão sem reescrita pela IA.
  if (Array.isArray(input.achievements) && input.achievements.length > 0) {
    if (!Array.isArray(r.achievements) || r.achievements.length === 0) {
      console.warn(
        `[adapt-resume] achievements dropped: input had ${input.achievements.length}, output empty. Auto-restoring from input.`,
      )
      r.achievements = input.achievements
    }
  }
  // Interests: mais leniente (alguns CVs nem têm). Só checa se input tinha.
  if (Array.isArray(input.interests) && input.interests.length > 0) {
    if (!Array.isArray(r.interests) || r.interests.length === 0) {
      console.warn(
        `[adapt-resume] interests dropped: input had ${input.interests.length}, output empty. Auto-restoring from input.`,
      )
      r.interests = input.interests
    }
  }

  // Cv-only-specific checks (sem dados estruturados de input, valida contra cvFlat)
  if (cvOnlyMode) {
    const expMarkers = ['experiencia profissional', 'experience', 'experiencias']
    const cvHasExperienceSection = expMarkers.some((m) => cvFlat.includes(m))
    if (cvHasExperienceSection && (!Array.isArray(r.experiences) || r.experiences.length === 0)) {
      throw new ValidationError(
        'experiences',
        'CV contém seção de experiência mas o output está vazio',
      )
    }

    const eduMarkers = ['formacao', 'formação', 'educacao', 'educação', 'education', 'graduation', 'bacharel', 'bachelor', 'tecnologo', 'tecnólogo', 'mestrado', 'graduacao', 'graduação']
    const cvHasEducationSection = eduMarkers.some((m) => cvFlat.includes(m))
    if (cvHasEducationSection && (!Array.isArray(r.education) || r.education.length === 0)) {
      throw new ValidationError(
        'education',
        'CV contém seção de formação mas o output está vazio',
      )
    }
  }

  // Dados de contato sempre validados (qualquer modo) se o CV bruto tem.
  if (cvFlat) {
    const phoneRegex = /\(?\d{2}\)?\s*\d{4,5}[\s\-]?\d{4}/
    const cvHasPhone = phoneRegex.test(input.importedCvText ?? '')
    if (cvHasPhone && (!r.phone || String(r.phone).trim().length < 8)) {
      // Tenta auto-restaurar do input antes de rejeitar.
      if (input.phone) {
        console.warn(`[adapt-resume] phone dropped, auto-restoring from input: ${input.phone}`)
        r.phone = input.phone
      } else {
        throw new ValidationError('phone', 'CV tem telefone mas output está vazio')
      }
    }

    const emailRegex = /[a-z0-9._-]+@[a-z0-9.-]+\.[a-z]{2,}/i
    const cvHasEmail = emailRegex.test(input.importedCvText ?? '')
    if (cvHasEmail && (!r.email || !emailRegex.test(String(r.email)))) {
      if (input.email) {
        console.warn(`[adapt-resume] email dropped, auto-restoring: ${input.email}`)
        r.email = input.email
      } else {
        throw new ValidationError('email', 'CV tem email válido mas output não tem')
      }
    }

    const locRegex = /[A-Z][a-záéíóúâêôãõç]+\s*[-–]\s*[A-Z]{2}\b/
    const cvHasLocation = locRegex.test(input.importedCvText ?? '')
    if (cvHasLocation && (!r.location || String(r.location).trim().length < 4)) {
      if (input.location) {
        console.warn(`[adapt-resume] location dropped, auto-restoring: ${input.location}`)
        r.location = input.location
      } else {
        throw new ValidationError('location', 'CV tem localização mas output está vazio')
      }
    }

    // LinkedIn: se input tem, output deve ter
    if (input.linkedin && (!r.linkedin || String(r.linkedin).trim().length < 5)) {
      console.warn(`[adapt-resume] linkedin dropped, auto-restoring: ${input.linkedin}`)
      r.linkedin = input.linkedin
    }
  }

  // Auto-correct: localização de experiência/educação não pode vir do nada.
  // Regra original: se input não tem location, zerava o output. Problema:
  // o pre-parser frequentemente perde a coluna direita do PDF (onde
  // localizações costumam estar), e o output da IA era apagado mesmo
  // quando a location realmente existe no raw_text bruto. Agora aceita a
  // location se: (a) bate com input estruturado OU (b) aparece em algum
  // lugar do cvFlat. Só limpa quando NENHUMA das duas condições se cumpre
  // — aí sim é invenção. Companies/instituições são comparadas via
  // `eqInstitutional` para tolerar pontuação alucinada pela IA.
  if (Array.isArray(r.experiences)) {
    for (const exp of r.experiences) {
      if (exp.location && String(exp.location).trim().length > 0) {
        const match = (input.experiences ?? []).find(
          (e) => eqInstitutional(e.company, exp.company) && eq(e.role, exp.role),
        )
        const inputLoc = match?.location ? String(match.location).trim() : ''
        const locInCv = cvFlat ? cvFlat.includes(flatten(String(exp.location))) : false
        if (!inputLoc && !locInCv) {
          console.warn(`[adapt-resume] clearing invented experience.location "${exp.location}" for ${exp.role} @ ${exp.company}`)
          exp.location = ''
        }
      }
    }
  }
  if (Array.isArray(r.education)) {
    for (const ed of r.education) {
      if (ed.location && String(ed.location).trim().length > 0) {
        const match = (input.education ?? []).find(
          (e) => eqInstitutional(e.institution, ed.institution) && eq(e.degree, ed.degree),
        )
        const inputLoc = match?.location ? String(match.location).trim() : ''
        const locInCv = cvFlat ? cvFlat.includes(flatten(String(ed.location))) : false
        if (!inputLoc && !locInCv) {
          console.warn(`[adapt-resume] clearing invented education.location "${ed.location}" for ${ed.degree} @ ${ed.institution}`)
          ed.location = ''
        }
      }
    }
  }

  // 1. Dados imutáveis
  // Em modo CV-only, o profile.name pode estar desatualizado ("da ava") mas
  // o CV tem o nome real do candidato. Aceitamos que fullName/email venham
  // do CV — desde que apareçam no raw_text.
  // Campos secundários (phone/linkedin/location): se a IA inventou (ex:
  // pegou localização da vaga em vez do candidato), zeramos silenciosamente
  // em vez de derrubar a adaptação inteira. Currículo gerado fica com
  // campo vazio, mas o resto da adaptação é válido.
  if (cvOnlyMode) {
    // fullName: matching token-a-token. Substring estrito quebra quando o
    // candidato tem 3+ nomes ("ZAC KOURI LOPES" no CV) mas a IA retorna 2
    // ("zac lopes" — sem o nome do meio), OU quando o profile.name vem de
    // Apple SignIn como "first+last" sem o meio. Aceita o fullName retornado
    // se TODAS as palavras significativas (>=2 chars) aparecem no CV em
    // qualquer ordem.
    if (r.fullName) {
      const v = flatten(String(r.fullName))
      if (v) {
        const tokens = v.split(/\s+/).filter((t) => t.length >= 2)
        const allTokensInCv = tokens.length > 0 && tokens.every((t) => cvFlat.includes(t))
        if (!allTokensInCv) {
          // Fallback: usa o profile.name (que veio do auth — confiável)
          // se ele também passa no token check no CV.
          if (input.fullName) {
            const fallbackTokens = flatten(input.fullName)
              .split(/\s+/)
              .filter((t) => t.length >= 2)
            const fallbackInCv = fallbackTokens.length > 0 && fallbackTokens.every((t) => cvFlat.includes(t))
            if (fallbackInCv) {
              console.warn(`[adapt-resume] fullName "${r.fullName}" not in CV, falling back to profile name "${input.fullName}"`)
              r.fullName = input.fullName
            } else {
              throw new ValidationError('fullName', `"${r.fullName}" não aparece no CV (tokens: ${JSON.stringify(tokens)})`)
            }
          } else {
            throw new ValidationError('fullName', `"${r.fullName}" não aparece no CV (tokens: ${JSON.stringify(tokens)})`)
          }
        }
      }
    }

    // email: tolerante. PDF extractor frequentemente quebra emails no @ ou
    // no .com, então `cvFlat.includes("foo@bar.com")` falha mesmo o email
    // estando ali. Estratégia em camadas:
    //   1. Se bate com profile.email (do Supabase auth — fonte confiável), aceita.
    //   2. Senão, tenta substring no CV achatado.
    //   3. Senão, tenta um normalize mais agressivo (remove TODO whitespace).
    //   4. Senão, força r.email = input.email (fallback silencioso pro email do auth).
    if (r.email) {
      const rEmail = flatten(String(r.email))
      const inputEmailFlat = flatten(input.email)
      const matchesProfile = inputEmailFlat && rEmail === inputEmailFlat
      const matchesCv = rEmail && cvFlat.includes(rEmail)
      // Match agressivo: tira todo whitespace do CV e tenta de novo
      const cvNoWs = cvFlat.replace(/\s+/g, '')
      const rEmailNoWs = rEmail.replace(/\s+/g, '')
      const matchesCvAggr = rEmailNoWs && cvNoWs.includes(rEmailNoWs)
      if (!matchesProfile && !matchesCv && !matchesCvAggr) {
        if (input.email) {
          console.warn(`[adapt-resume] email "${r.email}" not found in CV or profile, falling back to profile email`)
          r.email = input.email
        } else {
          console.warn(`[adapt-resume] email "${r.email}" not found, clearing`)
          r.email = ''
        }
      }
    } else if (input.email) {
      // IA não retornou email mas o profile tem → usa o do profile
      r.email = input.email
    }

    // Tolerantes: phone, linkedin, location → zera se não bater
    const lenientFields: Array<'phone' | 'linkedin' | 'location'> = ['phone', 'linkedin', 'location']
    for (const field of lenientFields) {
      const value = r[field]
      if (!value) continue
      const v = flatten(String(value))
      if (v && !cvFlat.includes(v)) {
        console.warn(`[adapt-resume] clearing invented ${field}: "${value}"`)
        r[field] = ''
      }
    }
  } else {
    if (input.fullName && !eq(r.fullName, input.fullName)) {
      throw new ValidationError('fullName', `mudou: "${input.fullName}" → "${r.fullName}"`)
    }
    if (input.email && !eq(r.email, input.email)) {
      throw new ValidationError('email', `mudou`)
    }
    if (input.phone && !eq(r.phone, input.phone)) {
      throw new ValidationError('phone', `mudou`)
    }
    if (input.linkedin && !eq(r.linkedin, input.linkedin)) {
      throw new ValidationError('linkedin', `mudou`)
    }
    if (input.location && !eq(r.location, input.location)) {
      throw new ValidationError('location', `mudou`)
    }
  }

  // 1.5. Resumo profissional — anti-invenção.
  //
  // Sumário não tinha validação antes. IA podia escrever "Estudante de
  // Engenharia da Computação com experiência em Windows" pra um candidato
  // de Administração, e nada barrava. Agora: tokeniza o resumo, tira
  // stop-words, e exige que >=60% dos tokens significativos apareçam em:
  //   1. CV bruto (cv-only) ou keywordPool (structured) — fonte do candidato
  //   2. Job pool (título, área, requisitos, descrição da vaga) — adaptação
  //      legítima pode mencionar a área da vaga ("interesse em [area]")
  //
  // Tolerante o suficiente pra IA reformular ("administrador" vs "gestão")
  // e puxar fit com a vaga, estrito o suficiente pra barrar invenção de
  // área/tecnologia que não tá em nenhum dos dois lugares.
  if (r.summary && typeof r.summary === 'string') {
    const summaryStr = String(r.summary).trim()
    if (summaryStr.length > 20) {
      const summaryTokens = tokenize(summaryStr)
      if (summaryTokens.length >= 5) {
        // Pool de tokens da VAGA (título + área + requisitos + descrição).
        // IA pode legitimamente mencionar a área da vaga no resumo —
        // ex: "estudante de Administração buscando atuar na área Comercial".
        // "Comercial" vem da vaga, não do CV — é adaptação legítima.
        const jobPool = new Set<string>()
        if (job) {
          tokenize(`${job.title} ${job.area} ${job.description}`).forEach((t) =>
            jobPool.add(t),
          )
          for (const req of job.requirements) tokenize(req).forEach((t) => jobPool.add(t))
        }

        let inCvCount = 0       // tokens encontrados no CV (peso forte)
        let onlyInJobCount = 0  // tokens encontrados SÓ na vaga (peso fraco — não é claim do user)
        const unknown: string[] = []
        for (const t of summaryTokens) {
          const inCv = input.keywordPool.has(t) || (cvFlat && cvFlat.includes(t))
          if (inCv) {
            inCvCount++
            continue
          }
          if (jobPool.has(t)) {
            onlyInJobCount++
            continue
          }
          unknown.push(t)
        }
        const total = summaryTokens.length
        // 1) Threshold geral: pelo menos 60% reconhecidos (CV OU vaga)
        const recognized = inCvCount + onlyInJobCount
        const ratio = recognized / total
        if (ratio < 0.6) {
          console.warn(
            `[adapt-resume] summary rejected: only ${recognized}/${total} tokens (${(ratio * 100).toFixed(0)}%) found in CV/job. ` +
            `Unknown tokens: ${unknown.slice(0, 10).join(',')}`,
          )
          throw new ValidationError(
            'summary',
            `resumo inventou conteúdo (${recognized}/${total} tokens conhecidos)`,
          )
        }
        // 2) Anti-invenção de experiência: detecta padrões "Experiência em X" /
        //    "Experiente em X" / "Atuou em X" / "atuação em X" onde X é
        //    DOMÍNIO DA VAGA (não no CV). IA estava escrevendo "Experiência em
        //    recuperação de créditos" pra candidato sem isso no CV.
        const summaryLower = normalize(summaryStr)
        const dangerousClaims: string[] = []
        const claimRegexes = [
          /\bexperi[eê]ncia em ([a-záéíóúâêôãõç ]{3,60}?)(?:[.,]|$| e\b| ou\b| al[eé]m\b| com\b)/g,
          /\bexperiente em ([a-záéíóúâêôãõç ]{3,60}?)(?:[.,]|$| e\b| ou\b| al[eé]m\b)/g,
          /\batuou (?:em|na|no|como) ([a-záéíóúâêôãõç ]{3,60}?)(?:[.,]|$| e\b| ou\b)/g,
          /\batua(?:ndo|cao|ção) (?:em|na|no|como) ([a-záéíóúâêôãõç ]{3,60}?)(?:[.,]|$| e\b| ou\b)/g,
          /\bvivência em ([a-záéíóúâêôãõç ]{3,60}?)(?:[.,]|$| e\b| ou\b)/g,
          /\bconhecimento (?:em|de|sobre) ([a-záéíóúâêôãõç ]{3,60}?)(?:[.,]|$| e\b| ou\b)/g,
          /\bproficien(?:te|cia) em ([a-záéíóúâêôãõç ]{3,60}?)(?:[.,]|$| e\b| ou\b)/g,
          /\bdomínio (?:em|de|sobre) ([a-záéíóúâêôãõç ]{3,60}?)(?:[.,]|$| e\b| ou\b)/g,
          /\bexpertise em ([a-záéíóúâêôãõç ]{3,60}?)(?:[.,]|$| e\b| ou\b)/g,
        ]
        for (const re of claimRegexes) {
          re.lastIndex = 0
          let m: RegExpExecArray | null
          while ((m = re.exec(summaryLower)) !== null) {
            const claim = m[1].trim()
            const claimTokens = tokenize(claim).filter((t) => !STOP_WORDS.has(t))
            if (claimTokens.length === 0) continue
            // Quantos dos tokens da claim estão NO CV? Se TODOS estiverem só
            // na vaga (não no CV), é uma claim INVENTADA.
            const inCv = claimTokens.filter((t) =>
              input.keywordPool.has(t) || (cvFlat && cvFlat.includes(t)),
            ).length
            if (inCv === 0 && claimTokens.some((t) => jobPool.has(t))) {
              dangerousClaims.push(claim)
            }
          }
        }
        if (dangerousClaims.length > 0) {
          console.warn(
            `[adapt-resume] summary rejected: claimed experience in vaga's domain: ${JSON.stringify(dangerousClaims)}`,
          )
          throw new ValidationError(
            'summary',
            `afirmou experiência em "${dangerousClaims[0]}" (vem da vaga, não do CV)`,
          )
        }
      }
    }
  }

  // 2. Experiências
  if (!Array.isArray(r.experiences)) {
    throw new ValidationError('experiences', 'não é array')
  }
  if (hasStructuredExperiences) {
    if (r.experiences.length > input.experiences.length) {
      throw new ValidationError(
        'experiences',
        `inventou: ${r.experiences.length} > ${input.experiences.length} originais`,
      )
    }
    for (const exp of r.experiences) {
      // company via eqInstitutional (tolera pontuação alucinada);
      // role via eq estrito (variação de cargo costuma ser intencional).
      const found = input.experiences.find(
        (orig) => eqInstitutional(orig.company, exp.company) && eq(orig.role, exp.role),
      )
      if (!found) {
        throw new ValidationError(
          'experiences',
          `experiência inventada: "${exp.role}" @ "${exp.company}"`,
        )
      }
      // F6: auto-correct silencioso de nome canônico. eqInstitutional pode
      // passar com diferenças sutis ("Link @ School" → "Link School"); o
      // currículo final deve usar o nome exato do input do candidato, não
      // a versão alucinada da IA. Trocar aqui evita que diferenças voltem
      // depois em comparação contra o raw_text.
      if (found.company !== exp.company) {
        console.warn(`[adapt-resume] auto-correct company: "${exp.company}" → "${found.company}"`)
        exp.company = found.company
      }
      // Período: deve ser exatamente igual (datas não podem mudar).
      if (found.period && !eq(found.period, exp.period)) {
        throw new ValidationError(
          'experiences',
          `período de "${exp.company}" mudou: "${found.period}" → "${exp.period}"`,
        )
      }
      // Bullets: count <= original × MAX_BULLET_INFLATION.
      const origCount = bulletCount(found.description)
      const newCount = bulletCount(exp.description ?? '')
      if (origCount > 0 && newCount > Math.ceil(origCount * MAX_BULLET_INFLATION)) {
        throw new ValidationError(
          'experiences',
          `inflou bullets em "${exp.company}": ${origCount} → ${newCount}`,
        )
      }
    }
  } else if (cvFlat) {
    // Modo CV-only: cada experiência precisa ter (1) empresa NÃO-VAZIA que
    // apareça no CV, (2) role/cargo, (3) bullets cujos tokens concretos
    // venham majoritariamente do CV. Sem isso, a IA inventava experiências
    // completas alinhadas com a vaga (ex: vaga de Trade Marketing → IA
    // criava experiência fake "Estagiário Trade Marketing" pra um CEO do
    // Stage). Limite: 8 experiências (CV típico tem 1-5).
    if (r.experiences.length > 8) {
      throw new ValidationError('experiences', `excesso: ${r.experiences.length}`)
    }
    for (const exp of r.experiences) {
      const company = flatten(String(exp.company ?? ''))
      const role = String(exp.role ?? '').trim()

      // (1) Company não pode ser vazia em cv-only — sem isso, IA escapava
      // criando experiências sem company só com bullets fabricados.
      if (!company) {
        throw new ValidationError(
          'experiences',
          `experiência sem empresa: role="${role}"`,
        )
      }
      if (!cvFlat.includes(company)) {
        throw new ValidationError(
          'experiences',
          `empresa "${exp.company}" não aparece no CV`,
        )
      }

      // (2) Bullets: para cada bullet, exigir que >=50% dos tokens
      // significativos (após stop-words) apareçam no CV ou keywordPool.
      // Pode mencionar termos da vaga (tokens em jobPool seriam aceitos
      // se passássemos job aqui — não passamos pra manter local, mas
      // 50% é gentil o bastante pra incluir verbos novos como "auxiliando").
      const desc = String(exp.description ?? '')
      if (desc.trim().length > 10) {
        const bullets = desc
          .split('\n')
          .map((b) => b.replace(/^[-•·\s]+/, '').trim())
          .filter((b) => b.length >= 15)
        for (const bullet of bullets) {
          const tokens = tokenize(bullet)
          if (tokens.length < 4) continue
          let recognized = 0
          for (const t of tokens) {
            if (cvFlat.includes(t) || input.keywordPool.has(t)) recognized++
          }
          const ratio = recognized / tokens.length
          if (ratio < 0.5) {
            const unknown = tokens.filter((t) => !cvFlat.includes(t) && !input.keywordPool.has(t)).slice(0, 8).join(',')
            console.warn(
              `[adapt-resume] bullet rejected in "${exp.company}": ${recognized}/${tokens.length} (${(ratio * 100).toFixed(0)}%) tokens in CV. Unknown: ${unknown}. Bullet: "${bullet.slice(0, 100)}"`,
            )
            throw new ValidationError(
              'experiences',
              `bullet inventado em "${exp.company}": ${recognized}/${tokens.length} tokens conhecidos`,
            )
          }
        }
      }
    }
  } else if (r.experiences.length > 0) {
    // Sem dados estruturados nem CV bruto, qualquer experience é invenção.
    throw new ValidationError('experiences', 'sem fonte de dados')
  }

  // 3. Educação
  if (!Array.isArray(r.education)) {
    throw new ValidationError('education', 'não é array')
  }
  if (hasStructuredEducation) {
    if (r.education.length > input.education.length) {
      throw new ValidationError('education', 'inventou educação')
    }
    for (const ed of r.education) {
      // institution via eqInstitutional (tolera pontuação alucinada);
      // degree via eq estrito (variação de grau costuma ser intencional).
      const found = input.education.find(
        (orig) => eqInstitutional(orig.institution, ed.institution) && eq(orig.degree, ed.degree),
      )
      if (!found) {
        throw new ValidationError(
          'education',
          `educação inventada: "${ed.degree}" @ "${ed.institution}"`,
        )
      }
      // F6: auto-correct silencioso pra nome canônico da instituição.
      if (found.institution !== ed.institution) {
        console.warn(`[adapt-resume] auto-correct institution: "${ed.institution}" → "${found.institution}"`)
        ed.institution = found.institution
      }
    }
  } else if (cvFlat) {
    if (r.education.length > 5) {
      throw new ValidationError('education', `excesso: ${r.education.length}`)
    }
    for (const ed of r.education) {
      const inst = flatten(String(ed.institution ?? ''))
      if (!inst) continue
      if (!cvFlat.includes(inst)) {
        throw new ValidationError(
          'education',
          `instituição "${ed.institution}" não aparece no CV`,
        )
      }
    }
  } else if (r.education.length > 0) {
    throw new ValidationError('education', 'sem fonte de dados')
  }

  // 4. Skills: validação anti-invenção
  //    - Modo structured: skill deve estar no input.skills OU ter todos os
  //      tokens significativos no keywordPool (CV + experiences + ...).
  //    - Modo CV-only: skill DEVE aparecer textualmente no CV bruto
  //      (flatten/substring). A IA pode reescrever espacamento mas não pode
  //      inventar palavras novas. Permite tolerância de até 1 skill rejeitada
  //      silenciosamente em vez de derrubar tudo — é comum a IA tentar
  //      melhorar 1-2 itens mesmo com prompt forte.
  if (!Array.isArray(r.skills)) throw new ValidationError('skills', 'não é array')
  if (r.skills.length > 15) {
    throw new ValidationError('skills', `excesso: ${r.skills.length} skills`)
  }
  const originalSkillsNorm = new Set(input.skills.map((s) => normalize(s)))
  const filteredSkills: string[] = []
  let droppedSkills = 0
  for (const s of r.skills) {
    const sNorm = normalize(s)
    if (!sNorm) continue
    if (originalSkillsNorm.has(sNorm)) {
      filteredSkills.push(s)
      continue
    }

    let accepted = false
    if (cvFlat) {
      // CV-only: substring no CV achatado (cobre "Gestão de projetos" mesmo
      // que o PDF venha como "Gestão\nde\nprojetos").
      const sFlat = flatten(s)
      if (sFlat && cvFlat.includes(sFlat)) accepted = true
    } else {
      // structured: todos tokens significativos têm que estar no pool.
      const tokens = tokenize(s)
      if (tokens.length > 0 && tokens.every((t) => input.keywordPool.has(t))) {
        accepted = true
      }
    }

    if (accepted) {
      filteredSkills.push(s)
    } else {
      droppedSkills++
      console.warn(`[adapt-resume] dropping invented skill: "${s}"`)
    }
  }
  // Atualiza a resposta in-place: skills inventadas são silenciosamente
  // removidas (até 3). Se a IA inventou MAIS que 3, considera má fé e rejeita.
  if (droppedSkills > 3) {
    throw new ValidationError('skills', `${droppedSkills} skills inventadas`)
  }
  r.skills = filteredSkills

  // 5. Achievements: subset (case-insensível) ou reformulação que
  //    ainda esteja contida em algum original. Mantemos checagem
  //    leve aqui — não quero rejeitar reformulações legítimas.
  if (Array.isArray(r.achievements) && r.achievements.length > input.achievements.length + 1) {
    throw new ValidationError('achievements', 'inventou conquista')
  }

  // 6. Changes: array com no máximo 6.
  if (!Array.isArray(parsed.changes)) {
    throw new ValidationError('changes', 'não é array')
  }
  if (parsed.changes.length > 6) {
    throw new ValidationError('changes', 'excesso (>6)')
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Match score upgrade (best-effort, sem nova chamada IA)
// ────────────────────────────────────────────────────────────────────────────

/**
 * Calcula upgrade de match. O "before" usa o SCORE REAL que o usuário já vê
 * no card de swipe (de `match_analyses`, o cache do analyze-match) — garante
 * consistência conceitual: o sheet começa do mesmo número que o card mostra.
 *
 * O "after" estima o ganho da adaptação contando quantos requisitos da vaga
 * passaram a estar TEXTUALMENTE no CV adaptado mas NÃO estavam no original.
 * Cada requisito novo vale ~3 pontos, cap de +20 pontos total. Garante que
 * after >= before (a adaptação nunca regride).
 *
 * Se não há `beforeScore` (sem cache de match_analyses ainda), retorna o
 * mesmo valor pros dois — UI não mostra upgrade nesse caso.
 */
/**
 * F7 da reformulação: score objetivo (0-100) de qualidade da adaptação.
 * Soma de 5 fatores ponderados — não depende de feedback humano explícito
 * (raro), mas dá um sinal aproximado pra dashboard/alertas e A/B test
 * entre modelos.
 *
 * Fatores:
 *  - 30 pts: campos críticos preservados (name/email/phone/linkedin/
 *            location/#experiences/#education). Sinal de integridade.
 *  - 20 pts: zero retries do validador (1 = 10, 2 = 0). Sinal de "IA
 *            acertou de primeira".
 *  - 20 pts: Jaccard de bigrams entre summary adaptado e CV original.
 *            Sinal de "summary não inventou nada".
 *  - 15 pts: requisitos da vaga agora cobertos no CV. Sinal de fit.
 *  - 15 pts: placeholder fixo (default 15). Em F7+ vai virar inverso do
 *            histórico de cv_adaptation_user_edited do user, quando
 *            tivermos dataset.
 *
 * Retorna 0-100 (inteiro).
 */
function computeQualityScore(args: {
  input: InputResume
  adapted: any
  job: JobContext
  validatorRetries: number
}): number {
  const { input, adapted, job, validatorRetries } = args

  // (1) Preservação de campos críticos — 30 pts
  let preserved = 0
  const criticalChecks: Array<[string, boolean]> = [
    ['fullName', !!(adapted?.fullName && String(adapted.fullName).trim() === String(input.fullName ?? '').trim())],
    ['email', !!(input.email ? eqInstitutional(adapted?.email, input.email) : true)],
    ['phone', !!(input.phone ? eqInstitutional(adapted?.phone, input.phone) : true)],
    ['linkedin', !!(input.linkedin ? eqInstitutional(adapted?.linkedin, input.linkedin) : true)],
    ['location', !!(input.location ? eqInstitutional(adapted?.location, input.location) : true)],
    ['experiences_count', Array.isArray(adapted?.experiences) &&
        adapted.experiences.length === (input.experiences?.length ?? 0)],
    ['education_count', Array.isArray(adapted?.education) &&
        adapted.education.length === (input.education?.length ?? 0)],
  ]
  for (const [, ok] of criticalChecks) if (ok) preserved++
  const preservedPts = Math.round((preserved / criticalChecks.length) * 30)

  // (2) Validator retries — 20 pts (0 retries = 20, 1 = 10, 2 = 0)
  const retriesPts = validatorRetries === 0 ? 20 : (validatorRetries === 1 ? 10 : 0)

  // (3) Jaccard de bigrams summary — 20 pts
  let summaryPts = 20
  if (typeof adapted?.summary === 'string' && adapted.summary.length > 30) {
    const cvText = String(input.summary ?? '') + ' ' +
                   String(input.importedCvText ?? '').slice(0, 4000)
    const adaptedBigrams = toBigrams(adapted.summary)
    const cvBigrams = toBigrams(cvText)
    if (adaptedBigrams.size > 0 && cvBigrams.size > 0) {
      let intersect = 0
      for (const b of adaptedBigrams) if (cvBigrams.has(b)) intersect++
      const union = adaptedBigrams.size + cvBigrams.size - intersect
      const jaccard = union > 0 ? intersect / union : 0
      // Mapeia 0..0.4 → 0..20 (Jaccard maior que 0.4 é raro mesmo com
      // summary fiel; clamp evita penalizar reformulação válida).
      summaryPts = Math.min(20, Math.round((jaccard / 0.4) * 20))
    }
  }

  // (4) Requisitos da vaga cobertos — 15 pts
  let jobFitPts = 15
  if (Array.isArray(job.requirements) && job.requirements.length > 0) {
    const adaptedText = [
      adapted?.summary ?? '',
      (adapted?.skills ?? []).join(' '),
      ...(adapted?.experiences ?? []).map((e: any) => `${e.role ?? ''} ${e.description ?? ''}`),
    ].join(' ').toLowerCase()
    let covered = 0
    for (const req of job.requirements) {
      const reqTokens = tokenize(String(req)).filter((t) => t.length >= 4)
      if (reqTokens.length === 0) continue
      const matches = reqTokens.filter((t) => adaptedText.includes(t)).length
      if (matches / reqTokens.length >= 0.5) covered++
    }
    jobFitPts = Math.round((covered / job.requirements.length) * 15)
  }

  // (5) Placeholder fixo — 15 pts. Em iteração futura: inverso de
  //     cv_adaptation_user_edited histórico do user.
  const userTrustPts = 15

  const total = preservedPts + retriesPts + summaryPts + jobFitPts + userTrustPts
  return Math.max(0, Math.min(100, total))
}

/** Converte texto em set de bigrams pra Jaccard similarity. */
function toBigrams(text: string): Set<string> {
  const flat = flatten(text)
  const out = new Set<string>()
  if (flat.length < 2) return out
  for (let i = 0; i < flat.length - 1; i++) {
    const bg = flat.substring(i, i + 2)
    if (/\S\S/.test(bg)) out.add(bg)
  }
  return out
}

function computeMatchUpgrade(
  input: InputResume,
  adapted: any,
  job: JobContext,
  beforeScore: number | undefined,
): { before: number; after: number } {
  // Sem score real cacheado → não conseguimos mostrar upgrade significativo.
  if (beforeScore == null) {
    return { before: 0, after: 0 }
  }

  const reqTokens = new Set<string>()
  for (const r of job.requirements) tokenize(r).forEach((t) => reqTokens.add(t))
  tokenize(job.description).forEach((t) => reqTokens.add(t))
  if (reqTokens.size === 0) {
    return { before: beforeScore, after: beforeScore }
  }

  // Texto "original" do candidato: structured se tem, senão raw_text do CV.
  const originalText = input.importedCvText && input.importedCvText.length > 0
    ? input.importedCvText
    : [
        ...input.skills,
        ...input.experiences.map((e) => `${e.role} ${e.description}`),
        input.summary,
      ].join(' ')
  const originalTokens = new Set(tokenize(originalText))

  // Texto "adaptado" (skills + experiences + summary da resposta).
  const adaptedText = [
    ...(Array.isArray(adapted.skills) ? adapted.skills : []),
    ...(Array.isArray(adapted.experiences)
      ? adapted.experiences.map((e: any) => `${e.role ?? ''} ${e.description ?? ''}`)
      : []),
    adapted.summary ?? '',
  ].join(' ')
  const adaptedTokens = new Set(tokenize(adaptedText))

  // Requisitos que agora estão no CV adaptado mas NÃO estavam no original.
  let newReqMatches = 0
  for (const t of reqTokens) {
    if (adaptedTokens.has(t) && !originalTokens.has(t)) newReqMatches++
  }

  // Cada novo requisito vale ~3 pontos, cap em +20 (adaptação não faz milagre).
  const delta = Math.min(20, newReqMatches * 3)
  const after = Math.min(100, beforeScore + delta)
  return { before: beforeScore, after }
}

// ────────────────────────────────────────────────────────────────────────────
// Main handler
// ────────────────────────────────────────────────────────────────────────────

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  // F2.6: timer global da function. Comparado ao $ai_latency (só OpenAI)
  // permite isolar onde mora o tail: parsing/cache/validation vs IA pura.
  // Pré-fix p95 = 221s — sem breakdown, era impossível atribuir.
  const fnStart = Date.now()
  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: req.headers.get('Authorization')! } } },
    )

    // Service role pra escrever em adapted_resumes (RLS bloqueia user).
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    // 1. Auth
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser()
    if (authError || !user) return jsonResponse({ error: 'Unauthorized' }, 401)

    // 2. Parse input
    const body = await req.json().catch(() => ({}))
    const jobId: string | undefined = body?.job_id
    const force: boolean = body?.force === true
    if (!jobId || typeof jobId !== 'string') {
      return jsonResponse({ error: 'job_id required' }, 400)
    }

    // extra_skills: skills que o user confirmou ter mas não estão no CV.
    // Vêm da tela de "confirmação de skills" antes da adaptação. Tratadas
    // como parte do CV original (entram em input.skills + keywordPool ANTES
    // da validação) — IA pode usá-las sem ser rejeitada por "invenção".
    const extraSkills: string[] = Array.isArray(body?.extra_skills)
      ? (body.extra_skills as unknown[])
          .map((s) => String(s ?? '').trim())
          .filter((s) => s.length > 0 && s.length <= 60)
          .slice(0, 10)
      : []
    // Dedup case-insensitive preservando ordem
    const _seenExtra = new Set<string>()
    const extraSkillsClean: string[] = []
    for (const s of extraSkills) {
      const k = normalize(s)
      if (!_seenExtra.has(k)) {
        _seenExtra.add(k)
        extraSkillsClean.push(s)
      }
    }

    // 3. Rate limit (cache hits NÃO contam)
    const today = new Date()
    today.setHours(0, 0, 0, 0)
    const { count: rlCount } = await supabaseClient
      .from('ai_generation_logs')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', user.id)
      .eq('generation_type', 'resume_adaptation')
      .gte('created_at', today.toISOString())

    if (rlCount && rlCount >= RATE_LIMIT_PER_DAY) {
      return jsonResponse(
        { error: `Rate limit exceeded. Maximum ${RATE_LIMIT_PER_DAY} adaptations per day.` },
        429,
      )
    }

    // 4. Fetch em paralelo: job + companies, profile.
    //    Profile lido via service role pra bypass de RLS — o user.id vem
    //    do JWT validado, então é o próprio usuário; não há leak.
    //    Caso contrário, RLS pode esconder o profile e a função pensa que
    //    o perfil está vazio quando na verdade está bloqueado por permissão.
    const [jobR, profileR] = await Promise.all([
      supabaseClient
        .from('jobs')
        .select('*, companies(name)')
        .eq('id', jobId)
        .maybeSingle(),
      supabaseAdmin
        .from('user_profiles')
        .select('id, name, email, gamification_data')
        .eq('id', user.id)
        .maybeSingle(),
    ])

    if (jobR.error || !jobR.data) return jsonResponse({ error: 'job_not_found' }, 404)

    const jobRow = jobR.data
    const job: JobContext = {
      title: String(jobRow.title ?? ''),
      company: String(jobRow.companies?.name ?? ''),
      area: String(jobRow.area ?? ''),
      jobType: String(jobRow.job_type ?? ''),
      workModel: String(jobRow.work_model ?? ''),
      location: [jobRow.location_city, jobRow.location_state].filter(Boolean).join(', '),
      description: String(jobRow.description ?? ''),
      requirements: Array.isArray(jobRow.requirements) ? jobRow.requirements : [],
    }

    // user_profiles é criado on-demand pelo Flutter (getUserProfile cria se
    // não existe). User pode ter logado e ido direto pra Vagas sem disparar
    // essa criação. Em vez de falhar com 404 técnico, montamos um perfil
    // mínimo a partir de auth.users e deixamos buildInputResume decidir se
    // tem dados suficientes — caindo no friendly "profile_incomplete".
    const profileFallback = profileR.data ?? {
      id: user.id,
      name: user.user_metadata?.name ?? '',
      email: user.email ?? '',
      phone: user.user_metadata?.phone ?? '',
      location: '',
      gamification_data: {},
    }

    // DEBUG: log do que chegou pra debugar quando user reporta profile_incomplete
    const _gd: any = profileFallback?.gamification_data ?? {}
    const _imp = _gd?.imported_resume ?? {}
    console.log(`[adapt-resume] user=${user.id} email=${user.email} ` +
      `profileRowExists=${!!profileR.data} ` +
      `name="${profileFallback?.name ?? ''}" ` +
      `rawTextLen=${typeof _imp?.raw_text === 'string' ? _imp.raw_text.length : 0} ` +
      `hasParsed=${!!_imp?.parsed} ` +
      `hasWhoIAm=${!!_gd?.whoIAm?.derived}`)

    const input = buildInputResume(profileFallback)
    if (!input) {
      console.warn(`[adapt-resume] profile_incomplete for user=${user.id}: ` +
        `fullName="${profileFallback?.name ?? ''}" ` +
        `rawTextLen=${typeof _imp?.raw_text === 'string' ? _imp.raw_text.length : 0}`)
      return jsonResponse(
        {
          error: 'profile_incomplete',
          detail: 'Complete seu perfil ou suba seu currículo antes de adaptar.',
        },
        422,
      )
    }
    console.log(`[adapt-resume] input built: fullName="${input.fullName}" ` +
      `experiences=${input.experiences.length} education=${input.education.length} ` +
      `skills=${input.skills.length} summary=${input.summary.length}chars ` +
      `importedCv=${input.importedCvText?.length ?? 0}chars ` +
      `phone="${input.phone}" location="${input.location}" linkedin="${input.linkedin}"`)
    if (input.experiences.length > 0) {
      console.log(`[adapt-resume] experiences detected: ${JSON.stringify(input.experiences.map((e) => ({ role: e.role, company: e.company, period: e.period })))}`)
    }
    if (input.education.length > 0) {
      console.log(`[adapt-resume] education detected: ${JSON.stringify(input.education.map((e) => ({ degree: e.degree, institution: e.institution, period: e.period })))}`)
    }

    // 4.5. Injeta extra_skills no input ANTES da validação. Cada skill entra
    // em input.skills (caso ainda não exista) e seus tokens no keywordPool —
    // o validator anti-invenção (validateAdaptation) passa a aceitá-las como
    // legítimas. Sem isso, a IA seria forçada a ignorar essas skills mesmo
    // tendo sido pedidas explicitamente.
    if (extraSkillsClean.length > 0) {
      for (const s of extraSkillsClean) {
        const sNorm = normalize(s)
        const exists = input.skills.some((existing) => normalize(existing) === sNorm)
        if (!exists) input.skills.push(s)
        tokenize(s).forEach((t) => input.keywordPool.add(t))
      }
      console.log(`[adapt-resume] injected ${extraSkillsClean.length} extra_skills: ${JSON.stringify(extraSkillsClean)}`)
    }

    // 5. Cache lookup (extraSkills entra no hash: adaptações com skills
    // diferentes geram cache distinto)
    const sourceHash = await sha256Hex(
      pickInputForHash(input) + '|' + jobId + '|extras:' + extraSkillsClean.join(','),
    )

    if (!force) {
      const { data: cachedRow } = await supabaseAdmin
        .from('adapted_resumes')
        .select('changes, resume_data, match_score_before, match_score_after, source_hash, prompt_version, model_used')
        .eq('user_id', user.id)
        .eq('job_id', jobId)
        .maybeSingle()

      if (
        cachedRow &&
        cachedRow.source_hash === sourceHash &&
        cachedRow.prompt_version === PROMPT_VERSION
      ) {
        // Cache hit — emite com cached=true pra alimentar cache hit rate.
        trackAIGeneration({
          userId: user.id,
          generationType: 'cv_adaptation',
          model: cachedRow.model_used ?? MODEL,
          inputTokens: 0,
          outputTokens: 0,
          latencyMs: 0,
          cached: true,
        }).catch(() => {})
        return jsonResponse({
          changes: cachedRow.changes,
          resume_data: cachedRow.resume_data,
          match_score_before: cachedRow.match_score_before,
          match_score_after: cachedRow.match_score_after,
          cached: true,
          model_used: cachedRow.model_used,
          extra_skills_used: extraSkillsClean,
        })
      }
    }

    // 6. Call OpenAI (com 1 retry se validateAdaptation falhar)
    //
    // Pré-fix: ~19 usuários únicos hit `adaptation_rejected` em 7 dias por
    // a IA propor inflation > 1.3x ou tocar campos imutáveis. O fallback
    // era jogar o erro pro user — agora retentamos UMA vez alimentando
    // o erro de validação de volta como feedback ("você violou X: ajuste e
    // tente de novo"). Se a 2ª resposta também falhar, retornamos o erro
    // original como antes.
    const userPromptInitial = buildUserPrompt(input, job, extraSkillsClean)
    console.log(`[adapt-resume] calling OpenAI (prompt ${userPromptInitial.length} chars)`)

    let parsed: any = null
    let lastValidationError: ValidationError | null = null
    let attempts = 0
    let userPrompt = userPromptInitial
    // tokensUsedTotal acumula entre tentativas — usado pelo rate-limit log
    // (`ai_generation_logs`) na linha ~2289. Sem isso, retries consumiriam IA
    // sem contar contra o limite diário.
    let tokensUsedTotal = 0

    while (attempts < 2 && parsed === null) {
      attempts++
      const ai = await callOpenAI(SYSTEM_PROMPT, userPrompt)
      tokensUsedTotal += ai.totalTokens
      console.log(`[adapt-resume] OpenAI responded attempt=${attempts} tokens=${ai.totalTokens}`)

      trackAIGeneration({
        userId: user.id,
        generationType: 'cv_adaptation',
        model: MODEL,
        inputTokens: ai.inputTokens,
        outputTokens: ai.outputTokens,
        latencyMs: ai.latencyMs,
        cached: false,
        extra: {
          prompt_chars: userPrompt.length,
          attempt: attempts,
          // function_ms_so_far inclui parse/cache/validation feitos antes
          // da chamada. Diferença com ai.latencyMs (= só fetch OpenAI) dá
          // o overhead da função — alvo de tuning se ficar significativo.
          function_ms_so_far: Date.now() - fnStart,
        },
      }).catch(() => {})

      let candidate: any
      try {
        candidate = JSON.parse(ai.content)
      } catch (_e) {
        console.error('Failed to JSON.parse AI output:', ai.content.slice(0, 500))
        return jsonResponse({ error: 'ai_response_invalid', detail: 'JSON parse failed' }, 502)
      }

      try {
        validateAdaptation(input, candidate, job)
        parsed = candidate
      } catch (e) {
        lastValidationError = e as ValidationError
        console.warn(`[adapt-resume] validation failed attempt=${attempts} for user=${user.id} job=${jobId}: ${lastValidationError.message}`)
        if (attempts < 2) {
          // Anexa o erro como feedback ao prompt e retenta. Geralmente o
          // segundo passe corrige porque o modelo agora SABE o que precisa
          // respeitar (ex.: "use bullets do CV em vez de inventar").
          userPrompt = userPromptInitial +
            `\n\n[REJEITADO NA TENTATIVA ${attempts}] A resposta anterior violou: ` +
            `${lastValidationError.field} → ${lastValidationError.message}. ` +
            `Refaça mantendo TODA a integridade dos dados originais.`
        }
      }
    }

    if (parsed === null) {
      const ve = lastValidationError!
      console.warn(`adaptation rejected (after retry) for user=${user.id} job=${jobId}: ${ve.message}`)
      return jsonResponse(
        {
          error: 'adaptation_rejected',
          detail: 'A adaptação não passou na verificação de integridade. Tente novamente.',
          field: ve.field,
        },
        422,
      )
    }

    // F5 da reformulação: step B — refinar summary + bullets com modelo
    // maior (gpt-4o). Step A (mini) já cuida da estrutura; step B só
    // melhora qualidade de escrita. Custo extra ~$0.01/adaptação. Falha
    // do step B é não-fatal — usa output do step A direto.
    // Controlado por env REFINEMENT_ENABLED=false pra rollback rápido.
    const refinementEnabled = (Deno.env.get('REFINEMENT_ENABLED') ?? 'true').toLowerCase() !== 'false'
    let stepUsed: 'mini_only' | 'mini+4o' = 'mini_only'
    let refineLatencyMs = 0
    if (refinementEnabled) {
      const refineResult = await refineWithBigModel(input, job, parsed.resume, user.id, fnStart)
      if (refineResult) {
        // Re-validar o refinamento (anti-invenção continua valendo).
        try {
          const candidate = { ...parsed, resume: refineResult.refined }
          validateAdaptation(input, candidate, job)
          parsed = candidate
          tokensUsedTotal += refineResult.tokensUsed
          refineLatencyMs = refineResult.latencyMs
          stepUsed = 'mini+4o'
          console.log(`[adapt-resume] step B applied (${refineResult.latencyMs}ms, tokens=${refineResult.tokensUsed})`)
        } catch (e) {
          console.warn(`[adapt-resume] step B output failed validation — usando step A: ${(e as Error).message}`)
        }
      }
    } else {
      console.log('[adapt-resume] REFINEMENT_ENABLED=false — pulando step B')
    }

    // 8. Match score upgrade
    // Pegamos o score REAL do analyze-match (cache em match_analyses) pra
    // usar como "before" — assim o sheet começa do mesmo número que o card
    // de swipe mostra. Sem isso, before/after eram inventados e não batiam
    // com o que o user vê no resto da app.
    const matchAnalysisR = await supabaseAdmin
      .from('match_analyses')
      .select('score')
      .eq('user_id', user.id)
      .eq('job_id', jobId)
      .maybeSingle()
    const realMatchScore = (matchAnalysisR.data?.score as number | undefined)
    const matchUpgrade = computeMatchUpgrade(input, parsed.resume, job, realMatchScore)
    console.log(`[adapt-resume] match upgrade: before=${matchUpgrade.before} after=${matchUpgrade.after} (real cached: ${realMatchScore ?? 'none'}) step_used=${stepUsed}`)

    // F7 da reformulação: score objetivo 0-100 da qualidade da adaptação.
    // attempts - 1 = retries (1ª tentativa não conta como retry).
    const validatorRetries = Math.max(0, attempts - 1)
    const qualityScore = computeQualityScore({
      input,
      adapted: parsed.resume,
      job,
      validatorRetries,
    })
    console.log(`[adapt-resume] quality_score=${qualityScore} validatorRetries=${validatorRetries}`)

    // Emite o quality_score como evento PostHog dedicado pra dashboard.
    // Separado de $ai_generation porque o quality_score é calculado APÓS
    // todas as chamadas de LLM (incluindo retries) terminarem.
    captureEvent({
      event: 'cv_adaptation_quality_score',
      distinctId: user.id,
      properties: {
        job_id: jobId,
        quality_score: qualityScore,
        validator_retries: validatorRetries,
        model_used: MODEL,
        prompt_version: PROMPT_VERSION,
        // F5: distingue cohort no PostHog. step_used = 'mini_only' são
        // adaptações antes do refinamento ou quando step B falhou.
        step_used: stepUsed,
        refine_latency_ms: refineLatencyMs,
        input_experiences: input.experiences?.length ?? 0,
        input_education: input.education?.length ?? 0,
        adapted_experiences: Array.isArray(parsed.resume?.experiences) ? parsed.resume.experiences.length : 0,
        adapted_education: Array.isArray(parsed.resume?.education) ? parsed.resume.education.length : 0,
      },
    }).catch(() => {})

    // Também emite cv_adaptation_validator_retry quando houve retry —
    // sinal mais granular pra debugging de prompts que estão falhando.
    if (validatorRetries > 0) {
      captureEvent({
        event: 'cv_adaptation_validator_retry',
        distinctId: user.id,
        properties: {
          job_id: jobId,
          retries: validatorRetries,
          model_used: MODEL,
        },
      }).catch(() => {})
    }

    // 9. Persiste cache (service role bypassa RLS)
    const upsertR = await supabaseAdmin.from('adapted_resumes').upsert(
      {
        user_id: user.id,
        job_id: jobId,
        changes: parsed.changes,
        resume_data: parsed.resume,
        match_score_before: matchUpgrade.before,
        match_score_after: matchUpgrade.after,
        source_hash: sourceHash,
        prompt_version: PROMPT_VERSION,
        model_used: MODEL,
        computed_at: new Date().toISOString(),
        // F7: coluna adicionada via migration 20260521000001. RODAR ESSA
        // MIGRATION ANTES DO DEPLOY desta edge function, senão upsert
        // falha por coluna desconhecida.
        quality_score: qualityScore,
      },
      { onConflict: 'user_id,job_id' },
    )
    if (upsertR.error) {
      console.error(`[adapt-resume] upsert failed:`, upsertR.error)
    } else {
      console.log(`[adapt-resume] upsert OK`)
    }

    await supabaseClient.from('ai_generation_logs').insert({
      user_id: user.id,
      generation_type: 'resume_adaptation',
      tokens_used: tokensUsedTotal,
    })

    // 10. Merge extra_skills no gamification_data.confirmed_skills (global do
    // user). Skills confirmadas em uma vaga ficam pré-selecionadas pra
    // vagas futuras que pedirem a mesma skill. Não-fatal se falhar.
    if (extraSkillsClean.length > 0) {
      try {
        const existingGd: any = profileFallback?.gamification_data ?? {}
        const existingConfirmed: string[] = Array.isArray(existingGd.confirmed_skills)
          ? existingGd.confirmed_skills.map((s: any) => String(s))
          : []
        const mergedSet = new Set<string>()
        const mergedList: string[] = []
        for (const s of [...existingConfirmed, ...extraSkillsClean]) {
          const k = normalize(s)
          if (!k || mergedSet.has(k)) continue
          mergedSet.add(k)
          mergedList.push(s.trim())
        }
        const updatedGd = { ...existingGd, confirmed_skills: mergedList }
        await supabaseAdmin
          .from('user_profiles')
          .update({ gamification_data: updatedGd })
          .eq('id', user.id)
        console.log(`[adapt-resume] confirmed_skills merged: ${mergedList.length} total`)
      } catch (e) {
        console.warn('[adapt-resume] failed to persist confirmed_skills:', (e as Error).message)
      }
    }

    console.log(`[adapt-resume] SUCCESS user=${user.id} job=${jobId} ` +
      `changes=${parsed.changes?.length ?? 0} ` +
      `score=${matchUpgrade.before}→${matchUpgrade.after}`)
    return jsonResponse({
      changes: parsed.changes,
      resume_data: parsed.resume,
      match_score_before: matchUpgrade.before,
      match_score_after: matchUpgrade.after,
      cached: false,
      model_used: MODEL,
      extra_skills_used: extraSkillsClean,
    })
  } catch (err) {
    const msg = (err as Error).message || 'unknown'
    console.error('adapt-resume-to-job error:', msg)
    const status = msg.includes('AbortError') || msg.includes('aborted') ? 504 : 500
    return jsonResponse({ error: 'internal', detail: msg.slice(0, 300) }, status)
  }
})
