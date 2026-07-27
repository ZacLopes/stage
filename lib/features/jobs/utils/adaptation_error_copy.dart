import '../../../services/ai_service.dart' show ResumeAdaptationException;
import '../../../core/utils/safe_error_text.dart';

/// Copy e affordances do estado de erro da adaptação de currículo.
///
/// Função pura — o widget só renderiza o que sai daqui. Existe por três
/// defeitos medidos no device-test de 24/07 (§9, A1–A3):
///
/// - **A3 (vazamento):** a sheet renderiza `message` LITERALMENTE. O client
///   punha `e.toString()` ali, então a tela exibiu
///   `ClientException: ... uri=https://<project>.supabase.co/functions/v1/...`
///   — jargão em inglês e a URL/ref do projeto Supabase na UI. Corrigido na
///   origem (`ai_service.dart`), e aqui existe uma **segunda barreira**: nenhum
///   texto vindo do servidor chega à tela se parecer técnico.
/// - **A1 (affordance falsa):** "Tente novamente" em falha determinística.
/// - **A2:** a mensagem não dizia o que fazer.
///
/// A copy de `adaptation_rejected` é do CLIENT de propósito. O servidor manda
/// `detail: 'A adaptação não passou na verificação de integridade. Tente
/// novamente.'` (`v2.ts:2023`) — jargão, e mudar isso lá dentro exigiria tocar
/// a Edge do adapt, coberta por R5 (cujo `golden_set/` está vazio). A UI é dona
/// da própria linguagem.
class AdaptationErrorCopy {
  final String title;
  final String message;

  /// Retry só é oferecido quando ele pode realmente resolver. Numa falha
  /// determinística, um botão "Tentar de novo" é promessa falsa.
  final bool canRetry;

  /// CTA "Importar CV em PDF".
  final bool showImportCv;

  /// CTA que leva ao editor de habilidades do perfil.
  final bool showAddSkills;

  const AdaptationErrorCopy({
    required this.title,
    required this.message,
    required this.canRetry,
    this.showImportCv = false,
    this.showAddSkills = false,
  });
}

/// True quando o texto do servidor é seguro para renderizar direto ao usuário.
///
/// Delega para [SafeErrorText], que é a política ÚNICA do app — antes esta
/// regra vivia só aqui e o mesmo vazamento reapareceu no export do Currículo
/// geral (code-review de 27/07). Uma regra, um lugar.
bool isPresentableDetail(String? detail) => SafeErrorText.isPresentable(detail);

/// Resolve título, mensagem e botões a partir do erro capturado pela sheet.
AdaptationErrorCopy resolveAdaptationErrorCopy(Object? error) {
  final code = error is ResumeAdaptationException ? error.code : 'unknown';
  final detail = error is ResumeAdaptationException ? error.message : null;

  switch (code) {
    case 'profile_incomplete':
      return AdaptationErrorCopy(
        title: 'Complete seu perfil primeiro',
        message: isPresentableDetail(detail)
            ? detail!
            : 'Pra eu adaptar seu currículo, preciso de pelo menos uma '
                'experiência, projeto ou formação completa — ou um CV '
                'importado em PDF.',
        // Determinístico: tentar de novo com o mesmo perfil dá o mesmo "não".
        canRetry: false,
        showImportCv: true,
        showAddSkills: false,
      );

    case 'missing_skills':
      // F6: o gate passou a exigir habilidades no perfil. É determinístico —
      // sem habilidades o validador anti-invenção rejeita SEMPRE.
      return AdaptationErrorCopy(
        title: 'Adicione suas habilidades',
        message: isPresentableDetail(detail)
            ? detail!
            : 'Pra adaptar seu currículo pra uma vaga, preciso saber o que '
                'você sabe fazer. Adicione suas habilidades ao perfil e eu '
                'cuido do resto.',
        canRetry: false,
        showImportCv: false,
        showAddSkills: true,
      );

    case 'rate_limited':
      return AdaptationErrorCopy(
        title: 'Limite diário atingido',
        message: isPresentableDetail(detail)
            ? detail!
            : 'Você atingiu o limite diário de adaptações. Tente amanhã.',
        canRetry: false,
      );

    case 'adaptation_rejected':
      // Copy do client, ignorando o `detail` do servidor de propósito.
      return const AdaptationErrorCopy(
        title: 'Descartei essa versão',
        message:
            'A IA sugeriu habilidades que não estão no seu perfil, e eu '
            'prefiro não inventar nada no seu currículo. Tentar de novo '
            'costuma resolver — se insistir, adicione essas habilidades ao '
            'seu perfil primeiro.',
        canRetry: true,
        showAddSkills: true,
      );

    case 'job_not_found':
      return const AdaptationErrorCopy(
        title: 'Vaga indisponível',
        message: 'Esta vaga não está mais disponível.',
        canRetry: false,
      );

    case 'unauthorized':
      return const AdaptationErrorCopy(
        title: 'Sessão expirada',
        message: 'Sua sessão expirou. Entre novamente para continuar.',
        canRetry: false,
      );

    case 'network':
      return const AdaptationErrorCopy(
        title: 'Sem conexão com o servidor',
        message: 'Não consegui falar com o servidor agora. Verifique sua '
            'conexão e tente de novo.',
        canRetry: true,
      );

    case 'timeout':
      return const AdaptationErrorCopy(
        title: 'Demorou demais',
        message: 'A adaptação passou do tempo. Tente de novo.',
        canRetry: true,
      );

    default:
      return AdaptationErrorCopy(
        title: 'Algo deu errado',
        message: isPresentableDetail(detail)
            ? detail!
            : 'Não consegui adaptar seu currículo agora. Tente de novo em '
                'instantes.',
        canRetry: true,
      );
  }
}
