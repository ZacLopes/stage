// Helpers compartilhados pelas Edge Functions de sync de vagas:
// sync-jobs-ats (Greenhouse/Lever/Ashby/Workable/Recruitee/SmartRecruiters/Teamtailor),
// sync-jobs-apify (Gupy via Apify), sync-jobs-brazil (InfoJobs/Vagas/APInfo/LinkedIn via Apify).
//
// Antes deste módulo, htmlToText/stripHtml/inferArea/inferJobType/markStale/etc
// estavam duplicados em 3 arquivos com variações sutis. Consolidar aqui evita
// drift e dá um único ponto de evolução para os 5 novos ATS.

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

// ── HTTP / Auth ──────────────────────────────────────────────────────────────

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/**
 * Aceita 2 caminhos:
 * (1) pg_cron com `x-cron-secret: <CRON_SECRET>`.
 * (2) Trigger manual com `Authorization: Bearer <JWT>`. O gateway do Supabase
 *     JÁ valida a JWT antes da função receber, então qualquer Bearer significa
 *     "veio de alguém com chave do projeto".
 */
export function isAuthorized(req: Request, cronSecret: string): boolean {
  const cronHeader = req.headers.get("x-cron-secret");
  if (cronSecret && cronHeader === cronSecret) return true;
  const auth = req.headers.get("authorization");
  if (auth && /^Bearer\s+\S+/.test(auth)) return true;
  return false;
}

/** Tenta parsear body JSON sem crash — retorna null em qualquer falha. */
export async function safeJson<T = Record<string, unknown>>(req: Request): Promise<T | null> {
  if (req.method !== "POST") return null;
  try {
    return await req.json() as T;
  } catch {
    return null;
  }
}

// ── HTML ─────────────────────────────────────────────────────────────────────

/**
 * Decodifica entidades HTML comuns. Greenhouse e outros ATSs entregam content
 * com `&lt;`, `&gt;` etc — precisa decodificar antes de aplicar regex.
 *
 * Loop até estabilizar: cobre double-encoding (ex: `&amp;nbsp;` que vira
 * `&nbsp;` no primeiro pass e precisa de segundo pass pra virar espaço).
 * 94/94 vagas Greenhouse tinham `&nbsp;` literal no description antes deste
 * fix porque o input do ATS vem double-escaped.
 */
export function decodeEntities(s: string): string {
  let prev: string;
  let result = s;
  do {
    prev = result;
    result = result
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">")
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/&apos;/g, "'")
      .replace(/&nbsp;/g, " ")
      .replace(/&ndash;/g, "–")
      .replace(/&mdash;/g, "—")
      .replace(/&hellip;/g, "…")
      .replace(/&aacute;/g, "á")
      .replace(/&eacute;/g, "é")
      .replace(/&iacute;/g, "í")
      .replace(/&oacute;/g, "ó")
      .replace(/&uacute;/g, "ú")
      .replace(/&atilde;/g, "ã")
      .replace(/&otilde;/g, "õ")
      .replace(/&ccedil;/g, "ç")
      .replace(/&Aacute;/g, "Á")
      .replace(/&Eacute;/g, "É")
      .replace(/&Iacute;/g, "Í")
      .replace(/&Oacute;/g, "Ó")
      .replace(/&Uacute;/g, "Ú")
      .replace(/&Atilde;/g, "Ã")
      .replace(/&Otilde;/g, "Õ")
      .replace(/&Ccedil;/g, "Ç")
      .replace(/&amp;/g, "&"); // por último pra não dupla-decodificar
  } while (result !== prev);
  return result;
}

/**
 * Converte HTML em texto preservando estrutura (quebras de parágrafo e bullets).
 * Uso típico: campo `description` de vagas.
 */
export function htmlToText(html: string | null | undefined): string {
  if (!html) return "";
  return decodeEntities(html)
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/p>/gi, "\n\n")
    .replace(/<\/li>/gi, "\n")
    .replace(/<li[^>]*>/gi, "• ")
    .replace(/<[^>]*>/g, " ")
    .replace(/[ \t]+/g, " ")
    .replace(/\n[ \t]+/g, "\n")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

