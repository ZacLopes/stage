import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import '../../core/constants/stage_colors.dart';
import '../../services/ai_service.dart';
import '../../services/pdf_generator_service.dart';
import '../../data/models/models.dart';
import '../auth/user_viewmodel.dart';
import '../profile/profile_viewmodel.dart';

class ResumeImprovementChatScreen extends StatefulWidget {
  final String resumeText;
  final List<int>? pdfBytes;
  final ResumeAnalysisResult analysis;
  final VoidCallback onFinish;

  const ResumeImprovementChatScreen({
    super.key,
    required this.resumeText,
    this.pdfBytes,
    required this.analysis,
    required this.onFinish,
  });

  @override
  State<ResumeImprovementChatScreen> createState() => _ResumeImprovementChatScreenState();
}

class _ResumeImprovementChatScreenState extends State<ResumeImprovementChatScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isTyping = false;
  int _currentQuestionIndex = 0;
  
  String? _improvedResume;

  @override
  void initState() {
    super.initState();
    _addBotMessage("Olá! Analisei seu currículo e vi que podemos deixá-lo ainda mais forte. Vamos ajustar alguns detalhes?");
    _askNextQuestion();
  }

  void _addBotMessage(String text) {
    setState(() {
      _messages.add(ChatMessage(text: text, isBot: true));
    });
    _scrollToBottom();
  }

  void _addUserMessage(String text) {
    setState(() {
      _messages.add(ChatMessage(text: text, isBot: false));
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleSend() async {
    if (_controller.text.trim().isEmpty) return;
    
    final text = _controller.text;
    _controller.clear();
    _addUserMessage(text);
    
    _askNextQuestion();
  }

  void _askNextQuestion() async {
    setState(() => _isTyping = true);
    
    try {
      final aiService = AIService();
      final history = _messages.map((m) => {'text': m.text, 'isBot': m.isBot}).toList();
      
      final result = await aiService.refineResumeChat(
        history: history,
        originalResume: widget.resumeText,
        analysis: widget.analysis,
      );

      print('Chat Result Received: $result');

      setState(() => _isTyping = false);

      if (result['isFinished'] == true) {
        _improvedResume = result['improvedResume'];
        print('Improved Resume Set: ${_improvedResume?.length ?? 0} chars');
        _addBotMessage(result['message'] ?? "Tudo pronto! Seu currículo foi otimizado com sucesso.");
        await Future.delayed(const Duration(seconds: 1));
        _showSuccessDialog();
      } else {
        _addBotMessage(result['question'] ?? "Pode me falar mais sobre isso?");
      }
    } catch (e) {
      setState(() => _isTyping = false);
      _addBotMessage("Houve um probleminha na conexão, mas não se preocupe. Vamos continuar?");
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Currículo Otimizado!', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: const Text('As melhorias foram aplicadas. Você pode visualizar o novo arquivo antes de continuar.'),
        actions: [
          TextButton(
            onPressed: () async {
              if (_improvedResume != null) {
                final pdfBytes = await PDFGeneratorService.generateResumePDF(_improvedResume!);
                await Printing.layoutPdf(onLayout: (_) => pdfBytes);
              }
            },
            child: Text('VISUALIZAR PDF', style: GoogleFonts.inter(color: StageColors.brandBlue, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () => _handleFinalAction(),
            style: ElevatedButton.styleFrom(
              backgroundColor: StageColors.brandBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('VAMOS PARA AS VAGAS!'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleFinalAction() async {
    // 1. Save (improved) to library
    if (_improvedResume != null) {
      final pdfBytes = await PDFGeneratorService.generateResumePDF(_improvedResume!);
      await context.read<ProfileViewModel>().saveResume(
        'Currículo Otimizado (${DateTime.now().day}/${DateTime.now().month})',
        pdfBytes,
      );
    } else if (widget.pdfBytes != null) {
      // Fallback to original if something went wrong
      await context.read<ProfileViewModel>().saveResume(
        'Currículo Original (${DateTime.now().day}/${DateTime.now().month})',
        widget.pdfBytes!,
      );
    }

    // 2. Mark as seen and navigate
    widget.onFinish();
    if (mounted) {
       Navigator.of(context).pop(); // Dialog
       Navigator.of(context).pop(); // Chat Screen
       Navigator.of(context).pop(); // Score Screen
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('Otimização com IA', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(20),
              itemCount: _messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length && _isTyping) {
                  return const _TypingIndicator();
                }
                return _messages[index];
              },
            ),
          ),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.of(context).viewPadding.bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  hintText: 'Escreva sua resposta...',
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _handleSend(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          CircleAvatar(
            backgroundColor: StageColors.brandBlue,
            child: IconButton(
              icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              onPressed: _handleSend,
            ),
          ),
        ],
      ),
    );
  }
}

class ChatMessage extends StatelessWidget {
  final String text;
  final bool isBot;

  const ChatMessage({super.key, required this.text, required this.isBot});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: isBot ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          if (isBot) ...[
            const CircleAvatar(
              radius: 16,
              backgroundColor: StageColors.brandBlue,
              child: Icon(Icons.auto_awesome, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isBot ? Colors.white : StageColors.brandBlue,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isBot ? 4 : 20),
                  bottomRight: Radius.circular(isBot ? 20 : 4),
                ),
                boxShadow: [
                  if (isBot) BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Text(
                text,
                style: GoogleFonts.inter(
                  color: isBot ? StageColors.titleText : Colors.white,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
          ),
          if (!isBot) const SizedBox(width: 40), // Spacing for user messages
          if (isBot) const SizedBox(width: 40), // Spacing for bot messages
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 16,
            backgroundColor: StageColors.brandBlue,
            child: Icon(Icons.auto_awesome, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) => Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 4),
                decoration: const BoxDecoration(color: Colors.grey, shape: BoxShape.circle),
              )),
            ),
          ),
        ],
      ),
    );
  }
}
