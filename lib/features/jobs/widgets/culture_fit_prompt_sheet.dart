import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/theme.dart';
import '../../../core/widgets/buttons/primary_button.dart';
import '../../../services/analytics_events.dart';
import '../../../services/analytics_service.dart';
import '../models/culture_fit_profile.dart';

class CultureFitPromptSheet extends StatefulWidget {
  final CultureFitProfile initialProfile;

  const CultureFitPromptSheet({super.key, required this.initialProfile});

  @override
  State<CultureFitPromptSheet> createState() => _CultureFitPromptSheetState();
}

class _CultureFitPromptSheetState extends State<CultureFitPromptSheet> {
  late CultureFitProfile _profile;
  late final PageController _pageController;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _profile = widget.initialProfile;
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _selectAnswer(_CultureFitQuestion question, _CultureFitOption option) {
    HapticFeedback.selectionClick();
    setState(() {
      _profile = _profile.withAnswer(question.key, option.value);
    });
    Analytics.shared.track(
      evCultureFitQuestionAnswered,
      props: {
        'question_key': question.key,
        'answer': option.value,
        'question_index': _index,
      },
    );
  }

  Future<void> _goTo(int nextIndex) async {
    if (nextIndex < 0 || nextIndex >= _questions.length) return;
    setState(() => _index = nextIndex);
    await _pageController.animateToPage(
      nextIndex,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  void _continue() {
    if (_index == _questions.length - 1) {
      Navigator.of(context).pop(_profile);
      return;
    }
    _goTo(_index + 1);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final currentQuestion = _questions[_index];
    final selectedAnswer = _profile.answerFor(currentQuestion.key);
    final canContinue = selectedAnswer != null;

    return Container(
      constraints: BoxConstraints(maxHeight: size.height * 0.86),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderStrong,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      color: AppColors.primarySoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.diversity_3_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fit cultural',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '4 respostas rápidas',
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.textTertiary,
                    tooltip: 'Fechar',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _ProgressDots(
                currentIndex: _index,
                total: _questions.length,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _questions.length,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (context, pageIndex) {
                  final question = _questions[pageIndex];
                  return _QuestionPage(
                    question: question,
                    selectedValue: _profile.answerFor(question.key),
                    onSelected: (option) => _selectAnswer(question, option),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: _index == 0 ? null : () => _goTo(_index - 1),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        side: const BorderSide(color: AppColors.border),
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppRadius.brMd,
                        ),
                      ),
                      child: const Icon(Icons.chevron_left_rounded),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PrimaryButton(
                      label: _index == _questions.length - 1
                          ? 'Salvar fit'
                          : 'Continuar',
                      icon: _index == _questions.length - 1
                          ? Icons.check_rounded
                          : Icons.chevron_right_rounded,
                      onPressed: canContinue ? _continue : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionPage extends StatelessWidget {
  final _CultureFitQuestion question;
  final String? selectedValue;
  final ValueChanged<_CultureFitOption> onSelected;

  const _QuestionPage({
    required this.question,
    required this.selectedValue,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${question.stepLabel} de ${_questions.length}',
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            question.title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 24,
              height: 1.16,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            question.subtitle,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 14,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 22),
          for (final option in question.options) ...[
            _CultureFitOptionTile(
              option: option,
              selected: selectedValue == option.value,
              onTap: () => onSelected(option),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _CultureFitOptionTile extends StatelessWidget {
  final _CultureFitOption option;
  final bool selected;
  final VoidCallback onTap;

  const _CultureFitOptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.brLg,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? AppColors.primarySoft : AppColors.surfaceVariant,
            borderRadius: AppRadius.brLg,
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.border,
                  ),
                ),
                child: Icon(
                  option.icon,
                  color: selected ? Colors.white : AppColors.textTertiary,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  option.label,
                  style: TextStyle(
                    color: selected ? AppColors.primary : AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    height: 1.24,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 140),
                child: selected
                    ? const Icon(
                        Icons.check_circle_rounded,
                        key: ValueKey('selected'),
                        color: AppColors.primary,
                        size: 22,
                      )
                    : const Icon(
                        Icons.radio_button_unchecked_rounded,
                        key: ValueKey('empty'),
                        color: AppColors.borderStrong,
                        size: 22,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressDots extends StatelessWidget {
  final int currentIndex;
  final int total;

  const _ProgressDots({required this.currentIndex, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (index) {
        final active = index <= currentIndex;
        return Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 5,
            margin: EdgeInsets.only(right: index == total - 1 ? 0 : 6),
            decoration: BoxDecoration(
              color: active ? AppColors.primary : AppColors.border,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        );
      }),
    );
  }
}

class _CultureFitQuestion {
  final String key;
  final String stepLabel;
  final String title;
  final String subtitle;
  final List<_CultureFitOption> options;

  const _CultureFitQuestion({
    required this.key,
    required this.stepLabel,
    required this.title,
    required this.subtitle,
    required this.options,
  });
}

class _CultureFitOption {
  final String value;
  final String label;
  final IconData icon;

  const _CultureFitOption({
    required this.value,
    required this.label,
    required this.icon,
  });
}

const List<_CultureFitQuestion> _questions = <_CultureFitQuestion>[
  _CultureFitQuestion(
    key: CultureFitKeys.workStyle,
    stepLabel: '1',
    title: 'Como você prefere receber trabalho?',
    subtitle: 'Isso ajuda a entender se o ambiente combina com seu jeito.',
    options: <_CultureFitOption>[
      _CultureFitOption(
        value: 'clear_scope',
        label: 'Com prioridade e escopo bem claros',
        icon: Icons.checklist_rounded,
      ),
      _CultureFitOption(
        value: 'autonomy',
        label: 'Com autonomia para decidir o caminho',
        icon: Icons.explore_rounded,
      ),
      _CultureFitOption(
        value: 'guided_autonomy',
        label: 'Com direção inicial e liberdade depois',
        icon: Icons.route_rounded,
      ),
    ],
  ),
  _CultureFitQuestion(
    key: CultureFitKeys.learningStyle,
    stepLabel: '2',
    title: 'Quando entra em algo novo, você aprende melhor...',
    subtitle: 'A pergunta mede o tipo de suporte que te faz evoluir.',
    options: <_CultureFitOption>[
      _CultureFitOption(
        value: 'mentor',
        label: 'Com alguém explicando e acompanhando',
        icon: Icons.record_voice_over_rounded,
      ),
      _CultureFitOption(
        value: 'docs',
        label: 'Com documentação, curso ou passo a passo',
        icon: Icons.menu_book_rounded,
      ),
      _CultureFitOption(
        value: 'hands_on',
        label: 'Testando, errando pouco e pedindo ajuda',
        icon: Icons.construction_rounded,
      ),
    ],
  ),
  _CultureFitQuestion(
    key: CultureFitKeys.collaborationStyle,
    stepLabel: '3',
    title: 'No time, você prefere uma rotina...',
    subtitle: 'Esse sinal separa culturas mais síncronas das mais focadas.',
    options: <_CultureFitOption>[
      _CultureFitOption(
        value: 'high_collaboration',
        label: 'Com bastante conversa e troca ao vivo',
        icon: Icons.forum_rounded,
      ),
      _CultureFitOption(
        value: 'async_focus',
        label: 'Com foco individual e comunicação assíncrona',
        icon: Icons.mark_chat_unread_rounded,
      ),
      _CultureFitOption(
        value: 'balanced_rituals',
        label: 'Com rituais curtos e foco no restante',
        icon: Icons.groups_2_rounded,
      ),
    ],
  ),
  _CultureFitQuestion(
    key: CultureFitKeys.paceStyle,
    stepLabel: '4',
    title: 'Sobre ritmo de trabalho, o melhor para você é...',
    subtitle: 'Ajuda a evitar vagas com pressão incompatível com seu momento.',
    options: <_CultureFitOption>[
      _CultureFitOption(
        value: 'predictable',
        label: 'Planejado, com metas estáveis',
        icon: Icons.calendar_month_rounded,
      ),
      _CultureFitOption(
        value: 'dynamic',
        label: 'Dinâmico, com mudanças rápidas',
        icon: Icons.bolt_rounded,
      ),
      _CultureFitOption(
        value: 'seasonal_intensity',
        label: 'Picos intensos, mas com pausas reais',
        icon: Icons.waves_rounded,
      ),
    ],
  ),
];
