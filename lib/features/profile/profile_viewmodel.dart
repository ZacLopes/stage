import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:printing/printing.dart';
import '../../data/models/models.dart';
import '../../data/supabase_repository.dart';
import '../../services/ai_service.dart';
import '../../data/local_storage_repository.dart';

class ProfileViewModel extends ChangeNotifier {
  final SupabaseRepository _repository;
  
  List<SavedResume> _savedResumes = [];
  bool _isLoading = true;
  String? _error;

  ProfileViewModel(this._repository, _, __) {
    _init();
  }

  void _init() {
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      if (event == AuthChangeEvent.signedIn) {
        loadSavedResumes();
      } else if (event == AuthChangeEvent.signedOut) {
        _clearData();
      }
    });

    loadSavedResumes();
  }

  void _clearData() {
    _savedResumes = [];
    _error = null;
    _isLoading = false;
    notifyListeners();
  }

  List<SavedResume> get savedResumes => _savedResumes;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadSavedResumes() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      _clearData();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      _savedResumes = await _repository.getSavedResumes();
    } catch (e) {
      print('Error loading saved resumes: $e');
      _error = 'Erro ao carregar sua biblioteca';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteResume(SavedResume resume) async {
    try {
      await _repository.deleteSavedResume(resume.id, resume.filePath);
      _savedResumes.removeWhere((r) => r.id == resume.id);
      notifyListeners();
    } catch (e) {
      print('Error deleting resume: $e');
      _error = 'Erro ao excluir currículo';
      notifyListeners();
    }
  }

  Future<void> downloadAndShareResume(SavedResume resume) async {
    try {
      final bytes = await _repository.downloadResume(resume.filePath);
      await Printing.sharePdf(
        bytes: bytes,
        filename: '${resume.title.replaceAll(' ', '_')}.pdf',
      );
    } catch (e) {
      print('Error sharing resume: $e');
      _error = 'Erro ao abrir currículo';
      notifyListeners();
    }
  }

  Future<Uint8List?> downloadResumeBytes(SavedResume resume) async {
    try {
      return await _repository.downloadResume(resume.filePath);
    } catch (e) {
      print('Error downloading resume: $e');
      _error = 'Erro ao baixar currículo';
      notifyListeners();
      return null;
    }
  }

  Future<SavedResume> saveResume(
    String title,
    List<int> pdfBytes, {
    SavedResumeSource source = SavedResumeSource.manual,
    Map<String, dynamic>? resumeData,
    String? templateId,
  }) async {
    try {
      final saved = await _repository.saveResume(
        title,
        pdfBytes,
        source: source,
        resumeData: resumeData,
        templateId: templateId,
      );
      await loadSavedResumes(); // Refresh list
      return saved;
    } catch (e) {
      print('Error saving resume: $e');
      _error = 'Erro ao salvar currículo';
      notifyListeners();
      rethrow;
    }
  }

  /// Troca o template de um CV salvo na biblioteca: re-render server-side
  /// (PDF novo) → upload sobrescreve o arquivo → atualiza `template_id`.
  /// Só faz sentido quando `resume.resumeData != null` (ie, CV salvo
  /// depois da migration 20260526). Atualiza a lista in-memory pra UI.
  Future<SavedResume> updateResumeTemplate({
    required SavedResume resume,
    required List<int> newPdfBytes,
    required String newTemplateId,
  }) async {
    try {
      final updated = await _repository.updateResumeTemplate(
        resumeId: resume.id,
        filePath: resume.filePath,
        pdfBytes: newPdfBytes,
        templateId: newTemplateId,
      );
      // Substitui in-memory pra evitar refetch completo (e flicker da
      // biblioteca enquanto carrega). Mantém o resumeData original do
      // local (não vem no UPDATE return se o jsonb não foi tocado).
      final mergedResumeData = updated.resumeData ?? resume.resumeData;
      final merged = updated.copyWith(resumeData: mergedResumeData);
      _savedResumes = _savedResumes
          .map((r) => r.id == merged.id ? merged : r)
          .toList();
      notifyListeners();
      return merged;
    } catch (e) {
      print('Error updating resume template: $e');
      _error = 'Erro ao trocar modelo do currículo';
      notifyListeners();
      rethrow;
    }
  }

  /// Resolves a unique title given a base. If the base already exists in
  /// the user's library, appends "(2)", "(3)", ... until a free slot is
  /// found. Loads the library if it hasn't been loaded yet so the check
  /// has fresh data.
  Future<String> resolveUniqueTitle(String base) async {
    if (_savedResumes.isEmpty) {
      await loadSavedResumes();
    }
    final taken = _savedResumes.map((r) => r.title).toSet();
    if (!taken.contains(base)) return base;
    var n = 2;
    while (taken.contains('$base ($n)')) {
      n++;
    }
    return '$base ($n)';
  }
}
