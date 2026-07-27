# Plano de correções — device-test IA/Perfil (24/07/2026)

**Criado em:** 26/07/2026 · **Branch:** `refactor/ia-fase-2-fechamento` · **HEAD:** `b66c24c`
**Base:** `DEVICE-TEST-IA-PERFIL-2026-07-24.md` + auditoria read-only própria (67 agentes,
verificação adversarial por achado) + queries no Supabase de **produção**.
**Regra aplicada:** *o fato vence* e *verificado, não declarado*. Onde o código ou o banco
contradisseram o relatório, o desvio está registrado abaixo — nenhum achado foi aceito por herança.

**Nada foi implementado.** Este documento é o gate R1. Não houve commit, push, deploy,
`db push`, migration remota nem mudança de flag.

---

## 1. Auditoria read-only

### 1.1 Estado do repositório (medido)

| Item | Valor |
|---|---|
| Branch | `refactor/ia-fase-2-fechamento` |
| HEAD | `b66c24c` (Fase 3 F3 — invalidação de match uniforme) |
| `git status --porcelain` | **42 entradas** (21 tracked modificados + 21 untracked; 2 são diretórios colapsados) |
| `git diff --check` | limpo |
| `flutter test` | **782 testes** — ver ressalva de flake em §1.5 |
| `flutter analyze --no-fatal-warnings` | **627 issues** (45 warnings + 582 infos), **0 errors** |
| `check_env_safety.sh` | OK |
| `check_migrations_manifest.sh` | OK — **126 migrations** |

O working tree contém F4.1–F4.5 e F5.1–F5.3 completas (auditado fatia a fatia), mais a
migration extra `20260724120000`. Nada foi tocado.

### 1.2 Estado de produção (medido por query, não por documento)

**Migrations aplicadas: topo = `20260720120000`.** As três do working tree **não estão em prod**:
`20260721120000`, `20260722120000`, `20260724120000`.

```
saved_resumes_source_check → CHECK (source = ANY (ARRAY['manual','imported','adapted']))
```

Prod **não aceita** `'trail'` nem `'general'`. Quem alarga o CHECK é a `20260721120000`
(não a `20260722120000` — o relatório cita só a 125; sem a 124 a 125 nem roda).
`save_general_resume_version_v1` **não existe** em prod; `remove_imported_source` e
`delete_saved_resume` existem (vieram da `20260714130000`).

**Flags em prod (tabela `app_feature_flags`, autoritativa):**

| flag | enabled | rollout |
|---|---|---|
| `trilha_assist_v1` | **false** | 0 |
| `trilha_coleta_v1` | **true** | **100** |
| `applications_tracker_v1` | **true** | **100** |
| `feed_list_v1` | true | 100 |
| `adapt_v2_enabled` | true | 100 |
| `skills_typeahead_v1` | true | 100 |

### 1.3 Bloqueadores — o que confirmei

**Bloqueador A — CONFIRMADO, com causa-raiz mais precisa que a do relatório.**

`ProfileEvents` (`lib/services/profile_events.dart:17-35`) é um bus singleton `Stream<void>`,
sem payload, sem debounce, sem dedupe. Levantamento exaustivo:

- **5 emissores:** `profile_editor_view_model.dart:633`, `preferences_view_model.dart:226`,
  `resume_tab.dart:159`, `cv_import_service.dart:201`, `gamification_viewmodel.dart:390`.
- **4 assinantes:** `user_viewmodel.dart:42`, `jobs_viewmodel.dart:61`,
  `jobs_swipe_screen.dart:179`, `general_resume_card.dart:58`.

**Nenhum dos 4 assinantes é um ViewModel que renderiza Perfil.** `ProfileEditorViewModel`
emite (`:633`, dentro de `_setSaved`) e não assina; `ProfileViewModel` não faz nem uma coisa
nem outra. Esse é o defeito estrutural — não "faltou um reload".

`lib/features/trilha/application/trilha_writeback.dart` (980 linhas) tem **zero** ocorrências
de `ProfileEvents`/`notifyChanged`/`reload` — confirmado. E `_onOrch()`
(`resume_tab.dart:440-470`) só recarrega o VM em **dois** momentos: `awaitingImportConfirm`
(`:447`) e `orch.finished` (`:464`). **Passo a passo da coleta guiada não recarrega nada.**
Por isso completar *uma* experiência por chip deixa a tela em "Experiência profissional (0)".

**Bloqueador B — CONFIRMADO, e sem flag nenhuma** (`grep FeatureFlagsService` no arquivo → vazio).

```dart
- bool get _isEditable => widget.resume.title.startsWith(ResumeViewModel.kTrailResumeBaseTitle);
+ bool get _isEditable => widget.resume.source == SavedResumeSource.trail;   // :118
```

`SavedResumeSource.fromDb` cai em `orElse: () => SavedResumeSource.manual`
(`models.dart:778-784`). Com o CHECK de prod, nenhuma linha pode ser `trail` ⇒ o predicado é
**constante-falso** hoje.

**Bloqueador C — CONFIRMADO, e a §2 do `PLANO-IA-PERFIL-FASE-6.md` está de fato errada.**

O desacordo é literal:

- `canAdaptCv` (`profile_snapshot_service.dart:93-107`) aceita experiência **ou** projeto
  **ou** formação com conteúdo **ou** perfil importado. **Não olha skills em momento algum.**
- O validador (`v2.ts:1676-1698`): `translationSlots = extraSkills.length`; qualquer skill de
  saída que não bata exato com `cvOriginalNorm` nem com `extraSkillsNorm` incrementa
  `unmatchedCount`; `unmatchedCount > translationSlots` ⇒ `throw`.

Com 0 skills no perfil e a folha de extras pulada: `cvOriginalNorm = {}`, `translationSlots = 0`
⇒ **qualquer** skill emitida derruba a adaptação no primeiro item. Determinístico, como o
relatório disse.

### 1.4 O que estava ERRADO no relatório (o código/banco ganharam)

| # | O relatório dizia | O fato |
|---|---|---|
| **1** | "a prévia **e o PDF** do Currículo geral também ignoram" (§1) | **O PDF não é afetado.** `general_resume_export.dart:222` carrega `ProfileSnapshotService().loadGeneralResumeSnapshot(id)` — **do banco** — e renderiza com `forceFallback: true`. Só a **prévia** (`general_resume_preview.dart:108`) faz `context.watch<ProfileEditorViewModel>()`. A frase "logo o PDF exportado também sairia sem ela" é inferência, não medição, e é falsa. **O defeito real é outro e pior de confiança: a prévia e o PDF podem discordar** — contra a paridade "prévia = PDF" que a Fase 4 declara. |
| **2** | "100% das linhas leem `manual` ⇒ somem Editar/Regerar/Exportar" (§2) | O predicado é constante-falso, sim. Mas a **regressão contra o comportamento de hoje** atinge **91 documentos / 87 usuários** (as únicas linhas com título `'Currículo Stage%'`, todas `source='manual'`). Os outros 1.210 documentos já eram view-only. "100%" descreve o predicado, não o dano. |
| **3** | B3 — "sobrenome não auto-capitaliza" | **Falso no código.** Os dois `TextField` têm `textCapitalization: TextCapitalization.words`, ambos na linha 77 dos respectivos arquivos. "Zac Teste silva" é artefato de digitação/autocorreção, não assimetria de código. |
| **4** | B7 — "`debugPrint` em loop" tratado como bug do app | A string não existe no repositório. Vem do SDK `posthog_flutter` 4.11.0 (capturador de screenshots do session replay), atrás de `printIfDebug`. **Não é nosso.** |
| **5** | E2 — "skills importadas não são normalizadas; assimetria entre os caminhos de escrita" | **Premissa falsa.** Existe o trigger `trg_profile_skills_canonical` BEFORE INSERT OR UPDATE OF name em `profile_skills`, que roda em toda escrita venha de onde vier. Não há assimetria de caminho; o que houve foi falha de match da taxonomia (provavelmente o PDF ASCII, como a própria ressalva do relatório admite). |
| **6** | D7 — "o app não valida formato de e-mail antes de imprimir no PDF" | **Existe** política dedicada `ContactEmail` (`lib/core/utils/contact_email.dart`), aplicada no editor com `errorText` inline e com defesa de última linha `resumeValueOrEmpty` em `pdf_service.dart:185`. `s@f.g` é sintaticamente válido — o defeito, se houver, é de rigor da regra, não de ausência dela. |
| **7** | B6 — "estágio com término igual ao início aceito sem aviso" | O banco tem `CHECK (end_date IS NULL OR end_date >= start_date)` (`20260522000001:31`), e o optimistic update faz rollback + `_setError`. Data **invertida** nunca persiste. E `end == start` (07/2026→07/2026) é um estágio de um mês — **valor legítimo**, permitido de propósito pelo `>=`. O exemplo citado não é defeito. |
| **8** | C5 — "valor do enum vazando para a UI" | Sintoma real, mecanismo errado: é um literal `Text('manual')` escrito à mão (`manual_application_card.dart:90`), com o comentário `// selo "manual"` acima. `ApplicationType` nem expõe getter `label`. |
| **9** | E1 generalizado como "o caminho de import não recarrega" | Só o caminho **novo** (trilha/3.0I) deixa o VM obsoleto. O import **legado** (`CvImportService.pickAndImport`, que é o que roda em prod hoje com a flag OFF) chama `profileVM.saveResume(...)`, que faz `await loadSavedResumes()`. |
| **10** | §5 — "Onde você mora está em Objetivos, mas é um fato" | Confirmado como localização (`preferences_tab.dart:103`), mas registro que **mover isso é mudança de contrato de UI**, não correção de bug — vai para backlog, não para esta rodada. |

