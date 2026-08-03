import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/features/onboarding/utils/name_validation.dart';

/// Revisão UX 28/07, achado P3-35 — e a lição de 30/07.
///
/// A primeira correção blindou só o `onContinue` do botão. O `_continue()`
/// interno seguia com `if (value.isEmpty) return`, e `onSubmitted` chama esse
/// método DIRETO: a tecla de retorno do teclado salvava um nome de uma letra
/// com o botão "Continuar" desabilitado ao lado.
///
/// É o padrão que se repetiu em quase toda a revisão: corrigir a afordância que
/// aparece na foto e deixar o caminho de verdade aberto. Este arquivo existe
/// para o predicado ter dono e teste próprios.
void main() {
  group('isValidOnboardingName', () {
    test('rejeita vazio e só espaço', () {
      expect(isValidOnboardingName(''), isFalse);
      expect(isValidOnboardingName('   '), isFalse);
      expect(isValidOnboardingName('\n\t'), isFalse);
    });

    test('rejeita uma letra — o dano do achado', () {
      // "T" ia parar no cabeçalho do currículo enviado ao recrutador.
      expect(isValidOnboardingName('T'), isFalse);
      expect(isValidOnboardingName(' a '), isFalse);
    });

    test('aceita duas letras — é o piso, não uma regra sobre nome de gente', () {
      expect(isValidOnboardingName('Bo'), isTrue);
      expect(isValidOnboardingName('Al'), isTrue);
    });

    test('não inventa regra sobre forma do nome', () {
      // Nada de exigir sobrenome, acento, capitalização ou só letras: nome é
      // dado de identidade, não de formulário.
      expect(isValidOnboardingName('ana'), isTrue);
      expect(isValidOnboardingName("D'Ávila"), isTrue);
      expect(isValidOnboardingName('Nguyễn'), isTrue);
      expect(isValidOnboardingName('Ana Maria'), isTrue);
      expect(isValidOnboardingName('J. R.'), isTrue);
    });

    test('conta depois de aparar as bordas', () {
      expect(isValidOnboardingName('  T  '), isFalse);
      expect(isValidOnboardingName('  Té  '), isTrue);
    });
  });
}
