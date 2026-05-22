// Máscara de telefone brasileiro: `(DD) NNNNN-NNNN` — 11 dígitos.
// Strip de não-dígitos é responsabilidade do consumidor (ex:
// PhoneAuthHelpers.syntheticEmail).

import 'package:flutter/services.dart';

class BrazilPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = format(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  /// Aplica máscara `(DD) NNNNN-NNNN` em qualquer string (extrai dígitos
  /// primeiro, depois limita a 11 e formata). Use ao popular um campo com
  /// valor pré-existente (ex: vindo do banco em dígitos puros).
  static String format(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    final d = digits.length > 11 ? digits.substring(0, 11) : digits;
    if (d.isEmpty) return '';
    final b = StringBuffer('(');
    if (d.length <= 2) {
      b.write(d);
      return b.toString();
    }
    b.write(d.substring(0, 2));
    b.write(') ');
    if (d.length <= 7) {
      b.write(d.substring(2));
      return b.toString();
    }
    b.write(d.substring(2, 7));
    b.write('-');
    b.write(d.substring(7));
    return b.toString();
  }
}