### 1.5 O que NÃO consegui verificar / ressalvas honestas

1. **A suíte tem 782 testes; "782 verdes" não é propriedade estável.** Em três execuções
   completas, duas saíram verdes (exit 0) e **uma saiu vermelha**: `update_field: edição manual
   mais recente bloqueia aplicar e desfazer` (`test/features/trilha/assistant_flow_test.dart:692`),
   com `TimeoutException after 0:00:30` e `Bad state: No element` em `:715`
   (`whereType<AssistEditItem>().single` sobre lista vazia). Rodado **isolado**, o arquivo passa
   (2/2, `+88`). Diagnóstico: **flake sensível a carga/paralelismo**, não teste quebrado.
   **Registro isto para que um vermelho futuro nessa linha não seja atribuído às correções.**
2. **Bloqueador B não foi reproduzido em runtime** — nem pelo device-test nem por mim. O único
   escritor de `source='trail'` (`phase_completion_widget.dart:277`) está na gamificação sem
   entry point vivo. Continua verificado por **código + banco**, não em runtime.
3. **R5 não mede nada.** `golden_set/cvs`, `ground_truth` e `outputs` estão **vazios**; os 3
   scripts chamam `extract-profile`, **não** `adapt-resume-to-job`; com corpus vazio ambos saem
   exit 0 — "golden_set limpo" é indistinguível de "não havia nada pra rodar". Pior: nenhum
   script ou job de CI invoca `golden_set/` (as 3 menções em `scripts/`, `.github/` e `CLAUDE.md`
   são um comentário e duas frases de doutrina), e `adapt-resume-to-job` está **excluído por nome**
   do `check_functions_types.sh`. **Não finjo cobertura: hoje o pipeline adapt está sem rede.**
4. **`user_metadata` como segunda origem do nome vazio.** No adapt, `profileFallback`
   (`index.ts:2517-2524`) é o SELECT em `user_profiles` **ou** um objeto sintético de
   `auth.users`. O `name=""` do log pode vir das duas fontes.

### 1.6 Correções aos planos (confirmadas)

- **F6.0 está FEITA e LIGADA.** `lib/features/jobs/utils/original_source.dart` tem a função pura
  com a política exata que o §3 pede; o caller está em `adapted_resume_preview_screen.dart:310`;
  são **exatamente 14 testes**; o `inFilter('source',['imported','manual'])` **não existe mais**
  em `lib/`. O `PLANO-IA-PERFIL-FASE-6.md` §3 e §1.3 estão desatualizados.
- **`HANDOFF §7` está desatualizado.** Cargo desejado, senioridade ("Momento de carreira") e fit
  cultural estão **os três** expostos em Objetivos (`preferences_tab.dart`), com estados vazios
  honestos e ação Editar.
- **`PLANO-IA-PERFIL-FASE-6.md` §1.7** ("0 candidaturas `type='manual'`") foi superada pelo
  próprio teste. E `applications_tracker_v1` está **ON/100** — o refutador que disse o contrário
  confiou no seed da migration e no `CLAUDE.md`; **o banco venceu**.
- **Achados novos de drift documental** (registrados, não corrigidos aqui):
  - `PLANO-IA-PERFIL-FASE-5.md` §3/§4 afirma "nenhuma migration nova" e "sem harness SQL novo" —
    mas o working tree tem `20260724120000_import_cache_cleanup_tautological.sql` **e**
    `supabase/tests/perfil_central_fase5_import_cache_test.sql`.
  - O mesmo plano diz que "Substituir" fica para a F5.4 — mas o botão **já está ligado**
    (`imported_source_card.dart:177`, `:223`, `:320-322`).
  - O mesmo plano diz que `remove_imported_source` está "sem caller Dart" — **já tem** (F5.2).
  - Manifest: F4 projeta 125, F5 nega migration nova, F6 já parte de 126. O real é **126**.
  - **A análise de retrocompatibilidade da F4.5 é unidirecional**: o plano só analisou
    "build antigo + DB novo". A combinação quebrada é a inversa — **é exatamente o Bloqueador B**.

---

## 2. Fatias

Seis fatias **independentes**: nenhuma depende da aprovação de outra, nenhuma exige migration,
deploy de Edge, mudança de flag ou refactor de Provider/Navigator (R6 preservado).
Cada uma tem critério de pronto **medido**.

### F1 — Nome do arquivo do currículo (B1 + D1)

**Escopo.** `curriculo_.pdf` e `curriculo__1eee2f.pdf` acontecem porque `UserProfile.name` é
**não-nulável** e o desserializador coage NULL para `''` (`models.dart:49`), então
`user?.name ?? 'profissional'` só dispara se o **objeto** for null. Em prod: **110 de 2.137
usuários** com nome vazio — e a série por coorte é **crescente**: maio 1,1% → junho 11,7% →
julho 21,1%. **100 desses 110 têm `first_name` preenchido em `profile_personal`**, ou seja, o
nome certo está a uma leitura de distância.

- Criar `ResumeFilename` (classe estática pura, molde do `ContactEmail` já existente no repo).
  Cadeia: `resume.fullName` → `user.name` → literal de fallback; trim, colapso de espaços,
  sanitização, truncamento.
- Aplicar nos 2 call sites reais: `general_resume_export.dart:252` e
  `adapted_resume_preview_screen.dart:487` (este último também mata o underscore duplo).
- **Precedente que justifica não usar flag:** `pdf_service.dart:718` (e `:1061`, `:1280`,
  `:1544`, `:1754`) **já** prioriza `resume.fullName` sobre `user?.name` para imprimir o nome
  **dentro** do PDF. O corpo do documento saiu certo e o nome do arquivo saiu vazio na mesma
  exportação — a correção alinha o filename a uma regra que a casa já aplica.

**Contrato aprovado (decisão 6):** sem flag · fallback **`curriculo.pdf`** · **sem acentos**
(ASCII-folded) · **nunca derivar de e-mail** (descarta qualquer candidato com `@` ou reprovado
por `ContactEmail.isPrivateOrSynthetic`).

**Arquivos:** `lib/core/utils/resume_filename.dart` (novo), `general_resume_export.dart`,
`adapted_resume_preview_screen.dart`, `test/core/utils/resume_filename_test.dart` (novo).

**Testes novos:** nome vazio→`curriculo.pdf`; nome só-espaços→idem; `fullName` vence `user.name`;
espaços viram `_`; sem underscore duplo quando há sufixo de vaga; truncamento;
`José Antônio`→`Jose_Antonio`; caracteres de path (`/`, `..`) não vazam;
**e-mail Apple relay nunca vira nome**; **e-mail sintético `phone_*@stage.app` nunca vira nome**;
qualquer string com `@` é descartada.

**Pronto quando:** todos os testes passam; `flutter test` sem regressão; um caso derivado do
usuário real de teste (`name=''`, `first_name='Zac Teste'`) produz filename com nome; e um caso
derivado de um dos 109 usuários de login por telefone produz **`curriculo.pdf`**, nunca o número.

**"Não quebrar nada" — como isso é garantido, não prometido:** a função é **pura** (sem I/O, sem
Flutter, sem Supabase), então roda inteira em teste. A mudança é **monotônica por construção**:
onde já existe nome, a saída é idêntica à de hoje — e há teste explícito para isso. Os 2 call
sites trocam uma expressão por uma chamada, sem `await` novo, sem leitura nova, sem provider
novo. Não há caminho para loop, race ou regressão com a flag OFF.

