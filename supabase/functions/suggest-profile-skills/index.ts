import { serve } from 'std/http/server'
import { createClient } from 'supabase'
import { trackAIGeneration, withEdgeAnalytics } from '../_shared/posthog.ts'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

/**
 * suggest-profile-skills Edge Function
 *
 * A partir do PERFIL relacional (curso/formação + experiências + área + skills
 * que a pessoa JÁ marcou), sugere 4-6 habilidades plausíveis que ela
 * provavelmente tem/desenvolve e que NÃO estão na lista — pra ela CONFIRMAR
 * (não grava nada; quem grava é o cliente quando o usuário toca). Disciplina
 * anti-invenção: só sugere o plausível pelo contexto, e o usuário decide.
 *
 * Request:  {} (usuário vem do JWT)
 * Response: { skills: string[] }  (vazio = nada a sugerir)
 */
serve(withEdgeAnalytics('suggest-profile-skills', async (req) => {
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

        const [expR, eduR, skillsR, desiredR] = await Promise.all([
            client.from('profile_experiences')
                .select('title,company,profile_bullets(text)').eq('user_id', userId),
            client.from('profile_education')
                .select('degree,current_semester,profile_education_majors(name)').eq('user_id', userId),
            client.from('profile_skills').select('name').eq('user_id', userId),
            client.from('profile_desired_titles').select('title').eq('user_id', userId),
        ])

        const current = (skillsR.data ?? []).map((s) => s.name).filter(Boolean) as string[]
        const currentLower = new Set(current.map((s) => s.toLowerCase().trim()))
        const areas = (desiredR.data ?? []).map((d) => d.title).filter(Boolean) as string[]
        const experiences = (expR.data ?? []).map((e) => ({
            title: e.title as string | null,
            company: e.company as string | null,
            bullets: ((e.profile_bullets ?? []) as Array<{ text: string }>).map((b) => b.text).filter(Boolean),
        }))
        const education = (eduR.data ?? []).map((e) => ({
            degree: e.degree as string | null,
            semester: e.current_semester as number | null,
            majors: ((e.profile_education_majors ?? []) as Array<{ name: string }>).map((m) => m.name),
        }))

        // Gate: sem contexto nenhum (nem curso, nem experiência, nem área), não há
        // base pra sugerir — devolve vazio.
        if (education.length === 0 && experiences.length === 0 && areas.length === 0) {
            return new Response(JSON.stringify({ skills: [] }),
                { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
        }

        const systemPrompt = buildSystemPrompt()
        const userPrompt = buildUserPrompt({ areas, current, experiences, education })

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
                temperature: 0.4,
                max_tokens: 200,
                response_format: { type: 'json_object' },
            }),
        })

        if (!openaiResponse.ok) {
            trackAIGeneration({
                userId, generationType: 'skill_suggestion', model: 'gpt-4o-mini',
                inputTokens: 0, outputTokens: 0, latencyMs: Date.now() - aiStart, isError: true,
            }).catch(() => {})
            throw new Error(`OpenAI API error: ${openaiResponse.statusText}`)
        }

        const openaiData = await openaiResponse.json()
        trackAIGeneration({
            userId, generationType: 'skill_suggestion', model: 'gpt-4o-mini',
            inputTokens: openaiData.usage?.prompt_tokens ?? 0,
            outputTokens: openaiData.usage?.completion_tokens ?? 0,
            latencyMs: Date.now() - aiStart,
        }).catch(() => {})

        let suggested: string[] = []
        try {
            const parsed = JSON.parse(openaiData.choices[0].message.content)
            if (Array.isArray(parsed.skills)) {
                suggested = parsed.skills.map((s: unknown) => String(s).trim()).filter(Boolean)
            }
        } catch (_) {
            suggested = []
        }

        // Tira duplicatas do que a pessoa já tem + dedup interno; limita a 6.
        const out: string[] = []
        const seen = new Set<string>()
        for (const s of suggested) {
            const k = s.toLowerCase().trim()
            if (!k || currentLower.has(k) || seen.has(k)) continue
            seen.add(k)
            out.push(s)
            if (out.length >= 6) break
        }

        return new Response(JSON.stringify({ skills: out }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    } catch (error) {
        console.error('suggest-profile-skills error:', error)
        return new Response(
            JSON.stringify({ error: (error as Error).message ?? 'Internal server error' }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    }
}))

function buildSystemPrompt(): string {
    return `Você ajuda estudantes/candidatos a estágio no Brasil a lembrar de habilidades que provavelmente têm.

## TAREFA
Dado o curso, as experiências e a área de interesse, sugira de 4 a 6 HABILIDADES concretas que alguém com esse perfil COMUMENTE tem ou está desenvolvendo, e que AINDA NÃO estão na lista atual.

## REGRAS
- Sugira o PLAUSÍVEL pelo contexto (curso/experiência/área). O usuário vai CONFIRMAR cada uma — você está lembrando, não afirmando.
- Prefira habilidades concretas e nomeáveis: ferramentas (Excel, Figma, AutoCAD, SQL...), métodos (Scrum, análise de dados...), idiomas técnicos. Evite traços vagos ("proatividade").
- NÃO repita nada que já está na lista atual.
- NÃO invente certificações, números ou experiências.
- Português brasileiro. Nomes curtos e canônicos (ex.: "Power BI", não "ferramenta Power BI da Microsoft").
- Retorne APENAS JSON: {"skills": ["...", "..."]}. Se não houver base boa, retorne {"skills": []}.`
}

interface Ctx {
    areas: string[]
    current: string[]
    experiences: Array<{ title: string | null; company: string | null; bullets: string[] }>
    education: Array<{ degree: string | null; semester: number | null; majors: string[] }>
}

function buildUserPrompt(c: Ctx): string {
    const lines: string[] = ['## PERFIL', '']
    if (c.areas.length) lines.push(`Áreas de interesse: ${c.areas.join(', ')}`)
    if (c.education.length) {
        lines.push('Formação:')
        for (const e of c.education) {
            const parts = [e.degree, e.majors.join('/')].filter(Boolean)
            const sem = e.semester ? ` (${e.semester}º sem)` : ''
            lines.push(`- ${parts.join(' em ') || 'curso'}${sem}`)
        }
    }
    if (c.experiences.length) {
        lines.push('Experiências:')
        for (const x of c.experiences) {
            lines.push(`- ${[x.title, x.company].filter(Boolean).join(' — ') || 'experiência'}`)
            for (const b of x.bullets) lines.push(`  • ${b}`)
        }
    }
    lines.push('', `Habilidades JÁ marcadas (não repita): ${c.current.length ? c.current.join(', ') : '(nenhuma)'}`)
    lines.push('', 'Sugira de 4 a 6 habilidades plausíveis que faltam, em JSON.')
    return lines.join('\n')
}
