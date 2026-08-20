// Razões do match — parte determinística, separada do `index.ts` para poder
// ser TESTADA. O `index.ts` termina num `Deno.serve(...)` de módulo: importá-lo
// num teste subiria um servidor e travaria a suíte.
//
// R6: extração mecânica, sem mudança de comportamento. O `index.ts` passa a
// importar daqui.

export interface MatchReason {
  label: string
  matched: boolean
  weight: number
  detail?: string
}

/** Nome do modelo de trabalho como a pessoa lê na tela. */
function rotuloModelo(modelo: string): string {
  switch (modelo) {
    case 'remoto': return 'Remoto'
    case 'hibrido': return 'Híbrido'
    case 'presencial': return 'Presencial'
    default: return modelo
  }
}

/**
 * Peso de Localização e de Modelo no Cenário A do prompt (`index.ts`, seção
 * ESTRATÉGIA: Área 30, Tipo 20, Localização 15, Modelo 15, Skills 10).
 */
const PESO_DIMENSAO = 15

/**
 * Rótulo comparável: sem acento, sem caixa, sem espaço nas bordas.
 *
 * O casamento era por string exata em minúsculas, então qualquer variação que o
 * modelo devolvesse ("Localizacao", "LOCALIZAÇÃO ") escapava da reconciliação
 * em silêncio — e o usuário via a penalidade falsa de novo.
 */