---

### F2 — `_isEditable` tolerante ao legado (Bloqueador B)

**Escopo.** Extrair o predicado para função pura e torná-lo tolerante **com o OR restrito a
`manual`**:

```dart
bool isTrailResume(SavedResumeSource source, String title) =>
    source == SavedResumeSource.trail ||
    (source == SavedResumeSource.manual && title.startsWith(kTrailResumeBaseTitle));
```

**Por que o OR restrito a `manual` e não ao título solto:** medi em prod que o prefixo
`'Currículo Stage%'` existe **exclusivamente** em linhas `manual` (91 linhas / 87 usuários;
0 em `imported`, `adapted`). Restringir a `manual` garante que um documento `general` ou
`adapted` que por acaso nascesse com esse prefixo **não** vire editável.

**Por que isso é seguro:** `_buildEditableBody` **nunca lê o CV salvo** — renderiza
`resumeVM.resumeData`, a projeção viva do perfil (as únicas referências a `widget.resume` no
arquivo são `:118, :132, :430, :446, :454, :472, :484`). `_isEditable` é um interruptor de
**exibição**; virá-lo não pode corromper linha nenhuma.

**Por que sobrevive à migration:** quando a `20260722120000` rodar, o 1º ramo passa a valer para
as 91 linhas convertidas e o 2º simplesmente para de casar. Nada quebra no dia da migration.

**Arquivos:** `resume_detail_screen.dart` (1 linha + import), função pura (arquivo próprio ou
junto de `models.dart`), teste novo.

**Testes novos:** `trail` → editável; `manual` + prefixo → editável; `manual` sem prefixo → não;
`imported` com prefixo → **não**; `adapted` → não; `general` → não.

**Pronto quando:** os 6 testes passam e a matriz cobre as 4 combinações de `source` que existem
em prod hoje (1.301/1.301 linhas por classe).

---

### F3 — Invalidação da coleta guiada (Bloqueador A, instância 1)

**Escopo.** O seam já existe: `resume_tab.dart:399` passa `onProfileEdited: _scheduleProfileReload`
ao controller, e `trilha_chat_controller.dart:1204` já o chama para a edição in-place
(`if (changed) onProfileEdited?.call();`). Falta chamá-lo no **fim do `_doSubmit`** da coleta
guiada — depois dos guards de `writeFailed` (`:1217`) e de fila estável (`:1227`), que são os
marcos que o próprio código já trata como sucesso.

Isso é **uma linha de produção**, num ponto já provado, reusando o debounce de 250 ms que
`_scheduleProfileReload` já tem.

**Por que não mexo em `trilha_writeback.dart`:** espalharia o diff por ~25 escritores de um
arquivo de 980 linhas cujo modo de falha é silencioso. O seam único é mais barato e mais
testável. (A alternativa "cada writer emite" fica registrada como fatia 2 possível, se a
telemetria mostrar volume incômodo.)

**Por que não faço `ProfileEditorViewModel` assinar o bus:** fecharia a classe inteira, mas vale
**sem flag em produção** e cruza o caminho do onboarding/optimistic update. É decisão do fundador
(§4, decisão 3) — não a tomo sozinho.

**Arquivos:** `trilha_chat_controller.dart` (1 linha), teste.

**Testes novos:** o harness `build(... onProfileEdited: () => reloads++)` **já existe**
(`assistant_flow_test.dart:288-340`, usado em `:1856/:1981/:2018/:2052/:2090`) — não é
infraestrutura nova. Casos: passo respondido com sucesso ⇒ `reloads == 1`; write-back falhou ⇒
`reloads == 0` (não avança nem invalida — regra 5 do handoff); dois passos seguidos ⇒ debounce
coalesce; flag OFF ⇒ comportamento esperado conforme a decisão 3.

**Pronto quando:** os testes passam **e** o teste "write-back falhou ⇒ 0 reloads" prova que a
correção não transforma falha em falso sucesso.

**Nota de escopo:** esta fatia também resolve a divergência **prévia × PDF** do §1.4 item 1,
porque a prévia lê o VM que passa a ser recarregado.

---

### F4 — Invalidação do card "Fonte importada" (Bloqueador A, instância 2 / E1)

**Escopo.** No caminho **novo** (trilha/3.0I), a linha de `saved_resumes` nasce **server-side**
(`import_review_coordinator.dart:95`, RPC `begin_import_source`) e ninguém recarrega
`ProfileViewModel.savedResumes` — que é a fonte do card (`imported_source_card.dart:161-162`).
`ProfileViewModel` só recarrega em construção, `signedIn`, `saveResume` e pull-to-refresh da aba
**Currículos** (`profile_screen.dart:358`). O caminho de **remoção** recarrega; o de **import**, não.

Canal novo e explícito (`onDocumentsChanged`) no controller, disparado no fim do import e da
aplicação de conflitos, ligado a `ProfileViewModel.loadSavedResumes()`.

**Arquivos:** `trilha_chat_controller.dart`, `resume_tab.dart`, teste.

**Testes novos:** import concluído ⇒ canal disparado 1×; aplicação de conflitos ⇒ disparado;
falha de import ⇒ **não** disparado.

**Pronto quando:** os testes passam. **Dívida registrada honestamente:** o wiring
`resume_tab → ProfileViewModel` em si não é testável sem device; o que testo é o canal no nível
do controller. Não escondo isso atrás de "R3 cumprida".

---

### F5 — Falha honesta da adaptação (Bloqueador C — parte sem decisão de produto)

**Escopo.** Três defeitos independentes do gate, todos client-side:

1. **A3 — vazamento.** A tela exibiu `ClientException: ... uri=https://<project>.supabase.co/...`.
   Isso põe a URL/ref do projeto Supabase na UI, em inglês, para usuário pt-BR. Trocar por
   mensagem de rede honesta em pt-BR, sem `e.toString()`. Auditar os demais `catch` do mesmo
   caminho pelo mesmo padrão.
2. **A1 — affordance falsa.** "Tente novamente" + CTA "Tentar de novo" numa falha
   **determinística**. Quando o motivo for `adaptation_rejected` **com 0 skills no perfil**, a
   mensagem e o CTA passam a apontar para a ação que resolve.
3. **A2 — a mensagem não diz o que fazer.** Idem.

**Não toca** prompt, validador, `v2.ts` nem qualquer Edge ⇒ **não aciona R5**.

**Arquivos:** `resume_adaptation_sheet.dart`, teste.

**Testes novos:** mensagem de rede não contém `http`/`uri=`/nome do projeto; `adaptation_rejected`
+ 0 skills ⇒ copy e CTA de "adicionar habilidades"; `adaptation_rejected` + skills > 0 ⇒ mantém
retry (aí a variância do LLM é real); nenhuma mensagem exposta contém `Exception`.

**Pronto quando:** os testes passam e um grep no caminho de erro não acha `e.toString()`
alcançável pela UI.

---

### F6 — Gate do adapt exige skills (Bloqueador C) — **AUTORIZADA pela decisão 2, mínimo 3**

**Escopo aprovado (26/07):** `canAdaptCv` passa a exigir também **≥ 3 habilidades**, extraído
para função pura testável (molde do `resolveOriginalSource` que a F6.0 já estabeleceu), e o
gate passa a rodar **antes** da folha de extras (hoje `jobs_swipe_screen.dart:417-449` abre a
folha e só depois `resume_adaptation_sheet.dart:162-179` consulta o gate).

**O tamanho do problema, medido em prod:**

| | usuários |
|---|---|
| Total | 2.137 |
| Passam no `canAdaptCv` atual (exp/projeto/formação) | **1.530** |
| Destes, com **0 skills** | **745** |
| Destes, com skills ≥ 1 | 785 |

**48,7% de quem o gate deixa entrar hoje o validador vai expulsar** — se pular a folha de extras.
Isto é muito mais forte que "37% das falhas": é metade da população elegível caminhando para uma
falha determinística de ~25 s.

**Agravante que o relatório não pegou:** a folha de extras só aparece quando `hasResume` é
verdadeiro (`jobs_swipe_screen.dart:410-436`). Para quem não tem CV importado, `extraSkills` é
`[]` **por construção** ⇒ `translationSlots = 0` ⇒ com 0 skills a falha é inescapável, sem
nenhuma saída dentro do fluxo.

**Comportamento aprovado, nas três faixas:**

