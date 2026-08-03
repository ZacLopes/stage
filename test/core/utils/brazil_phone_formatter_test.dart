import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/core/utils/brazil_phone_formatter.dart';

/// Revisão UX 28/07, achado P2-25 — e o bug que a PRÓPRIA correção introduziu.
///
/// `formatForDocument` nasceu delegando a `format`, que é máscara de DIGITAÇÃO
/// e agrupa sempre 5+4 porque o campo pede celular. Com um fixo de 10 dígitos
/// isso produzia "(11) 32654-321": um telefone errado no currículo que a pessoa
/// manda ao recrutador. O arquivo não tinha teste nenhum até 30/07.
void main() {
  group('formatForDocument — número completo, para documento', () {
    test('celular de 11 dígitos agrupa 5+4', () {
      expect(BrazilPhoneFormatter.formatForDocument('11987650143'), '(11) 98765-0143');
    });

    test('FIXO de 10 dígitos agrupa 4+4 — era o bug', () {
      expect(BrazilPhoneFormatter.formatForDocument('1132654321'), '(11) 3265-4321');
      expect(BrazilPhoneFormatter.formatForDocument('4133334444'), '(41) 3333-4444');
    });

    test('tira o DDI brasileiro em qualquer forma de entrada', () {
      expect(BrazilPhoneFormatter.formatForDocument('+5511987650143'), '(11) 98765-0143');
      expect(BrazilPhoneFormatter.formatForDocument('5511987650143'), '(11) 98765-0143');
      expect(BrazilPhoneFormatter.formatForDocument('+55 11 98765-0143'), '(11) 98765-0143');
      expect(BrazilPhoneFormatter.formatForDocument('551132654321'), '(11) 3265-4321');
    });

    test('fora do padrão BR devolve intacto — melhor estranho que ERRADO', () {
      // Um número internacional formatado como se fosse brasileiro seria uma
      // mentira no documento. Devolver como veio é o comportamento honesto.
      expect(BrazilPhoneFormatter.formatForDocument('+1 415 555 2671'), '+1 415 555 2671');
      expect(BrazilPhoneFormatter.formatForDocument('123'), '123');
      expect(BrazilPhoneFormatter.formatForDocument(''), '');
      expect(BrazilPhoneFormatter.formatForDocument('   '), '');
    });

    test('é idempotente (formatar o já formatado não muda)', () {
      for (final n in ['11987650143', '1132654321', '+5511987650143']) {
        final umaVez = BrazilPhoneFormatter.formatForDocument(n);
        expect(BrazilPhoneFormatter.formatForDocument(umaVez), umaVez);
      }
    });
  });

  group('format — máscara de digitação, agrupamento progressivo', () {
    test('monta a máscara conforme a pessoa digita', () {
      expect(BrazilPhoneFormatter.format('1'), '(1');
      expect(BrazilPhoneFormatter.format('11'), '(11');
      expect(BrazilPhoneFormatter.format('1198'), '(11) 98');
      expect(BrazilPhoneFormatter.format('11987650143'), '(11) 98765-0143');
    });

    test('descarta o que passa de 11 dígitos', () {
      expect(BrazilPhoneFormatter.format('119876501439999'), '(11) 98765-0143');
    });
  });
}