/**
 * Versão agressiva — colapsa TODO whitespace numa linha. Útil pra
 * snippets curtos, normalização de dedup, descrições inline.
 */
export function stripHtml(html: string | null | undefined): string {
  if (!html) return "";
  return decodeEntities(html)
    .replace(/<[^>]*>/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Tenta extrair bullets de um bloco HTML. Estratégia em cascata:
 * 1) <li>...</li> direto
 * 2) múltiplos <p>...</p>
 * 3) split por \n, ; ou •
 * 4) split por emoji (padrão comum em benefícios do Gupy)
 * 5) string inteira como 1 item
 */
export function htmlToBullets(html: string | null | undefined): string[] {
  if (!html) return [];

  const liMatches = html.match(/<li[^>]*>([\s\S]*?)<\/li>/gi);
  if (liMatches && liMatches.length > 0) {
    return liMatches.map((li) => stripHtml(li)).filter((s) => s.length > 2);
  }

  const pMatches = html.match(/<p[^>]*>([\s\S]*?)<\/p>/gi);
  if (pMatches && pMatches.length > 1) {
    return pMatches.map((p) => stripHtml(p)).filter((s) => s.length > 2);
  }

  const normalized = html
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/p>/gi, "\n")
    .replace(/<\/?div[^>]*>/gi, "\n");
  const text = stripHtml(normalized);

  const parts = text
    .split(/[\n•;]+/)
    .map((s) => s.trim())
    .filter((s) => s.length > 2);
  if (parts.length > 1) return parts;

  const emojiSplit = text.split(/(?=\s*\p{Extended_Pictographic})/u)
    .map((s) => s.trim())
    .filter((s) => s.length > 3);
  if (emojiSplit.length > 1) return emojiSplit;

  return text.length > 2 ? [text] : [];
}

/**
 * Palavras-chave que tipicamente prefixam seções no HTML de vagas (PT/EN).
 * PT pluraliza `el` → `eis` (Desejável → Desejáveis), então usamos prefixos
 * que casam ambos (`desej[áa]ve` cobre vel/veis).
 */
export const REQ_KEYWORDS: RegExp[] = [
  /requisitos/i, /qualifica/i, /requirements/i, /qualifications/i,
  /pr[ée][- ]?requisitos/i, /desej[áa]ve/i, /obrigat[óo]rios/i,
  /must have/i, /nice to have/i, /who you are/i, /what we are looking/i,
  /what you'?ll need/i, /habilidades/i, /skills/i, /compet[êe]ncias/i,
  /o que esperamos/i, /esperamos de voc[êe]/i, /o que buscamos/i,
  /o que precisa ter/i, /o que voc[êe] precisa/i, /quem somos buscando/i,
  /o que procuramos/i, /o que esper.{0,3}encontrar/i, /diferenciais/i,
  /atribui[cç][õo]es/i, /atividades/i, /o que voc[êe] vai fazer/i,
  /o que voc[êe] far[áa]/i, /desafios e impacto/i, /seu dia a dia/i,
  /perfil (do candidato|que buscamos|desejado|esperado|ideal)/i,
  /conhecimentos? (necess[áa]rios|t[ée]cnicos)/i,
];

export const BENEFIT_KEYWORDS: RegExp[] = [
  /benef[íi]cios/i, /benefits/i, /perks/i, /oferecemos/i, /we offer/i,
  /vantagens/i, /what we offer/i, /o que oferecemos/i, /additional information/i,
  /o que voc[êe] (ter[áa]|encontra)/i,
];

/**
 * Extrai items de uma seção (Requisitos / Benefícios) do HTML.
 * Encontra headers (h1-h6 ou <p><strong>), strippa tags inline, casa contra
 * os keywords. Conteúdo da seção é tudo até o próximo header.
 *
 * Acumula items de TODOS os headers que casam — alguns sites separam em
 * sub-seções (ex: Inter usa "Obrigatórios:" + "Desejáveis:" ambos pra requisitos).
 */
