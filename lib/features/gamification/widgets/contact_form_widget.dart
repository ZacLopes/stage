import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

class ContactFormWidget extends StatefulWidget {
  final Function(String) onSelect;
  final String? initialValue;

  const ContactFormWidget({
    super.key,
    required this.onSelect,
    this.initialValue,
  });

  @override
  State<ContactFormWidget> createState() => _ContactFormWidgetState();
}

class _ContactFormWidgetState extends State<ContactFormWidget> {
  final _linkedinController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final Map<String, String> _portfolio = {}; // platform -> url

  static const _platforms = [
    'GitHub', 'Behance', 'Dribbble', 'Portfólio Pessoal',
    'Instagram Profissional', 'Outro', 'Não tenho',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      try {
        final data = jsonDecode(widget.initialValue!);
        _linkedinController.text = data['linkedin'] ?? '';
        _emailController.text = data['email'] ?? '';
        _phoneController.text = data['phone'] ?? '';
        if (data['portfolio'] is List) {
          for (final p in (data['portfolio'] as List)) {
            _portfolio[p['platform'] as String] = p['url'] as String? ?? '';
          }
        }
      } catch (_) {}
    }
    _linkedinController.addListener(_emitIfValid);
    _emailController.addListener(_emitIfValid);
    _phoneController.addListener(_emitIfValid);
    WidgetsBinding.instance.addPostFrameCallback((_) => _emitIfValid());
  }

  @override
  void dispose() {
    _linkedinController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _emailController.text.trim().isNotEmpty &&
      _phoneController.text.trim().length >= 10;

  void _emitIfValid() {
    if (!_isValid) return;
    final portfolioList = _portfolio.entries
        .where((e) => e.key != 'Não tenho')
        .map((e) => {'platform': e.key, 'url': e.value})
        .toList();
    widget.onSelect(jsonEncode({
      'linkedin': _linkedinController.text.trim(),
      'portfolio': portfolioList,
      'email': _emailController.text.trim(),
      'phone': _phoneController.text.trim(),
    }));
  }

  void _handlePlatformTap(String platform) {
    if (platform == 'Não tenho') {
      setState(() {
        _portfolio.clear();
        _portfolio['Não tenho'] = 'true';
      });
      _emitIfValid();
      return;
    }
    if (_portfolio.containsKey('Não tenho')) {
      setState(() => _portfolio.remove('Não tenho'));
    }
    _showLinkDialog(platform);
  }

  void _showLinkDialog(String platform) {
    String url = _portfolio[platform] ?? '';
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, anim, _) => Padding(
        padding: MediaQuery.of(ctx).viewInsets,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: ScaleTransition(
              scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
              child: Container(
                width: MediaQuery.of(ctx).size.width * 0.85,
                padding: const EdgeInsets.all(24),
                margin: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 10))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_iconFor(platform), size: 32, color: const Color(0xFF1CB0F6)),
                    const SizedBox(height: 12),
                    Text('Link do $platform',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF374151))),
                    const SizedBox(height: 20),
                    TextField(
                      autofocus: true,
                      controller: TextEditingController(text: url),
                      decoration: InputDecoration(
                        hintText: 'https://...',
                        filled: true,
                        fillColor: const Color(0xFFF3F4F6),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      onChanged: (v) => url = v,
                    ),
                    const SizedBox(height: 20),
                    Row(children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancelar', style: TextStyle(color: Color(0xFF9CA3AF))),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF58CC02), foregroundColor: Colors.white,
                              elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          onPressed: () {
                            setState(() {
                              if (url.trim().isNotEmpty) {
                                _portfolio[platform] = url.trim();
                              } else {
                                _portfolio.remove(platform);
                              }
                            });
                            _emitIfValid();
                            Navigator.pop(ctx);
                          },
                          child: const Text('SALVAR', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // LinkedIn
        _sectionLabel('LINKEDIN (OPCIONAL)'),
        const SizedBox(height: 8),
        _textField(
          controller: _linkedinController,
          hint: 'linkedin.com/in/seuperfil',
          icon: Icons.link,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 24),

        // Portfolio
        _sectionLabel('PORTFÓLIO / PROJETOS (OPCIONAL)'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _platforms.map((p) {
            final isSelected = _portfolio.containsKey(p);
            final isNone = p == 'Não tenho';
            return GestureDetector(
              onTap: () => _handlePlatformTap(p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isNone ? const Color(0xFFFEF2F2) : const Color(0xFFDDF4FF))
                      : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? (isNone ? const Color(0xFFFF4B4B) : const Color(0xFF1CB0F6))
                        : const Color(0xFFE5E7EB),
                    width: 2,
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_iconFor(p),
                      size: 16,
                      color: isSelected
                          ? (isNone ? const Color(0xFFFF4B4B) : const Color(0xFF1CB0F6))
                          : const Color(0xFF6B7280)),
                  const SizedBox(width: 6),
                  Text(p,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? (isNone ? const Color(0xFFFF4B4B) : const Color(0xFF1CB0F6))
                            : const Color(0xFF374151),
                      )),
                  if (isSelected && !isNone)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.check_circle, size: 14, color: Color(0xFF58CC02)),
                    ),
                ]),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),

        // Email
        _sectionLabel('E-MAIL PROFISSIONAL *'),
        const SizedBox(height: 8),
        _textField(
          controller: _emailController,
          hint: 'exemplo@email.com',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 24),

        // Phone
        _sectionLabel('WHATSAPP PARA CONTATO *'),
        const SizedBox(height: 8),
        _textField(
          controller: _phoneController,
          hint: '(11) 99999-9999',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          inputFormatters: [_PhoneMaskFormatter()],
        ),
        const SizedBox(height: 8),
        const Text('* campos obrigatórios', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) =>
      TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFFD1D5DB)),
          prefixIcon: Icon(icon, color: const Color(0xFF9CA3AF), size: 20),
          filled: true,
          fillColor: const Color(0xFFF9FAFB),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF58CC02), width: 2)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      );

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
  );

  IconData _iconFor(String platform) {
    switch (platform.toLowerCase()) {
      case 'github': return Icons.code;
      case 'behance': return Icons.brush;
      case 'dribbble': return Icons.sports_basketball;
      case 'instagram profissional': return Icons.camera_alt;
      case 'portfólio pessoal': return Icons.person;
      case 'outro': return Icons.link;
      case 'não tenho': return Icons.block;
      default: return Icons.link;
    }
  }
}

class _PhoneMaskFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue next) {
    final digits = next.text.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length && i < 11; i++) {
      if (i == 0) buffer.write('(');
      if (i == 2) buffer.write(') ');
      if (i == 7) buffer.write('-');
      buffer.write(digits[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
