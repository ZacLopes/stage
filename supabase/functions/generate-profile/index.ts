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

    // Rate limiting: Verificar quantas gerações o usuário fez hoje
    const today = new Date()
    today.setHours(0, 0, 0, 0)

    const { count } = await supabaseClient
      .from('ai_generation_logs')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', user.id)
      .eq('generation_type', 'profile')
      .gte('created_at', today.toISOString())

    if (count && count >= 20) { // Limite: 20 gerações de perfil por dia
      return new Response(
        JSON.stringify({ error: 'Rate limit exceeded. Maximum 20 profile generations per day.' }),
        { status: 429, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Obter dados da requisição
    const { answersWithQuestions } = await req.json()

    if (!answersWithQuestions || typeof answersWithQuestions !== 'object') {
      return new Response(
        JSON.stringify({ error: 'Invalid request body' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Construir prompt
    const prompt = buildPrompt(answersWithQuestions)

    // Chamar OpenAI (chave fica APENAS no servidor)
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
            content: `Você é um assistente especializado em desenvolvimento de perfil profissional.
Sua tarefa é analisar as respostas de um estudante universitário e gerar um perfil profissional coerente e atrativo.
IMPORTANTE: Use APENAS as informações fornecidas nas respostas. NÃO invente dados. Se não houver informação suficiente para uma seção, retorne uma string vazia para esse campo.
Responda APENAS com um JSON válido no seguinte formato:
{
  "sobre_mim": "Texto descritivo em PRIMEIRA PESSOA (ex: 'Sou estudante de...', 'Busco oportunidades...') baseado nas respostas (2-3 frases) OU string vazia se não houver dados",
  "experiencias": "Lista de experiências baseadas nas respostas (formato bullet point com • no início de cada linha) OU string vazia",
  "habilidades": "Lista de habilidades baseadas nas respostas (formato bullet point com • no início de cada linha) OU string vazia. IMPORTANTE: Não inclua idiomas aqui, apenas competências técnicas e comportamentais.",
  "interesses": "Lista de interesses baseados nas respostas (formato bullet point com • no início de cada linha) OU string vazia"
}`
          },
          {
            role: 'user',
            content: prompt
          }
        ],
        temperature: 0.7,
        max_tokens: 1000,
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
      generation_type: 'profile',
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

function buildPrompt(answersWithQuestions: Record<string, string>): string {
  if (Object.keys(answersWithQuestions).length === 0) {
    return 'O usuário ainda não respondeu nenhuma pergunta. Crie um perfil genérico para um estudante universitário.'
  }

  let prompt = 'Aqui estão as respostas do usuário:\n\n'

  for (const [question, answer] of Object.entries(answersWithQuestions)) {
    prompt += `Pergunta: ${question}\n`
    prompt += `Resposta: ${answer}\n\n`
  }

  prompt += 'Com base nessas respostas, gere um perfil profissional completo.'

  return prompt
}
