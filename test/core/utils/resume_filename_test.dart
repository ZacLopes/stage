import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/core/utils/resume_filename.dart';

/// B1/D1 do device-test de 24/07 + decisão 6 do fundador (26/07):
/// sem flag · fallback `curriculo.pdf` · sem acentos · NUNCA derivar de e-mail.
void main() {
  group('fallback — o defeito original', () {
    test('nome vazio vira curriculo.pdf (era curriculo_.pdf)', () {
      expect(
        ResumeFilename.build(preferredName: '', accountName: ''),
        'curriculo.pdf',
      );
    });

    test('nome nulo vira curriculo.pdf', () {
      expect(ResumeFilename.build(), 'curriculo.pdf');
    });

    test('nome só com espaços vira curriculo.pdf', () {
      expect(
        ResumeFilename.build(preferredName: '   ', accountName: '  '),
        'curriculo.pdf',
      );
    });

    test('sem nome mas com sufixo NÃO gera underscore duplo', () {
      // Era `curriculo__1eee2f.pdf`.
      expect(
        ResumeFilename.build(accountName: '', suffix: '1eee2f'),
        'curriculo_1eee2f.pdf',
      );
    });
  });

  group('precedência — o nome impresso no documento vence o da conta', () {
    test('preferredName tem prioridade sobre accountName', () {
      expect(
        ResumeFilename.build(
          preferredName: 'Maria Oliveira',
          accountName: 'Zac Teste',
        ),
        'curriculo_Maria_Oliveira.pdf',
      );
    });

    test('cai para accountName quando preferredName é inutilizável', () {
      expect(
        ResumeFilename.build(preferredName: '', accountName: 'Zac Teste'),
        'curriculo_Zac_Teste.pdf',
      );
    });

    test('o caso real do device-test: name vazio + first_name preenchido', () {
      // 100 dos 110 usuários sem `user_profiles.name` têm first_name salvo —
      // é ele que chega aqui como preferredName (via ResumeData.fullName).
      expect(
        ResumeFilename.build(preferredName: 'Zac Teste', accountName: ''),
        'curriculo_Zac_Teste.pdf',
      );
    });
  });

  group('NUNCA derivar de e-mail (decisão 6)', () {
    test('e-mail sintético do login por telefone é rejeitado', () {
      // 109 dos 110 usuários sem nome entraram por telefone. Se isso vazasse,
      // o telefone da pessoa iria no nome do PDF anexado numa vaga.
      final out = ResumeFilename.build(
        preferredName: 'phone_5511999887766@stage.app',
      );
      expect(out, 'curriculo.pdf');
      expect(out.contains('5511999887766'), isFalse);
      expect(out.contains('phone'), isFalse);
    });

    test('alias privado da Apple é rejeitado', () {
      expect(
        ResumeFilename.build(preferredName: 'abc123xyz@privaterelay.appleid.com'),
        'curriculo.pdf',
      );
    });

    test('domínio privado do iCloud é rejeitado', () {
      expect(
        ResumeFilename.build(preferredName: 'abc@private.icloud.com'),
        'curriculo.pdf',
      );
    });

    test('QUALQUER coisa com @ é rejeitada, não só relay/sintético', () {
      expect(
        ResumeFilename.build(preferredName: 'joao.silva@gmail.com'),
        'curriculo.pdf',
      );
      expect(ResumeFilename.isUsableName('a@b'), isFalse);
    });

    test('e-mail no preferredName cai para o accountName válido', () {
      expect(
        ResumeFilename.build(
          preferredName: 'phone_5511999887766@stage.app',
          accountName: 'Zac Teste',
        ),
        'curriculo_Zac_Teste.pdf',
      );
    });
  });

  group('acentos — sem acento (decisão 6)', () {
    test('nome acentuado é dobrado para ASCII', () {
      expect(
        ResumeFilename.build(preferredName: 'José Antônio da Silva'),
        'curriculo_Jose_Antonio_da_Silva.pdf',
      );
    });

    test('cedilha e til', () {
      expect(
        ResumeFilename.build(preferredName: 'Conceição Assunção'),
        'curriculo_Conceicao_Assuncao.pdf',
      );
    });

    test('nome sem acento sai idêntico ao comportamento de hoje', () {
      // Monotonicidade: onde já havia nome ASCII, o filename NÃO muda.
      const nome = 'Zac Lopes';
      final antigo = 'curriculo_${nome.replaceAll(' ', '_')}.pdf';
      expect(ResumeFilename.build(preferredName: nome), antigo);
    });
  });

  group('sanitização — nada escapa para o filename', () {
    test('barra e path traversal não sobrevivem', () {
      final out = ResumeFilename.build(preferredName: '../../etc/passwd');
      expect(out.contains('/'), isFalse);
      expect(out.contains('..'), isFalse);
    });

    test('espaços múltiplos viram um underscore só', () {
      expect(
        ResumeFilename.build(preferredName: 'Ana    Maria'),
        'curriculo_Ana_Maria.pdf',
      );
    });

    test('não sobra underscore nas pontas', () {
      final out = ResumeFilename.build(preferredName: '  _Ana_  ');
      expect(out, 'curriculo_Ana.pdf');
    });

    test('nome muito longo é truncado sem underscore solto no fim', () {
      final longo = List.filled(30, 'Silva').join(' ');
      final out = ResumeFilename.build(preferredName: longo);
      expect(out.endsWith('.pdf'), isTrue);
      expect(out.endsWith('_.pdf'), isFalse);
      // 'curriculo_' + <=60 + '.pdf'
      expect(out.length <= 'curriculo_'.length + 60 + '.pdf'.length, isTrue);
    });

    test('sempre termina em .pdf e começa em curriculo', () {
      for (final nome in ['', 'Ana', 'José', 'a@b.com', '   ']) {
        final out = ResumeFilename.build(preferredName: nome);
        expect(out.startsWith('curriculo'), isTrue, reason: nome);
        expect(out.endsWith('.pdf'), isTrue, reason: nome);
      }
    });
  });

  group('sufixo da vaga (CV adaptado)', () {
    test('nome + sufixo', () {
      expect(
        ResumeFilename.build(preferredName: 'Zac Lopes', suffix: '1eee2f'),
        'curriculo_Zac_Lopes_1eee2f.pdf',
      );
    });

    test('sufixo vazio não deixa underscore sobrando', () {
      expect(
        ResumeFilename.build(preferredName: 'Zac Lopes', suffix: ''),
        'curriculo_Zac_Lopes.pdf',
      );
    });
  });
}
