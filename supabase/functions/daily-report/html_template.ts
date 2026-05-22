// Renderiza o HTML do relatório diário pra envio via Resend.
//
// Estilo: inline CSS (Gmail/Outlook strippam <style>), tabela simples por
// bloco, cores do Stage (#00C27A primário, #F59E0B accent).

import type {
  CvAdaptedBlock,
  EngagementBlock,
  GapBlock,
  HealthBlock,
  JobsInsertedBlock,
  JobsStockBlock,
  MatchBlock,
  ReportWindow,
  UsersBlock,
  UsersTotalBlock,
  WeeklyBlock,
} from './queries.ts'

export interface ReportPayload {
  window: ReportWindow
  usersTotal: UsersTotalBlock
  users: UsersBlock
  engagement: EngagementBlock
  jobsInserted: JobsInsertedBlock
  jobsStock: JobsStockBlock
  match: MatchBlock
  cvAdapted: CvAdaptedBlock
  gap: GapBlock
  health: HealthBlock
  /// Presente só aos domingos.
  weekly?: WeeklyBlock
}

const STYLE = {
  bg: '#F8FAFC',
  card: '#FFFFFF',
  border: '#E5E7EB',
  text: '#0F172A',
  muted: '#64748B',
  primary: '#00C27A',
  accent: '#F59E0B',
  up: '#16A34A',
  down: '#DC2626',
}

function delta(current: number, previous: number): string {
  if (previous === 0) {
    return current > 0
      ? `<span style="color:${STYLE.up};font-weight:600">+${current} (novo)</span>`
      : '<span style="color:#94A3B8">—</span>'
  }
  const diff = current - previous
  const pct = (diff / previous) * 100
  const arrow = diff >= 0 ? '↑' : '↓'
  const color = diff >= 0 ? STYLE.up : STYLE.down
  return `<span style="color:${color};font-weight:600">${arrow} ${Math.abs(pct).toFixed(0)}%</span> <span style="color:${STYLE.muted};font-size:12px">(vs ${previous})</span>`
}

