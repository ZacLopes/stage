# Handoff para Claude Code — arquitetura IA, Perfil, fontes e currículos

**Atualizado em:** 17/07/2026, America/Sao_Paulo  
**Repositório:** `/Users/zackourilopes/Gameficação Duolingo/career_gamification`  
**Branch atual:** `refactor/ia-fase-2-fechamento`  
**HEAD verificado:** `24007c2`  
**Situação:** há trabalho importante não commitado no working tree. Não limpar,
não trocar de branch e não descartar arquivos.

Este documento é o contexto canônico para transferir a continuação deste
trabalho ao Claude Code. Ele reconcilia o plano original de arquitetura da
informação com o estado real do repositório e define o próximo gate pequeno.

---

## 0. Prompt inicial pronto para colar no Claude Code

```text
Você vai continuar o trabalho de arquitetura IA/Perfil do Stage no repositório:
/Users/zackourilopes/Gameficação Duolingo/career_gamification

Antes de qualquer alteração, leia INTEIRO, nesta ordem:
1. HANDOFF-CLAUDE-CODE-IA-PERFIL.md
2. CLAUDE.md (as regras continuam válidas; a seção “Estado atual” está
   desatualizada e é substituída pelo handoff)
3. PLANO-IA-PERFIL-FASE-2-FECHAMENTO.md
4. PLANO-IA-PERFIL-FASE-3-GATE-3.0A.md
5. PLANO-IA-PERFIL-FASE-3-GATE-3.0B.md

Depois faça uma auditoria read-only do código e confirme branch, HEAD, git
status, callers e contratos. O working tree contém o trabalho real: NÃO use
git reset, checkout, restore, clean ou stash; NÃO descarte nem sobrescreva
mudanças preexistentes.

Você está autorizado a planejar e implementar SOMENTE o Gate 3.0C descrito no
handoff: cutover da escrita ADITIVA de skills da coleta guiada para
merge_guided_profile_list(section='skills'), com adapter/recibo tipado
fail-closed, incluindo TrilhaWriteback e TrailToProfileBridge. Não migre
replace manual, remoções, idiomas, interesses, áreas, importação, outras UIs ou
Edge Functions neste gate.

Antes de codar, crie PLANO-IA-PERFIL-FASE-3-GATE-3.0C.md com o escopo exato. A
autorização deste prompt vale somente se o plano continuar dentro desse escopo;
se a auditoria contradisser o handoff ou exigir expansão, pare e explique.

Preserve trilha_assist_v1 OFF/0 e o rollback com a flag OFF. Não faça commit,
push, deploy, migration remota, db push ou alteração de flag. Não renomeie
chaves internas/rotas por estética e não faça refatoração oportunista.

Implemente, rode os testes focados, os dois harnesses SQL, a suíte Flutter
completa, analyzer, manifest, segurança de ambiente e diff-check. Faça revisão
adversarial de concorrência, retry/idempotência, recibos malformados, limites,
ACL e regressão flag OFF. Pare ao final do Gate 3.0C e entregue um relatório
medido; não avance para o Gate 3.0D sem nova autorização.
```

O envio desse texto pelo fundador autoriza somente o Gate 3.0C acima. Não é
autorização para rollout, deploy ou para executar as demais fases.

---

## 1. Por que este trabalho existe

O Stage é um app Flutter + Supabase de vagas de estágio. O usuário descobre e
salva vagas, acompanha candidaturas e conversa com uma IA. O negócio vende para
empresas shortlists formadas a partir dos dados dos candidatos.

O problema original era de arquitetura de informação e confiança:

- os mesmos dados profissionais apareciam em Perfil e numa visão chamada
  “Currículo”;
- “currículo” significava dados estruturados, PDF importado, PDF geral e
  currículo adaptado;
- a conversa vivia dentro de Currículo apesar de já operar perfil, vagas e
  carreira;
- fontes importadas e documentos gerados eram misturados na mesma biblioteca;
- vários caminhos escreviam `profile_*` com políticas e garantias diferentes;
- concorrência, retry ou falha parcial podiam produzir falso sucesso ou
  sobrescrever uma edição manual.

A hipótese de produto foi validada, com uma correção importante: existe uma
**fonte semântica central**, não uma única tabela gigante.

```text
ENTRADAS
Onboarding · Assistente · Edição manual · Importação
                         │
                         ▼
               PERFIL CANÔNICO (`profile_*`)
        ┌────────────────┼────────────────┐
        │                │                │
  fatos profissionais   objetivos      visibilidade
        │                │                │
        └────────────────┼────────────────┘
                         ▼
SAÍDAS
Match · Shortlist · Currículo geral · Currículos por vaga

EM PARALELO
Swipes · vagas salvas · candidaturas · histórico de interação
```

Fatos profissionais, objetivos, eventos comportamentais e documentos têm
ciclos de vida diferentes. Swipes e candidaturas podem informar ranking e B2B,
mas não devem virar silenciosamente campos editáveis do perfil.

