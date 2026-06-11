import { serve } from 'std/http/server'
import { createClient } from 'supabase'
import { trackAIGeneration, withEdgeAnalytics } from '../_shared/posthog.ts'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

/**
 * generate-bullets Edge Function (Phase 5 rewrite)
 *
 * Receives {experience_phase_id, campaign_id} and fetches all context
 * server-side before calling GPT-4o. Returns 3 bullet versions and
 * persists them to bullet_versions.
 *
 * experience_phase_id format: 'm3.stage.0', 'm3.emp.1', etc.
 * D1-D5 raw_responses have phase_id like 'm3.stage.0.d1' ... 'm3.stage.0.d5'
 */
serve(withEdgeAnalytics('generate-bullets', async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        const supabaseClient = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_ANON_KEY') ?? '',
            { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
        )

        // Auth check
        const { data: { user }, error: authError } = await supabaseClient.auth.getUser()
        if (authError || !user) {
            return new Response(
                JSON.stringify({ error: 'Unauthorized' }),
                { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // Rate limiting: 50 generations/day
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
        // target_experience_id (opcional, Semana 2): se vier, escreve bullets gerados
        // tambem em profile_bullets vinculados a profile_experiences. Backward compatible
        // — sem o parametro mantem comportamento legacy (so bullet_versions).
        const { experience_phase_id, campaign_id, clarification_answer, target_experience_id } = await req.json()

        if (!experience_phase_id || !campaign_id) {
            return new Response(
                JSON.stringify({ error: 'experience_phase_id and campaign_id are required' }),
                { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // 1. Fetch D1-D5 raw responses for this experience
        const { data: rawResponses } = await supabaseClient
            .from('raw_responses')
            .select('phase_id, question, answer')
            .eq('user_id', user.id)
            .like('phase_id', `${experience_phase_id}.d%`)
            .order('phase_id', { ascending: true })

        if (!rawResponses || rawResponses.length === 0) {
            return new Response(
                JSON.stringify({ error: 'No D1-D5 responses found for this experience' }),
                { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // 2. Fetch user profile
        const { data: userProfile } = await supabaseClient
            .from('user_profiles')
            .select('course, gamification_data')
            .eq('id', user.id)
            .single()

        // 3. Fetch target job from campaign
        const { data: campaign } = await supabaseClient
            .from('campaigns')
            .select('target_job_id, target_jobs(title, description_text)')
            .eq('id', campaign_id)
            .eq('user_id', user.id)
            .single()

        const targetJob = campaign?.target_jobs as { title?: string, description_text?: string } | null

        // 4. Fetch M1 answers for user context
        const { data: m1Answers } = await supabaseClient
            .from('raw_responses')
            .select('phase_id, answer')
            .eq('user_id', user.id)
            .in('phase_id', ['m1.1', 'm1.3'])

        const interestAreas = m1Answers?.find(r => r.phase_id === 'm1.1')?.answer ?? ''
        const visionText = m1Answers?.find(r => r.phase_id === 'm1.3')?.answer ?? ''

        // 5. Fetch previously approved bullets for consistency
        const { data: previousBullets } = await supabaseClient
            .from('approved_bullets')
            .select('final_text')
            .eq('campaign_id', campaign_id)
            .eq('is_active', true)
            .order('display_order', { ascending: true })

        const previousBulletTexts = previousBullets?.map(b => b.final_text) ?? []

        // 6. Build prompt and call GPT-4o
        const gamificationData = userProfile?.gamification_data ?? {}
        const module2 = gamificationData?.module2?.myBase ?? {}
        const course = userProfile?.course ?? module2?.education?.course ?? ''
        const semester = module2?.education?.semester ?? ''

        const systemPrompt = buildSystemPrompt(targetJob, interestAreas, visionText)
        const userPrompt = buildUserPrompt(rawResponses, course, semester, previousBulletTexts, clarification_answer)

        const startTime = Date.now()
        const openaiResponse = await fetch('https://api.openai.com/v1/chat/completions', {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${Deno.env.get('OPENAI_API_KEY')}`,
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                model: 'gpt-4o',
                messages: [
                    { role: 'system', content: systemPrompt },
                    { role: 'user', content: userPrompt },
                ],
                temperature: 0.7,
                max_tokens: 1000,
                response_format: { type: 'json_object' },
            }),
        })
        const latencyMs = Date.now() - startTime

        if (!openaiResponse.ok) {
            throw new Error(`OpenAI API error: ${openaiResponse.statusText}`)
        }

        const openaiData = await openaiResponse.json()

        // PostHog LLM Analytics — fire-and-forget pra não atrasar a resposta.
        trackAIGeneration({
            userId: user.id,
            generationType: 'bullet_generation',
            model: 'gpt-4o',
            inputTokens: openaiData.usage?.prompt_tokens ?? 0,
            outputTokens: openaiData.usage?.completion_tokens ?? 0,
            latencyMs,
            isError: false,
        }).catch(() => {})

        let result
        try {
            result = JSON.parse(openaiData.choices[0].message.content)
        } catch {
            let text = openaiData.choices[0].message.content.trim()
            if (text.startsWith('```json')) text = text.slice(7)
            if (text.startsWith('```')) text = text.slice(3)
            if (text.endsWith('```')) text = text.slice(0, -3)
            result = JSON.parse(text.trim())
        }

        if (!result.bullets || !Array.isArray(result.bullets) || result.bullets.length < 3) {
            throw new Error('AI response missing required bullets array')
        }

        // 7. Persist bullet_versions
        const bulletInserts = result.bullets.map((b: { angle: string; content: string; confidence: number }) => ({
            campaign_id,
            experience_phase_id,
            content: b.content,
            angle: b.angle,
            version_number: clarification_answer ? 2 : 1,
            model_used: 'gpt-4o',
            prompt_version: 'v2',
            tokens_used: Math.floor((openaiData.usage?.total_tokens ?? 0) / 3),
            confidence: b.confidence ?? 0.8,
            was_chosen: false,
            was_edited: false,
        }))

        const { data: insertedVersions } = await supabaseClient
            .from('bullet_versions')
            .insert(bulletInserts)
            .select('id, angle')

        // Map version IDs back into result
        const versionIds: Record<string, string> = {}
        for (const v of (insertedVersions ?? [])) {
            versionIds[v.angle] = v.id
        }
        result.bullets = result.bullets.map((b: { angle: string; content: string; confidence: number }) => ({
            ...b,
            version_id: versionIds[b.angle] ?? null,
        }))

        // Forward-compat (Semana 2): se target_experience_id veio, escreve as
        // 3 variantes geradas também em profile_bullets. UI do BulletReviewScreen
        // depois marca a aprovada via update. Fire-and-forget — falha aqui NÃO
        // derruba a resposta com bullet_versions.
        if (target_experience_id) {
            const profileBulletInserts = result.bullets.map((b: { angle: string; content: string; confidence: number }, idx: number) => ({
                experience_id: target_experience_id,
                text: b.content,
                angle: b.angle, // já é 'leadership'/'technical'/'impact'
                strength_score: Math.round((b.confidence ?? 0.8) * 100),
                order_index: idx,
            }))
            try {
                await supabaseClient.from('profile_bullets').insert(profileBulletInserts)
            } catch (e) {
                console.error('[generate-bullets] profile_bullets insert failed:', e)
            }
        }

        // 8. Log generation
        await supabaseClient.from('bullet_generation_logs').insert({
            user_id: user.id,
            campaign_id,
            experience_phase_id,
            generation_type: clarification_answer ? 'regeneration' : 'bullets',
            model_used: 'gpt-4o',
            prompt_version: 'v2',
            input_tokens: openaiData.usage?.prompt_tokens ?? 0,
            output_tokens: openaiData.usage?.completion_tokens ?? 0,
            total_tokens: openaiData.usage?.total_tokens ?? 0,
            latency_ms: latencyMs,
            had_clarification: result.needs_clarification != null,
            clarification_question: result.needs_clarification?.question ?? null,
            clarification_answered: !!clarification_answer,
        })

        return new Response(
            JSON.stringify(result),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )

    } catch (error) {
        console.error('generate-bullets error:', error)
        return new Response(
            JSON.stringify({ error: error.message ?? 'Internal server error' }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    }
}))

function buildSystemPrompt(
    targetJob: { title?: string; description_text?: string } | null,
    interestAreas: string,
    visionText: string,
): string {
    return `Você é um ghostwriter especializado em currículos para estudantes universitários brasileiros.

## CONTEXTO DA CAMPANHA
Vaga-alvo: ${targetJob?.title ?? 'Estágio ou Primeiro Emprego'}
Descrição da vaga: ${targetJob?.description_text ?? 'não fornecida'}
Área de foco do usuário: ${interestAreas || 'não informada'}
Norte profissional: ${visionText || 'não informado'}

## SUA TAREFA
Gere EXATAMENTE 3 versões de bullet point com ângulos narrativos distintos:

1. **RESULTADO**: Impacto quantificável. Verbo de ação + entrega mensurável.
2. **PROCESSO**: Foco no método/como o trabalho foi feito.
3. **HABILIDADE**: Competência demonstrada conectada a uma skill transferível.

As 3 versões usam as MESMAS informações mas com ênfase diferente — NÃO são paráfrases.

## REGRAS INVIOLÁVEIS
- Português brasileiro
- Verbo de ação forte no início (NUNCA "Responsável por", "Auxiliou em", "Participou de")
- USE: Liderei, Desenvolvi, Otimizei, Cresci, Implementei, Gerenciei, Criei, Estruturei, Conduzi
- Primeira pessoa implícita (não use "Eu" — comece direto com o verbo)
- 1-2 linhas por bullet, máximo ~180 caracteres
- NUNCA invente dados, números ou ferramentas não mencionados pelo usuário
- Se a informação for rasa demais, retorne needs_clarification MAS ainda gere os 3 bullets

## EXEMPLO
❌ RUIM: "Responsável por atividades de marketing digital"
✅ BOM (Liga de Marketing, cresceu Instagram de 800 → 2.400):
- RESULTADO: "Cresci o Instagram da Liga de Marketing de 800 para 2.400 seguidores em 4 meses, gerando 15 leads para eventos."
- PROCESSO: "Estruturei calendário editorial semanal com 3 formatos iterando com base em métricas de engajamento."
- HABILIDADE: "Apliquei gestão de mídias sociais e análise de dados para otimizar a estratégia de conteúdo digital."

## FORMATO DE RESPOSTA (JSON estrito)
{
  "bullets": [
    {"angle": "resultado", "content": "...", "confidence": 0.85},
    {"angle": "processo", "content": "...", "confidence": 0.90},
    {"angle": "habilidade", "content": "...", "confidence": 0.75}
  ],
  "needs_clarification": null
}

Se info for rasa:
{
  "bullets": [ ... os 3 bullets do jeito que conseguir ... ],
  "needs_clarification": {
    "question": "Pergunta específica...",
    "reason": "Por que isso tornaria o bullet mais impactante.",
    "target_angle": "resultado"
  }
}`
}

function buildUserPrompt(
    rawResponses: Array<{ phase_id: string; question: string; answer: string }>,
    course: string,
    semester: string,
    previousBullets: string[],
    clarificationAnswer?: string,
): string {
    let prompt = '## CONTEXTO DO USUÁRIO\n'
    if (course) prompt += `- Curso: ${course}\n`
    if (semester) prompt += `- Semestre: ${semester}\n`

    if (previousBullets.length > 0) {
        prompt += `\n## BULLETS JÁ APROVADOS (evite repetição, mantenha consistência de tom):\n`
        previousBullets.forEach((b, i) => { prompt += `${i + 1}. ${b}\n` })
    }

    if (clarificationAnswer) {
        prompt += `\n## INFORMAÇÃO ADICIONAL (resposta a aprofundamento anterior):\n${clarificationAnswer}\n`
    }

    prompt += '\n## RESPOSTAS DO USUÁRIO SOBRE ESTA EXPERIÊNCIA:\n\n'

    // Sort D1..D6 and format
    const sorted = [...rawResponses].sort((a, b) => a.phase_id.localeCompare(b.phase_id))
    const dLabels: Record<string, string> = {
        'd1': 'Detalhes (organização, cargo, período)',
        'd2': 'O que a organização faz',
        'd3': 'Por que foi escolhido / por que criou',
        'd4': 'O que fez concretamente',
        'd5': 'O que mudou / impacto',
        'd6': 'NÚMEROS CONCRETOS (use OBRIGATORIAMENTE em pelo menos um bullet, em bold)',
    }
    for (const r of sorted) {
        const dKey = r.phase_id.split('.').pop() ?? ''
        const label = dLabels[dKey] ?? r.question
        prompt += `**${label}**\n${r.answer}\n\n`
    }

    prompt += 'Gere os 3 bullets conforme as instruções do sistema. '
    prompt += 'Se houver números na resposta D6, INCLUA esses números '
    prompt += 'literalmente em pelo menos UM dos 3 bullets.'
    return prompt
}
