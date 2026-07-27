// ProfileEvents — bus singleton pra coordenar invalidação de cache entre
// ViewModels desacoplados quando o user edita o perfil.
//
// Cenário motivador: user adicionou uma skill via ProfileEditorScreen.
// `ProfileEditorViewModel.addSkill` salva no banco e notifica seus próprios
// listeners (widgets). Mas o `UserViewModel._hasProfileData` (que alimenta
// o getter sync `hasResume`) e o `JobsViewModel._cachedProfileText` (que
// alimenta o match score determinístico) ficam stale — não há forma direta
// dum ViewModel descobrir que outro mudou sem acoplamento.
//
// ## Dois canais, não um (27/07)
//
// Nem toda mudança de perfil custa o mesmo para quem escuta:
//
//  • [changes] é BARATO: "os fatos do perfil mudaram, releia sua tela".
//  • [matchInputsChanged] é CARO: invalida caches de match e pode disparar um
//    refetch do FEED INTEIRO de vagas (`JobsViewModel._onProfileChanged` →
//    `_performFetch`, quando o usuário não tem filtros locais salvos).
//
// Antes havia um canal só, então a coleta guiada — que emite a CADA passo
// respondido (correção do Bloqueador A) — pagava o preço caro oito vezes numa
// sessão de oito perguntas. Agora ela emite o barato por passo e o caro UMA vez,
// quando a seção/trilha termina.
//
// `affectsMatch` tem default `true` de propósito: todos os emissores
// preexistentes (editor manual, preferências, import, bridge da gamificação)
// mantêm exatamente o comportamento que tinham. Só quem sabe que está num
// BURST passa `false`.

import 'dart:async';

class ProfileEvents {
  ProfileEvents._();
  static final ProfileEvents instance = ProfileEvents._();

  final _controller = StreamController<void>.broadcast();
  final _matchController = StreamController<void>.broadcast();

  /// Stream que emite quando qualquer mutação no perfil acontece (skill,
  /// experience, education, summary, etc). Subscribers devem invalidar
  /// caches relacionados ao perfil e re-fetch conforme necessário.
  Stream<void> get changes => _controller.stream;

  /// Subconjunto de [changes]: só as mudanças que afetam as ENTRADAS do match.
  ///
  /// Quem faz trabalho caro (recalcular match, refetch de feed) deve escutar
  /// aqui, não em [changes].
  Stream<void> get matchInputsChanged => _matchController.stream;

  /// Emite evento de mudança. Fire-and-forget — não bloqueia o save.
  ///
  /// [affectsMatch] `false` sinaliza uma mudança dentro de um burst (ex.: cada
  /// passo da coleta guiada): a UI relê, mas o match não é recalculado ainda.
  /// Quem passa `false` é responsável por emitir uma vez com `true` ao fim do
  /// burst — senão o match fica velho.
  void notifyChanged({bool affectsMatch = true}) {
    if (!_controller.isClosed) {
      _controller.add(null);
    }
    if (affectsMatch && !_matchController.isClosed) {
      _matchController.add(null);
    }
  }
}