| Habilidades | O que acontece |
|---|---|
| 0 | Barrado na porta, com botão que redireciona para o editor de habilidades |
| 1–2 | Barrado na porta, com a mesma saída — mas a copy diz **quantas faltam**, não "adicione habilidades" (a pessoa já começou; tratá-la como quem tem zero é errado) |
| ≥ 3 | Passa. A folha "esqueceu de mencionar" abre normalmente e ela pode adicionar mais — **comportamento atual, sem trabalho novo** |

**Testes novos:** 0 skills ⇒ bloqueia com CTA de redirecionamento; 1–2 skills ⇒ bloqueia com copy
de "faltam N"; ≥3 + experiência ⇒ passa; ≥3 **sem** material narrativo ⇒ continua bloqueando
(não afrouxa o critério que já existe); o gate é consultado **antes** de abrir a folha.

**Pronto quando:** os testes passam **e** a consulta SQL da tabela acima, reaplicada ao predicado
novo, mostra **817 usuários** (745 + 72) movidos de "entra e falha em 25 s" para "é avisado em 0 s
com uma saída".

---

## 3. Ordem, e o que depende de deploy

### 3.0 Ordem de release fechada pelas decisões (26/07)

**Caminho A:** app primeiro, migrations depois. Logo a sequência operacional é:

```
1. F1…F6 implementadas e verdes
2. commit  (as 3 migrations continuam locais, sem push)
3. release do app  ← precisa OBRIGATORIAMENTE da F2, senão quebra p/ 87 usuários
4. esperar a build nova dominar os usuários ativos (checar versão no PostHog)
5. supabase db push  → as 3 migrations juntas
6. só então avaliar ligar `trilha_assist_v1`
```

Entre os passos 3 e 5 o export do Currículo geral avisa "não consegui salvar a versão" — honesto,
mas visível. Encurtar essa janela é o objetivo do passo 4.

### 3.1 Ordem recomendada de implementação

**F2 → F1 → F5 → F3 → F4 → F6.**

Justificativa por risco, não por facilidade:

1. **F2 primeiro** porque é a única que **bloqueia qualquer release**. Não está atrás de flag:
   se um app subir com o working tree como está, 87 usuários perdem editar/regerar sem aviso e
   sem rollback por flag. É 1 linha e 6 testes — não há motivo para ela esperar.
2. **F1** porque é o arquivo que o candidato **anexa numa vaga**, o dano é 100% externo, o custo
   é trivial, e a série por coorte está **subindo** (1,1% → 11,7% → 21,1%).
3. **F5** antes de F6 porque corrige um **vazamento de infraestrutura na UI** e não depende de
   nenhuma decisão de produto — vale mesmo que o gate nunca mude.
4. **F3/F4** porque são pré-condição para ligar `trilha_assist_v1`, e F3 tem um pé em produção
   hoje (§3.3).
5. **F6 por último** porque é a única que muda **política de produto** (transforma um "talvez"
   num "não") e depende de decisão explícita.

### 3.2 O que precisa estar em prod ANTES de qualquer app subir

**Nenhuma das seis fatias exige migration.** Isso é deliberado: elas foram desenhadas para não
amarrar na janela de co-deploy. Mas o resto do working tree exige, e a ordem importa:

| Migration | Em prod? | O que trava se o app subir sem ela | Muda dados? |
|---|---|---|---|
| `20260721120000_general_resume_versions` | **não** | `save_general_resume_version_v1` não existe ⇒ o auto-save da F4.3 **no-opa em silêncio**; colunas `version`/`profile_fingerprint` não existem; CHECK não aceita `general`/`trail` ⇒ **causa raiz do Bloqueador B** | **não** — puramente aditiva, 0 linhas afetadas, 0 linhas `general` existem |
| `20260722120000_backfill_trail_source` | **não** | sem ela, `source='trail'` nunca existe | **sim** — converte **91 linhas / 87 usuários** de `manual` → `trail` |
| `20260724120000_import_cache_cleanup_tautological` | **não** | limpeza do cache legado | conforme decidido em 24/07 |

**O ponto crítico de sequenciamento** (medido no `PLANO-IA-PERFIL-FASE-6.md` §1.3 e confirmado
por mim): aplicar a `20260722120000` **enquanto o app em produção ainda for o de hoje** custa
**78 usuários vendo outro documento como "Original"** e **50 ficando sem nenhum**, porque o
binário em prod ainda filtra por `['imported','manual']`. A F6.0 (que corrige isso) está pronta
**no working tree**, não em prod.

Daí a recomendação da decisão 4 (§4): **desacoplar as duas**. A `20260721120000` é aditiva e
pode ir a qualquer momento; a `20260722120000` deve esperar um app com `resolveOriginalSource`
em produção.

**O que dá para corrigir sem migration nenhuma:** F1, F2, F3, F4, F5, F6 — as seis.

### 3.3 Um recorte que muda a leitura do Bloqueador A

`trilha_coleta_v1` está **ON/100 em prod** e `resume_tab.dart:163-181` monta o
`TrilhaChatController` **incondicionalmente** — a flag `trilha_assist_v1` só liga as
*ferramentas* do assistente. Ou seja, a coleta guiada roda em produção hoje, e o painel
"Prévia do currículo" do shell legado lê o `ProfileEditorViewModel` que ninguém recarrega entre
passos. **O Bloqueador A não é só um bloqueio de rollout: uma parte dele já está em produção.**
Isso é o que torna a decisão 3 do §4 (gatear ou não o hook) uma decisão de verdade.

---

## 4. Decisões que dependem do fundador

> Nenhuma linha de código será escrita sobre estes pontos sem resposta explícita.

### Decisão 1 — Bloqueador B: co-deploy obrigatório ou `_isEditable` tolerante? — **DECIDIDA (26/07): SAÍDA A**

> **Fundador, 26/07:** predicado tolerante, com o gatilho de remoção datado.
> F2 está autorizada no formato descrito abaixo.

**Minha recomendação (acatada): tolerante (F2), com gatilho de remoção datado.**

- Restaura o comportamento de prod **bit-a-bit**: as 91 linhas voltam a ser editáveis, as 1.210
  restantes seguem view-only exatamente como hoje.
- **Não cria janela de co-deploy para errar.** A alternativa (migration primeiro) tem custo
  medido: 50 usuários sem "Original" e 28 vendo outro, e o dano dura até cada um atualizar o app.
- Sobrevive à migration sem ação nenhuma.
- É testável sem device, no molde que a casa já usa.

