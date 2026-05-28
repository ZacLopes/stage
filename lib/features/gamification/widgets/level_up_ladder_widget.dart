import 'package:flutter/material.dart';
import '../../../core/theme/theme.dart';

class LevelUpLadderWidget extends StatefulWidget {
  final Function(String) onSelect;
  final String? initialValue;

  const LevelUpLadderWidget({
    super.key, 
    required this.onSelect, 
    this.initialValue
  });

  @override
  State<LevelUpLadderWidget> createState() => _LevelUpLadderWidgetState();
}

class _LevelUpLadderWidgetState extends State<LevelUpLadderWidget> {
  String? _selectedLevel;

  @override
  void initState() {
    super.initState();
    _selectedLevel = widget.initialValue;
  }
  
  final List<String> _levels = [
    'Pós-Graduação',
    'Graduação / Faculdade',
    'Ensino Técnico',
    'Ensino Médio',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _levels.map((level) => _buildLevelStep(level)).toList(),
    );
  }

  Widget _buildLevelStep(String level) {
    final isSelected = _selectedLevel == level;
    
    return GestureDetector(
      onTap: () {
        setState(() => _selectedLevel = level);
        widget.onSelect(level);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brandSoft : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.secondary : AppColors.border,
            width: isSelected ? 3 : 2,
          ),
          boxShadow: [
             BoxShadow(
               color: isSelected ? AppColors.secondary.withOpacity(0.2) : Colors.black.withOpacity(0.05),
               offset: const Offset(0, 4),
               blurRadius: isSelected ? 8 : 4,
             )
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.secondary : AppColors.background,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.school,
                color: isSelected ? Colors.white : AppColors.textDisabled,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                level,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? AppColors.secondary : AppColors.textSecondary,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: AppColors.secondary, size: 28),
          ],
        ),
      ),
    );
  }
}
