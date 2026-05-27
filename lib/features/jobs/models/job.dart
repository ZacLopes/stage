import 'company.dart';

class Job {
  final String id;
  final String title;
  final String companyName;
  final String companyLogoUrl;
  final String location;
  final String salaryRange;
  final String workModel;
  final String jobType;
  final int matchScore;
  final String description;
  /// HTML cru do description, preservado pra renderização rica em
  /// job_details_sheet. Texto plano (description) continua sendo usado em
  /// JobCard preview, match_score e analytics — manter os dois evita
  /// regressões.
  final String descriptionHtml;
  final List<String> requirements;
  final List<String> benefits;
  final String aboutCompany;
  /// HTML cru do aboutCompany (mesma motivação de [descriptionHtml]).
  final String aboutCompanyHtml;
  final String postedDaysAgo;
  final String? deadline;
  /// Data crua da deadline pra comparação (filtros, agrupamento por prazo
  /// expirado). `deadline` mantém o display formatado em PT-BR.
  final DateTime? deadlineAt;

  // Raw DB fields (kept for filtering logic)
  final String? companyId;
  final String? locationCity;
  final String? locationState;
  final int? salaryMin;
  final int? salaryMax;
  final String? workModelRaw; // 'presencial', 'hibrido', 'remoto'
  final String? jobTypeRaw;   // 'estagio', 'trainee', 'clt_junior', 'temporario'
  final String? area;
  final String? externalUrl; // URL do site da empresa pra aplicar (Greenhouse/Lever/Apify)
  final Company? company;

  Job({
    required this.id,
    required this.title,
    required this.companyName,
    required this.companyLogoUrl,
    required this.location,
    required this.salaryRange,
    required this.workModel,
    required this.jobType,
    required this.matchScore,
    required this.description,
    this.descriptionHtml = '',
    required this.requirements,
    required this.benefits,
    required this.aboutCompany,
    this.aboutCompanyHtml = '',
    required this.postedDaysAgo,
    this.deadline,
    this.deadlineAt,
    this.companyId,
    this.locationCity,
    this.locationState,
    this.salaryMin,
    this.salaryMax,
    this.workModelRaw,
    this.jobTypeRaw,
    this.area,
    this.externalUrl,
    this.company,
  });

  /// Creates a Job from Supabase JSON (with nested company via join).
  /// Expected shape: { ...job_columns, companies: { ...company_columns } }
  factory Job.fromJson(Map<String, dynamic> json) {
    // Parse the nested company object
    Company? company;
    if (json['companies'] != null && json['companies'] is Map) {
      company = Company.fromJson(Map<String, dynamic>.from(json['companies']));
    }

    final String companyName = company?.name ?? json['company_name'] ?? '';
    final String companyLogoUrl = company?.logoUrl ?? '';
    final String aboutCompany = company?.description ?? '';
    final String aboutCompanyHtmlRaw = company?.descriptionHtml ?? '';

    // Build location string
    final city = json['location_city'] as String?;
    final state = json['location_state'] as String?;
    final workModelRaw = json['work_model'] as String;
    String location;
    if (workModelRaw == 'remoto') {
      location = 'Remoto';
    } else if (city != null && state != null) {
      location = '$city, $state';
    } else {
      location = city ?? state ?? 'Não informado';
    }

    // Build salary range string (convert centavos to reais)
    final salaryMin = json['salary_min'] as int?;
    final salaryMax = json['salary_max'] as int?;
    String salaryRange;
    if (salaryMin != null && salaryMax != null && salaryMin != salaryMax) {
      salaryRange = 'R\$ ${(salaryMin / 100).toStringAsFixed(0)} - R\$ ${(salaryMax / 100).toStringAsFixed(0)}';
    } else if (salaryMin != null) {
      salaryRange = 'R\$ ${(salaryMin / 100).toStringAsFixed(0)}';
    } else {
      salaryRange = 'A combinar';
    }

    // Map raw work model to display string
    final workModelDisplay = _workModelDisplay(workModelRaw);

    // Map raw job type to display string
    final jobTypeRaw = json['job_type'] as String;
    final jobTypeDisplay = _jobTypeDisplay(jobTypeRaw);

    // Compute posted time ago
    final publishedAt = json['published_at'] != null
        ? DateTime.tryParse(json['published_at'] as String)
        : null;
    final postedDaysAgo = _computePostedAgo(publishedAt);

    // Compute deadline display
    final deadlineRaw = json['deadline'] != null
        ? DateTime.tryParse(json['deadline'] as String)
        : null;
    String? deadlineDisplay;
    if (deadlineRaw != null) {
      final months = [
        'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
        'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'
      ];
      deadlineDisplay = 'Inscrições até ${deadlineRaw.day} de ${months[deadlineRaw.month - 1]}';
    }

    // Match score começa zerado — é calculado na UI via MatchScoreCalculator
    // usando as preferências do usuário e dados do gamificationData.
    const matchScore = 0;

    // Parse requirements and benefits arrays (strip HTML defensively)
    final requirements =
        _parseStringList(json['requirements']).map(_stripHtml).where((s) => s.isNotEmpty).toList();
    final benefits =
        _parseStringList(json['benefits']).map(_stripHtml).where((s) => s.isNotEmpty).toList();

    // description: texto plano (já vem stripped do backend) — usado em
    //   JobCard preview, match_score e analytics.
    // description_html: HTML cru preservado pelo sync (campo novo, NULL em
    //   vagas antigas) — usado pelo flutter_html no detalhe da vaga.
    // Quando description_html for null/vazio, o widget cai no fallback de
    // texto plano automaticamente.
    final description = json['description'] as String? ?? '';
    final descriptionHtmlRaw = json['description_html'] as String? ?? '';

    return Job(
      id: json['id'] as String,
      title: json['title'] as String,
      companyName: companyName,
      companyLogoUrl: companyLogoUrl,
      location: location,
      salaryRange: salaryRange,
      workModel: workModelDisplay,
      jobType: jobTypeDisplay,
      matchScore: matchScore,
      description: description,
      descriptionHtml: descriptionHtmlRaw,
      requirements: requirements,
      benefits: benefits,
      aboutCompany: aboutCompany,
      aboutCompanyHtml: aboutCompanyHtmlRaw,
      postedDaysAgo: postedDaysAgo,
      deadline: deadlineDisplay,
      deadlineAt: deadlineRaw,
      companyId: json['company_id'] as String?,
      locationCity: city,
      locationState: state,
      salaryMin: salaryMin,
      salaryMax: salaryMax,
      workModelRaw: workModelRaw,
      jobTypeRaw: jobTypeRaw,
      area: json['area'] as String?,
      externalUrl: json['external_url'] as String?,
      company: company,
    );
  }

