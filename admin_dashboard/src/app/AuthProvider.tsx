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
      setAdmin(null);
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
    const { data: listener } = supabase.auth.onAuthStateChange(async (_, nextSession) => {
      setSession(nextSession);
      if (nextSession) await refreshAdmin();
      else setAdmin(null);
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
