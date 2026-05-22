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

class PersonalInfoForm extends StatefulWidget {
  final PersonalInfo? initial;
  final void Function(PersonalInfo draft) onChanged;
  final bool requireCriticalFields; // true no onboarding

  /// Mostra o campo "Cargo / posição atual" (headline). Default true.
  /// Desligado no onboarding pq a maioria dos usuários é estudante/estagiário
  /// e o campo gera ruído. A aba Perfil mantém pra quem quer preencher.
  final bool showHeadline;

  const PersonalInfoForm({
    super.key,
    required this.initial,
    required this.onChanged,
    this.requireCriticalFields = false,
    this.showHeadline = true,
  });

  @override
  State<PersonalInfoForm> createState() => _PersonalInfoFormState();
}

class _PersonalInfoFormState extends State<PersonalInfoForm> {
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _email;
  late final TextEditingController _phoneNumber;
  late final TextEditingController _headline;
  late final TextEditingController _summary;
  String _phoneCountryCode = '+55';

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
    _headline = TextEditingController(text: i?.headline ?? '');
    _summary = TextEditingController(text: i?.summary ?? '');
    _phoneCountryCode = i?.phoneCountryCode ?? '+55';

    for (final c in [_firstName, _lastName, _email, _phoneNumber, _headline, _summary]) {
      c.addListener(_emitChange);
    }
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
      headline: _headline.text.trim().isEmpty ? null : _headline.text.trim(),
      summary: _summary.text.trim().isEmpty ? null : _summary.text.trim(),
    ));
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phoneNumber.dispose();
    _headline.dispose();
    _summary.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, {bool critical = false, bool empty = false}) {
    final isMissing = widget.requireCriticalFields && critical && empty;
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: isMissing ? Colors.amber : const Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isMissing ? Colors.amber.shade700 : const Color(0xFFE5E7EB),
          width: isMissing ? 1.5 : 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF00C27A), width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              width: 124,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _phoneCountryCode,
                decoration: _decoration('País'),
                items: const [
                  DropdownMenuItem(value: '+55', child: Text('🇧🇷 +55', overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(value: '+1', child: Text('🇺🇸 +1', overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(value: '+351', child: Text('🇵🇹 +351', overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(value: '+44', child: Text('🇬🇧 +44', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _phoneCountryCode = v;
                    _phoneNumber.clear();
                  });
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
        if (widget.showHeadline) ...[
          const SizedBox(height: 14),
          TextField(
            controller: _headline,
            decoration: _decoration('Cargo / posição atual'),
            maxLines: 1,
          ),
        ],
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
