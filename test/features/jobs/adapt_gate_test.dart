import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/jobs/utils/adapt_gate.dart';

/// F6 — Bloqueador C do device-test (24/07) + decisão 2 do fundador (26/07).
///
/// O gate ignorava skills; o validador anti-invenção da Edge as exigia. Medido
/// em prod: 745 de 1.530 usuários que passavam tinham 0 skills.
void main() {
  test('o limiar é 3 (decisão do fundador, 26/07)', () {
    expect(kMinSkillsToAdapt, 3);
  });

  group('as três faixas de habilidades', () {
    test('0 skills + material narrativo ⇒ barrado por skills', () {
      expect(
        evaluateAdaptGate(hasNarrativeMaterial: true, skillCount: 0),
        AdaptGateResult.missingSkills,
      );
    });

    test('1 e 2 skills também são barrados (limiar é 3)', () {
      for (final n in [1, 2]) {
        expect(
          evaluateAdaptGate(hasNarrativeMaterial: true, skillCount: n),
          AdaptGateResult.missingSkills,
          reason: '$n skills',
        );
      }
    });

    test('3 skills passa — é o caso provado pelo §11 do device-test', () {
      // O experimento controlado: 0 → 3 skills, nada mais alterado, e a
      // adaptação passou.
      expect(
        evaluateAdaptGate(hasNarrativeMaterial: true, skillCount: 3),
        AdaptGateResult.allowed,
      );
    });

    test('mais de 3 passa', () {
      expect(
        evaluateAdaptGate(hasNarrativeMaterial: true, skillCount: 12),
        AdaptGateResult.allowed,
      );
    });
  });

  group('material narrativo continua sendo pré-requisito', () {
    test('sem material, skills não destravam (o critério antigo não afrouxou)', () {
      expect(
        evaluateAdaptGate(hasNarrativeMaterial: false, skillCount: 12),
        AdaptGateResult.missingMaterial,
      );
    });

    test('sem material E sem skills ⇒ reporta o buraco MAIOR', () {
      expect(
        evaluateAdaptGate(hasNarrativeMaterial: false, skillCount: 0),
        AdaptGateResult.missingMaterial,
      );
    });
  });

  group('códigos de erro', () {
    test('missingMaterial mantém o código histórico profile_incomplete', () {
      // Não quebra a série de analytics que sustentou o diagnóstico dos 63%.
      expect(AdaptGateResult.missingMaterial.errorCode, 'profile_incomplete');
    });

    test('missingSkills usa código novo e distinto', () {
      expect(AdaptGateResult.missingSkills.errorCode, 'missing_skills');
    });

    test('allowed não tem código de erro', () {
      expect(AdaptGateResult.allowed.errorCode, '');
    });
  });

  group('quantas faltam — a copy não trata "1 skill" como "zero"', () {
    test('aritmética', () {
      expect(missingSkillsToAdapt(0), 3);
      expect(missingSkillsToAdapt(1), 2);
      expect(missingSkillsToAdapt(2), 1);
      expect(missingSkillsToAdapt(3), 0);
      expect(missingSkillsToAdapt(10), 0);
    });

    test('quem tem 0 recebe o convite completo', () {
      final msg = missingSkillsMessage(0);
      expect(msg, contains('3 habilidades'));
      expect(msg.contains('Você já tem'), isFalse);
    });

    test('quem tem 1–2 é informado de quantas faltam, no plural certo', () {
      expect(missingSkillsMessage(1), contains('Você já tem 1'));
      expect(missingSkillsMessage(1), contains('mais 2 habilidades'));
      expect(missingSkillsMessage(2), contains('mais 1 habilidade'));
      // singular, não "1 habilidades"
      expect(missingSkillsMessage(2).contains('1 habilidades'), isFalse);
    });

    test('a mensagem nunca é técnica nem vazia', () {
      for (var n = 0; n < 4; n++) {
        final msg = missingSkillsMessage(n);
        expect(msg.trim().isNotEmpty, isTrue, reason: '$n');
        expect(msg.contains('http'), isFalse, reason: '$n');
      }
    });
  });

  group('contagem NÃO confiável não pode bloquear (code-review 27/07)', () {
    // `loadSnapshot` é best-effort POR TABELA: se só a consulta de
    // profile_skills falhar, o snapshot volta com skills: [] e o resto
    // carregado — indistinguível de quem realmente tem zero. Barrar aí
    // mentiria para quem tem 7 habilidades, e sem oferecer retry.
    test('0 skills + contagem não confiável ⇒ LIBERA', () {
      expect(
        evaluateAdaptGate(
          hasNarrativeMaterial: true,
          skillCount: 0,
          skillCountIsReliable: false,
        ),
        AdaptGateResult.allowed,
      );
    });

    test('1-2 skills + contagem não confiável ⇒ LIBERA', () {
      for (final n in [1, 2]) {
        expect(
          evaluateAdaptGate(
            hasNarrativeMaterial: true,
            skillCount: n,
            skillCountIsReliable: false,
          ),
          AdaptGateResult.allowed,
          reason: '$n skills',
        );
      }
    });

    test('falta de MATERIAL ainda bloqueia mesmo com contagem não confiável', () {
      // O material narrativo não depende da consulta de skills — esse ramo
      // continua válido e é o buraco maior.
      expect(
        evaluateAdaptGate(
          hasNarrativeMaterial: false,
          skillCount: 0,
          skillCountIsReliable: false,
        ),
        AdaptGateResult.missingMaterial,
      );
    });

    test('o default é confiável — não afrouxa o caminho normal', () {
      expect(
        evaluateAdaptGate(hasNarrativeMaterial: true, skillCount: 0),
        AdaptGateResult.missingSkills,
      );
    });
  });

  group('a população medida em prod', () {
    test('reproduz a classificação das três faixas do banco', () {
      // 745 com 0 · 72 com 1–2 · 713 com 3+ (query de 26/07, entre os 1.530
      // usuários que passavam no gate antigo).
      final faixas = <int, AdaptGateResult>{
        0: AdaptGateResult.missingSkills,
        1: AdaptGateResult.missingSkills,
        2: AdaptGateResult.missingSkills,
        3: AdaptGateResult.allowed,
        7: AdaptGateResult.allowed,
      };
      faixas.forEach((skills, esperado) {
        expect(
          evaluateAdaptGate(hasNarrativeMaterial: true, skillCount: skills),
          esperado,
          reason: '$skills skills',
        );
      });
    });
  });
}
