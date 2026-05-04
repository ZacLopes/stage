import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { OpenAI } from "https://esm.sh/openai@4.28.0"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Auth: only authenticated users can refine.
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

    // Rate limit: 30 chamadas/dia. O chat consome múltiplas (uma por turno),
    // então o teto precisa acomodar 5-6 sessões completas.
    const today = new Date()
    today.setHours(0, 0, 0, 0)

    const { count } = await supabaseClient
      .from('ai_generation_logs')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', user.id)
      .eq('generation_type', 'resume_refine')
      .gte('created_at', today.toISOString())

    if (count && count >= 30) {
      return new Response(
        JSON.stringify({ error: 'Rate limit exceeded. Maximum 30 refinement turns per day.' }),
        { status: 429, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const { history, originalResume, analysis } = await req.json()

    if (!originalResume || typeof originalResume !== 'string') {
      return new Response(
        JSON.stringify({ error: 'invalid_request', message: 'Missing originalResume' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const apiKey = Deno.env.get('OPENAI_API_KEY')
    const openai = new OpenAI({ apiKey })

    const systemPrompt = `Você é um especialista em recrutamento e seleção (Tech Recruiter).
Sua missão é ajudar o usuário a melhorar o currículo dele através de um chat interativo.

CONTEXTO DO CURRÍCULO ATUAL:
${originalResume}

ANÁLISE DE PONTOS A MELHORAR:
${JSON.stringify(analysis?.weaknesses ?? [])}

REGRAS:
1. Faça APENAS UMA pergunta por vez. Seja direto.
2. Se o chat está começando, escolha o ponto mais fraco e peça detalhes.
3. Quando o usuário responder (após 2-4 interações), você DEVE decidir que o chat acabou.
4. Quando o chat acabar, você DEVE retornar um JSON com "isFinished": true e o "improvedResume" contendo TODO o texto do currículo reescrito e melhorado, incorporando os novos detalhes.

EXEMPLO DE RESPOSTA FINAL:
{
  "isFinished": true,
  "message": "Parabéns! Otimizei seu currículo com base no que conversamos.",
  "improvedResume": "JOÃO SILVA\\nDesenvolvedor Mobile..."
}

EXEMPLO DE PERGUNTA:
{
  "isFinished": false,
  "question": "Você mencionou que trabalhou com React, qual foi o maior desafio técnico?"
}

Mantenha o tom profissional.`

    const completion = await openai.chat.completions.create({
      model: 'gpt-4o',
      messages: [
        { role: 'system', content: systemPrompt },
        ...(Array.isArray(history) ? history : []).map((m: any) => ({
          role: m.isBot ? 'assistant' : 'user',
          content: m.text
        }))
      ],
      response_format: { type: "json_object" }
    })

    const result = JSON.parse(completion.choices[0].message.content || '{}')

    // Log para rate limiting
    await supabaseClient.from('ai_generation_logs').insert({
      user_id: user.id,
      generation_type: 'resume_refine',
      tokens_used: completion.usage?.total_tokens || 0,
    })

    return new Response(
      JSON.stringify(result),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error: any) {
    console.error('refine-resume error:', error)
    return new Response(
      JSON.stringify({ error: 'internal_error', message: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
