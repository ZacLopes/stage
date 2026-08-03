import 'package:flutter/material.dart';
import '../../../core/theme/theme.dart';
import '../../../core/constants/stage_legal_links.dart';
import '../../../core/utils/open_legal_link.dart';

class AIConsentModal extends StatefulWidget {
  final VoidCallback onAccept;
  final VoidCallback onCancel;

  /// Fecha SEM registrar decisão. Passe só quando a tela for aberta pra
  /// consulta (Configurações). Nulo nos gates, onde responder é obrigatório.
  final VoidCallback? onDismiss;

  const AIConsentModal({
    super.key,
    required this.onAccept,
    required this.onCancel,
    this.onDismiss,
  });

  @override
  State<AIConsentModal> createState() => _AIConsentModalState();
}

class _AIConsentModalState extends State<AIConsentModal> {
  bool _isCheckboxMarked = false;

  // As três URLs viviam hardcoded AQUI, e este arquivo é a origem que o
  // `StageLegalLinks` foi criado pra centralizar — a de privacidade
  // continuava duplicada, e quebrada (`/privacy` é 404). Também abriam sem
  // `LaunchMode.externalApplication`, então um documento pra ler com calma
  // podia ficar preso num webview. Achado P2-15.
  Future<void> _launchOpenAIPrivacy() =>
      openLegalLink(StageLegalLinks.openAiPrivacyUrl);

  Future<void> _launchAppPrivacy() => openLegalLink(StageLegalLinks.privacyUrl);

  Future<void> _launchSupport() => openLegalLink(StageLegalLinks.supportUrl);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Saída neutra, só quando a tela é aberta pra CONSULTA (o call
              // site de Configurações). Sem isto, quem entrava só pra ler o
              // que é enviado à OpenAI era obrigado a emitir uma declaração de
              // vontade — aceitar ou recusar — pra conseguir sair: não havia
              // botão de voltar nem swipe-back (o dialog usa
              // barrierDismissible:false). Revisão UX 28/07, achado P2-16.
              //
              // Nos call sites de GATE (antes de gerar com IA) o parâmetro fica
              // nulo e a decisão continua obrigatória, como deve ser.
              if (widget.onDismiss != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.textSecondary),
                    tooltip: 'Fechar',
                    onPressed: widget.onDismiss,
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                'Uso de Inteligência Artificial',
                style: TextStyle(fontFamily: 'Outfit', 
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Para gerar seu currículo personalizado e relatórios com IA, precisamos enviar alguns dos seus dados para processamento.',
                        style: TextStyle(fontFamily: 'Inter', 
                          fontSize: 16,
                          color: AppColors.textSecondary,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // --- THIRD PARTY SECTION ---
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.business, size: 20, color: AppColors.primary),
                                const SizedBox(width: 8),
                                Text(
                                  'Terceiro que receberá seus dados:',
                                  style: TextStyle(fontFamily: 'Inter', 
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'OpenAI, Inc.',
                              style: TextStyle(fontFamily: 'Inter', 
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Os dados são enviados de forma segura (HTTPS) via API para processamento de linguagem natural. A OpenAI não armazena permanentemente seus dados pessoais.',
                              style: TextStyle(fontFamily: 'Inter', 
                                fontSize: 13,
                                color: AppColors.textTertiary,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      // --- DATA LIST ---
                      Text(
                        'Dados que serão enviados:',
                        style: TextStyle(fontFamily: 'Inter', 
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildBulletPoint('Nome completo'),
                      _buildBulletPoint('Experiência profissional'),
                      _buildBulletPoint('Formação acadêmica'),
                      _buildBulletPoint('Habilidades e idiomas'),
                      _buildBulletPoint('Respostas fornecidas nas trilhas do app'),
                      _buildBulletPoint('Outras informações inseridas por você'),
                      const SizedBox(height: 20),
                      // --- PURPOSE ---
                      Text(
                        'Finalidade:',
                        style: TextStyle(fontFamily: 'Inter', 
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Esses dados serão utilizados exclusivamente para gerar o conteúdo do seu currículo e relatórios de análise de perfil. Nenhum dado será compartilhado com terceiros além da OpenAI, Inc.',
                        style: TextStyle(fontFamily: 'Inter', 
                          fontSize: 14,
                          color: AppColors.textSecondary,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 24),
                      // --- LINKS ---
                      GestureDetector(
                        onTap: _launchAppPrivacy,
                        child: Text(
                          'Política de Privacidade do App',
                          style: TextStyle(fontFamily: 'Inter', 
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: _launchOpenAIPrivacy,
                        child: Text(
                          'Política de Privacidade da OpenAI',
                          style: TextStyle(fontFamily: 'Inter', 
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: _launchSupport,
                        child: Text(
                          'Suporte do App',
                          style: TextStyle(fontFamily: 'Inter', 
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Checkbox(
                    value: _isCheckboxMarked,
                    onChanged: (value) {
                      setState(() {
                        _isCheckboxMarked = value ?? false;
                      });
                    },
                    activeColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _isCheckboxMarked = !_isCheckboxMarked;
                        });
                      },
                      child: Text(
                        'Eu autorizo o envio dos meus dados pessoais para a OpenAI, Inc. para processamento conforme descrito acima.',
                        style: TextStyle(fontFamily: 'Inter', 
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.onCancel,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: AppColors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Recusar',
                        style: TextStyle(fontFamily: 'Inter', 
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isCheckboxMarked ? widget.onAccept : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.border,
                        disabledForegroundColor: AppColors.textDisabled,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Aceitar e continuar',
                        style: TextStyle(fontFamily: 'Inter', 
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontFamily: 'Inter', 
                fontSize: 15,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

