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

    // Rate limit: 10/dia
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

    const { resumeText, targetJobTitle, targetJobDescription } = await req.json()

    if (!resumeText || typeof resumeText !== 'string' || resumeText.trim().length < 100) {
      return new Response(
        JSON.stringify({
          error: 'invalid_resume_text',
          message: 'Texto do currículo está vazio ou muito curto. Verifique se o PDF tem camada de texto (não é apenas imagem/scan).',
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const hasTarget = typeof targetJobTitle === 'string' && targetJobTitle.trim().length > 0

    const targetBlock = hasTarget
      ? `\n\nVAGA-ALVO DO USUÁRIO:
- Cargo: ${targetJobTitle}
${targetJobDescription ? `- Descrição: ${targetJobDescription}` : ''}

A nota e os pontos a melhorar devem ser CONTEXTUALIZADOS para essa vaga-alvo.
Ex: "Faltam métricas de impacto comuns em vagas de produto" é melhor que "Faltam métricas".`
      : `\n\nO usuário NÃO informou vaga-alvo. Avalie o currículo de forma geral, mas mencione na resposta que uma análise mais precisa exigiria saber a vaga-alvo.`

    const systemPrompt = `Você é um recrutador sênior brasileiro especialista em análise de currículos para estágios e primeiros empregos.

Sua tarefa é ler o texto extraído de um currículo (já em texto puro, não é PDF) e produzir uma avaliação rigorosa, prática e útil.${targetBlock}

Forneça sua resposta ESTRITAMENTE em formato JSON, com estas chaves exatas:
{
  "score": <inteiro 0-100, ${hasTarget ? 'aderência à vaga-alvo' : 'qualidade geral'}>,
  "positives": ["3-5 pontos fortes específicos, citando trecho ou seção"],
  "improvements": ["3-6 melhorias acionáveis, em ordem de impacto"],
  "parsed_data": {
    "sobre_mim": "Resumo profissional de 2-3 frases extraído ou reescrito",
    "experiencias": "Bullet points (•) das experiências",
    "habilidades": "Bullet points (•) das habilidades",
    "interesses": "Bullet points (•) dos interesses (ou string vazia)"
  }
}

REGRAS:
- Seja rigoroso. Currículos de estudante raramente passam de 75 sem métricas concretas.
- "improvements" deve ser ACIONÁVEL ("Reescreva o bullet X usando verbo no passado e métrica" — não "melhore os bullets").
- "parsed_data" deve preservar fielmente o conteúdo do CV. Não invente nomes de empresas, datas ou números.
- Use português do Brasil.
- Retorne APENAS o JSON, sem markdown, sem texto antes ou depois.`

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
          { role: 'user', content: `Texto do currículo:\n\n${resumeText}` }
        ],
        temperature: 0.4,
        max_tokens: 1500,
        response_format: { type: 'json_object' },
      })
    })

    if (!openaiResponse.ok) {
      const errBody = await openaiResponse.text()
      console.error('OpenAI error:', openaiResponse.status, errBody)
      return new Response(
        JSON.stringify({ error: 'ai_provider_error', message: 'Falha temporária na análise. Tente novamente em alguns instantes.' }),
        { status: 502, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const openaiData = await openaiResponse.json()
    const responseText = openaiData.choices[0].message.content

    let result
    try {
      result = JSON.parse(responseText)
    } catch (e) {
      console.error('Failed to parse AI JSON:', responseText)
      return new Response(
        JSON.stringify({ error: 'parse_error', message: 'Resposta inválida da IA. Tente novamente.' }),
        { status: 502, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

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
      JSON.stringify({ error: 'internal_error', message: error.message || 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
