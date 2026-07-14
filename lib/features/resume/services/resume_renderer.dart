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
import '../../../services/analytics_events.dart';
import '../../../services/analytics_service.dart';
import '../../../services/feature_flags_service.dart';
import '../data/profile_pdf_data_loader.dart';
import '../pdf_service.dart';
import '../resume_viewmodel.dart' show ResumeData;

/// Origem dos dados renderizados no PDF (telemetria `pdf_generated.source`).
///   - v2Relational            — flag templates_v2 ON + ProfilePdfData carregou.
///   - v1LegacyFallback        — flag ON mas perfil relacional vazio → JSONB v1.
///   - v1FlagOff               — flag OFF → ResumeData v1 do caller.
///   - canonicalProfileSnapshot — `forceFallback:true`: o caller passou um
///     ResumeData montado a partir do PERFIL CANÔNICO (profile_*, via
///     ProfileSnapshot). É o caminho do CURRÍCULO GERAL — flag-independente, NÃO
///     re-lê ProfilePdfData. NUNCA classificar como v1_flag_off (a flag pode até
///     estar ON; a origem é o snapshot canônico, não a ausência de flag).
enum ResumeRenderSource {
  v2Relational,
  v1LegacyFallback,
  v1FlagOff,
  canonicalProfileSnapshot,
}

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
  ///
  /// `forceFallback` (Fase 2): renderiza SEMPRE o `fallbackResume` fornecido,
  /// ignorando a flag templates_v2 e o re-load do ProfilePdfData. O currículo
  /// geral usa isto pra ser FLAG-INDEPENDENTE e ter o snapshot passado como
  /// ÚNICA autoridade — sem uma segunda leitura (divergente) do perfil.
  static Future<ResumeRenderResult> render({
    required String? userId,
    required UserProfile? user,
    required ResumeData fallbackResume,
    required String templateId,
    String purpose = 'render',
    bool forceFallback = false,
  }) async {
    final flagOn = !forceFallback &&
        userId != null &&
        FeatureFlagsService.instance
            .isEnabledForUser(FeatureFlagKeys.templatesV2Enabled, userId);

    // O v2 é o ÚNICO caminho que precisa de I/O (carrega o perfil relacional).
    final profileData =
        (!forceFallback && flagOn) ? await ProfilePdfData.load(userId) : null;

    final source = decideSource(
      forceFallback: forceFallback,
      flagOn: flagOn,
      hasProfileData: profileData != null,
    );
    // Só o caminho v2Relational usa os dados re-lidos; todos os demais
    // (inclusive canonicalProfileSnapshot) usam o ResumeData fornecido.
    final resumeToRender = source == ResumeRenderSource.v2Relational
        ? profileData!.toResumeData()
        : fallbackResume;

    final stopwatch = Stopwatch()..start();
    final bytes = await PdfService.generateResumeBytes(user, resumeToRender, templateId);
    stopwatch.stop();

    _track(source: source, templateId: templateId, durationMs: stopwatch.elapsedMilliseconds, purpose: purpose);

    return ResumeRenderResult(
      bytes: bytes,
      source: source,
      templateId: templateId,
    );
  }

  /// Decisão PURA de origem (sem I/O), extraída pra ser testável sem Printing
  /// (o [render] real depende de plataforma). Contrato:
  ///   - `forceFallback` VENCE tudo → canonicalProfileSnapshot (flag ON ou OFF
  ///     dá o MESMO resultado → o currículo geral é flag-independente).
  ///   - senão, flag OFF → v1FlagOff.
  ///   - senão (flag ON), perfil relacional presente → v2Relational; ausente →
  ///     v1LegacyFallback.
  @visibleForTesting
  static ResumeRenderSource decideSource({
    required bool forceFallback,
    required bool flagOn,
    required bool hasProfileData,
  }) {
    if (forceFallback) return ResumeRenderSource.canonicalProfileSnapshot;
    if (!flagOn) return ResumeRenderSource.v1FlagOff;
    return hasProfileData
        ? ResumeRenderSource.v2Relational
        : ResumeRenderSource.v1LegacyFallback;
  }

  static void _track({
    required ResumeRenderSource source,
    required String templateId,
    required int durationMs,
    required String purpose,
  }) {
    // Fix QA Dia 8 (Bug 4): `pdf_generated` estava disparando ~6x por
    // adaptação porque a tela de preview renderiza 1 thumbnail por template
    // ao trocar a seleção. Em PostHog o evento ficava inflado e a métrica
    // "PDFs gerados por user" virava ruído. Solução: o caller passa
    // `purpose` distinguindo render meaningful (download/export/share)
    // de render auxiliar (preview/thumbnail). Pra thumbnails/preview,
    // pulamos a emissão — eles são consequência técnica da UI, não ação
    // do usuário. Pra os meaningful, emitimos com `purpose` preenchido
    // pra futuras métricas distinguirem fluxos (CV base × CV adaptado ×
    // share externo). Default `'render'` preserva compat com callers
    // ainda não migrados (continuam emitindo como antes).
    if (purpose == 'preview' || purpose == 'thumbnail') return;
    try {
      Analytics.shared.track(evPdfGenerated, props: <String, Object>{
        'template_id': templateId,
        'source': _sourceLabel(source),
        // Dados relacionais (profile_*) = "v2", seja via ProfilePdfData
        // (v2Relational) ou via snapshot canônico (currículo geral).
        'version_used': (source == ResumeRenderSource.v2Relational ||
                source == ResumeRenderSource.canonicalProfileSnapshot)
            ? 'v2'
            : 'v1',
        'duration_ms': durationMs,
        'purpose': purpose,
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
      case ResumeRenderSource.canonicalProfileSnapshot:
        return 'canonical_profile_snapshot';
    }
  }
}
