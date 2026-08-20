import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service de feature flags do Stage. Lê tabela `app_feature_flags` no
/// Supabase com cache em memória.
///
/// **Por que não PostHog**: na Semana 2, `new_onboarding_enabled` (PostHog)
/// foi bypassada por cache async frágil. Pra rollout de features críticas
/// (templates v2, adapt v2, match v2) precisamos de fonte única + leitura
/// síncrona após o cache cold-start.
///
/// **Rollout determinístico por user_id**: usa `hashCode.abs() % 100` pra
/// estabilidade entre sessões. User com hash baixo entra primeiro, alto
/// entra por último, mas cada user fica num bucket fixo.
///
/// **Fluxo**:
///   1. App startup chama `FeatureFlagsService.instance.refresh()` — carrega
///      todas as flags do banco em ~1 chamada.
///   2. Código pergunta `isEnabledForUser('templates_v2_enabled', userId)`
///      sincronamente. Se cache ainda não carregou, retorna `false`
///      (failure-safe — mantém v1).
///   3. Refresh chamado de novo on-foreground.
class FeatureFlagsService {
  FeatureFlagsService._internal();
  static final FeatureFlagsService instance = FeatureFlagsService._internal();

  // Lazy: só é tocado no refresh() (carga do banco). Deferir evita exigir o
  // Supabase inicializado só pra ler flags do cache (e quebra em testes).
  late final SupabaseClient _client = Supabase.instance.client;

  /// Cache: feature_key → (enabled, rollout_pct)
  final Map<String, _FlagState> _cache = {};
  bool _loaded = false;

  /// Carrega todas as flags do banco. Idempotente. Falha silenciosa: se
  /// não conseguir ler, deixa o cache vazio → tudo retorna false → v1.
  Future<void> refresh() async {
    try {
      final rows = await _client
          .from('app_feature_flags')
          .select('feature_key, enabled, rollout_pct');

      _cache.clear();
      for (final row in rows as List<dynamic>) {
        final m = row as Map<String, dynamic>;
        final key = m['feature_key'] as String?;
        if (key == null) continue;
        _cache[key] = _FlagState(
          enabled: (m['enabled'] as bool?) ?? false,
          rolloutPct: (m['rollout_pct'] as int?) ?? 0,
        );
      }
      _loaded = true;
      if (kDebugMode) {
        debugPrint('[FeatureFlags] loaded ${_cache.length} flags: '
            '${_cache.entries.map((e) => "${e.key}=${e.value}").join(", ")}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[FeatureFlags] refresh falhou: $e');
      // Mantém cache atual (ou vazio se primeira tentativa). Não rethrow.
    }
  }

  /// True se `_loaded` (ao menos uma refresh com sucesso aconteceu).
  /// Útil pra UI esperar antes de tomar decisão crítica de roteamento.
  bool get isLoaded => _loaded;

  /// Pergunta principal: a flag está ativa pro user `userId`?
  ///
  /// Lógica:
  ///   1. enabled=false → false (kill switch global)
  ///   2. enabled=true + rollout_pct=100 → true (full rollout)
  ///   3. enabled=true + rollout_pct=0..99 → hash determinístico do userId
  ///
  /// `userId` ser null → false (não dá pra hashear; melhor v1).
  bool isEnabledForUser(String featureKey, String? userId) {
    final flag = _cache[featureKey];
    if (flag == null || !flag.enabled) return false;
    if (flag.rolloutPct >= 100) return true;
    if (flag.rolloutPct <= 0) return false;
    if (userId == null || userId.isEmpty) return false;

    final bucket = _userBucket(userId);
    return bucket < flag.rolloutPct;
  }

  /// Gate estrutural da terceira aba: o Assistente só pode ligar dentro da
  /// trilha de coleta que o hospeda. Manter esta composição aqui evita que
  /// telas diferentes consultem apenas a flag filha e entrem em variantes
  /// incompatíveis.
  ///
  /// Ausência de usuário ou de qualquer uma das flags é failure-safe: OFF.
  bool isTrilhaAssistEnabledForUser(String? userId) {
    if (userId == null || userId.isEmpty) return false;
    return isEnabledForUser(FeatureFlagKeys.trilhaColetaV1, userId) &&
        isEnabledForUser(FeatureFlagKeys.trilhaAssistV1, userId);
  }

  /// Persistir o currículo geral ao exportar (source='general').
  ///
  /// Separada de [trilhaAssistV1] em 20/08/2026 por decisão do fundador: ele
  /// quer o Assistente E o salvar-ao-exportar, mas NÃO quer as outras três
  /// consequências que estavam amarradas na mesma leitura (ver
  /// [FeatureFlagKeys.importedSourceHomeV1]).
  ///
  /// ANINHADA de propósito: com o Assistente OFF o card "Currículo geral" nem
  /// é montado, então salvar a versão gravaria linha + PDF que NINGUÉM
  /// consegue ver (a biblioteca esconde 'general' sempre, por regra fixa).
  /// O aninhamento vive aqui, em código, pra não depender de disciplina
  /// operacional na tabela.
  bool isGeneralResumeSaveEnabledForUser(String? userId) =>
      isTrilhaAssistEnabledForUser(userId) &&
      isEnabledForUser(FeatureFlagKeys.resumeSaveOnExportV1, userId);

  /// Mudar o currículo importado de casa: some da aba Currículos e passa a
  /// viver no card "Fonte importada" em Perfil → Dados.
  ///
  /// As duas metades vivem na MESMA flag de propósito. Meia mudança tem
  /// consequência real: só a primeira metade faria 696 pessoas (medido em
  /// prod, 20/08/2026) perderem qualquer tela que alcance o CV importado —
  /// 47 delas com mais de um arquivo. Chave separada pra cada metade é o
  /// defeito seguinte.
  ///
  /// Nasce OFF e o fundador decidiu em 20/08 mantê-la OFF: os importados
  /// ficam onde estão. Existe pra que essa decisão seja reversível por banco,
  /// sem build.
  bool isImportedSourceHomeEnabledForUser(String? userId) =>
      isTrilhaAssistEnabledForUser(userId) &&
      isEnabledForUser(FeatureFlagKeys.importedSourceHomeV1, userId);

  /// Versão sem rollout — true se a flag está globalmente ligada.
  /// Use só em context onde rollout percentual não faz sentido (ex: feature
  /// que ou tá pronta ou não tá, sem teste A/B). Para o caso v1/v2 do
  /// Stage, prefira `isEnabledForUser`.
  bool isGloballyEnabled(String featureKey) {
    final flag = _cache[featureKey];
    return flag != null && flag.enabled && flag.rolloutPct >= 100;
  }

  /// Hash determinístico → bucket 0..99.
  /// Usa `hashCode` do Dart (estável por sessão; pra estabilidade entre
  /// rebuilds, garantimos que UUID é a entrada — UUIDs do Supabase têm
  /// distribuição uniforme natural).
  int _userBucket(String userId) {
    return userId.hashCode.abs() % 100;
  }

  /// Para testes — limpa cache.
  @visibleForTesting
  void resetForTesting() {
    _cache.clear();
    _loaded = false;
  }

  /// Para testes — força estado de uma flag.
  @visibleForTesting
  void setFlagForTesting(String key, {required bool enabled, required int rolloutPct}) {
    _cache[key] = _FlagState(enabled: enabled, rolloutPct: rolloutPct);
    _loaded = true;
  }
}

class _FlagState {
  final bool enabled;
  final int rolloutPct;
  _FlagState({required this.enabled, required this.rolloutPct});

