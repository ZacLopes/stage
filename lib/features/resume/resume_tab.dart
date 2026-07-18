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
import '../home/home_viewmodel.dart';
import '../jobs/data/job_repository.dart';
import '../jobs/jobs_viewmodel.dart';
import '../jobs/models/job.dart';
import '../jobs/models/user_preferences.dart';
import '../jobs/screens/job_details_sheet.dart';
import '../jobs/utils/filter_helpers.dart';
import '../profile/application/profile_editor_view_model.dart';
import '../trilha/application/assistant_context_store.dart';
import '../trilha/application/trilha_hub_status.dart';
import '../trilha/application/trilha_section.dart';
import '../trilha/application/trilha_session.dart';
import '../trilha/data/assist_skills_writer_supabase.dart';
import '../trilha/domain/assist_skills_write.dart';
import '../trilha/presentation/trilha_chat_controller.dart';
import '../trilha/presentation/trilha_chat_view.dart';
import 'services/general_resume_export.dart';
import 'widgets/assistant_tab_layout.dart';
import 'widgets/curriculo_section_stepper.dart';
import 'widgets/curriculo_toggle.dart';
import 'widgets/fortalecer_perfil_disclosure.dart';
import 'widgets/general_resume_preview.dart';
import 'widgets/section_detail_sheet.dart';

/// Fábrica da sessão da trilha — injetável pra teste (evita Supabase).
typedef TrilhaSessionFactory = Future<TrilhaSession> Function(String userId);

/// Seam estreito do cutover 3.0B. A fábrica só pode ser avaliada quando o
/// gate composto do Assistente está ligado; com OFF, nem o writer é criado.
typedef ResumeTabAssistSkillsWriterFactory = AssistSkillsWriter Function();

AssistSkillsWriter? resolveResumeTabAssistSkillsWriter({
  required bool assistEnabled,
  required ResumeTabAssistSkillsWriterFactory factory,
}) {
  if (!assistEnabled) return null;
  return factory();
}

class ResumeTab extends StatefulWidget {
  const ResumeTab({
    super.key,
    this.sessionFactory,
    this.assistSkillsWriterFactory,
  });

  /// Só pra teste: substitui [buildTrilhaSession].
  final TrilhaSessionFactory? sessionFactory;