function canonical(label: string): string {
  return String(label ?? '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .trim()
    .toLowerCase()
}

/**
 * Cenário C canônico: a única razão é "Sem perfil". O prompt manda score 50
 * FIXO nesse caso e o `index.ts` respeita isso explicitamente
 * (§ parseAndValidate, `isScenarioC`). Nenhum reconciliador pode encostar:
 * o caminho de CACHE re-deriva o score a partir das reasons sempre que elas
 * mudam, então inserir ou alterar uma linha aqui devolve 0 (ou 15, se entrar a
 * Localização de vaga remota) no lugar de 50.
 *
 * Não é hipótese: medido em 04/08/2026, **872 linhas de Cenário C** em
 * `match_analyses` são de usuários que HOJE têm `work_models` preenchido — ou
 * seja, passam pelo `aceitaEsteModelo` e entram no laço. O early-return de
 * quem não tem prefs mascarava isso.
 */
export function isScenarioC(reasons: MatchReason[]): boolean {
  return reasons.length === 1 &&
    canonical(reasons[0]?.label ?? '') === 'sem perfil' &&
    reasons[0]?.matched !== true
}

/**
 * Normaliza work_mode do schema relacional (EN: `remote`/`hybrid`/`in_person`)
 * pro vocabulário que `jobs.work_model` usa (PT: `remoto`/`hibrido`/`presencial`).
 * Sem isso, a IA tentava casar "in_person" com "presencial" textualmente e
 * marcava matched=false mesmo o user tendo presencial nas prefs.
 *
 * Valores legacy (PT) passam intactos — `user_preferences.work_models`
 * sempre foi PT.
 */
export function normalizeWorkMode(s: string): string {
  switch (s) {
    case 'remote': return 'remoto'
    case 'hybrid': return 'hibrido'
    case 'in_person': return 'presencial'
    default: return s // já PT ou desconhecido — passa intacto
  }
}

/**
 * Correção determinística das razões de vaga REMOTA (revisão UX 28/07/2026).
 *
 * Dois defeitos observados ao vivo no detalhe da vaga, ambos vindos do modelo:
 *
 *  1. `{"label":"Modelo","matched":false,"detail":"Você prefere remoto, mas a
 *     vaga é remoto."}` — a frase se contradiz sozinha e conta um ACERTO como
 *     falha. É a mesma classe de erro que `normalizeWorkMode` já trata na
 *     ENTRADA (in_person × presencial); aqui tratamos a SAÍDA.
 *  2. "Localização — <cidade> não está entre suas cidades preferidas" numa vaga
 *     remota, contradizendo a regra que os filtros anunciam ("Remoto sempre
 *     passa"). Cidade não limita quem trabalha remoto.
 *
 * Mesma doutrina do score: a IA propõe, o código determinístico valida.
 *
 * REVISÃO 29/07 — esconder não era corrigir. A primeira versão apenas REMOVIA a
 * linha de Localização, então a vaga remota continuava sem os 15 pontos dela e
 * tetava em 85 enquanto a mesma vaga na cidade da pessoa chegava a 100. A
 * penalidade tinha virado invisível em vez de deixar de existir — e o
 * "Esperado" do achado é literalmente que vaga remota NÃO perca ponto por
 * cidade. Pior: o cálculo determinístico do cliente já dava esses 15 pontos, e
 * os dois motores divergiam na mesma vaga.
 *
 * REVISÃO 30/07 — a contradição não era só do remoto. Verificando o flip em
 * produção, o app mostrou numa vaga HÍBRIDA: "Você prefere remoto ou híbrido,
 * mas a vaga é híbrida" — a pessoa prefere híbrido, a vaga É híbrida, e isso
 * contava como falha. Consertar só o remoto repetiria o erro que gerou esta
 * revisão: corrigir a instância fotografada e deixar a irmã viva.
 *
 * Regras, então:
 *  - MODELO vira matched com peso cheio (15) sempre que o modelo da vaga está
 *    entre os que a pessoa aceita — remoto, híbrido ou presencial.
 *  - LOCALIZAÇÃO só é dispensada em vaga REMOTA, e aí com peso cheio. Em
 *    híbrida e presencial a cidade pesa de verdade e não pode ser perdoada.
 *  - Se a pessoa NÃO aceita o modelo da vaga, nada é mexido: é desencontro real
 *    e o score deve dizer isso.
 *  - Localização ausente é INSERIDA em vaga remota. Sem isso, duas vagas
 *    remotas pontuariam diferente só porque o modelo emitiu a linha numa e não
 *    na outra — medido: 2.343 de 3.132 análises remotas trazem a dimensão.
 */
export function reconcileRemoteReasons(
  reasons: MatchReason[],
  // deno-lint-ignore no-explicit-any
  job: any,
  // deno-lint-ignore no-explicit-any
  prefs: any,
): MatchReason[] {
  // Cenário C não se reconcilia — ver `isScenarioC`.
  if (isScenarioC(reasons)) return reasons

  const jobModel = normalizeWorkMode(String(job?.work_model ?? '').trim().toLowerCase())
  if (!jobModel) return reasons

  const accepted: string[] = Array.isArray(prefs?.work_models) ? prefs.work_models : []
  const aceitaEsteModelo = accepted
    .map((w: unknown) => normalizeWorkMode(String(w ?? '').trim().toLowerCase()))
    .includes(jobModel)

  // O modelo da vaga não está entre os que a pessoa aceita: desencontro real,
  // não se mexe em nada.
  if (!aceitaEsteModelo) return reasons

  const isRemoto = jobModel === 'remoto'

  let sawLocation = false
  const out: MatchReason[] = []
  for (const r of reasons) {
    const label = canonical(r.label)

    if (label === 'modelo' && !r.matched) {
      out.push({
        ...r,
        matched: true,
        // Peso FORÇADO, não herdado. A IA costuma mandar weight 0 quando
        // considera a dimensão falha — herdar isso consertaria o texto e
        // deixaria o ponto para trás, que é o defeito que estamos fechando.
        weight: PESO_DIMENSAO,
        detail: `${rotuloModelo(jobModel)}, que é como você prefere trabalhar.`,
      })
      continue
    }

    if (isRemoto && label === 'localizacao') {
      sawLocation = true
      if (!r.matched) {
        out.push({
          ...r,
          matched: true,
          weight: PESO_DIMENSAO,
          detail: 'Vaga remota — de onde você mora não pesa aqui.',
        })
        continue
      }
    }

    out.push(r)
  }

  // Linha ausente é inserida, senão duas vagas remotas pontuam diferente só
  // porque o modelo emitiu a dimensão numa e não na outra.
  if (isRemoto && !sawLocation) {
    out.push({
      label: 'Localização',
      matched: true,
      weight: PESO_DIMENSAO,
      detail: 'Vaga remota — de onde você mora não pesa aqui.',
    })
  }

  // Log distinto: sem isto a correção apareceria só como "score divergence" e
  // seria confundida com regressão do modelo. Mede quanto o gpt erra aqui.
  if (out.length !== reasons.length || out.some((r, i) => r !== reasons[i])) {
    console.log(
      `[analyze-match] work-mode reasons reconciled job=${job?.id ?? '?'} ` +
        `model=${jobModel} before=${reasons.length} after=${out.length}`,
    )
  }
  return out
}

// ────────────────────────────────────────────────────────────────────────────
// Skills — achado A4 do relatório de UX de 03/08/2026
// ────────────────────────────────────────────────────────────────────────────

/** A dimensão é a de habilidades? Cobre "Skills", "Skills/Ferramentas", "Habilidades". */
function isSkillsLabel(label: string): boolean {
  const c = canonical(label)
  return c.includes('skill') || c.includes('habilidade')
}

/**
 * A frase NEGA QUE A PESSOA TENHA DECLARADO skills — em oposição a dizer que as
 * skills dela não bateram com a vaga?
 *
 * A distinção é o coração desta correção e foi tirada da produção, não do
 * palpite. Medindo os `detail` da dimensão Skills em `match_analyses`
 * (04/08/2026) aparecem duas famílias:
 *
 *  (A) NEGA A EXISTÊNCIA — é o defeito. ~14,4 mil ocorrências, sendo 11.086 de
 *      "Você não declarou skills específicas para comparar." Essa frase é
 *      cópia LITERAL do few-shot do próprio system prompt
 *      (`index.ts`, Exemplo 1); o modelo repete o exemplo em vez de olhar o
 *      candidato. Para quem tem skills gravadas, é simplesmente falso.
 *
 *  (B) DIZ QUE NÃO BATEU — é VERDADE e não pode ser tocado:
 *      "Nenhuma skill sua aparece nos requisitos da vaga." (717)
 *      "Você não possui skills que correspondem aos requisitos da vaga." (947)
 *      "Excel não aparece nos requisitos desta vaga." (141)
 *      Reescrever essas destruiria informação correta — e a de Excel é
 *      justamente a MELHOR das frases, porque nomeia a skill.
 *
 * Por isso o teste não é "matched=false" nem o verbo da frase — é a CLÁUSULA DE
 * FINALIDADE. Quem diz "para comparar" / "para comparação" está dizendo que não
 * há O QUE comparar (existência). Quem cita "requisitos", "batem",
 * "correspondem", "aparece", "exigidas" está comparando de fato (família B).
 *
 * A primeira versão desta função usava o verbo ("não declarou" ⇒ nega
 * existência) e a varredura da CAUDA em produção derrubou a regra nos dois
 * sentidos — motivo de ela estar escrita assim e não do jeito óbvio:
 *   - falso POSITIVO: "Você não declarou skills que batem com os requisitos da
 *     vaga." (47 linhas) é comparação, não negação de existência;
 *   - falso NEGATIVO: "Você não possui skills técnicas para comparar." (52) e
 *     "Não há skills específicas para comparar." (64) negam existência sem usar
 *     nenhum dos verbos que a regra antiga procurava.
 *
 * As DUAS exclusões existem pelo mesmo motivo: há frases em que quem não tem
 * skills é a VAGA, não a pessoa — e reescrevê-las culparia o candidato por um
 * anúncio mal escrito. Varridas em produção:
 *   - "requisito": "Não há requisitos de skills para comparar." (45 linhas)
 *   - "na vaga" / "da vaga": "Não há skills específicas na vaga para comparar."
 *     (22), "Não há skills na vaga para comparar." (6), "Nenhuma skill foi
 *     exigida na vaga para comparação." (1) e irmãs — ~28 linhas no total.
 * Nenhuma frase legítima da família (A) casa essas exclusões: as que citam a
 * vaga do lado do candidato usam "COM a vaga" ("...para comparar com a vaga."),
 * que não colide.
 */
function negaTerSkills(detail: string): boolean {
  const d = canonical(detail)
  if (!d.includes('skill') && !d.includes('habilidade')) return false
  // A ausência é atribuída à VAGA, não à pessoa — não é o defeito do A4.
  if (d.includes('requisito') || d.includes('na vaga') || d.includes('da vaga')) return false
  return d.includes('para comparar') || d.includes('para comparacao')
}

/** Lista em português: "A", "A e B", "A, B e C". */
function listaPt(itens: string[]): string {
  if (itens.length <= 1) return itens[0] ?? ''
  return `${itens.slice(0, -1).join(', ')} e ${itens[itens.length - 1]}`
}

/**
 * Texto factual que substitui a negação falsa. Nomeia o que a pessoa DE FATO
 * declarou e mantém o veredito do modelo (não bateu) — não afirmamos match que
 * não foi avaliado, só paramos de negar a existência do dado.
 *
 * Teto de 3 nomes + "e mais N": `index.ts` corta `detail` em 200 chars na
 * entrada, e uma lista longa viraria parede de texto no cartão.
 */
function detalheSkillsDeclaradas(skills: string[]): string {
  const mostra = skills.slice(0, 3)
  const resto = skills.length - mostra.length
  const lista = resto > 0 ? `${listaPt(mostra)} e mais ${resto}` : listaPt(mostra)
  const plural = skills.length > 1 || resto > 0
  const texto = plural
    ? `Você declarou ${lista} — não encontrei essas skills nos requisitos desta vaga.`
    : `Você declarou ${lista} — não encontrei essa skill nos requisitos desta vaga.`
  // Cinto de segurança: nome de skill é texto livre do usuário e pode ser longo.
  return texto.length <= 200 ? texto : `Suas skills declaradas não aparecem nos requisitos desta vaga.`
}

/**
 * Correção determinística da dimensão SKILLS (achado A4, relatório de UX
 * 03/08/2026).
 *
 * O defeito: o cartão de match diz "Você não declarou skills específicas para
 * comparar" para quem declarou. Medido em 04/08/2026: **6.450 análises** com
 * essa família de frase pertencem a usuários que TÊM linhas em `profile_skills`
 * — 442 pessoas distintas. Só na v14, 37,6% das negações são falsas. E é
 * intermitente: duas análises do mesmo usuário separadas por 37 ms se
 * contradizem, o que descarta "consertar o prompt" como garantia.
 *
 * Mesma doutrina de `reconcileRemoteReasons`: a IA propõe, o código
 * determinístico valida.
 *
 * Regras:
 *  - O SCORE NÃO MUDA. `matched` e `weight` são preservados como vieram; só o
 *    texto é reescrito. Não estamos afirmando que as skills batem — estamos
 *    parando de afirmar que elas não existem.
 *  - Só reescreve quando a pessoa TEM skills declaradas E a frase é da família
 *    que nega existência (ver `negaTerSkills`). Quem não declarou nada continua
 *    lendo a verdade.
 *  - `matched=true` nunca é tocado: reescrever um acerto só poderia piorar.
 *  - Dimensão AUSENTE é inserida com weight 0 (invariante: o eixo sempre
 *    existe). Sem isso o cliente simplesmente não desenha a linha — que é
 *    exatamente como o eixo "sumiu" no achado A3.
 *  - Cenário C não é tocado (ver `isScenarioC`).
 *
 * Devolve a MESMA referência quando nada muda: o caminho de cache do
 * `index.ts` re-deriva o score sempre que o array troca, então preservar a
 * referência é o que garante "correção sem efeito colateral".
 */
export function reconcileSkillsReason(
  reasons: MatchReason[],
  declaredSkills: string[],
): MatchReason[] {
  if (!Array.isArray(reasons) || reasons.length === 0) return reasons
  if (isScenarioC(reasons)) return reasons

  const skills = (declaredSkills ?? [])
    .map((s) => String(s ?? '').trim())
    .filter((s) => s.length > 0)

  let touched = false
  let sawSkills = false
  const out: MatchReason[] = []

  for (const r of reasons) {
    if (!isSkillsLabel(r.label)) {
      out.push(r)
      continue
    }
    sawSkills = true
    if (r.matched || skills.length === 0 || !negaTerSkills(r.detail ?? '')) {
      out.push(r)
      continue
    }
    touched = true
    out.push({ ...r, detail: detalheSkillsDeclaradas(skills) })
  }

  if (!sawSkills) {
    touched = true
    out.push({
      label: 'Skills',
      matched: false,
      weight: 0,
      detail: skills.length > 0
        ? detalheSkillsDeclaradas(skills)
        : 'Adicione suas habilidades pra eu comparar com o que a vaga pede.',
    })
  }

  if (!touched) return reasons

  console.log(
    `[analyze-match] skills reason reconciled declared=${skills.length} ` +
      `inserted=${!sawSkills} before=${reasons.length} after=${out.length}`,
  )
  return out
}
