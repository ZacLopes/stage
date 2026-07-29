# Golden Set — pipeline **adapt**

Bateria reguladora do `adapt-resume-to-job`. É a rede que a **R5** exige ao
encostar nesse pipeline.

```bash
bash scripts/run_golden_set_adapt.sh
```

Roda também em CI (job `golden-set-adapt`), em todo push.

---

## Por que este diretório existe

O `golden_set/` original (um nível acima) foi desenhado para o **`extract-profile`**
— PDFs de currículo → perfil estruturado. A R5, porém, fala do pipeline **adapt**.
Eram coisas diferentes, e a do adapt não existia.

Pior: `cvs/`, `ground_truth/` e `outputs/` estavam **vazios** e nenhum script ou
job de CI os invocava. Na prática, "golden set limpo" era indistinguível de
"não havia nada para rodar" — a regra existia no papel, a proteção não.

Esta pasta cobre o adapt. A do extract-profile continua vazia e continua sendo
dívida em aberto (ver `../README.md`).

---

## O que ela protege

`validateAdaptationV2` — a barreira anti-invenção entre a resposta do modelo e o
PDF que o recrutador lê. Cada caso é um par **(input do candidato, resposta
hipotética do modelo)** mais o veredito esperado.

**Duas direções, ambas obrigatórias:**

| Direção | Pega o quê | Se quebrar |
|---|---|---|
| casos `rejeita` (`adv-*`) | validador ficando **frouxo** | invenção chega ao currículo do candidato |
| casos `aceita` (`ok-*`) | validador ficando **estrito demais** | usuário legítimo fica sem currículo (foi o BLOQUEADOR C) |

Só a primeira direção não bastaria: um validador que rejeita tudo passaria em
todos os casos adversariais.

## O que ela **não** cobre

Qualidade de escrita do modelo. Saber se os bullets ficaram melhores ou piores
exige rodada real contra a OpenAI e julgamento humano. Esta bateria é
determinística, offline e de graça — por isso roda em CI. Não confunda "18/18
verde" com "a adaptação está boa".

---

## Como adicionar um caso

Crie um JSON em `cases/`. O runner preenche o resto: o **input** parte de um
perfil-base e o **candidate** parte de uma cópia fiel do input. Você só escreve
o que o caso exercita.

```json
{
  "id": "adv-013-descreva-aqui",
  "adversarial": true,
  "categoria": "anti-invenção / skills",
  "porque": "Explique o DANO ao usuário, não o mecanismo. Este campo é o que faz alguém entender o caso daqui a 6 meses.",
  "adicionado_em": "2026-07-28",
  "input":     { "skills": ["Excel"] },
  "candidate": { "skills": ["Excel", "Python"] },
  "espera": {
    "resultado": "rejeita",
    "campo": "skills",
    "mensagem_contem": "skill inventada"
  }
}
```

- `input` — partial de `InputResumeV2`.
- `candidate` — partial de `resume` (a resposta do modelo).
- `extraSkills` — extras confirmadas pela pessoa na folha "Algo que esqueceu de
  mencionar?". Abrem *slots de tradução* na checagem de skills.
- `espera.campo` e `espera.mensagem_contem` são opcionais, mas **use**: sem eles
  o caso passa por rejeição acidental, pelo motivo errado.

### Quando adicionar

1. Bug de invenção visto em produção → vira caso adversarial, com o texto real.
2. Nova checagem no validador → um caso `rejeita` **e** um `aceita` que a
   exercitem.
3. Alguém reclamou de `adaptation_rejected` indevido → vira caso `aceita`.

---

## Prova de que a bateria mede algo

Verde na primeira rodada não prova nada — já houve teste vazio neste repo
passando verde. Estes dois mutantes foram aplicados ao `v2.ts` e revertidos
(28/07/2026):

| Mutação | Resultado esperado | Observado |
|---|---|---|
| desligar a checagem 8 (`return` no topo) | adversariais de summary quebram | **3 [ADV] falharam**, saída bloqueante |
| neutralizar o contexto de busca (`if (false && ...)`) | caso legítimo quebra | **`ok-002` falhou** ("buscando experiência em") |

Repita isso ao mexer no validador: se a bateria continua verde com o validador
quebrado, ela não está medindo o que você acha.

---

## Estado atual

18 casos — 12 adversariais, 6 de linha de base. Cobrem: identidade, experiences
(contagem e empresa), bullets (`kept`/`rewritten`/`synthesized` + keywordPool),
education (majors), skills (invenção e slot de tradução), tools, languages,
contato (linkedin) e summary (alegação de experiência inexistente).