Arquivos importados são **fontes/proveniência**. Eles não são o currículo
produzido pelo Stage, mas precisam sobreviver para auditoria, comparação,
reprocessamento e vínculo de origem.

---

## 2. Contrato de produto e linguagem que não deve regredir

| Termo | Significado único |
|---|---|
| Perfil | Fatos estruturados verdadeiros sobre o candidato |
| Objetivos | O que a pessoa busca profissionalmente |
| Filtros | Recorte temporário do feed atual |
| Currículo | Documento gerado, versionável e exportável |
| Fonte importada | Arquivo usado para propor/preencher/validar o perfil |
| Assistente | Agente transversal que opera perfil, carreira, vagas e documentos |

Regras de domínio:

1. `profile_*` é a fonte canônica dos fatos do candidato.
2. Edição manual recente sempre vence importação, resposta antiga do Assistente
   ou operação concorrente.
3. A IA propõe; código determinístico e RPC validam e aplicam.
4. Toda mutação visível exige confirmação, resultado real e desfazer seguro
   quando possível.
5. Falha de persistência nunca pode avançar a conversa ou aparecer como
   sucesso.
6. Retry não pode duplicar, recapturar baseline nem aplicar outro payload.
7. Remover o arquivo-fonte não remove os fatos já incorporados ao perfil.
8. Substituir uma fonte não sobrescreve silenciosamente dados manuais.
9. Currículo geral/adaptado é snapshot de saída; posicionamento específico de
   uma vaga não altera o perfil automaticamente.
10. Objetivos persistentes e filtros temporários do feed permanecem separados.
11. Chaves internas legadas como `curriculo` podem continuar existindo para
    compatibilidade mesmo quando a copy visível é “Assistente”. Não fazer
    renomeação interna em massa.

---

## 3. Não confundir os dois sistemas de fases

Existem dois roadmaps no mesmo repositório:

1. `PLANO-MAE.md` e `PLANO-FASE-*`: evolução ampla do marketplace, feed,
   tracker, shortlist etc. A numeração 0–7 desses arquivos é outra.
2. O roadmap deste handoff: arquitetura de informação **IA/Perfil**, com fases
   1–8 descritas na seção 7.

Os checkpoints `PLANO-IA-PERFIL-*` usam o segundo sistema e são os documentos
operacionais desta frente.

Precedência em caso de conflito:

1. fatos verificados no código, migration e testes;
2. instrução atual do fundador;
3. este handoff e os checkpoints `PLANO-IA-PERFIL-*`;
4. plano inicial anexado;
5. documentos históricos `PLANO-ASSISTENTE.md` e `PLANO-FASE-*`.

`CLAUDE.md` deve ser lido: suas regras de segurança, migrations, flags, testes
e deploy continuam válidas. Entretanto, a seção “Estado atual (2026-06-16)” é
histórica e não descreve este working tree de 17/07.

---

## 4. Snapshot exato do repositório no handoff

- Branch: `refactor/ia-fase-2-fechamento`.
- HEAD: `24007c2`, atualmente também apontado por `main`/`origin/main`.
- Nenhum arquivo está staged.
- Antes da criação deste handoff havia 23 arquivos rastreados modificados e 24
  entradas não rastreadas. Este arquivo acrescenta mais uma entrada não
  rastreada.
- Nenhum commit, push, deploy ou migration remota foi feito para os Gates 2,
  3.0A ou 3.0B.
- A migration manifest local termina em 119 migrations.
- `supabase/.temp/cli-latest` está modificado por tooling. Não apagar nem
  incluir automaticamente num futuro commit sem revisar.
- O warning de shell sobre `~/.cargo/env` ausente é ruído local e não foi causa
  de falha nos testes.

O working tree é grande porque contém a implementação real ainda não
commitada. Não concluir que arquivos não rastreados são descartáveis.

Principais grupos no working tree:

- fechamento da terceira aba como Assistente;
- write-back honesto, contexto curto e stepper recolhido;
- seed OFF/0 da flag;
- migrations de Fonte importada e integridade de perfil;
- fundação de writers guiados;
- CAS/receipts do editor visual de skills;
- harnesses SQL e testes Flutter correspondentes;
- três documentos `PLANO-IA-PERFIL-*`.

Antes de continuar, o Claude deve executar apenas comandos read-only:

```bash
pwd
git branch --show-current
git rev-parse --short HEAD
git status --short
git diff --check
```

Proibido no início: `reset`, `restore`, `checkout`, `clean`, stash, troca de
branch ou formatação ampla.

---

## 5. Baseline já commitado em `main`

Não repetir nem desfazer estes trabalhos:

### 5.1 Linguagem e casa canônica

- `df808ec` alinhou a linguagem perfil × currículo × fonte.
- `cd7e2d7` consolidou o pacote “Perfil central — casa única e currículo
  canônico”.
- Bottom navigation já mostra **Assistente** na terceira posição.
- Perfil já usa as subabas **Dados**, **Objetivos** e **Currículos**.
- A chave interna `curriculo` do tool/navigation foi preservada por
  compatibilidade.

