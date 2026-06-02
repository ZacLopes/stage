import { useEffect, useMemo, useState } from 'react';
import type { ColumnDef } from '@tanstack/react-table';
import { Search, Sparkles } from 'lucide-react';
import { invokeAdmin } from '../../lib/api';
import type { AdminJob } from '../../lib/types';
import { formatDate, formatNumber } from '../../lib/utils';
import { Badge, Button, Card, Field, Input, Select } from '../../components/ui';
import { DataTable } from '../../components/DataTable';

interface JobsPageProps {
  onOpenLists: () => void;
}

export function JobsPage({ onOpenLists }: JobsPageProps) {
  const [jobs, setJobs] = useState<AdminJob[]>([]);
  const [total, setTotal] = useState(0);
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState<'all' | 'active' | 'inactive'>('active');
  const [selected, setSelected] = useState<AdminJob | null>(null);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function load() {
    setLoading(true);
    setMessage(null);
    try {
      const payload = await invokeAdmin<{ jobs: AdminJob[]; total: number }>('admin-jobs', {
        action: 'list',
        page: 1,
        pageSize: 50,
        filters: { search, status },
      });
      setJobs(payload.jobs);
      setTotal(payload.total);
    } catch (err) {
      setMessage(err instanceof Error ? err.message : 'Erro ao carregar vagas');
    } finally {
      setLoading(false);
    }
  }

  async function createListFromJob(job: AdminJob) {
    setMessage(null);
    try {
      const created = await invokeAdmin<{ request: { id: string } }>('admin-candidate-lists', {
        action: 'create',
        request: { sourceJobId: job.id, minScore: 60 },
      });
      await invokeAdmin('admin-candidate-lists', { action: 'generate', id: created.request.id });
      onOpenLists();
    } catch (err) {
      setMessage(err instanceof Error ? err.message : 'Falha ao criar lista');
    }
  }

  useEffect(() => {
    void load();
  }, []);

  const columns = useMemo<ColumnDef<AdminJob>[]>(() => [
    {
      header: 'Vaga',
      cell: ({ row }) => (
        <button className="max-w-md text-left font-medium text-ink hover:text-brand" onClick={() => setSelected(row.original)}>
          {row.original.title}
          <div className="text-xs font-normal text-slate-500">{row.original.company?.name ?? 'Empresa sem nome'}</div>
        </button>
      ),
    },
    { header: 'Area', accessorKey: 'area' },
    {
      header: 'Local',
      cell: ({ row }) => row.original.workModel === 'remoto'
        ? 'Remoto'
        : [row.original.locationCity, row.original.locationState].filter(Boolean).join(', ') || '-',
    },
    {
      header: 'Status',
      cell: ({ row }) => <Badge tone={row.original.isActive ? 'green' : 'red'}>{row.original.isActive ? 'ativa' : 'inativa'}</Badge>,
    },
    {
      header: 'Sinais',
      cell: ({ row }) => (
        <span>{formatNumber(row.original.metrics.likes)} likes · {formatNumber(row.original.metrics.applies)} aplic.</span>
      ),
    },
    {
      header: 'Publicada',
      cell: ({ row }) => formatDate(row.original.publishedAt),
    },
    {
      header: '',
      cell: ({ row }) => (
        <Button variant="secondary" onClick={() => createListFromJob(row.original)}>
          <Sparkles size={15} className="mr-2" />
          Encontrar
        </Button>
      ),
    },
  ], []);

  return (
    <div className="grid gap-5">
      <div>
        <h1 className="text-2xl font-semibold text-ink">Vagas</h1>
        <p className="text-sm text-slate-500">{formatNumber(total)} vagas encontradas</p>
      </div>
      <Card>
        <div className="grid gap-3 md:grid-cols-[1fr_180px_auto]">
          <Field label="Busca">
            <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Cargo, descricao, empresa" />
          </Field>
          <Field label="Status">
            <Select value={status} onChange={(e) => setStatus(e.target.value as typeof status)}>
              <option value="active">Ativas</option>
              <option value="inactive">Inativas</option>
              <option value="all">Todas</option>
            </Select>
          </Field>
          <div className="flex items-end">
            <Button onClick={load} disabled={loading}>
              <Search size={15} className="mr-2" />
              Filtrar
            </Button>
          </div>
        </div>
      </Card>
      {message ? <Card className="text-sm text-slate-700">{message}</Card> : null}
      <DataTable data={jobs} columns={columns} empty={loading ? 'Carregando vagas...' : 'Nenhum resultado'} />
      {selected ? (
        <Card>
          <div className="flex items-start justify-between gap-4">
            <div>
              <h2 className="text-lg font-semibold">{selected.title}</h2>
              <p className="text-sm text-slate-500">{selected.company?.name} · {selected.area}</p>
            </div>
            <Button variant="ghost" onClick={() => setSelected(null)}>Fechar</Button>
          </div>
          <div className="mt-4 grid gap-3 text-sm md:grid-cols-4">
            <div><b>Fonte:</b> {selected.source ?? '-'}</div>
            <div><b>Modelo:</b> {selected.workModel ?? '-'}</div>
            <div><b>Tipo:</b> {selected.jobType ?? '-'}</div>
            <div><b>Score medio:</b> {Math.round(selected.metrics.avgScore || 0)}</div>
          </div>
          <p className="mt-4 whitespace-pre-wrap text-sm leading-6 text-slate-700">{selected.description}</p>
          {selected.requirements?.length ? (
            <div className="mt-4">
              <h3 className="font-semibold">Requisitos</h3>
              <ul className="mt-2 list-disc pl-5 text-sm text-slate-700">
                {selected.requirements.map((item) => <li key={item}>{item}</li>)}
              </ul>
            </div>
          ) : null}
        </Card>
      ) : null}
    </div>
  );
}
