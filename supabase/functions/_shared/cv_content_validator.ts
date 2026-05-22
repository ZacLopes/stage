// Detecta uploads que claramente NÃO são currículos (extratos bancários,
// documentos de identidade gov.br, holerites). Conservador: prefere deixar
// passar do que rejeitar CV legítimo. Cada categoria exige uma combinação
// de sinais específicos — palavra solta não dispara.
//
// Casos reais observados em produção que motivaram esse validador:
//   - Extrato Nubank de 14k chars com dados financeiros + dados de terceiros
//   - Documento gov.br com CPF, nome da mãe, endereço
//
// Falsos positivos a evitar: CVs que mencionam bancos como experiência
// profissional ou cursos ("Excel Básico - Santander", "Trabalhou no Bradesco").
// Por isso a heurística NUNCA dispara só por nome de banco.

export type NonCvCategory = 'bank_statement' | 'gov_id_document' | 'payroll'

export interface NonCvDetection {
  isNonCv: boolean
  category: NonCvCategory | null
  reasons: string[]
}

export function detectNonCvContent(rawText: string): NonCvDetection {
  if (!rawText || rawText.length < 50) {
    return { isNonCv: false, category: null, reasons: [] }
  }

  const t = rawText.toLowerCase()

  // ── Extrato bancário ──────────────────────────────────────────────────
  // Exige pelo menos 2 sinais específicos de movimentação financeira.
  const bankSignals: string[] = []
  if (t.includes('saldo final')) bankSignals.push('saldo final')
  if (t.includes('saldo inicial')) bankSignals.push('saldo inicial')
  if (t.includes('total de entradas') || t.includes('total de saídas') || t.includes('total de saidas')) {
    bankSignals.push('total entradas/saídas')
  }
  if (t.includes('transferência recebida') || t.includes('transferencia recebida')) {
    bankSignals.push('transferência recebida')
  }
  if (t.includes('transferência enviada') || t.includes('transferencia enviada')) {
    bankSignals.push('transferência enviada')
  }
  if (t.includes('movimentações') || t.includes('movimentacoes')) bankSignals.push('movimentações')
  // "pix" + "agência" + "conta" juntos = quase certeza de extrato
  if (t.includes('pix') && t.includes('agência') && t.includes('conta')) {
    bankSignals.push('pix+agência+conta')
  }
  if (bankSignals.length >= 2) {
    return {
      isNonCv: true,
      category: 'bank_statement',
      reasons: bankSignals,
    }
  }

  // ── Documento gov.br / identidade ─────────────────────────────────────
  // "gov.br" sozinho é fraco (pode ser link). Exige combinação com campo
  // típico de doc identidade.
  const govSignals: string[] = []
  if (t.includes('gov.br')) govSignals.push('gov.br')
  if (t.includes('dados de pessoa física') || t.includes('dados de pessoa fisica')) {
    govSignals.push('dados de pessoa física')
  }
  if (t.includes('nome da mãe') || t.includes('nome da mae')) govSignals.push('nome da mãe')
  if (t.includes('título de eleitor') || t.includes('titulo de eleitor')) {
    govSignals.push('título de eleitor')
  }
  if (t.includes('situação cadastral') || t.includes('situacao cadastral')) {
    govSignals.push('situação cadastral')
  }
  if (t.includes('assinado digitalmente por gov.br') || t.includes('validar.iti.gov.br')) {
    govSignals.push('assinatura digital gov.br')
  }
  if (govSignals.length >= 2) {
    return {
      isNonCv: true,
      category: 'gov_id_document',
      reasons: govSignals,
    }
  }

  // ── Holerite / contracheque ───────────────────────────────────────────
  // Exige ≥2 sinais (igual extrato bancário e gov.br) pra não bloquear
  // CV de RH/DP que mencione "holerite" ou "contracheque" como parte da
  // descrição de experiência profissional.
  const payrollSignals: string[] = []
  if (t.includes('holerite')) payrollSignals.push('holerite')
  if (t.includes('contracheque') || t.includes('contra-cheque')) payrollSignals.push('contracheque')
  if (t.includes('recibo de pagamento de salário') || t.includes('recibo de pagamento de salario')) {
    payrollSignals.push('recibo de pagamento de salário')
  }
  // FGTS + INSS + proventos = padrão de holerite
  if (t.includes('fgts') && t.includes('inss') && (t.includes('proventos') || t.includes('descontos'))) {
    payrollSignals.push('fgts+inss+proventos/descontos')
  }
  // Valor líquido + competência = padrão de holerite
  if ((t.includes('valor líquido') || t.includes('valor liquido')) && t.includes('competência')) {
    payrollSignals.push('valor líquido+competência')
  }
  if (payrollSignals.length >= 2) {
    return {
      isNonCv: true,
      category: 'payroll',
      reasons: payrollSignals,
    }
  }

  return { isNonCv: false, category: null, reasons: [] }
}

export function nonCvMessage(category: NonCvCategory): string {
  switch (category) {
    case 'bank_statement':
      return 'Isso parece um extrato bancário, não um currículo. Envie o seu CV.'
    case 'gov_id_document':
      return 'Isso parece um documento de identidade, não um currículo. Envie o seu CV.'
    case 'payroll':
      return 'Isso parece um holerite, não um currículo. Envie o seu CV.'
  }
}
