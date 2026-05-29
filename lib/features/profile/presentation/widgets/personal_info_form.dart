// PersonalInfoForm — formulário de informações pessoais.
//
// Usado em 2 contextos:
//   - Onboarding (ReviewPersonalInfoScreen): validação dura, Continue habilitado
//     só se first_name+last_name+email preenchidos
//   - Aba Perfil (ProfileEditorScreen): autosave via ProfileEditorViewModel
//     com debounce 800ms

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/utils/brazil_phone_formatter.dart';
import '../../domain/entities/entities.dart';
import '../../../../core/theme/theme.dart';

class PersonalInfoForm extends StatefulWidget {
  final PersonalInfo? initial;
  final void Function(PersonalInfo draft) onChanged;
  final bool requireCriticalFields; // true no onboarding

  const PersonalInfoForm({
    super.key,
    required this.initial,
    required this.onChanged,
    this.requireCriticalFields = false,
  });

  @override
  State<PersonalInfoForm> createState() => _PersonalInfoFormState();
}

class _PersonalInfoFormState extends State<PersonalInfoForm> {
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _email;
  late final TextEditingController _phoneNumber;
  late final TextEditingController _dateOfBirth;
  late final TextEditingController _summary;
  // DDI editável — guarda só os dígitos; o '+' é renderizado fixo via
  // prefixText. Default '55' (Brasil), mas user pode digitar qualquer código.
  late final TextEditingController _phoneCountryCodeCtrl;
  DateTime? _parsedDob;
  String? _dobError;

  /// Código completo (com '+') usado pra salvar e pra detectar BR (e ativar
  /// a máscara de telefone brasileira).
  String get _phoneCountryCode => '+${_phoneCountryCodeCtrl.text.trim()}';

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _firstName = TextEditingController(text: i?.firstName ?? '');
    _lastName = TextEditingController(text: i?.lastName ?? '');
    _email = TextEditingController(text: i?.email ?? '');
    final initialPhone = i?.phoneNumber ?? '';
    final initialCountry = i?.phoneCountryCode ?? '+55';
    _phoneNumber = TextEditingController(
      text: initialCountry == '+55' && initialPhone.isNotEmpty
          ? BrazilPhoneFormatter.format(initialPhone)
          : initialPhone,
    );
    _summary = TextEditingController(text: i?.summary ?? '');
    _phoneCountryCodeCtrl = TextEditingController(
      text: initialCountry.replaceAll('+', ''),
    );

    _parsedDob = i?.dateOfBirth;
    _dateOfBirth = TextEditingController(
      text: _parsedDob != null ? _formatDob(_parsedDob!) : '',
    );

    for (final c in [_firstName, _lastName, _email, _phoneNumber, _summary]) {
      c.addListener(_emitChange);
    }
  }

  static String _formatDob(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }

  void _onDobChanged(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 8) {
      setState(() {
        _parsedDob = null;
        _dobError = digits.isEmpty ? null : null; // só erra quando tenta salvar incompleta
      });
      _emitChange();
      return;
    }
    final day = int.tryParse(digits.substring(0, 2));
    final month = int.tryParse(digits.substring(2, 4));
    final year = int.tryParse(digits.substring(4, 8));
    if (day == null || month == null || year == null || year < 1900) {
      setState(() {
        _parsedDob = null;
        _dobError = 'Data inválida';
      });
      _emitChange();
      return;
    }
    final candidate = DateTime(year, month, day);
    if (candidate.day != day || candidate.month != month || candidate.year != year) {
      setState(() {
        _parsedDob = null;
        _dobError = 'Data inválida';
      });
      _emitChange();
      return;
    }
    final now = DateTime.now();
    if (candidate.isAfter(now)) {
      setState(() {
        _parsedDob = null;
        _dobError = 'Data no futuro';
      });
      _emitChange();
      return;
    }
    setState(() {
      _parsedDob = candidate;
      _dobError = null;
    });
    _emitChange();
  }

  int? get _ageInYears {
    final dob = _parsedDob;
    if (dob == null) return null;
    final now = DateTime.now();
    var age = now.year - dob.year;
    final hadBirthdayThisYear = (now.month > dob.month) ||
        (now.month == dob.month && now.day >= dob.day);
    if (!hadBirthdayThisYear) age -= 1;
    return age < 0 ? null : age;
  }

  void _emitChange() {
    final base = widget.initial;
    if (base == null) return;
    widget.onChanged(base.copyWith(
      firstName: _firstName.text.trim().isEmpty ? null : _firstName.text.trim(),
      lastName: _lastName.text.trim().isEmpty ? null : _lastName.text.trim(),
      email: _email.text.trim().isEmpty ? null : _email.text.trim().toLowerCase(),
      phoneCountryCode: _phoneCountryCode,
      phoneNumber: _phoneNumber.text.trim().isEmpty ? null : _phoneNumber.text.trim(),
      dateOfBirth: _parsedDob,
      ageRange: ageRangeFromDate(_parsedDob),
      summary: _summary.text.trim().isEmpty ? null : _summary.text.trim(),
    ));
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phoneNumber.dispose();
    _dateOfBirth.dispose();
    _summary.dispose();
    _phoneCountryCodeCtrl.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, {bool critical = false, bool empty = false, String? helper, String? errorText}) {
    final isMissing = widget.requireCriticalFields && critical && empty;
    return InputDecoration(
      labelText: label,
      helperText: helper,
      errorText: errorText,
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(
          color: isMissing ? AppColors.warning : AppColors.border,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(
          color: isMissing ? AppColors.warning : AppColors.border,
          width: isMissing ? 1.5 : 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ageHelper = _ageInYears != null ? '$_ageInYears anos' : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _firstName,
          decoration: _decoration('Nome', critical: true, empty: _firstName.text.trim().isEmpty),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _lastName,
          decoration: _decoration('Sobrenome', critical: true, empty: _lastName.text.trim().isEmpty),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _email,
          decoration: _decoration('Email', critical: true, empty: _email.text.trim().isEmpty),
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            SizedBox(
              width: 104,
              child: TextField(
                controller: _phoneCountryCodeCtrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: _decoration('DDI').copyWith(
                  prefixText: '+',
                ),
                onChanged: (_) {
                  // Limpa o número quando o DDI muda — a máscara BR só vale
                  // pra +55 e formatos de outros países podem conflitar.
                  setState(() => _phoneNumber.clear());
                  _emitChange();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _phoneNumber,
                decoration: _decoration('Telefone'),
                keyboardType: TextInputType.phone,
                inputFormatters: _phoneCountryCode == '+55'
                    ? [BrazilPhoneFormatter()]
                    : [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(15),
                      ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _dateOfBirth,
          decoration: _decoration(
            'Data de nascimento',
            helper: ageHelper,
            errorText: _dobError,
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [_DobFormatter()],
          onChanged: _onDobChanged,
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _summary,
          decoration: _decoration('Resumo profissional'),
          minLines: 5,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
        ),
      ],
    );
  }
}

/// Formata input como DD/MM/AAAA, limitando a 8 dígitos.
class _DobFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limited = digits.length > 8 ? digits.substring(0, 8) : digits;
    final buf = StringBuffer();
    for (int i = 0; i < limited.length; i++) {
      if (i == 2 || i == 4) buf.write('/');
      buf.write(limited[i]);
    }
    final formatted = buf.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
