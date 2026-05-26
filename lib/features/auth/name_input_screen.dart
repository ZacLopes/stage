import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/analytics/screen_tracking.dart';
import '../../core/constants/stage_colors.dart';
import 'user_viewmodel.dart';

/// Tela bloqueante mostrada quando `UserViewModel.needsName` é true.
/// Sai assim que o user salva um nome válido — daí o `AuthGate` re-roteia
/// pra home ou onboarding normalmente.
class NameInputScreen extends StatefulWidget {
  const NameInputScreen({super.key});

  @override
  State<NameInputScreen> createState() => _NameInputScreenState();
}

class _NameInputScreenState extends State<NameInputScreen>
    with ScreenTrackingMixin {
  @override
  String get screenName => 'onboarding_name';

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Auto-foca o input depois da tela montar
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await context.read<UserViewModel>().updateName(_controller.text);
      // Não navegamos manualmente — o AuthGate (Consumer<UserViewModel>) tem
      // `needsName` na condição e re-roteia sozinho quando vira false.
      // Push manual aqui criaria GlobalKey duplicada com a HomeScreen do
      // AuthGate (TutorialKeys.jobsTab fica em duas árvores ao mesmo tempo).
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Não consegui salvar. Tenta de novo.';
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Tela bloqueante — sem voltar
      child: Scaffold(
        backgroundColor: StageColors.offWhite,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(flex: 2),
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: StageColors.brandGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: StageColors.brandBlue.withValues(alpha: 0.25),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.waving_hand_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Como podemos te chamar?',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Outfit', 
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: StageColors.titleText,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Vamos usar esse nome no seu currículo e em todo o app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Inter', 
                      fontSize: 15,
                      color: StageColors.subtitleGray,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _controller,
                    focusNode: _focusNode,
                    enabled: !_isSaving,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.words,
                    autocorrect: false,
                    style: TextStyle(fontFamily: 'Inter', 
                      fontSize: 17,
                      color: StageColors.darkText,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Seu nome completo',
                      hintStyle: TextStyle(fontFamily: 'Inter', 
                        color: StageColors.hintGray,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 18,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: StageColors.chipBorder,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: StageColors.chipBorder,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: StageColors.brandBlue,
                          width: 1.5,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: StageColors.error),
                      ),
                    ),
                    validator: (v) {
                      final s = v?.trim() ?? '';
                      if (s.isEmpty) return 'Digite seu nome';
                      if (s.length < 2) return 'Nome muito curto';
                      if (s.toLowerCase() == 'user') {
                        return 'Por favor, escolha outro nome';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => _save(),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Inter', 
                        fontSize: 13,
                        color: StageColors.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: StageColors.brandBlue,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          StageColors.brandBlue.withValues(alpha: 0.5),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white),
                            ),
                          )
                        : Text(
                            'Continuar',
                            style: TextStyle(fontFamily: 'Outfit', 
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                  const Spacer(flex: 3),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
