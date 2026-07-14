import 'package:career_gamification/features/profile/domain/skill_name_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeSkillNames', () {
    test('limpa espaços e agrupa duplicatas sem caixa ou acento', () {
      expect(
        normalizeSkillNames(const [
          '  Comunicação  ',
          'comunicacao',
          'Excel   avançado',
          'ÉXCEL AVANCADO',
          ' ',
        ]),
        const ['Comunicação', 'Excel avançado'],
      );
    });

    test('não une aliases semânticos sem confirmação', () {
      expect(normalizeSkillNames(const ['Excel', 'Excel básico']), const [
        'Excel',
        'Excel básico',
      ]);
    });

    test('nunca trunca silenciosamente uma lista acima do recomendado', () {
      final names = List.generate(14, (index) => 'Habilidade ${index + 1}');
      expect(normalizeSkillNames(names), hasLength(14));
    });
  });
}
