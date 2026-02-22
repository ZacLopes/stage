import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BalanceSliderWidget extends StatefulWidget {
  final Map<String, dynamic> options; 
  final Function(String) onSelect;
  final dynamic initialValue;

  const BalanceSliderWidget({
    super.key, 
    required this.options, 
    required this.onSelect,
    this.initialValue,
  });

  @override
  State<BalanceSliderWidget> createState() => _BalanceSliderWidgetState();
}

class _BalanceSliderWidgetState extends State<BalanceSliderWidget> {
  int? _selectedIndex;

  final List<Map<String, dynamic>> _stages = [
    {
      'id': 'perfectionist',
      'title': 'Perfeccionista',
      'subtitle': 'Foco em Detalhes',
      'desc': 'Prefiro revisar cada detalhe para garantir a precisão máxima.',
      'icon': Icons.center_focus_strong_rounded,
      'color': const Color(0xFF3B82F6), // Blue
    },
    {
      'id': 'balanced',
      'title': 'Equilibrado',
      'subtitle': 'Equilíbrio',
      'desc': 'Busco o meio-termo entre o rigor técnico e a velocidade.',
      'icon': Icons.balance_rounded,
      'color': const Color(0xFF58CC02), // Duolingo Green
    },
    {
      'id': 'generalist',
      'title': 'Generalista',
      'subtitle': 'Visão de Entrega',
      'desc': 'Foco em entender o objetivo macro e fazer o projeto avançar.',
      'icon': Icons.rocket_launch_rounded,
      'color': const Color(0xFFF59E0B), // Amber
    },
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      final val = widget.initialValue.toString();
      // Handle old numeric values if any
      if (double.tryParse(val) != null) {
         final dVal = double.parse(val);
         if (dVal < 35) _selectedIndex = 0;
         else if (dVal > 65) _selectedIndex = 2;
         else _selectedIndex = 1;
      } else {
        _selectedIndex = _stages.indexWhere((s) => s['id'] == val || s['title'] == val);
        if (_selectedIndex == -1) _selectedIndex = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Stage Indicator (Duolingo Style Progression)
        Container(
          margin: const EdgeInsets.only(bottom: 24),
          child: Row(
            children: List.generate(_stages.length, (index) {
              final isPassed = _selectedIndex != null && index <= _selectedIndex!;
              final isCurrent = _selectedIndex == index;
              
              return Expanded(
                child: Container(
                  height: 10,
                  margin: EdgeInsets.only(
                    left: index == 0 ? 0 : 4,
                    right: index == _stages.length - 1 ? 0 : 4,
                  ),
                  decoration: BoxDecoration(
                    color: isPassed ? _stages[index]['color'] : const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: isCurrent ? [
                       BoxShadow(
                         color: _stages[index]['color'].withOpacity(0.4),
                         blurRadius: 8,
                         offset: const Offset(0, 2),
                       )
                    ] : null,
                  ),
                ),
              );
            }),
          ),
        ),

        // Cards
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _stages.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final stage = _stages[index];
            final isSelected = _selectedIndex == index;
            final color = (stage['color'] as Color?) ?? Colors.blue;

            return GestureDetector(
              onTap: () {
                setState(() => _selectedIndex = index);
                widget.onSelect(stage['title']!); // Saving Title as it's descriptive for AI
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSelected ? color.withOpacity(0.1) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? color : const Color(0xFFE5E7EB),
                    width: isSelected ? 3 : 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isSelected ? color.withOpacity(0.1) : Colors.black.withOpacity(0.05),
                      offset: const Offset(0, 4),
                      blurRadius: isSelected ? 12 : 4,
                    )
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isSelected ? color : const Color(0xFFF3F4F6),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        stage['icon'],
                        color: isSelected ? Colors.white : const Color(0xFF9CA3AF),
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                "ESTÁGIO ${index + 1}",
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? color : const Color(0xFF9CA3AF),
                                  letterSpacing: 1.2,
                                ),
                              ),
                              if (isSelected) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'SELECIONADO',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            stage['title'],
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? color : const Color(0xFF374151),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            stage['desc'],
                            style: TextStyle(
                              fontSize: 14,
                              color: isSelected ? color.withOpacity(0.8) : const Color(0xFF6B7280),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
