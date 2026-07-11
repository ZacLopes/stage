// Fase 7 · gate-list +10 (Tarefa 2): o usuário pode adicionar QUALQUER área;
// cada área custom ganha uma canônica oculta ('inferred') pro candidato ficar
// matchável. Testa o mapeamento e a derivação.
import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/features/trilha/application/area_canonical.dart';
import 'package:career_gamification/features/profile/domain/entities/entities.dart';

DesiredTitle _dt(String title,
        [DesiredTitleSource s = DesiredTitleSource.userAdded]) =>
    DesiredTitle(id: '', userId: 'u', title: title, source: s, orderIndex: 0);

void main() {
  group('canonicalArea', () {
    test('identidade + normalização quando já é canônica', () {
      expect(canonicalArea('Marketing'), 'Marketing');
      expect(canonicalArea('marketing'), 'Marketing');
      expect(isCanonicalArea('Tecnologia'), isTrue);
      expect(isCanonicalArea('Dados'), isFalse);
    });
    test('alias mapeia área custom → uma das 13', () {
      expect(canonicalArea('Dados'), 'Tecnologia');
      expect(canonicalArea('Comunicação'), 'Marketing');
      expect(canonicalArea('Logística'), 'Operações');
      expect(canonicalArea('Moda'), 'Design');
    });
    test('contém nome de canônica ("Marketing Digital" → Marketing)', () {
      expect(canonicalArea('Marketing Digital'), 'Marketing');
    });
    test('área desconhecida cai em Geral (não some do funil)', () {
      expect(canonicalArea('Astrologia Financeira'), 'Geral');
    });
  });

  group('withInferredAreas', () {
    test('área custom → linha do usuário + canônica oculta', () {
      final out = withInferredAreas('u', [_dt('Dados')]);
      final bySource = {for (final t in out) t.title: t.source};
      expect(bySource['Dados'], DesiredTitleSource.userAdded);
      expect(bySource['Tecnologia'], DesiredTitleSource.inferred);
    });
    test('área canônica não gera inferred duplicada', () {
      final out = withInferredAreas('u', [_dt('Tecnologia')]);
      expect(out.length, 1);
      expect(out.first.source, DesiredTitleSource.userAdded);
    });
    test('área explícita do usuário nunca é rebaixada a inferred', () {
      // Escolhe uma custom que mapeia pra Tecnologia E escolhe Tecnologia.
      final out = withInferredAreas('u', [_dt('Dados'), _dt('Tecnologia')]);
      final tec = out.firstWhere((t) => t.title == 'Tecnologia');
      expect(tec.source, DesiredTitleSource.userAdded);
    });
    test('canônica mis-cased → grava na grafia canônica (bucket exato)', () {
      // "recursos humanos" (autocapitalize do teclado) tem que virar
      // "Recursos Humanos" pra cair no bucket EXATO da busca do admin, não
      // num bucket órfão minúsculo que o recrutador não filtra.
      final out = withInferredAreas('u', [_dt('recursos humanos')]);
      final titles = out.map((t) => t.title).toList();
      expect(titles, contains('Recursos Humanos'));
      expect(titles, isNot(contains('recursos humanos')));
      final rh = out.firstWhere((t) => t.title == 'Recursos Humanos');
      expect(rh.source, DesiredTitleSource.userAdded);
    });
  });
}
