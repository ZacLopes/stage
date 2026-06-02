import { BarChart3, BriefcaseBusiness, Building2, ListChecks, LogOut, Users } from 'lucide-react';
import { Button } from '../components/ui';
import { useAuth } from './AuthProvider';

const nav = [
  { id: 'overview', label: 'Overview', icon: BarChart3 },
  { id: 'jobs', label: 'Vagas', icon: BriefcaseBusiness },
  { id: 'users', label: 'Usuarios', icon: Users },
  { id: 'clients', label: 'Empresas', icon: Building2 },
  { id: 'candidate-lists', label: 'Listas', icon: ListChecks },
] as const;

export type PageId = typeof nav[number]['id'];

export function Layout(props: {
  page: PageId;
  onPageChange: (page: PageId) => void;
  children: React.ReactNode;
}) {
  const { admin, signOut } = useAuth();

  return (
    <div className="min-h-screen bg-slate-50">
      <aside className="fixed inset-y-0 left-0 hidden w-64 border-r border-border bg-white p-4 md:block">
        <div className="mb-6">
          <div className="text-lg font-semibold text-ink">Stage Admin</div>
          <div className="text-xs text-slate-500">{admin?.email} · {admin?.role}</div>
        </div>
        <nav className="grid gap-1">
          {nav.map((item) => {
            const Icon = item.icon;
            const active = item.id === props.page;
            return (
              <button
                key={item.id}
                onClick={() => props.onPageChange(item.id)}
                className={[
                  'flex items-center gap-2 rounded-md px-3 py-2 text-left text-sm font-medium',
                  active ? 'bg-sky-50 text-brand' : 'text-slate-600 hover:bg-slate-100',
                ].join(' ')}
              >
                <Icon size={18} />
                {item.label}
              </button>
            );
          })}
        </nav>
        <Button variant="ghost" className="absolute bottom-4 left-4 right-4 justify-start" onClick={signOut}>
          <LogOut size={16} className="mr-2" />
          Sair
        </Button>
      </aside>
      <div className="md:pl-64">
        <header className="sticky top-0 z-10 border-b border-border bg-white/95 px-4 py-3 backdrop-blur md:hidden">
          <select
            value={props.page}
            onChange={(e) => props.onPageChange(e.target.value as PageId)}
            className="w-full rounded-md border border-border px-3 py-2"
          >
            {nav.map((item) => <option key={item.id} value={item.id}>{item.label}</option>)}
          </select>
        </header>
        <main className="p-4 md:p-6">{props.children}</main>
      </div>
    </div>
  );
}
