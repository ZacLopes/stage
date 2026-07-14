import { assertEquals, assertFalse } from 'https://deno.land/std@0.168.0/testing/asserts.ts';
import {
  isApplePrivateRelayEmail,
  isSyntheticAuthEmail,
  isUsableContactEmail,
  publicContactEmailOrEmpty,
  resolveImportedContactEmail,
} from './contact_email.ts';

Deno.test('detecta os dois domínios Apple sem bloquear iCloud comum', () => {
  assertEquals(isApplePrivateRelayEmail('a@privaterelay.appleid.com'), true);
  assertEquals(isApplePrivateRelayEmail('a@private.icloud.com'), true);
  assertFalse(isApplePrivateRelayEmail('a@sub.private.icloud.com'));
  assertFalse(isApplePrivateRelayEmail('pessoa@icloud.com'));
  assertEquals(isUsableContactEmail('pessoa@icloud.com'), true);
});

Deno.test('detecta e-mail sintético do login por telefone', () => {
  assertEquals(isSyntheticAuthEmail('phone_5511987654321@stage.app'), true);
  assertFalse(isUsableContactEmail('phone_5511987654321@stage.app'));
  assertFalse(isSyntheticAuthEmail('pessoa@stage.app'));
});

Deno.test('normaliza contato público e suprime valores inseguros', () => {
  assertEquals(publicContactEmailOrEmpty('  Pessoa@Example.COM '), 'pessoa@example.com');
  assertEquals(publicContactEmailOrEmpty('alias@private.icloud.com'), '');
  assertEquals(publicContactEmailOrEmpty('inválido'), '');
});

Deno.test('importação preserva contato profissional existente', () => {
  assertEquals(
    resolveImportedContactEmail('manual@example.com', 'curriculo@example.com'),
    'manual@example.com',
  );
});

Deno.test('importação preenche vazio ou relay com contato válido', () => {
  assertEquals(
    resolveImportedContactEmail(null, 'CURRICULO@Example.com'),
    'curriculo@example.com',
  );
  assertEquals(
    resolveImportedContactEmail('alias@privaterelay.appleid.com', 'cv@example.com'),
    'cv@example.com',
  );
});

Deno.test('importação nunca introduz relay ou sintético', () => {
  assertEquals(resolveImportedContactEmail(null, 'alias@private.icloud.com'), null);
  assertEquals(resolveImportedContactEmail(null, 'phone_5511999999999@stage.app'), null);
});
