import { useEffect, useMemo, useState } from 'react';
import type { ColumnDef } from '@tanstack/react-table';
import { Plus, Search } from 'lucide-react';
import { invokeAdmin } from '../../lib/api';
import type { EmployerClient } from '../../lib/types';
import { formatDate, formatNumber } from '../../lib/utils';
import { Badge, Button, Card, Field, Input, Select, Textarea } from '../../components/ui';
import { DataTable } from '../../components/DataTable';

const emptyForm = {
  name: '',
  website: '',
  contactName: '',
  contactEmail: '',
  status: 'prospect',
  notes: '',
};

export function ClientsPage() {
  const [clients, setClients] = useState<EmployerClient[]>([]);
  const [total, setTotal] = useState(0);
  const [search, setSearch] = useState('');
  const [form, setForm] = useState(emptyForm);
  const [message, setMessage] = useState<string | null>(null);

  async function load() {
    const payload = await invokeAdmin<{ clients: EmployerClient[]; total: number }>('admin-clients', {
      action: 'list',
      page: 1,
      pageSize: 50,
      search,
    });
    setClients(payload.clients);
    setTotal(payload.total);
  }

  async function create() {
    setMessage(null);
    try {
      await invokeAdmin('admin-clients', {
        action: 'create',
        client: {
          name: form.name,
          website: form.website || null,
          contactName: form.contactName || null,
          contactEmail: form.contactEmail || null,
          status: form.status,
          notes: form.notes || null,
        },
      });
      setForm(emptyForm);
      await load();
    } catch (err) {
      setMessage(err instanceof Error ? err.message : 'Erro ao criar empresa');
    }
  }

  useEffect(() => {
    void load();
  }, []);

  const columns = useMemo<ColumnDef<EmployerClient>[]>(() => [
    {
      header: 'Empresa',
      cell: ({ row }) => (
        <div>
          <div className="font-medium text-ink">{row.original.name}</div>
          <div className="text-xs text-slate-500">{row.original.website ?? '-'}</div>
        </div>
      ),
    },
    { header: 'Contato', cell: ({ row }) => row.original.contactName ?? '-' },
    { header: 'Email', cell: ({ row }) => row.original.contactEmail ?? '-' },
    {
      header: 'Status',
      cell: ({ row }) => <Badge tone={row.original.status === 'active' ? 'green' : 'slate'}>{row.original.status}</Badge>,
    },
    { header: 'Criada', cell: ({ row }) => formatDate(row.original.createdAt) },
  ], []);

  return (
    <div className="grid gap-5">
      <div>
        <h1 className="text-2xl font-semibold text-ink">Empresas</h1>
        <p className="text-sm text-slate-500">{formatNumber(total)} clientes B2B cadastrados</p>
      </div>
      <Card>
        <h2 className="mb-3 text-base font-semibold">Nova empresa</h2>
        <div className="grid gap-3 md:grid-cols-3">
          <Field label="Nome">
            <Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
          </Field>
          <Field label="Website">
            <Input value={form.website} onChange={(e) => setForm({ ...form, website: e.target.value })} />
          </Field>
          <Field label="Status">
            <Select value={form.status} onChange={(e) => setForm({ ...form, status: e.target.value })}>
              <option value="prospect">Prospect</option>
              <option value="active">Active</option>
              <option value="paused">Paused</option>
              <option value="archived">Archived</option>
            </Select>
          </Field>
          <Field label="Contato">
            <Input value={form.contactName} onChange={(e) => setForm({ ...form, contactName: e.target.value })} />
          </Field>
          <Field label="Email">
            <Input value={form.contactEmail} onChange={(e) => setForm({ ...form, contactEmail: e.target.value })} />
          </Field>
          <div className="flex items-end">
            <Button onClick={create} disabled={!form.name.trim()}>
              <Plus size={15} className="mr-2" />
              Criar
            </Button>
          </div>
          <div className="md:col-span-3">
            <Field label="Notas">
              <Textarea value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} />
            </Field>
          </div>
        </div>
      </Card>
      <Card>
        <div className="grid gap-3 md:grid-cols-[1fr_auto]">
          <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Buscar empresa ou contato" />
          <Button onClick={load}>
            <Search size={15} className="mr-2" />
            Buscar
          </Button>
        </div>
      </Card>
      {message ? <Card className="text-sm text-rose-600">{message}</Card> : null}
      <DataTable data={clients} columns={columns} />
    </div>
  );
}