### 5.2 Currículo geral canônico — parte já entregue

- `af9527f` criou card, prévia e export do Currículo geral a partir de um
  `ProfileSnapshot` canônico.
- O loader de export é estrito para as fontes usadas: falha parcial não gera
  PDF mutilado nem analytics falso.
- Prévia e PDF usam o mesmo `ResumeData` canônico.
- Projetos e prêmios são independentes e renderizam nos cinco templates.
- Forte Foundation passou a renderizar summary.
- Matriz de contrato cobre nove grupos de conteúdo × cinco templates.
- `templates_v2_enabled` não faz o export geral reler uma fonte divergente.
- Thumbnails Forte e Cobalt foram regenerados e commitados em `ece96e1`.

Limite ainda existente: o Currículo geral é uma projeção virtual e não um
documento persistido/versionado.

### 5.3 Qualidade dos dados de perfil e PDF

`0bb2f57` adicionou, entre outros:

- e-mail profissional separado do Apple Private Relay para contato/CV;
- melhoria de edição de educação e previsão de conclusão;
- reconciliação de prêmios;
- título profissional consistente;
- normalização/limite de skills;
- mapper único do perfil para currículo;
- correções de cabeçalho e contato nos templates;
- testes de domínio, widget e PDF.

Essas decisões fazem parte do baseline e não são escopo dos próximos gates.

---

## 6. Trabalho implementado, validado e ainda não commitado

### 6.1 Fechamento da Fase 2 — Assistente assume a terceira aba

Documento: `PLANO-IA-PERFIL-FASE-2-FECHAMENTO.md`.

Implementado:

- `ConversationController.submit` é fail-closed: uma falha de write-back não
  avança passo, não entra no histórico e preserva a resposta para retry;
- apply em lote não trata falha parcial como sucesso;
- `trilha_assist_v1` foi semeada por migration como OFF/0 e é aninhada em
  `trilha_coleta_v1`;
- flag ON usa conversa única e remove o toggle global da superfície;
- o stepper vira `Fortalecer perfil`, recolhido;
- flag OFF preserva o shell legado completo como rollback;
- contexto curto local: no máximo três turnos, TTL de sete dias, 8 KiB,
  isolado por usuário e best-effort;
- falha do cache de conversa não bloqueia o app nem simula persistência;
- request contract da Edge do Assistente é validado;
- importação por conversa ficou indisponível até existir o pipeline seguro;
- interesses e áreas não foram injetados na composição ON porque seus writers
  ainda eram destrutivos.

Com a flag OFF, a bottom bar continua visivelmente chamada **Assistente**, mas
o conteúdo usa o rollback legado `Conversa | Currículo`. Isso é esperado e não
prova que o app carregou uma versão antiga. O gate/upload legado de CV também
continua presente fora da nova ferramenta segura; não confundir a ferramenta
desabilitada no prompt com remoção total de todos os uploads antigos.

Arquivos centrais:

- `lib/features/trilha/application/conversation_controller.dart`
- `lib/features/trilha/application/assistant_context_store.dart`
- `lib/features/resume/widgets/fortalecer_perfil_disclosure.dart`
- `lib/features/resume/resume_tab.dart`
- `lib/features/resume/widgets/assistant_tab_layout.dart`
- `lib/services/feature_flags_service.dart`
- `supabase/functions/trilha-assistant/request_contract.ts`
- `supabase/migrations/20260717120000_seed_trilha_assist_v1.sql`

Por que não pode ligar a flag ainda: `ResumeTab` ainda injeta callbacks legados
para campo, add/remove de item, bullet, idioma e item composto. Eles podem ser
corretos isoladamente, mas não compartilham todos CAS/receipt/atomicidade
necessários para uma edição concorrente segura.

**Bloqueador confirmado na auditoria deste handoff:** o card de conflitos da
importação ainda aplica escolhas aceitas uma por uma, captura exceções e termina
o card como `applied`. O caminho está em
`trilha_chat_controller.dart` (região atual ~2022–2048), e a composição de
produção injeta o aplicador legado em `resume_tab.dart` (~281–289). A RPC
transacional `apply_reviewed_conflicts_and_promote` já existe na migration de
14/07, mas não tem caller Flutter nesta branch. Isso contradiz o critério amplo
“lote parcial nunca aparece como sucesso”. A flag OFF contém o risco; não
declarar a Fase 2 pronta para rollout até corrigir este fluxo em gate próprio.

### 6.2 Gate 3.0A — fundação server-side

Documento: `PLANO-IA-PERFIL-FASE-3-GATE-3.0A.md`.

Migrations integradas, nesta ordem imutável:

1. `20260714120000_saved_resumes_import_metadata.sql`
2. `20260714130000_save_profile_fill_empty.sql`
3. `20260717120000_seed_trilha_assist_v1.sql`
4. `20260717130000_profile_guided_write_foundation.sql`

A fundação fornece:

