import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

class ToolsCatalogWidget extends StatefulWidget {
  final Function(String) onSelect;
  final List<String> categories;
  final String? initialValue;

  const ToolsCatalogWidget({
    super.key,
    required this.onSelect,
    required this.categories,
    this.initialValue,
  });

  @override
  State<ToolsCatalogWidget> createState() => _ToolsCatalogWidgetState();
}

class _ToolsCatalogWidgetState extends State<ToolsCatalogWidget> {
  // category -> level (null means selected but no level yet)
  final Map<String, String?> _selected = {};

  static const _levels = ['Básico', 'Intermediário', 'Avançado'];

  static const _levelColors = {
    'Básico': Color(0xFF10B981),
    'Intermediário': Color(0xFFF59E0B),
    'Avançado': Color(0xFFEF4444),
  };

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      try {
        final List<dynamic> list = jsonDecode(widget.initialValue!);
        for (final item in list) {
          _selected[item['category'] as String] = item['level'] as String?;
        }
      } catch (_) {}
    }
  }

  void _toggleCategory(String cat) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selected.containsKey(cat)) {
        _selected.remove(cat);
      } else {
        _selected[cat] = null;
      }
    });
    _emit();
  }

  void _setLevel(String cat, String level) {
    HapticFeedback.lightImpact();
    setState(() => _selected[cat] = level);
    _emit();
  }

  void _emit() {
    final complete = _selected.entries
        .where((e) => e.value != null)
        .map((e) => {'category': e.key, 'level': e.value})
        .toList();
    if (complete.isNotEmpty) {
      widget.onSelect(jsonEncode(complete));
    }
  }

  IconData _iconFor(String cat) {
    if (cat.contains('Office')) return Icons.table_chart;
    if (cat.contains('Design')) return Icons.brush;
    if (cat.contains('Programação')) return Icons.code;
    if (cat.contains('Dados')) return Icons.bar_chart;
    if (cat.contains('Redes') || cat.contains('Marketing')) return Icons.campaign;
    if (cat.contains('Gestão')) return Icons.task_alt;
    if (cat.contains('Vendas')) return Icons.handshake;
    return Icons.star;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Toque para selecionar e escolha seu nível',
          style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
        ),
        const SizedBox(height: 20),
        ...widget.categories.map((cat) {
          final isSelected = _selected.containsKey(cat);
          final currentLevel = _selected[cat];

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              children: [
                GestureDetector(
                  onTap: () => _toggleCategory(cat),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFEEF2FF) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF6366F1) : const Color(0xFFE5E7EB),
                        width: 2,
                      ),
                      boxShadow: isSelected
                          ? []
                          : [const BoxShadow(color: Color(0xFFE5E7EB), offset: Offset(0, 3), blurRadius: 0)],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF6366F1).withOpacity(0.15) : const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(_iconFor(cat),
                              color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF6B7280), size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(cat,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? const Color(0xFF4338CA) : const Color(0xFF374151),
                              )),
                        ),
                        if (currentLevel != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _levelColors[currentLevel]!.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(currentLevel,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _levelColors[currentLevel])),
                          )
                        else if (isSelected)
                          const Text('← escolha o nível',
                              style: TextStyle(fontSize: 12, color: Color(0xFFF59E0B))),
                        const SizedBox(width: 8),
                        Icon(
                          isSelected ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF9CA3AF),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isSelected)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(top: 4, left: 16, right: 16),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: _levels.map((level) {
                        final isChosen = currentLevel == level;
                        final color = _levelColors[level]!;
                        return GestureDetector(
                          onTap: () => _setLevel(cat, level),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: isChosen ? color : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: isChosen ? color : const Color(0xFFE5E7EB), width: 2),
                            ),
                            child: Text(level,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isChosen ? Colors.white : const Color(0xFF6B7280),
                                )),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }
}
