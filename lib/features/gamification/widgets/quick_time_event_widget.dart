import 'package:flutter/material.dart';

class QuickTimeEventWidget extends StatefulWidget {
  final Function(String) onSelect;
  final String? initialValue;

  const QuickTimeEventWidget({
    super.key, 
    required this.onSelect,
    this.initialValue,
  });

  @override
  State<QuickTimeEventWidget> createState() => _QuickTimeEventWidgetState();
}

class _QuickTimeEventWidgetState extends State<QuickTimeEventWidget> {
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialValue;
  }

  final List<Map<String, String>> _actions = [
    {
      'id': 'self_research',
      'label': 'Investigar Sozinho',
      'desc': 'Google, tutoriais e aprender na raça.',
    },
    {
      'id': 'consult_expert',
      'label': 'Consultar Especialista',
      'desc': 'Perguntar para quem sabe.',
    },
    {
      'id': 'trial_error',
      'label': 'Tentativa e Erro',
      'desc': 'Fazer e ajustar no processo.',
    },
    {
      'id': 'read_manual',
      'label': 'Ler o Manual',
      'desc': 'Documentação oficial primeiro.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _actions.map((action) {
        final isSelected = _selectedId == action['id'];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: GestureDetector(
            onTap: () {
               setState(() => _selectedId = action['id']);
               widget.onSelect(action['id']!);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF58CC02) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? const Color(0xFF46A302) : const Color(0xFFE5E7EB),
                  width: isSelected ? 0 : 2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xFFE5E7EB),
                    offset: Offset(0, 4),
                    blurRadius: 0,
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action['label']!,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : const Color(0xFF374151),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    action['desc']!,
                    style: TextStyle(
                      fontSize: 14,
                      color: isSelected ? Colors.white.withOpacity(0.9) : const Color(0xFF6B7280),
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
