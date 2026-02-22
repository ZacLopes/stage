import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DynamicListInputWidget extends StatefulWidget {
  final Function(List<String>) onSelect;
  final String? hintText;
  final String? inputLabel;
  final List<String> suggestions;
  final int? maxSelections;
  final List<String>? initialValue;

  const DynamicListInputWidget({
    super.key,
    required this.onSelect,
    this.hintText,
    this.inputLabel,
    this.suggestions = const [],
    this.maxSelections,
    this.initialValue,
  });

  @override
  State<DynamicListInputWidget> createState() => _DynamicListInputWidgetState();
}

class _DynamicListInputWidgetState extends State<DynamicListInputWidget> {
  final TextEditingController _controller = TextEditingController();
  TextEditingController? _autocompleteController;
  String _currentText = '';
  bool _isShowingSnackBar = false;
  final List<String> _items = [];
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _items.addAll(widget.initialValue!);
    }
  }

  void _addItem(String text) {
    if (text.trim().isEmpty) return;

    if (widget.maxSelections != null && _items.length >= widget.maxSelections!) {
      if (_isShowingSnackBar) return;

      _isShowingSnackBar = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Você só pode selecionar até ${widget.maxSelections} opções.'),
          backgroundColor: const Color(0xFFFF4B4B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ).closed.then((_) {
        if (mounted) _isShowingSnackBar = false;
      });
      
      _controller.clear();
      _currentText = '';
      _autocompleteController?.clear();
      return;
    }

    if (!_items.contains(text.trim())) {
      HapticFeedback.lightImpact();
      setState(() {
        _items.add(text.trim());
        _controller.clear();
        _currentText = '';
        _autocompleteController?.clear();
      });
      widget.onSelect(_items);
    } else {
      // Already added
      _controller.clear();
      _currentText = '';
      _autocompleteController?.clear();
    }
  }

  void _removeItem(String item) {
    HapticFeedback.mediumImpact();
    setState(() {
      _items.remove(item);
    });
    widget.onSelect(_items);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Input Area
        Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE5E7EB), width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      offset: const Offset(0, 4),
                      blurRadius: 0,
                    )
                  ],
                ),
                child: widget.suggestions.isEmpty 
                  ? TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      decoration: InputDecoration(
                        hintText: widget.hintText ?? 'Digite aqui...',
                        hintStyle: const TextStyle(color: Color(0xFFABB2B9)),
                        border: InputBorder.none,
                        prefixIcon: const Icon(Icons.add_circle_outline, color: Color(0xFF1CB0F6)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                      onSubmitted: (val) => _addItem(val),
                    )
                  : Autocomplete<String>(
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        _currentText = textEditingValue.text;
                        if (textEditingValue.text == '') {
                          return widget.suggestions;
                        }
                        return widget.suggestions.where((String option) {
                          return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                        });
                      },
                      onSelected: (String selection) {
                        _addItem(selection);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                           _autocompleteController?.clear();
                        });
                      },
                      fieldViewBuilder: (context, fieldTextEditingController, fieldFocusNode, onFieldSubmitted) {
                        _autocompleteController = fieldTextEditingController;
                        return TextField(
                          controller: fieldTextEditingController,
                          focusNode: fieldFocusNode,
                          onChanged: (val) => _currentText = val,
                          decoration: InputDecoration(
                            hintText: widget.hintText ?? 'Digite ou selecione...',
                            hintStyle: const TextStyle(color: Color(0xFFABB2B9)),
                            border: InputBorder.none,
                            prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF1CB0F6)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          ),
                          onSubmitted: (val) {
                             _addItem(val);
                             fieldTextEditingController.clear();
                          },
                        );
                      },
                      optionsViewBuilder: (context, onSelected, options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 8.0,
                            shadowColor: Colors.black26,
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              width: MediaQuery.of(context).size.width - 100,
                              margin: const EdgeInsets.only(top: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFFE5E7EB), width: 2),
                              ),
                              constraints: const BoxConstraints(maxHeight: 250),
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shrinkWrap: true,
                                itemCount: options.length,
                                separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF3F4F6)),
                                itemBuilder: (BuildContext context, int index) {
                                  final String option = options.elementAt(index);
                                  final bool isSelected = _items.contains(option);
                                  
                                  return InkWell(
                                    onTap: () => onSelected(option),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      color: isSelected ? const Color(0xFFF3FFEF) : Colors.transparent,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                      child: Row(
                                        children: [
                                          Icon(
                                            _getIconForOption(option), 
                                            size: 20, 
                                            color: isSelected ? const Color(0xFF58CC02) : const Color(0xFF6B7280)
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              option,
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                                                color: isSelected ? const Color(0xFF58CC02) : const Color(0xFF374151),
                                              ),
                                            ),
                                          ),
                                          Icon(
                                            isSelected ? Icons.check_circle_rounded : Icons.add_rounded, 
                                            size: 18, 
                                            color: isSelected ? const Color(0xFF58CC02) : const Color(0xFF1CB0F6)
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () {
                String textToAdd = widget.suggestions.isEmpty ? _controller.text : _currentText;
                _addItem(textToAdd);
                _focusNode.unfocus();
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1CB0F6),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1899D6),
                      offset: const Offset(0, 4),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 30),
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 32),
        
        // Selected Items List
        if (_items.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 40),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFF3F4F6), width: 2, style: BorderStyle.solid),
            ),
            child: Column(
              children: [
                Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey[300]),
                const SizedBox(height: 12),
                Text(
                  'Nenhuma área selecionada',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ITENS ADICIONADOS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF9CA3AF),
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _items.map((item) {
                  return Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDDF4FF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF1CB0F6), width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF1899D6).withOpacity(0.2),
                          offset: const Offset(0, 3),
                          blurRadius: 0,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Color(0xFF1899D6),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _removeItem(item),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Color(0xFF1CB0F6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
      ],
    );
  }

  IconData _getIconForOption(String option) {
    final lower = option.toLowerCase();
    if (lower.contains('vendas') || lower.contains('negócios')) return Icons.trending_up_rounded;
    if (lower.contains('marketing') || lower.contains('branding')) return Icons.campaign_rounded;
    if (lower.contains('finanças') || lower.contains('capital')) return Icons.payments_rounded;
    if (lower.contains('tecnologia') || lower.contains('programação')) return Icons.code_rounded;
    if (lower.contains('dados') || lower.contains('intelligence')) return Icons.insights_rounded;
    if (lower.contains('produto') || lower.contains('ux')) return Icons.design_services_rounded;
    if (lower.contains('humanos') || lower.contains('cultura')) return Icons.groups_rounded;
    if (lower.contains('operações') || lower.contains('logística')) return Icons.local_shipping_rounded;
    if (lower.contains('consultoria')) return Icons.lightbulb_rounded;
    if (lower.contains('administração')) return Icons.assignment_rounded;
    if (lower.contains('explorando')) return Icons.explore_rounded;
    return Icons.star_rounded;
  }
}
