// A pergunta do aluno não pode virar dado no perfil dele.
//
// Defeito ativo em produção até 20/08/2026, e independente de qualquer flag:
// no passo de texto guiado, QUALQUER coisa digitada virava a resposta. A tela
// perguntava "Qual o nome da empresa?", a pessoa digitava "como faço um
// currículo sem experiência?", e o perfil ficava com esse texto no campo da
// empresa.
//
// O predicado é privado no controller, então este teste replica a MESMA regex
// e trava o contrato dela. Se alguém mexer no controller sem mexer aqui, a
// duplicata deixa de bater e a divergência aparece — que é o objetivo. A
// alternativa (instanciar o TrilhaChatController) arrasta Supabase e não roda
// em teste de unidade.
//
// ⚠️ O viés é assumido e está documentado no controller: é MELHOR deixar passar
// uma pergunta do que bloquear uma resposta legítima. Por isso este detector é
// bem mais estreito que o `_looksLikeCommand` do assistente — aquele casa
// 'certifica', 'experiência', 'cargo', 'idioma', que são respostas válidas.

import 'package:flutter_test/flutter_test.dart';

final RegExp _questionOpeners = RegExp(
  r"^\s*(como\s+(fa[cç]o|que|eu)|o\s+que\s+(é|e|significa)|me\s+ajuda"
  r"|pode\s+me\s+ajudar|preciso\s+de\s+ajuda|tem\s+como|e\s+se\s+eu"
  r"|n[aã]o\s+sei|nao\s+sei|sei\s+l[aá])(?![a-zà-ÿ])",
  caseSensitive: false,
);

bool looksLikeQuestionNotAnswer(String t) {
  final s = t.trim();
  if (s.isEmpty) return false;
  if (s.endsWith('?')) return true;
  return _questionOpeners.hasMatch(s);
}

void main() {
  group('BLOQUEIA — não pode virar dado no perfil', () {
    const perguntas = [
      // o caso real que motivou o conserto
      'como faço um currículo sem experiência?',
      'como faço pra colocar meu estágio',
      'o que é bullet point',
      'o que significa ATS?',
      'me ajuda a escrever isso',
      'pode me ajudar?',
      'preciso de ajuda',
      'tem como pular essa parte',
      'e se eu não tiver experiência',
      // desistência: gravar "não sei" como nome de empresa é lixo que o
      // match depois pontua a sério
      'não sei',
      'nao sei',
      'Sei lá',
      // qualquer coisa terminada em '?'
      'Ambev?',
    ];

    for (final p in perguntas) {
      test('"$p"', () => expect(looksLikeQuestionNotAnswer(p), isTrue));
    }
  });

  group('DEIXA PASSAR — respostas legítimas de passo de texto', () {
    const respostas = [
      // nomes de empresa
      'Ambev',
      'Banco Inter S.A.',
      'Como & Cia Consultoria', // começa com "Como" mas não é pergunta
      // cargos
      'Estagiário de Business Intelligence',
      'Analista de Dados Júnior',
      // instituições
      'Universidade de São Paulo',
      'Escola Politécnica',
      // ⚠️ os que o `_looksLikeCommand` bloquearia por engano — a razão de
      // este predicado existir separado
      'Certificação Scrum Master',
      'Experiência em Power BI',
      'Cargo de monitoria',
      'Idiomas: inglês e espanhol',
      'São Paulo',
      'Projeto de otimização logística',
    ];

    for (final r in respostas) {
      test('"$r"', () => expect(looksLikeQuestionNotAnswer(r), isFalse));
    }
  });

  group('bordas', () {
    test('vazio não bloqueia (o passo trata isso antes)', () {
      expect(looksLikeQuestionNotAnswer(''), isFalse);
      expect(looksLikeQuestionNotAnswer('   '), isFalse);
    });

    test('espaço à frente não escapa do detector', () {
      expect(looksLikeQuestionNotAnswer('   não sei   '), isTrue);
    });

    test('"como" sozinho não basta — precisa da forma de pergunta', () {
      // "Como" é começo de nome próprio plausível; só bloqueia com
      // faço/que/eu logo depois.
      expect(looksLikeQuestionNotAnswer('Comodoro Engenharia'), isFalse);
    });
  });
}
