// PreferencesViewModel — gerencia JobPreferences + DesiredTitles +
// ApplicationCountries + OtherLocations. Usado nas 8 telas de preferências
// do onboarding novo e na edição futura via aba Perfil.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/profile_events.dart';
import '../../trilha/application/area_canonical.dart';
import '../domain/entities/entities.dart';
import '../domain/repositories/profile_repository.dart';
import 'profile_editor_view_model.dart' show SaveStatus;

class PreferencesViewModel extends ChangeNotifier {
  final ProfileRepository _repo;

  JobPreferences? _prefs;
  List<DesiredTitle> _desiredTitles = [];
  List<OtherLocation> _otherLocations = [];

  bool _isLoading = false;
  SaveStatus _saveStatus = SaveStatus.idle;
  String? _lastError;

  JobPreferences? get prefs => _prefs;
  // Esconde a canônica oculta ('inferred', mapeada de áreas custom) — o usuário
  // só vê as áreas que ele escolheu. Os readers (match/feed/admin) leem a tabela
  // direto, então continuam enxergando as 'inferred'. Fase 7 · +10 (Tarefa 2).
  List<DesiredTitle> get desiredTitles => List.unmodifiable(
      _desiredTitles.where((t) => t.source != DesiredTitleSource.inferred));
  List<OtherLocation> get otherLocations => List.unmodifiable(_otherLocations);
  bool get isLoading => _isLoading;
  SaveStatus get saveStatus => _saveStatus;
  String? get lastError => _lastError;

  PreferencesViewModel(this._repo) {
    // Limpa o estado quando o user faz signOut ou delete account — sem
    // isso, o singleton Provider mantém `_desiredTitles` em memória da
    // sessão anterior e a próxima conta vê seleções alheias (bug
    // observado: criar conta nova mostra "Tecnologia" pré-marcada na
    // DesiredTitlesScreen porque a conta deletada tinha selecionado).
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedOut) {
        _clear();
      }
    });
  }

  void _clear() {
    _prefs = null;
    _desiredTitles = [];
    _otherLocations = [];
    _isLoading = false;
    _saveStatus = SaveStatus.idle;
    _lastError = null;
    notifyListeners();
  }

  Future<void> load() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    _isLoading = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        _repo.getJobPreferences(userId),
        _repo.getDesiredTitles(userId),
        _repo.getOtherLocations(userId),
      ]);
      _prefs = results[0] as JobPreferences?;
      _desiredTitles = results[1] as List<DesiredTitle>;
      _otherLocations = results[2] as List<OtherLocation>;
    } catch (e) {
      _lastError = 'Erro ao carregar preferências: $e';
      debugPrint('[PreferencesViewModel] load: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> upsertPrefs(JobPreferences prefs) async {
    if (prefs.userId.isEmpty) {
      const message = 'Usuário não autenticado.';
      _error(message);
      throw StateError(message);
    }
    _prefs = prefs;
    notifyListeners();
    _saving();
    try {
      _prefs = await _repo.upsertJobPreferences(prefs);
      _saved();
    } catch (e) {
      _error('Erro ao salvar preferências: $e');
      rethrow;
    }
  }

  /// Atualiza só `work_mode`, mantém resto.
  Future<void> setWorkMode(List<WorkMode> modes) async {
    final current = _prefs ?? _emptyPrefs();
    await upsertPrefs(current.copyWith(workMode: modes));
  }

  Future<void> setJobTypes(List<JobType> types) async {
    final current = _prefs ?? _emptyPrefs();
    await upsertPrefs(current.copyWith(jobTypes: types));
  }

  /// Fase 3 — cargo desejado (texto; vazio limpa via a flag do copyWith).
  Future<void> setDesiredPosition(String? position) async {
    final current = _prefs ?? _emptyPrefs();
    final v = (position ?? '').trim();
    await upsertPrefs(v.isEmpty
        ? current.copyWith(clearDesiredPosition: true)
        : current.copyWith(desiredPosition: v));
  }

  /// Fase 3 — senioridade (lista de níveis; vazia limpa).
  Future<void> setExperienceLevel(List<ExperienceLevel> levels) async {
    final current = _prefs ?? _emptyPrefs();
    await upsertPrefs(current.copyWith(experienceLevel: levels));
  }

  /// Fase 3 — fit cultural (ids das opções; só o que vier não-nulo é atualizado).
  Future<void> setCulturalFit({
    String? companyStage,
    String? workEnvironment,
    String? workStyle,
  }) async {
    final current = _prefs ?? _emptyPrefs();
    await upsertPrefs(current.copyWith(
      companyStage: companyStage,
      workEnvironment: workEnvironment,
      workStyle: workStyle,
    ));
  }

  Future<void> setPrimaryLocation({
    String? country,
    String? state,
    String? city,
    String? postalCode,
    double? lat,
    double? lng,
    int? radiusKm,
  }) async {
    final current = _prefs ?? _emptyPrefs();
    await upsertPrefs(
      current.copyWith(
        primaryLocationCountry: country,
        primaryLocationState: state,
        primaryLocationCity: city,
        primaryLocationPostalCode: postalCode,
        primaryLocationLat: lat,
        primaryLocationLng: lng,
        primaryLocationRadiusKm: radiusKm,
      ),
    );
  }

  Future<void> replaceDesiredTitles(List<DesiredTitle> titles) async {
    final userId = _requireUserId();
    // Re-deriva a canônica oculta ('inferred') das áreas custom (Fase 7 +10 T2):
    // sem isso, editar áreas no perfil apagaria o mapeamento e o candidato
    // sumiria do match/busca. O getter esconde 'inferred' do usuário.
    final full = withInferredAreas(userId, titles);
    _desiredTitles = full;
    notifyListeners();
    _saving();
    try {
      await _repo.replaceDesiredTitles(userId, full);
      _desiredTitles = await _repo.getDesiredTitles(userId);
      _saved();
    } catch (e) {
      _error('Erro: $e');
      rethrow;
    }
  }

  Future<void> replaceOtherLocations(List<OtherLocation> locations) async {
    final userId = _requireUserId();
    _otherLocations = locations;
    notifyListeners();
    _saving();
    try {
      await _repo.replaceOtherLocations(userId, locations);
      _otherLocations = await _repo.getOtherLocations(userId);
      _saved();
    } catch (e) {
      _error('Erro: $e');
      rethrow;
    }
  }

  String? _userId() =>
      _prefs?.userId ?? Supabase.instance.client.auth.currentUser?.id;

  String _requireUserId() {
    final userId = _userId();
    if (userId == null || userId.isEmpty) {
      throw StateError('Usuário não autenticado.');
    }
    return userId;
  }

  JobPreferences _emptyPrefs() => JobPreferences(userId: _requireUserId());

  void _saving() {
    _saveStatus = SaveStatus.saving;
    _lastError = null;
    notifyListeners();
  }

  void _saved() {
    _saveStatus = SaveStatus.saved;
    notifyListeners();
    // Notifica outros ViewModels (UserViewModel, JobsViewModel, swipe
    // screen) que as preferências mudaram — eles invalidam caches de
    // match score. Sem isso, alterar work_mode/desired_titles via
    // aba Perfil → Preferências não reflete no card de match até
    // hot-restart, mesmo com `analyze-match` server-side lendo do
    // relacional, porque o cliente serve do `_matchCache` em memória.
    ProfileEvents.instance.notifyChanged();
  }

  void _error(String msg) {
    _saveStatus = SaveStatus.error;
    _lastError = msg;
    debugPrint('[PreferencesViewModel] $msg');
    notifyListeners();
  }
}
