import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/models.dart';
import '../../data/supabase_repository.dart';
import '../../data/supabase_repository.dart';
import '../../services/ai_service.dart';
import 'gamification_logic.dart';

enum PhaseStatus { locked, available, completed }

class GamificationViewModel extends ChangeNotifier {
  final SupabaseRepository _repository;
  final AIService _aiService = AIService();
  
  // ... (existing code)

  // ============================================
  // INTERVIEW REPORT
  // ============================================

  Future<Map<String, String>> getAnswersForTrack(String trackId) async {
    // For the Secret World report, we actually want context from ALL tracks 
    // (background, values, etc.) to give a better analysis.
    // So we fetch all user answers.
    return await _repository.getUserAnswersWithQuestions();
  }

  Future<InterviewReport> generateInterviewReport(Map<String, String> answers) async {
    try {
      return await _aiService.generateInterviewReport(answers);
    } catch (e) {
      print('Error generating interview report in ViewModel: $e');
      rethrow;
    }
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
  int _earnedXp = 0;

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
      
      // FIRE & FORGET CLEANUP
      _cleanupObsoleteData();
      
      notifyListeners();
    } catch (e) {
      print('Error loading completed phases: $e');
    }
  }

  Future<void> _cleanupObsoleteData() async {
    // Cleanup questions the user explicitly asked to remove
    await _repository.deleteQuestionsByContent("qual era a sua função");
    await _repository.deleteQuestionsByContent("Onde essa experiência aconteceu");
    // Force reload of questions next time
    _repository.clearCache();
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
    _earnedXp = 0;
    notifyListeners();
  }

  List<Phase> get phases => _phases;
  bool get isLoadingPhases => _isLoadingPhases;
  
  List<Question> get questions => _questions;
  Question? get currentQuestion => _questions.isNotEmpty && _currentQuestionIndex < _questions.length ? _questions[_currentQuestionIndex] : null;
  bool get isLoadingQuestions => _isLoadingQuestions;
  bool get isCurrentPhaseFinished => _isPhaseCompleted;
  int get earnedXp => _earnedXp;
  int get currentQuestionIndex => _currentQuestionIndex;
  double get progress => _questions.isEmpty ? 0 : (_currentQuestionIndex / _questions.length);

  // Global Progress
  double _totalCareerProgress = 0.0;
  double get totalCareerProgress => _totalCareerProgress;


  Future<void> _loadGlobalProgress() async {
    try {
      final totalPhases = await _repository.getTotalPhaseCount();
      final completedCount = _completedPhaseIds.length;
      
      if (totalPhases > 0) {
        _totalCareerProgress = completedCount / totalPhases;
      } else {
        _totalCareerProgress = 0.0;
      }
      notifyListeners();
    } catch (e) {
      print('Error loading global progress: $e');
    }
  }

  // Load Phases for a Track
  Future<void> loadPhases(String trackId) async {
    _isLoadingPhases = true;
    notifyListeners();
    try {
      _repository.clearCache(); // Force fresh data when switching worlds
      final allPhases = await _repository.getPhases(trackId);
      // HARD FILTER: Remove obsolete phase by ID OR Title
      _phases = allPhases.where((p) => 
        p.id != 't1_p4' && 
        p.title != 'Revisão' &&
        p.title != 'O Cronômetro da Jornada' &&
        p.title != 'O que você fez'
      ).toList();
      _completedPhaseIds = await _repository.getCompletedPhaseIds();
    } catch (e) {
      print('Error loading phases: $e');
    } finally {
      _isLoadingPhases = false;
      notifyListeners();
    }
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
    _isLoadingQuestions = true;
    _currentQuestionIndex = 0;
    _answers = {};
    _isPhaseCompleted = false;
    _earnedXp = 0;
    notifyListeners();
    
    try {
      final fetchedQuestions = await _repository.getQuestions(phaseId);
      // HARD FILTER: Remove persistent unwanted questions & Strip Emojis from options
      _questions = fetchedQuestions.where((q) {
        final content = q.content.toLowerCase();
        return !content.contains("qual era a sua função") &&
               !content.contains("onde essa experiência aconteceu");
      }).map((q) {
        // Strip emojis from options for a cleaner look
        final sanitizedOptions = q.options.map((opt) {
          return opt.replaceAll(RegExp(r'[\u{1f300}-\u{1f5ff}\u{1f600}-\u{1f64f}\u{1f680}-\u{1f6ff}\u{1f1e6}-\u{1f1ff}\u{2600}-\u{26ff}\u{2700}-\u{27bf}\u{1f900}-\u{1f9ff}\u{1f018}-\u{1f270}\u{1f300}-\u{1f5ff}\u{1f900}-\u{1f9ff}\u{1f600}-\u{1f64f}\u{1f680}-\u{1f6ff}\u{1f1e6}-\u{1f1ff}]', unicode: true), '').trim();
        }).toList();
        
        return Question(
          id: q.id,
          phaseId: q.phaseId,
          type: q.type,
          content: q.content,
          options: sanitizedOptions,
        );
      }).toList();
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

      await _repository.saveAnswer(
        currentQ.id,
        answer is List ? answer.join(',') : answer.toString(),
      );
    } catch (e) {
      print('Error saving answer: $e');
    }

    // --- Dynamic Question Generation Logic ---
    _handleDynamicQuestionGeneration(currentQ.id, answer);
    
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

    // --- MODULE 3.1: EXPERIENCE TYPE (Q1) -> GENERATE FORMS (Q2+) ---
    if (currentQuestionId == 'M3_1_1_Q1') {
       final experiences = parseAnswerList(answer);
       // Filter out NO_EXPERIENCE, none, and 'other' (which is handled via custom dialog)
       final validExperiences = experiences.where((e) => 
           e != 'NO_EXPERIENCE' && 
           e != 'none' && 
           !e.contains('"id": "none"') &&
           !e.contains('"id": "other"')
       ).toList();

       final q1Index = _questions.indexWhere((q) => q.id == 'M3_1_1_Q1');
       if (q1Index != -1) {
          final insertionIndex = q1Index + 1;
          
          // Remove existing M3_1_1_Q2 variants (including static one)
          while (insertionIndex < _questions.length && _questions[insertionIndex].id.startsWith('M3_1_1_Q2')) {
            _questions.removeAt(insertionIndex);
          }

          if (validExperiences.isNotEmpty) {
             List<Question> newQuestions = [];
             for (int i = 0; i < validExperiences.length; i++) {
                final expStr = validExperiences[i];
                newQuestions.add(Question(
                   id: 'M3_1_1_Q2_$i',
                   phaseId: 't3_p1',
                   type: QuestionType.experienceForm,
                   content: 'Conte mais sobre essa experiência!', 
                   options: [expStr], // Pass context
                ));
             }
             _questions.insertAll(insertionIndex, newQuestions);
          }
       }
    }

    // --- MODULE 4.1: TOOLS LIST (Q2) -> GENERATE LEVEL QUESTIONS (Q3) ---
    if (currentQuestionId == 'M4_1_1_Q2') {
      final tools = parseAnswerList(answer);
      
      // 1. Find insertion point (Index of Q2 + 1)
      final insertionIndex = _questions.indexWhere((q) => q.id == 'M4_1_1_Q2') + 1;
      if (insertionIndex == 0) return; // Should not happen if we are processing Q2

      // 2. Remove any previously generated Q3 variants (id starts with M4_1_1_Q3)
      // We look ahead from insertion point until we hit something else
      while (insertionIndex < _questions.length && _questions[insertionIndex].id.startsWith('M4_1_1_Q3')) {
        _questions.removeAt(insertionIndex);
      }

      // 3. Generate New Questions
      if (tools.isNotEmpty) {
        List<Question> newQuestions = [];
        for (int i = 0; i < tools.length; i++) {
          final toolName = tools[i];
          newQuestions.add(Question(
            id: 'M4_1_1_Q3_$i',
            phaseId: 't4_p1',
            type: QuestionType.stepSlider,
            content: 'Qual o seu nível de domínio em $toolName?',
            options: ['Básico', 'Intermediário', 'Avançado'],
          ));
        }
        _questions.insertAll(insertionIndex, newQuestions);
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

  Future<void> _finishPhase() async {
    _isPhaseCompleted = true;
    
    // Calculate XP
    _earnedXp = 50 + (_questions.length * 10);
    
    notifyListeners();
  }
  
  Future<void> saveProgress(String phaseId) async {
    try {
      // Mark phase as completed
      await _repository.markPhaseCompleted(phaseId, _earnedXp);
      
      // Update user XP
      final user = await _repository.getUserProfile();
      if (user != null) {
        final newXp = user.xp + _earnedXp;
        final newLevel = (newXp / 500).floor() + 1;
        
        // --- ADDED: Check if this is the end of Module 1 or a specific phase ---
        Map<String, dynamic> updatedGamificationData = Map.from(user.gamificationData);
        
        // MODULE 1 PROCESSING
        if (phaseId.startsWith('t1_')) {
          final allAnswers = await getAnswersForTrack('track_1');
          final module1Data = GamificationLogic.processModule1Answers(allAnswers);
          
          if (module1Data['traits'].isNotEmpty) {
             updatedGamificationData['whoIAm'] = {
               'derived': module1Data,
               'last_updated': DateTime.now().toIso8601String(),
             };
          }
        }
        
        // MODULE 2 PROCESSING
        if (phaseId.startsWith('t2_')) {
          final allAnswers = await getAnswersForTrack('track_2');
          final module2Data = GamificationLogic.processModule2Answers(allAnswers);
          
          // Merge derived data
          updatedGamificationData['module2'] = {
            'myBase': module2Data,
            'last_updated': DateTime.now().toIso8601String(),
          };
        }

        // MODULE 3 PROCESSING
        if (phaseId.startsWith('t3_')) {
          final allAnswers = await getAnswersForTrack('track_3');
          final module3Data = GamificationLogic.processModule3Answers(allAnswers);
          
          updatedGamificationData['module3'] = {
            'experiences_and_courses': module3Data,
            'last_updated': DateTime.now().toIso8601String(),
          };
        }

        await _repository.updateUserXP(user.id!, newXp, newLevel);
        
        // Update profile with extracted data
        if (updatedGamificationData.isNotEmpty) {
           final updatedProfile = user.copyWith(
             xp: newXp,
             level: newLevel,
             gamificationData: updatedGamificationData,
           );
           await _repository.updateUserProfile(updatedProfile);
        }
      }


      // Refresh completed phase IDs to update UI
      _completedPhaseIds = await _repository.getCompletedPhaseIds();
      notifyListeners();
    } catch (e) {
      print('Error saving progress: $e');
      rethrow;
    }
  }
}
