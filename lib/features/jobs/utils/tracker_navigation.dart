import '../models/application.dart';

/// Segmento de DESTINO de uma candidatura com um dado status.
///
/// `segmentForStatus` pode, em teoria, devolver `salvas` — mas "Salvas" na aba
/// significa "vaga curtida SEM candidatura", não um status. Uma candidatura que
/// existe nunca mora ali; cai em Enviadas. Este wrapper concentra essa regra num
/// lugar só (antes era um closure duplicado dentro do agrupamento).
///
/// [base] existe para o teste. Hoje nenhum status do mapa real cai em `salvas`,
/// então o guard é inalcançável e afirmá-lo sobre o mapa real seria tautologia
/// — a asserção passaria com o guard deletado (medido por mutação em 27/07).
/// Com a injeção, a conversão vira comportamento verificado em vez de comentário.
ApplicationSegment segmentForApplication(
  ApplicationStatus status, {
  ApplicationSegment Function(ApplicationStatus) base = segmentForStatus,
}) {
  final seg = base(status);
  return seg == ApplicationSegment.salvas ? ApplicationSegment.enviadas : seg;
}

/// Iça para o topo o primeiro item que satisfaz [ehOAlvo]. No-op se ele já
/// estiver no topo ou não estiver na lista.
///
/// Serve à candidatura recém-criada: no agrupamento por segmento as manuais
/// entram DEPOIS de todos os cards de vaga, então num segmento com vários itens
/// a nova nascia fora da área visível — o app levava a pessoa até o segmento
/// certo e ela não via nada de novo ali. A ordem relativa do resto é preservada.
void hoistToTop<T>(List<T> items, bool Function(T) ehOAlvo) {
  final at = items.indexWhere(ehOAlvo);
  if (at > 0) items.insert(0, items.removeAt(at));
}

/// Decide se a aba Candidaturas deve PULAR para outro segmento depois de uma
/// ação do usuário. Devolve o segmento de destino, ou `null` para ficar onde
/// está.
///
/// ## O defeito que isto corrige (C1 do device-test de 24/07)
///
/// `_selectedSegment` só era escrito no toque da pílula. Nenhuma ação
/// reposicionava o usuário, então:
///
///  • adicionar uma candidatura (nasce em Enviadas) deixava a pessoa em
///    "Salvas" lendo *"Nenhuma vaga salva ainda"*;
///  • mudar o status para Entrevista deixava a pessoa em "Enviadas" lendo
///    *"Nenhuma candidatura enviada ainda"*.
///
/// Duas ações seguidas terminando numa tela vazia, com o item a um toque de
/// distância. A pessoa conclui que o app perdeu o que ela acabou de fazer.
///
/// ## Por que NÃO seguir sempre
///
/// Seguir a cada mudança de status atrapalharia quem está processando vários
/// itens em sequência: marcar um de cinco como "Em processo" jogaria a pessoa
/// para outra aba, e ela teria que voltar para tratar o próximo.
///
/// A regra é: **seguir quando ficar sem nada para ver**. Assim o trabalho em
/// lote não é interrompido e ninguém fica preso numa tela vazia.
///
/// A exceção é a CRIAÇÃO: quem acabou de cadastrar uma candidatura quer vê-la,
/// mesmo que o segmento atual ainda tenha outros itens.
///
/// ## E quando a pessoa navega no meio do caminho
///
/// [startedAt] é onde ela estava quando disparou a ação; [current] é onde ela
/// está agora que o request voltou. Se tocou outra pílula durante a espera, a
/// escolha dela vence — pular ali seria arrancá-la de onde acabou de decidir
/// ficar, sem nada na tela explicando o pulo.
ApplicationSegment? nextSegmentAfterAction({
  required ApplicationSegment current,
  required ApplicationSegment destination,
  required bool currentBecomesEmpty,
  required bool isCreation,
  required ApplicationSegment startedAt,
}) {
  // A pessoa se moveu sozinha enquanto o request estava no ar.
  if (current != startedAt) return null;
  // Já estamos no destino: nada a fazer (evita setState inútil).
  if (destination == current) return null;
  if (isCreation) return destination;
  if (currentBecomesEmpty) return destination;
  return null;
}
