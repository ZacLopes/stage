import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_repository.dart';
import '../../services/ai_service.dart';
import '../../data/models/models.dart';
import '../../data/local_storage_repository.dart';
import 'pdf_service.dart';

class ToolWithLevel {
  final String name;
  final String level;
  const ToolWithLevel(this.name, this.level);
}

class ResumeData {
  final String fullName;
  final String email;
  final String phone;
  final String linkedin;
  final String location;
  final String address; // optional full street address (Rua + número + bairro)
  final String summary;
  final List<String> skills;
  final List<ToolWithLevel> tools;
  final List<ExperienceItem> experiences;
  final List<EducationItem> education;
  final List<String> achievements;
  final List<String> interests;
  final List<ResumeProject> academicProjects;
  final List<ResumeLeadership> leadership;
  final List<ResumeCourse> courses;
  final List<ResumeLanguage> languages;
  final List<ResumeAward> awards;

  ResumeData({
    this.fullName = '',
    this.email = '',
    this.phone = '',
    this.linkedin = '',
    this.location = '',
    this.address = '',
    this.summary = '',
    this.skills = const [],
    this.tools = const [],
    this.experiences = const [],
    this.education = const [],
    this.achievements = const [],
    this.interests = const [],
    this.academicProjects = const [],
    this.leadership = const [],
    this.courses = const [],
    this.languages = const [],
    this.awards = const [],
  });

  ResumeData copyWith({
    String? fullName,
    String? email,
    String? phone,
    String? linkedin,
    String? location,
    String? address,
    String? summary,
    List<String>? skills,
    List<ToolWithLevel>? tools,
    List<ExperienceItem>? experiences,
    List<EducationItem>? education,
    List<String>? achievements,
    List<String>? interests,
    List<ResumeProject>? academicProjects,
    List<ResumeLeadership>? leadership,
    List<ResumeCourse>? courses,
    List<ResumeLanguage>? languages,
    List<ResumeAward>? awards,
  }) {
    return ResumeData(
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      linkedin: linkedin ?? this.linkedin,
      location: location ?? this.location,
      address: address ?? this.address,
      summary: summary ?? this.summary,
      skills: skills ?? this.skills,
      tools: tools ?? this.tools,
      experiences: experiences ?? this.experiences,
      education: education ?? this.education,
      achievements: achievements ?? this.achievements,
      interests: interests ?? this.interests,
      academicProjects: academicProjects ?? this.academicProjects,
      leadership: leadership ?? this.leadership,
      courses: courses ?? this.courses,
      languages: languages ?? this.languages,
      awards: awards ?? this.awards,
    );
  }
}

class ExperienceItem {
  final String role;
  final String company;
  final String period;
  final String description;
  final String location;

  ExperienceItem({
    required this.role,
    required this.company,
    required this.period,
    required this.description,
    this.location = '',
  });
}

class EducationItem {
  final String degree;
  final String institution;
  final String period;
  final String details;
  final String location;
  // Harvard-style enrichments — all optional
  final String gpa;          // ex: "8.9/10"
  final String honors;       // ex: "1º colocado em 2 semestres"
  final String repRole;      // ex: "Representante de turma"
  final String coursework;   // ex: "Finanças Corporativas, Valuation, ..."

  EducationItem({
    required this.degree,
    required this.institution,
    required this.period,
    this.details = '',
    this.location = '',
    this.gpa = '',
    this.honors = '',
    this.repRole = '',
    this.coursework = '',
  });
}

class ResumeViewModel extends ChangeNotifier {
  final SupabaseRepository _repository;
  final AIService _aiService;
  final LocalStorageRepository _localStorage;

  ResumeData? _resumeData;
  ResumeContent? _resumeContent;
  bool _isLoading = false;
  bool _isGeneratingResume = false;
  bool _isSaving = false;
  String? _error;

  ResumeViewModel(this._repository, this._aiService, this._localStorage) {
    _init();
  }

