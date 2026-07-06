import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/services/ai_service.dart';

/// Fase 7 Onda 1 — Tarefa 1 (R3): a resolução da versão de prompt do cache de
/// match deixou de cair num fallback 'v4' hardcoded (a maior coorte MORTA de
/// `match_analyses`) quando o `app_config` não pode ser lido. Sem versão de
/// confiança → `null` → `fetchCachedMatches` não hidrata nada e o
/// determinístico assume. Este é o núcleo puro dessa decisão.
void main() {
  group('AIService.resolveMatchPromptVersionFromConfig', () {
    test('valor válido do app_config vira a versão de cache', () {
      expect(AIService.resolveMatchPromptVersionFromConfig('v13'), 'v13');
    });

    test('faz trim de espaços em volta', () {
      expect(AIService.resolveMatchPromptVersionFromConfig('  v13  '), 'v13');
    });

    test('null (app_config ilegível: rede/RLS) → null, não hidrata', () {
      expect(AIService.resolveMatchPromptVersionFromConfig(null), isNull);
    });

    test('vazio / só espaços → null', () {
      expect(AIService.resolveMatchPromptVersionFromConfig(''), isNull);
      expect(AIService.resolveMatchPromptVersionFromConfig('   '), isNull);
    });

    test('regressão: nunca devolve a versão morta hardcoded v4', () {
      // Antes, qualquer falha de rede resolvia p/ 'v4' e o app hidratava
      // ~18k scores de uma versão que o servidor não grava mais.
      expect(AIService.resolveMatchPromptVersionFromConfig(null), isNot('v4'));
      expect(AIService.resolveMatchPromptVersionFromConfig(''), isNot('v4'));
    });
  });
}