export function extractSection(html: string | null | undefined, keywords: RegExp[]): string[] {
  if (!html) return [];
  const decoded = decodeEntities(html);

  // NÃO incluir bare <strong> porque muitas vagas têm <strong> dentro de <li>
  // (ex: "<li>... entre <strong>Dez 2023</strong>...</li>") e isso truncaria
  // a seção antes dela ter qualquer <li> completo.
  const headerRe =
    /<(h[1-6])[^>]*>([\s\S]*?)<\/\1>|<p[^>]*>\s*<strong[^>]*>([\s\S]*?)<\/strong>\s*<\/p>/gi;

  type Header = { startIdx: number; endIdx: number; text: string };
  const headers: Header[] = [];
  let m: RegExpExecArray | null;
  while ((m = headerRe.exec(decoded)) !== null) {
    const inner = m[2] ?? m[3] ?? "";
    const text = inner.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
    if (text.length > 0 && text.length < 200) {
      headers.push({ startIdx: m.index, endIdx: headerRe.lastIndex, text });
    }
  }

  const allItems: string[] = [];
  const seenIdx = new Set<number>();

  for (let i = 0; i < headers.length; i++) {
    if (seenIdx.has(i)) continue;
    const matches = keywords.some((kw) => kw.test(headers[i].text));
    if (!matches) continue;
    seenIdx.add(i);

    const start = headers[i].endIdx;
    const end = i + 1 < headers.length ? headers[i + 1].startIdx : decoded.length;
    const sectionHtml = decoded.slice(start, end);

    const liMatches = sectionHtml.match(/<li[^>]*>([\s\S]*?)<\/li>/gi);
    if (!liMatches || liMatches.length === 0) continue;

    const items = liMatches
      .map((li) => htmlToText(li).trim())
      .filter((s) => s.length > 3 && s.length < 500);
    allItems.push(...items);

    if (allItems.length >= 15) break;
  }

  return allItems.slice(0, 15);
}

// ── Localização ──────────────────────────────────────────────────────────────

export const BR_PATTERN =
  /brazil|brasil|são paulo|s[aã]o paulo|rio de janeiro|recife|porto alegre|belo horizonte|salvador|brasília|, br$|, br /i;

export const STATE_MAP: Record<string, string> = {
  "são paulo": "SP", "sao paulo": "SP", "rio de janeiro": "RJ",
  "minas gerais": "MG", "rio grande do sul": "RS", "paraná": "PR", "parana": "PR",
  "santa catarina": "SC", "bahia": "BA", "pernambuco": "PE",
  "ceará": "CE", "ceara": "CE", "distrito federal": "DF",
  "espírito santo": "ES", "espirito santo": "ES", "goiás": "GO", "goias": "GO",
  "amazonas": "AM", "pará": "PA", "para": "PA", "maranhão": "MA",
  "paraíba": "PB", "alagoas": "AL", "rio grande do norte": "RN", "tocantins": "TO",
};

// Fallback city → state quando a vaga só fornece "Brazil - <cidade>" sem estado.
// Cobre as 30 maiores cidades + capitais. Match case-insensitive.
export const CITY_TO_STATE_MAP: Record<string, string> = {
  "são paulo": "SP", "sao paulo": "SP", "campinas": "SP", "santos": "SP",
  "ribeirão preto": "SP", "ribeirao preto": "SP", "são josé dos campos": "SP",
  "sao jose dos campos": "SP", "guarulhos": "SP", "osasco": "SP", "barueri": "SP",
  "rio de janeiro": "RJ", "niterói": "RJ", "niteroi": "RJ",
  "belo horizonte": "MG", "contagem": "MG", "uberlândia": "MG", "uberlandia": "MG",
  "porto alegre": "RS", "canoas": "RS", "caxias do sul": "RS",
  "curitiba": "PR", "londrina": "PR", "maringá": "PR", "maringa": "PR",
  "florianópolis": "SC", "florianopolis": "SC", "joinville": "SC", "blumenau": "SC",
  "salvador": "BA", "feira de santana": "BA",
  "recife": "PE", "olinda": "PE", "jaboatão dos guararapes": "PE", "jaboatao dos guararapes": "PE",
  "fortaleza": "CE", "caucaia": "CE",
  "brasília": "DF", "brasilia": "DF",
  "vitória": "ES", "vitoria": "ES", "vila velha": "ES",
  "goiânia": "GO", "goiania": "GO",
  "manaus": "AM", "belém": "PA", "belem": "PA", "são luís": "MA", "sao luis": "MA",
  "joão pessoa": "PB", "joao pessoa": "PB", "maceió": "AL", "maceio": "AL",
  "natal": "RN", "palmas": "TO", "campo grande": "MS", "cuiabá": "MT", "cuiaba": "MT",
};

