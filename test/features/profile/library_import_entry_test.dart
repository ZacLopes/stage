import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/profile/presentation/widgets/library_import_entry.dart';
import 'package:career_gamification/features/profile/profile_screen.dart'
    show shouldShowLibraryImportEntry;
import 'package:career_gamification/features/resume/widgets/import_cv_button.dart';

/// A porta de importar CV em Perfil → Currículos.
///
/// Ela existe porque, no código de hoje, quem tem perfil preenchido ficou sem
/// NENHUM caminho para subir um currículo — 1.550 pessoas, das quais 869 nunca
/// conseguiram subir nem o primeiro. Medido em produção em 31/07/2026.
void main() {
  group('shouldShowLibraryImportEntry — tabela-verdade', () {
    test('sem kill switch → MOSTRA', () {
      expect(shouldShowLibraryImportEntry(killSwitchOn: false), isTrue);
    });

    test('kill switch ligado → esconde', () {
      expect(shouldShowLibraryImportEntry(killSwitchOn: true), isFalse);
    });

    test(
      'REGRESSÃO: a porta NÃO depende mais do Assistente (decisão de 20/08/2026)',
      () {
        // O desenho anterior escondia esta porta quando `trilha_assist_v1`
        // ligasse, porque a revisão de conflitos passaria a morar no card
        // "Fonte importada" em Perfil → Dados. O fundador decidiu o contrário:
        // quer import pelas DUAS portas (aba Currículos e conversa da trilha).
        //
        // O medo original era legítimo, mas mirava o alvo errado: o defeito
        // não é ter duas portas, é ter dois MOTORES — o legado bate no trigger
        // `zzz_mark_latest_legacy_source` assim que existe fonte canônica.
        // Isso está resolvido em `library_import_entry.dart`, que com o
        // Assistente ligado aciona o motor do Assistente.
        //
        // Este teste é o guardião da decisão: se alguém reintroduzir a
        // dependência, a assinatura muda e ele para de compilar.
        expect(shouldShowLibraryImportEntry(killSwitchOn: false), isTrue);
        expect(shouldShowLibraryImportEntry(killSwitchOn: true), isFalse);
      },
    );
  });

  group('LibraryImportEntry — renderiza de verdade', () {
    Future<void> pump(
      WidgetTester tester, {
      double largura = 402,
      double escala = 1.0,
    }) async {
      tester.view.physicalSize = Size(largura, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(escala)),
          child: const MaterialApp(
            home: Scaffold(body: LibraryImportEntry()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('mostra o botão e a promessa', (tester) async {
      await pump(tester);
      expect(find.byType(ImportCvButton), findsOneWidget);
      expect(find.text('Importar CV em PDF'), findsOneWidget);
      expect(find.text(kLibraryImportEntryCopy), findsOneWidget);
    });

    testWidgets('a promessa diz que o import NÃO sobrescreve', (tester) async {
      // `save_profile_from_json` é fill-empty por contrato (migration
      // 20260714130000). Sem a frase, devolver o botão trocaria um defeito
      // por uma promessa falsa: a pessoa sobe o CV com o emprego novo e o
      // perfil não muda.
      expect(kLibraryImportEntryCopy, contains('não é sobrescrito'));
      await pump(tester);
      expect(find.textContaining('não é sobrescrito'), findsOneWidget);
    });

    testWidgets('320pt + fonte de acessibilidade: não estoura', (tester) async {
      // A tela mais estreita que o app suporta, com a fonte no talo — a mesma
      // condição do achado P1-10 desta revisão, que foi justamente um título
      // estourando por falta desse teste.
      await pump(tester, largura: 320, escala: 2.0);
      expect(tester.takeException(), isNull);
      expect(find.byType(ImportCvButton), findsOneWidget);
    });
  });

  group('a fiação na tela — o que o render sozinho não pega', () {
    late String codigo;

    setUpAll(() {
      final src = File('lib/features/profile/profile_screen.dart')
          .readAsStringSync();
      // Fora TODO comentário (`//` e `///`): o texto deles cita nomes de
      // símbolo — inclusive o aviso que explica por que a porta fica fora do
      // Consumer — e daria falso positivo nas asserções abaixo.
      codigo = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
    });

    test('a tela monta a porta e usa o predicado', () {
      expect(codigo, contains('LibraryImportEntry('),
          reason: 'a porta sumiu da tela');
      expect(codigo, contains('shouldShowLibraryImportEntry('),
          reason: 'a tela deixou de consultar o predicado');
    });

    test('a porta fica FORA do Consumer<ProfileViewModel>', () {
      // ESTA é a asserção que importa, e é o motivo deste bloco existir.
      //
      // O builder do Consumer troca a subárvore por um spinner quando
      // `isLoading` — e o próprio import liga esse `isLoading` (`saveResume`
      // chama `loadSavedResumes()`, que notifica ANTES do await de rede). Com
      // a porta lá dentro, o `_ImportCvButtonState` sofre dispose no meio do
      // fluxo que ele mesmo disparou: `context.mounted` vira false, o
      // `imported_resume.raw_text` nunca é gravado, e o analyze-match segue
      // pontuando o currículo VELHO — com o arquivo novo visível na lista.
      //
      // Ou seja: aninhar a porta no builder não quebra nada visivelmente.
      // Quebra em silêncio. Por isso a asserção é sobre o SOURCE: a tela não
      // monta em widget test (`_ResumesTab` lê `Supabase.instance.client`
      // direto no build).
      //
      // Recorta o corpo de `_buildLibrary` — do cabeçalho até o próximo método
      // da classe — em vez de comparar posições absolutas, para o teste ficar
      // indiferente à ORDEM dos métodos: reordenar não é o defeito, aninhar é.
      const cabecalho = 'Widget _buildLibrary(';
      final inicio = codigo.indexOf(cabecalho);
      expect(inicio, greaterThan(-1), reason: '_buildLibrary sumiu');
      final depois = codigo.indexOf('\n  Widget ', inicio + cabecalho.length);
      final corpo = depois == -1
          ? codigo.substring(inicio)
          : codigo.substring(inicio, depois);

      // Sentinela do recorte: confirma que pegamos o método certo, e não uma
      // fatia vazia que faria a asserção seguinte passar por acidente.
      //
      // 20/08/2026: era `contains('Consumer<ProfileViewModel>')`. O método
      // passou a usar `Selector`, que satisfaz a invariante MELHOR que o
      // Consumer — ele não troca a subárvore inteira quando `isLoading` muda,
      // que é justamente o mecanismo que desmontava a porta. Aceitar os dois
      // mantém a sentinela sem congelar a implementação: o que este bloco
      // protege é a porta ficar FORA do builder, não qual widget reconstrói.
      expect(
        corpo.contains('Selector<ProfileViewModel') ||
            corpo.contains('Consumer<ProfileViewModel>'),
        isTrue,
        reason: 'o recorte não pegou o método certo',
      );
      expect(
        corpo.contains('LibraryImportEntry('),
        isFalse,
        reason: 'a porta de import voltou para DENTRO do '
            'Consumer<ProfileViewModel> — ela será desmontada pelo spinner '
            'que o próprio import dispara, e o raw_text não será gravado',
      );
    });

    test('o evento de import sai identificando a porta', () {
      // Sem a prop, os 4 call sites emitem o mesmo evento indistinguível e
      // não há como responder "a porta nova foi usada?".
      final entry =
          File('lib/features/profile/presentation/widgets/library_import_entry.dart')
              .readAsStringSync();
      expect(entry, contains("analyticsSource: 'profile_resumes'"));
    });
  });
}
