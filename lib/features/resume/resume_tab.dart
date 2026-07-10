// Aba Currículo (PLANO-FASE-6 — reframe): a trilha de IA conversacional vira o
// conteúdo da aba, ABERTA naturalmente (sem botão pra iniciar). Layout = título +
// stepper de seções (Formação → Experiência → Skills → Idiomas → Interesses) +
// toggle [Conversa | Currículo] sobre um IndexedStack:
//
//   - Conversa: o chat embutido ([ChatThreadView] sem chrome) — abre digitando.
//   - Currículo: preview compacto do perfil coletado + Exportar (PDF).
//
// O "Importar CV" saiu desta aba (segue vivo no onboarding e no adapt-de-vaga).
// A trilha gamificada antiga (TracksTab) também saiu — arquivo congelado (R6).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../services/ai_service.dart';
import '../../services/analytics_events.dart';
import '../../services/analytics_service.dart';
import '../../services/profile_snapshot_service.dart';
import '../auth/user_viewmodel.dart';
import '../../services/feature_flags_service.dart';
import '../profile/application/profile_editor_view_model.dart';
import '../trilha/application/trilha_hub_status.dart';
import '../trilha/application/trilha_section.dart';
import '../trilha/application/trilha_session.dart';
import '../trilha/presentation/trilha_chat_controller.dart';
import '../trilha/presentation/trilha_chat_view.dart';
import 'resume_viewmodel.dart';
import 'services/resume_renderer.dart';
import 'widgets/curriculo_section_stepper.dart';
import 'widgets/curriculo_toggle.dart';
import 'widgets/section_detail_sheet.dart';

/// Fábrica da sessão da trilha — injetável pra teste (evita Supabase).
typedef TrilhaSessionFactory = Future<TrilhaSession> Function(String userId);

class ResumeTab extends StatefulWidget {
  const ResumeTab({super.key, this.sessionFactory});

  /// Só pra teste: substitui [buildTrilhaSession].
  final TrilhaSessionFactory? sessionFactory;

  @override
  State<ResumeTab> createState() => _ResumeTabState();
}