export function parseLocation(location: string): { city: string; state: string } {
  // Suporta vários separadores:
  //   "São Paulo, São Paulo, Brasil"            → city=São Paulo, state=SP
  //   "Brazil- São Paulo" / "Brazil - São Paulo" → country-first, city=São Paulo
  //   "São Paulo - SP"                          → city=São Paulo, state=SP
  // Split por vírgula primeiro. Se só 1 parte e contém " - " ou "- ", tenta hífen.
  let parts = location.split(",").map((s) => s.trim()).filter(Boolean);
  if (parts.length === 1 && /\s-\s|-\s/.test(parts[0])) {
    parts = parts[0].split(/\s+-\s+|-\s+|\s+-/).map((s) => s.trim()).filter(Boolean);
  }

  // Detecta padrão country-first: primeiro elemento é "Brazil"/"Brasil"
  if (parts.length >= 2 && /^(brazil|brasil)$/i.test(parts[0])) {
    parts = parts.slice(1);
  }

  const city = parts[0] || "Brasil";
  const stateRaw = parts[1] || "";
  let state = STATE_MAP[stateRaw.toLowerCase()] ||
    (stateRaw.length === 2 ? stateRaw.toUpperCase() : "");

  // Fallback: se não conseguiu state via parts[1], tenta inferir da cidade.
  // Caso típico: "Brazil - São Paulo" só nos dá ["São Paulo"] após remover country.
  if (!state || state === "BR") {
    const fromCity = CITY_TO_STATE_MAP[city.toLowerCase()];
    state = fromCity || "BR";
  }

  return { city, state };
}

// Vagas "banco de talentos" — captura de CV disfarçada de vaga. Padrão comum em
// XP Inc, Inter, agregadores e empresas que mantêm pool sempre aberto.
// Como títulos são curtos, qualquer ocorrência de "banco de talentos" no
// título é tratada como talent pool — pega "[BANCO DE TALENTOS]", "Banco de
// Talentos - X", "X | Banco de Talentos", etc.
export const TALENT_POOL_TITLE_REGEXES: RegExp[] = [
  /banco\s+de\s+talentos/i,
  /talent\s+pool/i,
];

export const TALENT_POOL_DESC_REGEXES: RegExp[] = [
  /^\s*banco\s+de\s+talentos/i,
  /estamos\s+formando\s+um\s+banco\s+de\s+(talentos|dados)/i,
];

export function isTalentPoolTitle(title: string | null | undefined): boolean {
  const t = (title ?? "").trim();
  if (!t) return false;
  return TALENT_POOL_TITLE_REGEXES.some((re) => re.test(t));
}

/**
 * Detecta "banco de talentos" pela descrição. Limita a descrições CURTAS
 * (< 500 chars) começando com o padrão, porque vaga real com descrição longa
 * pode mencionar talent pool no meio sem ser captura de CV
 * (ex: "ao final do estágio, entrará no nosso banco de talentos").
 */
export function isTalentPoolDescription(description: string | null | undefined): boolean {
  const d = (description ?? "").trim();
  if (!d || d.length > 500) return false;
  return TALENT_POOL_DESC_REGEXES.some((re) => re.test(d));
}

export function isBrazil(location: string | null | undefined): boolean {
  return !!location && BR_PATTERN.test(location);
}

// ── Filtros ──────────────────────────────────────────────────────────────────

export const ENTRY_LEVEL_PATTERN =
  /est[áa]gi|estagi[áa]ri|^intern$| intern | internship|trainee|j[úu]nior| jr | jr\.|jr,|aprendiz|associate|entry[ -]?level|rec[ée]m[ -]?formad|primeiro emprego|1[ºo] emprego|analyst i$|analyst i,|analyst i |analyst ii$|analyst ii,|analyst ii |jovem aprendiz|dcs /i;

