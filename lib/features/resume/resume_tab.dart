import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../home/home_viewmodel.dart';
import '../home/tracks_tab.dart';
import '../profile/profile_viewmodel.dart';
import '../tutorial/tutorial_keys.dart';
import 'resume_viewmodel.dart';
import 'widgets/import_cv_button.dart';
import '../../services/cv_import_service.dart';
import '../../services/feature_flags_service.dart';
import '../../core/widgets/pii_mask.dart';
import '../../core/theme/theme.dart';

/// Entry-point da aba Currículo (após a unificação Trilha + Currículo).
///
/// Estados:
///  - **Entry**: hero + 2 cards (construir pela trilha / importar PDF).
///    Texto e badges dos cards mudam conforme estado do usuário.
///  - **Trilha embutida**: quando user toca em "Construir pela trilha",
///    renderiza [TracksTab] dentro do mesmo Scaffold com seta de voltar.
///    Bottom nav segue visível porque o Scaffold pai (HomeScreen) o segura.
///
/// Toda criação/edição efetiva do CV (preview, templates, export, idioma)
/// vive agora na aba Perfil → [ResumeDetailScreen], acessada ao tocar
/// num card da biblioteca.
class ResumeTab extends StatefulWidget {
  const ResumeTab({super.key});

  @override
  State<ResumeTab> createState() => _ResumeTabState();
}

class _ResumeTabState extends State<ResumeTab> {
  bool _showingTracks = false;

  @override
  void initState() {
    super.initState();
    // O consenso de IA agora é solicitado no fim da trilha (no botão
    // "VER MEU CURRÍCULO" do PhaseCompletionWidget), garantindo que ele
    // apareça em contexto certo — não quando o user entra na aba.
  }

  void _enterTracks() {
    setState(() => _showingTracks = true);
  }

  void _exitTracks() {
    setState(() => _showingTracks = false);
  }

