import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/theme.dart';

class IconSelectWidget extends StatefulWidget {
  final Function(String) onSelect;
  final List<String> options;
  final String? initialValue;

  const IconSelectWidget({
    super.key, 
    required this.onSelect, 
    this.options = const [],
    this.initialValue,
  });

  @override
  State<IconSelectWidget> createState() => _IconSelectWidgetState();
}

class _IconSelectWidgetState extends State<IconSelectWidget> {
  String? _selectedOption;

  @override
  void initState() {
    super.initState();
    _selectedOption = widget.initialValue;
  }

  // Study period options used when widget.options is empty
  final List<Map<String, dynamic>> _defaultOptions = [
    {'id': 'morning', 'label': 'Matutino', 'icon': Icons.wb_sunny_rounded, 'color': AppColors.warning},
    {'id': 'afternoon', 'label': 'Vespertino', 'icon': Icons.light_mode_rounded, 'color': const Color(0xFFF97316)},
    {'id': 'night', 'label': 'Noturno', 'icon': Icons.nights_stay_rounded, 'color': AppColors.primary},
    {'id': 'flex', 'label': 'EAD / Flex', 'icon': Icons.computer_rounded, 'color': AppColors.info},
  ];

  List<Map<String, dynamic>> get _options {
    if (widget.options.isEmpty) return _defaultOptions;

    // Premium Duo color palette
    final colors = [
      AppColors.success, // Green
      AppColors.secondary, // Blue
      const Color(0xFFA64DFF), // Purple
      AppColors.warning, // Gold
      AppColors.error, // Red
      const Color(0xFF2B70C9), // Navy
      const Color(0xFFCE82FF), // Pink
    ];

    return widget.options.asMap().entries.map((entry) {
      final index = entry.key;
      final label = entry.value;
      return {
        'id': label,
        'label': label,
        'icon': _getIconForLabel(label),
        'color': colors[index % colors.length],
      };
    }).toList();
  }

  IconData _getIconForLabel(String label) {
    final l = label.toLowerCase();
    if (l.contains('whatsapp') || l.contains('chat')) return Icons.chat_rounded;
    if (l.contains('excel') || l.contains('planilha')) return Icons.table_view_rounded;
    if (l.contains('canva') || l.contains('design')) return Icons.brush_rounded;
    if (l.contains('office') || l.contains('word') || l.contains('ppt')) return Icons.description_rounded;
    if (l.contains('telefone') || l.contains('atendimento')) return Icons.phone_callback_rounded;
    if (l.contains('caixa') || l.contains('pagamento')) return Icons.savings_rounded;
    if (l.contains('ferramentas')) return Icons.construction_rounded;
    
    // Study Periods
    if (l.contains('matutino') || l.contains('manhã')) return Icons.wb_sunny_rounded;
    if (l.contains('vespertino') || l.contains('tarde')) return Icons.light_mode_rounded;
    if (l.contains('noturno') || l.contains('noite')) return Icons.nights_stay_rounded;
    if (l.contains('integral')) return Icons.all_inclusive_rounded;
    if (l.contains('ead')) return Icons.computer_rounded;

    return Icons.extension_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.95,
      ),
      itemCount: _options.length,
      itemBuilder: (context, index) {
        final option = _options[index];
        final isSelected = _selectedOption == option['id'];
        final color = option['color'] as Color;

        return GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            setState(() => _selectedOption = option['id']);
            widget.onSelect(option['id']);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutBack,
            decoration: BoxDecoration(
              color: isSelected ? color.withOpacity(0.08) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isSelected ? color : AppColors.border,
                width: isSelected ? 3.5 : 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSelected ? color.withOpacity(0.2) : Colors.black.withOpacity(0.04),
                  offset: const Offset(0, 5),
                  blurRadius: 0, // Hard shadow for 3D effect
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon Wrap
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isSelected ? color : AppColors.background,
                    shape: BoxShape.circle,
                    boxShadow: isSelected ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        offset: const Offset(0, 3),
                        blurRadius: 0,
                      )
                    ] : null,
                  ),
                  child: Icon(
                    option['icon'] as IconData,
                    color: isSelected ? Colors.white : AppColors.textDisabled,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 14),
                
                // Label
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    option['label'].toString().toUpperCase(),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: 0.5,
                      color: isSelected ? color : AppColors.textSecondary,
                    ),
                  ),
                ),
                
                // Active indicator
                if (isSelected) 
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    height: 4,
                    width: 30,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