class _ResumeTabState extends State<ResumeTab>
    with AutomaticKeepAliveClientMixin {
  // Mantém a aba VIVA ao trocar de tab (PageView): sem isso o State é
  // recriado e a trilha reinicia do gate (igual ao JobsSwipeScreen).
  @override
  bool get wantKeepAlive => true;

  late final Future<TrilhaChatController> _future;
  TrilhaChatController? _orch;
  bool _completionHandled = false;
  bool _importReloadHandled = false;

  /// 0 = Conversa, 1 = Currículo. Abre sempre na Conversa (gate de import).
  int _tab = 0;

  /// Última das 5 seções ativa — mantida quando o passo atual cai em `outros`
  /// (cidade/área/LinkedIn) pra o stepper não "apagar".
  TrilhaSection? _stickySection;

  /// Força honesta do perfil (derivada das lacunas reais) — alimenta o header do
  /// preview e o card de conclusão. Recarregada a cada mudança de perfil (import
  /// revelado, conclusão da trilha). Null enquanto não carrega → header cai no
  /// fallback neutro. Fase 7 · +10 Tarefa 4.
  TrilhaHubStatus? _hubStatus;

  bool _isExporting = false;

  /// Recomputa a força honesta a partir do perfil FRESCO. Failure-safe.
  Future<void> _refreshHubStatus() async {
    final uid = _orch?.userId ?? Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final s = await loadTrilhaHubStatus(uid);
      if (mounted) setState(() => _hubStatus = s);
    } catch (_) {
      // Mantém o último status (ou o fallback) — nunca trava a aba.
    }
  }

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  /// Debounce do reload do preview após edições do assistente (o "Salvar" de um
  /// editor chama os writers N vezes → coalescem num único reload).
  Timer? _reloadDebounce;

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _orch?.removeListener(_onOrch);
    _orch?.dispose();
    super.dispose();
  }

  /// Após uma escrita do assistente que MUTA o perfil (add/remove/edita skill,
  /// idioma, campo, bullet, experiência…), recarrega o preview (a aba Currículo
  /// e o stepper leem do ProfileEditorViewModel in-memory) + a força honesta.
  /// Sem isso o preview mostra dados velhos mesmo com o banco já atualizado.
  void _scheduleProfileReload() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      try {
        // ignore: unawaited_futures
        context.read<ProfileEditorViewModel>().load();
      } catch (_) {/* sem provider (teste): ignora */}
      // ignore: unawaited_futures
      _refreshHubStatus();
    });
  }

  Future<TrilhaChatController> _load() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      return Future.error(StateError('Sem usuário autenticado'));
    }
    final orch = TrilhaChatController(
      userId: uid,
      sessionBuilder: widget.sessionFactory ?? buildTrilhaSession,
      // Assistente de IA na barra (PLANO-ASSISTENTE, Fase A). Atrás da flag
      // `trilha_assist_v1`: OFF ⇒ a barra mantém o comportamento de hoje.
      assistEnabled: FeatureFlagsService.instance
          .isEnabledForUser(FeatureFlagKeys.trilhaAssistV1, uid),
      assistContextLoader: () => buildAssistContext(uid),
      assistSectionSteps: assistSectionStepsFor,
      // Fase B: alterar um campo (propõe → confirma → aplica → desfaz).
      assistReadField: (field) async {
        final m = await assistReadFieldMap(uid, field);
        return m == null
            ? null
            : AssistFieldValue(
                raw: m['raw'] ?? '',
                text: m['text'] ?? '—',
                label: m['label'] ?? field);
      },
      // Os writers do assistente gravam DIRETO no banco (fora do
      // ProfileEditorViewModel). Envolvo cada um pra, no sucesso, reagendar um
      // reload do preview — assim a aba Currículo/stepper refletem a edição na
      // hora (adds aparecem, removes somem). Cobre também os undos, que reusam
      // estes mesmos callbacks.
      assistWriteField: (field, value) async {
        await assistWriteFieldValue(uid, field, value);
        _scheduleProfileReload();
      },
      assistItemAdder: (kind, value) async {
        await assistAddItem(uid, kind, value);
        _scheduleProfileReload();
      },
      assistItemRemover: (kind, value) async {
        await assistRemoveItem(uid, kind, value);
        _scheduleProfileReload();
      },
      assistItemResolver: (kind, query) => assistResolveItems(uid, kind, query),
      assistBulletReader: (bulletId) async {
        final m = await assistBulletReadMap(uid, bulletId);
        return m == null
            ? null
            : AssistFieldValue(
                raw: m['raw'] ?? '',
                text: m['text'] ?? '',
                label: m['label'] ?? 'Experiência');
      },
      assistBulletWriter: (bulletId, text) async {
        await assistBulletWrite(uid, bulletId, text);
        _scheduleProfileReload();
      },
      // Remoção reversível de experiência (captura + delete + restore pro undo).
      assistReversibleRemover: (kind, value) async {
        final restore = await assistReversibleRemove(uid, kind, value);
        _scheduleProfileReload();
        if (restore == null) return null;
        return () async {
          await restore();
          _scheduleProfileReload();
        };
      },
      // Fase C (proativo): sugere a maior lacuna que resta ao concluir.
      assistProactiveLoader: () => assistTopGap(uid),
      // Editor visual de skills: skills atuais (chips) + sugestões pela área.
      assistSkillsLoader: () => loadAssistSkills(uid),
      assistSkillSuggester: () => assistSkillSuggestionsFor(uid),
      // Editor visual de interesses (replace-all) e idiomas (nome + nível).
      assistInterestsLoader: () => loadAssistInterests(uid),
      assistInterestsReplacer: (names) async {
        await assistReplaceInterests(uid, names);
        _scheduleProfileReload();
      },
      assistLanguagesLoader: () => loadAssistLanguages(uid),
      assistLanguageUpserter: (name, level) async {
        await assistUpsertLanguage(uid, name, level);
        _scheduleProfileReload();
      },
      // Edição in-place de card (✏️) grava fora dos writers → recarrega o preview.
      onProfileEdited: _scheduleProfileReload,
      // Abertura adaptativa: se o perfil já tem seções, a trilha reconhece e vai
      // direto completar o que falta (pula o gate "começar do zero"). Vazio ⇒ gate.
      preFilledLoader: () async {
        try {
          final snap = await ProfileSnapshotService().loadSnapshot(uid);
          final filled = preFilledSectionsFromSnapshot(snap);
          return kStepperSections
              .where(filled.contains)
              .map((s) => trilhaSectionLabel(s).toLowerCase())
              .toList();
        } catch (_) {
          return const <String>[]; // failure-safe: cai no gate
        }
      },
      onFinalize: () => AIService().generateProfileSummary(),
      // Disparado ao entrar na conversa (pós-gate/import) com as lacunas já
      // recomputadas — então `total_steps` reflete o que sobrou pra perguntar.
      onStarted: (totalSteps) {
        if (totalSteps > 0) {
          // ignore: unawaited_futures
          Analytics.shared.track(evTrilhaColetaStarted, props: {
            'source': 'resume_tab',
            'total_steps': totalSteps,
          });
        }
      },
    );
    _orch = orch;
    orch.addListener(_onOrch);
    // ignore: unawaited_futures
    orch.start();
    // Força inicial: um returning user pode cair direto na conclusão/preview.
    // ignore: unawaited_futures
    _refreshHubStatus();
    return orch;
  }

  /// Reage ao orquestrador: (1) quando o import revela o resumo, recarrega o
  /// perfil pra o stepper/sheets refletirem o que foi importado; (2) ao concluir
  /// a trilha, telemetria + reload + mostra o currículo. Cada um roda 1x.
  void _onOrch() {
    final orch = _orch;
    if (orch == null) return;
    if (orch.awaitingImportConfirm && !_importReloadHandled) {
      _importReloadHandled = true;
      try {
        // ignore: unawaited_futures
        context.read<ProfileEditorViewModel>().load();
      } catch (_) {/* sem provider: ignora */}
      // O import mudou o perfil → recomputa a força honesta.
      // ignore: unawaited_futures
      _refreshHubStatus();
    }
    if (!orch.finished || _completionHandled) return;
    _completionHandled = true;
    // ignore: unawaited_futures
    Analytics.shared.track(evTrilhaColetaCompleted,
        props: {'answered': orch.answeredCount, 'source': 'resume_tab'});
    try {
      // ignore: unawaited_futures
      context.read<ProfileEditorViewModel>().load();
    } catch (_) {/* sem provider: ignora */}
    // A trilha terminou de gravar → a força honesta reflete o perfil final.
    // ignore: unawaited_futures
    _refreshHubStatus();
    if (mounted) setState(() => _tab = 1);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin (mantém a aba viva)
    // SEM Scaffold próprio: a aba vive dentro do Scaffold da HomeScreen, que é a
    // ÚNICA autoridade do inset do teclado (Scaffold aninhado dobrava o inset e
    // bagunçava o dock). ColoredBox só pinta o fundo.
    return ColoredBox(
      color: AppColors.background,
      child: FutureBuilder<TrilhaChatController>(
        future: _future,
        builder: (context, snap) {
          final Widget body;
          if (snap.connectionState != ConnectionState.done) {
            body = KeyedSubtree(
                key: const ValueKey('loading'), child: _loading());
          } else if (snap.hasError) {
            body =
                KeyedSubtree(key: const ValueKey('error'), child: _error());
          } else {
            body = KeyedSubtree(
                key: const ValueKey('ready'), child: _ready(snap.data!));
          }
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: body,
          );
        },
      ),
    );
  }

  // ── Estados ────────────────────────────────────────────────────────────────

  Widget _loading() => const SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              SizedBox(height: AppSpacing.base),
              Text('Preparando seu currículo…', style: AppTextStyles.bodyMd),
            ],
          ),
        ),
      );

  Widget _error() => SafeArea(
        child: Center(
          child: Padding(
            padding: AppSpacing.allXl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: AppColors.textTertiary, size: 40),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Não consegui carregar agora. Tenta de novo daqui a pouco.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMd
                      .copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.lg),
                SecondaryButton(
                  label: 'Tentar de novo',
                  onPressed: () => setState(() => _future = _load()),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _ready(TrilhaChatController orch) {
    final profileVM = context.watch<ProfileEditorViewModel>();
    // Teclado aberto? (lido direto do inset — a HomeScreen não zera o viewInsets,
    // então isto reflete o teclado e re-builda a aba quando ele abre/fecha.)
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          // O topo (título + stepper + toggle) COLAPSA suave quando o teclado
          // abre: libera a altura pra conversa, então o dock de entrada nunca
          // tampa a pergunta. Volta suave ao fechar o teclado.
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: keyboardOpen
                ? const SizedBox(width: double.infinity)
                : _topBar(orch, profileVM),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                _conversaView(orch, profileVM),
                _curriculoView(profileVM),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Topo: título + stepper + toggle ─────────────────────────────────────────

  Widget _topBar(
      TrilhaChatController orch, ProfileEditorViewModel profileVM) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Currículo', style: AppTextStyles.headlineMd),
          const SizedBox(height: AppSpacing.md),
          // Stepper reativo ao orquestrador (notifica a cada passo).
          AnimatedBuilder(
            animation: orch,
            builder: (context, _) {
              final active = activeFiveSection(orch.currentStep);
              if (active != null) _stickySection = active;
              final statuses = sectionStatuses(
                history: orch.history,
                current: orch.currentStep,
                preFilled: _preFilledSections(profileVM),
                stickyCurrent: _stickySection,
              );
              return CurriculoSectionStepper(
                statuses: statuses,
                // Toque numa seção → sheet de verificação do que foi coletado.
                onSectionTap: (section) => showSectionDetailSheet(
                  context,
                  section: section,
                  status: statuses[section] ?? SectionStatus.pending,
                  vm: profileVM,
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.base),
          CurriculoToggle(
            index: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
        ],
      ),
    );
  }

  Set<TrilhaSection> _preFilledSections(ProfileEditorViewModel p) {
    final s = <TrilhaSection>{};
    if (p.education.isNotEmpty) s.add(TrilhaSection.formacao);
    if (p.experiences.isNotEmpty) s.add(TrilhaSection.experiencia);
    if (p.skills.isNotEmpty) s.add(TrilhaSection.skills);
    if (p.languages.isNotEmpty) s.add(TrilhaSection.idiomas);
    if (p.interests.isNotEmpty) s.add(TrilhaSection.interesses);
    return s;
  }

  // ── Visão Conversa (chat embutido) ──────────────────────────────────────────

  // O chat hospeda tudo: gate de import → "Lendo…"/resumo → conversa de lacunas
  // → card de conclusão (inclusive o caso "nada a coletar", que cai direto na
  // conclusão). Por isso a Conversa é sempre a [TrilhaChatView].
  Widget _conversaView(
      TrilhaChatController orch, ProfileEditorViewModel profileVM) {
    return TrilhaChatView(
      controller: orch,
      // Força honesta pro card de conclusão (mesma fonte do header do preview).
      hubStatus: _hubStatus,
      // Tile do resumo do import → sheet de verificação (categoria já coletada).
      onVerifySection: (section) => showSectionDetailSheet(
        context,
        section: section,
        status: SectionStatus.done,
        vm: profileVM,
      ),
    );
  }

  // ── Visão Currículo (preview + exportar) ────────────────────────────────────

  Widget _curriculoView(ProfileEditorViewModel p) {
    final hasAny = p.experiences.isNotEmpty ||
        p.skills.isNotEmpty ||
        p.education.isNotEmpty ||
        p.languages.isNotEmpty ||
        p.interests.isNotEmpty;
    return PiiMask(
      child: Column(
        children: [
          Expanded(
            child: hasAny
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                        AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
                    children: [
                      _previewHeader(p),
                      if (p.skills.isNotEmpty) _chipsSection('Habilidades',
                          p.skills.map((s) => s.name).toList()),
                      if (p.languages.isNotEmpty) _languagesSection(p),
                      if (p.experiences.isNotEmpty) _experienceSection(p),
                      if (p.education.isNotEmpty) _educationSection(p),
                      if (p.interests.isNotEmpty) _chipsSection(
                          'Áreas de interesse',
                          p.interests.map((i) => i.name).toList()),
                    ],
                  )
                : _previewEmpty(),
          ),
          _exportBar(p),
        ],
      ),
    );
  }

  Widget _previewEmpty() => Center(
        child: Padding(
          padding: AppSpacing.allXl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.description_outlined,
                  color: AppColors.textTertiary, size: 40),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Seu currículo aparece aqui',
                textAlign: TextAlign.center,
                style: AppTextStyles.titleSm
                    .copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Responda à conversa ao lado pra montar seu currículo.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMd
                    .copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );

  Widget _previewHeader(ProfileEditorViewModel p) {
    final name = p.personal?.fullName.trim() ?? '';
    final location = p.personal?.formattedLocation.trim() ?? '';
    final hs = _hubStatus;
    // Força honesta (ponderada por monetização). Enquanto o hub não carrega, cai
    // no completeness do banco em cor NEUTRA — nunca o verde de "está ótimo".
    final pct = hs?.strengthPercent ?? p.completenessScore;
    final initials = _initials(name);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.base),
      padding: AppSpacing.allBase,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: AppRadius.brMd,
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style:
                      AppTextStyles.titleSm.copyWith(color: AppColors.primary),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.isEmpty ? 'Seu perfil' : name,
                        style: AppTextStyles.titleSm,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(location,
                          style: AppTextStyles.bodySm
                              .copyWith(color: AppColors.textTertiary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              _strengthBadge(pct, hs?.level),
            ],
          ),
          // Painel honesto: nunca "beco sem saída". Mostra o próximo ganho (ou
          // comemora de verdade quando não falta nada). Fase 7 · +10 Tarefa 4.
          if (hs != null) ...[
            const SizedBox(height: AppSpacing.md),
            _hubNextWin(hs),
          ],
        ],
      ),
    );
  }

  /// Pílula de força colorida pelo ESTÁGIO real — verde só quando é verdade.
  Widget _strengthBadge(int pct, HubLevel? level) {
    Color bg;
    Color fg;
    switch (level) {
      case HubLevel.complete:
      case HubLevel.shortlistReady:
        bg = AppColors.successSoft;
        fg = AppColors.success;
      case HubLevel.building:
        bg = AppColors.warningSoft;
        fg = AppColors.warning;
      case null:
        bg = AppColors.border;
        fg = AppColors.textTertiary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.brPill),
      child: Text('$pct%',
          style: AppTextStyles.labelSm.copyWith(color: fg)),
    );
  }

  /// O próximo ganho enquadrado por valor — ou a comemoração honesta (completo).
  Widget _hubNextWin(TrilhaHubStatus hs) {
    if (hs.level == HubLevel.complete) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_rounded,
              size: 16, color: AppColors.success),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(hs.message,
                style: AppTextStyles.bodySm
                    .copyWith(color: AppColors.textSecondary)),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.trending_up_rounded,
                size: 15, color: AppColors.warning),
            const SizedBox(width: AppSpacing.xs),
            Text('PRÓXIMO GANHO',
                style: AppTextStyles.overline
                    .copyWith(color: AppColors.warning, letterSpacing: 0.6)),
            if (hs.nextStepLabel != null)
              Expanded(
                child: Text(' · ${hs.nextStepLabel}',
                    style: AppTextStyles.overline
                        .copyWith(color: AppColors.textTertiary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(hs.message,
            style:
                AppTextStyles.bodySm.copyWith(color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text(t.toUpperCase(),
            style: AppTextStyles.overline.copyWith(letterSpacing: 0.6)),
      );

  Widget _card({required Widget child}) => Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.base),
        padding: AppSpacing.allBase,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.brLg,
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [child]),
      );

  Widget _chipsSection(String title, List<String> items) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(title),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final it in items)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: AppRadius.brSm,
                  ),
                  child: Text(it,
                      style: AppTextStyles.labelSm
                          .copyWith(color: AppColors.primary)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _languagesSection(ProfileEditorViewModel p) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Idiomas'),
          for (final lang in p.languages)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(lang.name, style: AppTextStyles.bodyMd
                      .copyWith(color: AppColors.textPrimary)),
                  Text(lang.proficiencyLabel,
                      style: AppTextStyles.bodySm
                          .copyWith(color: AppColors.textTertiary)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _experienceSection(ProfileEditorViewModel p) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Experiência'),
          for (final exp in p.experiences)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(exp.title, style: AppTextStyles.labelMd),
                  Text(
                    [exp.company, exp.formattedPeriod]
                        .where((s) => s.trim().isNotEmpty)
                        .join(' · '),
                    style: AppTextStyles.bodySm
                        .copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _educationSection(ProfileEditorViewModel p) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Formação'),
          for (final ed in p.education)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ed.majors.isNotEmpty
                        ? ed.majors.map((m) => m.name).join(', ')
                        : (ed.degree ?? 'Curso'),
                    style: AppTextStyles.labelMd,
                  ),
                  Text(ed.institution,
                      style: AppTextStyles.bodySm
                          .copyWith(color: AppColors.textTertiary)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _exportBar(ProfileEditorViewModel p) {
    final resumeVM = context.watch<ResumeViewModel>();
    final canExport = resumeVM.resumeData != null ||
        p.experiences.isNotEmpty ||
        p.skills.isNotEmpty ||
        p.education.isNotEmpty ||
        p.languages.isNotEmpty ||
        p.interests.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: PrimaryButton(
          label: 'Exportar PDF',
          icon: Icons.upload_rounded,
          isLoading: _isExporting,
          onPressed: canExport ? () => _export(resumeVM) : null,
        ),
      ),
    );
  }

  Future<void> _export(ResumeViewModel resumeVM) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final userVM = context.read<UserViewModel>();
      final user = userVM.user;
      final uid = user?.id ?? Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) {
        throw Exception('Sessão expirada — entre novamente para exportar.');
      }
      // O currículo desta aba (trilha de IA) é montado a partir do que a trilha
      // coletou nas tabelas profile_*, via ProfileSnapshot — NÃO do
      // resumeVM.resumeData legado (gamificação desligada), que vinha vazio e
      // gerava um PDF em branco. Assim o export funciona independente da flag
      // templates_v2. O CV adaptado por vaga é outro fluxo (parte de um CV
      // importado) e não passa por aqui — segue intacto.
      final snapshot = await ProfileSnapshotService().loadSnapshot(uid);
      final resumeFromProfile = snapshot.toResumeData(
        userFallbackName: user?.name,
      );
      final rendered = await ResumeRenderer.render(
        userId: uid,
        user: user,
        fallbackResume: resumeFromProfile,
        templateId: resumeVM.selectedTemplateId, // padrão: harvard_ats
        purpose: 'export',
      );
      final safeName = (user?.name ?? 'profissional').replaceAll(' ', '_');
      await Printing.sharePdf(
        bytes: rendered.bytes,
        filename: 'curriculo_$safeName.pdf',
      );
      // ignore: unawaited_futures
      Analytics.shared.cvExported(templateId: resumeVM.selectedTemplateId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao gerar PDF: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '·';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}
