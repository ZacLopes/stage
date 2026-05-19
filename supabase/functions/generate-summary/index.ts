import { serve } from 'std/http/server'
import { createClient } from 'supabase'
import { trackAIGeneration } from '../_shared/posthog.ts'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

/**
 * generate-summary Edge Function
 *
 * Generates a professional summary (resumo profissional) by synthesizing
 * all approved bullets + target job + user profile.
 * Saves the result to section_versions and returns it.
 *
 * Request: { campaign_id: string }
 * Response: { summary: string, version_id: string }
 */
serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        const supabaseClient = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_ANON_KEY') ?? '',
            { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
        )

        const { data: { user }, error: authError } = await supabaseClient.auth.getUser()
        if (authError || !user) {
            return new Response(
                JSON.stringify({ error: 'Unauthorized' }),
                { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        const { campaign_id } = await req.json()
        if (!campaign_id) {
            return new Response(
                JSON.stringify({ error: 'campaign_id is required' }),
                { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // 1. Fetch approved bullets for this campaign
        const { data: approvedBullets } = await supabaseClient
            .from('approved_bullets')
            .select('final_text, experience_phase_id, display_order')
            .eq('campaign_id', campaign_id)
            .eq('is_active', true)
            .order('display_order', { ascending: true })

        if (!approvedBullets || approvedBullets.length === 0) {
            return new Response(
                JSON.stringify({ error: 'No approved bullets found for this campaign' }),
                { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // 2. Fetch campaign + target job
        const { data: campaign } = await supabaseClient
            .from('campaigns')
            .select('target_job_id, target_jobs(title, description_text)')
            .eq('id', campaign_id)
            .eq('user_id', user.id)
            .single()

        const targetJob = campaign?.target_jobs as { title?: string; description_text?: string } | null

        // 3. Fetch user profile
        const { data: userProfile } = await supabaseClient
            .from('user_profiles')
            .select('course, gamification_data')
            .eq('id', user.id)
            .single()

        const gamificationData = userProfile?.gamification_data ?? {}
        const module2 = gamificationData?.module2?.myBase ?? {}
        const course = userProfile?.course ?? module2?.education?.course ?? ''
        const semester = module2?.education?.semester ?? ''
        const institution = module2?.education?.institution ?? ''

        // 4. Fetch M1 context
        const { data: m1Answers } = await supabaseClient
            .from('raw_responses')
            .select('phase_id, answer')
            .eq('user_id', user.id)
            .in('phase_id', ['m1.1', 'm1.3'])

        const interestAreas = m1Answers?.find(r => r.phase_id === 'm1.1')?.answer ?? ''
        const visionText = m1Answers?.find(r => r.phase_id === 'm1.3')?.answer ?? ''

        // 5. Determine existing version number
        const { count: versionCount } = await supabaseClient
            .from('section_versions')
            .select('*', { count: 'exact', head: true })
            .eq('campaign_id', campaign_id)
            .eq('section_type', 'resumo_profissional')

        const nextVersion = (versionCount ?? 0) + 1

        // 6. Build prompt
        const systemPrompt = buildSummarySystemPrompt(targetJob, interestAreas, visionText, course, semester, institution)
        const userPrompt = buildSummaryUserPrompt(approvedBullets)

        const aiStart = Date.now()
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
                temperature: 0.6,
                max_tokens: 400,
            }),
        })

        if (!openaiResponse.ok) {
            trackAIGeneration({
                userId: user.id,
                generationType: 'summary_generation',
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
            generationType: 'summary_generation',
            model: 'gpt-4o',
            inputTokens: openaiData.usage?.prompt_tokens ?? 0,
            outputTokens: openaiData.usage?.completion_tokens ?? 0,
            latencyMs: Date.now() - aiStart,
        }).catch(() => {})
        const summaryText = openaiData.choices[0].message.content.trim()

        // 7. Save to section_versions
        const { data: inserted, error: insertError } = await supabaseClient
            .from('section_versions')
            .insert({
                campaign_id,
                user_id: user.id,
                section_type: 'resumo_profissional',
                content: summaryText,
                version_number: nextVersion,
                model_used: 'gpt-4o',
                was_chosen: false,
                was_edited: false,
            })
            .select('id')
            .single()

        if (insertError) {
            console.error('Error saving section version:', insertError)
        }

        return new Response(
            JSON.stringify({ summary: summaryText, version_id: inserted?.id ?? null }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )

    } catch (error) {
        console.error('generate-summary error:', error)
        return new Response(
            JSON.stringify({ error: (error as Error).message ?? 'Internal server error' }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    }
})

function buildSummarySystemPrompt(
    targetJob: { title?: string; description_text?: string } | null,
    interestAreas: string,
    visionText: string,
    course: string,
    semester: string,
    institution: string,
): string {
    return `Você é um ghostwriter especializado em currículos para estudantes universitários brasileiros.

## TAREFA
Escreva UM resumo profissional sintético de 3-4 linhas (~60-80 palavras) para o candidato.
O resumo vai aparecer no topo do currículo como "Sobre mim" ou "Resumo Profissional".

## CONTEXTO DO CANDIDATO
Vaga-alvo: ${targetJob?.title ?? 'Estágio ou Primeiro Emprego'}
${targetJob?.description_text ? `Descrição da vaga: ${targetJob.description_text}` : ''}
Curso: ${course}${semester ? ` (${semester} semestre)` : ''}
${institution ? `Instituição: ${institution}` : ''}
Área de interesse: ${interestAreas || 'não informada'}
Norte profissional: ${visionText || 'não informado'}

## REGRAS
- Conecte o perfil do candidato com a vaga-alvo
- Mencione a formação, área de interesse e diferenciais que aparecem nos bullets
- Português brasileiro, tom profissional mas humano (não robótico)
- NÃO use clichês como "profissional proativo", "foco em resultados", "perfil inovador"
- NÃO invente informações não presentes nos bullets ou no contexto
- Primeira pessoa implícita (não use "Eu sou")
- Retorne APENAS o texto do resumo, sem formatação extra, sem aspas, sem título`
}

function buildSummaryUserPrompt(
    approvedBullets: Array<{ final_text: string; experience_phase_id: string | null }>,
): string {
    let prompt = '## BULLETS APROVADOS DO CANDIDATO (síntese do que ele fez):\n\n'
    approvedBullets.forEach((b, i) => {
        prompt += `${i + 1}. ${b.final_text}\n`
    })
    prompt += '\nEscreva o resumo profissional sintetizando essas experiências e conectando com a vaga-alvo.'
    return prompt
}