/** Retorna true se QUALQUER texto fornecido casar o padrão de entry-level. */
export function isEntryLevel(...texts: Array<string | null | undefined>): boolean {
  for (const t of texts) {
    if (t && ENTRY_LEVEL_PATTERN.test(t)) return true;
  }
  return false;
}

/**
 * Normaliza string pra comparação fuzzy (dedup, slug, comparações case-insensitive):
 * lowercase, remove acentos, colapsa whitespace, tira pontuação.
 */
export function normalizeForDedup(s: string | null | undefined): string {
  if (!s) return "";
  return s
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "") // remove combining marks
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/** Parse "Salário R$ 2.500,00" → 2500 (BRL number). Best-effort. */
export function parseSalary(value: unknown): number | null {
  if (value == null) return null;
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value !== "string") return null;
  const digits = value.replace(/[^\d]/g, "");
  if (!digits) return null;
  const n = parseInt(digits, 10);
  return Number.isFinite(n) ? n : null;
}

// Vagas operacionais de varejo/serviços — fora do target (universitários
// corporativos). Mesma lista usada em sync-jobs-apify e sync-jobs-brazil.
export const TITLE_BLACKLIST_REGEXES: RegExp[] = [
  /\batendente\b/i,
  /\bbalconist[ao]\b/i,
  /\boperador(a)? de caix[ao]\b/i,
  /\boperador(a)? de loja\b/i,
  /\bcaixa de loja\b/i,
  /\baux(iliar)? de cozinha\b/i,
  /\baux(iliar)? de loja\b/i,
  /\baux(iliar)? de limpeza\b/i,
  /\baux(iliar)? de produ[cç][aã]o\b/i,
  /\baux(iliar)? log[íi]stico\b/i,
  /\baux(iliar)? de servi[cç]os gerais\b/i,
  /\bservi[cç]os gerais\b/i,
  /\brepositor(a)?\b/i,
  /\bempacotador(a)?\b/i,
  /\bestoquista\b/i,
  /\boperador(a)? de telemarketing\b/i,
  /\bteleoperador(a)?\b/i,
  /\bvendedor(a)? de loja\b/i,
  /\bpromotor(a)? de vendas?\b/i,
  /\bdemonstrador(a)?\b/i,
  /\bvigilante\b/i,
  /\bporteiro(a)?\b/i,
  /\bmotoboy\b/i,
  /\bmotorista\b/i,
  /\bentregador(a)?\b/i,
  /\boperador(a)? de produ[cç][aã]o\b/i,
  /\boperador(a)? de m[áa]quinas?\b/i,
  /\bsoldador(a)?\b/i,
  /\bcosturei[rt][ao]\b/i,
  /\bcamareir[ao]\b/i,
  /\bgar[cç]on(ete)?\b/i,
  /\bcopeiro(a)?\b/i,
  /\bpadeiro(a)?\b/i,
  /\baçougueiro(a)?\b/i,
  /\bconfeiteiro(a)?\b/i,
  /\bsushiman\b/i,
  /\bpizzaiolo\b/i,
  /\b(jovem )?aprendiz(agem)?\b/i,
  /\binstrutor(a)? de muscula[cç][aã]o\b/i,
  /\bpersonal trainer\b/i,
  /\bprofessor(a)? de muscula[cç][aã]o\b/i,
  /\brecep[cç]ionista de academia\b/i,
  // Discriminatórias (gênero) — ilegal pela CLT
  /\b(estagi[aá]ri[ao]|vaga)\s+(feminin|masculin)/i,
  /\bsomente\s+(mulher|homem|feminin|masculin)/i,
  /\bexclusiv[oa]\s+para\s+(mulher|homem)/i,
];

export function isTitleBlacklisted(title: string | null | undefined): boolean {
  const t = (title ?? "").trim();
  if (!t) return false;
  for (const re of TITLE_BLACKLIST_REGEXES) {
    if (re.test(t)) return true;
  }
  return false;
}

