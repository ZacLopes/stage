import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class VisionCardsWidget extends StatefulWidget {
  final Function(String) onSelect;
  final String? initialValue;

  const VisionCardsWidget({
    super.key, 
    required this.onSelect,
    this.initialValue,
  });

  @override
  State<VisionCardsWidget> createState() => _VisionCardsWidgetState();
}

class _VisionCardsWidgetState extends State<VisionCardsWidget> {
  String? _selectedId;
  PageController? _pageController;
  int _currentPage = 0;

  static final List<Map<String, dynamic>> _visions = [
    {
      'id': 'founder',
      'title': 'O Fundador',
      'desc': 'Criar, Inovar e Escalar',
      'detail': 'Quero criar minha própria startup do zero e transformar ideias em negócios de alto crescimento.',
      'icon': Icons.rocket_launch_rounded,
      'color': const Color(0xFF58CC02), // Green
    },
    {
      'id': 'ceo',
      'title': 'O Líder Executivo',
      'desc': 'Gerir, Liderar e Decidir',
      'detail': 'Quero subir na hierarquia de grandes empresas, gerir pessoas e tomar decisões estratégicas.',
      'icon': Icons.account_balance_rounded,
      'color': const Color(0xFF1CB0F6), // Blue
    },
    {
      'id': 'master',
      'title': 'O Especialista',
      'desc': 'Dominar e Referenciar',
      'detail': 'Quero dominar profundamente uma área técnica e ser a maior referência do mercado.',
      'icon': Icons.workspace_premium_rounded,
      'color': const Color(0xFFFFB900), // Gold
    },
    {
      'id': 'strategist',
      'title': 'O Estrategista',
      'desc': 'Analisar e Impulsionar',
      'detail': 'Quero analisar números, otimizar operações ou atuar com investimentos para impulsionar empresas.',
      'icon': Icons.query_stats_rounded,
      'color': const Color(0xFFA64DFF), // Purple
    },
  ];

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialValue;
    
    int initialPage = 0;
    if (_selectedId != null) {
      initialPage = _visions.indexWhere((v) => v['id'] == _selectedId);
      if (initialPage == -1) initialPage = 0;
      _currentPage = initialPage;
    }

    _pageController = PageController(
      viewportFraction: 0.82,
      initialPage: initialPage,
    );
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_pageController == null) {
      return const SizedBox(height: 480, child: Center(child: CircularProgressIndicator()));
    }

    return Column(
      children: [
        SizedBox(
          height: 480,
          child: PageView.builder(
            controller: _pageController,
            itemCount: _visions.length,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
            },
            itemBuilder: (context, index) {
              final vision = _visions[index];
              final isSelected = _selectedId == vision['id'];
              final color = (vision['color'] as Color?) ?? Colors.green;

              return GestureDetector(
                onTap: () {
                   HapticFeedback.lightImpact();
                   setState(() => _selectedId = vision['id']);
                   widget.onSelect(vision['id']!);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
                  decoration: BoxDecoration(
                    color: isSelected ? color.withOpacity(0.05) : Colors.white,
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(
                      color: isSelected ? color : const Color(0xFFE5E7EB),
                      width: isSelected ? 3.5 : 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isSelected ? color.withOpacity(0.15) : Colors.black.withOpacity(0.04),
                        offset: const Offset(0, 6),
                        blurRadius: 0, 
                      )
                    ],
                  ),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // Icon badge
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          vision['icon'],
                          size: 48,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 20),
                      
                      // Title
                      Text(
                        vision['title']!,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF374151),
                          letterSpacing: -0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      
                      // Secondary Label
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          vision['desc']!.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 1,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      
                      const SizedBox(height: 18),
                      
                      // Detail Text
                      Expanded(
                        child: Text(
                          vision['detail']!,
                          style: TextStyle(
                            fontSize: 15,
                            color: const Color(0xFF6B7280),
                            height: 1.4,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      
                      const SizedBox(height: 12),

                      // Selection Indicator Button
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: isSelected ? color : const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: isSelected ? [
                            BoxShadow(
                              color: color.withOpacity(0.3),
                              offset: const Offset(0, 4),
                              blurRadius: 0,
                            )
                          ] : [
                            const BoxShadow(
                              color: Color(0xFFE5E7EB),
                              offset: Offset(0, 4),
                              blurRadius: 0,
                            )
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isSelected ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
                              color: isSelected ? Colors.white : const Color(0xFF9CA3AF),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isSelected ? 'SELECIONADO' : 'ESCOLHER ESSA VISÃO',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: isSelected ? Colors.white : const Color(0xFF9CA3AF),
                                letterSpacing: 1,
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
        ),
        
        // Page Indicator (Dots)
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_visions.length, (index) {
            final isCurrent = _currentPage == index;
            final color = (_visions[index]['color'] as Color?) ?? Colors.green;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              height: 10,
              width: isCurrent ? 24 : 10,
              decoration: BoxDecoration(
                color: isCurrent ? color : const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(5),
              ),
            );
          }),
        ),
      ],
    );
  }
}
