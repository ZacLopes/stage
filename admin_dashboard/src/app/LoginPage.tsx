import { useState } from 'react';
import { Lock } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { Button, Card, Field, Input } from '../components/ui';

export function LoginPage() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [message, setMessage] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function submit() {
    setLoading(true);
    setMessage(null);
    try {
      if (password.trim()) {
        const { error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) throw error;
      } else {
        const { error } = await supabase.auth.signInWithOtp({
          email,
          options: { emailRedirectTo: window.location.origin },
        });
        if (error) throw error;
        setMessage('Enviamos um link de acesso para seu email.');
      }
    } catch (err) {
      setMessage(err instanceof Error ? err.message : 'Falha no login');
    } finally {
      setLoading(false);
    }
  }

  return (
    <main className="grid min-h-screen place-items-center bg-slate-50 px-4">
      <Card className="w-full max-w-md p-6">
        <div className="mb-6 flex items-center gap-3">
          <div className="grid h-10 w-10 place-items-center rounded-lg bg-brand text-white">
            <Lock size={20} />
          </div>
          <div>
            <h1 className="text-xl font-semibold text-ink">Stage Admin</h1>
            <p className="text-sm text-slate-500">Acesso interno para operacao B2B.</p>
          </div>
        </div>
        <div className="grid gap-4">
          <Field label="Email admin">
            <Input value={email} onChange={(e) => setEmail(e.target.value)} type="email" autoComplete="email" />
          </Field>
          <Field label="Senha opcional">
            <Input
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              type="password"
              autoComplete="current-password"
              placeholder="Deixe vazio para magic link"
            />
          </Field>
          <Button onClick={submit} disabled={loading || !email.trim()}>
            {loading ? 'Entrando...' : 'Entrar'}
          </Button>
          {message ? <p className="text-sm text-slate-600">{message}</p> : null}
        </div>
      </Card>
    </main>
  );
}
