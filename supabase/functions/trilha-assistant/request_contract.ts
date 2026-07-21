// Limites do contrato de entrada do assistente. Este arquivo é deliberadamente
// puro para que as defesas possam ser testadas sem iniciar o servidor Edge.

export const MAX_MESSAGE_CHARS = 2_000;
export const MAX_HISTORY_ITEMS = 6;
export const MAX_HISTORY_TEXT_CHARS = 800;
export const MAX_CONTEXT_BYTES = 32 * 1024;
export const MAX_OPEN_STEP_ID_CHARS = 120;
export const MAX_OPEN_STEP_QUESTION_CHARS = 500;
export const MAX_OPEN_STEP_INPUT_KIND_CHARS = 40;
export const MAX_OPEN_STEP_OPTIONS = 50;
export const MAX_OPEN_STEP_OPTION_ID_CHARS = 120;
export const MAX_OPEN_STEP_OPTION_LABEL_CHARS = 200;

export type AssistantHistoryRole = 'user' | 'assistant';

export interface AssistantHistoryEntry {
  role: AssistantHistoryRole;
  text: string;
}

export interface AssistantStepOption {
  id: string;
  label: string;
}

export interface AssistantOpenStep {
  id: string;
  question: string;
  inputKind: string;
  options: AssistantStepOption[];
  multi: boolean;
  optional: boolean;
}

export type MessageValidation =
  | { ok: true; value: string }
  | { ok: false; error: 'invalid_message' | 'message_too_long' };

const encoder = new TextEncoder();

function codePointLength(value: string): number {
  return Array.from(value).length;
}

function truncateCodePoints(value: string, maxChars: number): string {
  const chars = Array.from(value);
  return chars.length <= maxChars ? value : chars.slice(0, maxChars).join('');
}

export function normalizeText(value: string): string {
  return value
    .replace(/[\u0000-\u001f\u007f-\u009f]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export function validateMessage(raw: unknown): MessageValidation {
  if (typeof raw !== 'string') return { ok: false, error: 'invalid_message' };

  const value = normalizeText(raw);
  if (!value) return { ok: false, error: 'invalid_message' };
  if (codePointLength(value) > MAX_MESSAGE_CHARS) {
    return { ok: false, error: 'message_too_long' };
  }
  return { ok: true, value };
}

export function sanitizeHistory(raw: unknown): AssistantHistoryEntry[] {
  if (!Array.isArray(raw)) return [];

  const valid: AssistantHistoryEntry[] = [];
  for (const item of raw) {
    if (!item || typeof item !== 'object' || Array.isArray(item)) continue;
    const entry = item as Record<string, unknown>;
    if (entry.role !== 'user' && entry.role !== 'assistant') continue;
    if (typeof entry.text !== 'string') continue;

    const text = truncateCodePoints(
      normalizeText(entry.text),
      MAX_HISTORY_TEXT_CHARS,
    );
    if (!text) continue;
    valid.push({ role: entry.role, text });
  }
  return valid.slice(-MAX_HISTORY_ITEMS);
}

// `openStep` também vem do request autenticado, portanto não pode ampliar o
// prompt sem limite. Dados inválidos não abrem um passo; opções inválidas ou
// repetidas são descartadas e todos os textos recebem limites previsíveis.
export function sanitizeOpenStep(raw: unknown): AssistantOpenStep | null {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;

  const candidate = raw as Record<string, unknown>;
  if (typeof candidate.id !== 'string') return null;

  const id = truncateCodePoints(
    normalizeText(candidate.id),
    MAX_OPEN_STEP_ID_CHARS,
  );
  if (!id) return null;

  const question = truncateCodePoints(
    normalizeText(typeof candidate.question === 'string' ? candidate.question : ''),
    MAX_OPEN_STEP_QUESTION_CHARS,
  );
  const rawInputKind = normalizeText(
    typeof candidate.inputKind === 'string' ? candidate.inputKind : 'text',
  );
  const inputKind = truncateCodePoints(
    rawInputKind || 'text',
    MAX_OPEN_STEP_INPUT_KIND_CHARS,
  );

  const options: AssistantStepOption[] = [];
  const seenIds = new Set<string>();
  const rawOptions = Array.isArray(candidate.options) ? candidate.options : [];
  for (const rawOption of rawOptions) {
    if (options.length >= MAX_OPEN_STEP_OPTIONS) break;
    if (!rawOption || typeof rawOption !== 'object' || Array.isArray(rawOption)) {
      continue;
    }
    const option = rawOption as Record<string, unknown>;
    if (typeof option.id !== 'string' || typeof option.label !== 'string') {
      continue;
    }
    const optionId = truncateCodePoints(
      normalizeText(option.id),
      MAX_OPEN_STEP_OPTION_ID_CHARS,
    );
    if (!optionId || seenIds.has(optionId)) continue;
    const label = truncateCodePoints(
      normalizeText(option.label),
      MAX_OPEN_STEP_OPTION_LABEL_CHARS,
    );
    if (!label) continue;
    seenIds.add(optionId);
    options.push({ id: optionId, label });
  }

  return {
    id,
    question,
    inputKind,
    options,
    multi: candidate.multi === true,
    optional: candidate.optional === true,
  };
}

export interface SerializedContext {
  json: string;
  wasDropped: boolean;
}

export function serializeContext(raw: unknown): SerializedContext {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    return { json: '{}', wasDropped: raw != null };
  }

  try {
    const json = JSON.stringify(raw);
    if (typeof json !== 'string') {
      return { json: '{}', wasDropped: true };
    }
    if (encoder.encode(json).byteLength > MAX_CONTEXT_BYTES) {
      return { json: '{}', wasDropped: true };
    }
    return { json, wasDropped: false };
  } catch (_) {
    return { json: '{}', wasDropped: true };
  }
}
