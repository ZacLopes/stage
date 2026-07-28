/// Quando as seções opcionais do editor de perfil (Prêmios e Disciplinas
/// relevantes) devem aparecer.
///
/// ## O defeito que isto corrige (auditoria de 27/07)
///
/// As duas seções ficavam atrás de um botão genérico — "Adicionar outras
/// seções" — que não diz o nome de nenhuma das duas. Como o padrão do widget é
/// `showOptionalSections: false` e os dois call sites passam false, quem JÁ
/// TINHA prêmio ou disciplina preenchidos não via o próprio dado ao abrir
/// Perfil → Dados: precisava tocar um botão que não prometia mostrá-lo.
///
/// Medido em produção: 18 pessoas com prêmios (33 linhas) e 24 com disciplinas
/// (90 linhas). "Prêmios" já está na build publicada; "Disciplinas relevantes"
/// entra na próxima.
///
/// ## Por que não simplesmente `true` no call site
///
/// Mostrar sempre resolveria o caso de quem tem dado, mas daria a 97% das
/// pessoas duas seções vazias — "(0)" — num editor que já lista sete. A regra
/// abaixo mostra quando há o que mostrar e mantém a tela limpa quando não há.
///
/// [callSiteDefault] — o que a tela pediu (o onboarding pede `false` de
/// propósito, para não inflar a revisão inicial).
/// [userOpened] — a pessoa tocou o botão nesta sessão.
/// [hasOptionalContent] — já existe prêmio ou disciplina no perfil.
bool optionalSectionsVisible({
  required bool callSiteDefault,
  required bool userOpened,
  required bool hasOptionalContent,
}) =>
    callSiteDefault || userOpened || hasOptionalContent;
