import { serve } from 'std/http/server'
import { createClient } from 'supabase'
import { trackAIGeneration } from '../_shared/posthog.ts'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

/**
 * suggest-tools Edge Function
 *
 * Reads the user's M1 answers (area of interest, opportunity type, professional vision)
 * and returns the 15 tools/technologies most commonly required in real Brazilian job
 * listings for that profile.
 *
 * Request:  { campaign_id: string }
 * Response: { tools: string[], job_context: string }
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

        // 1. M1 answers: area (m1.1), opportunity type (m1.2), professional vision (m1.3)
        const { data: m1Answers } = await supabaseClient
            .from('raw_responses')
            .select('phase_id, answer')
            .eq('user_id', user.id)
            .in('phase_id', ['m1.1', 'm1.2', 'm1.3'])

        const area = m1Answers?.find(r => r.phase_id === 'm1.1')?.answer ?? ''
        const opportunityType = m1Answers?.find(r => r.phase_id === 'm1.2')?.answer ?? ''
        const vision = m1Answers?.find(r => r.phase_id === 'm1.3')?.answer ?? ''

        // 2. User profile (course)
        const { data: userProfile } = await supabaseClient
            .from('user_profiles')
            .select('course')
            .eq('id', user.id)
            .single()

        const course = userProfile?.course ?? ''

        // 3. Campaign target job (if user set a specific one — optional override)
        const { data: campaign } = await supabaseClient
            .from('campaigns')
            .select('target_job_id, target_jobs(title, description_text, is_skipped)')
            .eq('id', campaign_id)
            .eq('user_id', user.id)
            .single()

        const targetJob = campaign?.target_jobs as {
            title?: string
            description_text?: string
            is_skipped?: boolean
        } | null

        const specificJobTitle = (!targetJob?.is_skipped && targetJob?.title) ? targetJob.title : null
        const specificJobDesc = (!targetJob?.is_skipped && targetJob?.description_text) ? targetJob.description_text : null

        // 4. Build job context string (for display in the UI)
        const parts: string[] = []
        if (specificJobTitle) {
            parts.push(specificJobTitle)
        } else {
            if (opportunityType) parts.push(opportunityType)
            if (area) parts.push(area)
        }
        const jobContext = parts.join(' em ') || 'estágio ou primeiro emprego'

        // 5. Build GPT prompt
        const contextLines: string[] = []
        if (specificJobTitle) {
            contextLines.push(`Vaga específica: "${specificJobTitle}"`)
            if (specificJobDesc) contextLines.push(`Descrição: ${specificJobDesc.slice(0, 400)}`)
        } else {
            if (opportunityType) contextLines.push(`Tipo de oportunidade: ${opportunityType}`)
            if (area) contextLines.push(`Área de interesse: ${area}`)
            if (vision) contextLines.push(`Visão profissional do candidato: "${vision.slice(0, 300)}"`)
            if (course) contextLines.push(`Curso: ${course}`)
        }

        const contextBlock = contextLines.length > 0
            ? contextLines.join('\n')
            : 'Estudante universitário buscando estágio ou primeiro emprego no mercado brasileiro'

        const prompt = `Você é um especialista em recrutamento no Brasil com acesso a milhares de descrições de vagas reais.

Perfil do candidato:
${contextBlock}

Liste as 15 ferramentas, softwares e tecnologias mais frequentemente requisitadas em vagas reais brasileiras para este perfil em 2024/2025.

Seja específico e prático: prefira nomes exatos (ex: "Power BI", "Figma", "Python") em vez de categorias genéricas. Misture ferramentas técnicas e de produtividade relevantes para a área.

Responda APENAS com JSON: {"tools": ["Ferramenta1", "Ferramenta2", ...]}`

        const aiStart = Date.now()
        const openaiResponse = await fetch('https://api.openai.com/v1/chat/completions', {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${Deno.env.get('OPENAI_API_KEY')}`,
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                model: 'gpt-4o-mini',
                messages: [{ role: 'user', content: prompt }],
                temperature: 0.4,
                max_tokens: 300,
                response_format: { type: 'json_object' },
            }),
        })

        if (!openaiResponse.ok) {
            trackAIGeneration({
                userId: user.id,
                generationType: 'suggest_tools',
                model: 'gpt-4o-mini',
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
            generationType: 'suggest_tools',
            model: 'gpt-4o-mini',
            inputTokens: openaiData.usage?.prompt_tokens ?? 0,
            outputTokens: openaiData.usage?.completion_tokens ?? 0,
            latencyMs: Date.now() - aiStart,
        }).catch(() => {})
        const raw = openaiData.choices[0].message.content ?? '{}'

        let tools: string[] = []
        try {
            const parsed = JSON.parse(raw)
            tools = Array.isArray(parsed)
                ? parsed
                : (parsed.tools ?? parsed.ferramentas ?? Object.values(parsed)[0] ?? [])
            tools = tools.filter((t: unknown) => typeof t === 'string' && t.trim().length > 0)
        } catch {
            tools = []
        }

        return new Response(
            JSON.stringify({ tools, job_context: jobContext }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )

    } catch (error) {
        console.error('suggest-tools error:', error)
        return new Response(
            JSON.stringify({ error: (error as Error).message ?? 'Internal server error' }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    }
})
