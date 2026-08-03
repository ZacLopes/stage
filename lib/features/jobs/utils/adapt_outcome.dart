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

/// Uma "mudança" cujo antes e depois são iguais não é mudança.
///
/// ## Por que precisa existir (medido em 02/08/2026)
///
/// O modelo emite entradas que documentam **não-mudanças**, com justificativas
/// que denunciam sozinhas: *"Preservado conforme solicitado"*, *"Não há idiomas
/// listados no input"*, *"A experiência não possui bullets para serem
/// adaptados"*. Um caso real trazia `field: "skills"`, razão *"Reordenei as
/// skills para destacar a mais relevante"* — sobre uma lista de UM item, onde
/// reordenar é impossível.
///
/// Em produção: **14 de 129 ajustes reportados (10,9%) eram no-op**, em 5 de 31
/// currículos adaptados. E **12 desses 14 (86%) estavam em respostas que
/// bateram no teto de 6** — o prompt diz "Changes: máximo 6" e o modelo parece
/// ler como meta, completando a cota quando não tem 6 mudanças reais. (Bater no
/// teto não é causa suficiente: 10 dos 13 resultados com 6 ajustes estão
/// limpos. Amostra pequena — 31 CVs —, então é ordem de grandeza.)
///
/// Nada filtrava: o `JSON_SCHEMA_V2` exige `before` e `after`, mas não exige
/// que difiram, e `parsed.changes` ia direto do modelo para o cliente. O
/// cabeçalho então dizia "6 ajustes aplicados" quando 1 ajuste fora aplicado.
///
/// O filtro vive no CLIENTE de propósito, além do servidor: alcança os
/// currículos que já estão em `adapted_resumes` com no-ops gravados.
bool isNoOpChange({required String before, required String after}) =>
    before.trim() == after.trim();

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
