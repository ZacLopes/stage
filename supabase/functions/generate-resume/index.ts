import { serve } from 'std/http/server'
import { createClient } from 'supabase'
import { trackAIGeneration, trackRateLimitHit, withEdgeAnalytics } from '../_shared/posthog.ts'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(withEdgeAnalytics('generate-resume', async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        const supabaseClient = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_ANON_KEY') ?? '',
            {
                global: {
                    headers: { Authorization: req.headers.get('Authorization')! },
                },
            }
        )

        const { data: { user }, error: authError } = await supabaseClient.auth.getUser()

        if (authError || !user) {
            return new Response(
                JSON.stringify({ error: 'Unauthorized' }),
                { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // Rate limit diário por usuário (Fase 0 T0.2, ref. auditoria L3 #1).
        // O count usa ai_generation_logs, cujo INSERT acontece PÓS-sucesso
        // (mais abaixo) — falha de geração não consome cota. O SELECT roda
        // sob o JWT do user e passa pela policy "Users can view own
        // generation logs" (auth.uid() = user_id).
        // Configurável sem redeploy via secret RESUME_RATE_LIMIT_PER_DAY
        // (default 10) — também é o mecanismo de teste do 429.
        const rateLimit = Number(Deno.env.get('RESUME_RATE_LIMIT_PER_DAY') ?? '10')
        const today = new Date()
        today.setHours(0, 0, 0, 0)
        const { count: usedToday } = await supabaseClient
            .from('ai_generation_logs')
            .select('*', { count: 'exact', head: true })
            .eq('user_id', user.id)
            .eq('generation_type', 'resume')
            .gte('created_at', today.toISOString())
        if (rateLimit > 0 && (usedToday ?? 0) >= rateLimit) {
            trackRateLimitHit({
                distinctId: user.id,
                functionName: 'generate-resume',
                limitType: 'daily_per_user',
                limit: rateLimit,
            }).catch(() => {})
            return new Response(
                JSON.stringify({ error: 'rate_limit_exceeded', limit: rateLimit }),
                { status: 429, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        const { answersWithQuestions, areaContext, language } = await req.json()

        if (!answersWithQuestions || typeof answersWithQuestions !== 'object') {
            return new Response(
                JSON.stringify({ error: 'Invalid request body' }),
                { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        const targetRoleQuestion = 'Para qual vaga, cargo ou área específica você quer direcionar seu currículo agora? (Ex: Estágio em Direito Civil, Analista de Marketing Jr)'
        const isEnglish = language === 'en' || language === 'en-US'
        const targetRoleFallback = isEnglish ? 'an Internship or Entry-Level Position' : 'Estágio ou Primeiro Emprego'
        const targetRole = answersWithQuestions[targetRoleQuestion] || targetRoleFallback
        const prompt = buildResumePrompt(answersWithQuestions, areaContext, isEnglish)

        const systemPrompt = isEnglish
            ? buildEnglishSystemPrompt(targetRole, areaContext)
            : buildPortugueseSystemPrompt(targetRole, areaContext)


        const aiStart = Date.now()
        const openaiResponse = await fetch('https://api.openai.com/v1/chat/completions', {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${Deno.env.get('OPENAI_API_KEY')}`,
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                model: 'gpt-4o',
                messages: [
                    { role: 'system', content: systemPrompt },
                    { role: 'user', content: prompt }
                ],
                temperature: 0.5,
                max_tokens: 1500,
            })
        })

        if (!openaiResponse.ok) {
            trackAIGeneration({
                userId: user.id,
                generationType: 'resume_generation',
                model: 'gpt-4o',
                inputTokens: 0,
                outputTokens: 0,
                latencyMs: Date.now() - aiStart,
                isError: true,
            }).catch(() => {})
            throw new Error(`OpenAI API error: ${openaiResponse.statusText}`)
        }

        const openaiData = await openaiResponse.json()
        trackAIGeneration({
            userId: user.id,
            generationType: 'resume_generation',
            model: 'gpt-4o',
            inputTokens: openaiData.usage?.prompt_tokens ?? 0,
            outputTokens: openaiData.usage?.completion_tokens ?? 0,
            latencyMs: Date.now() - aiStart,
        }).catch(() => {})
        const responseText = openaiData.choices[0].message.content

        let jsonText = responseText.trim()
        if (jsonText.startsWith('```json')) jsonText = jsonText.substring(7)
        if (jsonText.startsWith('```')) jsonText = jsonText.substring(3)
        if (jsonText.endsWith('```')) jsonText = jsonText.substring(0, jsonText.length - 3)
        jsonText = jsonText.trim()

        const result = JSON.parse(jsonText)

        await supabaseClient.from('ai_generation_logs').insert({
            user_id: user.id,
            generation_type: 'resume',
            tokens_used: openaiData.usage?.total_tokens || 0,
        })

        return new Response(
            JSON.stringify(result),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )

    } catch (error) {
        console.error('Error:', error)
        return new Response(
            JSON.stringify({ error: error.message || 'Internal server error' }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    }
}))

function buildResumePrompt(
    answersWithQuestions: Record<string, string>,
    areaContext?: string,
    isEnglish: boolean = false,
): string {
    if (Object.keys(answersWithQuestions).length === 0) {
        return isEnglish
            ? 'The user has not answered any questions yet. Return placeholder messages for all sections.'
            : 'O usuário ainda não respondeu nenhuma pergunta. Retorne mensagens de placeholder para todas as seções.'
    }

    let prompt = isEnglish
        ? 'Here are the user\'s answers about their career and education (raw data is in Brazilian Portuguese — translate everything to natural English in the output):\n\n'
        : 'Aqui estão as respostas do usuário sobre sua carreira e formação:\n\n'

    for (const [question, answer] of Object.entries(answersWithQuestions)) {
        prompt += isEnglish
            ? `Question: ${question}\nAnswer: ${formatAnswer(answer)}\n\n`
            : `Pergunta: ${question}\nResposta: ${formatAnswer(answer)}\n\n`
    }

    if (isEnglish) {
        prompt += 'Generate the structured resume in ENGLISH following the system prompt rules. '
        prompt += 'Keep all JSON keys in Portuguese (e.g. "resumo_profissional", "experiencias") for backward compatibility, '
        prompt += 'but write all VALUES in natural North-American English.'
    } else {
        prompt += 'Com base nessas respostas, gere um currículo profissional estruturado.\n'
        prompt += 'Lembre-se: se não houver informação para alguma seção, use a mensagem de placeholder especificada.'
    }

    return prompt
}

function buildPortugueseSystemPrompt(targetRole: string, areaContext?: string): string {
    return `Você é um ghostwriter especializado em currículos no padrão Harvard Career Services (MCS), escrevendo em PORTUGUÊS BRASILEIRO para um estudante universitário.

VAGA / ÁREA-ALVO: "${targetRole}"
${areaContext ? `CONTEXTO DA ÁREA: ${areaContext}` : ''}

═══════════════════════════════════════════════════════════════════
PRINCÍPIOS HARVARD (rege tudo)
═══════════════════════════════════════════════════════════════════
1. ESPECÍFICO em vez de genérico
2. ATIVO em vez de passivo
3. EXPRESSAR e não impressionar (sem floreio)
4. ARTICULADO e não floreado
5. BASEADO EM FATOS — quantificar e qualificar
6. SCANEÁVEL — humanos e ATS leem em 6 segundos

═══════════════════════════════════════════════════════════════════
REGRAS LINGUÍSTICAS (não-negociáveis)
═══════════════════════════════════════════════════════════════════
- USE primeira pessoa IMPLÍCITA — verbos no pretérito perfeito SEM "eu" / "meu" / "nós"
  ✅ "Liderei equipe de 8 pessoas..."
  ❌ "Eu liderei...", "Sou responsável por...", "O candidato liderou..."
- NUNCA usar voz passiva ("Foi responsável por", "Esteve envolvido em")
- NUNCA narrar ("Durante minha jornada", "Ao longo do tempo")
- NUNCA abreviar (use "Universidade", não "Univ.")
- NUNCA incluir foto, idade, gênero, estado civil, salário, referências

═══════════════════════════════════════════════════════════════════
VERBOS DE AÇÃO PERMITIDOS (use SEMPRE no início do bullet)
═══════════════════════════════════════════════════════════════════
LIDERANÇA: Liderei, Coordenei, Dirigi, Geri, Supervisionei, Orquestrei, Encabecei, Presidi, Conduzi, Estabeleci, Priorizei, Deleguei, Recomendei, Avaliei
COMUNICAÇÃO: Apresentei, Negociei, Mediei, Redigi, Editei, Traduzi, Persuadi, Promovi, Recrutei, Convenci, Articulei
PESQUISA / ANÁLISE: Investiguei, Analisei, Identifiquei, Avaliei, Diagnostiquei, Mapeei, Examinei, Sintetizei, Modelei, Validei
TÉCNICO / CONSTRUÇÃO: Construí, Projetei, Implementei, Otimizei, Padronizei, Programei, Automatizei, Engenhei, Reformulei, Atualizei
QUANTITATIVO: Calculei, Orçamentei, Maximizei, Minimizei, Auditei, Quantifiquei, Reduzi, Cresci
CRIATIVO: Criei, Concebi, Fundei, Desenvolvi, Lancei, Originei, Visualizei
ORGANIZACIONAL: Organizei, Sistematizei, Centralizei, Categorizei, Compilei, Processei, Coletei

═══════════════════════════════════════════════════════════════════
VERBOS / EXPRESSÕES BANIDOS
═══════════════════════════════════════════════════════════════════
"Ajudei", "Auxiliei", "Trabalhei em", "Fui responsável por", "Tive a oportunidade de", "Estive envolvido em", "Participei de" (sozinho), "Fiz parte de"

CLICHÊS BANIDOS: "proativo", "dinâmico", "comunicativo", "perfil empreendedor", "foco em resultados", "habilidoso em", "apaixonado por", "team player", "hands-on", "líder nato", "automotivado"

═══════════════════════════════════════════════════════════════════
ESTRUTURA DE BULLETS (obrigatória)
═══════════════════════════════════════════════════════════════════
[VERBO FORTE no passado] + [O QUE FOI FEITO] + [ESCALA / ESCOPO] + [PROPÓSITO ou RESULTADO]

REGRA: NUNCA invente métricas. Se o usuário não deu número, NÃO insira número. Quando a resposta contém número, ele DEVE aparecer no bullet.

═══════════════════════════════════════════════════════════════════
CATEGORIZAÇÃO DAS EXPERIÊNCIAS (CRÍTICO)
═══════════════════════════════════════════════════════════════════
→ "experiencias": estágios, empregos CLT, freelance/PJ, fundadores com clientes/usuários
→ "lideranca": ligas, atléticas, voluntariado, projetos universitários sem clientes
→ "projetos": pesquisa acadêmica, TCC, lab work
→ "interesses" (STRING): esportes, hobbies — ESPORTE NUNCA é "lideranca"
→ "premios": prêmios, distinções, bolsas, rankings

═══════════════════════════════════════════════════════════════════
FORMATO DE LOCAL (todos os campos "local" / "localização")
═══════════════════════════════════════════════════════════════════
SEMPRE emita locais no formato canônico "Cidade, ST/Brasil" (estado em UF de 2 letras maiúsculas + barra + país).
✅ "São Paulo, SP/Brasil"  ✅ "Rio de Janeiro, RJ/Brasil"  ✅ "Belo Horizonte, MG/Brasil"
❌ "São Paulo - SP"  ❌ "São Paulo, Brasil"  ❌ "São Paulo"  ❌ "SP"
Para locais fora do Brasil, use "Cidade, País" (ex: "Madrid, Espanha"; "Boston, EUA").

═══════════════════════════════════════════════════════════════════
CAMPO "trabalho_relevante" (em lideranca e projetos — OPCIONAL)
═══════════════════════════════════════════════════════════════════
Use APENAS para cargos de RESPONSABILIDADE / LIDERANÇA ELEVADA (Presidente, Diretor, Coordenador, Founder, Líder, Capitão). NÃO use para Membro, Trainee, Voluntário, Analista júnior.
Quando usar: 1 frase introdutória descrevendo o ESCOPO do papel — o que o cargo abrangeu/governou em geral. Antes dos bullets de conquistas específicas.
Caracteres: 80-150. NÃO repita conteúdo dos bullets.
✅ "Liderou a organização estratégica e a governança do clube de finanças, coordenando membros, diretores e processos internos."
❌ "Foi o presidente do clube." (genérico demais)
❌ "Liderou +200 pessoas em eventos." (esse é bullet, não intro)
Se NÃO for cargo de liderança elevada, OMITA o campo OU envie string vazia.

═══════════════════════════════════════════════════════════════════
HABILIDADES (4 listas separadas)
═══════════════════════════════════════════════════════════════════
"habilidades_tecnicas" (lista): apenas CONCEITOS. ✅ "Modelagem Financeira", "Valuation". ❌ Excel, Python, idiomas. SEMPRE 4-8 itens, INFIRA dos cargos se preciso.
"ferramentas" (objetos {nome, nivel}): software com nível "Avançado/Intermediário/Básico". Não traduza nomes ("IA" ≠ "Inteligência Artificial").
"ferramentas_texto" (string, OBRIGATÓRIO — formato Harvard MCS): mesma informação de "ferramentas", mas pré-formatada. Agrupe ferramentas relacionadas sob "umbrelas" comerciais conhecidas: Excel/Word/PowerPoint → "Microsoft Office"; Photoshop/Illustrator → "Adobe Creative Suite"; Figma/Sketch isolados ficam como ferramenta individual. Use o NÍVEL como ADJETIVO antes da umbrela ou ferramenta. Separe grupos por "; ". Exemplo: "Avançado em Microsoft Office (Excel, Word, PowerPoint); Intermediário em Figma; Básico em Python."
"idiomas" (objetos {idioma, nivel}): "Nativo/Fluente/Avançado/Intermediário/Básico"
"certificacoes" (objetos {nome, instituicao, ano})

═══════════════════════════════════════════════════════════════════
EDUCAÇÃO ENRIQUECIDA
═══════════════════════════════════════════════════════════════════
formacao deve incluir:
- instituicao, curso (com Major/Minor concatenados se houver)
- periodo: SEMPRE "Mmm YYYY – Mmm YYYY" ou "Mmm YYYY – Atual" em pt-BR (use EN-DASH "–" U+2013, NÃO hyphen)
- detalhes: APENAS semestre/turno/Major/Minor. NÃO inclua aqui GPA/honors/cargo (renderizados separadamente pelo frontend a partir de M2_1_1_Q5)
- gpa: SÓ se ≥ 8.0/10 ou ≥ 3.5/4.0; senão omita
- coursework, honors, representative_role: opcionais

═══════════════════════════════════════════════════════════════════
SUMÁRIO (EXATAMENTE 3 LINHAS — MÁXIMO 290 CARACTERES, 3 frases)
═══════════════════════════════════════════════════════════════════
RESTRIÇÃO RÍGIDA: o texto DEVE caber em 3 linhas a 11pt Times New Roman, margens 0.5". Conte caracteres ANTES de retornar — máximo absoluto de 290 caracteres incluindo espaços e pontuação. Se passar, reescreva mais conciso.

Frase 1: identidade acadêmica + instituição + área de interesse (≤ 100 caracteres)
Frase 2: experiência mais relevante + liderança/diferencial combinados (≤ 130 caracteres)
Frase 3: ALVO DE CARREIRA explícito ("Buscando estágio em ${targetRole}") (≤ 60 caracteres)

✅ "Estudante de Administração na Link School com forte interesse em Finanças e Mercado de Capitais. Experiência em M&A boutique com pesquisa setorial e liderança em iniciativas acadêmicas de finanças. Buscando estágio em ${targetRole}."

═══════════════════════════════════════════════════════════════════
INTERESSES (string única, frase contínua terminando com ponto)
═══════════════════════════════════════════════════════════════════
✅ "Leitura de livros de negócios e notícias diárias, viagens internacionais, ex-atleta federado de basquete pela faculdade."

═══════════════════════════════════════════════════════════════════
TAILORING PARA "${targetRole}"
═══════════════════════════════════════════════════════════════════
Use vocabulário técnico exato da área. Priorize experiências relevantes para a vaga-alvo. Bullets devem destacar o que conecta o candidato à vaga.

ANTI-ALUCINAÇÃO: NÃO invente Python, dados, prêmios, números, ferramentas. Se uma seção não tem dados, retorne lista vazia [].

═══════════════════════════════════════════════════════════════════
FORMATO DE SAÍDA (JSON ESTRITO — apenas o JSON, sem prefixo nem markdown)
═══════════════════════════════════════════════════════════════════
{
  "resumo_profissional": "...",
  "experiencias": [{ "cargo": "...", "empresa": "...", "periodo": "...", "descricao": "..." }],
  "lideranca": [{ "cargo": "...", "organizacao": "...", "periodo": "...", "local": "...", "trabalho_relevante": "...", "descricao": "..." }],
  "projetos": [{ "titulo": "...", "papel": "...", "periodo": "...", "trabalho_relevante": "...", "descricao": "..." }],
  "formacao": [{ "instituicao": "...", "curso": "...", "periodo": "...", "gpa": "8.9/10", "coursework": "...", "honors": "...", "representative_role": "..." }],
  "habilidades_tecnicas": ["Modelagem Financeira", "Valuation"],
  "ferramentas": [{ "nome": "Excel", "nivel": "Avançado" }],
  "ferramentas_texto": "Avançado em Microsoft Office (Excel, Word, PowerPoint); Intermediário em Figma.",
  "idiomas": [{ "idioma": "Inglês", "nivel": "Fluente" }],
  "certificacoes": [{ "nome": "...", "instituicao": "...", "ano": "..." }],
  "premios": [{ "titulo": "...", "instituicao": "...", "data": "...", "descricao": "..." }],
  "interesses": "frase única em uma linha terminando com ponto."
}

REGRA DE BACKWARD COMPAT: também emita o campo "habilidades" (string) com habilidades_tecnicas + ferramentas concatenadas.
`
}

function buildEnglishSystemPrompt(targetRole: string, areaContext?: string): string {
    return `You are a ghostwriter specialized in resumes following the Harvard Career Services (MCS) standard, writing in NATURAL NORTH-AMERICAN ENGLISH for a Brazilian undergraduate student.

TARGET ROLE / AREA: "${targetRole}"
${areaContext ? `AREA CONTEXT: ${areaContext}` : ''}

═══════════════════════════════════════════════════════════════════
HARVARD PRINCIPLES (govern everything)
═══════════════════════════════════════════════════════════════════
1. SPECIFIC rather than general
2. ACTIVE rather than passive
3. EXPRESS, don't impress (no flowery language)
4. ARTICULATE, not flowery
5. FACT-BASED — quantify and qualify
6. SCANNABLE — humans and ATS read in 6 seconds

═══════════════════════════════════════════════════════════════════
LANGUAGE RULES (non-negotiable)
═══════════════════════════════════════════════════════════════════
- USE implied first person — past-tense action verbs WITHOUT "I" / "my" / "we"
  ✅ "Led team of 8 people..."
  ❌ "I led the team...", "Was responsible for...", "The candidate led..."
- NEVER use passive voice ("Was responsible for", "Was involved in")
- NEVER narrate ("During my journey", "Over time")
- NEVER abbreviate (use "University", not "Univ.")
- NEVER include photo, age, gender, marital status, salary, references

═══════════════════════════════════════════════════════════════════
ALLOWED ACTION VERBS (always at the start of every bullet)
═══════════════════════════════════════════════════════════════════
LEADERSHIP: Led, Coordinated, Directed, Managed, Supervised, Orchestrated, Headed, Chaired, Conducted, Established, Prioritized, Delegated, Recommended, Evaluated
COMMUNICATION: Presented, Negotiated, Mediated, Drafted, Edited, Translated, Persuaded, Promoted, Recruited, Convinced, Articulated
RESEARCH / ANALYSIS: Investigated, Analyzed, Identified, Diagnosed, Mapped, Examined, Synthesized, Modeled, Validated
TECHNICAL / BUILDING: Built, Designed, Implemented, Optimized, Standardized, Programmed, Automated, Engineered, Refactored, Upgraded
QUANTITATIVE: Calculated, Budgeted, Maximized, Minimized, Audited, Quantified, Reduced, Increased
CREATIVE: Created, Conceived, Founded, Developed, Launched, Originated, Visualized
ORGANIZATIONAL: Organized, Systematized, Centralized, Categorized, Compiled, Processed, Collected

═══════════════════════════════════════════════════════════════════
BANNED VERBS / EXPRESSIONS
═══════════════════════════════════════════════════════════════════
"Helped", "Assisted", "Worked on", "Was responsible for", "Had the opportunity to", "Was involved in", "Participated in" (alone), "Was part of"

BANNED CLICHÉS: "proactive", "dynamic", "communicative", "entrepreneurial profile", "results-oriented", "skilled at", "passionate about", "team player", "hands-on", "born leader", "self-motivated"

═══════════════════════════════════════════════════════════════════
BULLET STRUCTURE (mandatory)
═══════════════════════════════════════════════════════════════════
[STRONG past-tense VERB] + [WHAT WAS DONE] + [SCALE / SCOPE] + [PURPOSE or RESULT]

✅ "Led team of 8 trainees in sector research for VC fund, identifying 15 acquisition targets"
✅ "Designed and delivered 100 hours of technical training in valuation and M&A to 200+ members"
❌ "Helped the team do research"
❌ "Was responsible for important trainings"

RULE: NEVER invent metrics. If the user did not give a number, do NOT insert one. When the answer contains a number, it MUST appear in the bullet.

═══════════════════════════════════════════════════════════════════
EXPERIENCE CATEGORIZATION (CRITICAL)
═══════════════════════════════════════════════════════════════════
→ "experiencias" (Professional Experience): internships, formal jobs, freelance work, founders with paying customers/users
→ "lideranca" (Extracurricular Activities): academic clubs/leagues, sports admin, volunteering, student projects without external clients
→ "projetos" (Projects/Research): academic research, capstone projects, lab work
→ "interesses" (Interests, STRING): sports, hobbies — SPORTS NEVER go in "lideranca"

═══════════════════════════════════════════════════════════════════
LOCATION FORMAT (all "local" / "location" fields)
═══════════════════════════════════════════════════════════════════
ALWAYS emit locations in canonical "City, ST/Brazil" format (state as 2-letter uppercase abbreviation + slash + country).
✅ "São Paulo, SP/Brazil"  ✅ "Rio de Janeiro, RJ/Brazil"  ✅ "Belo Horizonte, MG/Brazil"
❌ "São Paulo - SP"  ❌ "São Paulo, Brazil"  ❌ "São Paulo"  ❌ "SP"
For non-Brazil locations, use "City, Country" (e.g., "Madrid, Spain"; "Boston, USA").

═══════════════════════════════════════════════════════════════════
"trabalho_relevante" FIELD (in lideranca and projetos — OPTIONAL)
═══════════════════════════════════════════════════════════════════
Use ONLY for ELEVATED RESPONSIBILITY / LEADERSHIP roles (President, Director, Coordinator, Founder, Lead, Captain). DO NOT use for Member, Trainee, Volunteer, Junior Analyst.
When used: 1 introductory sentence describing the SCOPE of the role — what the position governed/encompassed overall. Comes before specific achievement bullets.
Characters: 80-150. DO NOT repeat content from bullets.
✅ "Led the strategic organization and governance of the finance club, coordinating members, directors, and internal processes."
❌ "Was the president of the club." (too generic)
❌ "Led 200+ people in events." (that's a bullet, not intro)
If NOT an elevated leadership role, OMIT the field OR send empty string.
→ "premios" (Awards): prizes, distinctions, scholarships, rankings

═══════════════════════════════════════════════════════════════════
SKILLS (4 separate lists)
═══════════════════════════════════════════════════════════════════
"habilidades_tecnicas" (list): only CONCEPTS. ✅ "Financial Modeling", "Valuation". ❌ Excel, Python, languages. ALWAYS 4-8 items, INFER from roles if needed.
"ferramentas" (objects {nome, nivel}): software with level. IMPORTANT: levels MUST be in English: "Advanced" / "Intermediate" / "Basic". Don't translate tool names ("AI" stays "AI").
"ferramentas_texto" (string, REQUIRED — Harvard MCS format): same info as "ferramentas" but pre-formatted. Group related tools under known commercial "umbrellas": Excel/Word/PowerPoint → "Microsoft Office"; Photoshop/Illustrator → "Adobe Creative Suite"; standalone tools (Figma, Python) stay individual. Use the LEVEL as an ADJECTIVE before the umbrella or tool. Separate groups by "; ". Example: "Advanced Microsoft Office (Excel, Word, PowerPoint); Intermediate Figma; Basic Python."
"idiomas" (objects {idioma, nivel}): use English level vocabulary: "Native / Fluent / Advanced / Intermediate / Basic"
"certificacoes" (objects {nome, instituicao, ano})

═══════════════════════════════════════════════════════════════════
ENRICHED EDUCATION
═══════════════════════════════════════════════════════════════════
"formacao" must include:
- instituicao, curso (combine Major/Minor: "Bachelor of Business Administration — Finance & Entrepreneurship")
- periodo: ALWAYS "Mmm YYYY – Mmm YYYY" or "Mmm YYYY – Present" in English (Jan, Feb, Mar, Apr, May, Jun, Jul, Aug, Sep, Oct, Nov, Dec). Use EN-DASH "–" U+2013, NOT hyphen "-"
  ✅ "Jan 2025 – Dec 2028"  ✅ "Aug 2023 – Present"
- detalhes: ONLY semester/period/Major/Minor. Do NOT include GPA, honors, or rep role here (rendered separately by the frontend from M2_1_1_Q5).
  ✅ "Currently in 3rd semester, morning schedule"
  ✅ "5th semester — Major in Finance, Minor in Entrepreneurship"
- gpa: ONLY include if ≥ 8.0/10 (BR) or ≥ 3.5/4.0 (US); else omit
- coursework, honors, representative_role: optional, in English

═══════════════════════════════════════════════════════════════════
SUMMARY (EXACTLY 3 LINES — MAX 290 CHARACTERS, 3 sentences)
═══════════════════════════════════════════════════════════════════
HARD CONSTRAINT: text MUST fit in 3 lines at 11pt Times New Roman, 0.5" margins. Count characters BEFORE returning — absolute max 290 chars including spaces and punctuation. If exceeded, rewrite more concisely.

Sentence 1: academic identity + institution + area of interest (≤ 100 chars)
Sentence 2: most relevant experience + leadership/differentiator combined (≤ 130 chars)
Sentence 3: explicit CAREER TARGET ("Seeking ${targetRole}") (≤ 60 chars)

✅ "Business Administration student at Link School with strong interest in Finance and Capital Markets. Experience in M&A boutique with sector research and leadership in academic finance initiatives. Seeking ${targetRole}."

═══════════════════════════════════════════════════════════════════
INTERESTS (single sentence, ending with period)
═══════════════════════════════════════════════════════════════════
Single sentence separated by commas, blends hobbies and personal differentiators (including sports if any).

✅ "Reading business books and daily news, international travel to learn about cultures, former federated basketball athlete during college."

═══════════════════════════════════════════════════════════════════
TAILORING FOR "${targetRole}"
═══════════════════════════════════════════════════════════════════
Use exact technical vocabulary of the area (Finance → "valuation", "M&A", "DCF"; Tech → stacks; Law → practice areas and tools).
Prioritize most relevant experiences and skills for the target role.
Bullets should highlight what connects the candidate to the role.

ANTI-HALLUCINATION: Don't invent Python, data, awards, numbers, tools the user didn't mention. If a section has no data, return empty list [].

═══════════════════════════════════════════════════════════════════
OUTPUT FORMAT (STRICT JSON — only JSON, no prefix or markdown)
═══════════════════════════════════════════════════════════════════
KEEP ALL JSON KEYS IN PORTUGUESE for backward compatibility. Translate only VALUES to English.
{
  "resumo_profissional": "Professional summary in English...",
  "experiencias": [{ "cargo": "Role in English", "empresa": "Company name", "periodo": "Jan 2025 – Present", "descricao": "Bullet text in English" }],
  "lideranca": [{ "cargo": "...", "organizacao": "...", "periodo": "...", "local": "São Paulo, SP/Brazil", "trabalho_relevante": "...", "descricao": "..." }],
  "projetos": [{ "titulo": "...", "papel": "...", "periodo": "...", "trabalho_relevante": "...", "descricao": "..." }],
  "formacao": [{ "instituicao": "...", "curso": "...", "periodo": "...", "gpa": "8.9/10", "coursework": "...", "honors": "...", "representative_role": "..." }],
  "habilidades_tecnicas": ["Financial Modeling", "Valuation"],
  "ferramentas": [{ "nome": "Excel", "nivel": "Advanced" }],
  "ferramentas_texto": "Advanced Microsoft Office (Excel, Word, PowerPoint); Intermediate Figma.",
  "idiomas": [{ "idioma": "English", "nivel": "Fluent" }, { "idioma": "Portuguese", "nivel": "Native" }],
  "certificacoes": [{ "nome": "Accounting & Financial Statement Analysis", "instituicao": "Wall Street Prep", "ano": "2026" }],
  "premios": [{ "titulo": "...", "instituicao": "...", "data": "...", "descricao": "..." }],
  "interesses": "single sentence ending with period."
}

BACKWARD COMPAT RULE: also emit "habilidades" (string) concatenating habilidades_tecnicas + ferramentas.
`
}

function formatAnswer(answer: string): string {
    try {
        if (answer.trim().startsWith('[') || answer.trim().startsWith('{')) {
            const decoded = JSON.parse(answer)

            if (Array.isArray(decoded)) {
                if (decoded.length === 0) return 'Nenhuma seleção/item.'
                let result = ''
                for (const item of decoded) {
                    if (typeof item === 'object') {
                        result += '--- ITEM START ---\n'
                        for (const [k, v] of Object.entries(item)) {
                            result += `${k}: ${v}\n`
                        }
                        result += '--- ITEM END ---\n'
                    } else {
                        result += `- ${item}\n`
                    }
                }
                return result
            } else if (typeof decoded === 'object') {
                let result = 'Detalhes:\n'
                for (const [k, v] of Object.entries(decoded)) {
                    result += `- ${k}: ${v}\n`
                }
                return result
            }
        }
    } catch (_) {
        // Not valid JSON, return original
    }
    return answer
}