**O preço, dito na cara:** ressuscita a string mágica `'Currículo Stage'` — exatamente o
anti-pattern que a F4.5 queria matar. Por isso proponho um **gatilho explícito de remoção**:
*"deletar o 2º ramo de `isTrailResume` quando `select count(*) from saved_resumes where
source='trail'` retornar 91 em prod"*, com o teste `manual + prefixo → editável` servindo de
alarme vermelho quando a dívida puder morrer. Sem gatilho, vira legado permanente.

### Decisão 2 — Adapt: o gate passa a exigir skills, ou a folha de extras vira obrigatória? — **DECIDIDA (26/07): A + B, mínimo 3**

> **Fundador, 26/07:** o gate passa a exigir habilidades, **mínimo 3**. Quem já tem
> habilidades segue podendo adicionar mais pela folha "esqueceu de mencionar". Quem tem 0
> é mandado para onde se adiciona, por um botão que redireciona. O "não" na porta está
> aprovado.

**Distribuição medida em prod (26/07) — o limiar 3 custa pouco a mais que 1:**

| Habilidades | Usuários (dos 1.530 que passam no gate hoje) |
|---|---|
| 0 | 745 |
| 1–2 | **72** |
| ≥ 3 | 713 |

Passariam com mínimo 1: 51,3%. Com mínimo 3: 46,6%. A distribuição é **bimodal** — quase
ninguém vive na faixa do meio —, então exigir 3 barra apenas **72 pessoas a mais** que exigir 1,
e em troca garante uma seção de habilidades decente no PDF. A escolha do fundador está
sustentada por dado, não por gosto.

**Correção a uma afirmação minha anterior (o fato vence, inclusive contra mim):** eu havia
escrito que a folha de extras "só aparece para quem tem CV importado", repetindo o comentário
de `jobs_swipe_screen.dart:410-412`. **Falso.** O predicado real é `userVm.hasResume`, que é
mais amplo: `_hasProfileData = !snapshot.isEmpty` (`user_viewmodel.dart:210`) — qualquer dado
de perfil serve. Consequências:

1. **A parte B da decisão já funciona hoje, sem trabalho novo.** Quem passa no gate com ≥3
   habilidades tem snapshot não-vazio ⇒ a folha abre ⇒ pode adicionar mais. F6 não precisa
   mexer nisso.
2. O trabalho novo de F6 é **só** a parte A: barrar quem está abaixo de 3 e redirecionar.
3. Com o gate em 3, as 745 pessoas de 0 habilidades **não chegam mais à folha** — vão para o
   editor de habilidades. Quem chega à folha é quem tem material para ela cruzar.
4. O comentário enganoso em `jobs_swipe_screen.dart:410-412` deve ser corrigido junto (é a
   fonte do meu próprio erro).

**Minha recomendação (acatada, e ampliada pelo fundador): o gate exige skills (F6), e a folha
de extras fica como está.**

O argumento decisivo é que **a folha de extras não persiste nada no perfil**: `extra_skills` vai
no payload da Edge e entra no CV daquela vaga — não há **nenhum** writer para `profile_skills`
nesse caminho. Então "folha obrigatória quando o perfil tem 0 skills":

- resolve o sintoma **por vaga** e obriga a redigitar a cada vaga;
- deixa o perfil oco — que é o ativo do negócio (match, shortlist, Currículo geral);
- e nem é alcançável para quem não tem CV importado (a folha só abre com `hasResume`).

Já exigir skills no gate manda o usuário encher o **perfil**, que conserta a adaptação de hoje
**e** todas as futuras, mais o match e a shortlist. O §11 do device-test prova o mecanismo com
uma variável só: 0→3 skills fez a adaptação passar.

**Sub-decisões que preciso que você resolva:**
- **Limiar:** `>= 1` (único valor que o código justifica) ou `>= 3` (o que foi medido
  funcionando)? Se for 3, é um número mágico que alguém vai ter que defender depois.
- **Bloquear ou deixar tentar?** F6 transforma um "talvez" num "não". A alternativa é ficar só
  na F5 (deixa tentar, explica direito ao falhar). Acho o "não" certo — economiza 25 s e uma
  mentira — mas é sua chamada.

### Decisão 3 — O hook de invalidação (F3) fica atrás de `assistEnabled`? — **DECIDIDA (26/07): NÃO gatear**

> **Fundador, 26/07:** saída B — conserta para todos. Os recarregamentos extras do feed
> estão aceitos, com o compromisso de medir. F3 autorizada sem gate.

**Minha recomendação (acatada): NÃO gatear.**

`trilha_coleta_v1` está ON/100 e a trilha roda sem `trilha_assist_v1` (§3.3). Gatear conserta só
o mundo com a flag ON e **deixa de propósito um bug vivo em produção**. Contra-argumento honesto:
é comportamento visível sem flag, o que roça R4. Minha leitura é que R4 existe para tornar
*comportamento novo e arriscado* reversível, e isto não é comportamento novo — é a tela passando
a mostrar o que o banco já diz. O precedente está no mesmo arquivo: `_scheduleProfileReload` já é
incondicional em `:150` e `:399`.

**Efeito colateral que precisa do seu aval:** 1 `notifyChanged()` por passo respondido faz
`JobsViewModel._onProfileChanged()` (`jobs_viewmodel.dart:788-800`) poder refazer o fetch do feed
inteiro quando o usuário não tem filtros locais. Recomendo **aceitar e medir**; separar o bus em
dois sinais ("recarrega perfil" × "invalida match") vira fatia própria se incomodar.

### Decisão 4 — Desacoplar as migrations? — **DECIDIDA (26/07): sim** · ⚠️ **não executável do jeito direto**

> **Fundador, 26/07:** "vá pela sua recomendação" — aplicar a aditiva agora, segurar a que
> reetiqueta os 91 documentos.

**A intenção está certa. Mas verifiquei o caminho de execução e ele tem três travas.**

**Trava 1 — as três migrations estão NÃO COMMITADAS.** `git status` mostra as três como
untracked. O `CLAUDE.md` registra como aprendizado permanente: *"Deploy só de código COMMITADO —
deployar do working tree cria drift instantâneo entre repo e prod (aconteceu em 12/06 …;
flagrado por `check_functions_drift.sh`)"*. Aplicar agora repetiria um erro já documentado.

**Trava 2 — `supabase db push` não tem alvo de versão.** Conferi o `--help` do CLI 2.98.2: as
flags são `--db-url`, `--dry-run`, `--include-all`, `--include-roles`, `--include-seed`,
`--linked`, `--local`, `--password`. **Não existe `--target`/`--to-version`.** O comando aplica
**todas as pendentes**. Não dá para aplicar a 124 e segurar a 125 com o comando normal.

**Trava 3 — o push levaria junto a `20260724120000`**, cuja decisão de fundo a memória do
projeto registra como **ainda pendente** (limpeza do cache legado `imported_resume`). Aplicar
por arrasto uma migration cuja decisão não foi fechada é o oposto de "um gate por vez".

**Dois caminhos viáveis (escolha do fundador):**

| | Caminho | Como funciona | Custo |
|---|---|---|---|
| **A** | **Segurar tudo** | Nenhum push até o app com `resolveOriginalSource` estar em prod; aí aplica as três de uma vez | O versionamento do Currículo geral segue no-opando em silêncio até lá. **Zero risco.** |
| **B** | **Neutralizar a 125 agora** | A `20260722120000` **ainda não foi aplicada em lugar nenhum**, então editar o arquivo local é legal (a §8.1 do handoff proíbe reordenar/reusar timestamp e editar estado remoto — não isto). Tira-se o UPDATE, empurra-se 124 + 125-inerte + 126, e o backfill real vira uma migration NOVA quando o app subir | Entrega o versionamento já. Custo: +1 migration no manifest depois, e a etiqueta `trail` passa a existir sem nenhuma linha usando — que é exatamente o estado que a **F2 já cobre** |

**Não recomendo** mover arquivo de migration temporariamente para fora da pasta: cria drift de
manifest e é edição de estado à mão, que a casa evita por regra.

**Minha recomendação era o B. O fundador escolheu o A — CAMINHO A CONFIRMADO (26/07):**
nenhum push até o app novo estar em produção; depois as três migrations vão juntas.

**Consequências do caminho A, registradas para não surpreenderem depois:**

1. **A F2 deixa de ser "recomendável" e passa a ser obrigatória.** Sob o caminho A, o app sobe
   contra um banco **sem** as migrations. É exatamente a combinação que produz o Bloqueador B.
   Sem a F2, o release quebra editar/regerar para os 87 usuários. **F2 é pré-condição do
   release, não uma melhoria.**
2. **Toda exportação do Currículo geral vai avisar "não consegui salvar a versão"** enquanto as
   migrations não subirem, porque `save_general_resume_version_v1` não existe em prod
   (verificado). O comportamento é **honesto** — o PDF é gerado e compartilhado normalmente, o
   card não afirma versão que não existe e o evento sai com status de falha (device-test §3).
   Mas é um aviso visível em cada export. Quanto menor a janela entre release e migrations,
   melhor.
3. **O dano de 78/50 não zera no dia do release — decai com a adoção.** As 91 linhas
   reetiquetadas quebram o "Original" de quem ainda está no app **antigo** (o novo já traz
   `resolveOriginalSource`). Então 78 usuários vendo outro documento e 50 sem nenhum é o **pior
   caso** (100% na build velha), e encolhe conforme as pessoas atualizam.

**Gate recomendado para o push (não é decisão minha, é sugestão medida):** antes de rodar as
migrations, conferir no PostHog a distribuição de versão do app e empurrar quando a build nova
dominar os usuários ativos — em vez de empurrar no dia do release. Isso transforma o 78/50 num
resíduo pequeno.

**Nada disto está autorizado a mim:** commit, push e `db push` são do fundador (HANDOFF §15 e a
instrução desta tarefa). Registro o caminho e o gate; não executo.

### Decisão 5 — `golden_set` / R5 — **DECIDIDA (26/07): popular com 5–10 CVs**

> **Fundador, 26/07:** saída (a) — popular o corpus com 5 a 10 currículos.

**Fase própria, fora desta rodada** (nenhuma das seis fatias toca o motor de adaptação). Fica
registrada com os requisitos que a tornam útil de verdade, para quando for executada:

1. **≥2 dos CVs precisam ter ZERO skills** — é o caso que produziu o Bloqueador C e que hoje
   nenhum teste cobre.
2. **Apontar os scripts para o motor certo.** Hoje os 3 scripts chamam `extract-profile`, não
   `adapt-resume-to-job`. Popular o corpus sem corrigir o alvo continua não medindo a adaptação.
3. **Fazer o corpus vazio FALHAR.** Hoje corpus vazio sai exit 0 — "limpo" é indistinguível de
   "não havia nada". Sem isso, o corpus pode esvaziar de novo sem ninguém perceber.
4. **Ligar em algum lugar automático.** Nenhum script ou job de CI invoca `golden_set/` hoje;
   povoar sem ligar mantém a regra dependente de disciplina humana.
5. ⚠️ **LGPD:** o texto original dizia "CVs reais anonimizados". Recomendo **CVs sintéticos**
   ou anonimização verificada — puxar arquivos reais de usuários do Storage de produção para
   virar corpus de teste versionado no repositório é tratamento de dado pessoal com finalidade
   nova. Não faço isso sem decisão explícita e registrada.
6. **`adapt-resume-to-job` também está excluído do `check_functions_types.sh`**, e o script só
   varre `*/index.ts` — então `v2.ts` (2.155 linhas) não teria type-check nem depois do corpus.

**Enquanto os 6 itens acima não estiverem feitos, o motor de adaptação segue sem rede** e
qualquer fatia que toque `v2.ts` continua parada.

### Decisão 6 — F1: flag, fallback e acentos — **DECIDIDA (26/07)**

> **Fundador, 26/07:** **sem flag**, fallback **`curriculo.pdf`**, **sem acentos**
> (ASCII-folded). Requisito adicional: *"não quero nome do e-mail privado da Apple"*, e
> cuidado máximo para não quebrar nada.

**O requisito do e-mail vira invariante testada, não confiança.** A casa já tem a política:
`ContactEmail` (`lib/core/utils/contact_email.dart`) cobre
`privaterelay.appleid.com`, `private.icloud.com` (`isApplePrivateRelay`, `:30`) e o e-mail
sintético do login por telefone `phone_*@stage.app` (`isSyntheticAuthEmail`, `:33`), com o
combinado `isPrivateOrSynthetic` (`:41`) e a defesa de última linha `resumeValueOrEmpty` (`:50`,
documentada como *"para saídas públicas, como currículos"*). **Reuso essa política — não invento
outra.**

Regra do `ResumeFilename`: **nenhum candidato que contenha `@` pode virar nome de arquivo**, e
qualquer candidato reprovado por `ContactEmail.isPrivateOrSynthetic` é descartado antes do
fallback. Isso é mais estrito que o pedido e cobre os três vazamentos possíveis de uma vez.

**Por que isso importa mais do que parecia — medido em prod (26/07):**

| | |
|---|---|
| Usuários com `user_profiles.name = ''` | **110** |
| Destes, que entraram por **login por telefone** | **109 (99%)** |
| Usuários com e-mail sintético `phone_*@stage.app` | 110 |
| Usuários com e-mail Apple relay | 345 |
| `name` contendo `@` | **1** |
| `first_name`/`last_name` contendo `@` ou relay | **0** |

O risco vivo **não é o alias da Apple** — é o **e-mail sintético do telefone**. Se qualquer
caminho derivasse nome a partir do e-mail, essas 109 pessoas ganhariam um PDF chamado
`curriculo_phone_5511999...pdf` — **o número de telefone delas no nome do arquivo que anexam
numa vaga**. É a mesma classe de vazamento que o fundador pediu para evitar, só que pior e já
presente na base. A regra acima o impede por construção.

**A hipótese do fundador ("são usuários antigos de quando o app não estava 100%") não se
confirma.** Distribuição por mês de cadastro dos 110: maio **15**, junho **91**, julho **4**.
É um **pico concentrado em junho**, não decaimento legado — e correlaciona com o login por
telefone (ver [[phone_signup_synthetic]]). Isso reforça a decisão 7 e aponta onde investigar.

**Sem flag:** precedente direto — `ContactEmail` é aplicado incondicionalmente em
`pdf_service.dart:185`. A mudança é **monotônica**: onde já havia nome, o filename não muda.

### Decisão 7 (fora desta rodada) — B2, a causa-raiz do nome vazio — **agora com causa identificada**

F1 conserta o **sintoma** no filename. A causa-raiz ficou muito mais nítida com as queries de
26/07: **109 dos 110 usuários sem nome entraram por login por telefone** (99% de sobreposição),
e **91 dos 110 se cadastraram em junho**. Não é decaimento legado — é o fluxo de cadastro por
telefone não capturando nome, concentrado numa janela.

Isso muda o alvo da investigação: não é "o onboarding grava em `profile_personal` e esquece
`user_profiles`" em geral, é **especificamente o caminho de telefone** (ver
[[phone_signup_synthetic]] — o workaround do e-mail sintético enquanto o Twilio não está
configurado).

Autoriza abrir fatia separada para: (a) auditar o cadastro por telefone e fazer ele capturar
nome; (b) backfill dos 109 a partir de `profile_personal.first_name` (100 dos 110 já têm)?
Ambos exigem **migration em prod**, hoje proibida por esta tarefa.

---

## 5. O que NÃO entra nesta rodada

| Item | Por quê |
|---|---|
| **Qualquer mudança em `v2.ts`, prompt ou validador anti-invenção** | Aciona R5, que **não mede nada** (§1.5.3), com `adapt_v2_enabled` a 100% em prod e o adapt excluído do `deno check` do CI. É o único movimento da lista capaz de transformar 745 usuários bloqueados em toda a base quebrada. |
| **Aplicar migration, deployar Edge, mudar flag, commit/push/PR** | Decisão do fundador (HANDOFF §15). `trilha_assist_v1` continua OFF/0. |
| **`ProfileEditorViewModel`/`ProfileViewModel` assinarem `ProfileEvents`** | Fecha a classe inteira do bug, mas vale sem flag em prod e cruza onboarding/optimistic update. Depende da decisão 3; se aprovado, vira fatia própria — não é remendo dentro da F3. |
| **Reescrever `trilha_writeback.dart` para cada writer emitir** | Diff por ~25 escritores num arquivo de 980 linhas de falha silenciosa. O seam único da F3 entrega o mesmo resultado por 1 linha. Fica como fatia 2, guiada por telemetria. |
| **Refactor de Provider/Navigator** | R6. Nenhuma fatia precisa. |
| **Os ~627 lints preexistentes / `dart format` em legado** | Proibido explicitamente. (Registro: o CI já roda `--no-fatal-infos`, então eles não travam nada.) |
| **B3, B7, E2, D7, B6** | **Refutados** (§1.4 itens 3–7): não são defeitos do nosso código, ou o mecanismo alegado não existe. Consertar seria trabalho sobre ficção. |
| **Mover "Onde você mora" de Objetivos para Dados** | É mudança de contrato de UI (§2 do handoff), não correção de bug. Backlog. |
| **F4.6, F5.4/F5.5, fatias F6.1–F6.4** | Fases próprias, autorização própria. |
| **`PendingAdaptedCvTracker` / `requestOpenAdaptSheet` (código morto)** | Confirmados mortos, mas remoção é Fase 8 (retirada do legado). Legacy congela, não deleta (R6). |
| **Popular o `golden_set/`** | Trabalho legítimo e necessário, fase própria — ver decisão 5. |

---

## 6. Backlog priorizado (seções 4–5 e 8–12 — **não** é escopo desta rodada)

Ordenado por dano × custo, com o mecanismo já aterrado no código e os itens refutados removidos.

### 6.1 Visível em produção hoje

`applications_tracker_v1` está **ON/100**, então C1–C5 valem no instante em que a build 2.5.0 for
liberada.

| # | Achado | Local | Custo |
|---|---|---|---|
| **C1** | O app nunca segue o item para o novo segmento. `_selectedSegment` é escrito em **um** lugar só: o tap na pílula. Nem adicionar nem mudar status reposiciona | `liked_jobs_screen.dart:45,442,615` | baixo |
| **B5** | **Pior que o relatado:** não existe tela de login. `signIn` tem **um** chamador em todo o `lib/` — o próprio `catch` de `signUp`. Toda entrada passa por tentar cadastro | `user_viewmodel.dart:559,578,584` | médio |
| **SEC.12-1** | `clearPendingApply()` incondicional + erro engolido no "Sim, me candidatei" | `home_screen.dart:364,372` + `jobs_viewmodel.dart:1588` | baixo |
| **C5** | Selo `manual` cru (literal hardcoded, não enum) | `manual_application_card.dart:90` | 1 linha |
| **C3** | Os 4 segmentos não aparecem com lista vazia — `_buildBody` faz early-return do empty-state **antes** de checar a flag | `liked_jobs_screen.dart:341,347,357` | baixo |
| **C2** | Empty-state com vocabulário da aba "Salvas" antiga | `liked_jobs_screen.dart:783,843,867` | baixo |
| **C4** | Régua de segmentos corta sem fade nem indício de rolagem | `tracker_segment_bar.dart:24,29` | baixo |
| **D4** | CTA "Baixar PDF" em `brandCyan` (#29B6D2) enquanto o primário é #1565A8 | `adapted_resume_preview_screen.dart:1790` | 1 linha |
| **D5** | "Você pode adicionar mais 6" ao lado de `0/12` — imprime `recommendedMin - count` colado num denominador que é o teto | `edit_list_modal.dart:429` | baixo |
| **D6** | `+` vs lápis para seções vazias — a divisão é por tipo de editor, não por estado | `profile_section_list.dart:671,108,213` | médio |
| **SEC.5** | "Continuar" habilitado com 1 caractere (as duas telas) | `first_name_screen.dart:73`, `last_name_screen.dart:73` | 2 linhas |
| **SEC.12-2** | `onSave` é `void Function(...)`, não `Future` — **impossível** esperar por tipo; o `pop()` sempre corre antes | `add_edit_experience_modal.dart:22,150` (+ educação, projeto, idioma) | médio |

### 6.2 Só com `trilha_assist_v1` ON

| # | Achado | Local |
|---|---|---|
| **D2** | A folha de extras oferece skills que o usuário já tem. **Causa-raiz maior que "não filtra":** o flag `in_cv` vem de `extract-job-skills`, que lê **só as fontes legadas** | `extract-job-skills/index.ts:311,319,448` |
| **B4** | `profileHasContent` é um OR de 9 fontes: **uma** educação de ensino médio já libera exportar | `general_resume_export.dart:86,120` |
| **E4** | Handoff abrupto entre abas no "Importar currículo", sem frase de transição nem volta | `imported_source_card.dart:150,290` |
| **E3** | "Excel Avançado" entra como skill nova ao lado de "Excel" — duplicata semântica classificada como `novo` | fluxo de conflitos |
| **D3** | Card da biblioteca trunca o título. **O dado não está perdido** — o título já traz vaga + empresa; é `maxLines:1` + prefixo constante de 14 chars | `profile_screen.dart:1256` |
| — | Coach-mark cobre a 5ª opção do seletor; duas entradas de texto simultâneas; três balões redundantes; chip primário errado para perfil vazio | §5 do relatório |

### 6.3 Achados novos da auditoria (não estavam no relatório)

| Sev. | Achado |
|---|---|
| alta | **A retrocompatibilidade da F4.5 foi analisada só num sentido** ("build antigo + DB novo"). A combinação quebrada é a inversa — é o Bloqueador B. O plano nunca foi corrigido. |
| alta | **R5 não é aplicada por nada automático:** além do corpus vazio, nenhum script ou job de CI invoca `golden_set/`. |
| média | A query da F6.0 removeu o `.limit(1)` **sem** pôr outro limite: a aba "Original" agora baixa todas as linhas de `saved_resumes` do usuário. Seguro hoje (máx. medido: 10 candidatos/usuário), mas sem teto. |
| média | Drift documental entre os três planos irmãos sobre o mesmo manifest (F4 projeta 125, F5 nega migration nova, F6 parte de 126; o real é 126). |
| baixa | Comentário enganoso em `_kOutputSources` sugere precedência por grupo; o código só usa `contains` + recência. |

---

## 7. Validação por fatia

Ao fim de **cada** fatia: `flutter test` completo + focados novos; `flutter analyze
--no-fatal-warnings` (**0 errors**, sem lint novo); `git diff --check`; `check_env_safety.sh`.
Nenhuma fatia toca SQL, então os harnesses PG não são exigidos — se alguma passar a tocar, rodar
`run_fase3_sql_test.sh` e `run_profile_guided_write_foundation_test.sh` com
`PATH=/opt/homebrew/opt/postgresql@17/bin:$PATH` + `check_migrations_manifest.sh`.

Baseline a preservar: **782 testes** (com a ressalva de flake do §1.5.1), **627 issues / 0 errors**,
manifest **126**. Sem `dart format` em arquivo legado.

## 8. Condições de parada

Parar e pedir decisão se: a correção da invalidação exigir refactor de Provider/Navigator (R6);
a correção do Bloqueador B implicar alterar migration já aplicada remotamente; qualquer fatia
precisar tocar prompt, validador ou caminho coberto por R5; o hook da F3 provocar loop ou refetch
de feed além do previsto na decisão 3; ou surgir necessidade de ligar flag, deployar ou aplicar
migration.

---

---

## 9. Execução — resultados medidos

### F2 e F1 — FEITAS (26/07)

**Gate completo, medido (não declarado):**

| Verificação | Baseline | Depois | Veredito |
|---|---|---|---|
| `flutter test` | 782 | **814** (`All tests passed!`) | +32 = exatamente os testes novos; **0 regressões** |
| `flutter analyze --no-fatal-warnings` | 627 issues / 0 errors | **627 issues / 0 errors** | **nenhum lint novo** |
| `git diff --check` | limpo | limpo | ok |
| branch / HEAD | `refactor/ia-fase-2-fechamento` / `b66c24c` | idem | intactos |

**F2 — `_isEditable` tolerante** (10 testes)
- Novo: `lib/core/utils/trail_resume.dart` — `kTrailResumeTitlePrefix` + `isTrailResume`.
- `resume_detail_screen.dart:118` passa a chamar a função pura.
- `ResumeViewModel.kTrailResumeBaseTitle` passa a **referenciar** a constante nova —
  fonte única, sem literal duplicado. Um teste trava essa igualdade: se alguém mudar o título
  gerado sem mudar o predicado, o teste quebra em vez de a ponte legada falhar em silêncio.
- Teste de **paridade com produção**: para as 5 formas de linha que existem hoje em prod, o
  predicado novo devolve exatamente o mesmo que o predicado antigo (`title.startsWith`).
- Testes provam que `imported`/`adapted`/`general` com o prefixo **não** viram editáveis.

**F1 — nome do arquivo** (22 testes)
- Novo: `lib/core/utils/resume_filename.dart` — `ResumeFilename.build`, função pura.
- Aplicado nos 2 call sites: `general_resume_export.dart` e
  `adapted_resume_preview_screen.dart`. Ambos passam `preferredName` = o nome que já vai
  **impresso dentro** do PDF (`resume.fullName` / `_current.fullName`), com `user.name` como
  segunda opção — alinhado ao que o `PdfService` já fazia para o corpo do documento.
- **Guarda-corpo do e-mail (decisão 6), testado:** e-mail sintético `phone_*@stage.app`,
  alias `privaterelay.appleid.com`, `private.icloud.com` e qualquer string com `@` são
  descartados antes do fallback. Teste explícito garante que o telefone **não** aparece no
  nome do arquivo.
- Sem acento (`José Antônio` → `Jose_Antonio`), fallback `curriculo.pdf`, sem flag.
- **Monotonicidade provada por teste:** para nome ASCII, a saída é idêntica à fórmula antiga.
- Underscore duplo eliminado: sem nome + sufixo agora dá `curriculo_1eee2f.pdf`.

**Nada de commit, push, deploy, migration ou flag.** Working tree: 43 → 48 entradas
(4 arquivos novos + `resume_viewmodel.dart` que passou a ser modificado). Todo o trabalho
preexistente preservado.

### F5, F3, F4 e F6 — FEITAS (26/07)

**Gate completo, medido ao fim das seis fatias:**

| Verificação | Baseline | Depois | Veredito |
|---|---|---|---|
| `flutter test` | 782 | **849** (`All tests passed!`) | +67 = exatamente os testes novos; **0 regressões** |
| `flutter analyze --no-fatal-warnings` | 627 / 0 errors | **627 / 0 errors** | **nenhum lint novo** |
| `check_env_safety.sh` | OK | **OK** | ok |
| `check_migrations_manifest.sh` | OK (126) | **OK (126)** | nenhuma migration nova |
| `git diff --check` | limpo | limpo | ok |
| branch / HEAD | `refactor/ia-fase-2-fechamento` / `b66c24c` | idem | intactos |

**F5 — falha honesta da adaptação** (13 testes)
- **A causa do vazamento estava no `AIService`, não no widget.** `ai_service.dart:241` fazia
  `throw ResumeAdaptationException('network', e.toString())`, e a sheet renderiza `message`
  literalmente — daí `ClientException: … uri=https://<project>.supabase.co/…` na tela.
  Corrigido na origem (detalhe técnico vai para log), e o mesmo em mais **dois** pontos que
  vazavam jargão (`FormatException` e erro de parse).
