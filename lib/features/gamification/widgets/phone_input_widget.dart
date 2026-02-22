import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PhoneInputWidget extends StatefulWidget {
  final ValueChanged<String> onSelect;
  final String? initialValue;

  const PhoneInputWidget({super.key, required this.onSelect, this.initialValue});

  @override
  State<PhoneInputWidget> createState() => _PhoneInputWidgetState();
}

class _PhoneInputWidgetState extends State<PhoneInputWidget> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _controller.text = widget.initialValue!;
    }
  }

  void _formatPhone(String value) {
    // Simple formatter logic: (XX) XXXXX-XXXX
    // In a real app, use mask_text_input_formatter
    String raw = value.replaceAll(RegExp(r'\D'), '');
    String formatted = '';
    
    if (raw.length > 0) {
      formatted += '(${raw.substring(0, raw.length >= 2 ? 2 : raw.length)}';
    }
    if (raw.length >= 2) {
      formatted += ') ';
    }
    if (raw.length > 2) {
      formatted += raw.substring(2, raw.length >= 7 ? 7 : raw.length);
    }
    if (raw.length >= 7) {
      formatted += '-${raw.substring(7, raw.length >= 11 ? 11 : raw.length)}';
    }

    if (formatted != _controller.text) {
      _controller.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
      widget.onSelect(formatted);
    } else {
        widget.onSelect(formatted);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF58CC02), width: 2), // Focus color style
          ),
          child: Row(
            children: [
              const Icon(Icons.phone, color: Color(0xFF58CC02)),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [LengthLimitingTextInputFormatter(15)], // (11) 91234-5678
                  onChanged: _formatPhone,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: '(11) 99999-9999',
                    hintStyle: TextStyle(color: Color(0xFFD1D5DB)),
                  ),
                  style: const TextStyle(fontSize: 20, letterSpacing: 1.2),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
