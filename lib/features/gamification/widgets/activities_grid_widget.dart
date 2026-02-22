import 'dart:convert';
import 'package:flutter/material.dart';

class ActivitiesGridWidget extends StatefulWidget {
  final Function(String) onSelect;
  final List<String> options; // JSON strings
  final String? initialValue; // JSON string

  const ActivitiesGridWidget({
    super.key,
    required this.onSelect,
    this.options = const [],
    this.initialValue,
  });

  @override
  State<ActivitiesGridWidget> createState() => _ActivitiesGridWidgetState();
}

class _ActivitiesGridWidgetState extends State<ActivitiesGridWidget> {
  final Map<String, Map<String, dynamic>> _selectedItems = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      try {
        final List<dynamic> list = jsonDecode(widget.initialValue!);
        for (var item in list) {
          if (item is Map<String, dynamic>) {
             final id = item['id'];
             if (id != null) {
               _selectedItems[id] = item;
             }
          }
        }
      } catch (e) {
        // Fallback or ignore
      }
    }
  }

  void _handleCardTap(Map<String, dynamic> option) {
    if (option['id'] == 'none') {
      // "Não participei" logic: Clear everything else
      setState(() {
        _selectedItems.clear();
        _selectedItems['none'] = {'id': 'none', 'label': option['label']};
      });
      _emitSelection();
    } else {
      // If "none" was previously selected, clear it
      if (_selectedItems.containsKey('none')) {
        setState(() {
          _selectedItems.remove('none');
        });
      }
      
      // Open detailed popup
      _showDetailDialog(context, option);
    }
  }

  void _emitSelection() {
    widget.onSelect(jsonEncode(_selectedItems.values.toList()));
  }

  void _showDetailDialog(BuildContext context, Map<String, dynamic> option) {
    final existingData = _selectedItems[option['id']];
    
    final detailController = TextEditingController(text: existingData?['detail'] ?? '');
    final reflectionController = TextEditingController(text: existingData?['reflection'] ?? '');
    
    // Theme colors
    const primaryColor = Color(0xFF58CC02);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            top: 24, left: 24, right: 24,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Icon(_getIconData(option['icon']), color: primaryColor, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        option['label'],
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF374151)),
                      ),
                    ),
                    IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Color(0xFF9CA3AF))
                    )
                  ],
                ),
                const SizedBox(height: 24),

                // Field 1
                Text(
                  option['detailTitle'] ?? 'Detalhes',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF374151)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: detailController,
                  decoration: InputDecoration(
                    hintText: 'Digite aqui...',
                    filled: true,
                    fillColor: const Color(0xFFF3F4F6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 20),

                // Field 2 (Reflection)
                Text(
                  option['reflectiveTitle'] ?? 'Reflexão',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF374151)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: reflectionController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Conte um pouco sobre sua experiência...',
                    filled: true,
                    fillColor: const Color(0xFFF3F4F6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 32),

                // Save Button
                ElevatedButton(
                  onPressed: () {
                    final newData = {
                      'id': option['id'],
                      'label': option['label'],
                      'detail': detailController.text,
                      'reflection': reflectionController.text,
                    };

                    setState(() {
                      _selectedItems[option['id']] = newData;
                    });
                    
                    _emitSelection();
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: const Text('SALVAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _getIconData(String? iconName) {
    switch(iconName) {
      case 'groups': return Icons.groups_outlined;
      case 'public': return Icons.public;
      case 'rocket_launch': return Icons.rocket_launch_outlined;
      case 'sports_soccer': return Icons.sports_soccer;
      case 'star': return Icons.star_border;
      case 'block': return Icons.block;
      default: return Icons.category_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Parse options from JSON strings
    final List<Map<String, dynamic>> parsedOptions = widget.options.map((e) {
      try {
        return jsonDecode(e) as Map<String, dynamic>;
      } catch (_) {
        return <String, dynamic>{};
      }
    }).where((e) => e.isNotEmpty).toList();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.2,
      ),
      itemCount: parsedOptions.length,
      itemBuilder: (context, index) {
        final option = parsedOptions[index];
        final isSelected = _selectedItems.containsKey(option['id']);
        final isNone = option['id'] == 'none';
        final activeColor = isNone ? const Color(0xFFFF4B4B) : const Color(0xFF58CC02);

        return GestureDetector(
          onTap: () => _handleCardTap(option),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected ? activeColor.withOpacity(0.1) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? activeColor : const Color(0xFFE5E7EB),
                width: isSelected ? 2 : 1.5,
              ),
              boxShadow: isSelected ? [] : [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset:const Offset(0, 2))
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected ? activeColor : const Color(0xFFF3F4F6),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getIconData(option['icon']),
                    color: isSelected ? Colors.white : const Color(0xFF6B7280),
                    size: 28,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  option['label'] ?? '',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: isSelected ? activeColor : const Color(0xFF374151),
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
