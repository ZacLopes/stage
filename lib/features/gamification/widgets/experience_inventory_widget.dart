import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/theme.dart';

class ExperienceInventoryWidget extends StatefulWidget {
  final Function(String) onSelect;
  final String? initialValue;

  const ExperienceInventoryWidget({
    super.key,
    required this.onSelect,
    this.initialValue,
  });

  @override
  State<ExperienceInventoryWidget> createState() =>
      _ExperienceInventoryWidgetState();
}

class _ExperienceInventoryWidgetState
    extends State<ExperienceInventoryWidget> {
  final Set<String> _selected = {};

  static const _categories = [
    ('stage', 'Estágio / Trainee', Icons.work_outline),
    ('emp', 'Emprego (CLT / PJ)', Icons.business_center_outlined),
    ('free', 'Freelance / Autônomo', Icons.laptop_outlined),
    ('proj', 'Projeto Pessoal', Icons.lightbulb_outline),
    ('lead', 'Liderança Estudantil', Icons.groups_outlined),
    ('vol', 'Voluntariado', Icons.favorite_outline),
    ('res', 'Pesquisa Acadêmica', Icons.science_outlined),
    ('spo', 'Esporte de Alto Rendimento', Icons.emoji_events_outlined),
    ('none', 'Não tenho experiências ainda', Icons.sentiment_neutral_outlined),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      try {
        final List<dynamic> list = jsonDecode(widget.initialValue!);
        _selected.addAll(list.map((e) => e.toString()));
      } catch (_) {}
    }
  }

  void _toggle(String code) {
    HapticFeedback.selectionClick();
    setState(() {
      if (code == 'none') {
        _selected.clear();
        _selected.add('none');
      } else {
        _selected.remove('none');
        if (_selected.contains(code)) {
          _selected.remove(code);
        } else {
          _selected.add(code);
        }
      }
    });
    _emit();
  }

  void _emit() {
    if (_selected.isEmpty) return;
    widget.onSelect(jsonEncode(_selected.toList()));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _categories.map((cat) {
        final code = cat.$1;
        final label = cat.$2;
        final icon = cat.$3;
        final isSelected = _selected.contains(code);
        final isNone = code == 'none';

        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? (isNone
                    ? AppColors.background
                    : AppColors.success.withOpacity(0.08))
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? (isNone
                      ? AppColors.textDisabled
                      : AppColors.success)
                  : AppColors.border,
              width: isSelected ? 2 : 1.5,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _toggle(code),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: 22,
                      color: isSelected
                          ? (isNone
                              ? AppColors.textTertiary
                              : AppColors.success)
                          : AppColors.textDisabled,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: isSelected
                              ? (isNone
                                  ? AppColors.textTertiary
                                  : AppColors.textPrimary)
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if (isSelected)
                      Icon(
                        isNone ? Icons.check : Icons.check_circle,
                        size: 20,
                        color: isNone
                            ? AppColors.textDisabled
                            : AppColors.success,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
