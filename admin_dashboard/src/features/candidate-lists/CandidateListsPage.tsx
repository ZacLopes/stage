import { useEffect, useMemo, useState } from 'react';
import type { ColumnDef } from '@tanstack/react-table';
import { Download, Play, Plus } from 'lucide-react';
import { downloadCsv, invokeAdmin } from '../../lib/api';
import type { CandidateListItem, CandidateListRequest, EmployerClient } from '../../lib/types';
import { formatDate, formatNumber, slugify } from '../../lib/utils';
import { Badge, Button, Card, Field, Input, Select, Textarea } from '../../components/ui';
import { DataTable } from '../../components/DataTable';

const emptyRequest = {
  clientId: '',
  sourceJobId: '',
  title: '',
  area: '',
  description: '',
  requirements: '',
  locationCity: '',
  locationState: '',
  workModel: '',
  jobType: '',
  minScore: 60,
};

export function CandidateListsPage() {
  const [requests, setRequests] = useState<CandidateListRequest[]>([]);
  const [clients, setClients] = useState<EmployerClient[]>([]);
  const [selected, setSelected] = useState<CandidateListRequest | null>(null);
  const [items, setItems] = useState<CandidateListItem[]>([]);
  const [form, setForm] = useState(emptyRequest);
  const [message, setMessage] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function loadRequests() {
    const payload = await invokeAdmin<{ requests: CandidateListRequest[] }>('admin-candidate-lists', {
      action: 'list',
      page: 1,
      pageSize: 50,
    });
    setRequests(payload.requests);
  }

  async function loadClients() {
    const payload = await invokeAdmin<{ clients: EmployerClient[] }>('admin-clients', {
      action: 'list',
      page: 1,
      pageSize: 100,
    });
    setClients(payload.clients);
  }

  async function openRequest(request: CandidateListRequest) {
    const payload = await invokeAdmin<{ request: CandidateListRequest; items: CandidateListItem[] }>('admin-candidate-lists', {
      action: 'detail',
      id: request.id,
    });
    setSelected(payload.request);
    setItems(payload.items);
  }

  async function createRequest() {
    setMessage(null);
    try {
      const payload = await invokeAdmin<{ request: CandidateListRequest }>('admin-candidate-lists', {
        action: 'create',
        request: {
          clientId: form.clientId || null,
          sourceJobId: form.sourceJobId || null,
          title: form.title,
          area: form.area || null,
          description: form.description || null,
          requirements: form.requirements.split('\n').map((s) => s.trim()).filter(Boolean),
          locationCity: form.locationCity || null,
          locationState: form.locationState || null,
          workModel: form.workModel || null,
          jobType: form.jobType || null,
          minScore: Number(form.minScore),
        },
      });
      setForm(emptyRequest);
      await loadRequests();
      await openRequest(payload.request);
    } catch (err) {
      setMessage(err instanceof Error ? err.message : 'Erro ao criar lista');
    }
  }

  async function generate() {
    if (!selected) return;
    setLoading(true);
    setMessage(null);
    try {
      const payload = await invokeAdmin<{ count: number; items: CandidateListItem[] }>('admin-candidate-lists', {
        action: 'generate',
        id: selected.id,
      });
      setItems(payload.items);
      setMessage(`${formatNumber(payload.count)} candidatos ranqueados.`);
      await loadRequests();
    } catch (err) {
      setMessage(err instanceof Error ? err.message : 'Erro ao gerar ranking');
    } finally {
      setLoading(false);
    }
  }

  async function updateItem(item: CandidateListItem, status: CandidateListItem['status']) {
    setMessage(null);
    // Feedback otimista: reflete na hora; openRequest reconcilia com o servidor.
    setItems((prev) => prev.map((x) => (x.id === item.id ? { ...x, status } : x)));
    try {
      await invokeAdmin('admin-candidate-lists', {
        action: 'update_item',
        itemId: item.id,
        item: { status },
      });
      if (selected) await openRequest(selected);
    } catch (err) {
      setMessage(err instanceof Error ? err.message : 'Erro ao atualizar candidato');
      if (selected) await openRequest(selected); // reverte pro estado real do servidor
    }
  }

  async function exportCsv() {
    if (!selected) return;
    setMessage(null);
    try {
      const payload = await invokeAdmin<{ filename: string; csv: string; count: number }>('admin-candidate-lists', {
        action: 'export',
        id: selected.id,
      });
      // Nome automático legível: stage-{empresa?}-{titulo}-{AAAA-MM-DD}.csv
      // (ignora o filename cru com UUID que a função devolve).
      const today = new Date().toISOString().slice(0, 10);
      const parts = [selected.employer_clients?.name, selected.title]
        .map((part) => (part ? slugify(part) : ''))
        .filter(Boolean);
      const filename = `stage-${parts.join('-') || 'lista'}-${today}.csv`;
      downloadCsv(filename, payload.csv);
      setMessage(`${formatNumber(payload.count)} candidatos exportados.`);
      await openRequest(selected);
      await loadRequests();
    } catch (err) {
      setMessage(err instanceof Error ? err.message : 'Erro ao exportar');
    }
  }

  useEffect(() => {
    void loadRequests();
    void loadClients();
  }, []);

  const requestColumns = useMemo<ColumnDef<CandidateListRequest>[]>(() => [
    {
      header: 'Lista',
      cell: ({ row }) => (
        <button className="text-left font-medium text-ink hover:text-brand" onClick={() => openRequest(row.original)}>
          {row.original.title}
          <div className="text-xs font-normal text-slate-500">{row.original.employer_clients?.name ?? 'Sem empresa'}</div>
        </button>
      ),
    },
    { header: 'Area', accessorKey: 'area' },
    {
      header: 'Status',
      cell: ({ row }) => <Badge tone={row.original.status === 'exported' ? 'green' : 'blue'}>{row.original.status}</Badge>,
    },
    { header: 'Min.', cell: ({ row }) => `${row.original.min_score}%` },
    { header: 'Criada', cell: ({ row }) => formatDate(row.original.created_at) },
  ], []);

  const itemColumns = useMemo<ColumnDef<CandidateListItem>[]>(() => [
    { header: '#', accessorKey: 'rank' },
    {
      header: 'Candidato',
      cell: ({ row }) => (
        <div>
          <div className="font-medium text-ink">{row.original.candidate?.name ?? row.original.userId}</div>
          <div className="text-xs text-slate-500">{row.original.candidate?.headline ?? row.original.candidate?.email}</div>
        </div>
      ),
    },
    { header: 'Score', accessorKey: 'score' },
    {
      header: 'Consent.',
      cell: ({ row }) => (
        <Badge tone={row.original.exportable ? 'green' : 'amber'}>
          {row.original.candidate?.consentStatus ?? 'not_asked'}
        </Badge>
      ),
    },
    {
      header: 'Status',
      cell: ({ row }) => <Badge>{row.original.status}</Badge>,
    },
    {
      header: 'Acoes',
      cell: ({ row }) => (
        <div className="flex gap-2">
          <Button variant="secondary" onClick={() => updateItem(row.original, 'approved')}>Aprovar</Button>
          <Button variant="ghost" onClick={() => updateItem(row.original, 'rejected')}>Rejeitar</Button>
        </div>
      ),
    },
  ], []);

  return (
    <div className="grid gap-5">
      <div>
        <h1 className="text-2xl font-semibold text-ink">Listas de candidatos</h1>
        <p className="text-sm text-slate-500">Crie, ranqueie, revise e exporte listas B2B.</p>
      </div>
      <Card>
        <h2 className="mb-3 text-base font-semibold">Nova lista</h2>
        <div className="grid gap-3 md:grid-cols-3">
          <Field label="Empresa">
            <Select value={form.clientId} onChange={(e) => setForm({ ...form, clientId: e.target.value })}>
              <option value="">Sem empresa</option>
              {clients.map((client) => <option key={client.id} value={client.id}>{client.name}</option>)}
            </Select>
          </Field>
          <Field label="ID da vaga existente">
            <Input value={form.sourceJobId} onChange={(e) => setForm({ ...form, sourceJobId: e.target.value })} placeholder="Opcional" />
          </Field>
          <Field label="Score minimo">
            <Input value={form.minScore} onChange={(e) => setForm({ ...form, minScore: Number(e.target.value) })} type="number" min={0} max={100} />
          </Field>
          <Field label="Titulo">
            <Input value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} placeholder="Obrigatorio se nao houver vaga" />
          </Field>
          <Field label="Area">
            <Input value={form.area} onChange={(e) => setForm({ ...form, area: e.target.value })} />
          </Field>
          <Field label="Modelo">
            <Select value={form.workModel} onChange={(e) => setForm({ ...form, workModel: e.target.value })}>
              <option value="">Qualquer</option>
              <option value="remoto">Remoto</option>
              <option value="hibrido">Hibrido</option>
              <option value="presencial">Presencial</option>
            </Select>
          </Field>
          <Field label="Cidade">
            <Input value={form.locationCity} onChange={(e) => setForm({ ...form, locationCity: e.target.value })} />
          </Field>
          <Field label="Estado">
            <Input value={form.locationState} onChange={(e) => setForm({ ...form, locationState: e.target.value })} />
          </Field>
          <Field label="Tipo">
            <Select value={form.jobType} onChange={(e) => setForm({ ...form, jobType: e.target.value })}>
              <option value="">Qualquer</option>
              <option value="estagio">Estagio</option>
              <option value="trainee">Trainee</option>
              <option value="clt_junior">CLT Junior</option>
              <option value="temporario">Temporario</option>
            </Select>
          </Field>
          <div className="md:col-span-3">
            <Field label="Descricao">
              <Textarea value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} />
            </Field>
          </div>
          <div className="md:col-span-3">
            <Field label="Requisitos, um por linha">
              <Textarea value={form.requirements} onChange={(e) => setForm({ ...form, requirements: e.target.value })} />
            </Field>
          </div>
          <div className="md:col-span-3">
            <Button onClick={createRequest} disabled={!form.sourceJobId.trim() && !form.title.trim()}>
              <Plus size={15} className="mr-2" />
              Criar lista
            </Button>
          </div>
        </div>
      </Card>
      {message ? <Card className="text-sm text-slate-700">{message}</Card> : null}
      <div className="grid gap-5 xl:grid-cols-[420px_1fr]">
        <div>
          <DataTable data={requests} columns={requestColumns} />
        </div>
        <Card>
          {selected ? (
            <div className="grid gap-4">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <h2 className="text-lg font-semibold">{selected.title}</h2>
                  <p className="text-sm text-slate-500">{items.length} candidatos no ranking</p>
                </div>
                <div className="flex gap-2">
                  <Button onClick={generate} disabled={loading}>
                    <Play size={15} className="mr-2" />
                    Gerar
                  </Button>
                  <Button variant="secondary" onClick={exportCsv}>
                    <Download size={15} className="mr-2" />
                    CSV
                  </Button>
                </div>
              </div>
              <DataTable data={items} columns={itemColumns} empty="Gere o ranking para ver candidatos" />
              {items[0]?.scoreBreakdown?.length ? (
                <div className="rounded-lg bg-slate-50 p-3 text-sm text-slate-700">
                  <b>Motivos do primeiro candidato:</b>
                  <ul className="mt-2 list-disc pl-5">
                    {items[0].scoreBreakdown.map((item) => (
                      <li key={item.label}>{item.label}: {item.points} pts · {item.detail}</li>
                    ))}
                  </ul>
                </div>
              ) : null}
            </div>
          ) : (
            <div className="py-16 text-center text-slate-500">Selecione uma lista para revisar candidatos.</div>
          )}
        </Card>
      </div>
    </div>
  );
}