  @override
  String toString() => 'enabled=$enabled,pct=$rolloutPct';
}

/// Constantes pra evitar typo nos call sites. Sincronizado com seeds
/// da migration `20260523000002_app_feature_flags.sql`.
class FeatureFlagKeys {
  FeatureFlagKeys._();
  static const String templatesV2Enabled = 'templates_v2_enabled';
  static const String adaptV2Enabled = 'adapt_v2_enabled';
  static const String matchV2Enabled = 'match_v2_enabled';

  /// FASE 2 (T2.2): feed server-side via RPC get_feed_page (modo lista +
  /// swipe por snapshot). OFF = caminho legacy intocado (rollback).
  /// Seed na migration 20260612120200; rollout 10→50→100 pós-2.4.0.
  static const String feedListV1 = 'feed_list_v1';

  /// FASE 3 (T3.1/T3.2/T3.3): aba Candidaturas (4 segmentos) + prompt de
  /// retorno + adição manual. OFF = aba Salvas atual (3 buckets) intocada.
  /// Seed na migration 20260616140000; rollout 10→50→100 decidido pelo fundador.
  static const String applicationsTrackerV1 = 'applications_tracker_v1';

  /// Taxonomia de skills (P5, Fase C): typeahead canônico no editor de skills
  /// (sugere do skills_catalog). OFF = input texto-livre atual. Seed na migration
  /// 20260617130000. O trigger no banco já normaliza todo write — o typeahead
  /// só reduz nova fragmentação na origem.
  static const String skillsTypeaheadV1 = 'skills_typeahead_v1';

