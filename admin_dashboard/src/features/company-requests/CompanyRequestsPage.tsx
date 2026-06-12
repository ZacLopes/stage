import { useCallback, useEffect, useState } from 'react';
import type { ColumnDef } from '@tanstack/react-table';
import { invokeAdmin } from '../../lib/api';
import { DataTable } from '../../components/DataTable';
import { Button, Card } from '../../components/ui';

// FASE 2 (T2.3): pedidos de empresa feitos no estado de exaustão do feed.
// Leitura simples via admin-jobs { action: 'company_requests' } — alimenta a
// prospecção B2B ("quais empresas os candidatos pedem?").

interface CompanyRequestRow {
  id: string;
  companyName: string;
  note: string | null;
  createdAt: string;
  userId: string;
  user: { name?: string; email?: string } | null;
}

interface CompanyRequestsResponse {
  requests: CompanyRequestRow[];
  page: number;
  pageSize: number;
  total: number;
}

const PAGE_SIZE = 50;

const columns: ColumnDef<CompanyRequestRow>[] = [
  {
    header: 'Quando',
    accessorKey: 'createdAt',
    cell: ({ row }) => new Date(row.original.createdAt).toLocaleString('pt-BR'),
  },
  {
    header: 'Empresa pedida',
    accessorKey: 'companyName',
    cell: ({ row }) => <span className="font-semibold">{row.original.companyName}</span>,
  },
  {
    header: 'Nota',
    accessorKey: 'note',
    cell: ({ row }) => row.original.note ?? <span className="text-slate-400">—</span>,
  },
  {
    header: 'Candidato',
    accessorKey: 'user',
    cell: ({ row }) => {
      const u = row.original.user;
      if (!u) return <span className="text-slate-400">{row.original.userId.slice(0, 8)}…</span>;
      return (
        <div>
          <div>{u.name ?? '—'}</div>
          <div className="text-xs text-slate-500">{u.email ?? ''}</div>
        </div>
      );
    },
  },
];

export function CompanyRequestsPage() {
  const [rows, setRows] = useState<CompanyRequestRow[]>([]);
  const [page, setPage] = useState(1);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async (nextPage: number) => {
    setLoading(true);
    setError(null);
    try {
      const data = await invokeAdmin<CompanyRequestsResponse>('admin-jobs', {
        action: 'company_requests',
        page: nextPage,
        pageSize: PAGE_SIZE,
      });
      setRows(data.requests);
      setTotal(data.total);
      setPage(nextPage);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Falha ao carregar pedidos');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load(1);
  }, [load]);

  const lastPage = Math.max(1, Math.ceil(total / PAGE_SIZE));

  return (
    <div className="grid gap-4">
      <Card>
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-lg font-semibold">Pedidos de empresa</h1>
            <p className="text-sm text-slate-500">
              Empresas que candidatos pediram no fim do feed ({total} no total).
            </p>
          </div>
          <Button variant="secondary" onClick={() => void load(page)} disabled={loading}>
            {loading ? 'Carregando…' : 'Atualizar'}
          </Button>
        </div>
      </Card>

      {error ? (
        <Card>
          <p className="text-sm text-rose-600">{error}</p>
        </Card>
      ) : (
        <DataTable data={rows} columns={columns} empty="Nenhum pedido ainda." />
      )}

      {lastPage > 1 ? (
        <div className="flex items-center justify-end gap-2 text-sm text-slate-600">
          <Button variant="ghost" disabled={page <= 1 || loading} onClick={() => void load(page - 1)}>
            Anterior
          </Button>
          <span>
            {page} / {lastPage}
          </span>
          <Button variant="ghost" disabled={page >= lastPage || loading} onClick={() => void load(page + 1)}>
            Próxima
          </Button>
        </div>
      ) : null}
    </div>
  );
}