- Novo `lib/features/jobs/utils/adaptation_error_copy.dart`: função pura que decide título,
  mensagem e botões, com **segunda barreira** — texto do servidor com `http`, `uri=`,
  `Exception`, stack ou JSON **nunca** chega à tela, mesmo que um caminho novo da Edge passe
  a mandá-lo.
- **Desvio registrado:** a copy "não passou na verificação de integridade" vem da **Edge**
  (`v2.ts:2023`), não do client — o `_humanizeError` local era dead code nesse caminho.
  Mudar lá exigiria tocar a Edge do adapt (R5, sem rede). **A UI passou a ser dona da própria
  copy**, ignorando o `detail` do servidor para `adaptation_rejected`.
- `canRetry` deixou de ser "tudo que não é profile_incomplete/rate_limited": agora é por
  código, e falha determinística não oferece retry.

**F3 — invalidação da coleta guiada** (3 testes)
- Uma linha em `trilha_chat_controller.dart`, no fim de `_doSubmit`, **depois** dos dois guards
  que já existiam (write falhou / conversa não avançou). Reusa `onProfileEdited`, que o host já
  passava.
- **Sem gate de flag** (decisão 3). Teste prova que write-back que falha **não** invalida —
  falha nunca vira falso sucesso.

**F4 — card "Fonte importada"** (4 testes)
- Canal novo `onDocumentsChanged` no controller + `_scheduleDocumentsReload` no host, ligado a
  `ProfileViewModel.loadSavedResumes()`.
