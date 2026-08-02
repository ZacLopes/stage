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
