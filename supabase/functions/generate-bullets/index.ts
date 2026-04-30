import { serve } from 'std/http/server'
import { createClient } from 'supabase'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

/**
 * generate-bullets Edge Function
 * 
 * Receives raw responses for ONE experience and generates 3 bullet versions
 * (resultado, processo, habilidade). Also detects when info is too shallow
 * and returns a clarification question instead of inventing generic text.
 * 
 * This is the AI-Writer role — separate from the AI-Interviewer (the gamified flow).
 */
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

        // Auth check
        const { data: { user }, error: authError } = await supabaseClient.auth.getUser()
        if (authError || !user) {
            return new Response(
                JSON.stringify({ error: 'Unauthorized' }),
                { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // Rate limiting: 50 bullet generations per day (generous for MVP)
        const today = new Date()
        today.setHours(0, 0, 0, 0)

        const { count } = await supabaseClient
            .from('bullet_generation_logs')
            .select('*', { count: 'exact', head: true })
            .eq('user_id', user.id)
            .gte('created_at', today.toISOString())

        if (count && count >= 50) {
            return new Response(
                JSON.stringify({ error: 'Rate limit exceeded. Maximum 50 bullet generations per day.' }),
                { status: 429, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // Parse request
        const {
            experienceId,
            experienceType,
            rawResponses,   // Array of { question: string, answer: string }
            userContext,     // { course, semester, targetRole, previousBullets }
            clarificationAnswer, // Optional: answer to a previous needs_clarification
        } = await req.json()

        if (!rawResponses || !Array.isArray(rawResponses) || rawResponses.length === 0) {
            return new Response(
                JSON.stringify({ error: 'rawResponses is required and must be a non-empty array' }),
                { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // Build the prompt
        const systemPrompt = buildWriterSystemPrompt(
            userContext?.targetRole || 'Estágio ou Primeiro Emprego',
            experienceType || 'corporate'
        )
        const userPrompt = buildUserPrompt(
            rawResponses,
            userContext,
            clarificationAnswer
        )

        const startTime = Date.now()

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
                    { role: 'user', content: userPrompt }
                ],
                temperature: 0.7, // Slightly higher for creative writing variety
                max_tokens: 1000, // Focused output: 3 bullets + optional clarification
                response_format: { type: 'json_object' },
            })
        })

        const latencyMs = Date.now() - startTime

        if (!openaiResponse.ok) {
            const errorBody = await openaiResponse.text()
            console.error('OpenAI API error:', openaiResponse.status, errorBody)
            throw new Error(`OpenAI API error: ${openaiResponse.statusText}`)
        }

        const openaiData = await openaiResponse.json()
        const responseText = openaiData.choices[0].message.content

        let result
        try {
            result = JSON.parse(responseText)
        } catch (parseError) {
            // Fallback: try to extract JSON from markdown code blocks
            let jsonText = responseText.trim()
            if (jsonText.startsWith('```json')) jsonText = jsonText.substring(7)
            if (jsonText.startsWith('```')) jsonText = jsonText.substring(3)
            if (jsonText.endsWith('```')) jsonText = jsonText.substring(0, jsonText.length - 3)
            result = JSON.parse(jsonText.trim())
        }

        // Validate the response structure
        if (!result.bullets || !Array.isArray(result.bullets) || result.bullets.length < 3) {
            throw new Error('AI response missing required bullets array with 3 items')
        }

        // Log generation
        await supabaseClient.from('bullet_generation_logs').insert({
            user_id: user.id,
            experience_id: experienceId || null,
            generation_type: clarificationAnswer ? 'regeneration' : 'bullets',
            model_used: 'gpt-4o',
            prompt_version: 'v1',
            input_tokens: openaiData.usage?.prompt_tokens || 0,
            output_tokens: openaiData.usage?.completion_tokens || 0,
            total_tokens: openaiData.usage?.total_tokens || 0,
            latency_ms: latencyMs,
            had_clarification: result.needs_clarification != null,
            clarification_question: result.needs_clarification?.question || null,
            clarification_answered: !!clarificationAnswer,
        })

        // If experienceId is provided, persist bullet_versions to DB
        if (experienceId) {
            const bulletInserts = result.bullets.map((b: { angle: string, content: string, confidence: number }, idx: number) => ({
                experience_id: experienceId,
                content: b.content,
                angle: b.angle,
                version_number: clarificationAnswer ? 2 : 1, // v2 if regenerated after clarification
                model_used: 'gpt-4o',
                prompt_version: 'v1',
                tokens_used: Math.floor((openaiData.usage?.total_tokens || 0) / 3),
                confidence: b.confidence || 0.8,
                was_chosen: false,
                was_edited: false,
            }))

            const { error: insertError } = await supabaseClient
                .from('bullet_versions')
                .insert(bulletInserts)

            if (insertError) {
                console.error('Error persisting bullet versions:', insertError)
                // Non-fatal: still return bullets to the client
            }
        }

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


// ============================================
// PROMPT BUILDERS
// ============================================

function buildWriterSystemPrompt(targetRole: string, experienceType: string): string {
    return `Você é um ghostwriter especializado em currículos para estudantes universitários brasileiros.

## SUA TAREFA
Receba as respostas do usuário sobre UMA experiência específica e gere EXATAMENTE 3 versões de bullet point.
Tipo de experiência: ${experienceType}
Área-alvo do usuário: ${targetRole}

## AS 3 VERSÕES (OBRIGATÓRIAS)
1. **RESULTADO**: Foco no impacto quantificável. Começa com verbo de ação + entrega mensurável.
2. **PROCESSO**: Foco no método/processo usado. Mostra COMO o trabalho foi feito.
3. **HABILIDADE**: Foco na competência demonstrada. Conecta a ação a uma skill transferível.

As 3 versões usam as MESMAS informações mas com ênfase narrativa diferente. NÃO são paráfrases umas das outras.

## EXEMPLOS DE BULLETS BONS vs RUINS

### ❌ RUIM (genérico, sem evidência, paráfrases):
- "Responsável por atividades de marketing digital" (sem ação, sem resultado)
- "Auxiliou no desenvolvimento de estratégias de vendas" (verbo fraco, vago)
- "Participou de projetos de impacto social" (passivo, zero especificidade)

### ✅ BOM (mesmo contexto: estudante que gerenciou Instagram de Liga de Marketing):

**RESULTADO**: "Cresci o Instagram da Liga de Marketing de 800 para 2.400 seguidores em 4 meses, gerando 15 leads qualificados para eventos."
**PROCESSO**: "Planejei e executei calendário editorial semanal com 3 formatos de conteúdo (carrossel, reels, stories), usando métricas de engajamento para iterar a cada sprint."
**HABILIDADE**: "Apliquei gestão de mídias sociais e análise de dados de engajamento para otimizar a estratégia de conteúdo digital da organização."

### ❌ RUIM (3 versões que são paráfrases):
1. "Gerenciou as redes sociais da Liga"
2. "Foi responsável pelas redes sociais da Liga"
3. "Cuidou das redes sociais da Liga de Marketing"
→ São a mesma frase reescrita 3 vezes. PROIBIDO.

## REGRAS INVIOLÁVEIS
- Escreva em PRIMEIRA PESSOA (Liderei, Desenvolvi, Cresci). NUNCA terceira pessoa.
- Verbo de ação forte no início. PROIBIDO: "Responsável por", "Auxiliou em", "Participou de", "Ajudou a".
- USE: "Liderei", "Desenvolvi", "Otimizei", "Cresci", "Implementei", "Gerenciei", "Criei", "Estruturei", "Conduzi".
- Se a informação NÃO permite um bullet específico e impactante, retorne "needs_clarification" com uma pergunta. NÃO invente dados.
- NUNCA invente números, ferramentas, resultados ou qualquer informação não mencionada pelo usuário.
- Adapte o vocabulário para a área de ${targetRole}.
- Cada bullet deve ter entre 1 e 2 linhas (máximo ~180 caracteres).

## FORMATO DE RESPOSTA (JSON ESTRITO)
{
  "bullets": [
    {
      "angle": "resultado",
      "content": "texto do bullet...",
      "confidence": 0.85
    },
    {
      "angle": "processo",
      "content": "texto do bullet...",
      "confidence": 0.90
    },
    {
      "angle": "habilidade",
      "content": "texto do bullet...",
      "confidence": 0.75
    }
  ],
  "needs_clarification": null
}

Se a informação for rasa demais:
{
  "bullets": [ ... os 3 bullets mesmo assim, fazendo o melhor possível ... ],
  "needs_clarification": {
    "question": "Pergunta específica que esclareceria o ponto...",
    "reason": "Explicação curta de por que essa info melhoraria o bullet.",
    "target_angle": "resultado"
  }
}

IMPORTANTE: Mesmo quando needs_clarification é retornado, SEMPRE gere os 3 bullets (a melhor versão possível com o que tem). O usuário pode aceitar os bullets atuais mesmo sem responder a clarificação.`
}


function buildUserPrompt(
    rawResponses: Array<{ question: string, answer: string }>,
    userContext?: {
        course?: string,
        semester?: string,
        targetRole?: string,
        previousBullets?: string[]
    },
    clarificationAnswer?: string
): string {
    let prompt = ''

    // User context section
    if (userContext) {
        prompt += '## CONTEXTO DO USUÁRIO\n'
        if (userContext.course) prompt += `- Curso: ${userContext.course}\n`
        if (userContext.semester) prompt += `- Semestre: ${userContext.semester}\n`
        if (userContext.targetRole) prompt += `- Área-alvo: ${userContext.targetRole}\n`

        if (userContext.previousBullets && userContext.previousBullets.length > 0) {
            prompt += `\n## BULLETS JÁ APROVADOS (evite repetição, mantenha consistência de tom):\n`
            userContext.previousBullets.forEach((b, i) => {
                prompt += `${i + 1}. ${b}\n`
            })
        }
        prompt += '\n'
    }

    // Clarification answer (if regenerating after user provided more info)
    if (clarificationAnswer) {
        prompt += `## INFORMAÇÃO ADICIONAL (o usuário respondeu uma pergunta de aprofundamento):\n`
        prompt += `${clarificationAnswer}\n\n`
        prompt += `Use essa informação para gerar bullets mais específicos e impactantes.\n\n`
    }

    // Raw responses for this experience
    prompt += '## RESPOSTAS DO USUÁRIO SOBRE ESTA EXPERIÊNCIA:\n\n'
    rawResponses.forEach((r, i) => {
        prompt += `**${r.question}**\n${r.answer}\n\n`
    })

    prompt += 'Gere os 3 bullets conforme as instruções do sistema.'

    return prompt
}
