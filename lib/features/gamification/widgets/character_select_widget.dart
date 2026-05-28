import 'package:flutter/material.dart';
import '../../../core/theme/theme.dart';

class CharacterSelectWidget extends StatefulWidget {
  final Map<String, dynamic> options; // List of characters with descriptions
  final Function(String) onSelect;
  final String? initialValue;

  const CharacterSelectWidget({
    super.key, 
    required this.options, 
    required this.onSelect,
    this.initialValue,
  });

  @override
  State<CharacterSelectWidget> createState() => _CharacterSelectWidgetState();
}

class _CharacterSelectWidgetState extends State<CharacterSelectWidget> {
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialValue;
  }


  @override
  Widget build(BuildContext context) {
    // In a real implementation, we would parse widget.options
    // For now, we expect a list of objects in the options
    final List<Map<String, String>> characters = [
      {
        'id': 'architect',
        'title': 'O Estrategista',
        'desc': 'Gosto de desenhar o plano, analisar riscos e garantir que a lógica por trás da ideia seja sólida.',
        'icon': 'architect', 
      },
      {
        'id': 'visionary',
        'title': 'O Inovador',
        'desc': 'Trago as ideias que ninguém teve, foco no diferencial do produto e no que vem a seguir.',
        'icon': 'visionary',
      },
      {
        'id': 'chief',
        'title': 'O Líder',
        'desc': 'Assumo o comando do time, foco no resultado final e garanto que todos entreguem o seu melhor.',
        'icon': 'chief',
      },
      {
        'id': 'builder',
        'title': 'O Realizador',
        'desc': 'Sou o motor do projeto. Minha satisfação é tirar a ideia do papel e entregar com perfeição técnica.',
        'icon': 'builder',
      },
      {
        'id': 'negotiator',
        'title': 'O Facilitador',
        'desc': 'Mantenho o time unido, resolvo impasses e garanto que a comunicação flua sem ruídos.',
        'icon': 'negotiator',
      },
    ];

    return SizedBox(
      height: 300,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: characters.length,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final char = characters[index];
          final isSelected = _selectedId == char['id'];
          
          return GestureDetector(
            onTap: () {
               setState(() => _selectedId = char['id']);
               widget.onSelect(char['id']!);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 180,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.brandSoft : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppColors.secondary : AppColors.border,
                  width: isSelected ? 3 : 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    offset: const Offset(0, 4),
                    blurRadius: 10,
                  )
                ]
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   // Placeholder Icon
                   Icon(
                     _getIconData(char['icon']), 
                     size: 40, 
                     color: isSelected ? AppColors.secondary : AppColors.textSecondary
                   ),
                   const SizedBox(height: 16),
                   Text(
                     char['title']!,
                     textAlign: TextAlign.center,
                     style: TextStyle(
                       fontSize: 18,
                       fontWeight: FontWeight.bold,
                       color: isSelected ? AppColors.brand : AppColors.textSecondary,
                     ),
                   ),
                   const SizedBox(height: 12),
                   Expanded(
                     child: Center(
                       child: Text(
                         char['desc']!,
                         textAlign: TextAlign.center,
                         style: const TextStyle(
                           fontSize: 14.5,
                           color: AppColors.textTertiary,
                           height: 1.3, // Better line height for readability
                         ),
                       ),
                     ),
                   ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
  
  IconData _getIconData(String? iconName) {
    switch(iconName) {
      case 'architect': return Icons.architecture; 
      case 'visionary': return Icons.lightbulb_outline;
      case 'chief': return Icons.flag;
      case 'builder': return Icons.build;
      case 'negotiator': return Icons.handshake;
      default: return Icons.person;
    }
  }
}
