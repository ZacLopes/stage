import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:career_gamification/features/profile/data/repositories/profile_repository_supabase.dart';
import 'package:career_gamification/features/profile/domain/optional_sections_visibility.dart';
import 'package:career_gamification/features/resume/widgets/import_cv_button.dart';

/// Três consertos da auditoria de 27/07 que NÃO dependem de flag, de migration
/// nem do release para serem corretos.
///
/// Cobertura declarada, para não vender o que não entrego: `ProfileSectionList`
/// e `ImportCvButton` não são montáveis em teste sem refactor que o R6 proíbe —
/// o `ProfileEditorViewModel` toca `Supabase.instance` no construtor e o botão
/// abre um file picker. Por isso a regra e a copy são testadas como funções
/// puras, e a LIGAÇÃO delas ao widget é protegida por uma checagem estreita de
/// source (um arquivo, um literal), não por asserção de árvore.
void main() {
  group('C2 — seções opcionais aparecem quando já têm conteúdo', () {
    test('quem TEM prêmio ou disciplina vê, sem precisar tocar em nada', () {
      // O caso real: 18 pessoas com prêmios e 24 com disciplinas em produção
      // que não viam o próprio dado ao abrir Perfil → Dados.
      expect(
        optionalSectionsVisible(
          callSiteDefault: false,
          userOpened: false,
          hasOptionalContent: true,
        ),
        isTrue,
      );
    });

    test('quem NÃO tem nada continua com a tela limpa', () {
      // 97% das pessoas. Mostrar duas seções "(0)" num editor de sete seria
      // trocar um problema por outro.
      expect(
        optionalSectionsVisible(
          callSiteDefault: false,
          userOpened: false,
          hasOptionalContent: false,
        ),
        isFalse,
      );
    });

    test('tocar o botão continua abrindo, mesmo sem conteúdo', () {
      expect(
        optionalSectionsVisible(
          callSiteDefault: false,
          userOpened: true,
          hasOptionalContent: false,
        ),
        isTrue,
      );
    });

    test('o call site que pede explicitamente vence', () {
      expect(
        optionalSectionsVisible(
          callSiteDefault: true,
          userOpened: false,
          hasOptionalContent: false,
        ),
        isTrue,
      );
    });
  });

  group('D2 — o arquivo importado é FONTE, não "Currículo"', () {
    test('a mensagem de sucesso não chama o arquivo recebido de currículo', () {
      for (final usable in [true, false]) {
        final msg = importCvSuccessMessage(textWasUsable: usable);
        expect(msg.toLowerCase(), isNot(contains('currículo')),
            reason: 'contrato §2: "Currículo" é o documento GERADO pelo Stage');
        expect(msg, contains('fonte'),
            reason: 'o papel do arquivo tem que ficar explícito');
      }
    });

    test('o caso de texto ilegível continua avisando do match', () {
      final msg = importCvSuccessMessage(textWasUsable: false);
      expect(msg.toLowerCase(), contains('match'));
    });

    test('os dois casos são mensagens diferentes', () {
      expect(importCvSuccessMessage(textWasUsable: true),
          isNot(importCvSuccessMessage(textWasUsable: false)));
    });

    test('o widget USA a função — o literal não voltou inline', () {
      // Sem isto, o conserto seria fácil de desfazer sem ninguém notar:
      // bastaria a função continuar certa e alguém restaurar o texto cru
      // dentro do `_onTap`. Checagem deliberadamente estreita — UM arquivo,
      // UM literal — para não virar um freio burro sobre o repo inteiro.
      final src = File('lib/features/resume/widgets/import_cv_button.dart')
          .readAsStringSync();
      final codigo = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('///'))
          .join('\n');
      expect(codigo, contains('importCvSuccessMessage(textWasUsable:'),
          reason: 'o widget deixou de chamar a função');
      expect(codigo, isNot(contains("'✓ Currículo importado!'")),
          reason: 'o literal antigo voltou para dentro do widget');
    });
  });

  group('B1 — coursework substituído numa transação só', () {
    ProfileRepositorySupabase repo(MockClient c) => ProfileRepositorySupabase(
          client: SupabaseClient('http://localhost:54321', 'test-key',
              httpClient: c),
        );

    http.Response ok(http.BaseRequest r) => http.Response(
          jsonEncode(null),
          200,
          headers: {'content-type': 'application/json'},
          request: r,
        );

    test('usa a RPC atômica, com os nomes do usuário', () async {
      http.Request? capturado;
      final r = repo(MockClient((req) async {
        capturado = req;
        return ok(req);
      }));

      await r.replaceCoursework('user-1', const ['Cálculo I', 'Estatística']);

      expect(capturado?.method, 'POST');
      expect(capturado?.url.path, '/rest/v1/rpc/replace_profile_coursework');
      final body = jsonDecode(capturado!.body) as Map<String, dynamic>;
      expect(body['p_user_id'], 'user-1');
      expect(body['p_names'], ['Cálculo I', 'Estatística']);
    });

    test('UMA requisição só — não sobrou o DELETE+INSERT', () async {
      // Era o defeito: DELETE-all e INSERT-all em duas requisições sem
      // transação. Se a segunda falhasse, a pessoa ficava sem disciplina
      // nenhuma — o apagar já tinha acontecido e não havia rollback.
      final caminhos = <String>[];
      final r = repo(MockClient((req) async {
        caminhos.add('${req.method} ${req.url.path}');
        return ok(req);
      }));

      await r.replaceCoursework('user-1', const ['Cálculo I']);

      expect(caminhos, ['POST /rest/v1/rpc/replace_profile_coursework']);
    });

    test('lista vazia também vai pelo servidor (limpar é uma escrita)', () async {
      // O caminho antigo tinha `if (names.isEmpty) return;` DEPOIS do delete —
      // ou seja, limpar tudo já era destrutivo e sem transação.
      final caminhos = <String>[];
      final r = repo(MockClient((req) async {
        caminhos.add(req.url.path);
        return ok(req);
      }));

      await r.replaceCoursework('user-1', const []);

      expect(caminhos, ['/rest/v1/rpc/replace_profile_coursework']);
    });
  });
}
