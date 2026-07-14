import 'package:career_gamification/features/profile/domain/award_editor_reconciliation.dart';
import 'package:career_gamification/features/profile/domain/entities/entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reconcileAwardLabels', () {
    test('preserva id e data completa sem guardar o ano dentro do nome', () {
      final date = DateTime(2024, 8, 17);
      final result = reconcileAwardLabels(
        userId: 'user-1',
        current: [
          Award(
            id: 'award-1',
            userId: 'user-1',
            name: 'melhor projeto',
            date: date,
          ),
        ],
        labels: const ['melhor projeto (2024)'],
      );

      expect(result.single.id, 'award-1');
      expect(result.single.name, 'Melhor projeto');
      expect(result.single.name, isNot(contains('2024')));
      expect(result.single.date, date);
    });

    test('reconhece itens reordenados pelo label e mantém os UUIDs', () {
      final current = [
        Award(
          id: 'award-a',
          userId: 'user-1',
          name: 'Prêmio A',
          date: DateTime(2023),
        ),
        Award(
          id: 'award-b',
          userId: 'user-1',
          name: 'Prêmio B',
          date: DateTime(2024),
          orderIndex: 1,
        ),
      ];

      final result = reconcileAwardLabels(
        userId: 'user-1',
        current: current,
        labels: const ['Prêmio B (2024)', 'Prêmio A (2023)'],
      );

      expect(result.map((award) => award.id), ['award-b', 'award-a']);
      expect(result.map((award) => award.orderIndex), [0, 1]);
    });

    test('edição material vira item novo sem herdar identidade antiga', () {
      final result = reconcileAwardLabels(
        userId: 'user-1',
        current: [
          Award(
            id: 'award-1',
            userId: 'user-1',
            name: 'Prêmio antigo',
            date: DateTime(2024, 5, 9),
          ),
        ],
        labels: const ['premio de inovacao (2026)'],
      );

      expect(result.single.id, isEmpty);
      expect(result.single.name, 'Premio de inovacao');
      expect(result.single.date, DateTime(2026));
    });

    test('remoção antes de item editado não transfere UUID', () {
      final current = [
        const Award(id: 'removido', userId: 'user-1', name: 'Removido'),
        const Award(id: 'editado', userId: 'user-1', name: 'Nome antigo'),
        const Award(id: 'ancora', userId: 'user-1', name: 'Permanece'),
      ];

      final result = reconcileAwardLabels(
        userId: 'user-1',
        current: current,
        labels: const ['nome novo', 'Permanece'],
      );

      expect(result.map((award) => award.id), ['', 'ancora']);
      expect(result.first.name, 'Nome novo');
    });

    test(
      'item novo não herda id nem data de prêmio removido em outro segmento',
      () {
        final current = [
          Award(
            id: 'removido',
            userId: 'user-1',
            name: 'Prêmio A',
            date: DateTime(2020, 8, 17),
          ),
          Award(
            id: 'mantido',
            userId: 'user-1',
            name: 'Prêmio B',
            date: DateTime(2021, 4, 3),
          ),
        ];

        final result = reconcileAwardLabels(
          userId: 'user-1',
          current: current,
          // O editor remove A, mantém B (âncora) e acrescenta C ao fim.
          labels: const ['Prêmio B (2021)', 'Prêmio C'],
        );

        expect(result.first.id, 'mantido');
        expect(result.last.id, isEmpty);
        expect(result.last.name, 'Prêmio C');
        expect(result.last.date, isNull);
      },
    );

    test('remoção e rename após âncora também não transferem UUID/data', () {
      final current = [
        const Award(id: 'ancora', userId: 'user-1', name: 'Permanece'),
        Award(
          id: 'removido',
          userId: 'user-1',
          name: 'Prêmio A',
          date: DateTime(2020, 8, 17),
        ),
        Award(
          id: 'editado',
          userId: 'user-1',
          name: 'Prêmio B',
          date: DateTime(2021, 4, 3),
        ),
      ];

      final result = reconcileAwardLabels(
        userId: 'user-1',
        current: current,
        labels: const ['Permanece', 'Prêmio B renomeado (2021)'],
      );

      expect(result.first.id, 'ancora');
      expect(result.last.id, isEmpty);
      expect(result.last.date, DateTime(2021));
    });

    test('novo item recebe id vazio e ignora labels vazios', () {
      final result = reconcileAwardLabels(
        userId: 'user-1',
        current: const [],
        labels: const [' ', 'melhor tcc (2026)'],
      );

      expect(result, hasLength(1));
      expect(result.single.id, isEmpty);
      expect(result.single.name, 'Melhor tcc');
      expect(result.single.date, DateTime(2026));
    });
  });
}