  /// Só pra teste: observa a criação do writer sem acessar Supabase.
  final ResumeTabAssistSkillsWriterFactory? assistSkillsWriterFactory;

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
      } catch (_) {
        /* sem provider (teste): ignora */
      }
      // ignore: unawaited_futures
      _refreshHubStatus();
    });
  }

  Future<TrilhaChatController> _load() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      return Future.error(StateError('Sem usuário autenticado'));
    }
    final assistEnabled = FeatureFlagsService.instance
        .isTrilhaAssistEnabledForUser(uid);
    final orch = TrilhaChatController(
      userId: uid,
      sessionBuilder: widget.sessionFactory ?? buildTrilhaSession,
      // Assistente de IA na barra (PLANO-ASSISTENTE, Fase A). Atrás da flag
      // `trilha_assist_v1`, aninhada em `trilha_coleta_v1`: qualquer uma OFF
      // mantém a barra no comportamento de hoje.
      assistEnabled: assistEnabled,
      assistantContextStore: assistEnabled
          ? SharedPreferencesAssistantContextStore()
          : null,
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
                label: m['label'] ?? field,
              );
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
                label: m['label'] ?? 'Experiência',
              );
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
      // Cutover 3.0B: somente este editor usa o apply/undo atômico com CAS e
      // recibo durável. OFF não instancia nem chama as RPCs novas.
      assistSkillsWriter: resolveResumeTabAssistSkillsWriter(
        assistEnabled: assistEnabled,
        factory:
            widget.assistSkillsWriterFactory ??
            () => AssistSkillsWriterSupabase(),
      ),
      assistSkillSuggester: () => assistSkillSuggestionsFor(uid),
      // Interesses e áreas ainda usam writers destrutivos no legado. A Fase 2
      // não os injeta no Assistente: interesses vão para Perfil → Dados e
      // áreas para Perfil → Objetivos até existir persistência transacional.
      assistLanguagesLoader: () => loadAssistLanguages(uid),
      assistLanguageUpserter: (name, level) async {
        await assistUpsertLanguage(uid, name, level);
        _scheduleProfileReload();
      },
      // Editar UM campo de item multi-campo (experiência/formação/cert).
      assistItemFieldReader: (kind, query, field) =>
          assistReadItemField(uid, kind, query, field),
      assistItemFieldWriter: (kind, id, field, value) async {
        await assistWriteItemField(uid, kind, id, field, value);
        _scheduleProfileReload();
      },
      // Grandes: ações de app. Vagas reais (lê o feed já filtrado pelo perfil),
      // navegar entre abas, exportar o PDF. Nenhuma muta o perfil → sem reload.
      assistJobsLoader: ({String? area, String? query, int limit = 5}) =>
          _loadJobsForAssistant(area: area, query: query, limit: limit),
      assistOpenTab: (tabKey) async {
        if (!mounted) return;
        final idx = _tabIndexForKey(tabKey);
        if (idx == null || idx == HomeTabs.resume) return;
        try {
          context.read<HomeViewModel>().requestTabChange(idx);
        } catch (_) {
          /* sem HomeViewModel (teste) */
        }
      },
      assistOpenCvLibrary: () async {
        if (!mounted) return;
        try {
          final home = context.read<HomeViewModel>();
          home.requestTabChange(HomeTabs.profile);
          // Sub-aba Currículos da ProfileScreen (Dados=0, Objetivos=1, CVs=2).
          home.requestProfileSubTab(2);
        } catch (_) {
          /* sem HomeViewModel (teste) */
        }
      },
      assistExportPdf: _exportForAssistant,
      // Widget de conflito: aplica UMA linha escolhida + recarrega o preview.
      assistConflictApplier: (row, value) async {
        final undo = await assistApplyConflictRow(uid, row, value);
        _scheduleProfileReload();
        if (undo == null) return null;
        return () async {
          await undo();
          _scheduleProfileReload();
        };
      },
      // Render estruturado: lacunas do perfil (% + o que falta) pro card.
      assistGapsLoader: () async {
        final g = await loadAssistGaps(uid);
        return AssistGaps(
          completionPercent: g.completionPercent,
          missing: [
            for (final m in g.missing)
              GapRow(
                key: m.key,
                tier: m.tier,
                label: m.label,
                section: m.section,
              ),
          ],
        );
      },
      // Card de vagas: abrir detalhe + salvar (like) por vaga.
      assistOpenJobDetail: _openJobFromAssistant,
      assistSaveJob: _saveJobFromAssistant,
      assistUnsaveJob: _unsaveJobFromAssistant,
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
          Analytics.shared.track(
            evTrilhaColetaStarted,
            props: {'source': 'resume_tab', 'total_steps': totalSteps},
          );
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
      } catch (_) {
        /* sem provider: ignora */
      }
      // O import mudou o perfil → recomputa a força honesta.
      // ignore: unawaited_futures
      _refreshHubStatus();
    }
    if (!orch.finished || _completionHandled) return;
    _completionHandled = true;
    // ignore: unawaited_futures
    Analytics.shared.track(
      evTrilhaColetaCompleted,
      props: {'answered': orch.answeredCount, 'source': 'resume_tab'},
    );
    try {
      // ignore: unawaited_futures
      context.read<ProfileEditorViewModel>().load();
    } catch (_) {
      /* sem provider: ignora */
    }
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
              key: const ValueKey('loading'),
              child: _loading(),
            );
          } else if (snap.hasError) {
            body = KeyedSubtree(key: const ValueKey('error'), child: _error());
          } else {
            body = KeyedSubtree(
              key: const ValueKey('ready'),
              child: _ready(snap.data!),
            );
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
          Text('Preparando o assistente…', style: AppTextStyles.bodyMd),
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
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.textTertiary,
              size: 40,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Não consegui carregar agora. Tenta de novo daqui a pouco.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.textSecondary,
              ),
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

    // FASE 2 (casa única): a composição/gating vive em [AssistantTabLayout]
    // (widget puro, testável sem Supabase). ON = conversa única (sem
    // CurriculoToggle e sem IndexedStack de prévia); o currículo geral (prévia
    // + export) passa a viver em Perfil → Currículos. OFF = shell legado
    // (conversa + prévia + toggle) preservado como rollback.
    return AssistantTabLayout(
      assistEnabled: orch.assistEnabled,
      keyboardOpen: keyboardOpen,
      assistantTopBar: (_) => _assistantTopBar(orch, profileVM),
      legacyTopBar: (_) => _legacyTopBar(orch, profileVM),
      conversa: (_) => _conversaView(orch, profileVM),
      preview: (_) => _curriculoView(),
      tabIndex: _tab,
    );
  }

  // ── Topo do Assistente: stepper compartilhado + top bars por flag ──────────

  /// Stepper reativo ao orquestrador (notifica a cada passo). Compartilhado
  /// entre o Assistente conversa-única e o shell legado — é contexto da coleta,
  /// não uma segunda casa do perfil (§3.4).
  Widget _stepper(
    TrilhaChatController orch,
    ProfileEditorViewModel profileVM, {
    bool collapsible = false,
  }) {
    return AnimatedBuilder(
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
        final stepper = CurriculoSectionStepper(
          statuses: statuses,
          // Toque numa seção → sheet de verificação do que foi coletado.
          onSectionTap: (section) => showSectionDetailSheet(
            context,
            section: section,
            status: statuses[section] ?? SectionStatus.pending,
            vm: profileVM,
          ),
        );
        if (!collapsible) return stepper;
        final completedCount = kStepperSections
            .where((section) => statuses[section] == SectionStatus.done)
            .length;
        return FortalecerPerfilDisclosure(
          completedCount: completedCount,
          totalCount: kStepperSections.length,
          child: stepper,
        );
      },
    );
  }

  // ── Topo (flag ON): título + "Ver meu perfil" + stepper (SEM toggle) ────────
  Widget _assistantTopBar(
    TrilhaChatController orch,
    ProfileEditorViewModel profileVM,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Assistente', style: AppTextStyles.headlineMd),
              ),
              _verMeuPerfilButton(),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _stepper(orch, profileVM, collapsible: true),
        ],
      ),
    );
  }

  /// Ação compacta no header do Assistente → leva a Perfil → Dados (sub-aba 0),
  /// a única tela completa de edição do perfil. Reusa requestTabChange +
  /// requestProfileSubTab (sem rota nova).
  Widget _verMeuPerfilButton() {
    return TextButton.icon(
      onPressed: () {
        try {
          final home = context.read<HomeViewModel>();
          home.requestTabChange(HomeTabs.profile);
          home.requestProfileSubTab(0);
        } catch (_) {
          /* sem HomeViewModel (teste) */
        }
      },
      icon: const Icon(Icons.person_outline_rounded, size: 18),
      label: const Text('Ver meu perfil'),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  // ── Topo (flag OFF / rollback): título + stepper + CurriculoToggle ──────────
  Widget _legacyTopBar(
    TrilhaChatController orch,
    ProfileEditorViewModel profileVM,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Assistente', style: AppTextStyles.headlineMd),
          const SizedBox(height: AppSpacing.md),
          _stepper(orch, profileVM),
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
    TrilhaChatController orch,
    ProfileEditorViewModel profileVM,
  ) {
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

  // A UI da prévia (header + seções + empty state) e a lógica de export foram
  // extraídas pra [GeneralResumePreview] e [GeneralResumeExport] (Fase 2) — a
  // MESMA implementação usada por Perfil → Currículos. Aqui, no rollback (flag
  // OFF), só compomos os dois no shell legado (conversa | prévia via toggle).
  Widget _curriculoView() {
    return Column(
      children: [
        Expanded(child: GeneralResumePreview(hubStatus: _hubStatus)),
        const GeneralResumeExportBar(),
      ],
    );
  }

  // ── Grandes: callbacks de ação do assistente ──────────────────────────────

  /// `export_pdf`: desfecho REAL (vazio/falha/ok) pro assistente não confirmar
  /// sucesso em cima de um erro. Usa a MESMA implementação compartilhada do
  /// botão "Exportar PDF" de Perfil → Currículos ([GeneralResumeExport.export]).
  Future<AssistExportOutcome> _exportForAssistant() {
    if (!mounted) return Future.value(AssistExportOutcome.failed);
    return GeneralResumeExport.export(context);
  }

  /// `open_tab`: mapeia o tabKey (pt-BR/en) pro índice da aba. null ⇒ não
  /// reconhecido. Índice 1 aceita "salvas" e "candidaturas" (rótulo alterna
  /// pela flag, mas a aba é a mesma).
  int? _tabIndexForKey(String tabKey) {
    switch (tabKey.trim().toLowerCase()) {
      case 'vagas':
      case 'jobs':
      case 'feed':
        return HomeTabs.jobs;
      case 'salvas':
      case 'candidaturas':
      case 'saved':
      case 'applications':
        return HomeTabs.saved;
      case 'curriculo':
      case 'currículo':
      case 'resume':
        return HomeTabs.resume;
      case 'perfil':
      case 'profile':
        return HomeTabs.profile;
      default:
        return null;
    }
  }

  /// `show_jobs`: lê o feed REAL (já filtrado pelo perfil), aplica filtro
  /// opcional por área/texto (client-side), resolve o match de um pool pequeno
  /// do topo (o feed já vem rankeado) e devolve o top N reordenado por score.
  Future<AssistJobsResult> _loadJobsForAssistant({
    String? area,
    String? query,
    required int limit,
  }) async {
    if (!mounted) return const AssistJobsResult(hasResume: false, jobs: []);
    final jobsVM = context.read<JobsViewModel>();
    final hasResume = context.read<UserViewModel>().hasResume;
    // Garante o feed carregado mesmo se o user nunca abriu a aba Vagas (idempotente).
    if (jobsVM.jobs.isEmpty) {
      try {
        await jobsVM.init();
      } catch (_) {
        /* best-effort */
      }
    }
    if (!mounted) return AssistJobsResult(hasResume: hasResume, jobs: const []);
    // listJobs exclui as vagas que o user já swipou (curtiu/descartou) — não
    // faz sentido "recomendar" uma vaga que ele acabou de rejeitar.
    var candidates = jobsVM.listJobs;
    if (area != null && area.isNotEmpty) {
      candidates = candidates
          .where((j) => FilterHelpers.isAreaMatch(j.area, [area]))
          .toList();
    }
    if (query != null && query.isNotEmpty) {
      final q = FilterHelpers.normalize(query);
      candidates = candidates
          .where(
            (j) => FilterHelpers.normalize(
              '${j.title} ${j.companyName}',
            ).contains(q),
          )
          .toList();
    }
    // Área FORA do perfil (ex.: "tem vaga de marketing?" mas o perfil é Finanças):
    // o feed filtrado não tem essas vagas → busca no CATÁLOGO inteiro por área.
    var outOfProfile = '';
    if (candidates.isEmpty && area != null && area.isNotEmpty) {
      try {
        final uid = jobsVM.userId;
        if (uid != null) {
          final cat = await JobRepository().fetchJobs(
            preferences: UserJobPreferences(userId: uid, areas: [area]),
          );
          if (!mounted) {
            return AssistJobsResult(hasResume: hasResume, jobs: const []);
          }
          if (cat.isNotEmpty) {
            outOfProfile = area;
            candidates = (query != null && query.isNotEmpty)
                ? cat
                      .where(
                        (j) => FilterHelpers.normalize(
                          '${j.title} ${j.companyName}',
                        ).contains(FilterHelpers.normalize(query)),
                      )
                      .toList()
                : cat;
          }
        }
      } catch (_) {
        /* best-effort */
      }
    }
    // Resolve o match só de um pool pequeno do topo (feed já vem rankeado), em
    // PARALELO (Future.wait) pra não somar N latências de rede em série.
    final pool = candidates.take(12).toList();
    final results = await Future.wait(
      pool.map((job) async {
        try {
          final m = await jobsVM.resolveMatchForJob(job, hasResume: hasResume);
          return (
            job: job,
            score: m.score,
            hasScore: !m.isNoResume && !m.isUnknown,
          );
        } catch (_) {
          return null; // sem score — cai fora do topo
        }
      }),
    );
    if (!mounted) return AssistJobsResult(hasResume: hasResume, jobs: const []);
    final scored = results
        .whereType<({Job job, int score, bool hasScore})>()
        .toList();
    scored.sort((a, b) => b.score.compareTo(a.score));
    final rows = scored
        .take(limit)
        .map(
          (e) => AssistJobRow(
            id: e.job.id,
            title: e.job.title,
            company: e.job.companyName,
            area: e.job.area ?? '',
            score: e.score,
            hasScore: e.hasScore,
          ),
        )
        .toList();
    return AssistJobsResult(
      hasResume: hasResume,
      jobs: rows,
      outOfProfileArea: outOfProfile,
    );
  }

  /// Card de vagas: abre o DETALHE de uma vaga (por id) num bottom sheet.
  Future<void> _openJobFromAssistant(String jobId) async {
    if (!mounted) return;
    final jobsVM = context.read<JobsViewModel>();
    Job? job;
    try {
      job = await jobsVM.fetchJobById(jobId);
    } catch (_) {
      /* vaga sumiu */
    }
    if (!mounted || job == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => JobDetailsSheet(job: job!),
    );
  }

  /// Card de vagas: SALVA uma vaga (like) → vai pra Vagas Salvas. Retorna true
  /// SÓ se persistiu (vaga sumiu / já swipada / rede caiu ⇒ false).
  Future<bool> _saveJobFromAssistant(String jobId) async {
    if (!mounted) return false;
    final jobsVM = context.read<JobsViewModel>();
    try {
      final job = await jobsVM.fetchJobById(jobId);
      if (job == null) return false; // vaga desativada/sumiu
      // swipeJobFromList devolve true só se o recordSwipe PERSISTIU (reverte o
      // estado otimista e devolve false em falha de rede). NÃO checar likedJobs
      // aqui: o loadLikedJobs roda sem await → a lista ainda não atualizou.
      return await jobsVM.swipeJobFromList(job, 'liked');
    } catch (_) {
      return false;
    }
  }

  /// Card de vagas: DES-SALVA uma vaga (tira de Vagas Salvas). Robusto por ID —
  /// não depende de likedJobs estar carregado (apaga o swipe direto).
  Future<bool> _unsaveJobFromAssistant(String jobId) async {
    if (!mounted) return false;
    final jobsVM = context.read<JobsViewModel>();
    try {
      return await jobsVM.unsaveJobFromList(jobId);
    } catch (_) {
      return false;
    }
  }
}
