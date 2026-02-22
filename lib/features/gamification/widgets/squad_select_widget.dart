import 'package:flutter/material.dart';

class SquadSelectWidget extends StatefulWidget {
  final Function(List<String>) onSelect;
  final List<String>? initialValue;

  const SquadSelectWidget({
    super.key, 
    required this.onSelect,
    this.initialValue,
  });

  @override
  State<SquadSelectWidget> createState() => _SquadSelectWidgetState();
}

class _SquadSelectWidgetState extends State<SquadSelectWidget> {
  final List<String> _selectedIds = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _selectedIds.addAll(widget.initialValue!);
    }
  }

  final List<Map<String, dynamic>> _squads = [
    {'id': 'marketing', 'title': 'Marketing & Criação', 'desc': 'Criar campanhas, cuidar das redes sociais.', 'icon': Icons.palette_outlined},
    {'id': 'sales', 'title': 'Vendas & Comercial', 'desc': 'Negociar com clientes, fechar parcerias.', 'icon': Icons.storefront},
    {'id': 'finance', 'title': 'Financeiro & Adm', 'desc': 'Cuidar do dinheiro, organizar contas.', 'icon': Icons.attach_money},
    {'id': 'tech', 'title': 'Tecnologia & Dados', 'desc': 'Programar, desenvolver sites, analisar números.', 'icon': Icons.terminal},
    {'id': 'hr', 'title': 'Pessoas & RH', 'desc': 'Contratar talentos, treinar o time.', 'icon': Icons.groups_outlined},
    {'id': 'ops', 'title': 'Operações & Logística', 'desc': 'Fazer a mágica acontecer nos bastidores.', 'icon': Icons.local_shipping_outlined},
    {'id': 'legal', 'title': 'Jurídico & Compliance', 'desc': 'Cuidar de contratos, leis e regras.', 'icon': Icons.gavel},
  ];

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        if (_selectedIds.length < 2) {
          _selectedIds.add(id);
        } else {
          // Optional: Show snackbar "Maximum 2 selected"
        }
      }
    });
    widget.onSelect(_selectedIds);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Text(
            'Selecionado: ${_selectedIds.length}/2',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF6B7280),
            ),
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _squads.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.85,
          ),
          itemBuilder: (context, index) {
            final squad = _squads[index];
            final isSelected = _selectedIds.contains(squad['id']);
            final isFull = _selectedIds.length >= 2;
            final isDisabled = !isSelected && isFull;

            return GestureDetector(
              onTap: () {
                if (!isDisabled) _toggleSelection(squad['id']!);
              },
              child: AnimatedOpacity(
                opacity: isDisabled ? 0.5 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFDDF4FF) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF1CB0F6) : const Color(0xFFE5E7EB),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF1899D6) : const Color(0xFFF3F4F6),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          squad['icon'], 
                          size: 16, 
                          color: isSelected ? Colors.white : const Color(0xFF9CA3AF)
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        squad['title']!,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? const Color(0xFF1899D6) : const Color(0xFF374151),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: Text(
                          squad['desc']!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF6B7280),
                            height: 1.2,
                          ),
                        ),
                      ),
                      if(isSelected)
                        const Align(
                          alignment: Alignment.centerRight,
                          child: Icon(Icons.check_circle, size: 20, color: Color(0xFF1CB0F6)),
                        )
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
