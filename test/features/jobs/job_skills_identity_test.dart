import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/jobs/models/job_skills_extraction.dart';

/// A normalização de `markingAsInCv` é uma chave de IDENTIDADE, não de busca.
///
/// O servidor consertou isso em 01/08/2026 (`identityKey` em
/// `extract-job-skills/index.ts`), mas o cliente ficou com o flatten antigo
/// (`[^a-z0-9]`) e reintroduzia o falso positivo DEPOIS da resposta do
/// servidor — `markingAsInCv` só faz upgrade (`inCv: false → true`), nunca o
/// contrário, então nem deployar a function nova consertava.
///
/// Este arquivo é o primeiro teste a tocar `JobSkillsExtraction`: até 02/08 o
/// modelo não tinha nenhuma cobertura, e foi por isso que a divergência entre
/// as duas pontas passou. Espelha o caso "C, C++ e C# NÃO se confundem" de
/// `supabase/functions/extract-job-skills/owned_skills.test.ts`.
void main() {
  JobSkillsExtraction extracaoCom(List<String> nomes) => JobSkillsExtraction(
        skills: [
          for (final n in nomes)
            JobSkill(name: n, inCv: false, preConfirmed: false, source: 'requirements'),
        ],
        total: nomes.length,
        inCvCount: 0,
      );

  bool marcadaComoTenho(JobSkillsExtraction e, String nome) =>
      e.skills.firstWhere((s) => s.name == nome).inCv;

  group('a família C não colapsa numa coisa só', () {
    test('declarar C# NÃO faz o app dizer que a pessoa tem C++ nem C', () {
      final resultado = extracaoCom(['C', 'C++', 'C#']).markingAsInCv(['C#']);

      expect(marcadaComoTenho(resultado, 'C#'), isTrue,
          reason: 'a que ela declarou tem que ser reconhecida');
      expect(marcadaComoTenho(resultado, 'C++'), isFalse,
          reason: 'C++ é outra habilidade — ela precisa poder reivindicar');
      expect(marcadaComoTenho(resultado, 'C'), isFalse,
          reason: 'C é outra habilidade — ela precisa poder reivindicar');
      expect(resultado.inCvCount, 1);
    });

    test('declarar C não arrasta C++ nem C#', () {
      final resultado = extracaoCom(['C', 'C++', 'C#']).markingAsInCv(['C']);

      expect(marcadaComoTenho(resultado, 'C'), isTrue);
      expect(marcadaComoTenho(resultado, 'C++'), isFalse);
      expect(marcadaComoTenho(resultado, 'C#'), isFalse);
    });

    test('as três declaradas marcam as três', () {
      final resultado =
          extracaoCom(['C', 'C++', 'C#']).markingAsInCv(['C', 'C++', 'C#']);

      expect(resultado.inCvCount, 3);
      expect(resultado.missingSkills, isEmpty);
    });
  });

  group('o que a normalização DEVE continuar unificando', () {
    test('caixa, espaço e hífen não distinguem: "Power BI" == "power-bi"', () {
      final resultado = extracaoCom(['Power BI']).markingAsInCv(['power-bi']);
      expect(marcadaComoTenho(resultado, 'Power BI'), isTrue);
    });

    test('o ponto não distingue: "Node.js" == "nodejs"', () {
      final resultado = extracaoCom(['Node.js']).markingAsInCv(['nodejs']);
      expect(marcadaComoTenho(resultado, 'Node.js'), isTrue);
    });

    test('acento não distingue: "Inglês" == "ingles"', () {
      final resultado = extracaoCom(['Inglês']).markingAsInCv(['ingles']);
      expect(marcadaComoTenho(resultado, 'Inglês'), isTrue);
    });
  });

  group('contratos que já valiam e não podem regredir', () {
    test('lista vazia devolve o mesmo objeto, sem marcar nada', () {
      final original = extracaoCom(['C++', 'Python']);
      final resultado = original.markingAsInCv(const []);
      expect(identical(resultado, original), isTrue);
    });

    test('nomes só com pontuação são ignorados, não viram chave vazia', () {
      // Sem o filtro de `isNotEmpty`, "---" normalizaria para "" e passaria a
      // casar com qualquer skill que também normalizasse para vazio.
      final resultado = extracaoCom(['C++']).markingAsInCv(['---', '   ']);
      expect(marcadaComoTenho(resultado, 'C++'), isFalse);
      expect(resultado.inCvCount, 0);
    });

    test('quem já vinha inCv do servidor continua inCv', () {
      final original = JobSkillsExtraction(
        skills: const [
          JobSkill(name: 'SQL', inCv: true, preConfirmed: false, source: 'requirements'),
          JobSkill(name: 'C#', inCv: false, preConfirmed: false, source: 'requirements'),
        ],
        total: 2,
        inCvCount: 1,
      );
      final resultado = original.markingAsInCv(['C#']);
      expect(marcadaComoTenho(resultado, 'SQL'), isTrue);
      expect(marcadaComoTenho(resultado, 'C#'), isTrue);
      expect(resultado.inCvCount, 2);
    });
  });
}
