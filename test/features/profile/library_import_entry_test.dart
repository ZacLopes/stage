import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/profile/profile_screen.dart'
    show shouldShowLibraryImportEntry;

/// A porta de importar CV em Perfil → Currículos.
///
/// Ela existe porque, no código de hoje, quem tem perfil preenchido ficou sem
/// NENHUM caminho para subir um currículo — 1.550 pessoas, das quais 869 nunca
/// conseguiram subir nem o primeiro. Medido em produção em 31/07/2026.
void main() {
  group('shouldShowLibraryImportEntry — tabela-verdade', () {
    test('Assistente OFF e sem kill switch → MOSTRA (o caso de hoje)', () {
      expect(
        shouldShowLibraryImportEntry(assistEnabled: false, killSwitchOn: false),
        isTrue,
      );
    });

    test('kill switch ligado → esconde', () {
      expect(
        shouldShowLibraryImportEntry(assistEnabled: false, killSwitchOn: true),
        isFalse,
      );
    });

    test('Assistente ON → esconde, porque a casa passa a ser outra', () {
      // Com o Assistente ligado, quem oferece "Substituir" é o card "Fonte
      // importada" em Perfil → Dados, que tem a revisão de conflitos. Dois
      // botões de import na mesma navegação seria o defeito seguinte.
      expect(
        shouldShowLibraryImportEntry(assistEnabled: true, killSwitchOn: false),
        isFalse,
      );
      expect(
        shouldShowLibraryImportEntry(assistEnabled: true, killSwitchOn: true),
        isFalse,
      );
    });
  });

  group('a fiação na tela — o que a tabela-verdade sozinha não pega', () {
    late String codigo;

    setUpAll(() {
      final src = File('lib/features/profile/profile_screen.dart')
          .readAsStringSync();
      // Fora TODO comentário (`//` e `///`): o texto deles cita nomes de
      // símbolo — inclusive o aviso que explica por que a porta fica fora do
      // Consumer — e daria falso positivo em todas as asserções abaixo.
      codigo = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
    });

    test('a tela monta a porta e usa o predicado', () {
      expect(codigo, contains('ImportCvButton('),
          reason: 'a porta sumiu da tela');
      expect(codigo, contains('shouldShowLibraryImportEntry('),
          reason: 'a tela deixou de consultar o predicado');
    });

    test('a porta fica FORA do Consumer<ProfileViewModel>', () {
      // ESTA é a asserção que importa, e é o motivo deste arquivo existir.
      //
      // O builder do Consumer troca a subárvore por um spinner quando
      // `isLoading` — e o próprio import liga esse `isLoading` (`saveResume`
      // chama `loadSavedResumes()`, que notifica ANTES do await de rede). Com
      // o botão lá dentro, o `_ImportCvButtonState` sofre dispose no meio do
      // fluxo que ele mesmo disparou: `context.mounted` vira false, o
      // `imported_resume.raw_text` nunca é gravado, e o analyze-match segue
      // pontuando o currículo VELHO — com o arquivo novo visível na lista.
      //
      // Ou seja: mover a porta para dentro do builder não quebra nada
      // visivelmente. Quebra em silêncio. Por isso o teste lê o SOURCE: o
      // `ImportCvButton` abre file picker e o `ProfileEditorViewModel` toca
      // Supabase no construtor, então widget test não é possível aqui.
      //
      // Recorta o corpo de `_buildLibrary` — do cabeçalho até o próximo método
      // da classe — e afirma que a porta não está lá dentro. Recortar o método
      // em vez de comparar posições absolutas deixa o teste indiferente à
      // ORDEM em que os métodos aparecem: reordenar não é o defeito, aninhar é.
      const cabecalho = 'Widget _buildLibrary(';
      final inicio = codigo.indexOf(cabecalho);
      expect(inicio, greaterThan(-1), reason: '_buildLibrary sumiu');
      final depois = codigo.indexOf('\n  Widget ', inicio + cabecalho.length);
      final corpo =
          depois == -1 ? codigo.substring(inicio) : codigo.substring(inicio, depois);

      expect(corpo, contains('Consumer<ProfileViewModel>'),
          reason: 'o recorte não pegou o método certo');
      expect(
        corpo.contains('ImportCvButton('),
        isFalse,
        reason: 'a porta de import voltou para DENTRO do '
            'Consumer<ProfileViewModel> — ela será desmontada pelo spinner '
            'que o próprio import dispara, e o raw_text não será gravado',
      );
    });

    test('a copy diz que o import NÃO sobrescreve o que já existe', () {
      // `save_profile_from_json` é fill-empty por contrato (migration
      // 20260714130000): seção que já tem dado vira `preserved`. Sem essa
      // frase, restaurar o botão troca um defeito por uma promessa falsa.
      expect(codigo, contains('não é sobrescrito'));
    });

    test('o evento de import sai identificando a porta', () {
      // Sem a prop, os 4 call sites emitem o mesmo evento indistinguível e
      // não há como responder "a porta nova foi usada?".
      expect(codigo, contains("analyticsSource: 'profile_resumes'"));
    });
  });
}
