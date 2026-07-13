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

  /// Escolha única COMPACTA: renderiza como chips (toque submete) em vez de
  /// tiles de largura cheia. Bom pra escalas curtas (ex.: nível de idioma).
  final bool compact;

  const ChoiceInput({
    required this.options,
    this.multi = false,
    this.maxSelections,
    this.compact = false,
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

  /// Teto de linhas do campo. Se null, DERIVA do [maxLength] — campo que aceita
  /// mais texto abre mais alto ("personalizado por tópico"), com piso no
  /// [minLines] e teto em 14 (não vira scroll gigante no fio). Antes era 5
  /// cravado, o que espremia textões numa caixinha rolável (device-test).
  final int? maxLines;

  /// Pode ser pulado vazio (vira "Pular"). Bom pra campos de enriquecimento
  /// (ex.: link do projeto) — reduz fricção.
  final bool optional;

  const GuidedTextInput({
    required this.example,
    this.hint,
    this.maxLength = 280,
    this.minLines = 2,
    this.maxLines,
    this.optional = false,
  });

  /// Linhas máximas efetivas do campo de edição (nunca menor que [minLines]).
  int get effectiveMaxLines =>
      maxLines ?? (maxLength / 36).ceil().clamp(minLines, 14);
}

/// Seletor inline de mês + ano. Garante uma data real (1º dia do mês escolhido)
/// — usado quando o campo exige DateTime (ex.: início de experiência).
@immutable
class MonthYearInput extends StepInput {
  /// Quantos anos pra trás oferecer (default 15).
  final int yearsBack;

  /// Pode ser pulado sem escolher (vira "Pular"). Bom pra data opcional.
  final bool optional;

  const MonthYearInput({this.yearsBack = 15, this.optional = false});
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

  /// Mínimo de seleções pra liberar o "Continuar" (0 = sem mínimo). Quando > 0,
  /// obriga o usuário a escolher pelo menos esse tanto (ex.: 3 skills). O botão
  /// mostra quantas faltam.
  final int minSelections;

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
    this.minSelections = 0,
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

  /// Mínimo de seleções pra liberar o "Continuar" (0 = opcional, pode pular).
  final int minSelections;

  const AsyncSuggestInput({
    required this.load,
    this.catalog = const [],
    this.loadingHint = 'Procurando sugestões pra você…',
    this.minSelections = 0,
  });
}

/// Item de um typeahead assíncrono (cidade IBGE / instituição do catálogo).
/// `label` é o que aparece; `value` é o payload ESTRUTURADO (`Cidade|UF` ou
/// `institution_id|Nome`) decodificado no write-back — assim a coleta canoniza
/// o campo de FILTRO (sem 'sampa'/typo entrando cru).
@immutable
class PickSuggestion {
  final String label;
  final String value;
  const PickSuggestion({required this.label, required this.value});
}

/// Seleção ÚNICA com busca ASSÍNCRONA (typeahead real): a cada tecla chama
/// [search] (debounced na UI) contra uma fonte externa (catálogo IBGE de
/// cidades; catálogo de instituições no Supabase). Tocar num resultado submete
/// na hora. [allowFreeText] permite adicionar o texto digitado quando não há
/// match (nunca trava). Resposta = [StepAnswer.pick] (value = payload estruturado).
@immutable
class AsyncPickInput extends StepInput {
  final Future<List<PickSuggestion>> Function(String query) search;
  final String searchHint;
  final bool allowFreeText;
  final String loadingHint;

  const AsyncPickInput({
    required this.search,
    this.searchHint = 'Buscar…',
    this.allowFreeText = true,
    this.loadingHint = 'Buscando…',
  });
}

/// Um TIPO de experiência oferecido no seletor (tile rico: ícone + rótulo +
/// subtítulo). `id` é o `kind` canônico gravado (estagio, voluntariado…).
@immutable
class ExperienceTypeOption {
  final String id;
  final String label;
  final String subtitle;

  /// Nome do ícone material (resolvido na UI — domínio livre de Flutter).
  final String icon;

  const ExperienceTypeOption({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.icon,
  });
}

/// Seletor de TIPOS de experiência (abertura da seção Experiência): tiles ricos
/// em MULTISSELEÇÃO com CONTADOR (tocar de novo = +1 do mesmo tipo, ex.: 2
/// estágios), um "Outro" pra tipos fora da lista, e uma saída honesta ("ainda
/// não tenho"). A resposta é a lista ORDENADA de `kind`s escolhidos, com
/// repetição = contagem (ex.: ['estagio','estagio','voluntariado']); 'outro'
/// entra como 'outro'. Vazio = pulou (sem experiência). O `expand` do passo lê
/// essa lista e enfileira o bloco de perguntas de cada experiência, por tipo.
@immutable
class ExperienceTypeInput extends StepInput {
  final List<ExperienceTypeOption> types;

  /// Rótulo da saída "ainda não tenho experiência" (submete lista vazia).
  final String skipLabel;

  const ExperienceTypeInput({
    required this.types,
    this.skipLabel = 'Ainda não tenho experiência',
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

  /// Resumo DINÂMICO ao fechar um item (ex.: a IA mostra a experiência que
  /// acabou de anotar). Recebe o histórico de respostas (todas até aqui,
  /// incluindo a deste passo) e compõe o texto a partir das do próprio item —
  /// tem prioridade sobre [acknowledgement]; null cai no estático. Puro (sem
  /// Flutter), então funciona nas duas superfícies (chat embutido e pushado).
  final String? Function(List<StepAnswer> history)? recap;

  /// Passos DINÂMICOS: dada a resposta deste passo, devolve passos a inserir
  /// logo em seguida na fila. É o que permite loops (ex.: "adicionar outra
  /// experiência?" → injeta mais um item) e ramos condicionais. Nulo = sem
  /// expansão.
  final List<ConversationStep> Function(StepAnswer answer)? expand;

  /// Pode-se VOLTAR pra refazer este passo com segurança? True por padrão
  /// (passos idempotentes/de buffer: re-responder corrige). False nos passos
  /// cujo write-back INSERE linha (exp.ofazia / project.link / cert.date /
  /// award.date / idiomas): voltar e re-responder duplicaria — o "voltar" para neles.
  final bool reversible;

  const ConversationStep({
    required this.id,
    required this.aiMessages,
    required this.input,
    this.acknowledgement,
    this.expand,
    this.reversible = true,
    this.recap,
  });

  /// Conveniência: passo com uma única bolha de fala.
  ConversationStep.single({
    required String id,
    required String aiMessage,
    required StepInput input,
    String? acknowledgement,
    List<ConversationStep> Function(StepAnswer answer)? expand,
    bool reversible = true,
    String? Function(List<StepAnswer> history)? recap,
  }) : this(
          id: id,
          aiMessages: [aiMessage],
          input: input,
          acknowledgement: acknowledgement,
          expand: expand,
          reversible: reversible,
          recap: recap,
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

  /// Resposta de seleção única com payload ESTRUTURADO (typeahead async).
  /// `value` carrega 'Cidade|UF' ou 'institution_id|Nome'; `displayText` = label.
  factory StepAnswer.pick(String stepId,
      {required String label, required String value}) {
    return StepAnswer(stepId: stepId, value: value, displayText: label);
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
