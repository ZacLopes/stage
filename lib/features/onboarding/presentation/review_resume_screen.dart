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
import 'masking_questions/education_screen.dart';
import 'onboarding_scaffold.dart';
import 'preferences/desired_titles_screen.dart';
import '../../../core/theme/theme.dart';

class ReviewResumeScreen extends StatefulWidget {
  /// Se true, mostra badges de "Confirme isso?" em campos low-confidence.
  /// Setado quando o user veio do caminho upload.
  final bool fromUpload;

  const ReviewResumeScreen({super.key, this.fromUpload = true});

  @override
  State<ReviewResumeScreen> createState() => _ReviewResumeScreenState();
}

class _ReviewResumeScreenState extends State<ReviewResumeScreen> {
  // QA Dia 6 — pra calcular `time_on_screen_ms` no review_confirmed.
  DateTime? _shownAt;

  @override
  void initState() {
    super.initState();
    _shownAt = DateTime.now();
    // ignore: unawaited_futures
    Analytics.shared.onboardingCvReviewShown();
  }

  void _continue() {
    final timeOnScreenMs = _shownAt != null
        ? DateTime.now().difference(_shownAt!).inMilliseconds
        : 0;
    // ignore: unawaited_futures
    Analytics.shared.onboardingCvReviewConfirmed(
      editsCount: 0,
      timeOnScreenMs: timeOnScreenMs,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => widget.fromUpload
            ? const EducationScreen()
            : const DesiredTitlesScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final extraction = context.watch<ExtractionStatusViewModel>();
    final vm = context.watch<ProfileEditorViewModel>();

    // Se veio do upload e extração ainda rodando, mostra loading
    final isWaiting =
        widget.fromUpload && extraction.status == ExtractionStatus.running;
    final extractionFailed =
        widget.fromUpload && extraction.status == ExtractionStatus.failed;

    if (isWaiting) {
      return OnboardingScaffold(
        title: 'Seu perfil',
        subtitle: 'Quase pronto…',
        progress: 0.63,
        onContinue: null,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 80),
          child: Center(
            child: CircularProgressIndicator(color: AppColors.brandCyan),
          ),
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
      title: 'Seu perfil',
      subtitle: widget.fromUpload
          ? 'Confira se ficou tudo certinho — você pode editar qualquer coisa.'
          : 'Confira o que você preencheu.',
      progress: 0.63,
      onContinue: _continue,
      child: const ProfileSectionList(
        showLowConfidenceBadges: true,
        showOptionalSections: false,
      ),
    );
  }
}
