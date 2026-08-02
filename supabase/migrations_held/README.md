# Migrations seguradas

Migrations **prontas e revisadas** que não podem ser aplicadas ainda porque
dependem de algo fora do banco — normalmente uma build publicada na App Store.

Elas moram aqui, e não em `supabase/migrations/`, por um motivo mecânico: o
`supabase db push` não tem seleção. Sem flag ele recusa o lote inteiro quando há
arquivo fora de ordem; com `--include-all` ele aplica **tudo** que não estiver em
`supabase_migrations.schema_migrations`. Não existe `--until` nem `--except`.
Enquanto o arquivo estiver em `migrations/`, "segurar" depende de ninguém digitar
a flag errada — e o custo do engano é silencioso.

O manifest (`supabase/migrations.manifest`) só enxerga `migrations/`, então mover
para cá e rodar `bash scripts/check_migrations_manifest.sh --update` mantém o CI e
o pre-commit verdes.

---

## `20260722120000_backfill_trail_source.sql`

**Segurada em 02/08/2026. Condição de liberação: a build 2.5.0 estar publicada e
adotada.**

### O que ela faz

Retipa 92 currículos (88 pessoas) de `source = 'manual'` para `'trail'` — os que
a trilha de coleta gerou e que hoje se passam por "feitos à mão".

### Por que não pode ir agora

A build **2.4.0+7** (commit `37edebc`) é a que está na App Store. Ela resolve o
currículo "Original" por listas literais que conhecem só `imported`/`manual`.
`'trail'` não existe para ela.

O enum Dart tem fallback (`models.dart:773-778`, `orElse: () => manual`), então
badge, ordenação e filtro de tipo sobreviveriam. **O dano não passa pelo enum:**
passa por um filtro Postgrest cru em
`adapted_resume_preview_screen.dart:301` — `.inFilter('source', ['imported','manual'])`
— que nunca vê o enum e nunca vê `'trail'`.

Medido contra produção: das 88 pessoas, **79** resolvem hoje o "Original" para uma
linha que seria retipada. Pós-flip, **50 ficam sem nenhuma linha `imported`/`manual`**
e caem no render legado — o mesmo que foi substituído porque insere "Ci" no meio
das palavras. 16 caem em outro `manual`, 13 num `imported` de verdade.

É silencioso: ninguém recebe erro, ninguém reclama, e o app não se auto-cura (o
único UPDATE de `saved_resumes` na 2.4.0 escreve `template_id`, nunca `source` —
`supabase_repository.dart:961`).

### A proteção acidental que existia — e que já foi desarmada

Até 02/08, esta migration **falharia sozinha**: o CHECK de `saved_resumes.source`
em produção aceitava só `manual/imported/adapted`. Quem adiciona `'trail'` ao CHECK
é a `20260721120000_general_resume_versions.sql`, aplicada em 02/08.

Ou seja: a partir de agora ela **roda com sucesso** se alguém der o push. Foi
exatamente esse desarmamento que motivou tirá-la do diretório — a rede de proteção
que existia por acidente deixou de existir.

### Como liberar

1. Confirmar que a 2.5.0 está publicada **e** que a base adotou (não basta estar
   na loja — quem não atualizou continua na 2.4.0).
2. `git mv supabase/migrations_held/20260722120000_backfill_trail_source.sql supabase/migrations/`
3. `bash scripts/check_migrations_manifest.sh --update`
4. Aplicar. Como o timestamp é anterior ao topo remoto, `db push` vai exigir
   `--include-all` — nesse momento já não há nada a segurar, mas confira a fila
   antes de digitar a flag.

### Rollback

`update saved_resumes set source = 'manual' where source = 'trail';`

Reversível por UPDATE — mas o problema nunca foi a reversibilidade, e sim que
ninguém perceberia que precisa reverter.

---

## `20260724120000_import_cache_cleanup_tautological.sql`

**Segurada em 02/08/2026. Condição de liberação: `extract-job-skills` deployada
lendo `profile_skills`.**

### O que ela faz

Acrescenta UMA cláusula ao gatilho `_cleanup_import_cache_after_saved_resume_delete`:
apagar o cache `gamification_data.imported_resume` quando o último CV importado
da pessoa for apagado.

Não roda backfill. Não apaga nada no ato da aplicação. Só muda a regra dali para
frente. E não toca nos 419 caches órfãos (pessoas com cache e nenhum CV importado):
o gatilho só roda em `AFTER DELETE` de uma linha `source='imported'`, e essas
pessoas não têm nenhuma — não existe evento para disparar.

### Por que ela é necessária

As duas cláusulas atuais do gatilho estão MORTAS em produção, medido em 02/08:

- `is_current_source` → `0` linhas de 1.311 têm `true`
- `v_cache_source = OLD.id::text` → **0** dos 1.096 caches têm `source_resume_id`
  preenchido

Ou seja: o gatilho existe desde `20260714130000` e **nunca disparou para ninguém**.
É por isso que há 419 órfãos. Hoje, quem apaga o CV importado continua tendo o
texto dele lido pelo `analyze-match`, pelo `adapt-resume-to-job` e pelo
`extract-job-skills`. O "apagar" não apaga.

### Por que não pode ir sozinha

A `extract-job-skills` **versão 26, que está no ar**, resolve as skills da pessoa
só a partir de `imported_resume.parsed.skills`, `whoIAm.derived.skills` e
`confirmed_skills` (verificado no bundle deployado, não no working tree — a string
`profile_skills` não aparece nele).

Apagado o cache, essa function passa a devolver `in_cv: false` para TODA skill.
A tela de confirmação de skills diz à pessoa que ela não tem nenhuma das
competências da vaga — mesmo com o perfil relacional cheio — e o `extra_skills`
que segue para o `adapt-resume-to-job` sai errado.

Não é "ficar sem dado": é receber uma resposta **confiante e errada** sobre o
próprio perfil, que é a classe mais difícil de detectar. Exposição medida: 677
pessoas têm cache + CV importado; 672 delas têm perfil relacional cheio, e são
justamente essas que receberiam a resposta errada.

### Como liberar

1. Deployar `extract-job-skills` a partir do repo commitado — a versão do branch
   lê `profile_skills` e fecha a classe inteira.
   ⚠️ Ela também lê `skill_aliases.match_kind`, então `20260801120000` precisa
   estar aplicada ANTES do deploy (foi, em 02/08).
2. `bash scripts/check_functions_drift.sh` verde.
3. `git mv supabase/migrations_held/20260724120000_import_cache_cleanup_tautological.sql supabase/migrations/`
4. `bash scripts/check_migrations_manifest.sh --update` e aplicar.

### Rollback

`CREATE OR REPLACE FUNCTION` da versão anterior (a de `20260714130000`). Reversível,
mas o cache já apagado de quem deletou nesse meio-tempo não volta.