  /// Remoção reversível da trilha gamificada (estilo Duolingo) da aba Currículo.
  /// OFF (default failure-safe) = card "Construir pela trilha" escondido → a aba
  /// fica só com "Importar CV"; o passo equivalente do tutorial também some. ON
  /// (enabled + 100%) = trilha volta na hora, sem rebuild. O código da trilha
  /// continua no app (congelado, R6) — só o entry point da aba Currículo é
  /// gateado. A trilha no ONBOARDING (TwoDoorsScreen) NÃO é afetada. Binário
  /// (use isGloballyEnabled, sem A/B). Seed na migration 20260622120000.
  static const String resumeTrailEnabled = 'resume_trail_enabled';

  /// KILL-SWITCH (bugfix perfis ocos): restaura a `CompletionScreen` legacy como
  /// fallback de roteamento pós-login. Default OFF ⇒ o fallback vai pro
  /// onboarding que COLETA dados (`TwoDoorsScreen`). Ligar (enabled + 100%) só
  /// pra rollback de emergência se a mudança de roteamento causar regressão.
  /// Failure-safe ao contrário dos outros flags: ausente/não-carregada ⇒ fix
  /// ligado (lido via [FeatureFlagsService.isGloballyEnabled], que só retorna
  /// true com enabled+100). Seed na migration 20260623120000.
  static const String legacyCompletionScreenEnabled =
      'legacy_completion_screen_enabled';

  /// Trilha de coleta conversacional (PLANO-FASE-6 T6.3): mostra o card
  /// "Completar com a IA" no hub do Perfil. Default OFF (escondido); rollout
  /// 10→50→100 via app_feature_flags. Seed na migration 20260623150000.
  static const String trilhaColetaV1 = 'trilha_coleta_v1';

  /// Assistente de IA na barra do chat da trilha (PLANO-ASSISTENTE): a barra
  /// "Escreva uma mensagem…" vira assistente (tira dúvida, conduz a coleta,
  /// altera sob confirmação). ANINHADA em [trilhaColetaV1] — só vale onde a
  /// trilha existe. Default OFF (com OFF, a barra mantém o comportamento de
  /// hoje: resposta ao passo aberto). Kill-switch independente; rollout
  /// 10→50→100. Seed na migration 20260717120000.
  static const String trilhaAssistV1 = 'trilha_assist_v1';

  /// Salvar o currículo geral ao exportar. ANINHADA em [trilhaAssistV1] —
  /// leia por `isGeneralResumeSaveEnabledForUser`, nunca direto, senão o
  /// aninhamento se perde. Default OFF. Seed em
  /// `20260820120000_seed_split_trilha_assist_flags.sql`.
  ///
  /// Contexto: até 20/08/2026 isto vivia colado em [trilhaAssistV1], e o
  /// resultado medido foi ZERO linhas `source='general'` na base inteira —
  /// o app gera o PDF, compartilha, e não guarda cópia nenhuma.
  static const String resumeSaveOnExportV1 = 'resume_save_on_export_v1';

  /// Move o CV importado da aba Currículos para o card "Fonte importada" em
  /// Perfil → Dados. ANINHADA em [trilhaAssistV1] — leia por
  /// `isImportedSourceHomeEnabledForUser`. Default OFF **e assim decidido**
  /// pelo fundador em 20/08/2026: os importados ficam na aba Currículos.
  static const String importedSourceHomeV1 = 'imported_source_home_v1';

  /// ⚠️ **Flag NEGATIVA** — a única do repo. `enabled=true` + 100% ESCONDE a
  /// porta de importar CV em Perfil → Currículos; ausente/false a MOSTRA.
  ///
  /// A inversão é deliberada. Toda flag daqui é failure-CLOSED: sem rede no
  /// cold start, `refresh()` engole a exceção (main.dart:150-152), o cache
  /// fica vazio e o recurso some. Isso é seguro para feature nova — e é
  /// exatamente o defeito aqui, porque a porta de import não é feature nova:
  /// a 2.4.0 publicada tinha esse botão sem flag nenhuma
  /// (37edebc:resume_tab.dart:257-288). O estado "desligado" É a regressão.
  /// Com semântica positiva, qualquer abertura do app sem rede recriaria o
  /// problema que estamos consertando.
  ///
  /// Existe só como interruptor de emergência: se a porta der problema em
  /// produção, uma linha no banco a apaga sem publicar build. Precedente de
  /// leitura por [isGloballyEnabled]: `legacy_completion_screen_enabled`
  /// (splash_screen.dart:575-576).
  ///
  /// Seed em `20260731120000_seed_cv_import_entry_kill_switch.sql` — o código
  /// funciona sem a linha; ela só serve para MATAR a porta.
  static const String cvImportEntryDisabled = 'cv_import_entry_disabled';
}
