import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/features/jobs/models/job.dart';

// Revisão de UX 28/07: dois normalizadores de texto vindo do ATS.
//
// Os casos "não mexe" são tão importantes quanto os que limpam: normalizador
// agressivo demais destrói nome de empresa e conteúdo de vaga em silêncio.
void main() {
  group('cleanCompanyName — tira prefixo de tipo de vaga (achado P2-18)', () {
    test('remove prefixos vistos em produção', () {
      // Amostra real de `companies.name` (jobs ativas, 28/07).
      expect(Job.cleanCompanyName('Estágio M. Dias Branco'), 'M. Dias Branco');
      expect(Job.cleanCompanyName('ESTÁGIO KEMPETRO'), 'KEMPETRO');
      expect(Job.cleanCompanyName('Programa de Estágio - Santa Casa BH'),
          'Santa Casa BH');
      expect(Job.cleanCompanyName('Programa de Estágio Anbima 2026'), 'Anbima');
      expect(Job.cleanCompanyName('Programa de Trainee SLC Agrícola'),
          'SLC Agrícola');
      expect(Job.cleanCompanyName('Programa de Trainees - BLB Auditores e Consultores'),
          'BLB Auditores e Consultores');
      expect(Job.cleanCompanyName('Banco de Talentos — Acme'), 'Acme');
    });

    test('NÃO mexe em nome legítimo', () {
      // "Programa UTalent" é a marca do programa, não "Programa" + empresa:
      // não casa com `programa de …` e passa intacto.
      expect(Job.cleanCompanyName('Programa UTalent'), 'Programa UTalent');
      expect(Job.cleanCompanyName('Nubank'), 'Nubank');
      expect(Job.cleanCompanyName('Vagas.com'), 'Vagas.com');
      expect(Job.cleanCompanyName('Estagiário Digital Ltda'),
          'Estagiário Digital Ltda');
      expect(Job.cleanCompanyName('Banco do Brasil'), 'Banco do Brasil');
      expect(Job.cleanCompanyName('2026 Ventures'), '2026 Ventures');
    });

    test('devolve o cru quando sobraria pouco demais', () {
      expect(Job.cleanCompanyName('Estágio'), 'Estágio');
      expect(Job.cleanCompanyName('Programa de Estágio'), 'Programa de Estágio');
    });

    test('vazio e espaços não quebram', () {
      expect(Job.cleanCompanyName(''), '');
      expect(Job.cleanCompanyName('   '), '');
      expect(Job.cleanCompanyName('  Acme  '), 'Acme');
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
