import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Verificar autenticação
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

    // Rate limiting
    const today = new Date()
    today.setHours(0, 0, 0, 0)

    const { count } = await supabaseClient
      .from('ai_generation_logs')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', user.id)
      .eq('generation_type', 'resume_evaluation')
      .gte('created_at', today.toISOString())

    if (count && count >= 10) { 
      return new Response(
        JSON.stringify({ error: 'Rate limit exceeded. Maximum 10 resume evaluations per day.' }),
        { status: 429, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Obter dados da requisição
    const { resumeText } = await req.json()

    if (!resumeText || typeof resumeText !== 'string') {
      return new Response(
        JSON.stringify({ error: 'Invalid request body. Missing resumeText.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Chamar OpenAI
    const openaiResponse = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${Deno.env.get('OPENAI_API_KEY')}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        model: 'gpt-4o',
        messages: [
          {
            role: 'system',
            content: `Você é um recrutador sênior e especialista em análise de currículos.
Sua tarefa é ler o texto extraído de um currículo em PDF e estruturar uma avaliação detalhada.

Forneça sua resposta ESTRITAMENTE em formato JSON, com as seguintes chaves exatas:
{
  "score": <número de 0 a 100 dando a nota geral do currículo>,
  "positives": ["ponto forte 1", "ponto forte 2", ...],
  "improvements": ["ponto de melhoria 1", "ponto a corrigir 2", ...],
  "parsed_data": {
    "sobre_mim": "Resumo do perfil extraído ou reescrito de forma melhorada",
    "experiencias": "Lista de experiências em formato bullet point (•)",
    "habilidades": "Lista de habilidades em formato bullet point (•)",
    "interesses": "Lista de interesses em formato bullet point (•)"
  }
}

IMPORTANTE: 
- Seja rigoroso na nota.
- Identifique falta de métricas nas experiências, falta de foco, má formatação de texto e aponte isso na chave "improvements".
- A chave "parsed_data" deve conter o currículo reconstruído, formatado perfeitamente, pronto para ser reescrito na base de dados do usuário.`
          },
          {
            role: 'user',
            content: `Aqui está o texto bruto extraído do currículo em PDF:\n\n${resumeText}`
          }
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

    // Extrair JSON da resposta
    let jsonText = responseText.trim()
    if (jsonText.startsWith('```json')) {
      jsonText = jsonText.substring(7)
    }
    if (jsonText.startsWith('```')) {
      jsonText = jsonText.substring(3)
    }
    if (jsonText.endsWith('```')) {
      jsonText = jsonText.substring(0, jsonText.length - 3)
    }
    jsonText = jsonText.trim()

    const result = JSON.parse(jsonText)

    // Registrar geração para rate limiting
    await supabaseClient.from('ai_generation_logs').insert({
      user_id: user.id,
      generation_type: 'resume_evaluation',
      tokens_used: openaiData.usage?.total_tokens || 0,
    })

    return new Response(
      JSON.stringify(result),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error: any) {
    console.error('Error:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
