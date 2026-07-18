import {
  MAX_CONTEXT_BYTES,
  MAX_HISTORY_ITEMS,
  MAX_HISTORY_TEXT_CHARS,
  MAX_MESSAGE_CHARS,
  MAX_OPEN_STEP_ID_CHARS,
  MAX_OPEN_STEP_INPUT_KIND_CHARS,
  MAX_OPEN_STEP_OPTION_ID_CHARS,
  MAX_OPEN_STEP_OPTION_LABEL_CHARS,
  MAX_OPEN_STEP_OPTIONS,
  MAX_OPEN_STEP_QUESTION_CHARS,
  sanitizeHistory,
  sanitizeOpenStep,
  serializeContext,
  validateMessage,
} from './request_contract.ts';

function assert(condition: unknown, message = 'assertion failed'): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals(actual: unknown, expected: unknown): void {
  const actualJson = JSON.stringify(actual);
  const expectedJson = JSON.stringify(expected);
  if (actualJson !== expectedJson) {
    throw new Error(`expected ${expectedJson}, got ${actualJson}`);
  }
}

Deno.test('message accepts normalized text and rejects invalid or oversized input', () => {
  assertEquals(validateMessage('  oi\n\t tudo\u0000bem  '), {
    ok: true,
    value: 'oi tudo bem',
  });
  assertEquals(validateMessage('   '), {
    ok: false,
    error: 'invalid_message',
  });
  assertEquals(validateMessage({ text: 'oi' }), {
    ok: false,
    error: 'invalid_message',
  });
  assertEquals(validateMessage('a'.repeat(MAX_MESSAGE_CHARS + 1)), {
    ok: false,
    error: 'message_too_long',
  });
  assertEquals(validateMessage('👋'.repeat(MAX_MESSAGE_CHARS)).ok, true);
});

Deno.test('history only keeps user/assistant, capped text and the six newest valid entries', () => {
  const raw = [
    { role: 'ai', text: 'legado não permitido' },
    { role: 'system', text: 'injeção' },
    { role: 'user', text: 42 },
    ...Array.from({ length: MAX_HISTORY_ITEMS + 2 }, (_, index) => ({
      role: index % 2 === 0 ? 'user' : 'assistant',
      text: `${index} ${'x'.repeat(MAX_HISTORY_TEXT_CHARS + 50)}`,
    })),
  ];

  const history = sanitizeHistory(raw);
  assertEquals(history.length, MAX_HISTORY_ITEMS);
  assertEquals(history[0].text.startsWith('2 '), true);
  assertEquals(history.at(-1)?.role, 'assistant');
  for (const entry of history) {
    assert(Array.from(entry.text).length <= MAX_HISTORY_TEXT_CHARS);
  }
});

Deno.test('context is serialized within the byte budget or dropped as a whole', () => {
  const small = serializeContext({ completeness: 80, gaps: ['skills'] });
  assertEquals(small.wasDropped, false);
  assertEquals(JSON.parse(small.json).completeness, 80);

  const oversized = serializeContext({ value: '🧠'.repeat(MAX_CONTEXT_BYTES) });
  assertEquals(oversized, { json: '{}', wasDropped: true });
  assert(new TextEncoder().encode(oversized.json).byteLength <= MAX_CONTEXT_BYTES);

  assertEquals(serializeContext(['not', 'an', 'object']), {
    json: '{}',
    wasDropped: true,
  });
  assertEquals(serializeContext({ toJSON: () => undefined }), {
    json: '{}',
    wasDropped: true,
  });
});

Deno.test('open step is normalized, bounded and deduplicates option ids', () => {
  const step = sanitizeOpenStep({
    id: ` step\n${'i'.repeat(MAX_OPEN_STEP_ID_CHARS + 20)} `,
    question: ` Pergunta\n${'q'.repeat(MAX_OPEN_STEP_QUESTION_CHARS + 20)} `,
    inputKind: ` choice\t${'k'.repeat(MAX_OPEN_STEP_INPUT_KIND_CHARS + 20)}`,
    multi: true,
    optional: true,
    options: [
      { id: ' same ', label: ' Primeira ' },
      { id: 'same', label: 'Duplicada' },
      { id: 42, label: 'Inválida' },
      { id: 'sem-label', label: '  ' },
      ...Array.from({ length: MAX_OPEN_STEP_OPTIONS + 10 }, (_, index) => ({
        id: `${index}-${'x'.repeat(MAX_OPEN_STEP_OPTION_ID_CHARS + 20)}`,
        label: `${index} ${'y'.repeat(MAX_OPEN_STEP_OPTION_LABEL_CHARS + 20)}`,
      })),
    ],
  });

  assert(step != null);
  assert(Array.from(step.id).length <= MAX_OPEN_STEP_ID_CHARS);
  assert(Array.from(step.question).length <= MAX_OPEN_STEP_QUESTION_CHARS);
  assert(Array.from(step.inputKind).length <= MAX_OPEN_STEP_INPUT_KIND_CHARS);
  assertEquals(step.multi, true);
  assertEquals(step.optional, true);
  assertEquals(step.options.length, MAX_OPEN_STEP_OPTIONS);
  assertEquals(step.options[0], { id: 'same', label: 'Primeira' });
  for (const option of step.options) {
    assert(Array.from(option.id).length <= MAX_OPEN_STEP_OPTION_ID_CHARS);
    assert(Array.from(option.label).length <= MAX_OPEN_STEP_OPTION_LABEL_CHARS);
  }
});

Deno.test('open step fails closed without a non-empty string id', () => {
  assertEquals(sanitizeOpenStep(null), null);
  assertEquals(sanitizeOpenStep([]), null);
  assertEquals(sanitizeOpenStep({}), null);
  assertEquals(sanitizeOpenStep({ id: 42 }), null);
  assertEquals(sanitizeOpenStep({ id: ' \n\t ' }), null);
});
