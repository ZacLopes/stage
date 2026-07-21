import { serve } from 'std/http/server'
import { createClient } from 'supabase'
import { trackAIGeneration, withEdgeAnalytics } from '../_shared/posthog.ts'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

/**
 * generate-profile-summary Edge Function
 *
 * Sintetiza um headline (1 linha) + resumo profissional (3-4 linhas) a partir do
 * PERFIL RELACIONAL (profile_*) — desacoplado da gamificação legacy (que usa
 * campaign_id / section_versions). Usado pela trilha de coleta pra "completar" a
 * aba Perfil ao final. Grava em profile_personal.headline/summary (JWT do usuário,
 * RLS-safe). Disciplina anti-invenção: só sintetiza o que foi informado.
 *
 * Request:  {} (usuário vem do JWT)
 * Response: { headline: string, summary: string } | { skipped: true }
 */
serve(withEdgeAnalytics('generate-profile-summary', async (req) => {
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

        // 1. Lê o perfil relacional (em paralelo).
        const [personalR, expR, eduR, skillsR, langsR, desiredR, certsR, projsR, interestsR] = await Promise.all([
            client.from('profile_personal')
                .select('first_name,headline,summary,location_city,location_state')
                .eq('user_id', userId).maybeSingle(),
            client.from('profile_experiences')
                .select('title,company,is_current,profile_bullets(text)').eq('user_id', userId),
            client.from('profile_education')
                .select('institution,degree,current_semester,education_status,profile_education_majors(name)')
                .eq('user_id', userId),
            client.from('profile_skills').select('name').eq('user_id', userId),
            client.from('profile_languages').select('name').eq('user_id', userId),
            client.from('profile_desired_titles').select('title').eq('user_id', userId),
            client.from('profile_certifications').select('name').eq('user_id', userId),
            client.from('profile_projects').select('name,description').eq('user_id', userId),
            client.from('profile_interests').select('name').eq('user_id', userId),
        ])

        const personal = personalR.data
        const firstName = (personal?.first_name ?? '').trim()
        const city = (personal?.location_city ?? '').trim()
        const areas = (desiredR.data ?? []).map((d) => d.title).filter(Boolean) as string[]
        const skills = (skillsR.data ?? []).map((s) => s.name).filter(Boolean) as string[]
        const languages = (langsR.data ?? []).map((l) => l.name).filter(Boolean) as string[]
        const certs = (certsR.data ?? []).map((c) => c.name).filter(Boolean) as string[]
        const experiences = (expR.data ?? []).map((e) => ({
            title: e.title as string | null,
            company: e.company as string | null,
            isCurrent: e.is_current as boolean | null,
            bullets: ((e.profile_bullets ?? []) as Array<{ text: string }>)
                .map((b) => b.text).filter(Boolean),
        }))
        const education = (eduR.data ?? []).map((e) => ({
            institution: e.institution as string | null,
            degree: e.degree as string | null,
            semester: e.current_semester as number | null,
            status: e.education_status as string | null,
            majors: ((e.profile_education_majors ?? []) as Array<{ name: string }>).map((m) => m.name),
        }))
        const projects = (projsR.data ?? []).map((p) => ({
            name: p.name as string | null,
            description: p.description as string | null,
        }))
        const interests = (interestsR.data ?? []).map((i) => i.name).filter(Boolean) as string[]

        // 2. Gate de substância: sem NADA pra sintetizar, não gera resumo oco.
        const hasSubstance =
            experiences.length > 0 || skills.length > 0 || areas.length > 0 ||
            education.length > 0 || projects.length > 0 || certs.length > 0
        if (!hasSubstance) {
            return new Response(
                JSON.stringify({ skipped: true }),
                { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // 3. Monta o contexto e chama a IA.
        const systemPrompt = buildSystemPrompt()
        const userPrompt = buildUserPrompt({ firstName, city, areas, skills, languages, certs, interests, experiences, education, projects })

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
                temperature: 0.5,
                max_tokens: 450,
                response_format: { type: 'json_object' },
            }),
        })

        if (!openaiResponse.ok) {
            trackAIGeneration({
                userId, generationType: 'profile_summary_generation', model: 'gpt-4o',
                inputTokens: 0, outputTokens: 0, latencyMs: Date.now() - aiStart, isError: true,
            }).catch(() => {})
            throw new Error(`OpenAI API error: ${openaiResponse.statusText}`)
        }

        const openaiData = await openaiResponse.json()
        trackAIGeneration({
            userId, generationType: 'profile_summary_generation', model: 'gpt-4o',
            inputTokens: openaiData.usage?.prompt_tokens ?? 0,
            outputTokens: openaiData.usage?.completion_tokens ?? 0,
            latencyMs: Date.now() - aiStart,
        }).catch(() => {})

        let headline = ''
        let summary = ''
        try {
            const parsed = JSON.parse(openaiData.choices[0].message.content)
            headline = String(parsed.headline ?? '').trim()
            summary = String(parsed.summary ?? '').trim()
        } catch (_) {
            // Resposta malformada — não grava lixo.
        }
        if (!summary) {
            throw new Error('IA não retornou um resumo válido')
        }

        // 4. Grava com CAS (Gate 3.0H): não sobrescreve uma edição manual
        // concorrente de summary/headline. Os "esperados" são o que a IA
        // observou no passo 1 (personalR); se o vivo mudou desde então, volta
        // 'stale' e o banco mantém a edição manual. RLS/auth via JWT do usuário
        // (auth.uid() == userId). O trigger recalcula completeness.
        const expectedSummary = (personal?.summary ?? '').trim()
        const expectedHeadline = (personal?.headline ?? '').trim()
        const { data: casResult, error: updateError } = await client.rpc(
            'set_profile_summary_cas',
            {
                p_user_id: userId,
                p_summary: summary,
                p_headline: headline,
                p_expected_summary: expectedSummary,
                p_expected_headline: expectedHeadline,
            },
        )
        if (updateError) {
            console.error('generate-profile-summary set_profile_summary_cas error:', updateError)
            throw new Error('Falha ao salvar o resumo')
        }
        if (casResult === 'stale') {
            // Edição manual concorrente venceu; não sobrescrevemos. O app
            // recarrega o perfil e vê o estado real; devolvemos a sugestão.
            console.warn('[generate-profile-summary] CAS stale — mantida a edição manual')
        }

        return new Response(
            JSON.stringify({ headline, summary }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    } catch (error) {
        console.error('generate-profile-summary error:', error)
        return new Response(
            JSON.stringify({ error: (error as Error).message ?? 'Internal server error' }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    }
}))

function buildSystemPrompt(): string {
    return `Você é um ghostwriter especializado em currículos para estudantes universitários e candidatos a estágio/primeiro emprego no Brasil.

## TAREFA
A partir do perfil do candidato, escreva DOIS textos:
1. "headline": UMA linha curta (máx ~70 caracteres) que resume quem é o candidato e o que busca. Ex.: "Estudante de Administração (5º sem) buscando estágio em Marketing".
2. "summary": um resumo profissional de 3-4 linhas (~60-80 palavras) pra aparecer no topo do perfil/currículo como "Sobre mim".

## REGRAS (cumpra TODAS)
- Use SOMENTE informações presentes no perfil abaixo. NÃO invente experiências, números, resultados, empresas ou habilidades que não foram informados.
- Sem clichês: proibido "profissional proativo", "foco em resultados", "perfil dinâmico/inovador", "busco desafios".
- Português brasileiro, tom profissional mas humano (não robótico).
- Conecte formação + área de interesse + o que a pessoa já fez (experiências/projetos/skills).
- Primeira pessoa implícita (NÃO use "Eu sou" / "Eu tenho").
- Se houver pouca informação, escreva algo curto e honesto — não encha linguiça.
- Retorne APENAS um JSON válido: {"headline": "...", "summary": "..."} — sem markdown, sem texto fora do JSON.`
}

interface ProfileContext {
    firstName: string
    city: string
    areas: string[]
    skills: string[]
    languages: string[]
    certs: string[]
    interests: string[]
    experiences: Array<{ title: string | null; company: string | null; isCurrent: boolean | null; bullets: string[] }>
    education: Array<{ institution: string | null; degree: string | null; semester: number | null; status: string | null; majors: string[] }>
    projects: Array<{ name: string | null; description: string | null }>
}

function buildUserPrompt(c: ProfileContext): string {
    const lines: string[] = ['## PERFIL DO CANDIDATO', '']
    if (c.firstName) lines.push(`Nome: ${c.firstName}`)
    if (c.city) lines.push(`Cidade: ${c.city}`)
    if (c.areas.length) lines.push(`Áreas de interesse: ${c.areas.join(', ')}`)

    if (c.education.length) {
        lines.push('', 'Formação:')
        for (const e of c.education) {
            const parts = [e.degree, e.majors.join('/'), e.institution].filter(Boolean)
            const sem = e.semester ? ` — ${e.semester}º semestre` : ''
            const st = e.status ? ` (${e.status})` : ''
            lines.push(`- ${parts.join(' em ') || 'curso não informado'}${sem}${st}`)
        }
    }
    if (c.experiences.length) {
        lines.push('', 'Experiências:')
        for (const x of c.experiences) {
            const head = [x.title, x.company].filter(Boolean).join(' — ') || 'experiência'
            lines.push(`- ${head}${x.isCurrent ? ' (atual)' : ''}`)
            for (const b of x.bullets) lines.push(`  • ${b}`)
        }
    }
    if (c.projects.length) {
        lines.push('', 'Projetos:')
        for (const p of c.projects) {
            lines.push(`- ${[p.name, p.description].filter(Boolean).join(': ')}`)
        }
    }
    if (c.skills.length) lines.push('', `Habilidades: ${c.skills.join(', ')}`)
    if (c.languages.length) lines.push(`Idiomas: ${c.languages.join(', ')}`)
    if (c.certs.length) lines.push(`Certificações: ${c.certs.join(', ')}`)
    if (c.interests.length) lines.push(`Interesses/temas: ${c.interests.join(', ')}`)

    lines.push('', 'Gere o headline e o summary em JSON, seguindo as regras.')
    return lines.join('\n')
}
