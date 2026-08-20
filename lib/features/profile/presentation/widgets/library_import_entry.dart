import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/theme.dart';
import '../../../../services/feature_flags_service.dart';
import '../../../home/home_viewmodel.dart';
import '../../../resume/widgets/import_cv_button.dart';

/// Texto que acompanha a porta de import — MOTOR LEGADO (Assistente OFF).
///
/// Público para o teste poder afirmar sobre ele sem repetir a string, e para
/// deixar explícito que a promessa é parte do contrato desta tela.
///
/// `save_profile_from_json` é **fill-empty por contrato** (migration
/// 20260714130000: seção que já tem dado vira `preserved`). Sem esta frase,
/// devolver o botão trocaria um defeito por uma promessa falsa — a pessoa sobe
/// um CV com o emprego novo e o perfil não muda. O que muda de fato é o arquivo
/// guardado e o texto que alimenta o match.
const String kLibraryImportEntryCopy =
    'Guardo o arquivo e uso no seu match. O que já está preenchido no perfil '
    'não é sobrescrito — só as seções vazias podem ser preenchidas.';

/// Texto quando o motor é o do Assistente.
///
/// A promessa MUDA junto com o motor, e por isso são duas constantes e não uma
/// com interpolação: o motor do Assistente não é fill-empty silencioso — ele
/// mostra a revisão linha a linha ("o CV diz X, você tem Y") e tem desfazer.
/// Prometer "não sobrescrevo nada" ali seria mentir por baixo.
const String kLibraryImportEntryAssistCopy =
    'Você confere o que o Stage encontrou antes de aplicar, item por item — '
    'e pode desfazer depois.';

/// Porta de importar CV em Perfil → Currículos: o botão mais a promessa.
///
/// Extraído de `profile_screen.dart` por um motivo específico: lá dentro ele
/// era intestável. `_ResumesTab` lê `Supabase.instance.client` direto no
/// `build`, então a tela inteira não monta em widget test — e a única coisa que
/// eu conseguia afirmar sobre a porta era lendo o código-fonte como texto.
/// Aqui ela renderiza de verdade, inclusive na tela mais estreita com a fonte
/// de acessibilidade no talo (que foi exatamente o achado P1-10 desta revisão).
///
/// ## Um motor, duas portas (20/08/2026)
///
/// Esta porta continua existindo com o Assistente LIGADO — decisão do fundador,
/// contra o desenho anterior, que a aposentava. Mas ela troca de MOTOR:
///
/// - Assistente OFF → `CvImportService.pickAndImport` (motor legado, fill-empty,
///   sem revisão, sem desfazer). É o comportamento de hoje, intacto.
/// - Assistente ON  → encaminha para o cartão de import do Assistente
///   (`HomeViewModel.requestCvImport` + troca de aba), o MESMO caminho que o
///   card "Fonte importada" usa.
///
/// Por que não deixar os dois motores convivendo: o trigger
/// `zzz_mark_latest_legacy_source` **rejeita** um insert do motor legado assim
/// que existe uma fonte canônica na conta (`legacy_import_blocked_by_canonical_source`).
/// Não é intermitente — é toda vez, para sempre, naquela conta. E o PDF já subiu
/// para o Storage antes do erro, virando órfão. Ou seja: manter os dois motores
/// é que seria o defeito, não manter as duas portas.
///
/// ⚠️ Quem montar este widget: **fora** de qualquer `Consumer<ProfileViewModel>`.
/// O import dispara `loadSavedResumes()`, que liga `isLoading` antes do await de
/// rede; se o Consumer trocar a subárvore por um spinner, este widget sofre
/// dispose no meio do próprio fluxo e o `raw_text` do CV nunca é gravado. O
/// teste `library_import_entry_test.dart` trava isso.
class LibraryImportEntry extends StatelessWidget {
  /// Chamado com o id do currículo novo, quando o import dá certo.
  /// Só dispara no motor legado — no motor do Assistente, quem avisa a
  /// biblioteca é o próprio Assistente.
  final void Function(String newResumeId)? onImported;

  const LibraryImportEntry({super.key, this.onImported});

  /// O Assistente está ligado para esta pessoa?
  ///
  /// Lido aqui e não recebido por parâmetro para o widget continuar montável
  /// isolado no teste: sem sessão, `currentUser` é null e o serviço responde
  /// false (failure-safe), caindo no motor legado.
  bool _assistOn() {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      return FeatureFlagsService.instance.isTrilhaAssistEnabledForUser(uid);
    } catch (_) {
      return false;
    }
  }

  /// Encaminha para o cartão de import do Assistente.
  ///
  /// Mesmo par de chamadas que `imported_source_card.dart::_startImport` usa —
  /// a `ResumeTab` consome `pendingCvImport` num post-frame e empurra o cartão.
  void _forwardToAssistant(BuildContext context) {
    try {
      final home = context.read<HomeViewModel>();
      home.requestCvImport();
      home.requestTabChange(HomeTabs.resume);
    } catch (_) {
      // Sem HomeViewModel (teste isolado): no-op.
    }
  }

  @override
  Widget build(BuildContext context) {
    final assistOn = _assistOn();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ImportCvButton(
            variant: ImportCvVariant.secondary,
            analyticsSource: 'profile_resumes',
            onTapOverride: assistOn ? () => _forwardToAssistant(context) : null,
            onImported: (id) {
              if (id == null) return;
              onImported?.call(id);
            },
          ),
          const SizedBox(height: 8),
          Text(
            assistOn ? kLibraryImportEntryAssistCopy : kLibraryImportEntryCopy,
            style: AppTextStyles.bodySm.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}
