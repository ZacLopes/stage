// Modelo de domínio da Trilha de Coleta conversacional (PLANO-FASE-6 T6.3).
//
// A trilha é uma CONVERSA: a IA "fala" (uma ou mais bolhas), apresenta um
// WIDGET de entrada inline, o usuário responde, a IA reage e puxa o próximo
// passo. Este arquivo define o vocabulário desses passos — puro, sem Flutter,
// pra ser testável e reaproveitável pelo motor [ConversationController] e pela
// camada de UI.
//
// Os tipos de entrada ([StepInput]) mapeiam, na camada de apresentação, pros
// widgets inline (chips, texto guiado, etc.) — reaproveitando o design system.

import 'package:flutter/foundation.dart';

/// Uma opção de escolha (chip / tile). `icon` é opcional (nome do ícone
/// material resolvido na UI — mantemos o domínio livre de Flutter).
@immutable
class StepOption {
  final String id;
  final String label;

  /// Subtítulo opcional (ex.: "Pra quem ainda tá na faculdade").
  final String? subtitle;

  const StepOption({required this.id, required this.label, this.subtitle});

  @override
  bool operator ==(Object other) =>
      other is StepOption && other.id == id && other.label == label;

  @override
  int get hashCode => Object.hash(id, label);
}

/// O que um passo pede ao usuário. Variantes selam o conjunto — a UI faz um
/// switch exaustivo pra renderizar o widget inline certo.
@immutable
sealed class StepInput {
  const StepInput();
}

/// Escolha em chips/tiles. `multi=false` → escolha única (avança ao tocar).
/// `multi=true` → multisseleção com botão de confirmar; `maxSelections` limita.
@immutable
class ChoiceInput extends StepInput {
  final List<StepOption> options;
  final bool multi;
  final int? maxSelections;

  const ChoiceInput({
    required this.options,
    this.multi = false,
    this.maxSelections,
  });
}

/// Texto livre GUIADO — sempre com exemplo concreto pra matar a "página em
/// branco". A IA depois organiza (ex.: vira bullets). `example` aparece como
/// placeholder/dica; `maxLength` limita pra forçar concisão.
@immutable
class GuidedTextInput extends StepInput {
  final String? hint;
  final String example;
  final int maxLength;
  final int minLines;

  const GuidedTextInput({
    required this.example,
    this.hint,
    this.maxLength = 280,
    this.minLines = 2,
  });
}

/// Seletor inline de mês + ano. Garante uma data real (1º dia do mês escolhido)
/// — usado quando o campo exige DateTime (ex.: início de experiência).
@immutable
class MonthYearInput extends StepInput {
  /// Quantos anos pra trás oferecer (default 15).
  final int yearsBack;

  const MonthYearInput({this.yearsBack = 15});
}

/// Multisseleção "meio-termo" (skills/áreas/etc.): chips SUGERIDOS (reconhecer,
/// rápido) + BUSCA no catálogo (typeahead, ajuda a completar) + ADICIONAR LIVRE
/// (autonomia — nunca trava). O backend canoniza o texto livre (skill_aliases),
/// então o usuário escreve do jeito dele. Resposta = StepAnswer.choice (cada
/// item vira StepOption id=label=nome). Reutilizável entre passos.
@immutable
class SuggestPickInput extends StepInput {
  /// Chips iniciais (reconhecimento). Podem ser personalizados (ex.: pela área).
  final List<String> suggestions;

  /// Fonte do typeahead (ex.: skills_catalog canônicas). Filtrada localmente.
  final List<String> catalog;

  /// Permite adicionar um termo fora do catálogo (texto livre). True por padrão.
  final bool allowFreeText;

  /// Limite opcional de seleções (null = sem limite).
  final int? maxSelections;

  /// Placeholder do campo de busca.
  final String searchHint;

  /// Permite confirmar com 0 selecionados (ex.: passo de sugestão da IA, que é
  /// opcional → vira "Pular"). Default false (skills exige ao menos 1).
  final bool allowEmpty;

