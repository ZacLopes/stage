// Detecta uploads que claramente NÃO são currículos (extratos bancários,
// docs gov.br, holerites). Espelho da heurística no servidor
// (`supabase/functions/_shared/cv_content_validator.ts`) — manter os dois
// em paralelo: cliente avisa antes do upload pra UX boa, servidor rejeita
// como segunda camada.
//
// Conservador por design: nunca dispara em CV legítimo que apenas mencione
// um banco como experiência ou curso.

enum NonCvCategory { bankStatement, govIdDocument, payroll }

class NonCvDetection {
  final bool isNonCv;
  final NonCvCategory? category;
  final List<String> reasons;

  const NonCvDetection({
    required this.isNonCv,
    this.category,
    this.reasons = const [],
  });

  static const ok = NonCvDetection(isNonCv: false);
}

class CvContentValidator {
  static NonCvDetection detect(String rawText) {
    if (rawText.length < 50) return NonCvDetection.ok;
    final t = rawText.toLowerCase();

    // Extrato bancário: precisa de >=2 sinais específicos de movimentação.
    final bankSignals = <String>[];
    if (t.contains('saldo final')) bankSignals.add('saldo final');
    if (t.contains('saldo inicial')) bankSignals.add('saldo inicial');
    if (t.contains('total de entradas') ||
        t.contains('total de saídas') ||
        t.contains('total de saidas')) {
      bankSignals.add('total entradas/saídas');
    }
    if (t.contains('transferência recebida') ||
        t.contains('transferencia recebida')) {
      bankSignals.add('transferência recebida');
    }
    if (t.contains('transferência enviada') ||
        t.contains('transferencia enviada')) {
      bankSignals.add('transferência enviada');
    }
    if (t.contains('movimentações') || t.contains('movimentacoes')) {
      bankSignals.add('movimentações');
    }
    if (t.contains('pix') && t.contains('agência') && t.contains('conta')) {
      bankSignals.add('pix+agência+conta');
    }
    if (bankSignals.length >= 2) {
      return NonCvDetection(
        isNonCv: true,
        category: NonCvCategory.bankStatement,
        reasons: bankSignals,
      );
    }

    // Documento gov.br / identidade.
    final govSignals = <String>[];
    if (t.contains('gov.br')) govSignals.add('gov.br');
    if (t.contains('dados de pessoa física') ||
        t.contains('dados de pessoa fisica')) {
      govSignals.add('dados de pessoa física');
    }
    if (t.contains('nome da mãe') || t.contains('nome da mae')) {
      govSignals.add('nome da mãe');
    }
    if (t.contains('título de eleitor') || t.contains('titulo de eleitor')) {
      govSignals.add('título de eleitor');
    }
    if (t.contains('situação cadastral') ||
        t.contains('situacao cadastral')) {
      govSignals.add('situação cadastral');
    }
    if (t.contains('assinado digitalmente por gov.br') ||
        t.contains('validar.iti.gov.br')) {
      govSignals.add('assinatura digital gov.br');
    }
    if (govSignals.length >= 2) {
      return NonCvDetection(
        isNonCv: true,
        category: NonCvCategory.govIdDocument,
        reasons: govSignals,
      );
    }

    // Holerite / contracheque. Exige ≥2 sinais pra não bloquear CV de
    // RH/DP que mencione "holerite" ou "contracheque" como experiência.
    final payrollSignals = <String>[];
    if (t.contains('holerite')) payrollSignals.add('holerite');
    if (t.contains('contracheque') || t.contains('contra-cheque')) {
      payrollSignals.add('contracheque');
    }
    if (t.contains('recibo de pagamento de salário') ||
        t.contains('recibo de pagamento de salario')) {
      payrollSignals.add('recibo de pagamento de salário');
    }
    if (t.contains('fgts') &&
        t.contains('inss') &&
        (t.contains('proventos') || t.contains('descontos'))) {
      payrollSignals.add('fgts+inss+proventos/descontos');
    }
    if ((t.contains('valor líquido') || t.contains('valor liquido')) &&
        t.contains('competência')) {
      payrollSignals.add('valor líquido+competência');
    }
    if (payrollSignals.length >= 2) {
      return NonCvDetection(
        isNonCv: true,
        category: NonCvCategory.payroll,
        reasons: payrollSignals,
      );
    }

    return NonCvDetection.ok;
  }

  static String messageFor(NonCvCategory category) {
    switch (category) {
      case NonCvCategory.bankStatement:
        return 'Isso parece um extrato bancário, não um currículo. Envie o seu CV.';
      case NonCvCategory.govIdDocument:
        return 'Isso parece um documento de identidade, não um currículo. Envie o seu CV.';
      case NonCvCategory.payroll:
        return 'Isso parece um holerite, não um currículo. Envie o seu CV.';
    }
  }
}
