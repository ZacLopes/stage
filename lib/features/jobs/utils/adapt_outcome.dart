/// Como interpretar uma adaptação que voltou com ZERO mudanças.
///
/// ## Por que existe (achado do device-test de 02/08)
///
/// A tela tratava `changes.isEmpty` como uma coisa só e dizia:
///
///   "Seu currículo já está bem alinhado com essa vaga. Nenhum ajuste
///    necessário."
///
/// Só que zero mudanças tem DUAS causas opostas:
///
/// 1. **Já estava alinhado** — a pessoa tem experiências/projetos e a IA
///    olhou, comparou com a vaga e concluiu que não valia mexer. A mensagem
///    acima é verdadeira e tranquilizadora, e deve continuar existindo.
///
/// 2. **Não havia o que adaptar** — a pessoa não tem experiência nem projeto
///    nem resumo. O pipeline v2 é anti-invenção por desenho: ele só
///    reorganiza e reformula o que já foi cadastrado (é o que impede o bug de
///    "inventar emprego pra quem nunca teve", `13e073d`). Sem material
///    narrativo não existe bullet para reescrever, então devolver zero é a
///    ÚNICA resposta honesta que ele poderia dar — e a tela então afirmava
///    que um currículo praticamente vazio "está bem alinhado com a vaga".
///
/// O caso 2 não é raro nem teórico. Medido em produção em 02/08/2026:
/// **106 pessoas** — 14,5% das 729 que passam no gate do adapt — têm 3+ skills
/// e ZERO experiências e ZERO projetos. Todas recebiam a mensagem do caso 1.
///
/// Por que elas passam pelo gate: `evaluateAdaptGate` exige material narrativo,
/// e `canAdaptCv` conta **formação** como material. Formação é suficiente para
/// montar um currículo, mas não dá nada para a IA reescrever mirando na vaga.
/// O gate está certo; quem estava errado era a leitura do resultado.
///
/// É a mesma classe de defeito do falso positivo C/C++/C# e do consentimento
/// que diz "Não autorizado" com o dado já enviado: **resposta confiante e
/// errada**, silenciosa, que a pessoa não tem como detectar — e aqui ela segue
/// para a candidatura confiando que o currículo está adequado.
library;

/// Desfecho de uma adaptação, do ponto de vista do que dizer à pessoa.
enum AdaptOutcome {
  /// A IA aplicou pelo menos um ajuste. Mostra o diff.
  changesApplied,

  /// Havia material reescrevível e a IA concluiu que não valia mexer.
  alreadyAligned,

  /// Não havia material reescrevível — não existia o que adaptar.
  nothingToAdapt,
}

/// Classifica o desfecho. Função pura — sem Provider, sem rede.
///
/// [hasRewritableContent] deve ser calculado a partir do currículo ADAPTADO
/// (ver [resumeHasRewritableContent]), não do perfil: é ele que representa o
/// que o pipeline de fato teve em mãos.
AdaptOutcome classifyAdaptOutcome({
  required int changeCount,
  required bool hasRewritableContent,
}) {
  if (changeCount > 0) return AdaptOutcome.changesApplied;
  return hasRewritableContent
      ? AdaptOutcome.alreadyAligned
      : AdaptOutcome.nothingToAdapt;
}

/// O que a pessoa trouxe e a IA pode reescrever mirando numa vaga.
///
/// ⚠️ **Mede a ENTRADA (o perfil), nunca a SAÍDA (o currículo adaptado).**
/// Esta distinção derrubou a primeira versão deste código, em teste no
/// simulador em 02/08: eu checava `adapted.resumeData` e a condição nunca
/// disparava. O motivo é que **a IA escreve o SUMÁRIO do zero** — o perfil não
/// tem sequer um campo de resumo (`ProfileEditorViewModel` não expõe nenhum).
/// Então a saída SEMPRE tem conteúdo, mesmo partindo de um perfil vazio, e
/// julgar por ela é circular: pergunta "havia o que adaptar?" olhando para o
/// que a adaptação produziu.
///
/// Só experiência e projeto contam. Deliberadamente fora:
///
/// - **formação**: instituição, curso e semestre são fatos, não narrativa;
///   reescrevê-los seria inventar. É exatamente o que faz alguém passar no
///   gate (`canAdaptCv` aceita formação) e mesmo assim não ter o que adaptar;
/// - **habilidades**: viram lista no PDF, não texto reescrito — e o gate já
///   exige 3, então nunca discriminam os dois casos;
/// - **idiomas, prêmios, cursos, interesses**: entradas curtas e factuais.
bool profileHasRewritableContent({
  required int experienceCount,
  required int projectCount,
}) {
  return experienceCount > 0 || projectCount > 0;
}

/// Título mostrado quando a adaptação volta sem mudanças.
String adaptOutcomeTitle(AdaptOutcome outcome) => switch (outcome) {
      AdaptOutcome.changesApplied => '',
      AdaptOutcome.alreadyAligned =>
        'Seu currículo já está bem alinhado com essa vaga. '
            'Nenhum ajuste necessário.',
      // Não promete alinhamento, porque não há base para prometer; nomeia o
      // que falta e para onde ir. O "eu reescrevo mirando nesta vaga" repete
      // a proposta de valor no ponto exato em que ela não pôde ser cumprida.
      AdaptOutcome.nothingToAdapt =>
        'Não há experiências nem projetos no seu perfil pra eu adaptar. '
            'Adicione pelo menos um e eu reescrevo mirando nesta vaga.',
    };

/// Se a UI deve oferecer um caminho para completar o perfil.
bool adaptOutcomeWantsProfileCta(AdaptOutcome outcome) =>
    outcome == AdaptOutcome.nothingToAdapt;
