import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import '../../../core/theme/theme.dart';

class ContactFormWidget extends StatefulWidget {
  final Function(String) onSelect;
  final String? initialValue;

  const ContactFormWidget({
    super.key,
    required this.onSelect,
    this.initialValue,
  });

  @override
  State<ContactFormWidget> createState() => ContactFormWidgetState();
}

class ContactFormWidgetState extends State<ContactFormWidget> {
  final _linkedinController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final Map<String, String> _portfolio = {}; // platform -> url
  Timer? _debounce;

  static const _platforms = [
    'GitHub', 'Behance', 'Dribbble', 'Portfólio Pessoal',
    'Instagram Profissional', 'Outro', 'Não tenho',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      final data = _parseInitial(widget.initialValue!);
      if (data != null) {
        _linkedinController.text = data['linkedin']?.toString() ?? '';
        _emailController.text = data['email']?.toString() ?? '';
        _phoneController.text = data['phone']?.toString() ?? '';
        _addressController.text = data['address']?.toString() ?? '';
        if (data['portfolio'] is List) {
          for (final p in (data['portfolio'] as List)) {
            _portfolio[p['platform'] as String] = p['url'] as String? ?? '';
          }
        }
      }
    }
    _linkedinController.addListener(_scheduleEmit);
    _emailController.addListener(_onEmailOrPhoneChanged);
    _phoneController.addListener(_onEmailOrPhoneChanged);
    _addressController.addListener(_scheduleEmit);
    WidgetsBinding.instance.addPostFrameCallback((_) => _emitIfValid());
  }

  /// Triggered on every keystroke in email/phone — refreshes the inline
  /// validation state (red/green icon below the field) AND schedules the
  /// debounced emit.
  void _onEmailOrPhoneChanged() {
    if (mounted) setState(() {});
    _scheduleEmit();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _linkedinController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _scheduleEmit() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _emitIfValid);
  }

  /// Parses initialValue defensively. Handles both clean JSON and legacy
  /// concatenated JSONs ({...},{...}) by picking the LAST valid object.
  Map<String, dynamic>? _parseInitial(String raw) {
    try {
      final v = jsonDecode(raw);
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    final matches = RegExp(r'\{[^{}]*(?:\[[^\[\]]*\][^{}]*)*\}').allMatches(raw).toList();
    for (final m in matches.reversed) {
      try {
        final v = jsonDecode(m.group(0)!);
        if (v is Map && v.containsKey('phone')) {
          return Map<String, dynamic>.from(v);
        }
      } catch (_) {}
    }
    return null;
  }

  /// Phone is considered "complete enough" only when at least the full mobile
  /// `(XX) XXXXX-XXXX` (14 chars) is typed. Landline `(XX) XXXX-XXXX` (13)
  /// also accepted. Anything shorter is treated as in-progress and NOT
  /// emitted — prevents truncated-phone bugs in the saved JSON.
  bool _phoneLooksComplete(String s) {
    final digits = s.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 10;
  }

  /// Inline validity getters — used by the inline error indicators below
  /// each field AND by `_isValid` (gates emission/Save).
  bool get _emailIsEmpty => _emailController.text.trim().isEmpty;
  bool get _emailIsValid {
    final s = _emailController.text.trim();
    if (s.isEmpty) return false;
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s);
  }

  bool get _phoneIsEmpty => _phoneController.text.trim().isEmpty;
  int get _phoneDigitCount =>
      _phoneController.text.replaceAll(RegExp(r'\D'), '').length;

  bool get _isValid => _emailIsValid && _phoneLooksComplete(_phoneController.text);

  void _emitIfValid() {
    if (!_isValid) return;
    _emitNow();
  }

  /// Emits the current state IMMEDIATELY, regardless of debounce. Used by
  /// the Save button in the resume edit dialog to capture the user's last
  /// keystroke without waiting for the 500ms debounce window. Returns true
  /// when emission succeeded (i.e., form was valid), false otherwise — the
  /// caller can use this to show an error snackbar instead of popping.
  bool flushEmit() {
    _debounce?.cancel();
    if (!_isValid) return false;
    _emitNow();
    return true;
  }

  /// Public read-only check used by the parent dialog to disable/enable the
  /// Save button reactively (currently only used to surface errors on tap).
  bool get isValid => _isValid;

  void _emitNow() {
    final portfolioList = _portfolio.entries
        .where((e) => e.key != 'Não tenho')
        .map((e) => {'platform': e.key, 'url': e.value})
        .toList();
    widget.onSelect(jsonEncode({
      'linkedin': _linkedinController.text.trim(),
      'portfolio': portfolioList,
      'email': _emailController.text.trim(),
      'phone': _phoneController.text.trim(),
      'address': _addressController.text.trim(),
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
                    Icon(_iconFor(platform), size: 32, color: AppColors.secondary),
                    const SizedBox(height: 12),
                    Text('Link do $platform',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                    const SizedBox(height: 20),
                    TextField(
                      autofocus: true,
                      controller: TextEditingController(text: url),
                      decoration: InputDecoration(
                        hintText: 'https://...',
                        filled: true,
                        fillColor: AppColors.background,
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
                          child: const Text('Cancelar', style: TextStyle(color: AppColors.textDisabled)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary, foregroundColor: Colors.white,
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
                      ? (isNone ? AppColors.errorSoft : AppColors.brandSoft)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? (isNone ? AppColors.error : AppColors.secondary)
                        : AppColors.border,
                    width: 2,
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_iconFor(p),
                      size: 16,
                      color: isSelected
                          ? (isNone ? AppColors.error : AppColors.secondary)
                          : AppColors.textTertiary),
                  const SizedBox(width: 6),
                  Text(p,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? (isNone ? AppColors.error : AppColors.secondary)
                            : AppColors.textSecondary,
                      )),
                  if (isSelected && !isNone)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.check_circle, size: 14, color: AppColors.success),
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
        if (!_emailIsEmpty && !_emailIsValid)
          _validationMessage('Formato de e-mail inválido', isError: true)
        else if (_emailIsValid)
          _validationMessage('E-mail válido', isError: false),
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
        if (!_phoneIsEmpty && _phoneDigitCount < 10)
          _validationMessage(
            'Faltam ${10 - _phoneDigitCount} dígito${10 - _phoneDigitCount == 1 ? "" : "s"} (mínimo 10)',
            isError: true,
          )
        else if (_phoneDigitCount >= 10)
          _validationMessage('Telefone válido', isError: false),

        const SizedBox(height: 24),

        // Address (opcional, padrão Harvard internacional)
        _sectionLabel('ENDEREÇO (opcional)'),
        const SizedBox(height: 6),
        const Text(
          'Adicione rua e bairro se quiser o formato internacional. Ex: "Rua Joaquim Floriano, 152 – Itaim Bibi"',
          style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
        ),
        const SizedBox(height: 8),
        _textField(
          controller: _addressController,
          hint: 'Rua, número – Bairro',
          icon: Icons.home_outlined,
          keyboardType: TextInputType.streetAddress,
        ),

        const SizedBox(height: 8),
        const Text('* campos obrigatórios', style: TextStyle(color: AppColors.textDisabled, fontSize: 12)),
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
          hintStyle: const TextStyle(color: AppColors.borderStrong),
          prefixIcon: Icon(icon, color: AppColors.textDisabled, size: 20),
          filled: true,
          fillColor: AppColors.surfaceVariant,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.success, width: 2)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      );

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(color: AppColors.textTertiary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
  );

  /// Inline validation row shown below email/phone fields.
  Widget _validationMessage(String text, {required bool isError}) {
    final color = isError ? AppColors.error : AppColors.success;
    final icon = isError ? Icons.error_outline : Icons.check_circle_outline;
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }

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
