/// Candidatura (Fase 1 — espinha de dados). Espelha `public.applications`:
/// a fonte de verdade de "apliquei" deixou de ser `swipe_actions.applied`
/// (DEPRECATED) e passou a ser esta entidade, com máquina de estados
/// validada no banco (trigger + matriz por actor).
library;

enum ApplicationStatus {
  submitted,
  inReview,
  shortlisted,
  interview,
  offer,
  hired,
  rejected,
  withdrawn,
  expired;

  static ApplicationStatus fromDb(String raw) => switch (raw) {
        'submitted' => submitted,
        'in_review' => inReview,
        'shortlisted' => shortlisted,
        'interview' => interview,
        'offer' => offer,
        'hired' => hired,
        'rejected' => rejected,
        'withdrawn' => withdrawn,
        'expired' => expired,
        _ => submitted, // status desconhecido (versão futura) degrada pra base
      };

  String get db => switch (this) {
        submitted => 'submitted',
        inReview => 'in_review',
        shortlisted => 'shortlisted',
        interview => 'interview',
        offer => 'offer',
        hired => 'hired',
        rejected => 'rejected',
        withdrawn => 'withdrawn',
        expired => 'expired',
      };

  bool get isTerminal => this == hired || this == expired;

  /// Status oferecidos ao CRIAR uma candidatura manual.
  ///
  /// Mora no modelo, não numa lista literal na tela: o menu do card já é
  /// DERIVADO de [canTransition], e uma lista solta lá fora não acompanharia
  /// um status novo no enum. Revisão UX 28/07, achado P2-20.
  ///
  /// `withdrawn` ENTRA (correção de 30/07). O argumento anterior — "desistir é
  /// evento posterior" — vale para candidatura viva, não para registro
  /// histórico, e adição manual existe justamente para registrar o que já
  /// aconteceu fora do app. Quem quer lançar uma candidatura antiga que ELA
  /// retirou tinha de criar como "Enviada" e editar depois: exatamente o
  /// vaivém que o achado descreve. É seguro porque o banco permite
  /// `withdrawn → submitted` (verificado em `_application_transition_allowed`).
  ///
  /// `expired` fica de fora: é evento do prazo, não escolha de quem registra.
  static List<ApplicationStatus> get initialOptions => const [
        submitted,
        inReview,
        shortlisted,
        interview,
        offer,
        hired,
        rejected,
        withdrawn,
      ];

  /// Rótulo pt-BR pra UI (aba Candidaturas, chip de status).
  ///
  /// Todos concordam com **a candidatura** (feminino), que é o que a aba
  /// acompanha. Antes a lista misturava os dois sujeitos: "Pré-selecionado" e
  /// "Contratado" concordavam com o CANDIDATO, no meio de "Enviada",
  /// "Recusada" e "Retirada". Além de inconsistente, exibia o masculino pra
  /// quem informou gênero feminino. Revisão UX 28/07, achado P2-21.
  ///
  /// `hired` vira "Aprovada" porque "candidatura contratada" não existe em
  /// português — e o estado anterior já é "Proposta", então "Aprovada" lê como
  /// o desfecho positivo final sem ambiguidade.
  String get label => switch (this) {
        submitted => 'Enviada',
        inReview => 'Em análise',
        shortlisted => 'Pré-selecionada',
        interview => 'Entrevista',
        offer => 'Proposta',
        hired => 'Aprovada',
        rejected => 'Recusada',
        withdrawn => 'Retirada',
        expired => 'Expirada',
      };

  /// "Conta como aplicada" pra UI (bucket "Já apliquei" e contadores):
  /// qualquer estado vivo do pipeline. withdrawn/expired não contam;
  /// rejected conta (o user aplicou — o desfecho foi negativo).
  bool get countsAsApplied => this != withdrawn && this != expired;
}

/// Segmentos da aba Candidaturas (Fase 3 T3.1). Decisão do fundador: 4
/// segmentos (Entrevistas só na F4). "Salvas" não é um status — é liked SEM
/// application; os outros 3 derivam do status via [segmentForStatus].
enum ApplicationSegment {
  salvas,
  enviadas,
  emProcesso,
  finalizadas;

  String get label => switch (this) {
        salvas => 'Salvas',
        enviadas => 'Enviadas',
        emProcesso => 'Em processo',
        finalizadas => 'Finalizadas',
      };
}

/// Mapa status→segmento (PLANO-FASE-3 §2/D1, decisão do arquiteto):
/// Enviadas = submitted · Em processo = in_review|shortlisted|interview|offer ·
/// Finalizadas = hired|rejected|withdrawn|expired.
ApplicationSegment segmentForStatus(ApplicationStatus s) => switch (s) {
      ApplicationStatus.submitted => ApplicationSegment.enviadas,
      ApplicationStatus.inReview ||
      ApplicationStatus.shortlisted ||
      ApplicationStatus.interview ||
      ApplicationStatus.offer =>
        ApplicationSegment.emProcesso,
      ApplicationStatus.hired ||
      ApplicationStatus.rejected ||
      ApplicationStatus.withdrawn ||
      ApplicationStatus.expired =>
        ApplicationSegment.finalizadas,
    };

