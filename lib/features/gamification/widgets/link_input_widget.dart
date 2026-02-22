import 'package:flutter/material.dart';

class LinkInputWidget extends StatefulWidget {
  final ValueChanged<String> onSelect;
  final String? placeholder;
  final String? prefixUrl; // e.g., "linkedin.com/in/"
  final String? initialValue;

  const LinkInputWidget({
    super.key,
    required this.onSelect,
    this.placeholder,
    this.prefixUrl,
    this.initialValue,
  });

  @override
  State<LinkInputWidget> createState() => _LinkInputWidgetState();
}

class _LinkInputWidgetState extends State<LinkInputWidget> {
  final TextEditingController _controller = TextEditingController();
  bool _noLinkedinSelected = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      if (widget.initialValue == 'Não possuo') {
        _noLinkedinSelected = true;
      } else {
        _controller.text = widget.initialValue!;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: () {
             if (_noLinkedinSelected) {
               setState(() {
                 _noLinkedinSelected = false;
                 // _controller.clear(); 
               });
               widget.onSelect(_controller.text); // Restore text if any logic allows keeping it? Or just reset?
               // If disabled, user probably wants to edit.
             }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _noLinkedinSelected ? const Color(0xFFE5E7EB) : const Color(0xFF58CC02),
                width: _noLinkedinSelected ? 2 : 2, 
              ), 
              boxShadow: const [
                BoxShadow(
                   color: Color(0xFFE5E7EB),
                   offset: Offset(0, 4),
                   blurRadius: 0,
                )
              ],
            ),
            child: AbsorbPointer(
              absorbing: _noLinkedinSelected, // Prevent TextField from consuming touches if disabled
              child: TextField(
                controller: _controller,
                enabled: true, // Keep enabled but use AbsorbPointer to manage interaction
                readOnly: _noLinkedinSelected, // Visual indication
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Cole seu link aqui...',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  prefixIcon: Icon(Icons.link, color: _noLinkedinSelected ? Colors.grey : const Color(0xFF58CC02)),
                ),
                style: TextStyle(fontSize: 18, color: _noLinkedinSelected ? Colors.grey : Colors.black),
                onChanged: (val) {
                  // If user types, ensure we are not in 'no linkedin' mode (handled by logic below mostly)
                  if (_noLinkedinSelected) {
                     setState(() { _noLinkedinSelected = false; });
                  }
                  widget.onSelect(val);
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Option to skip valid for LinkedIn question ("Não tenho ainda")
        GestureDetector(
          onTap: () {
            setState(() {
              _noLinkedinSelected = !_noLinkedinSelected; // Toggle
              if (_noLinkedinSelected) {
                 _controller.clear();
                 widget.onSelect('Não possuo');
                 FocusScope.of(context).unfocus();
              } else {
                 widget.onSelect(''); // Reset if untoggled
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            decoration: BoxDecoration(
              color: _noLinkedinSelected ? const Color(0xFFFF4B4B) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _noLinkedinSelected ? const Color(0xFFFF4B4B) : const Color(0xFFAFAFAF),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_noLinkedinSelected) ...[
                  const Icon(Icons.check, size: 20, color: Colors.white),
                  const SizedBox(width: 8),
                ],
                Text(
                  'Não tenho LinkedIn ainda',
                  style: TextStyle(
                    fontSize: 16,
                    color: _noLinkedinSelected ? Colors.white : const Color(0xFFAFAFAF),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
