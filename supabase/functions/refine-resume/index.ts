import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
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
    const { history, originalResume, analysis } = await req.json()
    const apiKey = Deno.env.get('OPENAI_API_KEY')
    const openai = new OpenAI({ apiKey })

    const systemPrompt = `Você é um especialista em recrutamento e seleção (Tech Recruiter).
Sua missão é ajudar o usuário a melhorar o currículo dele através de um chat interativo.

CONTEXTO DO CURRÍCULO ATUAL:
${originalResume}

ANÁLISE DE PONTOS A MELHORAR:
${JSON.stringify(analysis.weaknesses)}

REGRAS:
1. Faça APENAS UMA pergunta por vez. Seja direto.
2. Se o chat está começando, escolha o ponto mais fraco e peça detalhes.
3. Quando o usuário responder (após 2-4 interações), você DEVE decidir que o chat acabou.
4. Quando o chat acabar, você DEVE retornar um JSON com "isFinished": true e o "improvedResume" contendo TODO o texto do currículo reescrito e melhorado, incorporando os novos detalhes.

EXEMPLO DE RESPOSTA FINAL:
{
  "isFinished": true,
  "message": "Parabéns! Otimizei seu currículo com base no que conversamos.",
  "improvedResume": "JOÃO SILVA\nDesenvolvedor Mobile...\n\nEXPERIÊNCIA\n- Desenvolveu app com 10k users (impacto aumentado)...\n..."
}

EXEMPLO DE PERGUNTA:
{
  "isFinished": false,
  "question": "Você mencionou que trabalhou com React, poderia me dizer qual foi o maior desafio técnico?"
}

Mantenha o tom profissional.`

    const completion = await openai.chat.completions.create({
      model: 'gpt-4o',
      messages: [
        { role: 'system', content: systemPrompt },
        ...history.map((m: any) => ({
          role: m.isBot ? 'assistant' : 'user',
          content: m.text
        }))
      ],
      response_format: { type: "json_object" }
    })

    const result = JSON.parse(completion.choices[0].message.content || '{}')
    console.log('AI Response Object:', JSON.stringify(result))

    return new Response(
      JSON.stringify(result),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
