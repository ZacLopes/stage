import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_repository.dart';
import '../../services/ai_service.dart';
import '../../data/models/models.dart';
import '../../data/local_storage_repository.dart';
import 'pdf_service.dart';

class ResumeData {
  final String fullName;
  final String email;
  final String phone;
  final String linkedin;
  final String location;
  final String summary;
  final List<String> skills;
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
    this.summary = '',
    this.skills = const [],
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
    String? summary,
    List<String>? skills,
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
      summary: summary ?? this.summary,
      skills: skills ?? this.skills,
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

  ExperienceItem({
    required this.role,
    required this.company,
    required this.period,
    required this.description,
  });
}

class EducationItem {
  final String degree;
  final String institution;
  final String period;
  final String details;

  EducationItem({
    required this.degree,
    required this.institution,
    required this.period,
    this.details = '',
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
    _resumeData = _convertToResumeData(newContent);
    await _updateHeaderInfo();
    notifyListeners();
  }

  bool _isCourseCompleted = false;
  bool get isCourseCompleted => _isCourseCompleted;

  Future<void> loadResumeData() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      _clearData();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _isCourseCompleted = await _repository.isEntireCourseCompleted();
      
      if (!_isCourseCompleted) {
        _resumeData = null;
        _resumeContent = null;
        return;
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
        _resumeData = _convertToResumeData(_resumeContent!);
        await _updateHeaderInfo();
      } else {
        // Only trigger AI if consent is already given, otherwise Tab will handle modal
        final userProfile = await _repository.getUserProfile();
        if (userProfile != null && userProfile.aiConsent) {
          await generateResumeWithAI();
        } else if (_resumeContent != null) {
          // Keep what we have but it's empty
          _resumeData = _convertToResumeData(_resumeContent!);
          await _updateHeaderInfo();
        }
      }
    } catch (e) {
      _error = 'Erro ao carregar currículo: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
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

    String linkedin = getAnswer('M5_1_1_Q1') ?? '';
    if (linkedin.isEmpty && userProfile != null) {
       linkedin = 'linkedin.com/in/${userProfile.name.replaceAll(' ', '').toLowerCase()}';
    }

    String email = getAnswer('M5_1_1_Q3') ?? userProfile?.email ?? 'email@exemplo.com';
    String phone = getAnswer('M5_1_1_Q4') ?? '(11) 99999-9999';
    String location = getAnswer('M5_2_1_Q1') ?? 'São Paulo, SP';

    if (userProfile != null) {
      _resumeData = _resumeData!.copyWith(
        fullName: userProfile.name,
        email: email,
        phone: phone,
        linkedin: linkedin,
        location: location,
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
      await _localStorage.saveResumeContent(userId, _resumeContent!);
      
      _resumeData = _convertToResumeData(_resumeContent!);
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
      _resumeData = _convertToResumeData(_resumeContent!);
      await _updateHeaderInfo();
    } catch (e) {
      _error = 'Erro ao atualizar currículo: $e';
    } finally {
      _isGeneratingResume = false;
      notifyListeners();
    }
  }

  ResumeData _convertToResumeData(ResumeContent content) {
    List<String> processList(String text) {
      if (text.isEmpty || text.contains('Continue a trilha')) return [];
      return text.split('\n')
          .where((line) => line.trim().isNotEmpty)
          .map((line) => line.replaceAll('•', '').trim())
          .toList();
    }

    final languageNames = content.languages.map((l) => l.language.toLowerCase()).toList();

    return ResumeData(
      fullName: _resumeData?.fullName ?? 'Carregando...',
      email: _resumeData?.email ?? 'email@exemplo.com',
      phone: _resumeData?.phone ?? '(11) 99999-9999',
      linkedin: _resumeData?.linkedin ?? 'linkedin.com/in/usuario',
      location: _resumeData?.location ?? 'São Paulo, SP',
      summary: content.summary,
      skills: processList(content.skills).where((skill) => !languageNames.contains(skill.toLowerCase())).toList(),
      experiences: content.experiences.map((e) => ExperienceItem(
        role: e.role,
        company: e.company,
        period: e.period,
        description: e.description,
      )).toList(),
      education: content.education.map((e) => EducationItem(
        degree: e.course,
        institution: e.institution,
        period: e.period,
        details: e.details,
      )).toList(),
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
      final bytes = await PdfService.generateResumeBytes(user, _resumeData!, 'quickcv');
      
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
