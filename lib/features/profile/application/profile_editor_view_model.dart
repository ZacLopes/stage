// ProfileEditorViewModel — gerencia perfil estruturado completo do user logado.
//
// Padrão:
//   - load() carrega todas as seções no boot da tela de edição
//   - upsert/add/update/delete por seção fazem optimistic update + save em background
//   - autosave debounced (800ms) pra campos free-text (PersonalInfo)
//   - status global: idle / saving / saved / error
//
// O ViewModel não conhece UI — apenas exibe estado via getters reativos.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/entities/entities.dart';
import '../domain/repositories/profile_repository.dart';

enum SaveStatus { idle, saving, saved, error }

class ProfileEditorViewModel extends ChangeNotifier {
  final ProfileRepository _repo;

  // ──────────────────────────────────────────────────────────────────────
  // State
  // ──────────────────────────────────────────────────────────────────────

  PersonalInfo? _personal;
  List<Experience> _experiences = [];
  List<Education> _education = [];
  List<Language> _languages = [];
  List<Skill> _skills = [];
  List<Certification> _certifications = [];
  List<Project> _projects = [];
  List<Interest> _interests = [];
  List<Award> _awards = [];

  bool _isLoading = false;
  SaveStatus _saveStatus = SaveStatus.idle;
  String? _lastError;
  Timer? _personalDebounce;

  // Getters reativos
  PersonalInfo? get personal => _personal;
  List<Experience> get experiences => List.unmodifiable(_experiences);
  List<Education> get education => List.unmodifiable(_education);
  List<Language> get languages => List.unmodifiable(_languages);
  List<Skill> get skills => List.unmodifiable(_skills);
  List<Certification> get certifications => List.unmodifiable(_certifications);
  List<Project> get projects => List.unmodifiable(_projects);
  List<Interest> get interests => List.unmodifiable(_interests);
  List<Award> get awards => List.unmodifiable(_awards);
  bool get isLoading => _isLoading;
  SaveStatus get saveStatus => _saveStatus;
  String? get lastError => _lastError;

  int get completenessScore => _personal?.completenessScore ?? 0;
  bool get hasPersonal => _personal != null;
  bool get isEmpty =>
      _personal == null &&
      _experiences.isEmpty &&
      _education.isEmpty &&
      _skills.isEmpty;

