import { supabase } from './supabase';

const ADMIN_FUNCTION_TIMEOUT_MS = 30_000;

// supabase-js embrulha resposta não-2xx num FunctionsHttpError cujo `.message`
// é sempre o genérico "Edge Function returned a non-2xx status code". O corpo
// real ({ error, message }) vive no `.context` (o Response original). Lê de volta
// pra propagar o motivo verdadeiro (ex.: "No approved candidates with granted
// consent") em vez do genérico.
async function describeFunctionError(error: unknown): Promise<string> {
  const ctx = (error as { context?: unknown })?.context;
  if (ctx instanceof Response) {
    try {
      const body = await ctx.clone().json();
      if (body?.message) return String(body.message);
      if (body?.error) return String(body.error);
    } catch {
      try {
        const text = (await ctx.clone().text()).trim();
        if (text) return text.slice(0, 300);
      } catch {
        // corpo já consumido / não legível — cai no genérico abaixo
      }
    }
  }
  return error instanceof Error ? error.message : 'Erro na função admin';
}

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

  if (error) throw new Error(await describeFunctionError(error));
  const payload = data as { error?: string; message?: string } & T;
  if (payload?.error) throw new Error(payload.message ?? payload.error);
  return payload as T;
}

export function downloadCsv(filename: string, csv: string) {
  // Prefixa o BOM UTF-8 (U+FEFF): sem ele o Excel lê o arquivo como Latin-1 e
  // quebra os acentos — "São Paulo" vira "SÃ£o Paulo".
  const bom = String.fromCharCode(0xfeff);
  const blob = new Blob([bom, csv], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}
