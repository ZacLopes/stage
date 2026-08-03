# Golden Set — extract-profile

> ⚠️ **Estado real (28/07/2026): este corpus está VAZIO.** `cvs/`,
> `ground_truth/` e `outputs/` não têm um único arquivo, e nenhum script ou job
> de CI invoca os scripts daqui. Rodar isto hoje sai com sucesso **porque não há
> nada para rodar** — "golden set limpo" não distingue "passou" de "vazio".
> Tratar como dívida em aberto, não como proteção existente.
>
> 🔗 **A R5 fala do pipeline `adapt`, que é outro.** A bateria do adapt existe,
> está populada e roda em CI: [`adapt/`](adapt/README.md) —
> `bash scripts/run_golden_set_adapt.sh`.
>
> Este arquivo descreve a bateria do **extract-profile** (PDF → perfil), que
> ainda precisa ser construída. O texto abaixo é o desenho pretendido.

Conjunto regulador de qualidade do extrator de currículos. Cada vez que o
prompt de `extract-profile` muda (`PROFILE_SYSTEM_PROMPT`) ou o schema é
ajustado (`PROFILE_JSON_SCHEMA`), rode o golden set e veja se a qualidade
piorou — antes de fazer deploy.

## Estrutura

```
golden_set/
  README.md                  # este arquivo
  cvs/                       # PDFs reais anonimizados (cv_001.pdf, cv_002.pdf, ...)
  ground_truth/              # JSON esperado por CV (cv_001.json, ...)
  outputs/                   # JSON gerado pelo run_extraction.ts (.gitignore)
  scripts/
    run_extraction.ts        # roda extract-profile pra cada PDF, salva outputs/
    compare.ts               # diff outputs/ vs ground_truth/, relatório
    bootstrap_ground_truth.ts # gera template inicial pra humano revisar
                             # (NÃO usar em CVs marcados adversarial: true)
```

## Composição alvo (fim da Semana 1)

| Tipo | Quantidade | Origem do ground truth |
|---|---|---|
| **Adversarial** | 5-10 CVs | **100% manual**, sem ver output da IA. Casos difíceis: multi-coluna, datas ambíguas, nomes compostos, OCR ruim, idioma misto. Detector de regressão real. |
| **Bootstrap-assisted** | 15-20 CVs | Template inicial via `bootstrap_ground_truth.ts` + revisão humana criteriosa. Cobertura ampla. |
| **Total** | 20-30 CVs | — |

### Por que adversariais 100% manuais?

`bootstrap_ground_truth.ts` chama o próprio extract-profile pra gerar um
template — viés de auto-validação. Se o modelo erra consistentemente em
um tipo de CV, esse erro vai pra ambos (output e "ground truth"), e
`compare.ts` não detecta nada.

Os CVs adversariais existem pra romper esse ciclo: o humano cria o JSON
esperado SEM ver o que o modelo gerou, e depois compara. **São esses
CVs que detectam regressão real quando ajustamos o prompt.**

## Lista de CVs adversariais

Marque cada CV adversarial nesta seção. Pull request que altera ground
truth de CV adversarial **deve ser revisado por outra pessoa** (não
auto-aprovar).

| ID | Categoria | Por que adversarial | Adicionado em |
|---|---|---|---|
| _(ex: cv_001)_ | _(ex: multi-coluna densa)_ | _(ex: vision falhou historicamente nesta classe)_ | _(2026-05-DD)_ |

## Como rodar

### Preparar `.env`

Na raiz do projeto Flutter (`career_gamification/.env`), garanta:
```
SUPABASE_URL=https://<ref>.supabase.co
SUPABASE_SERVICE_ROLE_KEY=<service_role_key>
```

`.env` já está em [.gitignore](../.gitignore). **Não cole essas chaves em
PRs, issues ou Slack.** Após a Semana 1, rotacionar SERVICE_ROLE_KEY (vide
[docs/profile_architecture.md](../docs/profile_architecture.md) seção
"Operações").

### Executar extração

```bash
cd career_gamification/golden_set
deno run --allow-env --allow-net --allow-read --allow-write scripts/run_extraction.ts
```

Roda todos os PDFs em `cvs/` contra a edge function `extract-profile`
em modo `force: true` (ignora cache) com chamada service-role. Salva o
resultado em `outputs/cv_NNN_output.json`.

Custo aprox: ~$0.005 por CV. 30 CVs ≈ $0.15.

### Comparar e gerar relatório

```bash
deno run --allow-read scripts/compare.ts
```

Saída:
- Tabela: % campos corretos por seção (personal, experiences, education, ...)
- Confidence_global médio
- Top 5 padrões de erro sistemático
- **Pass/fail por CV adversarial** (qualquer fail é bloqueante)

## Quando atualizar o golden set

1. Subiu uma nova categoria no `PROFILE_JSON_SCHEMA` → adicione CVs que
   exercitam o novo campo
2. Detectou um bug em produção via `profile_extraction_logs` → adicione o
   CV (anonimizado) como adversarial
3. Bump de versão `CURRENT_EXTRACTOR_VERSION` em `extract-profile/index.ts` →
   rode o golden set ANTES de deploy

## Anonimização de PDFs

CVs reais contêm PII. Antes de commitar:
- Substitua nome próprio, email, telefone, endereço por valores plausíveis
  mas falsos
- Mantenha estrutura (datas, cargos, empresas, formação) — o que importa
  pro teste é o LAYOUT e a SEMÂNTICA, não o dado individual
- Use editor de PDF (ex: PDF.js, Acrobat) ou regenere via template
