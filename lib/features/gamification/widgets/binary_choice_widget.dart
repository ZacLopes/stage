import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BinaryChoiceWidget extends StatelessWidget {
  final Function(String) onSelect;
  final String? selectedOption;
  final List<String> options;

  const BinaryChoiceWidget({
    super.key,
    required this.onSelect,
    this.selectedOption,
    this.options = const [],
  });

  @override
  Widget build(BuildContext context) {
    // defaults
    String noSubLabel = 'Esta é minha primeira e única graduação.';
    String yesSubLabel = 'Já estudei em outra faculdade ou fiz um curso anterior.';

    // Try to parse from options if available
    // Expected format: ["Sim, ...", "Não, ..."]
    if (options.isNotEmpty) {
      final yesOpt = options.firstWhere((e) => e.toLowerCase().startsWith('sim'), orElse: () => '');
      final noOpt = options.firstWhere((e) => e.toLowerCase().startsWith('não') || e.toLowerCase().startsWith('nao'), orElse: () => '');
      
      if (yesOpt.isNotEmpty) yesSubLabel = yesOpt;
      if (noOpt.isNotEmpty) noSubLabel = noOpt;
    }

    return Column(
      children: [
        _buildCard(
          context,
          label: 'Não',
          subLabel: noSubLabel,
          icon: Icons.school_outlined,
          color: const Color(0xFFFF4B4B),
          value: 'Não',
          isSelected: selectedOption == 'Não' || (selectedOption != null && selectedOption!.startsWith('Não')),
        ),
        const SizedBox(height: 16),
        _buildCard(
          context,
          label: 'Sim',
          subLabel: yesSubLabel,
          icon: Icons.history_edu,
          color: const Color(0xFF58CC02),
          value: 'Sim',
          isSelected: selectedOption == 'Sim' || (selectedOption != null && selectedOption!.startsWith('Sim')),
        ),
      ],
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required String label,
    required String subLabel,
    required IconData icon,
    required Color color,
    required String value,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onSelect(value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : Colors.black.withOpacity(0.05),
            width: isSelected ? 3 : 2,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected ? color.withOpacity(0.2) : Colors.black.withOpacity(0.05),
              offset: const Offset(0, 4),
              blurRadius: 12,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSelected ? color : color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon, 
                color: isSelected ? Colors.white : color, 
                size: 32
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subLabel,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[300], size: 28),
          ],
        ),
      ),
    );
  }
}
