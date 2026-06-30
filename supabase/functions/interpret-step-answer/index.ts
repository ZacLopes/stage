// interpret-step-answer (PLANO chat v2 — F4): mapeia TEXTO LIVRE digitado na
// barra do chat da trilha para os IDs das OPÇÕES de um passo de escolha.
//
// Entrada (JSON): { stepId, question, freeText, options:[{id,label}], multi }
// Saída  (JSON): { matched_ids:[...], confidence:'high'|'medium'|'low', reason }
//
// Failure-safe por construção: o cliente (AIService.interpretStepAnswer) trata
// qualquer não-200/timeout como null e cai no widget. Aqui, sem opções ou sem
// texto, devolve matched_ids vazio + low SEM gastar chamada de IA.
//
// Auth: JWT do usuário (getUser via Authorization do req) — default verify_jwt
// do CLI; NÃO precisa de entrada no config.toml. Modelo: gpt-4o-mini.

import { serve } from 'std/http/server'
import { createClient } from 'supabase'
import { trackAIGeneration, withEdgeAnalytics } from '../_shared/posthog.ts'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface OptionIn {
    id: string
    label: string
}

serve(withEdgeAnalytics('interpret-step-answer', async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        const client = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_ANON_KEY') ?? '',
            { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
        )

        const { data: { user }, error: authError } = await client.auth.getUser()
        if (authError || !user) {
            return new Response(
                JSON.stringify({ error: 'Unauthorized' }),
                { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }
        const userId = user.id

        // Normaliza pra objeto: JSON válido porém escalar/null (ex.: `null`, `42`)
        // não dispara o .catch — sem isso, ler body.x lançaria e viraria 500.
        const rawBody = await req.json().catch(() => ({}))
        const body: Record<string, unknown> =
            (rawBody && typeof rawBody === 'object') ? rawBody as Record<string, unknown> : {}
        const question = String(body.question ?? '').trim()
        const freeText = String(body.freeText ?? '').trim()
        const multi = body.multi === true
        const rawOptions = Array.isArray(body.options) ? body.options : []
        const options: OptionIn[] = rawOptions
            .map((o: unknown) => {
                const m = o as Record<string, unknown>
                return { id: String(m?.id ?? ''), label: String(m?.label ?? '') }
            })
            .filter((o: OptionIn) => o.id.length > 0)

        // Sem opções ou sem texto → nada a interpretar (não gasta IA).
        if (options.length === 0 || freeText.length === 0) {
            return new Response(
                JSON.stringify({ matched_ids: [], confidence: 'low', reason: 'empty' }),
                { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        const validIds = new Set(options.map((o) => o.id))
        const optionLines = options.map((o) => `- ${o.id} — ${o.label}`).join('\n')

        const systemPrompt = [
            'Você é um classificador de respostas de um formulário de currículo em PT-BR.',
            'O usuário digitou texto livre respondendo a uma pergunta que tem OPÇÕES FIXAS.',
            'Mapeie o texto para os IDs das opções que correspondem.',
            'REGRAS:',
            '- Use SOMENTE os ids da lista. NUNCA invente um id.',
            '- Se multi=false, retorne no máximo 1 id (o melhor).',
            '- Se multi=true, retorne todos os ids que o texto mencionar.',
            '- Se o texto não casar com clareza com nenhuma opção, retorne matched_ids vazio e confidence "low".',
            '- confidence: "high" quando o texto claramente bate; "medium" para inferência razoável; "low" para chute.',
            'Responda APENAS com JSON no formato:',
            '{"matched_ids": ["id"], "confidence": "high", "reason": "curto"}',
        ].join('\n')

        const userPrompt = [
            `Pergunta: ${question || '(sem enunciado)'}`,
            `multi: ${multi}`,
            'Opções (id — label):',
            optionLines,
            `Resposta do usuário: "${freeText}"`,
        ].join('\n')

        const aiStart = Date.now()
        const openaiResponse = await fetch('https://api.openai.com/v1/chat/completions', {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${Deno.env.get('OPENAI_API_KEY')}`,
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                model: 'gpt-4o-mini',
                messages: [
                    { role: 'system', content: systemPrompt },
                    { role: 'user', content: userPrompt },
                ],
                temperature: 0,
                max_tokens: 200,
                response_format: { type: 'json_object' },
            }),
        })

        if (!openaiResponse.ok) {
            trackAIGeneration({
                userId, generationType: 'step_answer_interpretation', model: 'gpt-4o-mini',
                inputTokens: 0, outputTokens: 0, latencyMs: Date.now() - aiStart, isError: true,
            }).catch(() => {})
            throw new Error(`OpenAI API error: ${openaiResponse.statusText}`)
        }

        const openaiData = await openaiResponse.json()
        trackAIGeneration({
            userId, generationType: 'step_answer_interpretation', model: 'gpt-4o-mini',
            inputTokens: openaiData.usage?.prompt_tokens ?? 0,
            outputTokens: openaiData.usage?.completion_tokens ?? 0,
            latencyMs: Date.now() - aiStart,
        }).catch(() => {})

        let matchedIds: string[] = []
        let confidence = 'low'
        let reason = ''
        try {
            const parsed = JSON.parse(openaiData.choices[0].message.content)
            const raw = Array.isArray(parsed.matched_ids) ? parsed.matched_ids : []
            // Só ids REAIS da lista (filtra alucinação); de-dup mantendo a ordem.
            const seen = new Set<string>()
            for (const x of raw) {
                const id = String(x)
                if (validIds.has(id) && !seen.has(id)) {
                    seen.add(id)
                    matchedIds.push(id)
                }
            }
            // multi=false → no máximo 1 (defesa; o cliente também corta).
            if (!multi && matchedIds.length > 1) matchedIds = [matchedIds[0]]
            const c = String(parsed.confidence ?? '').toLowerCase()
            confidence = (c === 'high' || c === 'medium' || c === 'low') ? c : 'low'
            reason = String(parsed.reason ?? '').slice(0, 200)
        } catch (_) {
            // Resposta malformada — devolve vazio/low (cliente cai no widget).
        }

        // Nada casou → rebaixa a confiança (coerência com o cliente).
        if (matchedIds.length === 0) confidence = 'low'

        return new Response(
            JSON.stringify({ matched_ids: matchedIds, confidence, reason }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    } catch (error) {
        console.error('interpret-step-answer error:', error)
        return new Response(
            JSON.stringify({ error: (error as Error).message ?? 'Internal server error' }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    }
}))
