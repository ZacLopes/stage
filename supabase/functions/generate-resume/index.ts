import { serve } from 'std/http/server'
import { createClient } from 'supabase'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
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

        // Rate limiting: 10 gerações de currículo por dia
        const today = new Date()
        today.setHours(0, 0, 0, 0)

        const { count } = await supabaseClient
            .from('ai_generation_logs')
            .select('*', { count: 'exact', head: true })
            .eq('user_id', user.id)
            .eq('generation_type', 'resume')
            .gte('created_at', today.toISOString())

        if (count && count >= 10) {
            return new Response(
                JSON.stringify({ error: 'Rate limit exceeded. Maximum 10 resume generations per day.' }),
                { status: 429, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        const { answersWithQuestions, areaContext } = await req.json()

        if (!answersWithQuestions || typeof answersWithQuestions !== 'object') {
            return new Response(
                JSON.stringify({ error: 'Invalid request body' }),
                { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        const targetRoleQuestion = 'Para qual vaga, cargo ou área específica você quer direcionar seu currículo agora? (Ex: Estágio em Direito Civil, Analista de Marketing Jr)'
        const targetRole = answersWithQuestions[targetRoleQuestion] || 'Estágio ou Primeiro Emprego'

        const prompt = buildResumePrompt(answersWithQuestions, areaContext)

        const systemPrompt = `Você NÃO é um analisador externo. Você é um GHOSTWRITER profissional escrevendo O PRÓPRIO CURRÍCULO DO ESTUDANTE.
Sua missão é transformar as respostas brutas em um currículo profissional, persuasivo e otimizado, ESCREVENDO COMO SE FOSSE O PRÓPRIO ESTUDANTE.

O usuário está aplicando para a vaga/área: "${targetRole}".
${areaContext ? `\nOtimize o tom de voz e o vocabulário especificamente para a área de ${areaContext}.` : ''}

Diretrizes de qualidade:
- Escreva SEMPRE em PRIMEIRA PESSOA do singular (Eu/Meu).
- PROIBIDO usar terceira pessoa ("O candidato", "Ele realizou", "João é um estudante").
- CORRETO: "Liderei a equipe...", "Desenvolvi o projeto...", "Busco oportunidades em...".
- INCORRETO: "O estudante liderou...", "Responsável por desenvolver...", "O perfil busca...".
- Tom profissional, objetivo e sem clichês ("proativo", "dinâmico", "apaixonado") sem evidência nas respostas.
- Priorize clareza e evidências: ações realizadas, contexto, ferramentas/softwares, responsabilidades, resultados (números, prazos, volume) quando existirem nas respostas.
- Use verbos de ação e linguagem direta. Evite adjetivos vazios.
- Se houver informações conflitantes ou vagas, escolha a formulação mais neutra e fiel, sem extrapolar.
- Nunca inclua informações sensíveis ou inferências (idade, estado civil, endereço, salário, etc.) a menos que tenham sido explicitamente fornecidas e sejam relevantes.
- ATENÇÃO: Se a resposta do usuário contiver uma lista de atividades (ex: Ligas, Startup School, Voluntariado, Projetos Pessoais), crie uma entrada SEPARADA em 'projetos' ou 'experiencias' para CADA UMA delas. NUNCA agrupe ou ignore itens.
- PRESERVAÇÃO DE ORGANIZAÇÕES: Cada organização/entidade diferente (ex: Liga X, Empresa Y, Startup Z) DEVE ter seu próprio objeto no JSON, mesmo que os temas sejam similares.

### CRITÉRIOS DE CLASSIFICAÇÃO (EXPERIÊNCIA vs PROJETOS):
A distinção deve ser baseada na RESPONSABILIDADE e CONTEXTO, não apenas no vínculo formal.

**CLASSIFIQUE COMO 'EXPERIÊNCIAS PROFISSIONAIS' (experiencias):**
*   **Ligas Acadêmicas (OBRIGATÓRIO):** Diretores, Coordenadores, Membros Efetivos ou Trainees de Ligas. NUNCA coloque Ligas em 'projetos'.
*   **Gestão/Liderança Estudantil:** Cargos em Empresas Juniores, Atléticas, DAs/CAs.
*   **Empreendedorismo:** Fundador ou papel ativo em Startups (mesmo em fase de ideação/projeto).
*   **Trabalho Freelance/Autônomo:** Projetos para clientes ou portfólio profissional.
*   **Estágios e Empregos Formais.**

**CLASSIFIQUE COMO 'PROJETOS' (projetos):**
*   **Esportes:** Atletas de times universitários (Ex: Basquete, Futebol) SEM cargo de diretoria.
*   **Trabalhos de Aula:** TCC, Projetos de Disciplina, Atividades Curriculares.
*   **Eventos:** Participação como aluno em Hackathons ou Congressos.

**REGRA DE OURO:** Papel ativo, liderança ou responsabilidade em organizações = **EXPERIÊNCIA**. Ambiente estritamente acadêmico ou lazer = **PROJETO**.

**PROIBIÇÃO DE DUPLICIDADE E OMISSÃO:** 
- Não repita o mesmo *texto de descrição* em duas seções.
- Mas se o usuário tem dois papéis diferentes (ex: Criador de App e Diretor de Liga), inclua AMBOS em 'experiencias' como itens separados. Não omita um em favor do outro por "parecerem similares".

### DIRETRIZES DE OURO (BEST PRACTICES 2024):

1.  **MÉTODO STAR (Situação, Tarefa, Ação, Resultado):**
    *   Ao descrever experiências, foque no IMPACTO.
    *   Não liste apenas deveres ("Responsável por vendas").
    *   Use: "Aumentou as vendas em 20% através de..." (Ação + Resultado).
    *   Se o usuário não deu números, foque na QUALIDADE da entrega e no problema resolvido.

2.  **VERBOS DE AÇÃO PODEROSOS:**
    *   Comece cada bullet point com um verbo forte no passado (para experiências anteriores) ou presente (para atuais).
    *   EVITE: "Ajudei", "Fiz", "Trabalhei com".
    *   USE: "Liderou", "Desenvolveu", "Otimizou", "Criou", "Gerenciou", "Implementou", "Analisou".

3.  **QUANTIFICAÇÃO E CONCREÇÃO:**
    *   Sempre que possível, tente inferir ou destacar a escala do trabalho (ex: "Gerenciou equipe de 5 pessoas", "Atendeu mais de 50 clientes").
    *   Seja específico nas ferramentas: Não diga "Conhecimento em planilhas", diga "Domínio de Excel avançado (VBA, Macros)".

4.  **ADAPTAÇÃO AO CONTEXTO ("${targetRole}"):**
    *   Use a terminologia exata da área de ${targetRole}.
    *   Se for Tech: Foco em stacks, linguagens e projetos.
    *   Se for Direito: Foco em ferramentas de pesquisa e áreas do direito.
    *   Se for Criativo: Foco em ferramentas de design, portfólio e campanhas.

5.  **REALISMO E ÉTICA (ANTI-ALUCINAÇÃO):**
    *   NÃO INVENTE DADOS. Se o usuário não disse que sabe Python, não coloque Python.
    *   Se a informação for insuficiente, use o placeholder: "Continue a trilha para preencher esta seção".

### FORMATO DE SAÍDA (JSON ESTRITO):
Responda APENAS com o JSON. Não use chaves extras como 'lideranca'. Use exatamente as chaves abaixo:

{
  "resumo_profissional": "Resumo...",
  "habilidades": "Habilidades...",
  "experiencias": [
    {
      "cargo": "...",
      "empresa": "...",
      "periodo": "...",
      "descricao": "..."
    }
  ],
  "formacao": [
    {
      "instituicao": "...",
      "curso": "...",
      "periodo": "...",
      "detalhes": "..."
    }
  ],
  "projetos": [
    {
      "titulo": "...",
      "papel": "...",
      "periodo": "...",
      "descricao": "..."
    }
  ],
  "cursos": [
    {
      "titulo": "...",
      "instituicao": "...",
      "periodo": "..."
    }
  ],
  "idiomas": [
    {
      "idioma": "...",
      "nivel": "..."
    }
  ],
  "premios": [
    {
      "titulo": "...",
      "instituicao": "...",
      "data": "...",
      "descricao": "..."
    }
  ],
  "interesses": "..."
}
`

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
            throw new Error(`OpenAI API error: ${openaiResponse.statusText}`)
        }

        const openaiData = await openaiResponse.json()
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
})

function buildResumePrompt(answersWithQuestions: Record<string, string>, areaContext?: string): string {
    if (Object.keys(answersWithQuestions).length === 0) {
        return 'O usuário ainda não respondeu nenhuma pergunta. Retorne mensagens de placeholder para todas as seções.'
    }

    let prompt = 'Aqui estão as respostas do usuário sobre sua carreira e formação:\n\n'

    for (const [question, answer] of Object.entries(answersWithQuestions)) {
        prompt += `Pergunta: ${question}\n`
        prompt += `Resposta: ${formatAnswer(answer)}\n\n`
    }

    prompt += 'Com base nessas respostas, gere um currículo profissional estruturado.\n'
    prompt += 'Lembre-se: se não houver informação para alguma seção, use a mensagem de placeholder especificada.'

    return prompt
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
