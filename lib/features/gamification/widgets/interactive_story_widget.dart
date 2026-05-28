import 'package:flutter/material.dart';
import '../../../core/theme/theme.dart';

class InteractiveStoryWidget extends StatefulWidget {
  final Map<String, dynamic> options; 
  final Function(String) onSelect;
  final String? initialValue;

  const InteractiveStoryWidget({
    super.key, 
    required this.options, 
    required this.onSelect,
    this.initialValue,
  });

  @override
  State<InteractiveStoryWidget> createState() => _InteractiveStoryWidgetState();
}

class _InteractiveStoryWidgetState extends State<InteractiveStoryWidget> {
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    // Hardcoded for now based on the spec, would be dynamic later
    final List<Map<String, String>> actions = [
      {
        'id': 'prioritize_execute',
        'text': 'Priorizar e Executar: Não dá tempo de chorar. Defino o que é essencial e foco em entregar o MVP.',
      },
      {
        'id': 'investigate_cause',
        'text': 'Investigar a Causa: Paro para analisar onde erramos, para corrigir a raiz do problema e não repetir.',
      },
      {
        'id': 'seek_support',
        'text': 'Buscar Apoio: Comunico o problema imediatamente e busco ajuda de quem sabe mais para resolver rápido.',
      },
      {
        'id': 'negotiate',
        'text': 'Negociar: Avalio o impacto e tento negociar um novo prazo ou escopo para garantir a qualidade.',
      },
    ];

    return Column(
      children: actions.map((action) {
        final isSelected = _selectedId == action['id'];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GestureDetector(
            onTap: () {
              setState(() => _selectedId = action['id']);
              widget.onSelect(action['id']!);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFFFF3CD) : Colors.white, // Warning tint
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? AppColors.warning : AppColors.border,
                  width: 2,
                ),
                boxShadow: [
                  if (isSelected)
                    const BoxShadow(
                      color: AppColors.warning,
                      offset: Offset(0, 0),
                      blurRadius: 0,
                    )
                  else
                    const BoxShadow(
                      color: AppColors.border,
                      offset: Offset(0, 4),
                      blurRadius: 0,
                    ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      action['text']!,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
