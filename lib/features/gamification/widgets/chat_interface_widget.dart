import 'package:flutter/material.dart';

class ChatInterfaceWidget extends StatefulWidget {
  final Function(String) onSelect;
  final bool isInputMode;
  final String? recruiterMessage;
  final String? hintText;

  const ChatInterfaceWidget({
    super.key, 
    required this.onSelect,
    this.isInputMode = false,
    this.recruiterMessage,
    this.hintText,
  });

  @override
  State<ChatInterfaceWidget> createState() => _ChatInterfaceWidgetState();
}

class _ChatInterfaceWidgetState extends State<ChatInterfaceWidget> {
  String? _selectedId;
  final TextEditingController _textController = TextEditingController();
  static const int _maxLength = 200;

  final List<Map<String, String>> _defaultMessages = [
    {
      'id': 'direct',
      'text': 'Direto e Reto: gosto que vá direto ao ponto e me diga exatamente o que errei para eu corrigir logo.',
    },
    {
      'id': 'sandwich',
      'text': 'Sanduíche: prefiro que destaque o que fiz de bom antes de apontar os erros, para eu não desanimar.',
    },
    {
      'id': 'data_driven',
      'text': 'Baseado em Dados: prefiro exemplos ou números que provem onde errei, para eu entender a lógica.',
    },
  ];

  @override
  void initState() {
    super.initState();
    if (widget.isInputMode) {
      _textController.addListener(_onTextChanged);
    }
  }

  void _onTextChanged() {
    widget.onSelect(_textController.text);
    setState(() {});
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isInputMode) {
      return _buildInputMode();
    }
    return _buildChoiceMode();
  }

  Widget _buildInputMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Recruiter Bubble (Left)
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              backgroundColor: Color(0xFF58CC02),
              child: Icon(Icons.person, color: Colors.white),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(20),
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                ),
                child: Text(
                  widget.recruiterMessage ?? 'Conte-nos mais sobre isso...',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF374151),
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        
        // User Input Bubble (Right)
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Expanded(
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.end,
                 children: [
                   Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                          bottomLeft: Radius.circular(20),
                          bottomRight: Radius.circular(4),
                        ),
                        border: Border.all(color: const Color(0xFFE5E7EB), width: 2),
                      ),
                      child: TextField(
                        controller: _textController,
                        maxLength: _maxLength,
                        maxLines: null, // Grows
                        minLines: 3,
                        style: const TextStyle(fontSize: 16, color: Color(0xFF374151)),
                        decoration: InputDecoration(
                          hintText: widget.hintText ?? 'Digite sua resposta...',
                          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(16),
                          counterText: '',
                        ),
                      ),
                   ),
                   const SizedBox(height: 8),
                   Text(
                      '${_textController.text.length} / $_maxLength',
                      style: TextStyle(
                        color: _textController.text.length > _maxLength ? Colors.red : Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                   ),
                 ],
               ),
             ),
             const SizedBox(width: 8),
             const CircleAvatar(
               backgroundColor: Color(0xFF1CB0F6),
               child: Icon(Icons.edit, color: Colors.white, size: 20),
             ),
          ],
        ),
      ],
    );
  }

  Widget _buildChoiceMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _defaultMessages.map((msg) {
        final isSelected = _selectedId == msg['id'];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: GestureDetector(
            onTap: () {
               setState(() => _selectedId = msg['id']);
               widget.onSelect(msg['id']!);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF1CB0F6) : const Color(0xFFF3F4F6),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                        bottomLeft: Radius.circular(20),
                        bottomRight: Radius.circular(4),
                      ),
                    ),
                    child: Text(
                      msg['text']!,
                      style: TextStyle(
                        fontSize: 16,
                        color: isSelected ? Colors.white : const Color(0xFF374151),
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
