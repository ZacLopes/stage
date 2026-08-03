import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/jobs/utils/adapt_outcome.dart';

/// Achado do device-test de 02/08/2026: a tela dizia "Seu currículo já está bem
/// alinhado com essa vaga" sempre que a adaptação voltava sem mudanças — e
/// zero mudanças tem duas causas opostas.
///
/// Medido em produção: 106 pessoas (14,5% das 729 que passam no gate do adapt)
/// têm 3+ skills e ZERO experiências e ZERO projetos. Todas recebiam a
/// mensagem de "já está alinhado" para um currículo sem nada a adaptar.
void main() {
  group('classifica os dois motivos de zero mudanças', () {
    test('com material reescrevível ⇒ já estava alinhado', () {
      expect(
        classifyAdaptOutcome(changeCount: 0, hasRewritableContent: true),
        AdaptOutcome.alreadyAligned,
      );
    });

    test('SEM material reescrevível ⇒ não havia o que adaptar', () {
      expect(
        classifyAdaptOutcome(changeCount: 0, hasRewritableContent: false),
        AdaptOutcome.nothingToAdapt,
      );
    });

    test('mudanças aplicadas vencem os dois — mesmo sem material', () {
      // Defensivo: se a IA de algum modo emitiu ajuste, mostramos o diff. Não
      // faz sentido dizer "não havia o que adaptar" exibindo o que foi
      // adaptado.
      expect(
        classifyAdaptOutcome(changeCount: 3, hasRewritableContent: true),
        AdaptOutcome.changesApplied,
      );
      expect(
        classifyAdaptOutcome(changeCount: 1, hasRewritableContent: false),
        AdaptOutcome.changesApplied,
      );
    });
  });

  group('o que conta como material reescrevível (mede a ENTRADA)', () {
    bool material({int exp = 0, int proj = 0}) => profileHasRewritableContent(
          experienceCount: exp,
          projectCount: proj,
        );

    test('experiência ou projeto — qualquer um basta', () {
      expect(material(exp: 1), isTrue);
      expect(material(proj: 1), isTrue);
      expect(material(exp: 2, proj: 3), isTrue);
    });

    test('perfil só com formação e skills NÃO tem material', () {
      // Este é exatamente o caso das 106 pessoas: passam no gate (que aceita
      // formação como material) e mesmo assim não têm o que a IA reescreva.
      expect(material(), isFalse);
    });

    test('regressão: julgar pela SAÍDA nunca dispararia o caso vazio', () {
      // A primeira versão deste código checava o currículo ADAPTADO, e a IA
      // escreve o sumário do zero — a saída de um perfil vazio vinha com
      // sumário e educação preenchidos, então "não havia o que adaptar" nunca
      // era alcançado. Verificado no simulador em 02/08 com um perfil de
      // 0 experiências / 0 projetos / resumo inexistente.
      //
      // Este teste fixa a semântica: a contagem vem do PERFIL. Um perfil
      // zerado é `false`, não importa o que a adaptação tenha produzido.
      expect(material(exp: 0, proj: 0), isFalse);
    });
  });

  group('a copy não pode prometer alinhamento sem base', () {
    test('nothingToAdapt NÃO afirma que está alinhado', () {
      final texto = adaptOutcomeTitle(AdaptOutcome.nothingToAdapt);
      expect(texto.toLowerCase(), isNot(contains('alinhado')));
      expect(texto, contains('Adicione'));
    });

    test('alreadyAligned mantém a mensagem tranquilizadora', () {
      expect(
        adaptOutcomeTitle(AdaptOutcome.alreadyAligned),
        contains('já está bem alinhado'),
      );
    });

    test('só o caso sem material oferece caminho pra completar o perfil', () {
      expect(adaptOutcomeWantsProfileCta(AdaptOutcome.nothingToAdapt), isTrue);
      expect(adaptOutcomeWantsProfileCta(AdaptOutcome.alreadyAligned), isFalse);
      expect(adaptOutcomeWantsProfileCta(AdaptOutcome.changesApplied), isFalse);
    });
  });
}
