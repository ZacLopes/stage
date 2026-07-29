import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Códigos de país oferecidos no app, em ordem de uso real.
///
/// Fonte única (revisão UX 28/07, achado P3-42): antes o cadastro pedia o DDI
/// como caixa de texto livre (qualquer número de até 4 dígitos) e o onboarding,
/// duas telas depois, pedia o MESMO dado num seletor com bandeira de 4 opções.
/// Além da incoerência visual, um DDI digitado fora dessas 4 opções chegava no
/// `DropdownButtonFormField` do onboarding como valor sem item correspondente.
///
/// Medido em produção em 28/07: dos 1.225 perfis com DDI preenchido, **1.225
/// são +55**. Nenhum usuário real foi perdido ao trocar o texto livre pelo
/// seletor; os outros três códigos ficam para quem estuda fora.
const kCountryCodes = <(String code, String label)>[
  ('+55', '🇧🇷 +55'),
  ('+1', '🇺🇸 +1'),
  ('+351', '🇵🇹 +351'),
  ('+44', '🇬🇧 +44'),
];

/// Seletor de DDI com bandeira — o MESMO controle no cadastro e no onboarding.
///
/// Aceita um [value] fora de [kCountryCodes] (ex.: conta antiga criada quando o
/// campo era texto livre): nesse caso o código entra na lista como item extra,
/// sem bandeira, em vez de virar um dropdown sem seleção.
class CountryCodeField extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final InputDecoration? decoration;

  const CountryCodeField({
    super.key,
    required this.value,
    required this.onChanged,
    this.decoration,
  });

  @override
  Widget build(BuildContext context) {
    final known = kCountryCodes.any((c) => c.$1 == value);
    final entries = <(String, String)>[
      ...kCountryCodes,
      if (!known) (value, value),
    ];

    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: value,
      decoration: decoration ??
          const InputDecoration(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 18),
          ),
      style: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      items: [
        for (final (code, label) in entries)
          DropdownMenuItem(
            value: code,
            child: Text(label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => onChanged(v ?? value),
    );
  }
}