// Nomes de empresa "spammy" — agregadores, emojis, "Confidencial".
export const COMPANY_NAME_BLACKLIST_REGEXES: RegExp[] = [
  /^programa de est[áa]gio$/i,
  /vagas de est[áa]gio\?? *temos/i,
  /[\u{1F300}-\u{1FAFF}]/u,
  /^confidencial$/i,
  /^empresa confidencial$/i,
  /^vaga confidencial$/i,
  /^anonim[oa]$/i,
  /^a definir$/i,
  /^sem identifica[çc][ãa]o$/i,
  /\bacademia\b/i,
  /\bgreenlife\b/i,
  /^sunojobs$/i,
  /^oval\s*-\s*vagas/i,
  /^conex[aã]o talento$/i,
  /^vagas instituto/i,
  /^seja pasa!?$/i,
  /^fa[cç]a parte do time/i,
  /^talentos barcelos/i,
  /^programa de est[áa]gio e aprendiz \d+$/i,
  /\bassessoria$/i,
  /\bvagas\s+(de\s+)?emprego/i,
  /\s*\|\s*vagas\b/i,
  /^vagas\s+confiden/i,
  /^recrutamento\s*[&e]\s*sele[cç][aã]o/i,
  /\brecrutament[oa]?\s+e\s+carreira/i,
  /\bconsultoria\s+(em|e\s+desenvolvi)/i,
  /\bcentro\s+de\s+est[aá]gio/i,
  /^pib-teste/i,
];

export function isCompanyNameBlacklisted(name: string | null | undefined): boolean {
  const n = (name ?? "").trim();
  if (!n) return false;
  for (const re of COMPANY_NAME_BLACKLIST_REGEXES) {
    if (re.test(n)) return true;
  }
  return false;
}

// ── Inferência ───────────────────────────────────────────────────────────────

/**
 * Infere área da vaga. Ordem importa — keywords MAIS específicas vão antes
 * (Jurídico antes de Tecnologia, senão "Programa de Estágio em Direito"
 * cai em Tecnologia por causa de "programa").
 *
 * ⚠️ SINCRONIZAÇÃO CROSS-LANGUAGE — leia antes de editar
 *
 * As strings retornadas (1º elemento de cada tupla nas `rules` + fallback
 * "Geral") são as ÁREAS que vagas terão no banco. O app Flutter mostra
 * uma lista de áreas pro user escolher como "áreas desejadas" — essa
 * lista precisa BATER com o que esta função produz, senão:
 *   • user escolhe área que nenhuma vaga tem (feed vazio), ou
 *   • vagas viram pra "Geral" sem categoria correta.
 *
 * Catálogo Dart (single source of truth no app):
 *   lib/core/constants/job_areas.dart
 *
 * Drift atual conhecido (2026-05-26):
 *   • "Design" existe no app Dart mas NÃO tem categoria própria aqui —
 *     vagas de design caem em "Produto" (regex inclui "design|ux|ui").
 *     Mitigado pelo mapa de sinônimos em filter_helpers.dart no client
 *     (Design ↔ Produto bidirecional), então user que escolhe "Design"
 *     ainda vê as vagas de Produto. Pra ter filtro estrito de Design,
 *     adicionar regex próprio AQUI antes de "Produto" e atualizar
 *     filter_helpers.dart pra remover Design dos sinônimos de Produto.
 *
 * Se adicionar/remover/renomear área aqui, atualizar o catálogo Dart também.
 *
 * @param title título da vaga
 * @param contextHints texto opcional concatenado (departamento, descrição, tags)
 */
