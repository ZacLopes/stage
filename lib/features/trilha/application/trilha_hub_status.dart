// Hub honesto da trilha (Fase 7 · +10 Tarefa 4).
//
// O painel de progresso do currículo parava de coletar e comemorava "perfil
// forte! 🎉" mesmo com lacunas de verdade (ex.: 0 experiências, 2 skills). Aqui
// a força é DERIVADA das lacunas reais ([ProfileGaps], ponderada por
// monetização) e o painel:
//   - nunca declara "completo/forte" com lacuna aberta;
//   - mostra a força real (0..100);
//   - aponta o PRÓXIMO passo de maior valor, explicando o ganho.
//
// O núcleo [trilhaHubStatusFromGaps] é PURO (só ProfileGaps) → testável (R3).
// [loadTrilhaHubStatus] é o adaptador que lê o perfil FRESCO e deriva o status.

import '../../../services/profile_snapshot_service.dart';
import '../../profile/application/profile_gaps.dart';
import '../../profile/data/repositories/profile_repository_supabase.dart';
import '../../profile/domain/repositories/profile_repository.dart';

/// Estágio honesto do perfil, do mais fraco ao mais forte.
///   building       = ainda faltam campos ESSENCIAIS (Tier 1) — não aparece
///                    direito nas buscas/match; não há o que comemorar.
///   shortlistReady = todos os filtros duros preenchidos (já entra nas listas
///                    das empresas), mas dá pra reforçar (experiência, idiomas…).
///   complete       = nada falta.
enum HubLevel { building, shortlistReady, complete }

/// O que o painel de progresso deve dizer — força real + próximo ganho.
class TrilhaHubStatus {
  final HubLevel level;

  /// Força ponderada por monetização (0..100) = [ProfileGaps.completionPercent].
  final int strengthPercent;

  /// Manchete honesta (sem "forte/completo" quando há lacuna aberta).
  final String title;

  /// Celebração honesta (quando forte) OU o próximo ganho enquadrado por valor.
  final String message;

  /// Rótulo curto da próxima lacuna de maior valor (null quando completo).
  final String? nextStepLabel;

  const TrilhaHubStatus({
    required this.level,
    required this.strengthPercent,
    required this.title,
    required this.message,
    this.nextStepLabel,
  });
}

/// Núcleo PURO: das lacunas reais → o que o painel deve dizer. Sem Supabase.
TrilhaHubStatus trilhaHubStatusFromGaps(ProfileGaps gaps) {
  final pct = gaps.completionPercent;
  final missing = gaps.missing;

  if (missing.isEmpty) {
    return TrilhaHubStatus(
      level: HubLevel.complete,
      strengthPercent: pct,
      title: 'Perfil completo e forte! 🎉',
      message:
          'Você tem tudo que as empresas filtram — e aparece nas listas que a gente envia pra elas.',
    );
  }

  // `missing` já vem ordenado por prioridade de coleta (Tier 1 primeiro), então
  // a primeira é a de maior valor — o "próximo ganho".
  final next = missing.first;
  final gain = _gainFor(next.key);

  if (gaps.isShortlistReady) {
    // Marco real: já bate os filtros duros. Comemora o marco (sem mentir que
    // está "completo") e aponta o próximo reforço.
    return TrilhaHubStatus(
      level: HubLevel.shortlistReady,
      strengthPercent: pct,
      title: 'Seu perfil já aparece pras empresas 👏',
      message: gain,
      nextStepLabel: next.label,
    );
  }

  // Faltam essenciais — nada de "forte". Mostra a força crua e o próximo passo.
  return TrilhaHubStatus(
    level: HubLevel.building,
    strengthPercent: pct,
    title: 'Seu perfil tá $pct% pronto',
    message: gain,
    nextStepLabel: next.label,
  );
}

/// O ganho concreto de preencher cada lacuna — o "por que vale a pena".
/// Enquadra pelo valor pro candidato (aparecer nas buscas/listas, subir o match).
String _gainFor(LacunaKey key) {
  switch (key) {
    case LacunaKey.area:
      return 'Escolha sua área de interesse — sem ela, as empresas não te encontram nas buscas.';
    case LacunaKey.workMode:
      return 'Diga a modalidade (presencial, híbrido ou remoto) pra bater com as vagas certas.';
    case LacunaKey.jobType:
      return 'Diga o tipo de vaga (estágio, trainee…) — as empresas filtram por isso.';
    case LacunaKey.city:
      return 'Informe sua cidade pra aparecer nas buscas por região.';
    case LacunaKey.educationStatus:
      return 'Diga seu momento de estudo (semestre ou formatura) — é filtro na hora da busca.';
    case LacunaKey.skills:
      return 'Chegue a $kMinSkillsForComplete habilidades pra aparecer em mais buscas das empresas.';
    case LacunaKey.experience:
      return 'Adicione 1 experiência e você aparece em mais listas que a gente envia pras empresas.';
    case LacunaKey.languages:
      return 'Coloque o nível dos seus idiomas — isso melhora o seu match.';
    case LacunaKey.summary:
      return 'Um resumo profissional deixa seu perfil mais forte pra quem recruta.';
    case LacunaKey.linkedin:
      return 'Adicione seu LinkedIn pra dar mais contexto às empresas.';
    case LacunaKey.desiredPosition:
      return 'Diga o cargo que você quer — isso afina os seus matches.';
    case LacunaKey.certifications:
      return 'Adicione certificações — elas reforçam o seu perfil.';
    case LacunaKey.awards:
      return 'Adicione conquistas ou prêmios pra se destacar.';
    case LacunaKey.projects:
      return 'Adicione projetos pra mostrar o que já fez na prática.';
    case LacunaKey.availability:
      return 'Diga sua disponibilidade pra facilitar pro recrutador.';
    case LacunaKey.interests:
      return 'Adicione seus interesses pra deixar o perfil mais completo.';
    case LacunaKey.companyStage:
      return 'Diga que tipo de empresa você busca — ajuda a conectar por cultura.';
    case LacunaKey.workEnvironment:
      return 'Conte como você curte o dia a dia — afina o fit com as empresas.';
    case LacunaKey.workStyle:
      return 'Diga seu estilo de trabalho pra melhorar o encaixe cultural.';
  }
}

/// Adaptador: lê o perfil FRESCO (reflete o que a trilha acabou de gravar) e
/// deriva o status honesto. Reusa o mesmo `profileGapsFromData` da trilha.
Future<TrilhaHubStatus> loadTrilhaHubStatus(
  String userId, {
  ProfileRepository? repository,
  ProfileSnapshotService? snapshotService,
}) async {
  final repo = repository ?? ProfileRepositorySupabase();
  final snapSvc = snapshotService ?? ProfileSnapshotService();
  final snapshot = await snapSvc.loadSnapshot(userId);
  final prefs = await repo.getJobPreferences(userId);
  final desired = await repo.getDesiredTitles(userId);
  final gaps = profileGapsFromData(
    snapshot: snapshot,
    prefs: prefs,
    desiredTitles: desired,
  );
  return trilhaHubStatusFromGaps(gaps);
}