  static String _workModelDisplay(String raw) {
    switch (raw) {
      case 'remoto': return 'Remoto';
      case 'hibrido': return 'Híbrido';
      case 'presencial': return 'Presencial';
      default: return raw;
    }
  }

  static String _jobTypeDisplay(String raw) {
    switch (raw) {
      case 'estagio': return 'Estágio';
      case 'trainee': return 'Trainee';
      case 'clt_junior': return 'CLT Júnior';
      case 'temporario': return 'Temporário';
      default: return raw;
    }
  }

  static String _computePostedAgo(DateTime? publishedAt) {
    if (publishedAt == null) return 'Publicada recentemente';
    final diff = DateTime.now().difference(publishedAt);
    if (diff.inDays == 0) return 'Publicada hoje';
    if (diff.inDays == 1) return 'Publicada há 1 dia';
    if (diff.inDays < 7) return 'Publicada há ${diff.inDays} dias';
    if (diff.inDays < 14) return 'Publicada há 1 semana';
    return 'Publicada há ${(diff.inDays / 7).floor()} semanas';
  }

  static List<String> _parseStringList(dynamic value) {
    if (value == null) return [];
    if (value is List) return value.cast<String>();
    return [];
  }

  /// Remove tags HTML, decodifica entidades comuns e normaliza whitespace.
  /// Quebras virais entre parágrafos viram \n\n, <br> vira \n, demais tags somem.
  static String _stripHtml(String input) {
    if (input.isEmpty) return input;
    // Otimização: se não tem nenhuma tag nem entidade, retorna direto.
    // Cuidado: alguns ATSs (XP Inc. via Gupy/Apify) mandam o description sem
    // tags `<>` mas com `&nbsp;` literais no meio do texto — checar só `<`
    // deixava esses casos com entidades cruas na UI.
    if (!input.contains('<') && !input.contains('&')) return input;

    var s = input
        // Quebras de linha semânticas
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'</div\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</li\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '• ')
        // Remove qualquer outra tag
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        // Decodifica entidades comuns
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&ndash;', '–')
        .replaceAll('&mdash;', '—')
        .replaceAll('&hellip;', '…');

    // Normaliza whitespace: múltiplos espaços/tabs viram 1 espaço,
    // múltiplas linhas em branco viram exatamente 2.
    s = s
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n[ \t]+'), '\n')
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    return s;
  }
}
