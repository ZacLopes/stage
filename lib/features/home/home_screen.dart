import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../profile/profile_screen.dart';
import '../resume/resume_tab.dart';
import '../resume/resume_viewmodel.dart';
import '../jobs/screens/jobs_swipe_screen.dart';
import '../jobs/screens/liked_jobs_screen.dart';
import '../jobs/jobs_viewmodel.dart';
import '../jobs/job_swipe_context.dart';
import '../jobs/utils/pending_apply.dart';
import '../jobs/widgets/apply_return_prompt_sheet.dart';
import '../shared/widgets/cv_landing_overlay.dart';
import '../tutorial/tutorial_controller.dart';
import '../tutorial/tutorial_keys.dart';
import '../tutorial/tutorial_step.dart';
import '../../core/analytics/screen_tracking.dart';
import '../../services/analytics_service.dart';
import '../../services/feature_flags_service.dart';
import '../../services/notifications_service.dart';
import 'home_viewmodel.dart';
import '../../core/theme/theme.dart';
import 'widgets/pending_upload_banner.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with ScreenTrackingMixin {
  @override
  String get screenName => 'home';

  int _currentIndex = 0;
  /// Marca o último tab switch pra calcular `duration_on_from_ms` no
  /// próximo. Plano v2 B.13 — métrica de stickiness por aba.
  DateTime? _lastTabEnteredAt = DateTime.now();
  final PageController _pageController = PageController();

  /// FASE 3 (T3.2): observer de foreground pro prompt de retorno pós-apply.
  /// Vive na camada UI (HomeScreen tem Navigator/context) — o observer do
  /// analytics_service é só telemetria, sem BuildContext.
  late final _HomeForegroundObserver _foregroundObserver;
  bool _applyPromptInFlight = false;

  @override
  void initState() {
    super.initState();

    _foregroundObserver =
        _HomeForegroundObserver(onResumed: _maybeShowApplyPrompt);
    WidgetsBinding.instance.addObserver(_foregroundObserver);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Listener de deep-nav tem que entrar antes de qualquer outra coisa
      // pra capturar troca de aba disparada pelo tutorial.
      context.read<HomeViewModel>().addListener(_onHomeViewModelChange);

      // Escuta pedidos de replay vindos de Configurações → Tutorial.
      context.read<TutorialController>().addListener(_onTutorialControllerChange);

      // Prompt iOS — só push aqui. ATT (App Tracking Transparency) saiu
      // do home open e foi pro primeiro engajamento real (primeiro swipe
      // em jobs_swipe_screen) — Apple recomenda pedir tracking DEPOIS que
      // o user entendeu o contexto do app, não logo na entrada. Ganha
      // opt-in rate maior, melhora atribuição da Meta Ads.
      //
      //   T+4000ms  → Push (OneSignal) - notificação de vagas
      //
      // Flag de "já pediu" persistido — não re-prompt em re-aberturas.
      Future.delayed(const Duration(milliseconds: 4000), () {
        if (!mounted) return;
        final uid = Supabase.instance.client.auth.currentUser?.id;
        // ignore: unawaited_futures
        NotificationsService.shared.requestPermissionIfNotShown(uid);
      });

      // Tutorial: roda 1x na primeira vez que o user chega na home.
      // (Pode ser re-disparado depois via Configurações → Tutorial.)
      final alreadySeen = await TutorialController.hasSeen();
      if (!mounted || alreadySeen) return;
      // Pequeno delay pra deixar a UI assentar antes de pôr overlay.
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      _startTutorial();
    });
  }

  void _onTutorialControllerChange() {
    if (!mounted) return;
    final tutorial = context.read<TutorialController>();
    if (tutorial.replayRequested && !tutorial.isRunning) {
      tutorial.consumeReplayRequest();
      // Pequeno delay pra deixar a transição do pop do Settings terminar.
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) _startTutorial();
      });
    }
  }

  /// Inicia (ou reinicia) o tutorial dinâmico — a sequência leva o user
  /// pelas 4 abas e pelos elementos-chave (botão IA, cards da Currículo).
  /// Cada passo cuida da troca de aba via `onEnter`.
  void _startTutorial() {
    final tutorial = context.read<TutorialController>();
    tutorial.start(steps: _buildTutorialSteps());
  }

  List<TutorialStep> _buildTutorialSteps() {
    Future<void> goTo(int index) async {
      _navigateToPage(index);
    }

    return [
      const TutorialStep(
        title: 'Bem-vindo ao Stage 👋',
        description:
            'Vou te mostrar como o app funciona em menos de 1 minuto. '
            'Você pode pular a qualquer momento.',
        anchor: TutorialTooltipAnchor.center,
      ),
      TutorialStep(
        title: 'Aba Vagas',
        description:
            'Aqui você descobre vagas e estágios. Deslize → pra salvar, ← pra '
            'pular. O selo no canto do card diz o quanto a vaga combina com '
            'seu perfil: Alta, Média ou Baixa. Toque na vaga pra ver por quê.',
        targetKey: TutorialKeys.jobsTab,
        onEnter: () => goTo(HomeTabs.jobs),
      ),
      TutorialStep(
        title: 'Adapta CV pra vaga com IA',
        description:
            'Esse botão central adapta seu currículo pra vaga que tá vendo agora — '
            'destaca o que importa pro recrutador.',
        targetKey: TutorialKeys.aiButton,
        padding: 12,
        radius: 40,
        onEnter: () => goTo(HomeTabs.jobs),
      ),
      TutorialStep(
        title: 'Acompanhe suas vagas',
        description:
            'Suas vagas salvas ficam aqui. Use "Marcar como enviada" quando se '
            'candidatar pra acompanhar o status.',
        targetKey: TutorialKeys.savedTab,
        onEnter: () => goTo(HomeTabs.saved),
      ),
      TutorialStep(
        title: 'Aba Assistente',
        description:
            'Aqui o assistente conversa com você pra completar seu perfil — '
            'responda as perguntas e veja seu perfil ficar mais forte. Dá pra '
            'gerar e exportar seu currículo em PDF quando quiser.',
        targetKey: TutorialKeys.resumeTab,
        onEnter: () => goTo(HomeTabs.resume),
      ),
      TutorialStep(
        title: 'Aba Perfil',
        description:
            'Aqui estão seus dados, objetivos e currículos. Os objetivos '
            'alimentam o match — ajuste quando eles mudarem.',
        targetKey: TutorialKeys.profileTab,
        onEnter: () => goTo(HomeTabs.profile),
      ),
      TutorialStep(
        title: 'Pronto! Por onde quer começar?',
        description:
            'Pode rever esse tutorial em Perfil → Configurações → Tutorial.',
        anchor: TutorialTooltipAnchor.center,
        finalChoices: [
          TutorialFinalChoice(
            label: 'Ver vagas',
            icon: Icons.work_rounded,
            onTap: () async {
              // Encerra o tutorial via controller (emite tutorial_completed
              // com flow+duration_ms+next_action via typed method — não
              // mais raw track).
              await context
                  .read<TutorialController>()
                  .finishWithChoice(nextAction: 'jobs');
              if (!mounted) return;
              goTo(HomeTabs.jobs);
            },
          ),
          TutorialFinalChoice(
            label: 'Falar com o assistente',
            icon: Icons.auto_awesome_rounded,
            onTap: () async {
              await context
                  .read<TutorialController>()
                  .finishWithChoice(nextAction: 'resume');
              if (!mounted) return;
              goTo(HomeTabs.resume);
            },
          ),
        ],
      ),
    ];
  }

  bool _runningLanding = false;

  void _onHomeViewModelChange() {
    if (!mounted) return;
    final homeVM = context.read<HomeViewModel>();

    if (homeVM.pendingLandingAnimation && !_runningLanding) {
      _runningLanding = true;
      homeVM.clearLandingAnimation();
      final pendingTab = homeVM.pendingTabIndex;
      // Don't clear highlight here — ProfileScreen reads it on mount.
      if (pendingTab != null) {
        homeVM.clearPendingTabChange();
      }

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) {
          _runningLanding = false;
          return;
        }
        await playCvLandingAnimation(
          context,
          profileIconKey: homeVM.profileNavKey,
        );
        if (!mounted) {
          _runningLanding = false;
          return;
        }
        if (pendingTab != null) {
          _navigateToPage(pendingTab);
        }
        // Apply the deferred highlight now that ProfileScreen is visible.
        homeVM.consumeDeferredHighlight();
        _runningLanding = false;
      });
      return;
    }

    if (homeVM.pendingTabIndex != null) {
      _navigateToPage(homeVM.pendingTabIndex!);
      homeVM.clearPendingTabChange();
    }
  }

  /// Mapa estável tab → screen_name pra PostHog. Mantido aqui (não no
  /// `HomeTabs`) porque é convenção de telemetria, não de domínio.
  static const Map<int, String> _tabScreenNames = {
    HomeTabs.jobs: 'jobs_swipe',
    HomeTabs.saved: 'jobs_liked',
    HomeTabs.resume: 'resume_tab',
    HomeTabs.profile: 'profile',
  };

  void _navigateToPage(int index) {
    if (!mounted) return; // Guard: state may be stale from an old closure
    final previousIndex = _currentIndex;
    setState(() {
      _currentIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );

    // Refresh resume data when entering the Currículo tab so dynamic
    // card text (e.g. "Atualizar pela trilha") reflects current state.
    if (index == HomeTabs.resume) {
       context.read<ResumeViewModel>().loadResumeData();
    }

    // Telemetria de troca de aba — dispara `$screen` com o nome real da
    // tab destino. `ScreenTrackingMixin` cobre a PRIMEIRA visita (initState),
    // mas com AutomaticKeepAliveClientMixin no JobsSwipeScreen o State
    // não recria em re-visitas, então este emit é o que mede stickiness
    // por aba e tempo entre tabs. Emitir só em troca real, não em re-tap
    // da mesma aba.
    if (previousIndex != index) {
      final name = _tabScreenNames[index];
      if (name != null) {
        // ignore: unawaited_futures
        Analytics.shared.screen(name);
      }
      // B.13 do plano v2 — nav_tab_switched com duration_on_from_ms
      // (tempo gasto na aba anterior). Permite construir tab switch matrix
      // + stickiness por aba.
      final from = _tabScreenNames[previousIndex] ?? 'unknown';
      final to = _tabScreenNames[index] ?? 'unknown';
      final lastEntered = _lastTabEnteredAt;
      final durationOnFromMs = lastEntered != null
          ? DateTime.now().difference(lastEntered).inMilliseconds
          : null;
      _lastTabEnteredAt = DateTime.now();
      // ignore: unawaited_futures
      Analytics.shared.navTabSwitched(
        fromTab: from,
        toTab: to,
        durationOnFromMs: durationOnFromMs,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_foregroundObserver);
    // Remove the listeners safely — the viewmodels outlive this widget
    try {
      context.read<HomeViewModel>().removeListener(_onHomeViewModelChange);
      context.read<TutorialController>().removeListener(_onTutorialControllerChange);
    } catch (_) {}
    _pageController.dispose();
    super.dispose();
  }

  /// FASE 3 (T3.2): no foreground, decide e mostra o prompt de retorno se há um
  /// apply pendente na janela. Único disparo por vez (`_applyPromptInFlight`).
  Future<void> _maybeShowApplyPrompt() async {
    if (_applyPromptInFlight || !mounted) return;
    // T3.2 atrás da MESMA flag do tracker (applications_tracker_v1). OFF = sem
    // prompt — o aceite de ≥30% conta a partir da ATIVAÇÃO da flag.
    final trackerOn = FeatureFlagsService.instance.isEnabledForUser(
      FeatureFlagKeys.applicationsTrackerV1,
      Supabase.instance.client.auth.currentUser?.id,
    );
    if (!trackerOn) return;
    final pending = await JobSwipeContext.shared.readPendingApply();
    if (pending == null || !mounted) return;

    final decision = pendingApplyDecision(pending, DateTime.now());
    switch (decision) {
      case PendingApplyDecision.wait:
        return;
      case PendingApplyDecision.expired:
        await JobSwipeContext.shared.clearPendingApply();
        return;
      case PendingApplyDecision.show:
        break;
    }

    _applyPromptInFlight = true;
    try {
      final isReask = pending.reaskAfterMs != null;
      // ignore: unawaited_futures
      Analytics.shared.jobApplyReturned(jobId: pending.jobId);
      // ignore: unawaited_futures
      Analytics.shared.applyPromptShown(jobId: pending.jobId, isReask: isReask);
      if (!mounted) return;
      final outcome = await showApplyReturnPrompt(context, pending: pending);
      await _handleApplyOutcome(pending, outcome);
    } finally {
      _applyPromptInFlight = false;
    }
  }

  Future<void> _handleApplyOutcome(
    PendingApply pending,
    ApplyPromptOutcome? outcome,
  ) async {
    switch (outcome) {
      case ApplyConfirmed():
        // ignore: unawaited_futures
        Analytics.shared.applyConfirmed(jobId: pending.jobId);
        if (mounted) {
          await context
              .read<JobsViewModel>()
              .markAppliedFromPrompt(pending.jobId);
        }
        await JobSwipeContext.shared.clearPendingApply();
      case ApplyAbandoned(:final reason):
        // ignore: unawaited_futures
        Analytics.shared.applyAbandonReason(
          jobId: pending.jobId,
          reason: reason.id,
          jobSource: pending.source,
        );
        await JobSwipeContext.shared.clearPendingApply();
      case ApplyLater():
        await JobSwipeContext.shared.scheduleReask();
      case null:
        // Dispensado (tap fora): mantém o pending — a janela (30min ou reask)
        // expira sozinha; não re-mostra agressivamente neste foreground.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final homeVM = context.read<HomeViewModel>();

    final List<Widget> tabs = const [
      JobsSwipeScreen(),
      LikedJobsScreen(),
      ResumeTab(),
      ProfileScreen(),
    ];

    return Scaffold(
      // Cor da status bar muda com a tab ativa: o SafeArea pinta o top inset
      // com a cor do Scaffold pai, então cada tab "pede" a cor que combina
      // com seu corpo. Vagas usa primarySoft (azul claro, topo do gradient).
      // Salvas/Currículo/Perfil usam background (cinza neutro) — mesmo do
      // body delas, sem faixa fora de tom.
      backgroundColor: _currentIndex == HomeTabs.jobs
          ? AppColors.primarySoft
          : AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Banner de PDF pendente — só aparece se o upload do CV durante
            // o onboarding falhou (rede ruim, Storage indisponível). Mostra
            // botão "Tentar agora" que reupload usando bytes do cache local.
            // Se não há pending, renderiza SizedBox.shrink() — zero overhead.
            const PendingUploadBanner(),
            // F8 da reformulação: banner persistente removido. O CV adaptado
            // agora é salvo automaticamente na biblioteca com o nome da vaga
            // (source='adapted') quando o user tap "Aprovar e baixar" na
            // preview screen. Não há mais o problema de "perdi minha adaptação"
            // — ela fica permanente. O PendingAdaptedCvTracker continua vivo
            // mas sem UI visual no home.
            Expanded(
              child: PageView(
                controller: _pageController,
                physics:
                    const NeverScrollableScrollPhysics(), // Disable swipe
                onPageChanged: (index) {
                  if (_currentIndex != index) {
                    setState(() => _currentIndex = index);
                  }
                },
                children: tabs,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 10,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            // Haptic sutil só quando troca de aba (não bate tap repetido na mesma).
            if (index != _currentIndex) {
              HapticFeedback.selectionClick();
            }
            _navigateToPage(index);
          },
          backgroundColor: AppColors.surface,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textDisabled,
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          // Atenção: as TutorialKeys ficam no `activeIcon` (não no `icon`).
          // BottomNavigationBar só renderiza um dos dois por item — e como
          // o tutorial sempre navega pra aba ANTES de destacá-la, na hora
          // da medição a aba alvo está selecionada → activeIcon presente.
          // A profileNavKey (usada pela animação do CV voando) fica no
          // `icon` porque a animação dispara quando o user NÃO está no
          // Perfil ainda.
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.work_outline),
              activeIcon: Padding(
                key: TutorialKeys.jobsTab,
                padding: EdgeInsets.zero,
                child: const Icon(Icons.work),
              ),
              label: 'Vagas',
            ),
            BottomNavigationBarItem(
              icon: _PendingBadgeIcon(
                icon: Icons.bookmark_border,
                count: context.watch<JobsViewModel>().pendingCount,
              ),
              activeIcon: Padding(
                key: TutorialKeys.savedTab,
                padding: EdgeInsets.zero,
                child: _PendingBadgeIcon(
                  icon: Icons.bookmark,
                  count: context.watch<JobsViewModel>().pendingCount,
                ),
              ),
              // FASE 3 (T3.1): aba vira "Candidaturas" com a flag ON; OFF = Salvas.
              label: FeatureFlagsService.instance.isEnabledForUser(
                FeatureFlagKeys.applicationsTrackerV1,
                Supabase.instance.client.auth.currentUser?.id,
              )
                  ? 'Candidaturas'
                  : 'Salvas',
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.auto_awesome_outlined),
              activeIcon: Padding(
                key: TutorialKeys.resumeTab,
                padding: EdgeInsets.zero,
                child: const Icon(Icons.auto_awesome),
              ),
              label: 'Assistente',
            ),
            BottomNavigationBarItem(
              icon: Padding(
                // profileNavKey é da animação "CV voando" (dispara enquanto
                // o user NÃO está no Perfil → icon não-ativo é o renderizado)
                key: homeVM.profileNavKey,
                padding: EdgeInsets.zero,
                child: const Icon(Icons.person_outline),
              ),
              activeIcon: Padding(
                key: TutorialKeys.profileTab,
                padding: EdgeInsets.zero,
                child: const Icon(Icons.person),
              ),
              label: 'Perfil',
            ),
          ],
        ),
      ),
    );
  }
}

/// Ícone do tab "Curtidas" com badge da contagem de vagas pendentes
/// (curtidas - aplicadas). Some quando count == 0.
class _PendingBadgeIcon extends StatelessWidget {
  final IconData icon;
  final int count;
  const _PendingBadgeIcon({required this.icon, required this.count});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return Icon(icon);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        Positioned(
          right: -8,
          top: -4,
          child: Container(
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.error,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.surface, width: 1.5),
            ),
            child: Center(
              child: Text(
                count > 99 ? '99+' : '$count',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  color: AppColors.textOnDark,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// FASE 3 (T3.2): observer leve de foreground. Classe dedicada (em vez de mixar
/// WidgetsBindingObserver no State) pra não colidir com o ScreenTrackingMixin.
class _HomeForegroundObserver with WidgetsBindingObserver {
  final VoidCallback onResumed;
  _HomeForegroundObserver({required this.onResumed});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResumed();
  }
}