- um advisory lock canônico por usuário;
- fencing `BEFORE STATEMENT` antes de tuple locks;
- replace atômico de skills, interesses e áreas;
- merge guiado somente aditivo e idempotente;
- CAS para nível de idioma;
- preservação de IDs/metadados de itens retidos;
- precedência de source para áreas;
- validação fail-closed de payload, ACL e duplicatas semânticas.

Não foram criados índices normalizados globais. Writers antigos ainda podem
produzir formatos diferentes; hoje uma duplicata semântica legacy deve falhar
e pedir revisão, nunca ser escolhida, fundida ou apagada silenciosamente.

### 6.3 Gate 3.0B — editor visual de skills

Documento: `PLANO-IA-PERFIL-FASE-3-GATE-3.0B.md`.

Somente o editor visual `edit_skills` do Assistente passou pelo cutover:

- `open_assist_skills_edit_v1` reserva baseline server-side;
- `apply_assist_skills_edit_v1` faz CAS da linha completa;
- `undo_assist_skills_edit_v1` restaura apenas se o estado vivo ainda for o
  pós-apply daquela operação;
- operation ID é estável;
- timeout congela operação e delta para retry idêntico;
- receipts distinguem `applied`, `noop`, `stale` e `undone`;
- `resulting` representa autoria histórica; `live`, o banco atual;
- replay é idempotente e payload contraditório falha fechado;
- UI não mostra adições/remoções falsas em noop;
- stale nunca sobrescreve edição mais recente;
- leitura de skills usa `order_index ASC, id ASC`, igual ao contrato SQL;
- o writer só é construído quando a flag efetiva está ON.

Arquivos centrais:

- `supabase/migrations/20260717140000_assist_skills_cas.sql`
- `lib/features/trilha/domain/assist_skills_write.dart`
- `lib/features/trilha/data/assist_skills_writer_supabase.dart`
- `lib/features/trilha/presentation/trilha_chat_controller.dart`
- `lib/features/trilha/presentation/widgets/list_editor_card.dart`
- `lib/features/resume/resume_tab.dart`
- `lib/features/profile/data/repositories/profile_repository_supabase.dart`

Limite explícito: isso não migrou o passo guiado `gap.skills`, o bridge da
trilha antiga, o replace manual em Perfil nem as remoções avulsas.

---

## 7. Estado das oito fases do plano original IA/Perfil

| Fase | Estado real | O que falta |
|---|---|---|
| 1. Contrato de linguagem | Concluída e commitada | Auditar apenas novas copies |
| 2. Assistente na terceira aba | Implementada localmente, não operacionalmente encerrada | Cutover seguro dos writers, migration/staging/device e rollout |
| 3. Perfil único e completo | Parcial | Todos os campos classificados/expostos, limpeza, invalidação e uma completude; writers seguros |
| 4. Casa do Currículo geral | Parcial | Persistência/versionamento, estado desatualizado e remoção do preview legado após rollout |
| 5. Importação e fontes | Fundação SQL parcial | Coordinator/Dart/Edge/UI, Fonte importada em Dados, Currículos outputs-only e pipeline único |
| 6. Currículos por vaga | Parcial/não comprovada | Vínculos estruturais completos com vaga/candidatura/fonte e idempotência |
| 7. Shortlist e visibilidade | Parcial em outra frente | Transparência/consentimento no app e auditoria da verdade B2B |
| 8. Retirada do legado | Não iniciada | Só após métricas, migração de consumidores e rollback documentado |

### Observações que evitam falsos “concluído”

- Perfil → Currículos ainda inclui `SavedResumeSource.imported`; portanto não é
  uma biblioteca apenas de saídas.
- Não existe hoje a seção compacta “Fonte importada” em Perfil → Dados.
- O Currículo geral é chamado no código de “projeção virtual do perfil, não
  persistida”.
- A fundação SQL de importação existe no working tree, mas o
  `SavedResumeLibrary`, `ImportCoordinator`, `import_merge.dart` e a UI da
  branch estacionada não foram incorporados nesta branch.
- Uma RPC existir não significa que o caller Flutter/Edge já foi migrado.
- `applications.adapted_resume_id` e documentos por vaga existem parcialmente,
  mas o ciclo completo vaga → documento → candidatura ainda precisa de prova.
- Trabalho administrativo de shortlist já existe no histórico; isso não prova
  que visibilidade/consentimento para o usuário esteja resolvido.
- `headline`, LinkedIn, site e disponibilidade existem no domínio, mas não
  estão todos editáveis no formulário atual.
- Cargo desejado, senioridade/nível e fit cultural ainda não estão todos
  expostos em Objetivos.
- Coursework existe em snapshot/repositório, sem seção canônica no editor.
- Ainda há duas medidas visíveis/derivadas de completude:
  `profile_personal.completeness_score` e `ProfileGaps.completionPercent`.
- Invalidação de perfil não é uniforme entre editor manual, chat e bridge
  gamificado.

---

## 8. Contratos SQL e de segurança que não podem ser quebrados

### 8.1 Ordem das migrations

Manter estritamente as cinco migrations nas posições 115–119 do manifest:

