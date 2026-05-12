import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../home/home_viewmodel.dart';
import '../home/tracks_tab.dart';
import '../profile/profile_viewmodel.dart';
import '../tutorial/tutorial_keys.dart';
import 'resume_viewmodel.dart';
import 'widgets/import_cv_button.dart';
import '../../services/cv_import_service.dart';

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
    if (_showingTracks) {
      return TracksTab(onBack: _exitTracks);
    }
    return Consumer2<ResumeViewModel, ProfileViewModel>(
      builder: (context, resumeVM, profileVM, _) {
        return Scaffold(
          backgroundColor: const Color(0xFFF3F4F6),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: _buildEntryState(context, resumeVM, profileVM),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEntryState(
    BuildContext context,
    ResumeViewModel resumeVM,
    ProfileViewModel profileVM,
  ) {
    const indigo = Color(0xFF4F46E5);
    const purple = Color(0xFF7C3AED);

    final isCourseCompleted = resumeVM.isCourseCompleted;
    final hasImportedBefore = profileVM.savedResumes
        .any((r) => r.title.startsWith(kImportedResumeBaseTitle));

    // Layout: tamanhos naturais (sem Expanded interno), espaço extra
    // distribuído ENTRE os blocos via spaceBetween. Em telas grandes
    // ganha respiro; em telas pequenas continua compacto.
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                isCourseCompleted
                    ? 'Seu currículo já está pronto'
                    : 'Dois jeitos de ter seu CV pronto',
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
                isCourseCompleted
                    ? 'Atualize pela trilha ou suba uma nova versão.'
                    : 'Escolha o caminho que faz mais sentido agora.',
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

        // Card Trilha — tamanho natural
        KeyedSubtree(
          key: TutorialKeys.trailCard,
          child: _buildPathCard(
            badge: isCourseCompleted ? 'JORNADA CONCLUÍDA' : 'RECOMENDADO',
            badgeColor: const Color(0xFF10B981),
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
        ),

        // Card Import — tamanho natural
        KeyedSubtree(
          key: TutorialKeys.importCard,
          child: _buildPathCard(
            badge: hasImportedBefore ? 'JÁ IMPORTADO' : 'MAIS RÁPIDO',
          badgeColor: hasImportedBefore
              ? const Color(0xFF6366F1)
              : const Color(0xFFF59E0B),
          icon: Icons.upload_file_rounded,
          iconBg: const Color(0xFF0EA5E9),
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
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
                        color: Color(0xFF0F172A),
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
              color: Colors.grey[700],
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
                          color: Color(0xFF334155),
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
                colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4F46E5).withOpacity(0.3),
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
