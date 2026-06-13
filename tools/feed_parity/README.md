# feed_parity — harness de paridade client × RPC (Fase 2)

Prova que o conjunto de vagas do caminho **client** (Dart real:
`fetchJobsWithDiagnostics` → `_loadProfilePrefs` → `_applyPreferenceFilters`)
é **idêntico** ao conjunto devolvido pelo RPC `get_feed_page` (migration
`20260612120000`), pros 7 perfis de referência do PLANO-FASE-2 §4 (D2).

Comparação: `count` + `md5` dos ids ordenados (uuid em PG ordena igual ao
sort lexicográfico do hex — hifens em posição fixa não mudam a ordem).
Paridade é de **CONJUNTO**: piso/jitter do ranking mudam ordem, não conjunto.

## Quando re-rodar (checklist de PR)

- Qualquer PR que toque `lib/features/jobs/utils/filter_helpers.dart`
  **ou** a migration do `get_feed_page` (sinônimos/cidades têm comentário-espelho
  nas duas pontas).
- Após migrations de DADOS em `profile_desired_titles` (ex.: D-11).

## Como rodar

1. **Snapshot** (lado client) — rode `fetch_snapshot.sql` em prod (service
   role: MCP `execute_sql` ou Studio) e salve o JSON retornado em
   `tools/feed_parity/snapshot.json`. **NUNCA commitar** (dados de usuários;
   o `.gitignore` daqui cobre).
2. **Lado client (Dart real):**
   ```bash
   dart run tools/feed_parity/parity_check.dart tools/feed_parity/snapshot.json
   ```
3. **Lado RPC (prod):** rode `rpc_parity.sql` em prod na MESMA janela de
   minutos (deadlines/swipes mudam com o tempo). Saída: tabela
   `(user_id, n, ids_md5)`.
4. Compare linha a linha: 7/7 `n` e `md5` idênticos = paridade. Qualquer
   divergência: explicar linha a linha ou é bug (aceite #1 da fase).

## Por que import direto e não cópia byte-idêntica

O plan mode (D2) usou cópia conferida por sha256. Aqui o harness importa
`package:career_gamification/features/jobs/utils/filter_helpers.dart`
diretamente — drift entre cópia e original deixa de existir por construção.
O espelhamento que segue manual (e que o harness vigia) é Dart ↔ SQL.

## Limitações conhecidas (registradas no plano)

- `unaccent` (SQL) remove diacríticos de qualquer língua; o mapa do client é
  PT-BR. Não ocorre nos dados reais; se aparecer, o harness acusa.
- O harness usa as prefs do Perfil como filtros (caminho default do
  `_performFetch`). Filtros locais (SharedPreferences) são client-side e
  invisíveis ao servidor — passariam como args do RPC do mesmo jeito (D-8).