```text
20260714120000_saved_resumes_import_metadata.sql
20260714130000_save_profile_fill_empty.sql
20260717120000_seed_trilha_assist_v1.sql
20260717130000_profile_guided_write_foundation.sql
20260717140000_assist_skills_cas.sql
```

Não reordenar, condensar, reutilizar timestamp ou editar estado remoto.
`120000` e `130000` devem futuramente ser aplicadas na mesma janela: entre elas
o import fica deliberadamente fail-closed.

### 8.2 Lock e fencing

Chave única:

```text
hashtextextended('profile_write:' || user_id, 0)
```

Ordem universal:

```text
advisory lock por usuário → tuple locks → escrita
```

Nunca reintroduzir aquisição de advisory em trigger `BEFORE ROW`; isso inverte
lock com tuple e pode causar deadlock. O fencing atual é `BEFORE STATEMENT`.

Writer authenticated direto participa via trigger. Service role não tem
`auth.uid()` e precisa de RPC que pegue explicitamente o lock por `p_user_id`.

### 8.3 SECURITY DEFINER, RLS e grants

- `SECURITY DEFINER` sempre com `SET search_path = ''`.
- Toda função nova recebe `REVOKE ... FROM PUBLIC` explícito.
- Só funções públicas necessárias recebem grant para `authenticated` ou
  `service_role`.
- Helpers e promoção direta aposentada ficam privadas.
- Tabelas de receipt têm RLS e zero grant direto.
- `saved_resumes` usa grants por coluna e RLS por posse/path.
- Não dar DELETE direto de `saved_resumes` para service role.

### 8.4 Fonte importada

Invariantes atuais das migrations:

- no máximo uma fonte atual por usuário;
- fonte atual precisa ser `imported + ready`;
- `client_import_id` é idempotente por usuário;
- conclusão é vinculada a `extraction_attempt_id`;
- payload/meta/raw/cache pertencem à candidata correta;
- cache legacy é reconstruído integralmente da fonte canônica;
- cache legacy sem vínculo não recebe `source_resume_id` inventado;
- aplicação e promoção só acontecem juntas quando o conteúdo realmente
  persistível foi salvo;
- e-mail profissional e valores manuais não vazios vencem importados;
- seção relacional já preenchida não é misturada silenciosamente;
- remover fonte não remove os dados incorporados ao perfil;
- Storage e Postgres não são transacionais juntos: eventual falha pode deixar
  blob órfão, nunca perfil parcialmente apagado.

### 8.5 Receipt completo do editor visual de skills

`profile_assist_skill_operations` usa PK `(user_id, operation_id)` e guarda
snapshot integral:

- `id`
- `name`
- `category`
- `canonical_skill_id`
- `order_index`
- `created_at`

Regras:

- apply sem open falha;
- retry de open não recaptura baseline;
- metadata/order/identity/name divergentes produzem stale;
- operação terminal é imutável;
- operation ID com payload diferente falha;
- `can_undo` só é verdadeiro se `live == after_rows`;
- undo exige esse mesmo estado exato;
- timestamps dos snapshots são UTC;
- o parser Dart aceita duplicata semântica apenas em `live`; baseline e
  resulting continuam estritos.

Risco residual seguro: se uma skill canônica referenciada no snapshot for
apagada antes do undo, a FK pode fazer o undo inteiro falhar/rollback em vez de
retornar stale. Não há perda parcial.

---

## 9. Writers ainda legados: não assumir segurança por proximidade

### 9.1 Skills

Pontos confirmados:

- `ProfileEditorViewModel.replaceSkills` →
  `ProfileRepositorySupabase.replaceSkills`: get + múltiplos insert/update +
  delete; manual e multi-request;
- `TrilhaWriteback._saveSkills`: lê skills e chama `replaceSkills` para um
  merge aparente, sujeito a TOCTOU;
- `TrailToProfileBridge` também adiciona via `replaceSkills` e continua
  registrado no `GamificationViewModel`;
- helpers de `trilha_session.dart` ainda possuem add/remove avulsos;
- importação usa contratos próprios fill-empty/reviewed;
- somente o card visual `edit_skills` usa CAS/receipt 3.0B.

### 9.2 Outras listas e campos

- idiomas ainda usam add/update/delete e alguns CAS somente em contratos não
  ligados a todos os callers;
- interesses ainda possuem delete + insert;
- áreas/desired titles ainda possuem delete + insert em callers manuais;
- coursework e algumas operações compostas permanecem multi-request;
- campos escalares, bullets e itens compostos do Assistente ainda precisam de
  inventário/cutover completo;
- `generate-profile-summary` ainda não usa `set_profile_summary_cas`;
- `generate-bullets` ainda não usa `append_experience_bullets`;
- o lifecycle completo de importação não está ligado aos callers atuais.
- o card de conflitos de importação ainda aplica linha por linha e pode mostrar
  sucesso depois de falha parcial; a RPC atômica correspondente não está ligada.

Por isso a flag continua OFF mesmo depois do Gate 3.0B.

---

