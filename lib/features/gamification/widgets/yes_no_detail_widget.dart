import 'package:flutter/material.dart';
import 'dart:convert';

class YesNoDetailWidget extends StatefulWidget {
  final Function(Map<String, dynamic>) onSelect;
  final bool simpleMode;
  final String? detailLabel;
  final String? detailHint;
  final String? initialValue;

  const YesNoDetailWidget({
    super.key, 
    required this.onSelect, 
    this.simpleMode = false,
    this.detailLabel,
    this.detailHint,
    this.initialValue,
  });

  @override
  State<YesNoDetailWidget> createState() => _YesNoDetailWidgetState();
}

class _YesNoDetailWidgetState extends State<YesNoDetailWidget> {
  bool? _hasAward;
  final TextEditingController _controller = TextEditingController();

  void _update() {
    widget.onSelect({
      'has_detail': _hasAward ?? false,
      'detail_text': _hasAward == true ? _controller.text : null,
      'value': _hasAward ?? false, // Consistent key for simple boolean checks
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      try {
        final Map<String, dynamic> data = jsonDecode(widget.initialValue!);
        _hasAward = data['value'] ?? data['has_detail'];
        if (_hasAward == true) {
          _controller.text = data['detail_text'] ?? '';
        }
      } catch (e) {
        // Fallback
      }
    }
    _controller.addListener(_update);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildOption(true, 'Sim', Icons.check_circle_outline),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildOption(false, 'Não', Icons.highlight_off),
            ),
          ],
        ),
        if (_hasAward == true && !widget.simpleMode) ...[
          const SizedBox(height: 24),
          Text(
            widget.detailLabel ?? 'Qual foi o prêmio ou destaque?',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: widget.detailHint ?? 'Ex: Melhor TCC, Aluno Destaque...',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOption(bool value, String label, IconData icon) {
    final isSelected = _hasAward == value;

    return GestureDetector(
      onTap: () {
        setState(() {
          _hasAward = value;
          // Clear text logic if needed, but keeping it allows user to change mind
        });
        _update();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: isSelected ? (value ? const Color(0xFF4F46E5) : const Color(0xFFFF4B4B)) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.transparent : const Color(0xFFE5E7EB),
            width: 2,
          ),
          boxShadow: [
             if (isSelected) 
               BoxShadow(
                 color: (value ? Colors.indigo : Colors.red).withOpacity(0.3),
                 blurRadius: 8,
                 offset: const Offset(0, 4),
               )
          ],
        ),
        child: Column(
          children: [
            Icon(
              icon, 
              size: 32, 
              color: isSelected ? Colors.white : Colors.grey,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
