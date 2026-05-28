import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../../../core/theme/theme.dart';

class RewardCardWidget extends StatefulWidget {
  final Function(dynamic) onSelect;
  final List<String> options;
  final String? initialValue;

  const RewardCardWidget({
    super.key, 
    required this.onSelect, 
    this.options = const [],
    this.initialValue,
  });

  @override
  State<RewardCardWidget> createState() => _RewardCardWidgetState();
}

class _RewardCardWidgetState extends State<RewardCardWidget> {
  String? _selectedOption;
  final TextEditingController _detailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      try {
        final Map<String, dynamic> data = jsonDecode(widget.initialValue!);
        _selectedOption = data['selected'];
        _detailController.text = data['detail'] ?? '';
      } catch (e) {
        // Fallback
      }
    }
  }

  // Default Options for Module 2
  final List<Map<String, dynamic>> _defaultOptions = [
    {
      'id': 'full',
      'label': 'Sim, bolsa integral (100%)',
      'icon': Icons.stars,
      'isPremium': true,
      'color': AppColors.gold // Gold
    },
    {
      'id': 'partial',
      'label': 'Sim, bolsa parcial',
      'icon': Icons.star_half,
      'isPremium': true,
      'color': AppColors.silver // Silver
    },
    {
      'id': 'none',
      'label': 'Não, sem bolsa',
      'icon': Icons.money_off,
      'isPremium': false,
      'color': AppColors.error // Red
    },
  ];

  List<Map<String, dynamic>> get _options {
     if (widget.options.isEmpty) return _defaultOptions;

     return widget.options.map((label) {
       final isPremium = _isPremium(label);
       Color color = isPremium ? AppColors.gold : AppColors.textDisabled;
       if (label.toLowerCase().contains('não') || label.toLowerCase().contains('sem')) {
         color = AppColors.error;
       }
       
       return <String, dynamic>{
         'id': label,
         'label': label,
         'icon': _getIconForLabel(label),
         'isPremium': isPremium,
         'color': color,
       };
     }).toList();
  }

  bool _isPremium(String label) {
    if (label.contains('Não') || label.contains('Outra')) return false;
    return true; // Assume achievement/victory is "premium" by default
  }

  IconData _getIconForLabel(String label) {
    final l = label.toLowerCase();
    if (l.contains('metas')) return Icons.trending_up;
    if (l.contains('elogios')) return Icons.favorite_border;
    if (l.contains('processo')) return Icons.speed;
    if (l.contains('pontualidade')) return Icons.schedule;
    if (l.contains('pontualidade')) return Icons.schedule;
    if (l.contains('outra')) return Icons.edit_note;
    
    // Scholarships
    if (l.contains('sim') && l.contains('100')) return Icons.stars;
    if (l.contains('sim') || l.contains('parcial')) return Icons.star_half;
    if (l.contains('não') || l.contains('sem')) return Icons.money_off;

    // Module 4.2: Language Usage
    if (l.contains('consumo') || l.contains('conteúdo')) return Icons.headphones;
    if (l.contains('escrita') || l.contains('comunicação')) return Icons.edit_note;
    if (l.contains('conversação') || l.contains('falar')) return Icons.record_voice_over;

    return Icons.emoji_events_outlined;
  }

  @override
  void dispose() {
    _detailController.dispose();
    super.dispose();
  }

  void _emitSelection() {
    final Map<String, dynamic> response = {
      'selected': _selectedOption,
      'detail': _detailController.text,
    };
    widget.onSelect(response);
  }

  bool _shouldShowDetail(String? optionId) {
    if (optionId == null) return false;
    final label = _options.firstWhere(
      (e) => e['id'] == optionId, 
      orElse: () => <String, dynamic>{'label': ''}
    )['label'].toString().toLowerCase();
    return label.contains('sim');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _options.map((option) => _buildCard(option)).toList(),
    );
  }

  Widget _buildCard(Map<String, dynamic> option) {
    final isSelected = _selectedOption == option['id'];
    final isPremium = option['isPremium'] as bool;
    final color = option['color'] as Color;
    final showInput = isSelected && _shouldShowDetail(option['id']);

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _selectedOption = option['id']);
        _emitSelection();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : AppColors.border,
            width: isSelected ? 3 : 1,
          ),
          boxShadow: [
            if (isSelected && isPremium)
              BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            if (!isSelected)
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                 Container(
                   padding: const EdgeInsets.all(12),
                   decoration: BoxDecoration(
                     color: isSelected ? color.withOpacity(0.1) : AppColors.background,
                     shape: BoxShape.circle,
                   ),
                   child: Icon(
                     option['icon'],
                     color: isSelected ? color : AppColors.textDisabled,
                     size: 28,
                   ),
                 ),
                 const SizedBox(width: 16),
                 Expanded(
                   child: Text(
                     option['label'],
                     style: TextStyle(
                       fontSize: 18,
                       fontWeight: FontWeight.bold,
                       color: isSelected ? Colors.black87 : AppColors.textSecondary,
                     ),
                   ),
                 ),
                 if (isSelected)
                   Icon(Icons.check_circle, color: color, size: 28),
              ],
            ),
            if (showInput) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _detailController,
                onChanged: (_) => _emitSelection(),
                decoration: InputDecoration(
                  hintText: 'Qual bolsa e instituição?',
                  filled: true,
                  fillColor: AppColors.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