  ProfileEditorViewModel(this._repo) {
    // Auto-load quando user troca de sessão
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final ev = data.event;
      if (ev == AuthChangeEvent.signedIn) {
        load();
      } else if (ev == AuthChangeEvent.signedOut) {
        _clear();
      }
    });
  }

  // ──────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────────────────

  Future<void> load() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      _clear();
      return;
    }

    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      // Carrega tudo em paralelo
      final results = await Future.wait([
        _repo.getPersonal(userId),
        _repo.getExperiences(userId),
        _repo.getEducation(userId),
        _repo.getLanguages(userId),
        _repo.getSkills(userId),
        _repo.getCertifications(userId),
        _repo.getProjects(userId),
        _repo.getInterests(userId),
        _repo.getAwards(userId),
      ]);

      _personal = results[0] as PersonalInfo?;
      _experiences = results[1] as List<Experience>;
      _education = results[2] as List<Education>;
      _languages = results[3] as List<Language>;
      _skills = results[4] as List<Skill>;
      _certifications = results[5] as List<Certification>;
      _projects = results[6] as List<Project>;
      _interests = results[7] as List<Interest>;
      _awards = results[8] as List<Award>;
    } catch (e) {
      _lastError = 'Erro ao carregar perfil: $e';
      debugPrint('[ProfileEditorViewModel] load error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _clear() {
    _personal = null;
    _experiences = [];
    _education = [];
    _languages = [];
    _skills = [];
    _certifications = [];
    _projects = [];
    _interests = [];
    _awards = [];
    _saveStatus = SaveStatus.idle;
    _lastError = null;
    notifyListeners();
  }

  // ──────────────────────────────────────────────────────────────────────
  // PersonalInfo (autosave debounced 800ms — campos free-text)
  // ──────────────────────────────────────────────────────────────────────

  void updatePersonalDraft(PersonalInfo draft) {
    // Optimistic
    _personal = draft;
    notifyListeners();

    _personalDebounce?.cancel();
    _personalDebounce = Timer(const Duration(milliseconds: 800), () {
      _savePersonal(draft);
    });
  }

  Future<void> _savePersonal(PersonalInfo info) async {
    _setSaving();
    try {
      final saved = await _repo.upsertPersonal(info);
      _personal = saved;
      _setSaved();
    } catch (e) {
      _setError('Erro ao salvar informações: $e');
    }
  }

  /// Force-save sem debounce (use ao tocar "Continue" no onboarding)
  Future<void> commitPersonal(PersonalInfo info) async {
    _personalDebounce?.cancel();
    await _savePersonal(info);
  }

  // ──────────────────────────────────────────────────────────────────────
  // Experiences (CRUD com optimistic)
  // ──────────────────────────────────────────────────────────────────────

  Future<void> addExperience(Experience exp) async {
    _setSaving();
    try {
      final saved = await _repo.addExperience(exp);
      _experiences = [..._experiences, saved];
      _setSaved();
    } catch (e) {
      _setError('Erro ao adicionar experiência: $e');
    }
  }

  Future<void> updateExperience(Experience exp) async {
    // Optimistic
    _experiences = _experiences.map((e) => e.id == exp.id ? exp : e).toList();
    notifyListeners();

    _setSaving();
    try {
      await _repo.updateExperience(exp);
      _setSaved();
    } catch (e) {
      _setError('Erro ao atualizar experiência: $e');
    }
  }

  Future<void> deleteExperience(String id) async {
    final original = _experiences;
    _experiences = _experiences.where((e) => e.id != id).toList();
    notifyListeners();

    _setSaving();
    try {
      await _repo.deleteExperience(id);
      _setSaved();
    } catch (e) {
      _experiences = original;
      _setError('Erro ao deletar experiência: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Education
  // ──────────────────────────────────────────────────────────────────────

  Future<void> addEducation(Education edu) async {
    _setSaving();
    try {
      final saved = await _repo.addEducation(edu);
      _education = [..._education, saved];
      _setSaved();
    } catch (e) {
      _setError('Erro ao adicionar formação: $e');
    }
  }

  Future<void> updateEducation(Education edu) async {
    _education = _education.map((e) => e.id == edu.id ? edu : e).toList();
    notifyListeners();
    _setSaving();
    try {
      await _repo.updateEducation(edu);
      _setSaved();
    } catch (e) {
      _setError('Erro ao atualizar formação: $e');
    }
  }

  Future<void> deleteEducation(String id) async {
    final original = _education;
    _education = _education.where((e) => e.id != id).toList();
    notifyListeners();
    _setSaving();
    try {
      await _repo.deleteEducation(id);
      _setSaved();
    } catch (e) {
      _education = original;
      _setError('Erro ao deletar formação: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Languages
  // ──────────────────────────────────────────────────────────────────────

  Future<void> addLanguage(Language lang) async {
    _setSaving();
    try {
      final saved = await _repo.addLanguage(lang);
      _languages = [..._languages, saved];
      _setSaved();
    } catch (e) {
      _setError('Erro ao adicionar idioma: $e');
    }
  }

  Future<void> updateLanguage(Language lang) async {
    _languages = _languages.map((l) => l.id == lang.id ? lang : l).toList();
    notifyListeners();
    _setSaving();
    try {
      await _repo.updateLanguage(lang);
      _setSaved();
    } catch (e) {
      _setError('Erro ao atualizar idioma: $e');
    }
  }

  Future<void> deleteLanguage(String id) async {
    final original = _languages;
    _languages = _languages.where((l) => l.id != id).toList();
    notifyListeners();
    _setSaving();
    try {
      await _repo.deleteLanguage(id);
      _setSaved();
    } catch (e) {
      _languages = original;
      _setError('Erro ao deletar idioma: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Skills, Interests, Coursework — replace em massa via EditListModal
  // ──────────────────────────────────────────────────────────────────────

  Future<void> replaceSkills(List<String> names) async {
    final userId = _personal?.userId ?? Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final original = _skills;
    _skills = names.asMap().entries
        .map((e) => Skill(id: 'temp_${e.key}', userId: userId, name: e.value, orderIndex: e.key))
        .toList();
    notifyListeners();
    _setSaving();
    try {
      await _repo.replaceSkills(userId, names);
      _skills = await _repo.getSkills(userId);
      _setSaved();
    } catch (e) {
      _skills = original;
      _setError('Erro ao salvar skills: $e');
    }
  }

  Future<void> replaceInterests(List<String> names) async {
    final userId = _personal?.userId ?? Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final original = _interests;
    _interests = names.asMap().entries
        .map((e) => Interest(id: 'temp_${e.key}', userId: userId, name: e.value, orderIndex: e.key))
        .toList();
    notifyListeners();
    _setSaving();
    try {
      await _repo.replaceInterests(userId, names);
      _interests = await _repo.getInterests(userId);
      _setSaved();
    } catch (e) {
      _interests = original;
      _setError('Erro ao salvar interesses: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Certifications, Projects, Awards — CRUD individual
  // ──────────────────────────────────────────────────────────────────────

  Future<void> addCertification(Certification c) async {
    _setSaving();
    try {
      _certifications = [..._certifications, await _repo.addCertification(c)];
      _setSaved();
    } catch (e) {
      _setError('Erro: $e');
    }
  }

  Future<void> updateCertification(Certification c) async {
    _certifications = _certifications.map((x) => x.id == c.id ? c : x).toList();
    notifyListeners();
    _setSaving();
    try {
      await _repo.updateCertification(c);
      _setSaved();
    } catch (e) {
      _setError('Erro: $e');
    }
  }

  Future<void> deleteCertification(String id) async {
    final original = _certifications;
    _certifications = _certifications.where((c) => c.id != id).toList();
    notifyListeners();
    _setSaving();
    try {
      await _repo.deleteCertification(id);
      _setSaved();
    } catch (e) {
      _certifications = original;
      _setError('Erro: $e');
    }
  }

  Future<void> addProject(Project p) async {
    _setSaving();
    try {
      _projects = [..._projects, await _repo.addProject(p)];
      _setSaved();
    } catch (e) {
      _setError('Erro: $e');
    }
  }

  Future<void> updateProject(Project p) async {
    _projects = _projects.map((x) => x.id == p.id ? p : x).toList();
    notifyListeners();
    _setSaving();
    try {
      final updated = await _repo.updateProject(p);
      _projects = _projects.map((x) => x.id == updated.id ? updated : x).toList();
      _setSaved();
    } catch (e) {
      _setError('Erro: $e');
    }
  }

  Future<void> deleteProject(String id) async {
    final original = _projects;
    _projects = _projects.where((p) => p.id != id).toList();
    notifyListeners();
    _setSaving();
    try {
      await _repo.deleteProject(id);
      _setSaved();
    } catch (e) {
      _projects = original;
      _setError('Erro: $e');
    }
  }

  Future<void> addAward(Award a) async {
    _setSaving();
    try {
      _awards = [..._awards, await _repo.addAward(a)];
      _setSaved();
    } catch (e) {
      _setError('Erro: $e');
    }
  }

  Future<void> updateAward(Award a) async {
    _awards = _awards.map((x) => x.id == a.id ? a : x).toList();
    notifyListeners();
    _setSaving();
    try {
      await _repo.updateAward(a);
      _setSaved();
    } catch (e) {
      _setError('Erro: $e');
    }
  }

  Future<void> deleteAward(String id) async {
    final original = _awards;
    _awards = _awards.where((a) => a.id != id).toList();
    notifyListeners();
    _setSaving();
    try {
      await _repo.deleteAward(id);
      _setSaved();
    } catch (e) {
      _awards = original;
      _setError('Erro: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Status helpers
  // ──────────────────────────────────────────────────────────────────────

  void _setSaving() {
    _saveStatus = SaveStatus.saving;
    _lastError = null;
    notifyListeners();
  }

  void _setSaved() {
    _saveStatus = SaveStatus.saved;
    notifyListeners();
    // Volta pra idle após 2s
    Timer(const Duration(seconds: 2), () {
      if (_saveStatus == SaveStatus.saved) {
        _saveStatus = SaveStatus.idle;
        notifyListeners();
      }
    });
  }

  void _setError(String msg) {
    _saveStatus = SaveStatus.error;
    _lastError = msg;
    debugPrint('[ProfileEditorViewModel] $msg');
    notifyListeners();
  }

  @override
  void dispose() {
    _personalDebounce?.cancel();
    super.dispose();
  }
}
