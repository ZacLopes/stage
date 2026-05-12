import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/models.dart';
import '../../data/supabase_repository.dart';
import '../../services/ai_service.dart';
import '../../services/analytics_service.dart';
import 'gamification_logic.dart';

enum PhaseStatus { locked, available, completed }

class GamificationViewModel extends ChangeNotifier {
  final SupabaseRepository _repository;
  final AIService _aiService = AIService();
  
  Future<Map<String, String>> _getAllAnswers() async {
    return await _repository.getUserAnswersWithQuestions();
  }

  // Track Details State
  List<Phase> _phases = [];
  bool _isLoadingPhases = false;
  Set<String> _completedPhaseIds = {};
  
  // Question Flow State
  List<Question> _questions = [];
  int _currentQuestionIndex = 0;
  Map<String, dynamic> _answers = {}; // questionId -> answer
  bool _isLoadingQuestions = false;
  bool _isPhaseCompleted = false;

  // Phase 5 — bullet & summary generation flags
  String? _pendingBulletExperienceId; // set after D5; cleared by BulletReviewScreen
  bool _pendingSummaryGeneration = false; // set after last t5 phase
  String? get pendingBulletExperienceId => _pendingBulletExperienceId;
  bool get pendingSummaryGeneration => _pendingSummaryGeneration;
  void clearBulletPending() { _pendingBulletExperienceId = null; notifyListeners(); }
  void clearSummaryPending() { _pendingSummaryGeneration = false; notifyListeners(); }

  GamificationViewModel(this._repository) {
    _init();
  }

