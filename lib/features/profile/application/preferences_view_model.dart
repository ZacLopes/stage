// PreferencesViewModel — gerencia JobPreferences + DesiredTitles +
// ApplicationCountries + OtherLocations. Usado nas 8 telas de preferências
// do onboarding novo e na edição futura via aba Perfil.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  List<DesiredTitle> get desiredTitles => List.unmodifiable(_desiredTitles);
  List<OtherLocation> get otherLocations => List.unmodifiable(_otherLocations);
  bool get isLoading => _isLoading;
  SaveStatus get saveStatus => _saveStatus;
  String? get lastError => _lastError;

  PreferencesViewModel(this._repo);

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
    _prefs = prefs;
    notifyListeners();
    _saving();
    try {
      _prefs = await _repo.upsertJobPreferences(prefs);
      _saved();
    } catch (e) {
      _error('Erro ao salvar preferências: $e');
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
    await upsertPrefs(current.copyWith(
      primaryLocationCountry: country,
      primaryLocationState: state,
      primaryLocationCity: city,
      primaryLocationPostalCode: postalCode,
      primaryLocationLat: lat,
      primaryLocationLng: lng,
      primaryLocationRadiusKm: radiusKm,
    ));
  }

  Future<void> replaceDesiredTitles(List<DesiredTitle> titles) async {
    final userId = _userId();
    if (userId == null) return;
    _desiredTitles = titles;
    notifyListeners();
    _saving();
    try {
      await _repo.replaceDesiredTitles(userId, titles);
      _desiredTitles = await _repo.getDesiredTitles(userId);
      _saved();
    } catch (e) {
      _error('Erro: $e');
    }
  }

  Future<void> replaceOtherLocations(List<OtherLocation> locations) async {
    final userId = _userId();
    if (userId == null) return;
    _otherLocations = locations;
    notifyListeners();
    _saving();
    try {
      await _repo.replaceOtherLocations(userId, locations);
      _otherLocations = await _repo.getOtherLocations(userId);
      _saved();
    } catch (e) {
      _error('Erro: $e');
    }
  }

  String? _userId() => _prefs?.userId ?? Supabase.instance.client.auth.currentUser?.id;

  JobPreferences _emptyPrefs() => JobPreferences(userId: _userId() ?? '');

  void _saving() {
    _saveStatus = SaveStatus.saving;
    _lastError = null;
    notifyListeners();
  }

  void _saved() {
    _saveStatus = SaveStatus.saved;
    notifyListeners();
  }

  void _error(String msg) {
    _saveStatus = SaveStatus.error;
    _lastError = msg;
    debugPrint('[PreferencesViewModel] $msg');
    notifyListeners();
  }
}
