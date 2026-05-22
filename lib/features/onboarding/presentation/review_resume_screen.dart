// ReviewResumeScreen (Container 1 — Tela B)
//
// Mostra ProfileSectionList com dados extraídos (via upload) ou preenchidos
// (via trilha). Pós-extração: showLowConfidenceBadges=true destaca campos
// suspeitos.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../services/analytics_service.dart';
import '../../profile/application/extraction_status_view_model.dart';
import '../../profile/application/profile_editor_view_model.dart';
import '../../profile/presentation/widgets/profile_section_list.dart';
import 'onboarding_scaffold.dart';
import 'preferences/desired_titles_screen.dart';

class ReviewResumeScreen extends StatefulWidget {
  /// Se true, mostra badges de "Confirme isso?" em campos low-confidence.
  /// Setado quando o user veio do caminho upload.
  final bool fromUpload;

  const ReviewResumeScreen({super.key, this.fromUpload = true});

  @override
  State<ReviewResumeScreen> createState() => _ReviewResumeScreenState();
}

class _ReviewResumeScreenState extends State<ReviewResumeScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.shared.track('onboarding_review_resume_shown');
  }

  void _continue() {
    AnalyticsService.shared.track('onboarding_review_resume_continued');
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DesiredTitlesScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final extraction = context.watch<ExtractionStatusViewModel>();
    final vm = context.watch<ProfileEditorViewModel>();

    // Se veio do upload e extração ainda rodando, mostra loading
    final isWaiting = widget.fromUpload && extraction.status == ExtractionStatus.running;
    final extractionFailed = widget.fromUpload && extraction.status == ExtractionStatus.failed;

    if (isWaiting) {
      return OnboardingScaffold(
        title: 'Seu currículo',
        subtitle: 'Quase pronto…',
        progress: 0.8,
        onContinue: null,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 80),
          child: Center(child: CircularProgressIndicator(color: Color(0xFF00C27A))),
        ),
      );
    }

    if (extractionFailed) {
      // Quando carrega vazio, ainda permite continuar
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (vm.experiences.isEmpty && vm.education.isEmpty) {
          vm.load();
        }
      });
    }

    return OnboardingScaffold(
      title: 'Seu currículo',
      subtitle: widget.fromUpload
          ? 'Confira se ficou tudo certinho — você pode editar qualquer coisa.'
          : 'Confira o que você preencheu.',
      progress: 0.8,
      onContinue: _continue,
      child: const ProfileSectionList(
        showLowConfidenceBadges: true,
        showOptionalSections: false,
      ),
    );
  }
}
