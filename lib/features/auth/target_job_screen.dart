import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/stage_colors.dart';
import '../home/home_screen.dart';
import 'user_viewmodel.dart';

class TargetJobScreen extends StatefulWidget {
  const TargetJobScreen({super.key});

  @override
  State<TargetJobScreen> createState() => _TargetJobScreenState();
}

class _TargetJobScreenState extends State<TargetJobScreen> {
  final _titleController = TextEditingController();
  final _urlController = TextEditingController();
  String? _titleError;
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _handleContinue() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'Informe pelo menos o cargo ou área que você busca');
      return;
    }
    setState(() {
      _titleError = null;
      _isSaving = true;
    });

    try {
      final vm = context.read<UserViewModel>();
      await vm.createCampaign(
        jobTitle: title,
        sourceUrl: _urlController.text.trim().isEmpty ? null : _urlController.text.trim(),
      );
      if (!mounted) return;
      _navigateHome();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao salvar. Tente novamente.'),
            backgroundColor: StageColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _handleSkip() async {
    setState(() => _isSaving = true);
    try {
      final vm = context.read<UserViewModel>();
      await vm.createCampaign(isSkipped: true);
      if (!mounted) return;
      _navigateHome();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao salvar. Tente novamente.'),
            backgroundColor: StageColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _navigateHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    IconData? icon,
    String? errorText,
    String? helperText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: errorText,
      helperText: helperText,
      helperMaxLines: 2,
      prefixIcon: icon != null
          ? Icon(icon, color: StageColors.hintGray, size: 20)
          : null,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: StageColors.brandCyan, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: StageColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: StageColors.error, width: 2),
      ),
      labelStyle: GoogleFonts.inter(color: StageColors.subtitleGray),
      hintStyle: GoogleFonts.inter(color: StageColors.hintGray),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: StageColors.offWhite,
        body: SafeArea(
          child: Column(
            children: [
              LinearProgressIndicator(
                value: 1.0,
                backgroundColor: Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation(StageColors.brandCyan),
                minHeight: 6,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: StageColors.ctaGreen.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.work_outline_rounded,
                          color: StageColors.ctaGreen,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Para qual vaga você\nestá se candidatando?',
                        style: GoogleFonts.outfit(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: StageColors.titleText,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Isso ajuda a IA a criar bullets certeiros para o seu perfil.',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          color: StageColors.subtitleGray,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 36),
                      TextField(
                        controller: _titleController,
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: (_) {
                          if (_titleError != null) setState(() => _titleError = null);
                        },
                        decoration: _inputDecoration(
                          label: 'Cargo ou área-alvo',
                          hint: 'Ex: estágio em produto, analista financeiro júnior em banco...',
                          icon: Icons.label_outline_rounded,
                          errorText: _titleError,
                        ),
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          color: StageColors.titleText,
                        ),
                        maxLines: 2,
                        minLines: 1,
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _urlController,
                        keyboardType: TextInputType.url,
                        decoration: _inputDecoration(
                          label: 'Link da vaga (Opcional)',
                          hint: 'https://...',
                          icon: Icons.link_rounded,
                          helperText:
                              'Cole a URL da vaga para a IA ler os requisitos completos.',
                        ),
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          color: StageColors.titleText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _handleContinue,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: StageColors.ctaGreen,
                          disabledBackgroundColor: Colors.grey.shade300,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Text(
                                'Continuar →',
                                style: GoogleFonts.inter(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _isSaving ? null : _handleSkip,
                      child: Text(
                        'Ainda não sei — quero um CV genérico',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: StageColors.subtitleGray,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