function pct(n: number): string {
  return `${(n * 100).toFixed(0)}%`
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

function table(rows: Array<{ key: string; count: number }>, emptyMsg = 'Sem dados'): string {
  if (rows.length === 0) {
    return `<p style="color:${STYLE.muted};font-size:13px;margin:8px 0">${emptyMsg}</p>`
  }
  const max = Math.max(...rows.map((r) => r.count))
  return `<table style="width:100%;border-collapse:collapse;font-size:13px">
    ${rows
      .map((r) => {
        const barW = max > 0 ? Math.round((r.count / max) * 100) : 0
        return `<tr>
          <td style="padding:4px 8px 4px 0;color:${STYLE.text}">${escapeHtml(r.key)}</td>
          <td style="padding:4px 0;width:40%">
            <div style="background:${STYLE.border};border-radius:3px;height:6px;width:100%">
              <div style="background:${STYLE.primary};border-radius:3px;height:6px;width:${barW}%"></div>
            </div>
          </td>
          <td style="padding:4px 0 4px 8px;text-align:right;color:${STYLE.text};font-weight:600;width:50px">${r.count}</td>
        </tr>`
      })
      .join('')}
  </table>`
}

function section(title: string, icon: string, contentHtml: string): string {
  return `<div style="background:${STYLE.card};border:1px solid ${STYLE.border};border-radius:8px;padding:16px;margin-bottom:12px">
    <h2 style="margin:0 0 12px;font-size:15px;color:${STYLE.text};font-weight:600">
      ${icon} ${title}
    </h2>
    ${contentHtml}
  </div>`
}

function bigNumber(value: number | string, label: string, sub?: string): string {
  return `<div style="display:inline-block;margin-right:24px;margin-bottom:8px">
    <div style="font-size:28px;font-weight:700;color:${STYLE.text};line-height:1">${value}</div>
    <div style="font-size:11px;color:${STYLE.muted};text-transform:uppercase;letter-spacing:0.5px;margin-top:4px">${label}</div>
    ${sub ? `<div style="font-size:12px;color:${STYLE.text};margin-top:2px">${sub}</div>` : ''}
  </div>`
}

export function renderEmailHtml(p: ReportPayload): string {
  const { window: win, usersTotal, users, engagement, jobsInserted, jobsStock, match, cvAdapted, gap, health, weekly } = p
  const title = weekly ? `Stage — Relatório Diário + Semanal (${win.yesterday.label})` : `Stage — Relatório Diário (${win.yesterday.label})`

  // === Bloco 1B: Perfil total (all-time) ===
  const usersTotalHtml = `
    <div style="margin-bottom:8px">
      ${bigNumber(usersTotal.totalUsers, 'usuários no app')}
      ${bigNumber(pct(usersTotal.activatedRate), 'ativaram (1+ swipe)')}
      ${bigNumber(pct(usersTotal.onboardingCompletionRate), 'completaram onb.')}
      ${bigNumber(pct(usersTotal.aiConsentRate), 'aceitaram IA')}
      ${bigNumber(pct(usersTotal.phoneRate), 'com telefone')}
    </div>
    <h3 style="margin:16px 0 6px;font-size:13px;color:${STYLE.muted};text-transform:uppercase;letter-spacing:0.5px">Top faculdades (all-time)</h3>
    ${table(usersTotal.byUniversity, 'Nenhum usuário com faculdade informada')}
    <h3 style="margin:16px 0 6px;font-size:13px;color:${STYLE.muted};text-transform:uppercase;letter-spacing:0.5px">Top cursos (all-time)</h3>
    ${table(usersTotal.byCourse)}
    <h3 style="margin:16px 0 6px;font-size:13px;color:${STYLE.muted};text-transform:uppercase;letter-spacing:0.5px">Por semestre (all-time)</h3>
    ${table(usersTotal.bySemester)}
    <h3 style="margin:16px 0 6px;font-size:13px;color:${STYLE.muted};text-transform:uppercase;letter-spacing:0.5px">Por idade (all-time)</h3>
    ${table(usersTotal.byAgeBucket, 'Nenhuma idade informada')}
  `

  // === Bloco 1: Usuários ===
  const usersHtml = `
    <div style="margin-bottom:8px">
      ${bigNumber(users.newSignups, 'novos cadastros', delta(users.newSignups, users.newSignupsPrev))}
      ${bigNumber(pct(users.onboardingCompletionRate), 'completaram onb.')}
      ${bigNumber(pct(users.aiConsentRate), 'aceitaram IA')}
      ${bigNumber(pct(users.phoneRate), 'com telefone')}
    </div>
    <h3 style="margin:16px 0 6px;font-size:13px;color:${STYLE.muted};text-transform:uppercase;letter-spacing:0.5px">Top faculdades</h3>
    ${table(users.byUniversity, 'Nenhum cadastro com faculdade informada')}
    <h3 style="margin:16px 0 6px;font-size:13px;color:${STYLE.muted};text-transform:uppercase;letter-spacing:0.5px">Top cursos</h3>
    ${table(users.byCourse)}
    <h3 style="margin:16px 0 6px;font-size:13px;color:${STYLE.muted};text-transform:uppercase;letter-spacing:0.5px">Por semestre</h3>
    ${table(users.bySemester)}
  `

  // === Bloco 2: Engajamento ===
  const engagementHtml = `
    ${bigNumber(engagement.dau, 'DAU (swipes)')}
    ${bigNumber(engagement.cvAdaptersYesterday, 'adaptaram CV')}
    ${bigNumber(engagement.appliersYesterday, 'aplicaram p/ vaga')}
  `

  // === Bloco 3: Vagas inseridas ===
  const jobsInsertedHtml = `
    <div style="margin-bottom:8px">
      ${bigNumber(jobsInserted.total, 'vagas novas', delta(jobsInserted.total, jobsInserted.totalPrev))}
    </div>
    <h3 style="margin:16px 0 6px;font-size:13px;color:${STYLE.muted};text-transform:uppercase;letter-spacing:0.5px">Por área</h3>
    ${table(jobsInserted.byArea)}
    <h3 style="margin:16px 0 6px;font-size:13px;color:${STYLE.muted};text-transform:uppercase;letter-spacing:0.5px">Por fonte</h3>
    ${table(jobsInserted.bySource)}
    <h3 style="margin:16px 0 6px;font-size:13px;color:${STYLE.muted};text-transform:uppercase;letter-spacing:0.5px">Top empresas</h3>
    ${table(jobsInserted.byCompany)}
    <h3 style="margin:16px 0 6px;font-size:13px;color:${STYLE.muted};text-transform:uppercase;letter-spacing:0.5px">Modelo de trabalho</h3>
    ${table(jobsInserted.byWorkModel)}
    <h3 style="margin:16px 0 6px;font-size:13px;color:${STYLE.muted};text-transform:uppercase;letter-spacing:0.5px">Tipo de vaga</h3>
    ${table(jobsInserted.byJobType)}
    <h3 style="margin:16px 0 6px;font-size:13px;color:${STYLE.muted};text-transform:uppercase;letter-spacing:0.5px">Top cidades</h3>
    ${table(jobsInserted.byCity)}
  `

  // === Bloco 4: Estoque ===
  const stockHtml = `
    ${bigNumber(jobsStock.activeTotal, 'vagas ativas no app')}
    ${bigNumber(jobsStock.avgAgeDays.toFixed(1) + 'd', 'idade média')}
    ${bigNumber(pct(jobsStock.withExternalUrlRate), 'com link p/ aplicar')}
    <h3 style="margin:16px 0 6px;font-size:13px;color:${STYLE.muted};text-transform:uppercase;letter-spacing:0.5px">Top áreas no estoque</h3>
    ${table(jobsStock.byArea)}
  `

  // === Bloco 5: Match ===
  const topJobsHtml = match.topLikedJobs.length === 0
    ? `<p style="color:${STYLE.muted};font-size:13px">Sem curtidas ontem</p>`
    : `<ol style="margin:8px 0;padding-left:20px;font-size:13px;color:${STYLE.text}">
        ${match.topLikedJobs
          .map(
            (j) => `<li style="margin-bottom:4px">
              ${j.url ? `<a href="${escapeHtml(j.url)}" style="color:${STYLE.primary};text-decoration:none">${escapeHtml(j.title)}</a>` : escapeHtml(j.title)}
              <span style="color:${STYLE.muted}"> · ${escapeHtml(j.company)}</span>
              <span style="color:${STYLE.text};font-weight:600"> · ${j.count} curtidas</span>
            </li>`,
          )
          .join('')}
      </ol>`

  const matchHtml = `
    ${bigNumber(match.totalLikes, 'curtidas')}
    ${bigNumber(match.totalApplies, 'aplicações reais')}
    ${bigNumber(pct(match.swipeToApplyRate), 'conv. swipe→apply')}
    ${bigNumber(match.avgMatchScore.toFixed(0), 'match score médio')}
    <h3 style="margin:16px 0 6px;font-size:13px;color:${STYLE.muted};text-transform:uppercase;letter-spacing:0.5px">Top 5 vagas curtidas</h3>
    ${topJobsHtml}
    <h3 style="margin:16px 0 6px;font-size:13px;color:${STYLE.muted};text-transform:uppercase;letter-spacing:0.5px">Top empresas curtidas</h3>
    ${table(match.topLikedCompanies)}
    <h3 style="margin:16px 0 6px;font-size:13px;color:${STYLE.muted};text-transform:uppercase;letter-spacing:0.5px">Curtidas por área</h3>
    ${table(match.likesByArea)}
  `

  // === Bloco 6: CV adaptado ===
  const cvHtml = `
    ${bigNumber(cvAdapted.total, 'CVs adaptados ontem')}
    <h3 style="margin:16px 0 6px;font-size:13px;color:${STYLE.muted};text-transform:uppercase;letter-spacing:0.5px">Por área da vaga</h3>
    ${table(cvAdapted.byArea)}
  `

  // === Bloco 7: Gap ===
  const gapRows = gap.underservedAreas.map((g) => ({
    key: `${g.area} (${g.likes} likes / ${g.activeJobs} vagas)`,
    count: Math.round(g.ratio * 10),
  }))
  const gapHtml = gap.underservedAreas.length === 0
    ? `<p style="color:${STYLE.muted};font-size:13px">Sem áreas em desbalanço claro</p>`
    : `<p style="color:${STYLE.muted};font-size:13px;margin:0 0 8px">Áreas com mais demanda que oferta no estoque atual (ratio = likes / vagas ativas, ×10)</p>
       ${table(gapRows)}`

  // === Bloco 8: Health ===
  const healthHtml = `
    ${bigNumber(health.aiGenerations, 'chamadas IA ontem')}
    ${bigNumber((health.totalTokensUsed / 1000).toFixed(1) + 'k', 'tokens usados')}
  `

  // === Bloco semanal (domingo) ===
  let weeklyHtml = ''
  if (weekly) {
    weeklyHtml = section(
      `Resumo semanal (${win.lastWeek.label})`,
      '📊',
      `
      <div>
        ${bigNumber(weekly.newSignupsLastWeek, 'cadastros 7d', delta(weekly.newSignupsLastWeek, weekly.newSignupsPrevWeek))}
        ${bigNumber(weekly.jobsLastWeek, 'vagas 7d', delta(weekly.jobsLastWeek, weekly.jobsPrevWeek))}
        ${bigNumber(weekly.likesLastWeek, 'curtidas 7d', delta(weekly.likesLastWeek, weekly.likesPrevWeek))}
        ${bigNumber(weekly.appliesLastWeek, 'aplicações 7d', delta(weekly.appliesLastWeek, weekly.appliesPrevWeek))}
      </div>
      `,
    )
  }

  return `<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8" />
  <title>${escapeHtml(title)}</title>
</head>
<body style="margin:0;padding:0;background:${STYLE.bg};font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;color:${STYLE.text}">
  <div style="max-width:680px;margin:0 auto;padding:24px 16px">
    <div style="background:linear-gradient(135deg,${STYLE.primary} 0%,#00A368 100%);color:white;padding:20px;border-radius:8px;margin-bottom:16px">
      <h1 style="margin:0;font-size:20px;font-weight:700">${escapeHtml(title)}</h1>
      <p style="margin:4px 0 0;font-size:13px;opacity:0.9">Janela: ${win.yesterday.label} (00h-24h BRT)</p>
    </div>

    ${weeklyHtml}
    ${section('Perfil dos usuários (total no app)', '🎓', usersTotalHtml)}
    ${section('Usuários novos ontem', '👥', usersHtml)}
    ${section('Engajamento', '⚡', engagementHtml)}
    ${section('Vagas inseridas', '💼', jobsInsertedHtml)}
    ${section('Estoque atual de vagas', '📦', stockHtml)}
    ${section('Match & engajamento com vagas', '❤️', matchHtml)}
    ${section('CV adaptado', '📄', cvHtml)}
    ${section('Gap oferta vs demanda', '⚖️', gapHtml)}
    ${section('Saúde do sistema', '🩺', healthHtml)}

    <p style="text-align:center;color:${STYLE.muted};font-size:11px;margin:24px 0 0">
      Gerado automaticamente pelo cron daily-report · Stage v1.5.3
    </p>
  </div>
</body>
</html>`
}

/// Texto curto pro ntfy.sh — 3 linhas com os números chave.
export function renderNtfyText(p: ReportPayload): { title: string; message: string } {
  const { window: win, users, jobsInserted, match } = p
  const title = p.weekly
    ? `Stage ${win.yesterday.label} (+ semanal)`
    : `Stage ${win.yesterday.label}`
  const message = [
    `${users.newSignups} cadastros · ${jobsInserted.total} vagas novas`,
    `${match.totalLikes} curtidas · ${match.totalApplies} aplicações`,
    `Email com o relatório completo já saiu.`,
  ].join('\n')
  return { title, message }
}
