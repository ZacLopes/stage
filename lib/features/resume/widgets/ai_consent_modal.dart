import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AIConsentModal extends StatefulWidget {
  final VoidCallback onAccept;
  final VoidCallback onCancel;

  const AIConsentModal({
    super.key,
    required this.onAccept,
    required this.onCancel,
  });

  @override
  State<AIConsentModal> createState() => _AIConsentModalState();
}

class _AIConsentModalState extends State<AIConsentModal> {
  bool _isCheckboxMarked = false;

  Future<void> _launchOpenAIPrivacy() async {
    final url = Uri.parse('https://openai.com/policies/privacy-policy');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> _launchAppPrivacy() async {
    final url = Uri.parse('https://stageapp.lovable.app/privacy');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> _launchSupport() async {
    final url = Uri.parse('https://stageapp.lovable.app');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

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
              const SizedBox(height: 20),
              Text(
                'Uso de Inteligência Artificial',
                style: TextStyle(fontFamily: 'Outfit', 
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF111827),
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
                          color: const Color(0xFF4B5563),
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // --- THIRD PARTY SECTION ---
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.business, size: 20, color: Color(0xFF4F46E5)),
                                const SizedBox(width: 8),
                                Text(
                                  'Terceiro que receberá seus dados:',
                                  style: TextStyle(fontFamily: 'Inter', 
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF1F2937),
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
                                color: const Color(0xFF111827),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Os dados são enviados de forma segura (HTTPS) via API para processamento de linguagem natural. A OpenAI não armazena permanentemente seus dados pessoais.',
                              style: TextStyle(fontFamily: 'Inter', 
                                fontSize: 13,
                                color: const Color(0xFF6B7280),
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
                          color: const Color(0xFF1F2937),
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
                          color: const Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Esses dados serão utilizados exclusivamente para gerar o conteúdo do seu currículo e relatórios de análise de perfil. Nenhum dado será compartilhado com terceiros além da OpenAI, Inc.',
                        style: TextStyle(fontFamily: 'Inter', 
                          fontSize: 14,
                          color: const Color(0xFF4B5563),
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
                            color: const Color(0xFF4F46E5),
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
                            color: const Color(0xFF4F46E5),
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
                            color: const Color(0xFF4F46E5),
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
                    activeColor: const Color(0xFF4F46E5),
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
                          color: const Color(0xFF374151),
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
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Recusar',
                        style: TextStyle(fontFamily: 'Inter', 
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF4B5563),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isCheckboxMarked ? widget.onAccept : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFE5E7EB),
                        disabledForegroundColor: const Color(0xFF9CA3AF),
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
          const Text('• ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5))),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontFamily: 'Inter', 
                fontSize: 15,
                color: const Color(0xFF4B5563),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

