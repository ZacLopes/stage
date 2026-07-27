/// Escolha do documento "Original" no toggle `Adaptado | Original` da preview
/// do CV adaptado (Fase 6 IA/Perfil, fatia F6.0).
///
/// **Por que existe:** a preview resolvia isso inline com
/// `inFilter('source', ['imported','manual']) + order(created_at desc).limit(1)`
/// — recência pura, sem escolha. Três defeitos medidos em prod (24/07):
///
/// 1. **Já errava.** 114 de 1.156 usuários (9,9%) têm mais de um candidato (o
///    máximo é 10). Quem importou um PDF e depois mexeu num CV no editor via
///    o CV do editor como "original" — que não é fonte de nada.
/// 2. **Ia quebrar.** A F4.5 introduziu `source='trail'` (backfill
///    `20260722120000`); a lista literal não o conhecia. Quando a migration
///    rodasse: 91 linhas mudam de source, 78 usuários (6,7%) passariam a ver
///    outro documento e **50 ficariam sem nenhum** candidato.
/// 3. **Ignorava o banco.** `is_current_source` marca a fonte importada ATUAL
///    (no máximo uma por usuário, CHECK amarra a `imported` + `ready`) e não
///    era consultada.
///
/// Tudo aqui é puro (sem Flutter/IO/Supabase) pra ser testável. A tela só
/// busca os candidatos e delega a escolha.
library;

import '../../../data/models/models.dart' show SavedResume, SavedResumeSource;

/// Sources elegíveis a "Original", em ordem de precedência de GRUPO.
///
/// `adapted` está deliberadamente fora: um CV adaptado por IA nunca é o
/// original de outra adaptação — mostrá-lo tornaria o toggle inútil (compararia
/// saída da IA com saída da IA).
///
/// `general` (F4) e `trail` (F4.5) entram no mesmo grupo de `manual`: são
/// documentos de SAÍDA gerados pelo Stage a partir do perfil. Não são fonte
/// importada, mas na ausência dela representam melhor "o CV que eu tinha" do
/// que nada — e o fallback de `ResumeData` da tela já vem da mesma origem
/// (snapshot `profile_*`), então não há divergência de conteúdo.
const List<SavedResumeSource> _kOutputSources = [
  SavedResumeSource.manual,
  SavedResumeSource.trail,
  SavedResumeSource.general,
];

/// Ordena por `(created_at DESC, id DESC)` — mesmo desempate do banco
/// (migration `20260714130000:202`), determinístico com timestamps iguais.
int _byRecency(SavedResume a, SavedResume b) {
  final byDate = b.createdAt.compareTo(a.createdAt);
  return byDate != 0 ? byDate : b.id.compareTo(a.id);
}

/// Escolhe qual documento exibir como "Original" na preview do CV adaptado.
///
/// Precedência, do mais forte pro mais fraco:
///
/// 1. a fonte importada marcada como ATUAL (`is_current_source`);
/// 2. a fonte `imported` mais recente;
/// 3. o documento de saída mais recente (`manual` / `trail` / `general`).
///
/// Retorna `null` quando não há nenhum candidato — a tela então mantém o
/// fallback de `ResumeData` que já existia (nunca falso sucesso, nunca
/// spinner infinito).
SavedResume? resolveOriginalSource(List<SavedResume> resumes) {
  final imported = resumes
      .where((r) => r.source == SavedResumeSource.imported)
      .toList()
    ..sort(_byRecency);

  // (1) fonte atual: o banco garante no máximo uma por usuário
  // (`saved_resumes_one_current_source_per_user`), mas a varredura não assume
  // isso — com duas, a mais recente vence, sem exceção.
  for (final r in imported) {
    if (r.isCurrentSource) return r;
  }

  // (2) importada mais recente
  if (imported.isNotEmpty) return imported.first;

  // (3) documento de saída mais recente
  final outputs = resumes
      .where((r) => _kOutputSources.contains(r.source))
      .toList()
    ..sort(_byRecency);
  if (outputs.isNotEmpty) return outputs.first;

  return null;
}