  void _init() {
    // Listen to auth changes
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      if (event == AuthChangeEvent.signedIn) {
        loadResumeData();
      } else if (event == AuthChangeEvent.signedOut) {
        _clearData();
      }
    });
    
    // Initial load
    loadResumeData();
  }

  String _selectedTemplateId = 'harvard_ats';
  String get selectedTemplateId => _selectedTemplateId;

  void setSelectedTemplateId(String id) {
    if (_selectedTemplateId != id) {
      _selectedTemplateId = id;
      notifyListeners();
    }
  }

  void _clearData() {
    _resumeData = null;
    _resumeContent = null;
    _error = null;
    _isLoading = false;
    _isCourseCompleted = false;
    notifyListeners();
  }

  String _selectedTemplateType = 'standard'; // 'standard' or 'area'
  String _detectedArea = 'Geral'; // Default

  ResumeData? get resumeData => _resumeData;
  ResumeContent? get resumeContent => _resumeContent;
  bool get isLoading => _isLoading;
  bool get isGeneratingResume => _isGeneratingResume;
  bool get isSaving => _isSaving;
  String get selectedTemplateType => _selectedTemplateType;
  String get detectedArea => _detectedArea;

  bool get isResumeEmpty => _resumeContent == null || 
      (_resumeContent!.summary.isEmpty && 
       _resumeContent!.experiences.isEmpty && 
       _resumeContent!.education.isEmpty);

  void setTemplateType(String type) {
    if (_selectedTemplateType != type) {
      _selectedTemplateType = type;
      notifyListeners();
    }
  }

  List<String> getResumeWarnings() {
    final warnings = <String>[];
    if (_resumeData == null) return warnings;

    // 1. Essential fields
    if (_resumeData!.fullName.isEmpty) warnings.add('Nome completo está faltando.');
    if (_resumeData!.email.isEmpty) warnings.add('E-mail está faltando.');
    if (_resumeData!.phone.isEmpty) warnings.add('Telefone está faltando.');
    if (_resumeData!.experiences.isEmpty) warnings.add('Adicione pelo menos uma experiência profissional.');
    if (_resumeData!.education.isEmpty) warnings.add('Adicione sua formação acadêmica.');

    // 2. Long bullets
    for (var exp in _resumeData!.experiences) {
      final lines = exp.description.split('\n');
      for (var line in lines) {
        if (line.length > 200) {
          warnings.add('Um dos pontos da experiência na ${exp.company} está muito longo. Tente ser mais conciso.');
          break;
        }
      }
    }

    // 3. Empty sections (already hidden, but good to alert)
    if (_resumeData!.summary.isEmpty) warnings.add('Seção "Resumo Profissional" está vazia.');

    // 4. Page count heuristic
    final totalItems = _resumeData!.experiences.length + 
                       _resumeData!.education.length + 
                       _resumeData!.academicProjects.length + 
                       _resumeData!.leadership.length;
    
    if (totalItems > 12) {
      warnings.add('Seu currículo tem muito conteúdo e pode passar de 2 páginas. Considere manter apenas o mais relevante.');
    }

    return warnings;
  }

  int _lastGeneratedPageCount = 1;
  int get lastGeneratedPageCount => _lastGeneratedPageCount;

  Future<void> updatePageCountHeuristic(UserProfile? user) async {
    if (_resumeData == null) return;
    try {
      final bytes = await PdfService.generateResumeBytes(user, _resumeData!, _selectedTemplateId);
      // We don't have an easy way to count pages from bytes without parsing, 
      // but we can modify PdfService to return page count.
    } catch (e) {
      print('Error updating page count: $e');
    }
  }

  void _detectUserArea(Map<String, String> answersMap) {
    _detectedArea = 'Geral';
    for (var entry in answersMap.entries) {
      final a = entry.value.toLowerCase();
      if (a.contains('marketing') || a.contains('criação')) {
        _detectedArea = 'Marketing & Criação';
        break;
      } else if (a.contains('vendas') || a.contains('comercial')) {
        _detectedArea = 'Vendas & Comercial';
        break;
      } else if (a.contains('financeiro') || a.contains('adm')) {
        _detectedArea = 'Financeiro & Adm';
        break;
      } else if (a.contains('tecnologia') || a.contains('dados') || a.contains('programar')) {
        _detectedArea = 'Tecnologia & Dados';
        break;
      } else if (a.contains('pessoas') || a.contains('rh')) {
        _detectedArea = 'Pessoas & RH';
        break;
      } else if (a.contains('operações') || a.contains('logística')) {
        _detectedArea = 'Operações & Logística';
        break;
      } else if (a.contains('jurídico') || a.contains('compliance')) {
        _detectedArea = 'Jurídico & Compliance';
        break;
      }
    }
    notifyListeners();
  }

  Future<void> saveManualEdit(ResumeContent newContent) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    _resumeContent = newContent;
    await _localStorage.saveResumeContent(userId, newContent);
    _resumeData = await _convertToResumeData(newContent);
    await _updateHeaderInfo();
    notifyListeners();
  }

  bool _isCourseCompleted = false;
  bool get isCourseCompleted => _isCourseCompleted;

  Future<void> loadResumeData({bool forceRefresh = false}) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      _clearData();
      return;
    }

    // If we already have data and are NOT forcing a refresh, skip the 'loading' state
    // to avoid UI flicker/fetching indicator. We still update in the background.
    if (!forceRefresh && _resumeContent != null && _resumeData != null) {
       _performSilentLoad(userId);
       return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _internalLoad(userId);
    } catch (e) {
      _error = 'Erro ao carregar currículo: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _performSilentLoad(String userId) async {
    try {
      await _internalLoad(userId);
      notifyListeners();
    } catch (e) {
      print('Silent load error: $e');
    }
  }

  Future<void> _internalLoad(String userId) async {
      _isCourseCompleted = await _repository.isEntireCourseCompleted();

      if (!_isCourseCompleted) {
        _resumeData = null;
        _resumeContent = null;
        return;
      }

      // One-time cache invalidation: legacy caches stored AI output AFTER
      // overrides were applied, which makes our idempotent override path
      // produce duplicated/inconsistent state. Bumping this key forces a
      // single regeneration on next AI call.
      const cacheSchemaVersion = 'v2_overrides_pre_save';
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('_resume_cache_schema');
      if (stored != cacheSchemaVersion) {
        await _localStorage.clearAll(userId);
        await prefs.setString('_resume_cache_schema', cacheSchemaVersion);
      }

      _resumeContent = await _localStorage.getResumeContent(userId);
      
      try {
        final answers = await _repository.getUserAnswersWithQuestions();
        if (answers.isNotEmpty) {
           _detectUserArea(answers);
        }
      } catch (e) {
        print('Error detecting area on load: $e');
      }

      if (_resumeContent != null && !isResumeEmpty) {
        await _applyFrontendOverrides(userId);
        _resumeData = await _convertToResumeData(_resumeContent!);
        await _updateHeaderInfo();
      } else {
        // Only trigger AI if consent is already given, otherwise Tab will handle modal
        final userProfile = await _repository.getUserProfile();
        if (userProfile != null && userProfile.aiConsent) {
          await generateResumeWithAI();
        } else if (_resumeContent != null) {
          // Keep what we have but it's empty
          _resumeData = await _convertToResumeData(_resumeContent!);
          await _updateHeaderInfo();
        }
      }
  }

  Future<void> _updateHeaderInfo() async {
    if (_resumeData == null) return;
    
    final userProfile = await _repository.getUserProfile();
    final rawAnswers = await _repository.getUserAnswers();
    
    final Map<String, dynamic> answersMap = {};
    for (var item in rawAnswers) {
      answersMap[item['question_id']] = item['answer'];
    }

    String? getAnswer(String qId) {
      final val = answersMap[qId];
      if (val == null) return null;
      if (val is String) return val;
      if (val is List && val.isNotEmpty) return val.first.toString();
      return val.toString();
    }

    String linkedin = '';
    String email = userProfile?.email ?? '';
    String phone = '';
    String address = '';

    // M5_1_1_Q1 is now a merged contactForm JSON
    final contactRaw = getAnswer('M5_1_1_Q1');
    if (contactRaw != null) {
      final contact = _parseContactPayload(contactRaw);
      linkedin = (contact['linkedin'] ?? '').trim();
      final contactEmail = (contact['email'] ?? '').trim();
      if (contactEmail.isNotEmpty) email = contactEmail;
      final contactPhone = (contact['phone'] ?? '').trim();
      if (contactPhone.isNotEmpty) phone = contactPhone;
      address = (contact['address'] ?? '').trim();
    }

    if (linkedin.isEmpty && userProfile != null) {
      linkedin = 'linkedin.com/in/${userProfile.name.replaceAll(' ', '').toLowerCase()}';
    }

    String location = getAnswer('M5_2_1_Q1') ?? 'São Paulo, SP';

    if (userProfile != null) {
      _resumeData = _resumeData!.copyWith(
        fullName: userProfile.name,
        email: email,
        phone: phone,
        linkedin: linkedin,
        location: location,
        address: address,
      );
    }
  }

  Future<void> generateResumeWithAI() async {
    await rewriteResumeWithAI();
  }

  Future<void> rewriteResumeWithAI() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    _isGeneratingResume = true;
    _error = null;
    notifyListeners();

    try {
      if (!_isCourseCompleted) {
         _error = 'O currículo só será liberado após o término da jornada.';
         return;
      }

      final userProfile = await _repository.getUserProfile();
      if (userProfile == null || !userProfile.aiConsent) {
        _error = 'Consentimento de IA necessário.';
        return;
      }

      final answers = await _repository.getUserAnswersWithQuestions();
      
      if (answers.isEmpty) {
        _error = 'Responda algumas perguntas nas trilhas para gerar seu currículo.';
        return;
      }

      _detectUserArea(answers);

      _resumeContent = await _aiService.generateResumeContent(answers, areaContext: _selectedTemplateType == 'area' ? _detectedArea : null);

      // Cache the raw AI output BEFORE applying overrides; overrides are
      // re-applied on every load so caching post-override would compound
      // mutations across runs.
      await _localStorage.saveResumeContent(userId, _resumeContent!);
      await _applyFrontendOverrides(userId);

      _resumeData = await _convertToResumeData(_resumeContent!);
      await _updateHeaderInfo();
    } catch (e) {
      _error = 'Erro ao gerar currículo com IA: $e';
      if (_resumeData == null) _createPlaceholderResume();
    } finally {
      _isGeneratingResume = false;
      notifyListeners();
    }
  }

  Future<void> updateResumeWithAI() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    _isGeneratingResume = true;
    _error = null;
    notifyListeners();

    try {
      final userProfile = await _repository.getUserProfile();
      if (userProfile == null || !userProfile.aiConsent) {
        _error = 'Consentimento de IA necessário.';
        return;
      }

      final answers = await _repository.getUserAnswersWithQuestions();
      final newContent = await _aiService.generateResumeContent(answers);
      
      if (_resumeContent == null) {
        _resumeContent = newContent;
      } else {
        _resumeContent = ResumeContent(
          summary: _shouldUpdateString(_resumeContent!.summary, newContent.summary) ? newContent.summary : _resumeContent!.summary,
          skills: _shouldUpdateString(_resumeContent!.skills, newContent.skills) ? newContent.skills : _resumeContent!.skills,
          experiences: _shouldUpdateList(_resumeContent!.experiences, newContent.experiences) ? newContent.experiences : _resumeContent!.experiences,
          education: _shouldUpdateList(_resumeContent!.education, newContent.education) ? newContent.education : _resumeContent!.education,
          achievements: _shouldUpdateString(_resumeContent!.achievements, newContent.achievements) ? newContent.achievements : _resumeContent!.achievements,
          interests: _shouldUpdateString(_resumeContent!.interests, newContent.interests) ? newContent.interests : _resumeContent!.interests,
        );
      }
      
      await _localStorage.saveResumeContent(userId, _resumeContent!);
      _resumeData = await _convertToResumeData(_resumeContent!);
      await _updateHeaderInfo();
    } catch (e) {
      _error = 'Erro ao atualizar currículo: $e';
    } finally {
      _isGeneratingResume = false;
      notifyListeners();
    }
  }

  /// Read tools with level from M4_1_1_Q1 (toolsCatalog).
  /// Returns empty list if absent. Defensive against legacy concatenated arrays
  /// like `[{...}],[{...}]` produced by older save paths — picks the LAST
  /// valid array as the most recent state, deduplicating tool names.
  Future<List<ToolWithLevel>> _readToolsFromAnswers() async {
    try {
      final answers = await _repository.getUserAnswers();
      String? raw;
      for (final a in answers) {
        if (a['question_id'] == 'M4_1_1_Q1') {
          raw = a['answer'] as String?;
          break;
        }
      }
      if (raw == null || raw.trim().isEmpty) return [];

      List<dynamic>? decoded;
      try {
        final v = jsonDecode(raw);
        if (v is List) decoded = v;
      } catch (_) {}

      // Fallback: extract array fragments and merge them (newer wins on dedup)
      if (decoded == null) {
        final fragments = RegExp(r'\[(?:[^\[\]]|\[[^\[\]]*\])*\]')
            .allMatches(raw)
            .map((m) => m.group(0)!)
            .toList();
        final merged = <dynamic>[];
        for (final f in fragments) {
          try {
            final v = jsonDecode(f);
            if (v is List) merged.addAll(v);
          } catch (_) {}
        }
        if (merged.isEmpty) return [];
        decoded = merged;
      }

      final byName = <String, ToolWithLevel>{};
      for (final item in decoded) {
        if (item is! Map) continue;
        final name = (item['category'] ?? item['tool'] ?? '').toString().trim();
        final level = (item['level'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        // Last write wins (preserves most recent level)
        byName[name.toLowerCase()] = ToolWithLevel(name, level);
      }
      return byName.values.toList();
    } catch (e) {
      print('Error reading tools: $e');
      return [];
    }
  }

  /// Read M2_1_1_Q5 (academic highlights form) — returns map with optional
  /// gpa/honors/rep_role/coursework. All values are trimmed strings; missing
  /// fields come back as empty strings.
  Future<Map<String, String>> _readAcademicHighlights() async {
    try {
      final answers = await _repository.getUserAnswers();
      String? raw;
      for (final a in answers) {
        if (a['question_id'] == 'M2_1_1_Q5') {
          raw = a['answer'] as String?;
          break;
        }
      }
      if (raw == null || raw.trim().isEmpty) return const {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        'gpa': (decoded['gpa'] ?? '').toString().trim(),
        'honors': (decoded['honors'] ?? '').toString().trim(),
        'rep_role': (decoded['rep_role'] ?? '').toString().trim(),
        'coursework': (decoded['coursework'] ?? '').toString().trim(),
      };
    } catch (e) {
      return const {};
    }
  }

  /// Defensive parser for the contact form JSON. Handles three cases:
  /// (1) clean JSON — direct decode;
  /// (2) multiple JSONs concatenated (legacy bug from keystroke-spam) —
  ///     extracts the LAST valid object containing "phone";
  /// (3) malformed string — falls back to regex-extracting individual fields.
  Map<String, String> _parseContactPayload(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return {
          'linkedin': (decoded['linkedin'] ?? '').toString(),
          'email': (decoded['email'] ?? '').toString(),
          'phone': (decoded['phone'] ?? '').toString(),
          'address': (decoded['address'] ?? '').toString(),
        };
      }
    } catch (_) {}

    // Try to extract the last valid {...} object (most recent state)
    final objMatches = RegExp(r'\{[^{}]*\}').allMatches(raw).toList();
    for (final m in objMatches.reversed) {
      try {
        final decoded = jsonDecode(m.group(0)!);
        if (decoded is Map && decoded.containsKey('phone')) {
          return {
            'linkedin': (decoded['linkedin'] ?? '').toString(),
            'email': (decoded['email'] ?? '').toString(),
            'phone': (decoded['phone'] ?? '').toString(),
            'address': (decoded['address'] ?? '').toString(),
          };
        }
      } catch (_) {}
    }

    // Last resort: regex per field
    String pick(String key) {
      final matches = RegExp('"$key"\\s*:\\s*"([^"]*)"').allMatches(raw).toList();
      return matches.isNotEmpty ? matches.last.group(1) ?? '' : '';
    }
    final phone = pick('phone');
    final email = pick('email');
    final linkedin = pick('linkedin');
    final address = pick('address');
    if (phone.isEmpty && email.isEmpty && linkedin.isEmpty) {
      // Probably a legacy plain LinkedIn URL string
      return {'linkedin': raw.trim(), 'email': '', 'phone': '', 'address': ''};
    }
    return {'linkedin': linkedin, 'email': email, 'phone': phone, 'address': address};
  }

  // ============================================================
  // Frontend overrides — pull structured data from local sources
  // when available, falling back to AI-generated content otherwise.
  // ============================================================

  Future<void> _applyFrontendOverrides(String userId) async {
    if (_resumeContent == null) return;
    try {
      // Always start from the raw cached content (pre-override) so that
      // re-applying overrides is idempotent and never operates on already-
      // modified state from a previous invocation.
      final raw = await _localStorage.getResumeContent(userId);
      if (raw != null) _resumeContent = raw;

      final mapping = await _buildExperienceMappingFromD1();
      await _overrideSummaryFromSectionVersions(userId);

      // Fetch approved bullets once and consolidate experiences in a single pass
      final campaign = await _repository.getLatestCampaign(userId);
      final bulletsByPhase = <String, List<String>>{};
      if (campaign != null) {
        final bullets = await _repository.getApprovedBullets(campaign.id);
        for (final b in bullets) {
          if (b.experiencePhaseId == null || b.finalText.trim().isEmpty) continue;
          bulletsByPhase.putIfAbsent(b.experiencePhaseId!, () => []).add(b.finalText);
        }
      }

      _consolidateExperiences(mapping, bulletsByPhase);
    } catch (e) {
      print('Error applying frontend overrides: $e');
    }
  }

  static const _founderRoleKeywords = [
    'founder', 'fundador', 'fundadora', 'co-founder', 'cofundador', 'cofundadora',
    'ceo', 'cto', 'coo', 'cfo', 'cmo', 'criador', 'criadora',
  ];

  static final RegExp _metricRegex = RegExp(
    r'\d+(?:[.,]\d+)?\s*%'                                      // percentages
    r'|\d+(?:[.,]\d+)*\+'                                       // plus-counts (200+)
    r'|R\$\s*\d+'                                               // currency
    r'|\d+(?:[.,]\d+)*\s+(?:usuários|usuarios|downloads|membros|pessoas|clientes|alunos|atendentes|alvos|empresas|projetos|acessos|visitantes|seguidores|leads|trainees|participantes|vendas|receita|faturamento|investimento|investidores|países|paises)',
    caseSensitive: false,
  );

  /// True when a `proj` D1 entry should be promoted to Experience.
  /// Criteria: (a) role is a founder/C-suite term AND (b) at least one
  /// approved bullet contains a real-world metric.
  bool _shouldPromoteToExperience(_D1Entry entry, List<String>? approved) {
    if (entry.cat != 'proj') return false;
    final roleLower = entry.role.toLowerCase();
    final hasFounderRole = _founderRoleKeywords.any(roleLower.contains);
    if (!hasFounderRole) return false;
    if (approved == null || approved.isEmpty) return false;
    return approved.any((b) => _metricRegex.hasMatch(b));
  }

  static const Map<String, List<String>> _catToBucket = {
    'experiences': ['emp', 'free'],
    'leadership':  ['lead', 'vol'],
    'projects':    ['proj', 'res'],
    // 'spo' (sports) is intentionally NOT in any bucket — sports go to the
    // "Interesses" string per Harvard MCS guidelines, never as a standalone
    // experience/leadership entry.
  };

  static const Map<String, String> _monthAbbrPtBr = {
    '01': 'Jan', '02': 'Fev', '03': 'Mar', '04': 'Abr',
    '05': 'Mai', '06': 'Jun', '07': 'Jul', '08': 'Ago',
    '09': 'Set', '10': 'Out', '11': 'Nov', '12': 'Dez',
  };

  String _formatMonthYear(String? mmYYYY) {
    if (mmYYYY == null || mmYYYY.trim().isEmpty) return '';
    final parts = mmYYYY.split('/');
    if (parts.length != 2) return mmYYYY;
    final mm = parts[0].padLeft(2, '0');
    final yyyy = parts[1];
    final abbr = _monthAbbrPtBr[mm] ?? mm;
    return '$abbr $yyyy';
  }

  String _formatPeriod(String? start, String? end, bool ongoing) {
    final s = _formatMonthYear(start);
    final e = ongoing ? 'Atual' : _formatMonthYear(end);
    if (s.isEmpty && e.isEmpty) return '';
    if (s.isEmpty) return e;
    if (e.isEmpty) return s;
    return '$s - $e';
  }

  Future<({Map<String, _D1Entry> byKey, Map<String, List<_D1Entry>> byCat})>
      _buildExperienceMappingFromD1() async {
    final answers = await _repository.getUserAnswers();
    final byKey = <String, _D1Entry>{};
    final byCat = <String, List<_D1Entry>>{};
    final re = RegExp(r'^M3_D1_([a-z]+)_(\d+)$');

    for (final a in answers) {
      final qid = a['question_id'] as String? ?? '';
      final m = re.firstMatch(qid);
      if (m == null) continue;
      final raw = a['answer'];
      if (raw == null || raw is! String) continue;
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        final cat = m.group(1)!;
        final idx = int.parse(m.group(2)!);
        final entry = _D1Entry(
          cat: cat,
          idx: idx,
          org: (j['org'] as String? ?? '').trim(),
          role: (j['role'] as String? ?? '').trim(),
          start: j['start'] as String?,
          end: j['end'] as String?,
          ongoing: j['ongoing'] == true,
          city: (j['city'] as String?)?.trim(),
          // Canonical phase id used in approved_bullets table: 'm3.lead.0'
          phaseId: 'm3.$cat.$idx',
        );
        if (entry.org.isNotEmpty || entry.role.isNotEmpty) {
          byKey['${entry.org}|${entry.role}'.toLowerCase()] = entry;
        }
        byCat.putIfAbsent(entry.cat, () => []).add(entry);
      } catch (_) {}
    }
    byCat.forEach((_, l) => l.sort((a, b) => a.idx.compareTo(b.idx)));
    return (byKey: byKey, byCat: byCat);
  }

  _D1Entry? _matchEntry(
    String org,
    String role,
    String bucket,
    Map<String, _D1Entry> byKey,
    Map<String, List<_D1Entry>> byCatRemaining,
  ) {
    final orgLower = org.trim().toLowerCase();
    final roleLower = role.trim().toLowerCase();
    final cats = _catToBucket[bucket] ?? const <String>[];

    // 1) Exact match on (org+role)
    final exact = byKey['$orgLower|$roleLower'];
    if (exact != null && cats.contains(exact.cat)) {
      // Remove from queue so it isn't consumed twice
      byCatRemaining[exact.cat]?.removeWhere((e) => e.phaseId == exact.phaseId);
      return exact;
    }

    // 2) Fallback by org (same bucket): exact, then substring.
    // We DO NOT do ordinal fallback — better to leave an item un-matched
    // (and append leftover D1 entries separately) than to attach the wrong
    // dates/bullets to an AI-generated item that has no textual relation.
    if (orgLower.isNotEmpty) {
      for (final cat in cats) {
        final list = byCatRemaining[cat];
        if (list == null) continue;
        final idx = list.indexWhere((e) => e.org.toLowerCase() == orgLower);
        if (idx >= 0) return list.removeAt(idx);
        final subIdx = list.indexWhere((e) {
          final eOrg = e.org.toLowerCase();
          return eOrg.isNotEmpty &&
              (orgLower.contains(eOrg) || eOrg.contains(orgLower));
        });
        if (subIdx >= 0) return list.removeAt(subIdx);
      }
    }
    return null;
  }

  /// Single-pass consolidation: walks every list of `_resumeContent`
  /// matching each item against D1 entries (date + bullets in one pass), then
  /// appends any leftover D1 entries that the AI omitted entirely.
  void _consolidateExperiences(
    ({Map<String, _D1Entry> byKey, Map<String, List<_D1Entry>> byCat}) mapping,
    Map<String, List<String>> bulletsByPhase,
  ) {
    if (_resumeContent == null) return;
    final remaining = <String, List<_D1Entry>>{
      for (final e in mapping.byCat.entries) e.key: List<_D1Entry>.from(e.value),
    };
    String bulletsAsDescription(List<String> list) =>
        list.map((b) => '• $b').join('\n');

    // Phase 1: walk AI items and match each. Track indices that did NOT match
    // so leftover D1 entries can REPLACE them (avoids duplicates when the AI
    // describes the same experience under a different title).
    // Also track which indices were POPULATED FROM D1 (matched or replaced/
    // appended in phase 2) so we can prefer those over AI duplicates during
    // a final cross-section dedup.
    final unmatchedExpIdx = <int>[];
    final unmatchedLeadIdx = <int>[];
    final unmatchedProjIdx = <int>[];
    final expFromD1 = <int>{};
    final leadFromD1 = <int>{};
    final projFromD1 = <int>{};

    final newExperiences = <ResumeExperience>[];
    for (int i = 0; i < _resumeContent!.experiences.length; i++) {
      final exp = _resumeContent!.experiences[i];
      final match = _matchEntry(exp.company, exp.role, 'experiences', mapping.byKey, remaining);
      if (match == null) {
        unmatchedExpIdx.add(i);
        newExperiences.add(exp);
        continue;
      }
      expFromD1.add(i);
      final period = _formatPeriod(match.start, match.end, match.ongoing);
      final approved = bulletsByPhase[match.phaseId];
      newExperiences.add(ResumeExperience(
        role: exp.role.isNotEmpty ? exp.role : match.role,
        company: exp.company.isNotEmpty ? exp.company : match.org,
        period: period.isNotEmpty ? period : exp.period,
        description: (approved != null && approved.isNotEmpty)
            ? bulletsAsDescription(approved)
            : exp.description,
      ));
    }

    final newLeadership = <ResumeLeadership>[];
    for (int i = 0; i < _resumeContent!.leadership.length; i++) {
      final lead = _resumeContent!.leadership[i];
      final match = _matchEntry(lead.organization, lead.role, 'leadership', mapping.byKey, remaining);
      if (match == null) {
        unmatchedLeadIdx.add(i);
        newLeadership.add(lead);
        continue;
      }
      leadFromD1.add(i);
      final period = _formatPeriod(match.start, match.end, match.ongoing);
      final approved = bulletsByPhase[match.phaseId];
      newLeadership.add(ResumeLeadership(
        role: lead.role.isNotEmpty ? lead.role : match.role,
        organization: lead.organization.isNotEmpty ? lead.organization : match.org,
        period: period.isNotEmpty ? period : lead.period,
        location: lead.location.isNotEmpty ? lead.location : (match.city ?? ''),
        description: (approved != null && approved.isNotEmpty)
            ? bulletsAsDescription(approved)
            : lead.description,
      ));
    }

    final newProjects = <ResumeProject>[];
    for (int i = 0; i < _resumeContent!.academicProjects.length; i++) {
      final proj = _resumeContent!.academicProjects[i];
      final match = _matchEntry(proj.title, proj.role, 'projects', mapping.byKey, remaining);
      if (match == null) {
        unmatchedProjIdx.add(i);
        newProjects.add(proj);
        continue;
      }
      projFromD1.add(i);
      final period = _formatPeriod(match.start, match.end, match.ongoing);
      final approved = bulletsByPhase[match.phaseId];
      newProjects.add(ResumeProject(
        title: proj.title.isNotEmpty ? proj.title : match.org,
        role: proj.role.isNotEmpty ? proj.role : match.role,
        period: period.isNotEmpty ? period : proj.period,
        description: (approved != null && approved.isNotEmpty)
            ? bulletsAsDescription(approved)
            : proj.description,
        location: proj.location.isNotEmpty ? proj.location : (match.city ?? ''),
      ));
    }

    // Phase 2: place leftover D1 entries — REPLACE an unmatched AI item in
    // the same bucket if available (likely the AI rephrased the same thing),
    // else APPEND as a new entry.
    // Sport entries (cat=spo) are collected separately to be merged into the
    // "Interesses" string per Harvard MCS guidelines.
    final sportInterestPhrases = <String>[];

    for (final cat in remaining.keys) {
      for (final entry in remaining[cat]!) {
        if (entry.org.isEmpty && entry.role.isEmpty) continue;
        final period = _formatPeriod(entry.start, entry.end, entry.ongoing);
        final approved = bulletsByPhase[entry.phaseId];
        final desc = (approved != null && approved.isNotEmpty)
            ? bulletsAsDescription(approved)
            : '';

        if (cat == 'spo') {
          // Build a SHORT phrase from role + org. Approved bullets are too
          // long for an interests line. Skip entirely if the AI already
          // mentioned this sport in the interests sentence.
          final aiInterests = (_resumeContent?.interests ?? '').toLowerCase();
          final roleLower = entry.role.toLowerCase();
          final orgLower = entry.org.toLowerCase();

          // Detect overlap: if AI's interests already contains 5+ chars from
          // the role (e.g., "basquete"), don't repeat ourselves.
          bool alreadyMentioned = false;
          if (orgLower.isNotEmpty && aiInterests.contains(orgLower)) {
            alreadyMentioned = true;
          }
          if (!alreadyMentioned) {
            for (final w in roleLower.split(RegExp(r'\s+'))) {
              if (w.length >= 5 && aiInterests.contains(w)) {
                alreadyMentioned = true;
                break;
              }
            }
          }
          if (alreadyMentioned) {
            continue; // skip — AI already covered it
          }

          String phrase;
          if (entry.role.isNotEmpty && entry.org.isNotEmpty) {
            phrase = '${entry.role.toLowerCase()} pela ${entry.org}';
          } else if (entry.org.isNotEmpty) {
            phrase = 'esporte pela ${entry.org}';
          } else if (entry.role.isNotEmpty) {
            phrase = entry.role.toLowerCase();
          } else {
            continue;
          }
          sportInterestPhrases.add(phrase);
          continue;
        }

        if (cat == 'emp' || cat == 'free') {
          final exp = ResumeExperience(
            role: entry.role,
            company: entry.org,
            period: period,
            description: desc,
          );
          if (unmatchedExpIdx.isNotEmpty) {
            final idx = unmatchedExpIdx.removeAt(0);
            newExperiences[idx] = exp;
            expFromD1.add(idx);
          } else {
            newExperiences.add(exp);
            expFromD1.add(newExperiences.length - 1);
          }
        } else if (cat == 'lead' || cat == 'vol') {
          final lead = ResumeLeadership(
            role: entry.role,
            organization: entry.org,
            period: period,
            location: entry.city ?? '',
            description: desc,
          );
          if (unmatchedLeadIdx.isNotEmpty) {
            final idx = unmatchedLeadIdx.removeAt(0);
            newLeadership[idx] = lead;
            leadFromD1.add(idx);
          } else {
            newLeadership.add(lead);
            leadFromD1.add(newLeadership.length - 1);
          }
        } else if (cat == 'proj' || cat == 'res') {
          // Harvard rule: a personal project led by a founder/CEO/CTO with
          // real-world metrics (users, revenue, percentages, etc.) belongs
          // in PROFESSIONAL EXPERIENCE, not in Leadership/Activities.
          if (cat == 'proj' && _shouldPromoteToExperience(entry, approved)) {
            final exp = ResumeExperience(
              role: entry.role,
              company: entry.org,
              period: period,
              description: desc,
            );
            if (unmatchedExpIdx.isNotEmpty) {
              final idx = unmatchedExpIdx.removeAt(0);
              newExperiences[idx] = exp;
              expFromD1.add(idx);
            } else {
              newExperiences.add(exp);
              expFromD1.add(newExperiences.length - 1);
            }
            continue;
          }

          final proj = ResumeProject(
            title: entry.org,
            role: entry.role,
            period: period,
            description: desc,
            location: entry.city ?? '',
          );
          if (unmatchedProjIdx.isNotEmpty) {
            final idx = unmatchedProjIdx.removeAt(0);
            newProjects[idx] = proj;
            projFromD1.add(idx);
          } else {
            newProjects.add(proj);
            projFromD1.add(newProjects.length - 1);
          }
        }
      }
    }

    // Phase 3: cross-section dedup. If the same (org+role) appears in more
    // than one of [experiences, leadership, projects], keep ONLY the entry
    // that was populated from D1 (which has structured period + approved
    // bullets). This handles cases like AI putting "Stage|Fundador" under
    // experiences while D1 has it under projects.
    String entryKey(String a, String b) =>
        '${a.toLowerCase().trim()}|${b.toLowerCase().trim()}';

    // Collect keys that have at least one D1-sourced entry across all sections
    final keysFromD1 = <String>{};
    for (final i in expFromD1) {
      final e = newExperiences[i];
      keysFromD1.add(entryKey(e.company, e.role));
    }
    for (final i in leadFromD1) {
      final l = newLeadership[i];
      keysFromD1.add(entryKey(l.organization, l.role));
    }
    for (final i in projFromD1) {
      final p = newProjects[i];
      keysFromD1.add(entryKey(p.title, p.role));
    }
    final dedupExp = <ResumeExperience>[];
    for (int i = 0; i < newExperiences.length; i++) {
      final e = newExperiences[i];
      final k = entryKey(e.company, e.role);
      if (k != '|' && keysFromD1.contains(k) && !expFromD1.contains(i)) {
        continue;
      }
      dedupExp.add(e);
    }
    final dedupLead = <ResumeLeadership>[];
    for (int i = 0; i < newLeadership.length; i++) {
      final l = newLeadership[i];
      final k = entryKey(l.organization, l.role);
      if (k != '|' && keysFromD1.contains(k) && !leadFromD1.contains(i)) {
        continue;
      }
      dedupLead.add(l);
    }
    final dedupProj = <ResumeProject>[];
    for (int i = 0; i < newProjects.length; i++) {
      final p = newProjects[i];
      final k = entryKey(p.title, p.role);
      if (k != '|' && keysFromD1.contains(k) && !projFromD1.contains(i)) {
        continue;
      }
      dedupProj.add(p);
    }

    // Merge sport phrases into the interests string (Harvard style).
    String mergedInterests = _resumeContent!.interests;
    if (sportInterestPhrases.isNotEmpty) {
      final extras = sportInterestPhrases.join('; ');
      if (mergedInterests.trim().isEmpty) {
        mergedInterests = extras;
      } else {
        // Strip trailing punctuation, append, restore period.
        final base = mergedInterests.trim().replaceAll(RegExp(r'[.;]+$'), '');
        mergedInterests = '$base; $extras';
      }
      if (!mergedInterests.trim().endsWith('.')) {
        mergedInterests = '$mergedInterests.';
      }
    }
    _resumeContent = ResumeContent(
      summary: _resumeContent!.summary,
      skills: _resumeContent!.skills,
      experiences: dedupExp,
      education: _resumeContent!.education,
      achievements: _resumeContent!.achievements,
      interests: mergedInterests,
      academicProjects: dedupProj,
      leadership: dedupLead,
      courses: _resumeContent!.courses,
      languages: _resumeContent!.languages,
      awards: _resumeContent!.awards,
    );
  }

  Future<void> _overrideSummaryFromSectionVersions(String userId) async {
    if (_resumeContent == null) return;
    try {
      final campaign = await _repository.getLatestCampaign(userId);
      if (campaign == null) {
        return;
      }
      final approved = await _repository.getApprovedSummary(campaign.id);
      if (approved == null) {
        return;
      }
      final finalText = (approved.editedContent != null && approved.editedContent!.isNotEmpty)
          ? approved.editedContent!
          : approved.content;
      if (finalText.trim().isEmpty) return;
      _resumeContent = ResumeContent(
        summary: finalText,
        skills: _resumeContent!.skills,
        experiences: _resumeContent!.experiences,
        education: _resumeContent!.education,
        achievements: _resumeContent!.achievements,
        interests: _resumeContent!.interests,
        academicProjects: _resumeContent!.academicProjects,
        leadership: _resumeContent!.leadership,
        courses: _resumeContent!.courses,
        languages: _resumeContent!.languages,
        awards: _resumeContent!.awards,
      );
    } catch (e) {
      print('Error overriding summary: $e');
    }
  }


  Future<ResumeData> _convertToResumeData(ResumeContent content) async {
    List<String> processList(String text) {
      if (text.isEmpty || text.contains('Continue a trilha')) return [];
      return text.split('\n')
          .where((line) => line.trim().isNotEmpty)
          .map((line) => line.replaceAll('•', '').trim())
          .toList();
    }

    final languageNames = content.languages.map((l) => l.language.toLowerCase()).toList();

    // Read tools with level from M4_1_1_Q1
    final tools = await _readToolsFromAnswers();
    // Read academic highlights from M2_1_1_Q5 (all fields optional)
    final academicHighlights = await _readAcademicHighlights();
    final toolNamesLower = tools.map((t) => t.name.toLowerCase()).toSet();

    // Filter tool names out of the generic "Técnico" list to avoid the same
    // tool appearing in both "Ferramentas" and "Técnico". Catches:
    //   "Excel"                — exact match
    //   "Excel (Avançado)"     — parenthesised level
    //   "Excel Avançado"       — concatenated level (AI output style)
    final filteredSkills = processList(content.skills)
        .where((skill) {
          final lower = skill.toLowerCase().trim();
          if (languageNames.contains(lower)) return false;
          if (toolNamesLower.contains(lower)) return false;
          // strip "(...)" suffix
          final stripped = lower.replaceAll(RegExp(r'\s*\(.*?\)\s*$'), '').trim();
          if (toolNamesLower.contains(stripped)) return false;
          // starts with a tool name followed by a separator (space or paren)
          for (final tool in toolNamesLower) {
            if (tool.isEmpty) continue;
            if (lower.startsWith('$tool ') || lower.startsWith('$tool(')) {
              return false;
            }
          }
          return true;
        })
        .toList();

    return ResumeData(
      fullName: _resumeData?.fullName ?? '',
      email: _resumeData?.email ?? '',
      phone: _resumeData?.phone ?? '',
      linkedin: _resumeData?.linkedin ?? '',
      location: _resumeData?.location ?? '',
      address: _resumeData?.address ?? '',
      summary: content.summary,
      skills: filteredSkills,
      tools: tools,
      experiences: content.experiences.map((e) => ExperienceItem(
        role: e.role,
        company: e.company,
        period: e.period,
        description: e.description,
      )).toList(),
      education: content.education.asMap().entries.map((entry) {
        final e = entry.value;
        // Apply Harvard highlights only to the FIRST education item
        // (the user's current/primary degree).
        final isFirst = entry.key == 0;
        return EducationItem(
          degree: e.course,
          institution: e.institution,
          period: e.period,
          details: e.details,
          gpa: isFirst ? (academicHighlights['gpa'] ?? '') : '',
          honors: isFirst ? (academicHighlights['honors'] ?? '') : '',
          repRole: isFirst ? (academicHighlights['rep_role'] ?? '') : '',
          coursework: isFirst ? (academicHighlights['coursework'] ?? '') : '',
        );
      }).toList(),
      achievements: processList(content.achievements),
      interests: processList(content.interests),
      academicProjects: content.academicProjects,
      leadership: content.leadership,
      courses: content.courses,
      languages: content.languages,
      awards: content.awards,
    );
  }

  bool _shouldUpdateString(String current, String newVal) {
    if (current.isEmpty) return true;
    if (current.contains('Continue a trilha')) return true;
    return false;
  }

  bool _shouldUpdateList(List current, List newVal) {
    if (current.isEmpty) return true;
    return newVal.isNotEmpty;
  }

  void _createPlaceholderResume() {
    _resumeData = ResumeData(
      fullName: 'Seu Nome',
      email: 'seu.email@exemplo.com',
      phone: '(11) 99999-9999',
      linkedin: 'linkedin.com/in/seunome',
      location: 'Sua Cidade, Estado',
      summary: 'Continue a trilha para gerar seu resumo profissional.',
      skills: ['Habilidade 1', 'Habilidade 2'],
      experiences: [],
      education: [],
      achievements: [],
      interests: [],
      academicProjects: [
        ResumeProject(title: 'Projeto de Estratégia', role: 'Líder', period: 'Set 2024 - Dez 2024', description: 'Liderou equipe de 5 pessoas na criação de plano de marketing.'),
      ],
      leadership: [
        ResumeLeadership(role: 'Diretor de Marketing', organization: 'Atlética da Faculdade', period: 'Ago 2024 - Atual', location: 'São Paulo', description: 'Gestão de redes sociais e eventos.'),
      ],
      courses: [
         ResumeCourse(title: 'Google Digital Marketing', institution: 'Coursera', period: 'Jun 2024'),
      ],
      languages: [
        ResumeLanguage(language: 'Inglês', level: 'Fluente'),
        ResumeLanguage(language: 'Espanhol', level: 'Intermediário'),
      ],
      awards: [
        ResumeAward(title: 'Dean\'s List', institution: 'Universidade', date: 'Dez 2024', description: 'Reconhecimento por excelência acadêmica.'),
      ],
    );
  }

  Future<void> saveToLibrary(UserProfile? user, String title) async {
    if (_resumeData == null) return;

    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      // 1. Generate PDF bytes
      final bytes = await PdfService.generateResumeBytes(user, _resumeData!, _selectedTemplateId);
      
      // 2. Save to Supabase
      await _repository.saveResume(title, bytes);
      
      print('DEBUG: Resume saved to library: $title');
    } catch (e) {
      print('Error saving to library: $e');
      _error = 'Erro ao salvar na biblioteca: $e';
      rethrow;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }
}

class _D1Entry {
  final String cat;
  final int idx;
  final String org;
  final String role;
  final String? start;
  final String? end;
  final bool ongoing;
  final String? city;
  final String phaseId;

  const _D1Entry({
    required this.cat,
    required this.idx,
    required this.org,
    required this.role,
    required this.start,
    required this.end,
    required this.ongoing,
    required this.city,
    required this.phaseId,
  });
}
