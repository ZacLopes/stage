import { createContext, useContext, useEffect, useMemo, useState } from 'react';
import type { Session } from '@supabase/supabase-js';
import { supabase } from '../lib/supabase';
import { invokeAdmin } from '../lib/api';
import type { AdminUser } from '../lib/types';

interface AuthContextValue {
  session: Session | null;
  admin: AdminUser | null;
  loading: boolean;
  error: string | null;
  refreshAdmin: () => Promise<void>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [admin, setAdmin] = useState<AdminUser | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  async function refreshAdmin() {
    setError(null);
    try {
      const me = await invokeAdmin<AdminUser>('admin-me');
      setAdmin(me);
    } catch (err) {
      // Falha transitória do admin-me (token em renovação, StrictMode, blip de
      // rede) NÃO deve derrubar um admin já validado pra tela de "Acesso negado".
      // O servidor revalida a cada chamada; aqui mantemos o último estado bom.
      setError(err instanceof Error ? err.message : 'Falha ao validar admin');
    }
  }

  useEffect(() => {
    let mounted = true;
    supabase.auth.getSession().then(async ({ data }) => {
      if (!mounted) return;
      setSession(data.session);
      if (data.session) await refreshAdmin();
      setLoading(false);
    });
    const { data: listener } = supabase.auth.onAuthStateChange(async (event, nextSession) => {
      setSession(nextSession);
      if (event === 'SIGNED_OUT' || !nextSession) {
        setAdmin(null);
      } else if (event === 'SIGNED_IN' || event === 'INITIAL_SESSION') {
        await refreshAdmin();
      }
      // TOKEN_REFRESHED / USER_UPDATED: sessão só renovou, o admin segue válido —
      // não revalidar aqui era o que disparava o "Acesso negado" no meio do clique.
      setLoading(false);
    });
    return () => {
      mounted = false;
      listener.subscription.unsubscribe();
    };
  }, []);

  const value = useMemo<AuthContextValue>(() => ({
    session,
    admin,
    loading,
    error,
    refreshAdmin,
    signOut: async () => {
      await supabase.auth.signOut();
      setAdmin(null);
      setSession(null);
    },
  }), [session, admin, loading, error]);

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const value = useContext(AuthContext);
  if (!value) throw new Error('useAuth must be used within AuthProvider');
  return value;
}
