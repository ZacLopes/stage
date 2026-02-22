import 'package:flutter/material.dart';

class MiniTextBoxWidget extends StatefulWidget {
  final Function(String) onSelect;
  final String? initialValue;

  const MiniTextBoxWidget({
    super.key, 
    required this.onSelect, 
    this.initialValue
  });

  @override
  State<MiniTextBoxWidget> createState() => _MiniTextBoxWidgetState();
}

class _MiniTextBoxWidgetState extends State<MiniTextBoxWidget> {
  final TextEditingController _controller = TextEditingController();
  static const int _maxLength = 180;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _controller.text = widget.initialValue!;
    }
    _controller.addListener(() {
      widget.onSelect(_controller.text);
      setState(() {}); // refresh counter
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB), width: 2),
          ),
          child: TextField(
            controller: _controller,
            maxLength: _maxLength,
            maxLines: 4,
            style: const TextStyle(fontSize: 16, color: Color(0xFF374151)),
            decoration: const InputDecoration(
              hintText: 'Ex: Fui responsável por organizar a semana da computação...',
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(16),
              counterText: '', // Hide default counter to make custom one
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${_controller.text.length} / $_maxLength',
          style: TextStyle(
            color: _controller.text.length > _maxLength ? Colors.red : Colors.grey,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
