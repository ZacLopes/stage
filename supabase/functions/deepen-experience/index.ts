import { serve } from 'std/http/server'
import { createClient } from 'supabase'
import { trackAIGeneration } from '../_shared/posthog.ts'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

/**
 * deepen-experience Edge Function
 * 
 * AI-Interviewer role: When the AI-Writer detects shallow information,
 * this function generates a targeted follow-up question to extract
 * more specific, impactful details from the user.
 * 
 * Separated from generate-bullets because:
 * 1. Different cognitive task = different prompt optimization
 * 2. Can be called independently (e.g., user wants to improve an existing bullet)
 * 3. Different tone: curious & non-evaluative (interviewer) vs precise (writer)
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

        const { data: { user }, error: authError } = await supabaseClient.auth.getUser()
        if (authError || !user) {
            return new Response(
                JSON.stringify({ error: 'Unauthorized' }),
                { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        const {
            rawResponses,    // What the user already said about this experience
            currentBullets,  // The bullets generated so far (so AI knows what's missing)
            experienceType,  // 'corporate', 'startup', etc.
            targetAngle,     // Which angle needs improvement: 'resultado', 'processo', 'habilidade'
        } = await req.json()

        if (!rawResponses || !Array.isArray(rawResponses)) {
            return new Response(
                JSON.stringify({ error: 'rawResponses is required' }),
                { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        const systemPrompt = buildInterviewerPrompt(experienceType, targetAngle)
        const userPrompt = buildDeepeningPrompt(rawResponses, currentBullets)

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
                    { role: 'user', content: userPrompt }
                ],
                temperature: 0.6,
                max_tokens: 300, // Just need a question + reason
                response_format: { type: 'json_object' },
            })
        })

        if (!openaiResponse.ok) {
            trackAIGeneration({
                userId: user.id,
                generationType: 'deepen_experience',
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
            generationType: 'deepen_experience',
            model: 'gpt-4o',
            inputTokens: openaiData.usage?.prompt_tokens ?? 0,
            outputTokens: openaiData.usage?.completion_tokens ?? 0,
            latencyMs: Date.now() - aiStart,
        }).catch(() => {})
        const result = JSON.parse(openaiData.choices[0].message.content)

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


function buildInterviewerPrompt(experienceType?: string, targetAngle?: string): string {
    return `Você é um entrevistador de carreira amigável, curioso e não-avaliativo.
Seu trabalho é fazer UMA pergunta que ajude o estudante a lembrar de detalhes específicos sobre sua experiência.

## TOM DE VOZ
- Curioso, nunca avaliativo ("Que legal!" em vez de "Isso é bom")
- Conversacional, como um amigo que está genuinamente interessado
- Específico: pergunte sobre DETALHES, não generalidades

## O QUE VOCÊ PROCURA
${targetAngle === 'resultado' ? '- NÚMEROS: quantas pessoas, quanto cresceu, qual volume, qual prazo' : ''}
${targetAngle === 'processo' ? '- MÉTODO: que ferramentas usou, como organizou, qual foi o passo-a-passo' : ''}
${targetAngle === 'habilidade' ? '- COMPETÊNCIA: o que você aprendeu, qual habilidade desenvolveu, como isso te preparou' : ''}
${!targetAngle ? '- Qualquer detalhe que torne a experiência mais concreta e específica' : ''}

## TIPO DE EXPERIÊNCIA
${experienceType || 'geral'}

## REGRAS
- Faça EXATAMENTE 1 pergunta (não 2, não 3)
- A pergunta deve ser respondível em 1-2 frases
- Nunca pergunte algo que o usuário já respondeu
- Use a escada de 3-4 perguntas mentalmente (esse é o aprofundamento, não o início)

## FORMATO DE RESPOSTA (JSON)
{
  "question": "A pergunta de aprofundamento...",
  "reason": "Por que essa informação melhoraria o currículo (mostrado ao usuário)",
  "emoji": "💡",
  "target_angle": "resultado | processo | habilidade"
}`
}


function buildDeepeningPrompt(
    rawResponses: Array<{ question: string, answer: string }>,
    currentBullets?: Array<{ angle: string, content: string, confidence: number }>
): string {
    let prompt = '## O QUE O USUÁRIO JÁ DISSE:\n\n'

    rawResponses.forEach(r => {
        prompt += `**P:** ${r.question}\n**R:** ${r.answer}\n\n`
    })

    if (currentBullets && currentBullets.length > 0) {
        prompt += '## BULLETS GERADOS ATÉ AGORA (e seus scores de confiança):\n\n'
        currentBullets.forEach(b => {
            prompt += `- [${b.angle}] (confiança: ${b.confidence}) ${b.content}\n`
        })
        prompt += '\nIdentifique qual bullet ficou mais fraco e gere a pergunta que melhoraria esse bullet.\n'
    }

    prompt += '\nGere a pergunta de aprofundamento.'
    return prompt
}