  void _init() {
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      if (event == AuthChangeEvent.signedIn) {
        _loadCompletedPhases();
      } else if (event == AuthChangeEvent.signedOut) {
        _clearData();
      }
    });

    // Load immediately if user is already logged in
    if (Supabase.instance.client.auth.currentUser != null) {
      _loadCompletedPhases();
    }
  }

  Future<void> _loadCompletedPhases() async {
    try {
      _completedPhaseIds = await _repository.getCompletedPhaseIds();
      await _loadGlobalProgress(); // Initial load of progress
      
      notifyListeners();
    } catch (e) {
      print('Error loading completed phases: $e');
    }
  }

  void _clearData() {
    _phases = [];
    _completedPhaseIds = {};
    _questions = [];
    _currentQuestionIndex = 0;
    _answers = {};
    _isLoadingPhases = false;
    _isLoadingQuestions = false;
    _isPhaseCompleted = false;
    _pendingBulletExperienceId = null;
    _pendingSummaryGeneration = false;
    notifyListeners();
  }

  List<Phase> get phases => _phases;
  bool get isLoadingPhases => _isLoadingPhases;
  
  List<Question> get questions => _questions;
  Question? get currentQuestion => _questions.isNotEmpty && _currentQuestionIndex < _questions.length ? _questions[_currentQuestionIndex] : null;
  bool get isLoadingQuestions => _isLoadingQuestions;
  bool get isCurrentPhaseFinished => _isPhaseCompleted;
  int get currentQuestionIndex => _currentQuestionIndex;
  double get progress => _questions.isEmpty ? 0 : (_currentQuestionIndex / _questions.length);

  // Global Progress
  double _totalCareerProgress = 0.0;
  double get totalCareerProgress => _totalCareerProgress;


  Future<void> _loadGlobalProgress() async {
    try {
      final tracks = await _repository.getTracks();
      final Set<String> activePhaseIds = {};
      
      for (var track in tracks) {
        final phases = await _repository.getPhases(track.id);
        
        for (var p in phases) {
          activePhaseIds.add(p.id);
        }
      }

      // Filter completed IDs to only count those that are still in active phases
      final completedActiveCount = _completedPhaseIds.where((id) => activePhaseIds.contains(id)).length;
      
      if (activePhaseIds.isNotEmpty) {
        _totalCareerProgress = completedActiveCount / activePhaseIds.length;
      } else {
        _totalCareerProgress = 0.0;
      }
      
      print('📊 Global Progress updated: $completedActiveCount / ${activePhaseIds.length} = $_totalCareerProgress');
      notifyListeners();
    } catch (e) {
      print('Error loading global progress: $e');
    }
  }

  Future<void> loadPhases(String trackId) async {
    _isLoadingPhases = true;
    notifyListeners();
    try {
      _phases = await _repository.getPhases(trackId);
      _completedPhaseIds = await _repository.getCompletedPhaseIds();
    } catch (e) {
      print('Error loading phases: $e');
    } finally {
      _isLoadingPhases = false;
      notifyListeners();
    }
  }

  /// Whether ALL phases across ALL tracks are now marked as completed.
  /// Used by PhaseCompletionWidget to decide if the "curriculum ready"
  /// celebration should fire — more reliable than checking if the just-
  /// completed phase is the last phase of `_phases`, because callers may
  /// enter QuestionScreen without first calling [loadPhases] (e.g. the
  /// `unified_track_list` direct-push path), which leaves `_phases`
  /// stale and breaks the heuristic.
  Future<bool> isEntireCourseCompleted() {
    return _repository.isEntireCourseCompleted();
  }

  PhaseStatus getPhaseStatus(int phaseIndex) {
    if (phaseIndex >= _phases.length) return PhaseStatus.locked;
    
    final phase = _phases[phaseIndex];
    
    // Check if completed
    if (_completedPhaseIds.contains(phase.id)) {
      return PhaseStatus.completed;
    }
    
    // Check if unlocked (first phase or previous phase completed)
    if (phaseIndex == 0) {
      return PhaseStatus.available;
    }
    
    final previousPhase = _phases[phaseIndex - 1];
    if (_completedPhaseIds.contains(previousPhase.id)) {
      return PhaseStatus.available;
    }
    
    return PhaseStatus.locked;
  }

  bool isPhaseUnlocked(int phaseIndex) {
    final status = getPhaseStatus(phaseIndex);
    return status == PhaseStatus.available || status == PhaseStatus.completed;
  }

  bool isPhaseCompleted(String phaseId) {
    return _completedPhaseIds.contains(phaseId);
  }

  // Start a Phase
  Future<void> startPhase(String phaseId) async {
    Analytics.shared.trackPhaseStarted(phaseId: phaseId);
    _isLoadingQuestions = true;
    _currentQuestionIndex = 0;
    _answers = {};
    _isPhaseCompleted = false;
    notifyListeners();

    try {
      final fetchedQuestions = await _repository.getQuestions(phaseId);

      // Build static question list — dynamic questions are regenerated by replay below.
      // M3_D* are experience detail questions (generated from quantity answer).
      // M3_1_1_Q2_* are legacy (pre-Phase 4) dynamic forms.
      // M4_2_1_Q2_* are language level questions (generated from language answer).
      _questions = fetchedQuestions.where((q) =>
          !q.id.startsWith('M3_D') &&
          !q.id.startsWith('M3_1_1_Q2_') &&
          !q.id.startsWith('M4_2_1_Q2_')
      ).map((q) {
        final sanitizedOptions = q.options.map((opt) {
          return opt.replaceAll(RegExp(r'[\u{1f300}-\u{1f5ff}\u{1f600}-\u{1f64f}\u{1f680}-\u{1f6ff}\u{1f1e6}-\u{1f1ff}\u{2600}-\u{26ff}\u{2700}-\u{27bf}\u{1f900}-\u{1f9ff}\u{1f018}-\u{1f270}\u{1f300}-\u{1f5ff}\u{1f900}-\u{1f9ff}\u{1f600}-\u{1f64f}\u{1f680}-\u{1f6ff}\u{1f1e6}-\u{1f1ff}]', unicode: true), '').trim();
        }).toList();
        return Question(id: q.id, phaseId: q.phaseId, type: q.type, content: q.content, options: sanitizedOptions);
      }).toList();

      // Partial progress restore: replay saved answers through dynamic generation,
      // then advance to the first unanswered question.
      final baseIds = _questions.map((q) => q.id).toList();
      final savedAnswers = await _repository.getAnswersForQuestions(baseIds);
      if (savedAnswers.isNotEmpty) {
        final baseSnapshot = List<Question>.from(_questions);
        for (final q in baseSnapshot) {
          final saved = savedAnswers[q.id];
          if (saved != null) {
            _answers[q.id] = saved;
            _handleDynamicQuestionGeneration(q.id, saved);
          }
        }
        // Fetch answers for dynamically-injected questions (e.g. D1-D5)
        final dynamicIds = _questions.map((q) => q.id).where((id) => !baseIds.contains(id)).toList();
        if (dynamicIds.isNotEmpty) {
          final dynAnswers = await _repository.getAnswersForQuestions(dynamicIds);
          _answers.addAll(dynAnswers);
        }
        // Advance to first unanswered
        _currentQuestionIndex = _questions.length - 1;
        for (int i = 0; i < _questions.length; i++) {
          if (!_answers.containsKey(_questions[i].id)) {
            _currentQuestionIndex = i;
            break;
          }
        }
      }
    } catch (e) {
      print('Error loading questions: $e');
    } finally {
      _isLoadingQuestions = false;
      notifyListeners();
    }
  }

  // Answer Question
  dynamic getAnswer(String questionId) {
    return _answers[questionId];
  }

  Future<void> answerQuestion(dynamic answer) async {
    if (currentQuestion == null) return;
    
    final currentQ = currentQuestion!;
    _answers[currentQ.id] = answer;
    
    // Save answer to database
    try {
      // Sync dynamic questions on the fly to avoid Foreign Key errors
      await _repository.ensureQuestionExists(currentQ);

      final answerStr = answer is List ? answer.join(',') : answer.toString();
      await _repository.saveAnswer(currentQ.id, answerStr);

      // Dual-write to raw_responses for all modules
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        const _phaseLabels = {
          // M1 Direção
          'M1_3_1_Q2': 'm1.1', 'M1_3_1_Q25': 'm1.2', 'M1_3_1_Q3': 'm1.3',
          // M2 Formação
          'M2_1_1_Q1': 'm2.1', 'M2_1_1_Q5': 'm2.1d', 'M2_1_1_Q2': 'm2.1b', 'M2_1_1_Q3': 'm2.1c',
          'M3_2_1_Q1': 'm2.2a', 'M3_2_1_Q2': 'm2.2b',
          'M2_3_1_Q1': 'm2.3a', 'M2_3_1_Q4': 'm2.3b',
          // M3 Experiências (Phase 4 redesign)
          'M3_1_1_Q1': 'm3.inventory',
          'M3_1_1_QCount': 'm3.count',
          // M4 Habilidades
          'M4_1_1_Q1': 'm4.1',
          'M4_2_1_Q1': 'm4.2a', 'M4_2_1_Q4': 'm4.2b',
          // M4_2_1_Q3 stores the structured languages list (resume edit override)
          'M4_2_1_Q3': 'm4.2c',
          // M5 Contatos
          'M5_1_1_Q1': 'm5.1',
          'M5_2_1_Q1': 'm5.2a', 'M5_2_1_Q2': 'm5.2b',
        };
        // Derive raw phase_id for M3 D-questions: M3_D{d}_{cat}_{n} → m3.{cat}.{n}.d{d}
        String? rawPhaseId = _phaseLabels[currentQ.id];
        if (rawPhaseId == null) {
          final m3d = RegExp(r'^M3_D(\d+)_(\w+)_(\d+)$').firstMatch(currentQ.id);
          if (m3d != null) {
            rawPhaseId = 'm3.${m3d.group(2)}.${m3d.group(3)}.d${m3d.group(1)}';
          }
        }
        if (rawPhaseId == null && currentQ.id.startsWith('M3_1_1_Q2_')) {
          rawPhaseId = 'm3.legacy_exp';
        }
        if (rawPhaseId != null) {
          String answerType;
          if (currentQ.type == QuestionType.text || currentQ.type == QuestionType.miniTextBox) {
            answerType = 'free_text';
          } else if (currentQ.type == QuestionType.singleChoice || currentQ.type == QuestionType.scale) {
            answerType = 'single_choice';
          } else {
            answerType = 'multi_choice';
          }
          await _repository.saveRawResponse(
            userId: userId,
            phaseId: rawPhaseId,
            question: currentQ.content,
            answer: answerStr,
            answerType: answerType,
            questionOrder: _currentQuestionIndex,
          );
        }
      }
    } catch (e) {
      print('Error saving answer: $e');
    }

    // --- Dynamic Question Generation Logic ---
    _handleDynamicQuestionGeneration(currentQ.id, answer);

    // --- Phase 5: Intercept D6 answers → trigger bullet generation ---
    // D6 is the optional "metric" question. We trigger AFTER it (whether
    // filled or skipped) so that the AI has the numbers when generating.
    final d6Match = RegExp(r'^M3_D6_(\w+)_(\d+)$').firstMatch(currentQ.id);
    if (d6Match != null) {
      final cat = d6Match.group(1)!;
      final n = d6Match.group(2)!;
      _pendingBulletExperienceId = 'm3.$cat.$n';
      notifyListeners();
      return; // Don't advance yet — BulletReviewScreen calls resumeAfterBullet()
    }

    if (_currentQuestionIndex < _questions.length - 1) {
      _currentQuestionIndex++;
      notifyListeners();
    } else {
      await _finishPhase();
    }
  }

  /// Called by BulletReviewScreen after a bullet is approved (or skipped).
  /// Advances the question flow to the next question or finishes the phase.
  Future<void> resumeAfterBullet() async {
    _pendingBulletExperienceId = null;
    if (_currentQuestionIndex < _questions.length - 1) {
      _currentQuestionIndex++;
      notifyListeners();
    } else {
      await _finishPhase();
    }
  }

  void previousQuestion() {
    if (_currentQuestionIndex > 0) {
      _currentQuestionIndex--;
      notifyListeners();
    }
  }

  void _handleDynamicQuestionGeneration(String currentQuestionId, dynamic answer) {
    // Helper to parse answer into List<String>
    List<String> parseAnswerList(dynamic ans) {
      if (ans is List) return ans.map((e) => e.toString()).toList();
      if (ans is String) {
        if (ans.isEmpty) return [];
        // CHECK IF IT IS A JSON LIST first
        if (ans.trim().startsWith('[')) {
          try {
            final parsed = jsonDecode(ans);
            if (parsed is List) {
              return parsed.map((e) => e.toString()).toList();
            }
          } catch (_) {}
        }
        return ans.split('|');
      }
      return [];
    }

    // --- MODULE 3.1: INVENTORY (Q1) → INJECT QCOUNT (if not 'none') ---
    if (currentQuestionId == 'M3_1_1_Q1') {
      List<String> categories = [];
      try {
        final parsed = jsonDecode(answer.toString());
        if (parsed is List) categories = parsed.map((e) => e.toString()).toList();
      } catch (_) {}

      final q1Index = _questions.indexWhere((q) => q.id == 'M3_1_1_Q1');
      if (q1Index != -1) {
        final insertAt = q1Index + 1;
        // Remove existing QCount and any D-questions (so replay is idempotent)
        while (insertAt < _questions.length &&
            (_questions[insertAt].id == 'M3_1_1_QCount' ||
                _questions[insertAt].id.startsWith('M3_D'))) {
          _questions.removeAt(insertAt);
        }
        if (!categories.contains('none') && categories.isNotEmpty) {
          _questions.insert(insertAt, Question(
            id: 'M3_1_1_QCount',
            phaseId: 't3_p1',
            type: QuestionType.experienceQuantity,
            content: 'Quantas experiências você teve em cada categoria?',
            options: categories, // category codes for ExperienceQuantityWidget
          ));
        }
      }
    }

    // --- MODULE 3.1: QUANTITY (QCount) → GENERATE D1-D5 PER (CATEGORY, N) ---
    if (currentQuestionId == 'M3_1_1_QCount') {
      Map<String, dynamic> counts = {};
      try {
        counts = jsonDecode(answer.toString());
      } catch (_) {}

      final qCountIdx = _questions.indexWhere((q) => q.id == 'M3_1_1_QCount');
      if (qCountIdx != -1) {
        final insertAt = qCountIdx + 1;
        // Remove existing D-questions (idempotent replay)
        while (insertAt < _questions.length && _questions[insertAt].id.startsWith('M3_D')) {
          _questions.removeAt(insertAt);
        }
        final newQuestions = <Question>[];
        for (final entry in counts.entries) {
          final cat = entry.key;
          if (cat == 'none') continue;
          final count = (entry.value as num).toInt();
          if (count <= 0) continue;
          final label = _categoryLabel(cat);
          for (int n = 0; n < count; n++) {
            final suffix = count > 1 ? ' ${n + 1}' : '';
            newQuestions.addAll(_buildDQuestions(cat, n, label, suffix));
          }
        }
        _questions.insertAll(insertAt, newQuestions);
      }
    }

    // --- MODULE 4.2: LANGUAGES (Q1) -> GENERATE LEVEL QUESTIONS (Q2) ---
    if (currentQuestionId == 'M4_2_1_Q1') {
       final languages = parseAnswerList(answer);
       
       final insertionIndex = _questions.indexWhere((q) => q.id == 'M4_2_1_Q1') + 1;
       if (insertionIndex == 0) return;

       // Remove existing Q2 variants
       while (insertionIndex < _questions.length && _questions[insertionIndex].id.startsWith('M4_2_1_Q2')) {
        _questions.removeAt(insertionIndex);
      }
       
       if (languages.isNotEmpty) {
         List<Question> newQuestions = [];
         
         for (int i = 0; i < languages.length; i++) {
           final langName = languages[i].replaceAll(RegExp(r'[^\w\s\u00C0-\u00FF]'), '').trim(); 
           newQuestions.add(Question(
             id: 'M4_2_1_Q2_$i',
             phaseId: 't4_p2',
             type: QuestionType.stepSlider,
             content: 'Qual é o seu nível de conhecimento em $langName?',
             options: ['Básico', 'Intermediário', 'Avançado', 'Fluente'],
           ));
         }
         _questions.insertAll(insertionIndex, newQuestions);
       }
    }
  }

  String _categoryLabel(String cat) => const {
    'stage': 'Estágio/Trainee',
    'emp': 'Emprego',
    'free': 'Freelance',
    'proj': 'Projeto Pessoal',
    'lead': 'Liderança Estudantil',
    'vol': 'Voluntariado',
    'res': 'Pesquisa Acadêmica',
    'spo': 'Esporte',
  }[cat] ?? cat;

  static const _d5Content = {
    'stage': ('Qual foi o resultado mais concreto que você gerou nesse estágio?',
        'Pode ser número, processo criado, problema resolvido, feedback que recebeu.',
        'Ex: Reduzi o tempo de geração de relatórios de 4h para 20min com automação...'),
    'emp':   ('Qual foi o impacto mais concreto do seu trabalho nessa empresa?',
        'Número, meta batida, processo melhorado, equipe desenvolvida.',
        'Ex: Aumentei a satisfação do cliente de 72% para 89% em 6 meses...'),
    'free':  ('O cliente ficou satisfeito? O que mudou depois da sua entrega?',
        'Feedback, repetição, indicação, resultado que o cliente relatou.',
        'Ex: O cliente recomendou para 2 amigos e voltou para um segundo projeto...'),
    'proj':  ('O que o projeto gerou de concreto — uso, aprendizado ou impacto?',
        'Downloads, usuários, aprendizados técnicos, feedbacks recebidos.',
        'Ex: O app teve 200 downloads no primeiro mês e recebi feedback de 3 usuários reais...'),
    'lead':  ('O que mudou na entidade ou no grupo depois da sua liderança?',
        'Crescimento, novos projetos, cultura, reconhecimento externo.',
        'Ex: A liga dobrou de tamanho e foi convidada para representar a faculdade em feira nacional...'),
    'vol':   ('Qual foi o impacto mais concreto do seu voluntariado?',
        'Pessoas impactadas, projetos entregues, mudança que ficou.',
        'Ex: 12 dos 15 alunos passaram no ENEM; o projeto foi replicado em outra escola...'),
    'res':   ('Quais foram os resultados ou conclusões da pesquisa?',
        'Publicações, apresentações, descobertas, continuidade do projeto.',
        'Ex: Artigo submetido para revista Qualis B2; pesquisa citada em TCC de outro aluno...'),
    'spo':   ('Qual foi o maior resultado ou aprendizado do seu percurso esportivo?',
        'Títulos, classificações, habilidades desenvolvidas, disciplina adquirida.',
        'Ex: Conquistei o 2º lugar no estadual e desenvolvi disciplina de treino que uso até hoje...'),
  };

  static const _d4Content = {
    'stage': ('Me conta 2-3 coisas concretas que você fez no estágio.',
        'Tarefas, entregas, projetos que tocou. Pode ser desorganizado, eu organizo depois.',
        'Ex: Automatizei relatórios em Python; participei de reuniões com clientes; atualizei o CRM...'),
    'emp':   ('Me conta 2-3 coisas concretas que você fez nesse trabalho.',
        'Responsabilidades, entregas, processos que você tocou ou criou.',
        'Ex: Gerenciei carteira de 50 clientes; criei o SOP de atendimento; treinei 3 funcionários...'),
    'free':  ('Me conta o que você entregou nesse projeto.',
        'O que foi criado ou executado, quanto tempo levou, quais ferramentas usou.',
        'Ex: Criei logo, cartão e paleta de cores; entreguei em 2 semanas com 3 rodadas de revisão...'),
    'proj':  ('Me conta o que você desenvolveu ou construiu nesse projeto.',
        'Funcionalidades, versões, o que você criou do zero ou melhorou.',
        'Ex: Desenvolvi o backend em Node.js; criei 5 telas no Figma; publiquei com 200 downloads...'),
    'lead':  ('Me conta 2-3 coisas concretas que você liderou ou organizou.',
        'Eventos, projetos, decisões, membros gerenciados. Pode ser desorganizado.',
        'Ex: Organizei evento com 300 pessoas; recrutei 10 membros; criei o planejamento anual...'),
    'vol':   ('Me conta 2-3 coisas concretas que você fez no voluntariado.',
        'Atividades, pessoas impactadas, projetos que você tocou.',
        'Ex: Dei aulas de reforço para 15 alunos; organizei arrecadação; criei material didático...'),
    'res':   ('Me conta 2-3 coisas concretas que você fez na pesquisa.',
        'Coleta de dados, análises, artigos, apresentações — sua contribuição real.',
        'Ex: Coletei dados de 80 municípios; rodei regressões em R; apresentei em congresso da área...'),
    'spo':   ('Me conta 2-3 conquistas ou atividades concretas do seu percurso esportivo.',
        'Campeonatos, treinos, liderança em equipe, resultados que alcançou.',
        'Ex: Fui campeão estadual sub-18; treinei 6x por semana; capitão do time por 2 temporadas...'),
  };

  static const _d3Content = {
    'stage': ('Como você entrou nesse estágio e o que esperavam de você?',
        'O processo seletivo, por que te escolheram, quais eram as expectativas iniciais.',
        'Ex: Fui selecionado entre 200 candidatos para atuar em dados, com foco em automação...'),
    'emp':   ('Como você foi contratado e qual era sua missão no cargo?',
        'O contexto da contratação e o problema que você foi resolver.',
        'Ex: Fui contratado para estruturar o atendimento que recebia 100+ reclamações por semana...'),
    'free':  ('Por que o cliente te contratou ou como surgiu esse projeto?',
        'O problema que ele queria resolver e por que escolheu você.',
        'Ex: O cliente precisava de identidade visual para lançar sua marca em 30 dias...'),
    'proj':  ('Por que você criou isso? Qual problema queria resolver?',
        'A motivação, o problema que existia, o que te fez começar.',
        'Ex: Criei porque não encontrava uma ferramenta simples para controlar gastos variáveis...'),
    'lead':  ('Como você entrou nessa liderança e qual era o desafio inicial?',
        'O processo de seleção ou fundação, e o que precisava ser feito.',
        'Ex: Fui eleito presidente para reformular o modelo de eventos que estava estagnado...'),
    'vol':   ('Por que você escolheu esse voluntariado e qual era sua função?',
        'A motivação pessoal e o papel que você assumiu na organização.',
        'Ex: Escolhi porque acredito em educação como transformação e assumi a coordenação de turmas...'),
    'res':   ('Como surgiu esse projeto de pesquisa e qual era a hipótese?',
        'O orientador, o problema científico, a pergunta que vocês queriam responder.',
        'Ex: Entrei como bolsista para investigar se microcrédito reduz informalidade em pequenos municípios...'),
    'spo':   ('Como você chegou nesse nível e o que te motivava a continuar?',
        'O início da trajetória, os treinamentos e a dedicação por trás dos resultados.',
        'Ex: Comecei aos 12 anos e fui convocado para o estadual aos 16 após treino intensivo...'),
  };

  static const _d2Content = {
    'stage': ('Em poucas palavras, o que essa empresa faz?',
        'Recrutador pode não conhecer. Em 1-2 frases, ajude ele a entender.',
        'Ex: Startup de pagamentos B2B que atende pequenas varejistas...'),
    'emp':   ('Em poucas palavras, o que essa empresa faz?',
        'Recrutador pode não conhecer. Em 1-2 frases, ajude ele a entender.',
        'Ex: Empresa de consultoria de RH com 200+ clientes corporativos...'),
    'free':  ('Em poucas palavras, qual era o projeto ou cliente?',
        'Descreva o contexto: tipo de cliente, nicho ou produto que você entregou.',
        'Ex: Prestei serviço de design gráfico para 3 marcas locais de moda...'),
    'proj':  ('Em poucas palavras, qual era o projeto e para quem?',
        'Descreva a ideia e o público: quem usaria ou se beneficiaria disso.',
        'Ex: App de controle financeiro pessoal que criei para aprender Flutter...'),
    'lead':  ('Em poucas palavras, o que essa entidade faz?',
        'Recrutador pode não conhecer. Em 1-2 frases, ajude ele a entender.',
        'Ex: Liga acadêmica de finanças que conecta estudantes de Administração...'),
    'vol':   ('Em poucas palavras, qual é a missão dessa organização?',
        'Recrutador pode não conhecer. Em 1-2 frases, ajude ele a entender.',
        'Ex: ONG que ensina programação para jovens de periferia em SP...'),
    'res':   ('Em poucas palavras, qual era o tema da pesquisa?',
        'Descreva o problema estudado e o contexto acadêmico.',
        'Ex: Pesquisa sobre impacto de políticas públicas na renda de MEIs...'),
    'spo':   ('Em poucas palavras, qual era o contexto do esporte?',
        'Descreva o nível, a equipe ou a competição em que você participava.',
        'Ex: Jogava tênis em nível estadual, treinando 5x por semana em clube...'),
  };

  List<Question> _buildDQuestions(String cat, int n, String label, String suffix) {
    final d2 = _d2Content[cat] ?? (
      'Em poucas palavras, o que essa experiência envolvia?',
      'Recrutador pode não conhecer. Em 1-2 frases, ajude ele a entender.',
      'Ex: Organização voltada para...',
    );
    final d3 = _d3Content[cat] ?? (
      'Por que você foi escolhido pra isso, ou por que você criou isso?',
      'A intenção, o problema que existia, a expectativa quando você começou.',
      'Ex: Fui chamado para estruturar a área que ainda não existia...',
    );
    final d5 = _d5Content[cat] ?? (
      'Olhando para trás, o que ficou diferente depois que você passou por aí?',
      'Pode ser número, problema resolvido, processo criado. Não precisa ser quantificado.',
      'Ex: A área passou a publicar relatórios mensais que viraram referência...',
    );
    final d4 = _d4Content[cat] ?? (
      'Me conta 2-3 coisas concretas que você fez.',
      'Foque em ações específicas: o que você criou, organizou, executou, mudou.',
      'Ex: Criei um modelo de análise em Excel para 30+ empresas; entrevistei 5 gestores...',
    );
    return [
    Question(
      id: 'M3_D1_${cat}_$n', phaseId: 't3_p1',
      type: QuestionType.experienceDetailForm,
      content: 'Me conta os detalhes do seu $label$suffix:',
      options: [cat],
    ),
    Question(
      id: 'M3_D2_${cat}_$n', phaseId: 't3_p1',
      type: QuestionType.text,
      content: d2.$1,
      options: [d2.$2, d2.$3],
    ),
    Question(
      id: 'M3_D3_${cat}_$n', phaseId: 't3_p1',
      type: QuestionType.text,
      content: d3.$1,
      options: [d3.$2, d3.$3],
    ),
    Question(
      id: 'M3_D4_${cat}_$n', phaseId: 't3_p1',
      type: QuestionType.text,
      content: d4.$1,
      options: [d4.$2, d4.$3],
    ),
    Question(
      id: 'M3_D5_${cat}_$n', phaseId: 't3_p1',
      type: QuestionType.text,
      content: d5.$1,
      options: [d5.$2, d5.$3],
    ),
    // D6 — explicit metric question (Harvard "fact-based" rule).
    // Optional, but when answered it lets the AI bake the number into the
    // bullet ("200+ membros", "1000 downloads", etc.).
    Question(
      id: 'M3_D6_${cat}_$n', phaseId: 't3_p1',
      type: QuestionType.text,
      content: 'Tem números concretos pra incluir?',
      options: [
        'Quantas pessoas envolvidas, quanto cresceu, ranking, downloads, prazo, ROI? Pode pular se não tiver.',
        'Ex: liderei 8 trainees; alcancei 1000 downloads; 200+ participantes; melhorou em 30%',
      ],
    ),
  ];}

  Future<void> _finishPhase() async {
    // Phase 5: after t5_p2 (last M5 phase), trigger summary generation before completion
    final lastPhaseId = _questions.isNotEmpty ? _questions.first.phaseId : '';
    if (lastPhaseId == 't5_p2') {
      _pendingSummaryGeneration = true;
      notifyListeners();
      return; // SummaryGenerationScreen calls completePhasAfterSummary()
    }

    _isPhaseCompleted = true;
    notifyListeners();
  }

  /// Called by SummaryGenerationScreen after the summary is approved/skipped.
  Future<void> completePhaseAfterSummary() async {
    _pendingSummaryGeneration = false;
    _isPhaseCompleted = true;
    notifyListeners();
  }

  Future<void> saveProgress(String phaseId) async {
    try {
      await _repository.markPhaseCompleted(phaseId);
      Analytics.shared.trackPhaseCompleted(
        phaseId: phaseId,
        xpEarned: 50 + (_questions.length * 10),
      );

      final user = await _repository.getUserProfile();
      if (user != null) {
        Map<String, dynamic> updatedGamificationData = Map.from(user.gamificationData);

        if (phaseId.startsWith('t1_')) {
          final allAnswers = await _getAllAnswers();
          final module1Data = GamificationLogic.processModule1Answers(allAnswers);
          if (module1Data['traits'].isNotEmpty) {
            updatedGamificationData['whoIAm'] = {
              'derived': module1Data,
              'last_updated': DateTime.now().toIso8601String(),
            };
          }
        }

        if (phaseId.startsWith('t2_')) {
          final allAnswers = await _getAllAnswers();
          final module2Data = GamificationLogic.processModule2Answers(allAnswers);
          updatedGamificationData['module2'] = {
            'myBase': module2Data,
            'last_updated': DateTime.now().toIso8601String(),
          };
        }

        if (phaseId.startsWith('t3_')) {
          final allAnswers = await _getAllAnswers();
          final module3Data = GamificationLogic.processModule3Answers(allAnswers);
          updatedGamificationData['module3'] = {
            'experiences_and_courses': module3Data,
            'last_updated': DateTime.now().toIso8601String(),
          };
        }

        if (updatedGamificationData.isNotEmpty) {
          final updatedProfile = user.copyWith(
            gamificationData: updatedGamificationData,
          );
          await _repository.updateUserProfile(updatedProfile);
        }
      }

      _completedPhaseIds = await _repository.getCompletedPhaseIds();
      await _loadGlobalProgress();
      notifyListeners();
    } catch (e) {
      print('Error saving progress: $e');
      rethrow;
    }
  }
}
