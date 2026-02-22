import 'package:flutter/material.dart';

class VibeSelectWidget extends StatefulWidget {
  final Function(String) onSelect;
  final String? initialValue;

  const VibeSelectWidget({
    super.key, 
    required this.onSelect,
    this.initialValue,
  });

  @override
  State<VibeSelectWidget> createState() => _VibeSelectWidgetState();
}

class _VibeSelectWidgetState extends State<VibeSelectWidget> {
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialValue;
  }

  // Placeholder data
  final List<Map<String, String>> _vibes = [
    {
      'id': 'laboratory',
      'title': 'O Laboratório',
      'desc': 'Ambiente silencioso, organizado e focado.',
      'icon': 'science',
    },
    {
      'id': 'arena',
      'title': 'A Arena',
      'desc': 'Ambiente acelerado, com metas e competição.',
      'icon': 'stadium',
    },
    {
      'id': 'community',
      'title': 'A Comunidade',
      'desc': 'Espaço aberto, muita conversa e troca.',
      'icon': 'groups',
    },
    {
      'id': 'stage',
      'title': 'O Palco',
      'desc': 'Conexão com pessoas e apresentações.',
      'icon': 'mic',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _vibes.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.8,
      ),
      itemBuilder: (context, index) {
        final vibe = _vibes[index];
        final isSelected = _selectedId == vibe['id'];

        return GestureDetector(
          onTap: () {
            setState(() => _selectedId = vibe['id']);
            widget.onSelect(vibe['id']!);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFDDF4FF) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? const Color(0xFF1CB0F6) : const Color(0xFFE5E7EB),
                width: isSelected ? 3 : 2,
              ),
              boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    offset: const Offset(0, 4),
                    blurRadius: 8,
                  )
              ]
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _getIcon(vibe['icon']),
                  size: 48,
                  color: isSelected ? const Color(0xFF1CB0F6) : const Color(0xFF6B7280),
                ),
                const SizedBox(height: 16),
                Text(
                  vibe['title']!,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? const Color(0xFF1899D6) : const Color(0xFF374151),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  vibe['desc']!,
                  style: const TextStyle(
                    fontSize: 14.5,
                    color: Color(0xFF6B7280),
                    height: 1.3,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _getIcon(String? icon) {
    switch (icon) {
      case 'science': return Icons.science;
      case 'stadium': return Icons.emoji_events;
      case 'groups': return Icons.diversity_3;
      case 'mic': return Icons.mic;
      default: return Icons.place;
    }
  }
}
