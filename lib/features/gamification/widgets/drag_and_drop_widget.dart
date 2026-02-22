import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';

class DragAndDropWidget extends StatefulWidget {
  final List<String> options;
  final Function(List<String>) onSelect;
  final List<String>? initialValue;

  const DragAndDropWidget({
    super.key, 
    this.options = const [],
    required this.onSelect,
    this.initialValue,
  });

  @override
  State<DragAndDropWidget> createState() => _DragAndDropWidgetState();
}

class _DragAndDropWidgetState extends State<DragAndDropWidget> {
  late List<String> _items;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null && widget.initialValue!.isNotEmpty) {
      _items = List.from(widget.initialValue!);
    } else if (widget.options.isNotEmpty) {
      _items = List.from(widget.options);
    } else {
      _items = [
        'Falando e Apresentando',
        'Escrevendo e Estruturando',
        'Visualizando e Criando',
        'Ouvindo e Pesquisando',
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Helper text
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app, size: 16, color: Color(0xFF6B7280)),
              SizedBox(width: 8),
              Text(
                'Arraste para reordenar sua ordem de preferência',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
        
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          proxyDecorator: (child, index, animation) {
            return AnimatedBuilder(
              animation: animation,
              builder: (BuildContext context, Widget? child) {
                final double animValue = Curves.easeInOut.transform(animation.value);
                final double elevation = lerpDouble(0, 8, animValue)!;
                return Material(
                  elevation: elevation,
                  color: Colors.transparent,
                  shadowColor: _getThemeColor(_items[index]).withOpacity(0.3),
                  borderRadius: BorderRadius.circular(20),
                  child: child,
                );
              },
              child: child,
            );
          },
          onReorder: (int oldIndex, int newIndex) {
            HapticFeedback.mediumImpact();
            setState(() {
              if (oldIndex < newIndex) {
                newIndex -= 1;
              }
              final String item = _items.removeAt(oldIndex);
              _items.insert(newIndex, item);
            });
            widget.onSelect(_items);
          },
          children: [
            for (int index = 0; index < _items.length; index++)
              ReorderableDragStartListener(
                key: ValueKey(_items[index]),
                index: index,
                child: _buildReorderableItem(index),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildReorderableItem(int index) {
    final item = _items[index];
    final color = _getThemeColor(item);
    final icon = _getIconData(item);

    return Container(
      key: ValueKey(item),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            offset: const Offset(0, 4),
            blurRadius: 0, // Hard shadow like Duolingo
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Rank indicator with color
              Container(
                width: 50,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  border: Border(
                    right: BorderSide(color: color.withOpacity(0.2), width: 2),
                  ),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}º',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                ),
              ),
              
              const SizedBox(width: 16),
              
              // Icon
              Icon(icon, color: color, size: 28),
              
              const SizedBox(width: 16),
              
              // Text
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    item,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF374151),
                      height: 1.2,
                    ),
                  ),
                ),
              ),
              
              // Drag handle
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.drag_indicator_rounded, color: color.withOpacity(0.4), size: 28),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getThemeColor(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('falando')) return const Color(0xFF1CB0F6); // Blue
    if (lower.contains('escrevendo')) return const Color(0xFFFFB900); // Yellow/Gold
    if (lower.contains('visualizando')) return const Color(0xFFA64DFF); // Purple
    if (lower.contains('ouvindo')) return const Color(0xFF58CC02); // Green
    
    // Career Success values
    if (lower.contains('mestria')) return const Color(0xFF1CB0F6);
    if (lower.contains('impacto')) return const Color(0xFFFF4B4B); // Red
    if (lower.contains('ascensão')) return const Color(0xFFFFB900);
    if (lower.contains('estabilidade')) return const Color(0xFF58CC02);
    if (lower.contains('autonomia')) return const Color(0xFFA64DFF);
    
    return const Color(0xFF58CC02); // Default green
  }

  IconData _getIconData(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('falando')) return Icons.record_voice_over_rounded;
    if (lower.contains('escrevendo')) return Icons.edit_note_rounded;
    if (lower.contains('visualizando')) return Icons.palette_rounded;
    if (lower.contains('ouvindo')) return Icons.graphic_eq_rounded;
    
    // Career Success values
    if (lower.contains('mestria')) return Icons.workspace_premium_rounded;
    if (lower.contains('impacto')) return Icons.favorite_rounded;
    if (lower.contains('ascensão')) return Icons.trending_up_rounded;
    if (lower.contains('estabilidade')) return Icons.shield_rounded;
    if (lower.contains('autonomia')) return Icons.anchor_rounded;
    
    return Icons.star_rounded;
  }
}