## 10. Próximo passo obrigatório: Gate 3.0C

### Objetivo

Migrar **somente a escrita aditiva de skills da coleta guiada** para o contrato
server-side aditivo/idempotente:

```text
merge_guided_profile_list(
  p_user_id: user,
  p_section: 'skills',
  p_items: [...]
)
```

Este RPC não é replace. Isso é intencional: uma resposta da coleta guiada pode
adicionar fatos confirmados, mas não deve apagar skills editadas manualmente.

### Callers incluídos

1. `TrilhaWriteback._saveSkills`, cobrindo `gap.skills` e
   `gap.skills.more.*`.
2. O caminho de adição de skill em `TrailToProfileBridge`, porque ele continua
   registrado e não pode ficar como writer concorrente esquecido.

Ao trocar `TrilhaWriteback._saveSkills`, auditar e testar também as superfícies
que chegam indiretamente a esse método (`gap.skills`, `gap.skills.more.*`,
adição de skill por tool, batch de coleta e conflito aditivo). Isso é cobertura
do mesmo contrato, não autorização para migrar remoções ou o lote de conflitos
completo.

### Implementação esperada

- adapter/repository dedicado e tipado para a RPC;
- parser fail-closed do receipt;
- aceitar apenas status/coerência documentados;
- payload normalizado e limite de 12 skills tratado honestamente;
- retry após resposta ambígua deve terminar como applied/noop válido, sem
  duplicar;
- nenhuma pós-leitura vazia deve ser reinterpretada como sucesso;
- preservar metadados e linhas manuais existentes;
- injeção testável, sem acoplar domínio diretamente ao singleton Supabase;
- testes com spies confirmando uma RPC por operação lógica.

### Fora do Gate 3.0C

- replace manual de skills;
- remoção de skills e undo de remoção;
- editor visual 3.0B, salvo ajuste estritamente necessário de contrato;
- idiomas, interesses, áreas ou coursework;
- importação/Fonte importada;
- mudanças de UI ou navegação;
- Edge Functions;
- índices normalizados globais;
- ativação de flags, deploy ou migration remota.

### Testes obrigatórios

1. receipt `applied` válido;
2. retry idempotente retornando `noop` sem duplicar;
3. response malformada/status desconhecido falha fechado;
4. payload inválido ou >12 não aparece como sucesso;
5. skill já existente com grafia equivalente não duplica;
6. manual × guided nas duas ordens preserva ambos os lados;
7. metadata/canonical ID/order do item manual não são perdidos;
8. duas chamadas concorrentes não geram duplicata nem deadlock;
9. `gap.skills` e `gap.skills.more.*` usam o novo adapter;
10. `TrailToProfileBridge` usa o mesmo contrato;
11. regressão flag OFF e suíte existente continuam verdes;
12. RLS/ACL: usuário B não escreve o perfil de A.

### Critério de pronto

- não existe chamada a `replaceSkills` nos dois callers aditivos incluídos;
- uma resposta guiada nunca remove skill existente;
- retry é idempotente e receipt contraditório falha fechado;
- concorrência real no harness PG17 preserva dados/metadados;
- testes focados, harnesses e suíte completa verdes;
- flag continua OFF/0;
- nenhum commit, push, deploy ou migration remota;
- relatório lista honestamente os writers de skills ainda legados.

### Condições de parada

Parar e pedir decisão se:

- a auditoria mostrar que o caller é replace/removal, não aditivo;
- o RPC atual não consegue expressar a política sem ampliar o escopo;
- receipt ou limite tiver contrato contraditório;
- teste de concorrência perder dado/metadado;
- for necessário alterar uma migration já aplicada remotamente;
- surgir necessidade de tocar idiomas/interesses/áreas/import/UI.

Ao terminar, parar para revisão independente. Não iniciar o Gate 3.0D.

---

## 11. Caminho recomendado depois do Gate 3.0C

Cada item abaixo exige nova autorização e um checkpoint independente:

1. **Gate 3.0D — replace manual de skills:** ligar Perfil ao
   `replace_profile_skills_atomic_v1`, preservando IDs/metadados e política de
   usuário manual autoritativo.
2. **Gate 3.0E — remoções/undo de skills:** CAS contra estado observado,
   receipt durável e stale honesto; nenhum remove por nome ambíguo.
3. **Gate 3.0F — idiomas:** add/level/remove, usando merge aditivo e CAS de
   nível; manual recente vence.
4. **Gate 3.0G — interesses e áreas:** gates separados se a auditoria mostrar
   políticas diferentes; área precisa preservar precedência de source.
5. **Gate 3.0H — escalares, bullets, itens compostos e Edge writers:** ligar
   RPCs já preparadas ou criar contratos mínimos, sempre sob o mesmo lock.
6. **Gate 3.0I — import/conflict wiring:** ligar o lote revisado à RPC
   `apply_reviewed_conflicts_and_promote`, com resultado agregado honesto e
   promoção na mesma transação; integrar lifecycle somente em escopo aprovado.
