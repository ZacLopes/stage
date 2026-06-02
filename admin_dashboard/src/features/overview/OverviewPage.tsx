import { useEffect, useState } from 'react';
import { Area, AreaChart, Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { invokeAdmin } from '../../lib/api';
import { formatNumber, formatPercent } from '../../lib/utils';
import { Card } from '../../components/ui';
import { StatCard } from '../../components/StatCard';

interface OverviewPayload {
  kpis: {
    totalUsers: number;
    completeProfiles: number;
    activeJobs: number;
    totalJobs: number;
    totalLikes: number;
    totalApplies: number;
    adaptedResumes: number;
    grantedConsents: number;
    pendingConsents: number;
    profileCompletionRate: number;
    applyRate: number;
  };
  series: Array<{ day: string; users: number; likes: number; applies: number }>;
  jobs: {
    byArea: Array<{ key: string; count: number }>;
    bySource: Array<{ key: string; count: number }>;
  };
}

export function OverviewPage() {
  const [data, setData] = useState<OverviewPayload | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    invokeAdmin<OverviewPayload>('admin-overview')
      .then(setData)
      .catch((err) => setError(err instanceof Error ? err.message : 'Erro ao carregar overview'));
  }, []);

  if (error) return <Card className="text-rose-600">{error}</Card>;
  if (!data) return <div className="text-slate-500">Carregando overview...</div>;

  return (
    <div className="grid gap-5">
      <div>
        <h1 className="text-2xl font-semibold text-ink">Overview</h1>
        <p className="text-sm text-slate-500">Base, vagas e sinais comerciais do Stage.</p>
      </div>
      <div className="grid gap-3 md:grid-cols-4">
        <StatCard label="Usuarios" value={data.kpis.totalUsers} detail={`${formatPercent(data.kpis.profileCompletionRate)} com perfil completo`} />
        <StatCard label="Vagas ativas" value={data.kpis.activeJobs} detail={`${formatNumber(data.kpis.totalJobs)} vagas no total`} />
        <StatCard label="Likes em vagas" value={data.kpis.totalLikes} detail={`${formatPercent(data.kpis.applyRate)} viraram aplicacao`} />
        <StatCard label="Consentimentos B2B" value={data.kpis.grantedConsents} detail={`${formatNumber(data.kpis.pendingConsents)} pendentes`} />
      </div>
      <div className="grid gap-5 xl:grid-cols-2">
        <Card>
          <h2 className="mb-4 text-base font-semibold">Atividade recente</h2>
          <div className="h-72">
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={data.series}>
                <CartesianGrid strokeDasharray="3 3" stroke="#E2E8F0" />
                <XAxis dataKey="day" tick={{ fontSize: 12 }} />
                <YAxis tick={{ fontSize: 12 }} />
                <Tooltip />
                <Area type="monotone" dataKey="users" name="Usuarios" stroke="#1E88B8" fill="#BAE6FD" />
                <Area type="monotone" dataKey="likes" name="Likes" stroke="#10B981" fill="#BBF7D0" />
                <Area type="monotone" dataKey="applies" name="Aplicacoes" stroke="#F59E0B" fill="#FDE68A" />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        </Card>
        <Card>
          <h2 className="mb-4 text-base font-semibold">Vagas por area</h2>
          <div className="h-72">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={data.jobs.byArea}>
                <CartesianGrid strokeDasharray="3 3" stroke="#E2E8F0" />
                <XAxis dataKey="key" tick={{ fontSize: 12 }} />
                <YAxis tick={{ fontSize: 12 }} />
                <Tooltip />
                <Bar dataKey="count" fill="#1E88B8" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </Card>
      </div>
    </div>
  );
}
