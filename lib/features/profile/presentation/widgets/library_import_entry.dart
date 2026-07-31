import 'package:flutter/material.dart';

import '../../../../core/theme/theme.dart';
import '../../../resume/widgets/import_cv_button.dart';

/// Texto que acompanha a porta de import.
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

/// Porta de importar CV em Perfil → Currículos: o botão mais a promessa.
///
/// Extraído de `profile_screen.dart` por um motivo específico: lá dentro ele
/// era intestável. `_ResumesTab` lê `Supabase.instance.client` direto no
/// `build`, então a tela inteira não monta em widget test — e a única coisa que
/// eu conseguia afirmar sobre a porta era lendo o código-fonte como texto.
/// Aqui ela renderiza de verdade, inclusive na tela mais estreita com a fonte
/// de acessibilidade no talo (que foi exatamente o achado P1-10 desta revisão).
///
/// ⚠️ Quem montar este widget: **fora** de qualquer `Consumer<ProfileViewModel>`.
/// O import dispara `loadSavedResumes()`, que liga `isLoading` antes do await de
/// rede; se o Consumer trocar a subárvore por um spinner, este widget sofre
/// dispose no meio do próprio fluxo e o `raw_text` do CV nunca é gravado. O
/// teste `library_import_entry_test.dart` trava isso.
class LibraryImportEntry extends StatelessWidget {
  /// Chamado com o id do currículo novo, quando o import dá certo.
  final void Function(String newResumeId)? onImported;

  const LibraryImportEntry({super.key, this.onImported});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ImportCvButton(
            variant: ImportCvVariant.secondary,
            analyticsSource: 'profile_resumes',
            onImported: (id) {
              if (id == null) return;
              onImported?.call(id);
            },
          ),
          const SizedBox(height: 8),
          Text(
            kLibraryImportEntryCopy,
            style: AppTextStyles.bodySm.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}
