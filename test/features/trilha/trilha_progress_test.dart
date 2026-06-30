import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:career_gamification/features/profile/domain/repositories/profile_repository.dart';
import 'package:career_gamification/features/trilha/application/trilha_progress.dart';

/// Repo falso: só os 2 métodos de progresso; o resto lança via noSuchMethod.
class _FakeRepo implements ProfileRepository {
  final Set<String> server = {};
  bool fail = false;
  int markCalls = 0;

  @override
  Future<Set<String>> getGuidedProgress(String userId) async {
    if (fail) throw Exception('network');
    return {...server};
  }

  @override
  Future<void> markGuidedProgress(String userId, String segment) async {
    markCalls++;
    if (fail) throw Exception('network');
    server.add(segment);
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} não deveria ser chamado');
}

/// Cobre a memória da trilha — o que impede re-perguntar skills/experiência.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('marca e lê trechos abordados, isolado por usuário', () async {
    final p = TrilhaProgress();
    expect(await p.addressed('u1'), isEmpty);

    await p.mark('u1', 'skills');
    // experiência conta quando o DADO é salvo (exp.0.ofazia), não no gate.
    await p.markForAnswer('u1', 'exp.0.ofazia', 'Cuidava das redes');

    expect(await p.addressed('u1'), containsAll(['skills', 'experience']));
    expect(await p.addressed('u2'), isEmpty); // outro usuário não é afetado
  });

  test('markForAnswer ignora controle E gate "sim" (bug do sair no meio)',
      () async {
    final p = TrilhaProgress();
    await p.markForAnswer('u1', 'intro', ['go']);
    await p.markForAnswer('u1', 'exp.0.company', 'Magalu');
    // "sim" no gate só abre o texto → NÃO marca (se sair, a pergunta volta).
    await p.markForAnswer('u1', 'exp.gate', ['yes']);
    expect(await p.addressed('u1'), isEmpty);
  });

  test('segmentForStep marca em passos terminais (dado salvo), não no gate', () {
    expect(TrilhaProgress.segmentForStep('gap.skills'), 'skills');
    expect(TrilhaProgress.segmentForStep('gap.area'), 'area');
    expect(TrilhaProgress.segmentForStep('gap.desired_position'), 'desired_position');
    expect(TrilhaProgress.segmentForStep('gap.availability'), 'availability');
    expect(TrilhaProgress.segmentForStep('gap.interests'), 'interests');
    expect(TrilhaProgress.segmentForStep('linkedin.url'), 'linkedin');
    // save indexados:
    expect(TrilhaProgress.segmentForStep('exp.0.ofazia'), 'experience');
    expect(TrilhaProgress.segmentForStep('project.1.link'), 'projects');
    // O 'did' NÃO conta mais (o projeto só é gravado no último passo, 'link') —
    // sair na data NÃO marca como abordado, então a trilha re-pergunta na volta.
    expect(TrilhaProgress.segmentForStep('project.1.did'), isNull);
    expect(TrilhaProgress.segmentForStep('cert.0.date'), 'certifications');
    expect(TrilhaProgress.segmentForStep('cert.0.name'), isNull); // intermediário
    expect(TrilhaProgress.segmentForStep('award.0.date'), 'awards');
    expect(TrilhaProgress.segmentForStep('award.0.name'), isNull); // intermediário
    // Educação: marca no último passo do ramo (formatura/ano), não nos do meio.
    expect(TrilhaProgress.segmentForStep('gap.edu.graduation'), 'education');
    expect(TrilhaProgress.segmentForStep('gap.edu.schoolyear'), 'education');
    expect(TrilhaProgress.segmentForStep('gap.edu.semester'), isNull); // intermediário
    expect(TrilhaProgress.segmentForStep('gap.edu.institution'), isNull);
    expect(TrilhaProgress.segmentForStep('gap.edu.moment'), isNull);
    // gates NÃO marcam por aqui:
    expect(TrilhaProgress.segmentForStep('exp.gate'), isNull);
    expect(TrilhaProgress.segmentForStep('linkedin.gate'), isNull);
    expect(TrilhaProgress.segmentForStep('intro'), isNull);
  });

  test('segmentToMark: gate "não" marca; gate "sim" não; dado salvo marca', () {
    expect(TrilhaProgress.segmentToMark('exp.gate', ['yes']), isNull);
    expect(TrilhaProgress.segmentToMark('project.gate', ['yes']), isNull);
    expect(TrilhaProgress.segmentToMark('linkedin.gate', ['yes']), isNull);
    expect(TrilhaProgress.segmentToMark('exp.gate', ['no']), 'experience');
    expect(TrilhaProgress.segmentToMark('cert.gate', ['no']), 'certifications');
    expect(TrilhaProgress.segmentToMark('award.gate', ['no']), 'awards');
    expect(TrilhaProgress.segmentToMark('interests.gate', ['no']), 'interests');
    expect(TrilhaProgress.segmentToMark('exp.0.ofazia', 'x'), 'experience');
    expect(TrilhaProgress.segmentToMark('award.0.date', '2025-03'), 'awards');
    expect(TrilhaProgress.segmentToMark('linkedin.url', 'x'), 'linkedin');
    // Educação: "outro" no momento marca (não re-pergunta); escolher faculdade/
    // escola NÃO marca no momento (espera o dado ser salvo no último passo).
    expect(TrilhaProgress.segmentToMark('gap.edu.moment', ['outro']), 'education');
    expect(TrilhaProgress.segmentToMark('gap.edu.moment', ['in_college']), isNull);
    expect(TrilhaProgress.segmentToMark('gap.edu.graduation', ['2027']), 'education');
    expect(TrilhaProgress.segmentToMark('gap.edu.semester', ['5']), isNull); // intermediário
  });

  group('híbrido (retomada entre devices)', () {
    test('addressed une servidor + local e semeia o cache local', () async {
      SharedPreferences.setMockInitialValues({
        'trilha_addressed_u1': ['skills'],
      });
      final repo = _FakeRepo()..server.addAll({'area', 'experience'});
      final p = TrilhaProgress(repository: repo);

      final got = await p.addressed('u1');
      expect(got, containsAll(['skills', 'area', 'experience']));

      // O cache local foi semeado com o do servidor → um leitor local-only
      // (outro "device" no mesmo prefs) agora enxerga tudo.
      expect(await TrilhaProgress().addressed('u1'),
          containsAll(['skills', 'area', 'experience']));
    });

    test('mark grava no local E no servidor', () async {
      final repo = _FakeRepo();
      final p = TrilhaProgress(repository: repo);
      await p.mark('u1', 'skills');
      expect(repo.server, contains('skills'));
      expect(await TrilhaProgress().addressed('u1'), contains('skills'));
    });

    test('falha do servidor no addressed cai no cache local (não lança)',
        () async {
      SharedPreferences.setMockInitialValues({
        'trilha_addressed_u1': ['skills'],
      });
      final repo = _FakeRepo()..fail = true;
      final p = TrilhaProgress(repository: repo);
      expect(await p.addressed('u1'), ['skills']);
    });

    test('falha do servidor no mark ainda grava local (não lança)', () async {
      final repo = _FakeRepo()..fail = true;
      final p = TrilhaProgress(repository: repo);
      await p.mark('u1', 'skills');
      expect(await TrilhaProgress().addressed('u1'), contains('skills'));
      expect(repo.markCalls, 1); // tentou o servidor
    });
  });
}