7. **Gate 3.0J — release environment:** aplicar migrations em staging, testar
   PostgREST/device com flag OFF, verificar rollback visual e só então avaliar
   rollout 10% → 50% → 100% em checkpoints distintos.
8. Retomar os critérios amplos da **Fase 3 original**: campos completos,
   limpeza/invalidação e uma única completude.
9. Fechar **Fase 4**: persistir/versionar Currículo geral e staleness.
10. Fechar **Fase 5**: pipeline único e UI de Fonte importada; Currículos apenas
   saídas.
11. Executar Fases 6–8 somente depois, com auditoria nova do estado real.

O plano acima é uma ordem de segurança, não autorização antecipada.

---

## 12. Arquitetura de informação final desejada

### Abas principais

| Aba | Responsabilidade |
|---|---|
| Vagas | Descobrir, filtrar esta busca, salvar, aplicar e adaptar no contexto da vaga |
| Candidaturas | Salvas, enviadas, em processo, finalizadas e externas |
| Assistente | Agente transversal: perfil, vagas, candidatura, preparação e documentos |
| Perfil | Casa dos fatos, objetivos, fontes, visibilidade e documentos |

### Perfil

1. **Dados:** contato, headline/resumo, experiência, educação, skills, idiomas,
   projetos, certificações, prêmios, LinkedIn/site/disponibilidade e seção
   secundária Fonte importada.
2. **Objetivos:** áreas, cargo, tipos de vaga, modalidades, locais,
   senioridade e fit cultural.
3. **Currículos:** Currículo geral, currículos adaptados, versões/templates e
   estado desatualizado.

### Fonte importada

Destino de UX ainda pendente:

- card compacto em Perfil → Dados;
- nome original, data, status de extração;
- visualizar, substituir e remover;
- substituir mostra novos dados/conflitos;
- finalizar importação em “Revisar dados preenchidos”;
- remover arquivo não apaga perfil;
- Perfil → Currículos não lista fontes.

### Currículo geral

Estado atual: card + prévia + PDF canônico, sem persistência. Estado final:

- snapshot salvo/versionado;
- preview = PDF;
- template e data;
- indicador “perfil mudou depois desta versão”;
- nenhum prefixo textual usado como tipo estrutural.

### Currículo por vaga

Estado final:

- vínculo estrutural com `job_id`, adaptação e candidatura;
- “Original” aponta para a fonte correta;
- reexportar é idempotente ou cria versão explícita;
- candidatura informa qual documento foi usado;
- correção factual pode oferecer “Atualizar também no Perfil”; ajuste de
  posicionamento não muda o perfil automaticamente.

---

## 13. Validação e baseline medidos no fim do Gate 3.0B

Resultados reais já obtidos:

- `flutter test --reporter compact`: **599 testes verdes**;
- testes focados finais do writer/wiring/card/order: **18 verdes**;
- analyzer focado: **No issues found**;
- analyzer completo: **0 errors**, 45 warnings e 582 infos, total 627 lints
  preexistentes;
- harness SQL isolado: T1–T15 + quatro matrizes de concorrência verdes;
- harness combinado: `ALL_SQL_TESTS_OK` e `ALL_COMBINED_SQL_TESTS_OK`;
- manifest: **119 migrations**, OK;
- segurança de ambiente: OK;
- `git diff --check`: limpo;
- scripts dos harnesses: sintaxe válida;
- sem deadlock nos cenários concorrentes exercitados.

Comandos principais:

```bash
flutter test --reporter compact
flutter analyze --no-fatal-warnings
bash scripts/check_env_safety.sh
bash scripts/check_migrations_manifest.sh
bash scripts/check_functions_types.sh
deno test supabase/functions/trilha-assistant/request_contract.test.ts
./scripts/run_profile_guided_write_foundation_test.sh
./scripts/run_fase3_sql_test.sh
git diff --check
git status --short
```

Se tocar somente Dart, ainda rode os harnesses porque o gate depende do
contrato SQL. Se tocar Edge, rode também checks/deno tests correspondentes. Se
tocar template/adaptação, obedecer os golden sets de `CLAUDE.md`.

Não formatar arquivos legados inteiros por conveniência. Formatar apenas os
arquivos realmente tocados e conferir churn no diff.

---

## 14. Checklist de revisão adversarial para todo gate

Antes de declarar pronto, revisar por lentes independentes:

1. **Concorrência:** manual × Assistente, import × Assistente, retry e duas
   sessões.
2. **Integridade:** nenhum replace acidental, perda de metadata/order/ID ou
   promoção com zero conteúdo persistível.
3. **Receipt:** malformed/unknown/contraditório falha fechado; replay não
   inventa autoria.
4. **UX:** nenhum falso sucesso, noop honesto, stale explicado, retry possível.
5. **Authz:** outro usuário, anon e service role sem grant são recusados.
6. **Locks:** advisory antes de tuple, sem BEFORE ROW.
7. **Flag:** OFF preserva rollback e não instancia/call RPC nova.
8. **Reapply/deploy:** migration idempotente sem apagar receipt; ordem do
   manifest preservada.
