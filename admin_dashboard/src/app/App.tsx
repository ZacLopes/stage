import { useEffect, useState } from 'react';
import { AuthProvider, useAuth } from './AuthProvider';
import { Layout, type PageId } from './Layout';
import { LoginPage } from './LoginPage';
import { OverviewPage } from '../features/overview/OverviewPage';
import { JobsPage } from '../features/jobs/JobsPage';
import { UsersPage } from '../features/users/UsersPage';
import { ClientsPage } from '../features/clients/ClientsPage';
import { CandidateListsPage } from '../features/candidate-lists/CandidateListsPage';
import { CandidatesSearchPage } from '../features/candidates/CandidatesSearchPage';
import { CompanyRequestsPage } from '../features/company-requests/CompanyRequestsPage';
import { Card } from '../components/ui';

function currentPage(): PageId {
  const hash = window.location.hash.replace('#', '');
  if (['overview', 'jobs', 'users', 'candidates', 'clients', 'candidate-lists', 'company-requests'].includes(hash)) return hash as PageId;
  return 'overview';
}

function Shell() {
  const { session, admin, loading, error } = useAuth();
  const [page, setPage] = useState<PageId>(currentPage());

  useEffect(() => {
    const handler = () => setPage(currentPage());
    window.addEventListener('hashchange', handler);
    return () => window.removeEventListener('hashchange', handler);
  }, []);

  function changePage(next: PageId) {
    window.location.hash = next;
    setPage(next);
  }

  if (loading) return <main className="grid min-h-screen place-items-center text-slate-500">Carregando...</main>;
  if (!session) return <LoginPage />;
  if (!admin) {
    return (
      <main className="grid min-h-screen place-items-center bg-slate-50 px-4">
        <Card className="max-w-lg">
          <h1 className="text-lg font-semibold">Acesso negado</h1>
          <p className="mt-2 text-sm text-slate-600">
            Sua conta esta autenticada, mas nao esta ativa em admin_users.
          </p>
          {error ? <p className="mt-3 text-sm text-rose-600">{error}</p> : null}
        </Card>
      </main>
    );
  }

  return (
    <Layout page={page} onPageChange={changePage}>
      {page === 'overview' && <OverviewPage />}
      {page === 'jobs' && <JobsPage onOpenLists={() => changePage('candidate-lists')} />}
      {page === 'users' && <UsersPage />}
      {page === 'candidates' && <CandidatesSearchPage />}
      {page === 'clients' && <ClientsPage />}
      {page === 'candidate-lists' && <CandidateListsPage />}
      {page === 'company-requests' && <CompanyRequestsPage />}
    </Layout>
  );
}

export function App() {
  return (
    <AuthProvider>
      <Shell />
    </AuthProvider>
  );
}