- **Canal separado de `onProfileEdited` de propósito** — documentos e fatos invalidam em
  frequências diferentes. Teste prova que responder um passo da coleta **não** recarrega a
  biblioteca (senão cada resposta viraria um fetch desnecessário).
- Testes cobrem import ok / falho / cancelado.

**F6 — gate exige 3 habilidades** (15 testes)
- Novo `lib/features/jobs/utils/adapt_gate.dart` — função pura com as três faixas.
- `UserViewModel` passa a expor `skillCount`, carregado no mesmo ponto que `canAdaptCv`, e
  **zerado nos três pontos de reset** (uid nulo, falha de carga, signOut) para não sobrar
  contagem obsoleta.
- **Ordem corrigida (§5 do device-test):** o gate agora roda em `jobs_swipe_screen`
  **antes** da folha "Algo que esqueceu de mencionar?". Quem está barrado não escolhe mais
  habilidades para uma adaptação que não vai rodar.
- `missingMaterial` mantém o código `profile_incomplete` (não quebra a série de analytics que
  sustentou o diagnóstico dos 63%); `missingSkills` é código novo.
- Copy diferenciada para a faixa 1–2 ("Você já tem 1. Adicione mais 2 habilidades…"), com
  plural correto — quem já começou não é tratado como quem tem zero.

