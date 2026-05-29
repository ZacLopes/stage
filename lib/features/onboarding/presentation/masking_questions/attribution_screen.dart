// AttributionScreen — "Como nos conheceu?" — primeira de 7 perguntas
// mascarando a latência da extração do CV.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:provider/provider.dart';
import '../../../auth/auth_session.dart';
import '../../../../services/analytics_service.dart';
import '../../../profile/application/profile_editor_view_model.dart';
import '../../../profile/domain/entities/entities.dart';
import '../../utils/save_with_retry.dart';
import '../onboarding_scaffold.dart';
import 'first_name_screen.dart';
import '../../../../core/theme/theme.dart';

const _options = [
  'Instagram',
  'TikTok',
  'Indicação de amigo',
  'LinkedIn',
  'ChatGPT',
  'X / Twitter',
  'Outro',
];

class AttributionScreen extends StatefulWidget {
  const AttributionScreen({super.key});

  @override
  State<AttributionScreen> createState() => _AttributionScreenState();
}

class _AttributionScreenState extends State<AttributionScreen> {
  String? _selected;
  bool _saving = false;

  Future<void> _continue() async {
    if (_selected == null || _saving) return;
    AnalyticsService.shared.track('onboarding_masking_question_answered',
        props: {'question': 'attribution', 'value': _selected!});

    final vm = context.read<ProfileEditorViewModel>();
    final userId = currentUserIdOrNull();
    if (userId == null) {
      // ignore: unawaited_futures
      handleSessionLost(context);
      return;
    }
    final base = vm.personal ?? PersonalInfo(userId: userId);
    setState(() => _saving = true);
    final ok = await saveWithRetry(
      context: context,
      operation: () => vm.commitPersonal(base.copyWith(attributionSource: _selected)),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const FirstNameScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Como nos conheceu?',
      subtitle: 'Ajuda a gente entender de onde você vem.',
      progress: 0.13,
      // Voltar daqui = volta pra TwoDoorsScreen (escolha Upload/Trail).
      // popUntil(isFirst) volta pra rota raiz (AuthGate), que re-renderiza
      // TwoDoorsScreen via Consumer<UserViewModel> (user logado + !hasCampaign).
      // Pré-requisito: todo o onboarding usa push regular pra manter
      // AuthGate no fundo do stack.
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
        onPressed: () =>
            Navigator.of(context).popUntil((route) => route.isFirst),
      ),
      continueLabel: _saving ? 'Salvando…' : 'Continuar',
      onContinue: (_selected == null || _saving) ? null : _continue,
      child: Column(
        children: _options.map((opt) {
          final isSelected = _selected == opt;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _selected = opt);
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.brandCyan.withValues(alpha: 0.08)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? AppColors.brandCyan : AppColors.border,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        opt,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected ? AppColors.brandCyan : Colors.black87,
                        ),
                      ),
                    ),
                    if (isSelected) const Icon(Icons.check_circle, color: AppColors.brandCyan),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