export function inferArea(title: string, contextHints?: string | null): string {
  const rules: Array<[string, RegExp]> = [
    // Saúde antes de tudo — vagas tipo "Estágio em Enfermagem" tinham
    // "enferma" pegando matchers genéricos depois e caindo em Produto/
    // Operações/RH errado. 22 vagas mal classificadas em 2026-05-27.
    ["Saúde", /(enferma|enferm[ae]ir[ao]|medic|m[ée]dic[ao]|farma|farm[áa]cia|farmac[êe]utic|fisio|fisioterap|nutricion|psic[óo]log|psicologia|biom[ée]dic|odont|odontol[óo]gi|veterin|cl[íi]nica|hospital|sa[úu]de|enfermagem|radiolo|terapeut|fonoaudi)/],
    ["Jurídico", /(jur[íi]dic|direito|advog|advocacia|legal|compliance|contencioso|tribut[áa]rio|paralegal|direito (?:empresarial|trabalhista|c[íi]vel|tribut[áa]rio|penal|consumidor)|escrit[óo]rio de advocacia)/],
    ["Tecnologia", /(engenharia de software|desenvolved|software engineer|backend|frontend|full[- ]?stack|dados|\bdata\b|machine learning|\bml\b|devops|sre|cloud|infraestrutura|\bqa\b|testes?|cybersecurity|segurança da informação|tech|tecnologia|\bti\b|program(?:a[cdr]|ação|ador)|sistemas)/],
    ["Marketing", /(marketing|growth|crm|mídia|branding|comunicação|publicidade|social media)/],
    ["Vendas", /(vendas|sales|comercial|account exec|consultor comercial|business development|bdr|sdr)/],
    ["Finanças", /(finanças|financeir|controladoria|tesouraria|fp&a|cont[áa]bi|accounting|treasury|investimento|finance|financ|controller|fp&a|auditoria|contas a (?:pagar|receber)|cr[ée]dito)/],
    // Tokens curtos com \b: "rh"/"hr"/"gente" sem fronteira casavam dentro de
    // "trabalho", "hora", "urgente", "agente", "inteligente" → falso RH.
    ["Recursos Humanos", /(recursos humanos|\brh\b|\bgente\b|people|talent|recruiter|recruta|treinamento|human|\bhr\b)/],
    ["Operações", /(operações|operations|logística|supply chain|\bcs\b|customer success|atendimento|suporte|opera[cç]ões|supply|compras|suprimentos)/],
    // \b em "pm"/"ux"/"ui": sem fronteira casavam dentro de "auxiliar" (ux),
    // "arquitetura"/"pesquisa" (ui), etc. → falso Produto.
    ["Produto", /(produto|product manager|\bpm\b|design de produto|\bux\b|\bui\b|design|product)/],
    ["Engenharia", /(engenharia(?! de software)|engenheir(?!o de software)|edifica[çc])/],
    ["Administrativo", /(administrativ|administração|secretaria|admin)/],
  ];

  // 1ª passada: SÓ o título. O título é o sinal mais confiável da área.
  // Classificar pelo título antes de olhar a descrição impede que termos
  // genéricos do corpo da vaga (benefícios, blurb institucional da empresa)
  // sobrescrevam um título claro. Era exatamente isso que jogava
  // "Estágio Financeiro", "Engenharia Mecânica", "Gente e Gestão (RH)" etc.
  // pra Saúde só porque a descrição citava "plano de saúde"/"hospital".
  const titleText = (title ?? "").toLowerCase();
  for (const [area, re] of rules) if (re.test(titleText)) return area;

  // 2ª passada: título não deu sinal (ex.: "Estagiário", "Analista" puro).
  // Aí sim caímos na descrição — mas REMOVENDO frases de benefício, que
  // aparecem em quase toda vaga brasileira e não dizem nada sobre a área
  // (principal fonte dos falsos positivos de "Saúde" via "plano de saúde").
  const hintsText = stripBenefitNoise((contextHints ?? "").toLowerCase());
  for (const [area, re] of rules) if (re.test(hintsText)) return area;

  return "Geral";
}

/**
 * Remove frases de benefício/boilerplate que poluíam a inferência de área
 * quando a descrição era usada como hint. "Plano de saúde", "assistência
 * médica" e afins estão em quase toda vaga e arrastavam vagas de qualquer
 * setor pra "Saúde". Mexe SÓ nos hints (descrição) — nunca no título.
 */
function stripBenefitNoise(text: string): string {
  return text.replace(
    /plano[s]? de sa[úu]de|assist[êe]ncia m[ée]dica|assist[êe]ncia [àa]? ?sa[úu]de|seguro[s]?(?: de)? sa[úu]de|conv[êe]nio m[ée]dico|vale[- ]?sa[úu]de|aux[íi]lio[- ]?sa[úu]de|plano[s]? odontol[óo]gico[s]?|assist[êe]ncia odontol[óo]gica/g,
    " ",
  );
}

