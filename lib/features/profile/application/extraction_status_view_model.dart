// ExtractionStatusViewModel — controla o estado da extração do CV que roda
// em background durante o onboarding novo (path Upload).
//
// Quando user toca "Continuar" no UploadConfirmScreen, dispara start(pdfBytes).
// Edge function extract-profile roda (10-15s tipicamente). Enquanto isso,
// o user passa pelas 7 telas de perguntas mascarando latência.
//
// Quando chega na ReviewResumeScreen, o status é consultado:
//   - completed: mostra seções populadas
//   - running: mostra "Quase pronto..." + spinner
//   - failed: fallback vazio editável

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum ExtractionStatus { notStarted, running, completed, failed }

class ExtractionResult {
  final Map<String, dynamic> parsed;
  final Map<String, dynamic>? profileData;
  final double? confidenceGlobal;
  final List<String> lowConfidenceFields;
  final bool cached;

  const ExtractionResult({
    required this.parsed,
    this.profileData,
    this.confidenceGlobal,
    this.lowConfidenceFields = const [],
    this.cached = false,
  });
}

class ExtractionStatusViewModel extends ChangeNotifier {
  ExtractionStatus _status = ExtractionStatus.notStarted;
  ExtractionResult? _result;
  String? _error;
  DateTime? _startedAt;

  ExtractionStatus get status => _status;
  ExtractionResult? get result => _result;
  String? get error => _error;
  Duration get elapsed => _startedAt == null
      ? Duration.zero
      : DateTime.now().difference(_startedAt!);

  /// Dispara extract-profile em background. Sem await — caller faz fire-and-forget
  /// e a UI observa via [status].
  void start(Uint8List pdfBytes, {String? rawTextFallback}) {
    if (_status == ExtractionStatus.running) return;
    _status = ExtractionStatus.running;
    _result = null;
    _error = null;
    _startedAt = DateTime.now();
    notifyListeners();

    _runExtraction(pdfBytes, rawTextFallback);
  }

  Future<void> _runExtraction(Uint8List pdfBytes, String? rawTextFallback) async {
    try {
      final pdfBase64 = base64Encode(pdfBytes);
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) {
        _failed('Usuário não autenticado');
        return;
      }

      final response = await supabase.functions.invoke(
        'extract-profile',
        body: {
          'pdf_base64': pdfBase64,
          if (rawTextFallback != null) 'raw_text_fallback': rawTextFallback,
        },
      ).timeout(const Duration(seconds: 75));

      final data = response.data;
      if (data is! Map) {
        _failed('Resposta inválida da extração');
        return;
      }
      if (data['error'] != null) {
        _failed(data['error'].toString());
        return;
      }

      final parsed = (data['parsed'] as Map?)?.cast<String, dynamic>() ?? {};
      final profileData = (data['profile_data'] as Map?)?.cast<String, dynamic>();
      final meta = (data['extraction_meta'] as Map?)?.cast<String, dynamic>();
      final confidenceGlobal = (meta?['confidence_global'] as num?)?.toDouble();
      final lowConfRaw = meta?['low_confidence_fields'];
      final lowConf = lowConfRaw is List
          ? lowConfRaw.map((e) => e.toString()).toList()
          : <String>[];

      _result = ExtractionResult(
        parsed: parsed,
        profileData: profileData,
        confidenceGlobal: confidenceGlobal,
        lowConfidenceFields: lowConf,
        cached: data['cached'] == true,
      );
      _status = ExtractionStatus.completed;
      notifyListeners();
    } catch (e) {
      _failed('Erro: $e');
    }
  }

  void _failed(String msg) {
    _error = msg;
    _status = ExtractionStatus.failed;
    debugPrint('[ExtractionStatusViewModel] failed: $msg');
    notifyListeners();
  }

  void reset() {
    _status = ExtractionStatus.notStarted;
    _result = null;
    _error = null;
    _startedAt = null;
    notifyListeners();
  }
}
