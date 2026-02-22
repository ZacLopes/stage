import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

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

        // Rate limiting: 5 relatórios de entrevista por dia
        const today = new Date()
        today.setHours(0, 0, 0, 0)

        const { count } = await supabaseClient
            .from('ai_generation_logs')
            .select('*', { count: 'exact', head: true })
            .eq('user_id', user.id)
            .eq('generation_type', 'interview')
            .gte('created_at', today.toISOString())

        if (count && count >= 5) {
            return new Response(
                JSON.stringify({ error: 'Rate limit exceeded. Maximum 5 interview reports per day.' }),
                { status: 429, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        const { answersWithQuestions } = await req.json()

        if (!answersWithQuestions || typeof answersWithQuestions !== 'object') {
            return new Response(
                JSON.stringify({ error: 'Invalid request body' }),
                { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        const prompt = buildInterviewPrompt(answersWithQuestions)

        const systemPrompt = `Você é um Coach de Carreira Sênior e Recrutador de Elite (ex-Google, ex-McKinsey).
Sua especialidade é preparar candidatos para entrevistas de alta performance.
Sua missão é analisar as respostas de um candidato em um simulado e gerar um Relatório tático de feedback BRUTALMENTE HONESTO, mas construtivo.

### FORMATO DE SAÍDA (JSON ESTRITO):
Responda APENAS com um JSON válido no seguinte formato:
{
  "spider_chart": {
    "Confiança": (0-100),
    "Storytelling": (0-100),
    "Objetividade": (0-100),
    "Fit Estratégico": (0-100)
  },
  "diagnostico": "Parágrafo curto (3-4 linhas) analisando o perfil psicológico do candidato com base nas respostas. Identifique se ele é inseguro, arrogante, despreparado ou um talento natural. Seja direto.",
  "pitch_feedback": "Análise crítica da resposta 'Fale sobre você'. Aponte O QUE melhorar (ex: 'Muito focado no passado', 'Faltou brilho nos olhos'). Reescreva a primeira frase sugerida para dar mais impacto.",
  "trap_feedback": "Feedback sobre a resposta do 'Maior Defeito'. Diga se ele caiu na armadilha (ex: 'Perfeccionismo é clichê') ou se foi autêntico. Dê uma dica de como estruturar melhor (Defeito real + O que já faz para melhorar).",
  "missoes_taticas": [
    "Missão 1: Uma tarefa prática e específica para melhorar (ex: 'Pesquise 3 concorrentes da empresa e anote em um papel').",
    "Missão 2: Outra tarefa prática (ex: 'Reescreva a história do desafio usando o modelo STAR: Situação, Tarefa, Ação, Resultado').",
    "Missão 3: Uma tarefa comportamental (ex: 'Grave um vídeo de 2 min respondendo a pergunta X e assista sem som para ver sua linguagem corporal')."
  ]
}

### CRITÉRIOS DE AVALIAÇÃO:
1.  **Spider Chart:**
    *   *Confiança:* Baseado nas respostas de autoavaliação (escala 0-10) e tom da escrita.
    *   *Storytelling:* Baseado na qualidade das histórias STAR (tem começo, meio, fim e resultado claro?).
    *   *Objetividade:* O candidato enrola ou vai direto ao ponto?
    *   *Fit Estratégico:* Ele entende o jogo corporativo? Sabe "se vender"?

2.  **Diagnóstico:** Não use "sopa de letrinhas" de RH. Fale como um mentor experiente falando a real para o mentorado. Use negrito (markdown) para destacar pontos chaves.

3.  **Feedback Específico:** Não dê dicas genéricas como "Seja você mesmo". Dê dicas TÁTICAS.`

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
                temperature: 0.7,
                max_tokens: 2000,
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
            generation_type: 'interview',
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

function buildInterviewPrompt(answersWithQuestions: Record<string, string>): string {
    if (Object.keys(answersWithQuestions).length === 0) {
        return 'O usuário não respondeu nada. Gere um feedback genérico criticando a falta de preparação.'
    }

    let prompt = 'Analise as seguintes respostas do candidato no simulado de entrevista:\n\n'

    for (const [question, answer] of Object.entries(answersWithQuestions)) {
        prompt += `PERGUNTA: ${question}\n`
        prompt += `RESPOSTA: ${answer}\n`
        prompt += '---\n'
    }

    prompt += 'Gere o Relatório de Performance conforme o formato JSON solicitado.'

    return prompt
}
