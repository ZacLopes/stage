import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/features/jobs/utils/apply_email.dart';

/// Cobre a montagem do email de candidatura (applicationMethod == 'email'):
/// corpo personalizado com nome da vaga + nome do candidato, assunto, e o
/// mailto final (RFC 6068: %20 pra espaço, %0D%0A pra quebra de linha).
void main() {
  group('buildApplicationEmailBody', () {
    test('preenche nome da vaga e do candidato', () {
      final body = buildApplicationEmailBody(
        jobTitle: 'Analista de Marketing',
        userName: 'Maria Silva',
      );
      expect(body, contains('Estou me candidatando à vaga de Analista de Marketing.'));
      expect(body, contains('Segue meu currículo em anexo para avaliação.'));
      expect(body.trimRight(), endsWith('Maria Silva'));
      // Sem placeholders sobrando quando há dados.
      expect(body, isNot(contains('[Nome da Vaga]')));
      expect(body, isNot(contains('[Nome do candidato]')));
    });

    test('usa CRLF entre as linhas (RFC 6068)', () {
      final body = buildApplicationEmailBody(
        jobTitle: 'Dev',
        userName: 'João',
      );
      expect(body, contains('\r\n'));
      expect(body, startsWith('Olá,\r\n'));
    });

    test('mantém placeholder do candidato quando nome ausente/fallback', () {
      expect(
        buildApplicationEmailBody(jobTitle: 'Dev', userName: null),
        contains('[Nome do candidato]'),
      );
      expect(
        buildApplicationEmailBody(jobTitle: 'Dev', userName: '   '),
        contains('[Nome do candidato]'),
      );
      // "Usuário" é o fallback genérico do resolveDisplayName — não é nome real.
      expect(
        buildApplicationEmailBody(jobTitle: 'Dev', userName: 'Usuário'),
        contains('[Nome do candidato]'),
      );
    });

    test('mantém placeholder da vaga quando título vazio', () {
      expect(
        buildApplicationEmailBody(jobTitle: '   ', userName: 'Ana'),
        contains('de [Nome da Vaga].'),
      );
    });
  });

  group('buildApplicationEmailSubject', () {
    test('usa assunto sugerido e substitui [SEU NOME]', () {
      expect(
        buildApplicationEmailSubject(
          jobTitle: 'Analista',
          suggestedSubject: 'Candidatura [SEU NOME] - Vaga X',
          userName: 'Maria Silva',
        ),
        'Candidatura Maria Silva - Vaga X',
      );
    });

    test('não substitui placeholder quando nome é fallback', () {
      expect(
        buildApplicationEmailSubject(
          jobTitle: 'Analista',
          suggestedSubject: '(seu nome) candidatura',
          userName: 'Usuário',
        ),
        '(seu nome) candidatura',
      );
    });

    test('padrão Candidatura — <vaga> quando não há assunto sugerido', () {
      expect(
        buildApplicationEmailSubject(jobTitle: 'Analista de Dados'),
        'Candidatura — Analista de Dados',
      );
    });
  });

  group('buildApplyMailtoUri', () {
    test('monta mailto com subject e body percent-encoded', () {
      final uri = buildApplyMailtoUri(
        email: 'rh@empresa.com',
        jobTitle: 'Designer',
        suggestedSubject: null,
        userName: 'Carlos Souza',
      );
      expect(uri.scheme, 'mailto');
      expect(uri.path, 'rh@empresa.com');
      // Espaço vira %20 (não +), quebra de linha vira %0D%0A.
      final raw = uri.toString();
      expect(raw, contains('subject=Candidatura%20%E2%80%94%20Designer'));
      expect(raw, contains('body='));
      expect(raw, contains('%0D%0A'));
      expect(raw, isNot(contains('+')));
      // O cliente de email decodifica de volta pro texto certo.
      expect(uri.queryParameters['body'], contains('vaga de Designer.'));
      expect(uri.queryParameters['body']!.trimRight(), endsWith('Carlos Souza'));
    });
  });
}