### Device-test das correções (26/07, iPhone 17 Pro · build debug · Supabase de PRODUÇÃO)

Conta de teste `187ed041-…`, sessão já ativa (nenhuma senha digitada). Flags inalteradas
(`trilha_assist_v1` OFF/0, `trilha_coleta_v1` ON/100). Nenhuma migration aplicada.

| Fatia | Resultado |
|---|---|
| **F1** | ✅ **PROVADA no caso exato do bug.** A conta tem `user_profiles.name = ''`. O share sheet do CV adaptado mostrou **`curriculo_Zac_Teste_silva_1eee2f`** (84 KB). Era `curriculo__1eee2f.pdf` — **mesma vaga, mesmo sufixo `1eee2f`** do relatório original. Nome recuperado via `resume.fullName`, underscore duplo eliminado. |
| **F6 (liberado)** | ✅ Com 7 skills o gate passa, a folha de extras abre e a adaptação roda: "6 ajustes aplicados", diff honesto. **Sem regressão.** |
| **F6 (barrado, 1–2)** | ✅ Com 2 skills: **a folha de extras NÃO abriu** (ordem corrigida). Tela: "Adicione suas habilidades" · *"Você já tem 2. Adicione mais 1 habilidade…"* — singular correto · **sem botão "Tentar de novo"** · CTA "Adicionar habilidades ao perfil" que leva ao Perfil. Instantâneo, não 25 s. |
| **F6 (barrado, 0)** | ✅ Com 0 skills: *"…Adicione pelo menos 3 habilidades ao seu perfil e eu cuido do resto."* Ramo correto, sem "Você já tem". |
| **F3** | ✅ **PROVADA.** Coleta guiada gravou 2 interesses (`profile_interests` 0 → 2, confirmado por SQL) e **Perfil → Dados mostrou "Interesses (2)" sem reiniciar o app e sem pull-to-refresh**. É exatamente o sintoma do Bloqueador A, invertido. |
| **F5** | ⚠️ **Parcial.** O caminho do gate (mensagem + CTA + ausência de retry) foi verificado junto com a F6. A falha de **rede** não foi forçada — ver abaixo. |
| **F2** | ❌ Não verificável em runtime (nenhum entry point vivo cria CV `trail`; a conta só tem CVs `adapted`). Segue coberta por código + banco + 10 testes. |
| **F4** | ❌ Não verificável (depende de `trilha_assist_v1`, que ficou OFF por decisão). Coberta por 4 testes de controller. |

**Por que a falha de rede (A3) não foi forçada — dito na cara:** as três formas de derrubar a
rede do simulador afetam o **host** (o simulador usa a pilha de rede do Mac): desligar o Wi-Fi
cortaria minha própria conexão com o Supabase e as ferramentas; editar `/etc/hosts` exige `sudo`
(senha) e é mudança de configuração de sistema; e `simctl status_bar` só troca o **ícone**, não a
conectividade. Preferi não fazer a ninguém acreditar que verifiquei algo que não verifiquei.
O vazamento segue coberto por teste que compara contra **a string crua exata** que apareceu no
device-test original (`ClientException: … uri=https://<projeto>.supabase.co/…`), e a correção foi
feita na origem (`ai_service.dart`) mais uma segunda barreira na função pura.

**Mutação de dados feita e desfeita:** as 7 skills foram removidas e **restauradas com fidelidade
total** — ids, nomes, categorias, `canonical_skill_id`, `order_index` e `created_at` idênticos ao
snapshot tirado antes (guardado em disco). Verificado por query após a restauração.
**Resíduos do teste, por ações normais de uso:** +2 interesses (Dados & IA, Sustentabilidade) e
+1 CV adaptado salvo na biblioteca. Ambos removíveis a pedido.

### Escopo tocado (contabilizado)

Working tree: 43 → **57** entradas. **8 arquivos novos** (4 de produção + 4 de teste) e
**9 arquivos** modificados por mim, dos quais 5 não estavam modificados antes.
Nenhuma migration, nenhuma Edge, nenhuma flag, nenhum refactor de Provider/Navigator.

---

**Estado (26/07):** **as seis fatias entregues e medidas.** Nada commitado, deployado ou
aplicado. Pendências do fundador: revisão, commit, release (com a F2 dentro,
obrigatoriamente) e, depois, o `db push` das três migrations juntas (caminho A).

**Decididas — 1, 2, 3 e 6.** Quatro fatias com escopo fechado e prontas para implementar
mediante aprovação:

| Fatia | Escopo fechado por |
|---|---|
| **F1** — nome do arquivo | decisão 6: sem flag, `curriculo.pdf`, sem acentos, nunca derivar de e-mail |
| **F2** — `_isEditable` tolerante | decisão 1: saída A + gatilho de remoção datado |
| **F3** — invalidação da coleta guiada | decisão 3: sem gate, recarregamentos aceitos |
| **F6** — gate do adapt | decisão 2: mínimo 3 habilidades + redirecionamento |

**F4** (card Fonte importada) e **F5** (falha honesta do adapt) nunca dependeram de decisão —
seguem o escopo do §2.

**Decisões 4 e 5 também respondidas**, ambas fora do caminho crítico desta rodada:

- **4** — desacoplar: **sim**, mas ⚠️ não executável direto (3 travas — ver §4 decisão 4).
  Precisa de uma escolha entre o caminho A (segurar tudo) e o B (neutralizar a 125), e de
  commit antes de qualquer push. **Nada disso é meu.**
- **5** — popular o `golden_set` com 5–10 CVs: **aprovado como fase própria**, com 6 requisitos
  registrados (incluindo ≥2 CVs sem skills, corrigir o alvo dos scripts, e a ressalva de LGPD).

**Única ainda aberta:**

| # | Pergunta | Natureza |
|---|---|---|
| **7** | Fatia separada para a causa-raiz do nome vazio — agora localizada no **cadastro por telefone** (109/110, pico em junho) | exige migration; fundador respondeu "não sei ainda" |

Nenhuma implementação começa sem aprovação explícita.
