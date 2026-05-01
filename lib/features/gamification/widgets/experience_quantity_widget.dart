import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Receives a JSON-encoded map of {categoryCode: count} as [initialValue].
/// Emits a JSON-encoded map via [onSelect].
class ExperienceQuantityWidget extends StatefulWidget {
  final Function(String) onSelect;
  final List<String> categories; // category codes from inventory answer
  final String? initialValue;

  const ExperienceQuantityWidget({
    super.key,
    required this.onSelect,
    required this.categories,
    this.initialValue,
  });

  @override
  State<ExperienceQuantityWidget> createState() =>
      _ExperienceQuantityWidgetState();
}

class _ExperienceQuantityWidgetState extends State<ExperienceQuantityWidget> {
  // categoryCode -> count (0 = not set)
  late final Map<String, int> _counts;

  static const _labels = {
    'stage': 'Estágio / Trainee',
    'emp': 'Emprego (CLT / PJ)',
    'free': 'Freelance / Autônomo',
    'proj': 'Projeto Pessoal',
    'lead': 'Liderança Estudantil',
    'vol': 'Voluntariado',
    'res': 'Pesquisa Acadêmica',
    'spo': 'Esporte de Alto Rendimento',
  };

  static const _options = [1, 2, 3, 4, 5];

  @override
  void initState() {
    super.initState();
    _counts = {for (final c in widget.categories) c: 0};
    if (widget.initialValue != null) {
      try {
        final Map<String, dynamic> saved = jsonDecode(widget.initialValue!);
        for (final entry in saved.entries) {
          if (_counts.containsKey(entry.key)) {
            _counts[entry.key] = (entry.value as num).toInt();
          }
        }
      } catch (_) {}
    }
  }

  void _setCount(String cat, int count) {
    HapticFeedback.selectionClick();
    setState(() => _counts[cat] = count);
    _emit();
  }

  void _emit() {
    if (_counts.values.any((v) => v > 0)) {
      widget.onSelect(jsonEncode(_counts));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widget.categories.map((cat) {
        final label = _labels[cat] ?? cat;
        final count = _counts[cat] ?? 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: count > 0
                  ? const Color(0xFF00C27A)
                  : const Color(0xFFE5E7EB),
              width: count > 0 ? 2 : 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Quantas experiências você teve?',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF9CA3AF),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: _options.map((n) {
                  final isSelected = count == n;
                  final label5 = n == 5 ? '5+' : '$n';
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: n < 5 ? 8 : 0),
                      child: GestureDetector(
                        onTap: () => _setCount(cat, n),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          height: 40,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF00C27A)
                                : const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF00C27A)
                                  : const Color(0xFFE5E7EB),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            label5,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? Colors.white
                                  : const Color(0xFF6B7280),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
