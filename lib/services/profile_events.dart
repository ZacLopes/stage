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
// Solução: bus broadcast singleton. ProfileEditorViewModel emite
// `notifyChanged()` após cada mutação. UserViewModel + JobsViewModel
// inscrevem-se no `changes` Stream e invalidam seus caches.

import 'dart:async';

class ProfileEvents {
  ProfileEvents._();
  static final ProfileEvents instance = ProfileEvents._();

  final _controller = StreamController<void>.broadcast();

  /// Stream que emite quando qualquer mutação no perfil acontece (skill,
  /// experience, education, summary, etc). Subscribers devem invalidar
  /// caches relacionados ao perfil e re-fetch conforme necessário.
  Stream<void> get changes => _controller.stream;

  /// Emite evento de mudança. Chamado por `ProfileEditorViewModel` após
  /// cada save bem-sucedido. Fire-and-forget — não bloqueia o save.
  void notifyChanged() {
    if (!_controller.isClosed) {
      _controller.add(null);
    }
  }
}