9. **Legado:** duplicata/whitespace/dados antigos falham com segurança.
10. **Escopo:** nenhum refactor Provider/Navigator ou limpeza paralela.

---

## 15. Regras operacionais e de autoridade

- Não fazer commit, push, PR, deploy, `supabase db push`, migration remota ou
  alteração de flag sem autorização explícita do fundador.
- Deploy futuro somente de código commitado e a partir do repo.
- Schema somente por migration + CLI; dashboard é proibido.
- Não usar down migration destrutiva como kill-switch. O rollback operacional
  é flag OFF e schema aditivo permanece.
- Antes de futuro deploy, confirmar que nenhuma versão preliminar da migration
  `20260717140000` foi aplicada remotamente; `CREATE TABLE IF NOT EXISTS` não
  corrige estrutura preliminar divergente.
- O kill-switch depende de refresh de flags/cold start; não é instantâneo em
  sessões já abertas.
- Não “corrigir” os 627 lints preexistentes neste trabalho.
- Não apagar bridges/legado até telemetria e critério formal de retirada.
- Não misturar fases em um único gate porque “os arquivos já estão abertos”.
- Não confiar apenas no relatório anterior: verificar o caminho real.

---

## 16. Formato esperado do relatório do Claude ao final de cada gate

1. Resultado em uma frase.
2. Causa/risco que o gate resolveu.
3. Arquivos novos e alterados.
4. Contrato antes → depois.
5. Como retry, concorrência, stale e erro são tratados.
6. Testes medidos, com contagens/saídas.
7. Lista explícita do que continua legado.
8. Confirmação de flag OFF e de nenhuma operação remota.
9. Riscos residuais honestos.
10. Próximo gate sugerido, sem iniciá-lo.

---

## 17. Arquivos que o Claude deve conhecer primeiro

Produto/composição:

- `lib/features/home/home_screen.dart`
- `lib/features/profile/profile_screen.dart`
- `lib/features/resume/resume_tab.dart`
- `lib/services/feature_flags_service.dart`

Perfil e writers:

- `lib/features/profile/domain/repositories/profile_repository.dart`
- `lib/features/profile/data/repositories/profile_repository_supabase.dart`
- `lib/features/profile/application/profile_editor_view_model.dart`
- `lib/features/trilha/application/trilha_writeback.dart`
- `lib/features/trilha/application/trilha_session.dart`
- `lib/features/gamification/services/trail_to_profile_bridge.dart`

Assistente:

- `lib/features/trilha/application/conversation_controller.dart`
- `lib/features/trilha/application/assistant_context_store.dart`
- `lib/features/trilha/presentation/trilha_chat_controller.dart`
- `lib/features/trilha/presentation/widgets/list_editor_card.dart`
- `lib/features/trilha/presentation/widgets/languages_editor_card.dart`
- `supabase/functions/trilha-assistant/index.ts`
- `supabase/functions/trilha-assistant/request_contract.ts`

Currículo canônico:

- `lib/services/profile_snapshot_service.dart`
- `lib/features/resume/services/general_resume_export.dart`
- `lib/features/resume/services/resume_renderer.dart`
- `lib/features/resume/data/profile_resume_mapper.dart`
- `lib/features/resume/widgets/general_resume_card.dart`
- `lib/features/resume/widgets/general_resume_preview.dart`
- `lib/features/resume/pdf_service.dart`

Migrations e testes do gate:

- `supabase/migrations/20260714120000_saved_resumes_import_metadata.sql`
- `supabase/migrations/20260714130000_save_profile_fill_empty.sql`
- `supabase/migrations/20260717120000_seed_trilha_assist_v1.sql`
- `supabase/migrations/20260717130000_profile_guided_write_foundation.sql`
- `supabase/migrations/20260717140000_assist_skills_cas.sql`
- `supabase/tests/profile_guided_write_foundation_test.sql`
- `supabase/tests/perfil_central_fase3_promote_test.sql`
- `supabase/tests/perfil_central_fase3_combined_test.sql`
- `test/features/trilha/assist_skills_writer_test.dart`
- `test/features/trilha/list_editor_card_test.dart`
- `test/features/trilha/assistant_flow_test.dart`
- `test/features/trilha/trilha_writeback_test.dart`
- `test/features/profile/profile_repository_supabase_order_test.dart`
- `test/features/resume/resume_tab_assist_writer_wiring_test.dart`

---

## 18. Fonte original do plano

O diagnóstico/plano original fornecido pelo fundador está anexado localmente
em:

`/Users/zackourilopes/.codex/attachments/c86b32a5-d423-4b15-a0f5-75883dae94a2/pasted-text.txt`

Ele contém diagnóstico, arquitetura proposta, mapa atual → proposto e as fases
1–8. Algumas referências de linha representam o código no início do trabalho;
usar este handoff e o código atual para o estado de 17/07.

Princípios finais: **o fato vence**, **verificado, não declarado**, **manual
vence**, **sem falso sucesso**, **um gate por vez**.