  /// Carrega as sugestões de forma assíncrona quando o passo é exibido (ex.:
  /// skills personalizadas pela ÁREA escolhida na própria trilha, que só existe
  /// DEPOIS do passo de área). Se presente, o resultado substitui [suggestions]
  /// — que vira placeholder até carregar. Failure-safe (erro mantém o estático).
  final Future<List<String>> Function()? suggestionsLoader;

  const SuggestPickInput({
    required this.suggestions,
    this.catalog = const [],
    this.allowFreeText = true,
    this.maxSelections,
    this.searchHint = 'Buscar ou adicionar…',
    this.allowEmpty = false,
    this.suggestionsLoader,
  });
}

/// Passo cujas sugestões são CARREGADAS de forma assíncrona (ex.: a IA sugere
/// skills a partir do perfil + do que a pessoa marcou). A UI mostra "carregando",
/// chama [load] uma vez e renderiza as sugestões como um picker (opcional →
/// pode pular). [load] é failure-safe: lista vazia ⇒ "nada a sugerir". Domínio
/// sem Flutter: só uma função que devolve nomes.
@immutable
class AsyncSuggestInput extends StepInput {
  final Future<List<String>> Function() load;
  final List<String> catalog;
  final String loadingHint;

  const AsyncSuggestInput({
    required this.load,
    this.catalog = const [],
    this.loadingHint = 'Procurando sugestões pra você…',
  });
}

/// Um passo da conversa: a(s) fala(s) da IA + a entrada esperada + uma reação
/// opcional da IA após responder (o "Massa!" que dá calor de conversa).
@immutable
class ConversationStep {
  /// Identificador estável — usado pra write-back (rota pro profile_*) e pra
  /// retomada (profile_guided_progress).
  final String id;

  /// O que a IA fala antes da entrada. Pode ser mais de uma bolha em sequência.
  final List<String> aiMessages;

  /// O widget de entrada inline.
  final StepInput input;

  /// Reação curta da IA depois que o usuário responde (opcional). Quando nula,
  /// a IA segue direto pro próximo passo sem comentar.
  final String? acknowledgement;

  /// Passos DINÂMICOS: dada a resposta deste passo, devolve passos a inserir
  /// logo em seguida na fila. É o que permite loops (ex.: "adicionar outra
  /// experiência?" → injeta mais um item) e ramos condicionais. Nulo = sem
  /// expansão.
  final List<ConversationStep> Function(StepAnswer answer)? expand;

  const ConversationStep({
    required this.id,
    required this.aiMessages,
    required this.input,
    this.acknowledgement,
    this.expand,
  });

  /// Conveniência: passo com uma única bolha de fala.
  ConversationStep.single({
    required String id,
    required String aiMessage,
    required StepInput input,
    String? acknowledgement,
    List<ConversationStep> Function(StepAnswer answer)? expand,
  }) : this(
          id: id,
          aiMessages: [aiMessage],
          input: input,
          acknowledgement: acknowledgement,
          expand: expand,
        );
}

/// A resposta do usuário a um passo. `value` carrega o dado bruto (`List<String>`
/// pra escolha, `String` pra texto) pro write-back; `displayText` é como a
/// resposta aparece na bolha do usuário no fio da conversa.
@immutable
class StepAnswer {
  final String stepId;
  final Object value;
  final String displayText;

  const StepAnswer({
    required this.stepId,
    required this.value,
    required this.displayText,
  });

  /// Resposta de escolha (1+ opções).
  factory StepAnswer.choice(String stepId, List<StepOption> selected) {
    return StepAnswer(
      stepId: stepId,
      value: selected.map((o) => o.id).toList(),
      displayText: selected.map((o) => o.label).join(', '),
    );
  }

  /// Resposta de texto guiado.
  factory StepAnswer.text(String stepId, String text) {
    final t = text.trim();
    return StepAnswer(stepId: stepId, value: t, displayText: t);
  }

  /// Resposta de mês/ano. `value` = 'YYYY-MM' (1º dia do mês na gravação).
  factory StepAnswer.monthYear(String stepId, int year, int month) {
    final mm = month.toString().padLeft(2, '0');
    return StepAnswer(
      stepId: stepId,
      value: '$year-$mm',
      displayText: '$mm/$year',
    );
  }
}
