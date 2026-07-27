import '../../data/models/models.dart';

/// Prefixo histórico do título dos CVs gerados pela trilha do Stage.
///
/// Fonte ÚNICA da verdade — `ResumeViewModel.kTrailResumeBaseTitle` aponta
/// para cá. Não duplicar o literal.
const String kTrailResumeTitlePrefix = 'Currículo Stage';

/// True quando o CV salvo é um documento gerado pela trilha — o único tipo que
/// o usuário pode editar/regerar na biblioteca.
///
/// ## Por que o predicado é tolerante
///
/// A F4.5 trocou "adivinhar pelo título" por um tipo estrutural
/// (`SavedResumeSource.trail`), que é o desenho certo. Mas o valor `'trail'` só
/// passa a existir no banco depois da migration `20260722120000`, e a ordem de
/// release decidida em 26/07 (caminho A) é **app primeiro, migration depois**.
///
/// No intervalo, nenhuma linha em produção é `trail` e o predicado estrutural
/// sozinho é **constante-falso**: os documentos que hoje são editáveis
/// perderiam "Editar texto", "Regerar com IA" e "Exportar PDF" — sem erro e sem
/// aviso, e sem flag para desligar. Medido em prod (26/07): **91 documentos de
/// 87 usuários**.
///
/// ## Por que o ramo legado é restrito a `manual`
///
/// Medido em prod: o prefixo `'Currículo Stage'` existe **exclusivamente** em
/// linhas `source='manual'` (91 linhas; zero em `imported`, `adapted`). Limitar
/// o OR a `manual` garante que um documento `general` ou `adapted` que nascesse
/// com esse prefixo **não** vire editável por acidente.
///
/// ## Dívida datada — gatilho de remoção acordado
///
/// O 2º ramo é temporário, mas **a sequência importa** e tem três degraus,
/// não dois (corrigido em 27/07 após o code-review):
///
/// 1. **Hoje:** o writer (`phase_completion_widget.dart`) grava `manual`, e
///    NÃO `trail` — porque o CHECK em produção ainda recusa `'trail'` e a
///    ordem de release é app-antes-de-migration. Logo, linhas novas continuam
///    nascendo `manual` + prefixo, e o 2º ramo é o ÚNICO que as mantém
///    editáveis. Remover o ramo agora quebraria todo CV de trilha novo.
/// 2. **Depois que a `20260721120000` estiver em produção:** trocar o writer
///    para `SavedResumeSource.trail`. A partir daí, linhas novas nascem
///    tipadas e só o legado depende do prefixo.
/// 3. **Depois que a `20260722120000` (backfill) rodar:** aí sim
///    `select count(*) from saved_resumes where source = 'trail'` estabiliza
///    cobrindo as 91 linhas legadas + as novas, e o 2º ramo pode sair.
///
/// O teste `manual + prefixo → editável` é o alarme: ele só pode ficar
/// vermelho depois do degrau 3.
bool isTrailResume({
  required SavedResumeSource source,
  required String title,
}) {
  // Tipo estrutural: a verdade a partir do backfill.
  if (source == SavedResumeSource.trail) return true;
  // Ponte legada: enquanto o backfill não rodou, `trail` chega como `manual`
  // (fallback de `SavedResumeSource.fromDb`) e só o título distingue.
  return source == SavedResumeSource.manual &&
      title.startsWith(kTrailResumeTitlePrefix);
}
