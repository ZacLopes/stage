import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/features/jobs/models/job.dart';

// Revisão de UX 28/07: dois normalizadores de texto vindo do ATS.
//
// Os casos "não mexe" são tão importantes quanto os que limpam: normalizador
// agressivo demais destrói nome de empresa e conteúdo de vaga em silêncio.
void main() {
  // ⚠️ ESTA TABELA É O CONTRATO. Ela existe IDÊNTICA em
  // supabase/functions/_shared/jobs.test.ts. Mudou aqui, muda lá — duas
  // implementações de uma regra só divergem quando a tabela não é a mesma.
  const casosNomeEmpresa = <List<String>>[
    // limpa o prefixo de tipo de vaga
    ['Estágio M. Dias Branco', 'M. Dias Branco'],
    ['ESTÁGIO KEMPETRO', 'KEMPETRO'],
    ['Programa de Estágio - Santa Casa BH', 'Santa Casa BH'],
    ['Programa de Estágio Anbima 2026', 'Anbima'],
    ['Programa de Trainee SLC Agrícola', 'SLC Agrícola'],
    ['Programa de Trainees - BLB Auditores e Consultores', 'BLB Auditores e Consultores'],
    ['Banco de Talentos — Acme', 'Acme'],
    // o que o prefixo deixava para trás (medido em prod, 30/07)
    ['Estágio | Pif Paf Alimentos', 'Pif Paf Alimentos'],
    ['Programa de Estágio 2026 - Grupo Solví', 'Grupo Solví'],
    ['Programa de Estágio da PUCPR', 'PUCPR'],
    ['Programa de Estágio do CEPEL', 'CEPEL'],
    // NÃO mexe: marca legítima, nome comum, conectivo sem prefixo
    ['Programa UTalent', 'Programa UTalent'],
    ['Nubank', 'Nubank'],
    ['Vagas.com', 'Vagas.com'],
    ['Estagiário Digital Ltda', 'Estagiário Digital Ltda'],
    ['Banco do Brasil', 'Banco do Brasil'],
    ['2026 Ventures', '2026 Ventures'],
    ['de Souza Consultoria', 'de Souza Consultoria'],
    // guard: sobrou pouco demais → devolve o cru
    ['Estágio', 'Estágio'],
    ['Programa de Estágio', 'Programa de Estágio'],
    // bordas
    ['', ''],
    ['   ', ''],
    ['  Acme  ', 'Acme'],
  ];

  group('cleanCompanyName — tira prefixo de tipo de vaga (achado P2-18)', () {
    for (final caso in casosNomeEmpresa) {
      test('"${caso[0]}" → "${caso[1]}"', () {
        expect(Job.cleanCompanyName(caso[0]), caso[1]);
      });
    }

    test('é idempotente (limpar o já limpo não muda)', () {
      for (final caso in casosNomeEmpresa) {
        final umaVez = Job.cleanCompanyName(caso[0]);
        expect(Job.cleanCompanyName(umaVez), umaVez,
            reason: 'não idempotente em "${caso[0]}"');
      }
    });
  });

  group('requisitos/benefícios — marcador duplo (achado P2-17)', () {
    // `_stripListItemMarker` é privado; o contrato é exercitado via fromJson,
    // que é como o app realmente monta a vaga.
    List<String> reqsOf(List<String> raw) => Job.fromJson({
          'id': 'j1',
          'title': 'Estágio',
          // `work_model` e `job_type` são cast não-nulável no fromJson.
          'work_model': 'remoto',
          'job_type': 'estagio',
          'requirements': raw,
          'benefits': raw,
        }).requirements;

    test('tira hífen digitado pelo recrutador', () {
      expect(reqsOf(['- Lembre-se que podemos te ligar']),
          ['Lembre-se que podemos te ligar']);
    });

    test('tira o bullet que veio de <li> e o ponto-e-vírgula final', () {
      expect(reqsOf(['• Plano de Saúde;']), ['Plano de Saúde']);
    });

    test('tira marcadores empilhados', () {
      expect(reqsOf(['- • Vale refeição']), ['Vale refeição']);
    });

    test('NÃO come hífen no meio nem palavra que começa com traço-de-união', () {
      expect(reqsOf(['Excel — nível avançado']), ['Excel — nível avançado']);
      expect(reqsOf(['Pró-atividade e organização']),
          ['Pró-atividade e organização']);
    });

    test('item vazio depois da limpeza é descartado', () {
      expect(reqsOf(['-', '•  ', 'Inglês intermediário']),
          ['Inglês intermediário']);
    });
  });
}
