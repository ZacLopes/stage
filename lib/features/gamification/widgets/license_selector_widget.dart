import 'package:flutter/material.dart';

class LicenseSelectorWidget extends StatefulWidget {
  final ValueChanged<String> onSelect;
  final String? initialValue;

  const LicenseSelectorWidget({super.key, required this.onSelect, this.initialValue});

  @override
  State<LicenseSelectorWidget> createState() => _LicenseSelectorWidgetState();
}

class _LicenseSelectorWidgetState extends State<LicenseSelectorWidget> {
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      if (widget.initialValue == 'Não possuo') {
        _selectedCategory = 'NONE';
      } else {
        _selectedCategory = widget.initialValue!.replaceAll('Categoria ', '');
      }
    }
  }

  final List<Map<String, dynamic>> _options = [
    {'id': 'A', 'label': 'Categoria A', 'icon': Icons.motorcycle, 'desc': 'Motos'},
    {'id': 'B', 'label': 'Categoria B', 'icon': Icons.directions_car, 'desc': 'Carros'},
    {'id': 'AB', 'label': 'Categoria AB', 'icon': Icons.commute, 'desc': 'Carro e Moto'},
    {'id': 'CDE', 'label': 'Categorias Profissionais', 'icon': Icons.local_shipping, 'desc': 'C, D ou E'},
    {'id': 'NONE', 'label': 'Não possuo', 'icon': Icons.not_interested, 'desc': ''},
  ];

  void _handleSelect(String id) {
    setState(() {
      _selectedCategory = id;
    });
    widget.onSelect(id == 'NONE' ? 'Não possuo' : 'Categoria $id');
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _options.length,
      itemBuilder: (context, index) {
        final option = _options[index];
        final id = option['id'] as String;
        final isSelected = _selectedCategory == id;
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GestureDetector(
            onTap: () => _handleSelect(id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSelected ? (id == 'NONE' ? const Color(0xFFFEF2F2) : const Color(0xFFDDF4FF)) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? (id == 'NONE' ? const Color(0xFFFF4B4B) : const Color(0xFF1CB0F6)) : const Color(0xFFE5E7EB),
                  width: 2,
                ),
                boxShadow: [
                  if (!isSelected)
                  const BoxShadow(
                    color: Color(0xFFE5E7EB),
                    offset: Offset(0, 4),
                    blurRadius: 0,
                  )
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 48, 
                    height: 48,
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white : const Color(0xFFF3F4F6),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      option['icon'] as IconData,
                      color: isSelected ? (id == 'NONE' ? const Color(0xFFFF4B4B) : const Color(0xFF1CB0F6)) : const Color(0xFF9CA3AF),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option['label'] as String,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? (id == 'NONE' ? const Color(0xFFFF4B4B) : const Color(0xFF1F2937)) : const Color(0xFF4B5563),
                          ),
                        ),
                        if ((option['desc'] as String).isNotEmpty)
                          Text(
                            option['desc'] as String,
                            style: TextStyle(
                              fontSize: 14,
                              color: isSelected ? const Color(0xFF1899D6) : const Color(0xFF9CA3AF),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check_circle, color: id == 'NONE' ? const Color(0xFFFF4B4B) : const Color(0xFF58CC02)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
