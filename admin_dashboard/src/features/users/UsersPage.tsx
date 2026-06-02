import { useEffect, useMemo, useState } from 'react';
import type { ColumnDef } from '@tanstack/react-table';
import { Eye, Search } from 'lucide-react';
import { invokeAdmin } from '../../lib/api';
import type { AdminCandidate } from '../../lib/types';
import { formatDate, formatNumber } from '../../lib/utils';
import { Badge, Button, Card, Field, Input, Select } from '../../components/ui';
import { DataTable } from '../../components/DataTable';

function consentTone(status: string) {
  if (status === 'granted') return 'green' as const;
  if (status === 'denied' || status === 'revoked') return 'red' as const;
  return 'amber' as const;
}

export function UsersPage() {
  const [users, setUsers] = useState<AdminCandidate[]>([]);
  const [total, setTotal] = useState(0);
  const [search, setSearch] = useState('');
  const [skill, setSkill] = useState('');
  const [consentStatus, setConsentStatus] = useState('');
  const [selected, setSelected] = useState<AdminCandidate | null>(null);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function load() {
    setLoading(true);
    setMessage(null);
    try {
      const payload = await invokeAdmin<{ users: AdminCandidate[]; total: number }>('admin-users', {
        action: 'list',
        page: 1,
        pageSize: 50,
        filters: {
          search,
          skill,
          consentStatus: consentStatus || undefined,
        },
      });
      setUsers(payload.users);
      setTotal(payload.total);
    } catch (err) {
      setMessage(err instanceof Error ? err.message : 'Erro ao carregar usuarios');
    } finally {
      setLoading(false);
    }
  }

  async function openDetail(user: AdminCandidate, revealPii = false) {
    const payload = await invokeAdmin<{ user: AdminCandidate }>('admin-users', {
      action: 'detail',
      id: user.id,
      revealPii,
    });
    setSelected(payload.user);
  }

  async function updateConsent(status: AdminCandidate['dataSharingConsent']) {
    if (!selected) return;
    const payload = await invokeAdmin<{ user: AdminCandidate }>('admin-users', {
      action: 'update_consent',
      id: selected.id,
      consent: { status },
    });
    void payload;
    await openDetail(selected);
    await load();
  }

  useEffect(() => {
    void load();
  }, []);

  const columns = useMemo<ColumnDef<AdminCandidate>[]>(() => [
    {
      header: 'Candidato',
      cell: ({ row }) => (
        <button className="text-left font-medium text-ink hover:text-brand" onClick={() => openDetail(row.original)}>
          {row.original.name}
          <div className="text-xs font-normal text-slate-500">{row.original.email}</div>
        </button>
      ),
    },
    {
      header: 'Local',
      cell: ({ row }) => [row.original.city, row.original.state].filter(Boolean).join(', ') || '-',
    },
    {
      header: 'Perfil',
      cell: ({ row }) => `${row.original.completenessScore}%`,
    },
    {
      header: 'Consent.',
      cell: ({ row }) => (
        <Badge tone={consentTone(row.original.dataSharingConsent)}>{row.original.dataSharingConsent}</Badge>
      ),
    },
    {
      header: 'Atividade',
      cell: ({ row }) => `${row.original.activity.likes} likes · ${row.original.activity.applies} aplic.`,
    },
    {
      header: 'Criado',
      cell: ({ row }) => formatDate(row.original.createdAt),
    },
  ], []);

  return (
    <div className="grid gap-5">
      <div>
        <h1 className="text-2xl font-semibold text-ink">Usuarios</h1>
        <p className="text-sm text-slate-500">{formatNumber(total)} candidatos encontrados</p>
      </div>
      <Card>
        <div className="grid gap-3 md:grid-cols-[1fr_220px_180px_auto]">
          <Field label="Busca">
            <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Nome, email, curso" />
          </Field>
          <Field label="Skill">
            <Input value={skill} onChange={(e) => setSkill(e.target.value)} placeholder="Excel, Python..." />
          </Field>
          <Field label="Consentimento">
            <Select value={consentStatus} onChange={(e) => setConsentStatus(e.target.value)}>
              <option value="">Todos</option>
              <option value="granted">Granted</option>
              <option value="denied">Denied</option>
              <option value="revoked">Revoked</option>
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
      {message ? <Card className="text-sm text-rose-600">{message}</Card> : null}
      <DataTable data={users} columns={columns} />
      {selected ? (
        <Card>
          <div className="flex items-start justify-between gap-4">
            <div>
              <h2 className="text-lg font-semibold">{selected.name}</h2>
              <p className="text-sm text-slate-500">{selected.email} · {selected.phone || 'telefone oculto'}</p>
            </div>
            <div className="flex gap-2">
              <Button variant="secondary" onClick={() => openDetail(selected, true)}>
                <Eye size={15} className="mr-2" />
                Revelar PII
              </Button>
              <Button variant="ghost" onClick={() => setSelected(null)}>Fechar</Button>
            </div>
          </div>
          <div className="mt-4 grid gap-3 text-sm md:grid-cols-3">
            <div><b>Local:</b> {[selected.city, selected.state].filter(Boolean).join(', ') || '-'}</div>
            <div><b>Completude:</b> {selected.completenessScore}%</div>
            <div><b>AI consent:</b> {selected.aiConsent ? 'sim' : 'nao'}</div>
          </div>
          <div className="mt-4">
            <h3 className="font-semibold">Consentimento comercial</h3>
            <div className="mt-2 flex flex-wrap gap-2">
              {(['not_asked', 'granted', 'denied', 'revoked'] as const).map((status) => (
                <Button
                  key={status}
                  variant={selected.dataSharingConsent === status ? 'primary' : 'secondary'}
                  onClick={() => updateConsent(status)}
                >
                  {status}
                </Button>
              ))}
            </div>
          </div>
          <div className="mt-4 grid gap-4 md:grid-cols-2">
            <div>
              <h3 className="font-semibold">Skills</h3>
              <div className="mt-2 flex flex-wrap gap-2">
                {selected.skills.map((skill) => <Badge key={skill} tone="blue">{skill}</Badge>)}
              </div>
            </div>
            <div>
              <h3 className="font-semibold">Cargos desejados</h3>
              <div className="mt-2 flex flex-wrap gap-2">
                {selected.desiredTitles.map((title) => <Badge key={title}>{title}</Badge>)}
              </div>
            </div>
          </div>
        </Card>
      ) : null}
    </div>
  );
}
