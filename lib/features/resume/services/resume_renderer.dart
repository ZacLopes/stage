// Semana 3 — Bloco B: ponto único de geração de PDF de currículo.
//
// Wrappa `PdfService.generateResumeBytes` adicionando:
//   - Seleção v1 (JSONB legacy) vs v2 (schema relacional) via feature flag
//     `templates_v2_enabled` + rollout percentual por user_id.
//   - Fallback automático ao v1 quando o perfil estruturado está vazio
//     (sinalizado por `ProfilePdfData.load` retornando null).
//   - Telemetria PostHog `pdf_generated` com source/template/version_used
//     pra alimentar dashboard de comparação.
//
// Call sites devem passar pelo `ResumeRenderer.render(...)` em vez de
// chamar `PdfService.generateResumeBytes` direto. Manter PdfService como
// builder bruto facilita testar templates isoladamente.

import 'package:flutter/foundation.dart';

import '../../../data/models/models.dart';
import '../../../services/analytics_service.dart';
import '../../../services/feature_flags_service.dart';
import '../data/profile_pdf_data_loader.dart';
import '../pdf_service.dart';
import '../resume_viewmodel.dart' show ResumeData;

enum ResumeRenderSource { v2Relational, v1LegacyFallback, v1FlagOff }

class ResumeRenderResult {
  final Uint8List bytes;
  final ResumeRenderSource source;
  final String templateId;
  const ResumeRenderResult({
    required this.bytes,
    required this.source,
    required this.templateId,
  });
}

class ResumeRenderer {
  ResumeRenderer._();

  /// Gera o PDF do currículo escolhendo entre v1 e v2 conforme feature
  /// flag + estado do perfil. `userId` pode ser null quando o user está
  /// rendendo de forma anônima (debug/thumbnail) — nesse caso usa v1 puro.
  ///
  /// `fallbackResume` é o ResumeData v1 (já hidratado pelo caller a partir
  /// do JSONB legacy). Continua sendo necessário pra preservar fallback
  /// quando v2 não tem dados.
  static Future<ResumeRenderResult> render({
    required String? userId,
    required UserProfile? user,
    required ResumeData fallbackResume,
    required String templateId,
  }) async {
    final flagOn = userId != null &&
        FeatureFlagsService.instance
            .isEnabledForUser(FeatureFlagKeys.templatesV2Enabled, userId);

    ResumeRenderSource source;
    ResumeData resumeToRender;

    if (!flagOn) {
      source = ResumeRenderSource.v1FlagOff;
      resumeToRender = fallbackResume;
    } else {
      final profileData = await ProfilePdfData.load(userId);
      if (profileData != null) {
        source = ResumeRenderSource.v2Relational;
        resumeToRender = profileData.toResumeData();
      } else {
        source = ResumeRenderSource.v1LegacyFallback;
        resumeToRender = fallbackResume;
      }
    }

    final stopwatch = Stopwatch()..start();
    final bytes = await PdfService.generateResumeBytes(user, resumeToRender, templateId);
    stopwatch.stop();

    _track(source: source, templateId: templateId, durationMs: stopwatch.elapsedMilliseconds);

    return ResumeRenderResult(
      bytes: bytes,
      source: source,
      templateId: templateId,
    );
  }

  static void _track({
    required ResumeRenderSource source,
    required String templateId,
    required int durationMs,
  }) {
    try {
      Analytics.shared.track('pdf_generated', props: <String, Object>{
        'template_id': templateId,
        'source': _sourceLabel(source),
        'version_used': source == ResumeRenderSource.v2Relational ? 'v2' : 'v1',
        'duration_ms': durationMs,
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[ResumeRenderer] track erro: $e');
    }
  }

  static String _sourceLabel(ResumeRenderSource s) {
    switch (s) {
      case ResumeRenderSource.v2Relational:
        return 'v2_relational';
      case ResumeRenderSource.v1LegacyFallback:
        return 'v1_legacy_fallback';
      case ResumeRenderSource.v1FlagOff:
        return 'v1_flag_off';
    }
  }
}
