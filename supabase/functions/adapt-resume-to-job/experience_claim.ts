/**
 * Predicado anti-invenção de EXPERIÊNCIA, compartilhado pelo v1 e pelo v2.
 *
 * Por que existe como módulo próprio:
 *   1. A checagem nasceu só no v2 (`assertSummaryDoesNotClaimExperience`), mas a
 *      auditoria de 29/07 mediu em produção que os currículos com cargo
 *      inventado saíram pelo **v1** — que não tinha checagem nenhuma nesse
 *      sentido. `validateAdaptation` (index.ts) só barra o "sumiço" (input cheio
 *      → output vazio), nunca o inverso.
 *   2. `index.ts` termina em `Deno.serve`, então importar de lá para testar
 *      subiria um servidor. Mesmo motivo que gerou `reasons.ts` no analyze-match.
 *
 * É um predicado PURO (devolve o problema, não lança) para o golden set poder
 * exercitá-lo direto, sem montar request. Quem chama decide como reclamar —
 * o v1 e o v2 têm classes de erro diferentes.
 */

/** Uma alegação de experiência que o perfil não sustenta. */
export interface ExperienceClaim {
    /** O trecho exato que disparou, já normalizado (sem acento, minúsculo). */
    readonly match: string
    /** De onde veio: o resumo, ou o bloco de experiências do output. */
    readonly field: 'summary' | 'experiences'
}

/** Tira acento e caixa: "experiência" → "experiencia". */
function flatten(input: unknown): string {
    return String(input ?? '')
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .toLowerCase()
}

/**
 * Afirmações de experiência vivida, PT e EN (o output sai nas duas línguas).
 *
 * O regex original só casava `experiência` COLADA numa preposição. Rodando-o
 * contra variantes reais, passavam batido — todas dizendo a mesma mentira:
 *   "com experiência prática em", "experiência acadêmica em", "atuei na",
 *   "já trabalhei com", "responsável pela", "experiente em".
 *
 * Cada alternativa aqui é uma dessas. Ampliar isso é barato; o que custa caro é
 * o falso positivo, e é para isso que serve o mitigador abaixo.
 */
const CLAIM_RE =
    /\bexperiencias?\s+(?:em|com|na|no|de)\b|\bexperiencias?\s+(?:pratica|academica|profissional|previa|comprovada)\b|\bexperiente\s+em\b|\banos?\s+de\s+experiencia\b|\batu(?:ei|ou|ando|acao)\s+(?:em|como|na|no|nas|nos)\b|\btrabalh(?:ei|ou|ando)\s+(?:em|com|na|no|como)\b|\bresponsavel\s+(?:por|pela|pelo)\b|\bvivencia\s+(?:em|com|na|no)\b|\bexperience\s+(?:in|with|at)\b|\bexperienced\s+in\b|\byears?\s+of\s+experience\b|\bworked\s+(?:at|with|on|as)\b/g

/**
 * Contexto imediatamente ANTES que torna a menção legítima.
 *
 * Frase de busca é exatamente o que o CV de um estudante deve dizer —
 * "buscando experiência em Suprimentos", "primeira experiência", "sem
 * experiência prévia". Barrar isso seria o erro oposto: deixar gente honesta
 * sem currículo. Foi o BLOQUEADOR C do golden set.
 */
const MITIGATOR_RE =
    /(?:buscando|busco|buscar|em busca de|procurando|procuro|ganhar|adquirir|conquistar|desenvolver|primeira|sem|nenhuma|pouca|nao tenho|oportunidade de|interesse em|vontade de|seeking|looking for|to gain|gain|first|without|no prior|opportunity to)\s*$/

/**
 * LIMITE CONHECIDO E DELIBERADO: a prosa só é checada com ZERO experiências.
 *
 * O ideal seria comparar a MAGNITUDE alegada com a real — "5 anos de
 * experiência" é mentira para quem tem um estágio de 6 meses. Mas julgar isso
 * exige a DURAÇÃO das experiências, que este predicado não recebe, e chutar um
 * piso por CONTAGEM não funciona: tentei `>= 2` e o caso `ok-006` do golden set
 * reprovou na hora, com razão — quem tem 1 experiência real PODE dizer
 * "experiência em X". Barrar essa pessoa é o erro pior, porque a deixa sem
 * currículo (BLOQUEADOR C).
 *
 * Fica registrado como o buraco (a) do achado P0-2, ainda aberto. Fechar exige
 * passar a duração total para cá — mudança de assinatura e de dois call sites,
 * que não cabe nesta fatia sem tornar o conserto arriscado.
 */
const LASTRO_SUFICIENTE = 1

/**
 * Procura alegação de experiência que o perfil não sustenta.
 *
 * @param realExperienceCount quantas experiências existem no PERFIL (input).
 * @param summary o resumo gerado.
 * @param outputExperienceCount quantas experiências o modelo devolveu.
 * @returns lista vazia quando está tudo bem.
 */
export function findUnsupportedExperienceClaims(
    realExperienceCount: number,
    summary: unknown,
    outputExperienceCount = 0,
): ExperienceClaim[] {
    const claims: ExperienceClaim[] = []

    // (1) Cargo inventado. Perfil sem experiência nenhuma não pode receber um
    // bloco de experiências preenchido — foi assim que 3 currículos saíram com
    // até 3 cargos que a pessoa nunca teve. Nenhum regex de prosa pegaria isso.
    if (realExperienceCount === 0 && outputExperienceCount > 0) {
        claims.push({ match: `${outputExperienceCount} experiencia(s) no output`, field: 'experiences' })
    }

    if (realExperienceCount >= LASTRO_SUFICIENTE) return claims

    // (2) Prosa que afirma vivência.
    const flat = flatten(summary)
    if (flat.length === 0) return claims

    for (const m of flat.matchAll(CLAIM_RE)) {
        const idx = m.index ?? 0
        const before = flat.slice(Math.max(0, idx - 40), idx)
        if (MITIGATOR_RE.test(before)) continue
        claims.push({ match: m[0].trim(), field: 'summary' })
    }

    return claims
}

/** Mensagem única para o modelo, usada pelos dois caminhos no retry. */
export function experienceClaimMessage(claim: ExperienceClaim, realExperienceCount: number): string {
    if (claim.field === 'experiences') {
        return `output traz ${claim.match} mas o perfil tem 0 experiências. ` +
            `Não invente emprego: devolva experiences vazio e fale de formação, ` +
            `projetos e conhecimento.`
    }
    // Com zero experiências a palavra exata é "inexistente" — e é o termo que o
    // caso adv-001 do golden set fixa desde a primeira correção.
    const qualificacao = realExperienceCount === 0
        ? 'experiência profissional inexistente'
        : `experiência profissional que o perfil não sustenta (tem ${realExperienceCount})`
    return `summary alega ${qualificacao} ("${claim.match}"). ` +
        `Reescreva como conhecimento/formação (ex.: "com conhecimento em", ` +
        `"familiaridade com") ou como objetivo ("buscando experiência em"), ` +
        `nunca como experiência já vivida.`
}
