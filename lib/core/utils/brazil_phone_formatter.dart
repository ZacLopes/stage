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

  /// Formata um telefone JÁ ARMAZENADO para exibição em documento.
  ///
  /// Diferente de [format], que serve pra digitação: aqui a entrada pode vir
  /// em qualquer forma — "+5511987650143", "5511987650143", "11987650143" —
  /// porque no CV adaptado ela chega do servidor, sem passar pelo formatter
  /// de input. O PDF saía "Telefone: +55 11987650143" enquanto o app inteiro
  /// mostrava "(11) 98765-0143". Revisão UX 28/07, achado P2-25.
  ///
  /// Fora do padrão BR (internacional, incompleto), devolve a entrada intacta
  /// — melhor um telefone estranho que um telefone ERRADO no currículo.
  static String formatForDocument(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';

    // DDI explícito de OUTRO país sai intacto. Sem isto, "+1 415 555 2671"
    // (EUA) tem 11 dígitos, passa pelo teste de tamanho e vira
    // "(14) 15555-2671" — um telefone americano formatado como brasileiro no
    // currículo. É o mesmo erro que a função existe pra evitar, na direção
    // oposta.
    if (trimmed.startsWith('+') && !trimmed.startsWith('+55')) return trimmed;

    var digits = trimmed.replaceAll(RegExp(r'\D'), '');
    // Tira o DDI brasileiro: 55 + 10 (fixo) ou 11 (celular) dígitos.
    if (digits.length == 12 || digits.length == 13) {
      if (digits.startsWith('55')) digits = digits.substring(2);
    }
    if (digits.length != 10 && digits.length != 11) return trimmed;

    // Agrupamento PRÓPRIO, não delegado a [format].
    //
    // [format] é máscara de DIGITAÇÃO: ela agrupa sempre 5+4 porque o campo
    // pede celular e o número vai sendo montado. Aqui o número já está
    // completo, e fixo tem 8 dígitos depois do DDD — delegar produzia
    // "(11) 32654-321" para 1132654321, que é um telefone ERRADO no currículo
    // que a pessoa manda pro recrutador.
    final ddd = digits.substring(0, 2);
    final rest = digits.substring(2);
    final corte = rest.length == 9 ? 5 : 4; // celular 9 dígitos, fixo 8
    return '($ddd) ${rest.substring(0, corte)}-${rest.substring(corte)}';
  }
}