enum ApplicationType {
  stage,
  externalConfirmed,
  manual;

  static ApplicationType fromDb(String raw) => switch (raw) {
        'stage' => stage,
        'manual' => manual,
        _ => externalConfirmed,
      };

  String get db => switch (this) {
        stage => 'stage',
        externalConfirmed => 'external_confirmed',
        manual => 'manual',
      };

  /// Rótulo em pt-BR para exibir ao usuário.
  ///
  /// O card de candidatura manual mostrava o literal `'manual'` — minúsculo,
  /// em jargão de banco, na cara de quem usa (C5 do device-test). O valor
  /// técnico continua em [db]; o que a pessoa lê vem daqui.
  String get label => switch (this) {
        stage => 'Pelo Stage',
        externalConfirmed => 'Confirmada por você',
        manual => 'Adicionada por você',
      };

  /// O usuário move o próprio pipeline só em manual/external_confirmed; `stage`
  /// é read-only pra ele (quem move é a empresa/ops na F4). Espelha a matriz
  /// da F1 — a UI só não oferece os controles.
  bool get userEditableStatus => this != stage;
}

class Application {
  final String id;
  final String userId;
  final String? jobId;
  final ApplicationType type;
  final ApplicationStatus status;
  final String? applicationMethod;
  final String? adaptedResumeId;
  final DateTime? slaDeadline;
  final String? rejectionCategory;
  final String? notes;
  final String? externalCompany;
  final String? externalTitle;
  final String? externalUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Application({
    required this.id,
    required this.userId,
    required this.jobId,
    required this.type,
    required this.status,
    this.applicationMethod,
    this.adaptedResumeId,
    this.slaDeadline,
    this.rejectionCategory,
    this.notes,
    this.externalCompany,
    this.externalTitle,
    this.externalUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Application.fromJson(Map<String, dynamic> json) => Application(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        jobId: json['job_id'] as String?,
        type: ApplicationType.fromDb((json['type'] as String?) ?? ''),
        status: ApplicationStatus.fromDb((json['status'] as String?) ?? ''),
        applicationMethod: json['application_method'] as String?,
        adaptedResumeId: json['adapted_resume_id'] as String?,
        slaDeadline: json['sla_deadline'] != null
            ? DateTime.tryParse(json['sla_deadline'] as String)
            : null,
        rejectionCategory: json['rejection_category'] as String?,
        notes: json['notes'] as String?,
        externalCompany: json['external_company'] as String?,
        externalTitle: json['external_title'] as String?,
        externalUrl: json['external_url'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Application copyWith({ApplicationStatus? status}) => Application(
        id: id,
        userId: userId,
        jobId: jobId,
        type: type,
        status: status ?? this.status,
        applicationMethod: applicationMethod,
        adaptedResumeId: adaptedResumeId,
        slaDeadline: slaDeadline,
        rejectionCategory: rejectionCategory,
        notes: notes,
        externalCompany: externalCompany,
        externalTitle: externalTitle,
        externalUrl: externalUrl,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

/// Espelho client da matriz de transições do banco (actor `user`). A
/// validação REAL é o trigger `_applications_validate_update` — este helper
/// existe pra UI desabilitar ações inválidas sem round-trip e pros testes.
bool canTransition(ApplicationType type, ApplicationStatus from, ApplicationStatus to) {
  if (from == to) return true;
  const pipeline = {
    ApplicationStatus.inReview,
    ApplicationStatus.shortlisted,
    ApplicationStatus.interview,
    ApplicationStatus.offer,
    ApplicationStatus.hired,
  };
  if (type == ApplicationType.stage) {
    // user em stage: só desistir.
    return !from.isTerminal &&
        from != ApplicationStatus.rejected &&
        from != ApplicationStatus.withdrawn &&
        to == ApplicationStatus.withdrawn;
  }
  // Reabertura (manual/external).
  if ((from == ApplicationStatus.rejected || from == ApplicationStatus.withdrawn) &&
      to == ApplicationStatus.submitted) {
    return true;
  }
  // Pipeline livre, INCLUSIVE retrocesso (por design — corrigir o próprio
  // tracker), a partir de qualquer não-terminal.
  if (from.isTerminal ||
      from == ApplicationStatus.rejected ||
      from == ApplicationStatus.withdrawn) {
    return false;
  }
  return pipeline.contains(to) ||
      to == ApplicationStatus.rejected ||
      to == ApplicationStatus.withdrawn;
}
