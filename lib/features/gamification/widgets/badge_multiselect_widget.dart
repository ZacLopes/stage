import 'package:flutter/material.dart';

class BadgeMultiSelectWidget extends StatefulWidget {
  final Function(List<String>) onSelect;
  final List<String> options;
  final List<String>? initialValue;

  const BadgeMultiSelectWidget({
    super.key, 
    required this.onSelect, 
    this.options = const [],
    this.initialValue,
  });

  @override
  State<BadgeMultiSelectWidget> createState() => _BadgeMultiSelectWidgetState();
}

class _BadgeMultiSelectWidgetState extends State<BadgeMultiSelectWidget> {
  final Set<String> _selectedBadges = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _selectedBadges.addAll(widget.initialValue!);
    }
  }

  static const Map<String, String> _flagAssets = {
    'Inglês': 'assets/images/flags/usa.png',
    'Espanhol': 'assets/images/flags/spain.png',
    'Francês': 'assets/images/flags/france.png',
    'Alemão': 'assets/images/flags/germany.png',
    'Japonês': 'assets/images/flags/japan.png',
  };

  // Default options for Module 2 (Backward parsing)
  final List<Map<String, dynamic>> _defaultBadges = [
    {'id': 'monitoria', 'label': 'Monitoria', 'icon': Icons.class_outlined},
    {'id': 'inic_cientifica', 'label': 'Inic. Científica', 'icon': Icons.science_outlined},
    {'id': 'representante', 'label': 'Representante', 'icon': Icons.campaign_outlined},
    {'id': 'empresa_jr', 'label': 'Empresa Jr / CA', 'icon': Icons.business_center_outlined},
    {'id': 'atletica', 'label': 'Atlética', 'icon': Icons.sports_basketball_outlined},
    {'id': 'extensao', 'label': 'Extensão', 'icon': Icons.public_outlined},
  ];


  IconData _getIconForLabel(String label) {
    final l = label.toLowerCase();
    if (l.contains('trabalho') || l.contains('formal')) return Icons.work_outline;
    if (l.contains('freelance') || l.contains('bico')) return Icons.laptop_mac;
    if (l.contains('negócio') || l.contains('vendas')) return Icons.storefront;
    if (l.contains('faculdade') || l.contains('projeto')) return Icons.school_outlined;
    if (l.contains('voluntariado') || l.contains('ong')) return Icons.volunteer_activism;
    if (l.contains('não') || l.contains('nenhuma')) return Icons.block;
    
    // Extracurriculars
    if (l.contains('monitoria')) return Icons.class_outlined;
    if (l.contains('científica') || l.contains('cientifica')) return Icons.science_outlined;
    if (l.contains('atlética') || l.contains('atletica')) return Icons.sports_basketball_outlined;
    if (l.contains('empresa') || l.contains('ca')) return Icons.business_center_outlined;
    if (l.contains('acadêmico') || l.contains('academico')) return Icons.groups_outlined;
    if (l.contains('extensão') || l.contains('extensao')) return Icons.public_outlined;
    
    // Verbs (Module 3.3)
    if (l.contains('organizar')) return Icons.inventory_2_outlined;
    if (l.contains('atender')) return Icons.support_agent;
    if (l.contains('criar')) return Icons.brush_outlined;
    if (l.contains('vender')) return Icons.attach_money;
    if (l.contains('ajudar')) return Icons.handshake_outlined;
    if (l.contains('analisar')) return Icons.analytics_outlined;
    if (l.contains('liderar')) return Icons.groups_outlined;
    
    // Module 4.1: Hard Skills
    if (l.contains('design') || l.contains('criatividade')) return Icons.palette_outlined;
    if (l.contains('programação') || l.contains('tech')) return Icons.terminal;
    if (l.contains('dados') || l.contains('finanças')) return Icons.ssid_chart;
    if (l.contains('redes sociais') || l.contains('vídeo')) return Icons.video_camera_back_outlined;
    if (l.contains('office') || l.contains('trabalho')) return Icons.work_outline;

    // Module 4.2: Languages
    if (l.contains('inglês') || l.contains('espanhol') || l.contains('francês') || l.contains('alemão') || l.contains('japonês')) return Icons.translate;
    if (l.contains('outro')) return Icons.add_circle_outline;

    return Icons.star_outline;
  }

  void _toggleBadge(String id) {
    if (id.toLowerCase() == 'outro') {
      _showOtherLanguageDialog();
      return;
    }

    setState(() {
      if (_selectedBadges.contains(id)) {
        _selectedBadges.remove(id);
      } else {
        _selectedBadges.add(id);
      }
    });
    widget.onSelect(_selectedBadges.toList());
  }

  void _showOtherLanguageDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Qual outro idioma?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: 'Ex: Italiano, Russo...',
            filled: true,
            fillColor: const Color(0xFFF3F4F6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                final newLang = controller.text.trim();
                setState(() {
                  _selectedBadges.add(newLang);
                });
                widget.onSelect(_selectedBadges.toList());
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF58CC02),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Adicionar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> get _badges {
    // Original options
    final List<Map<String, dynamic>> items = [];
    
    if (widget.options.isEmpty) {
      items.addAll(_defaultBadges);
    } else {
      for (final optionLabel in widget.options) {
        String cleanLabel = optionLabel;
        if (optionLabel.toLowerCase().contains('inglês')) cleanLabel = 'Inglês';
        else if (optionLabel.toLowerCase().contains('espanhol')) cleanLabel = 'Espanhol';
        else if (optionLabel.toLowerCase().contains('francês')) cleanLabel = 'Francês';
        else if (optionLabel.toLowerCase().contains('alemão')) cleanLabel = 'Alemão';
        else if (optionLabel.toLowerCase().contains('japonês')) cleanLabel = 'Japonês';
        
        items.add({
          'id': optionLabel,
          'label': cleanLabel,
          'icon': _getIconForLabel(optionLabel),
          'asset': _flagAssets[cleanLabel],
        });
      }
    }

    // Add selected items that are not in the predefined list
    final predefinedIds = items.map((e) => e['id']).toSet();
    for (final selectedId in _selectedBadges) {
      if (!predefinedIds.contains(selectedId)) {
        items.insert(items.length > 0 ? items.length - 1 : 0, {
          'id': selectedId,
          'label': selectedId,
          'icon': _getIconForLabel(selectedId),
          'asset': null,
          'isCustom': true,
        });
      }
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.15,
      ),
      itemCount: _badges.length,
      itemBuilder: (context, index) {
        final badge = _badges[index];
        final isSelected = _selectedBadges.contains(badge['id']);
        final isNone = badge['label'].toLowerCase().contains('nenhuma') || badge['label'].toLowerCase().contains('não');
        final isOther = badge['id'].toLowerCase() == 'outro';
        
        // Use a more vibrant purple/blue like Duolingo if selected
        final Color activeColor = isNone 
            ? const Color(0xFFFF4B4B) 
            : (isOther ? const Color(0xFF6B7280) : const Color(0xFF6366F1));

        return GestureDetector(
          onTap: () => _toggleBadge(badge['id']),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: isSelected ? activeColor : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? activeColor : const Color(0xFFE5E7EB),
                width: 2.5,
              ),
              boxShadow: [
                if (!isSelected)
                  const BoxShadow(
                    color: Color(0xFFE5E7EB),
                    offset: Offset(0, 4),
                    blurRadius: 0,
                  ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (badge['asset'] != null)
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(2.0),
                      child: ClipOval(
                        child: Image.asset(
                          badge['asset'],
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  )
                else
                  Icon(
                    badge['icon'],
                    size: 32,
                    color: isSelected ? Colors.white : const Color(0xFF9CA3AF),
                  ),
                const SizedBox(height: 10),
                Text(
                  badge['label'],
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : const Color(0xFF374151),
                    fontSize: 14,
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