const JOB_TYPE_KEYWORDS: Array<[RegExp, string]> = [
  // Cobre: estagio, estágio, estagiario, estagiaria, estagiário, estagiária,
  // estagiárias, estagiários. Aprendiz vai como estágio (CHECK constraint só
  // aceita 4 valores).
  [/est[aá]gi(?:o|os|[aá]ri[oa]s?)|^intern$|internship|aprendiz/i, "estagio"],
  [/trainee/i, "trainee"],
  [/temporári[oa]|tempor[aá]rio/i, "temporario"],
];

/** Infere job_type a partir do título + (opcional) employment_type da API. */
export function inferJobType(title: string, employmentType?: string | null): string {
  const text = `${title ?? ""} ${employmentType ?? ""}`;
  for (const [re, type] of JOB_TYPE_KEYWORDS) {
    if (re.test(text)) return type;
  }
  return "clt_junior";
}

export function inferWorkModel(location: string | null | undefined): string {
  if (!location) return "presencial";
  const l = location.toLowerCase();
  if (/remot|home[ -]?office/.test(l)) return "remoto";
  if (/h[íi]brid|hybrid/.test(l)) return "hibrido";
  return "presencial";
}

// ── DB ───────────────────────────────────────────────────────────────────────

/**
 * Marca como inativas vagas que não foram vistas no último sync.
 * `last_seen_at` é atualizado pra now() em cada upsert, então vagas que
 * sumiram do ATS (removidas pela empresa) caem fora após cutoffHours.
 *
 * @param source string exata ou pattern SQL LIKE (com `%`)
 */
export async function markStaleJobsInactive(
  supabase: SupabaseClient,
  source: string,
  cutoffHours: number,
): Promise<number> {
  const cutoff = new Date(Date.now() - cutoffHours * 60 * 60 * 1000).toISOString();
  const query = supabase
    .from("jobs")
    .update({ is_active: false }, { count: "exact" })
    .eq("is_active", true)
    .lt("last_seen_at", cutoff);

  const filtered = source.includes("%") ? query.like("source", source) : query.eq("source", source);
  const { error, count } = await filtered;
  if (error) {
    console.error(`markStaleJobsInactive(${source}) failed:`, error.message);
    return 0;
  }
  return count ?? 0;
}

export interface CompanyExtra {
  logo_url?: string | null;
  website?: string | null;
  description?: string | null;
  description_html?: string | null;
}

/**
 * Upsert em `companies` por `slug`. Quem chama monta o slug completo
 * (com prefixo de origem, ex: `greenhouse:inter`, `gupy:nubank`, `brz:hotmart`).
 * Retorna company_id ou null em erro.
 */
export async function getOrCreateCompany(
  supabase: SupabaseClient,
  fullSlug: string,
  displayName: string,
  source: string,
  extra?: CompanyExtra,
): Promise<string | null> {
  const payload: Record<string, unknown> = {
    slug: fullSlug,
    name: displayName,
    source,
  };
  if (extra?.logo_url !== undefined) payload.logo_url = extra.logo_url;
  if (extra?.website !== undefined) payload.website = extra.website;
  if (extra?.description !== undefined) payload.description = extra.description;
  if (extra?.description_html !== undefined) payload.description_html = extra.description_html;

  const { data, error } = await supabase
    .from("companies")
    .upsert(payload, { onConflict: "slug" })
    .select("id")
    .single();

  if (error) {
    console.error(`Company upsert failed for ${fullSlug}:`, error.message);
    return null;
  }
  return data.id as string;
}

// ── Async / Net ──────────────────────────────────────────────────────────────

export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Fetch com timeout via AbortController. Default 15s — suficiente pra a maioria
 * dos ATSs públicos sem bloquear o orquestrador num único endpoint lento.
 */
export async function fetchWithTimeout(
  url: string,
  init: RequestInit = {},
  timeoutMs = 15_000,
): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}
