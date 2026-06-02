import { supabase } from './supabase';

const ADMIN_FUNCTION_TIMEOUT_MS = 30_000;

export async function invokeAdmin<T>(fn: string, body?: Record<string, unknown>): Promise<T> {
  let timeout: ReturnType<typeof setTimeout> | undefined;
  const timeoutPromise = new Promise<never>((_, reject) => {
    timeout = setTimeout(() => {
      reject(new Error(`A chamada ${fn} demorou mais de 30s. Tente novamente ou verifique os logs da Edge Function.`));
    }, ADMIN_FUNCTION_TIMEOUT_MS);
  });

  const { data, error } = await Promise.race([
    supabase.functions.invoke(fn, { body: body ?? {} }),
    timeoutPromise,
  ]).finally(() => {
    if (timeout) clearTimeout(timeout);
  });

  if (error) throw new Error(error.message);
  const payload = data as { error?: string; message?: string } & T;
  if (payload?.error) throw new Error(payload.message ?? payload.error);
  return payload as T;
}

export function downloadCsv(filename: string, csv: string) {
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}