  Future<void> _onImported(String? newResumeId) async {
    if (!mounted) return;
    final homeVM = context.read<HomeViewModel>();

    // Hand off animation + tab switch + highlight to HomeScreen atomically.
    if (newResumeId != null) {
      homeVM.announceCvCreated(
        targetTab: HomeTabs.profile,
        highlightId: newResumeId,
      );
    } else {
      homeVM.requestTabChange(HomeTabs.profile);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Transição entre entry-state e trilha:
    // - Trilha entra com scale 0.92 → 1.0 + fade in (sensação de "abrir")
    // - Entry-state só faz fade out/in suave por baixo
    // Volta é mais rápida (280ms vs 380ms) pra sensação snappier.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      reverseDuration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.center,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        final key = child.key;
        final isTracks = key is ValueKey<String> && key.value == 'tracks';
        if (isTracks) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1.0).animate(
                CurvedAnimation(
                    parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          );
        }
        // Entry-state: só fade
        return FadeTransition(opacity: animation, child: child);
      },
      child: _showingTracks
          ? KeyedSubtree(
              key: const ValueKey<String>('tracks'),
              child: TracksTab(onBack: _exitTracks),
            )
          : KeyedSubtree(
              key: const ValueKey<String>('entry'),
              child: Consumer2<ResumeViewModel, ProfileViewModel>(
                builder: (context, resumeVM, profileVM, _) {
                  return PiiMask(
                    child: Scaffold(
                      backgroundColor: AppColors.background,
                      body: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                          child: _buildEntryState(
                              context, resumeVM, profileVM),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildEntryState(
    BuildContext context,
    ResumeViewModel resumeVM,
    ProfileViewModel profileVM,
  ) {
    const indigo = AppColors.primary;
    const purple = AppColors.primary;

    final isCourseCompleted = resumeVM.isCourseCompleted;
    final hasImportedBefore = profileVM.savedResumes
        .any((r) => r.title.startsWith(kImportedResumeBaseTitle));

    // Remoção reversível da trilha (flag binária remota). OFF (default) = card
    // "Construir pela trilha" escondido → aba fica só com Importar CV. Voltar =
    // ligar resume_trail_enabled no banco (sem rebuild). Onboarding não afetado.
    final trailEnabled = FeatureFlagsService.instance
        .isGloballyEnabled(FeatureFlagKeys.resumeTrailEnabled);

    final heroTitle = isCourseCompleted
        ? 'Seu currículo já está pronto'
        : (trailEnabled
            ? 'Dois jeitos de ter seu CV pronto'
            : 'Comece seu currículo');
    final heroSubtitle = isCourseCompleted
        ? (trailEnabled
            ? 'Atualize pela trilha ou suba uma nova versão.'
            : 'Suba uma nova versão quando quiser.')
        : (trailEnabled
            ? 'Escolha o caminho que faz mais sentido agora.'
            : 'Importe seu PDF e desbloqueie adaptação por vaga e match.');

    // Layout: tamanhos naturais (sem Expanded interno), espaço extra
    // distribuído ENTRE os blocos via spaceBetween. Em telas grandes
    // ganha respiro; em telas pequenas continua compacto.
    return Column(
      mainAxisAlignment:
          trailEnabled ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Hero
        Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [indigo, purple],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: indigo.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 12),
                    const SizedBox(width: 5),
                    Text(
                      isCourseCompleted
                          ? 'JORNADA CONCLUÍDA'
                          : 'COMECE SEU CURRÍCULO',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                heroTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                  letterSpacing: -0.4,
                  fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                heroSubtitle,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontSize: 12.5,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),

        // Card Trilha — escondido quando a flag resume_trail_enabled está OFF
        // (remoção reversível). Espaçador no lugar pra não colar o import no hero.
        if (trailEnabled)
          KeyedSubtree(
            key: TutorialKeys.trailCard,
            child: _buildPathCard(
              badge: isCourseCompleted ? 'JORNADA CONCLUÍDA' : 'RECOMENDADO',
              badgeColor: AppColors.success,
              icon: Icons.route_rounded,
              iconBg: indigo,
              title: isCourseCompleted
                  ? 'Atualizar pela trilha'
                  : 'Construir pela trilha',
              description: isCourseCompleted
                  ? 'Volte às fases pra atualizar — o CV é regerado e salvo no Perfil.'
                  : 'Responda perguntas estilo Duolingo. A IA monta seu CV com bullets Harvard.',
              highlights: isCourseCompleted
                  ? const [
                      'Reabra qualquer fase pra editar',
                      'Cada finalização vira nova versão',
                    ]
                  : const [
                      'Sem precisar escrever bullets',
                      'Templates ATS-friendly',
                    ],
              ctaLabel: isCourseCompleted ? 'Abrir trilha' : 'Continuar trilha',
              ctaIcon: Icons.arrow_forward_rounded,
              onCtaTap: _enterTracks,
              ctaVariant: _CtaVariant.gradient,
            ),
          )
        else
          const SizedBox(height: 16),

        // Card Import — tamanho natural
        KeyedSubtree(
          key: TutorialKeys.importCard,
          child: _buildPathCard(
            badge: hasImportedBefore ? 'JÁ IMPORTADO' : 'MAIS RÁPIDO',
          badgeColor: hasImportedBefore
              ? AppColors.primary
              : AppColors.warning,
          icon: Icons.upload_file_rounded,
          iconBg: AppColors.info,
          title: hasImportedBefore
              ? 'Importar outro CV'
              : 'Importar CV em PDF',
          description: hasImportedBefore
              ? 'Suba uma nova versão. As anteriores continuam salvas na biblioteca.'
              : 'Já tem um currículo? Suba o PDF e desbloqueie a adaptação por vaga.',
          highlights: hasImportedBefore
              ? const [
                  'Cada upload vira nova entrada',
                  'IA atualiza match com o novo CV',
                ]
              : const [
                  'Pronto em 5 segundos',
                  'IA lê seus dados automaticamente',
                ],
            ctaLabel: 'Importar PDF',
            ctaIcon: Icons.upload_file_rounded,
            onCtaTap: null,
            customCta: ImportCvButton(onImported: _onImported),
            ctaVariant: _CtaVariant.custom,
          ),
        ),
      ],
    );
  }

  Widget _buildPathCard({
    required String badge,
    required Color badgeColor,
    required IconData icon,
    required Color iconBg,
    required String title,
    required String description,
    required List<String> highlights,
    required String ctaLabel,
    required IconData ctaIcon,
    required VoidCallback? onCtaTap,
    required _CtaVariant ctaVariant,
    Widget? customCta,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header: icon + badge + title
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBg.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconBg, size: 20),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: badgeColor,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3,
                        fontFamily: 'Outfit',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Description
          Text(
            description,
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          // Highlights compactos (2 bullets)
          ...highlights.map((h) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_rounded, size: 14, color: badgeColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        h,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 10),
          // CTA
          if (ctaVariant == _CtaVariant.gradient)
            _buildCtaGradient(label: ctaLabel, icon: ctaIcon, onTap: onCtaTap)
          else if (ctaVariant == _CtaVariant.custom && customCta != null)
            customCta,
        ],
      ),
    );
  }

  Widget _buildCtaGradient({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 17),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _CtaVariant { gradient, custom }
