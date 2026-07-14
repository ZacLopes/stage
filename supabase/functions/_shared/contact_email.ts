/**
 * Política compartilhada para o e-mail público do perfil.
 *
 * Endereços privados/sintéticos continuam válidos como identidade de login,
 * mas não podem aparecer em currículos ou superfícies de recrutamento.
 */

const APPLE_PRIVATE_RELAY_DOMAINS = new Set([
  'privaterelay.appleid.com',
  'private.icloud.com',
]);

const VALID_EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

export function normalizeContactEmail(value: unknown): string {
  return typeof value === 'string' ? value.trim().toLowerCase() : '';
}

function emailDomain(value: unknown): string {
  const normalized = normalizeContactEmail(value);
  const separator = normalized.lastIndexOf('@');
  return separator < 0 ? '' : normalized.slice(separator + 1);
}

export function isValidContactEmail(value: unknown): boolean {
  const normalized = normalizeContactEmail(value);
  return normalized.length > 0 && VALID_EMAIL.test(normalized);
}

export function isApplePrivateRelayEmail(value: unknown): boolean {
  return APPLE_PRIVATE_RELAY_DOMAINS.has(emailDomain(value));
}

export function isSyntheticAuthEmail(value: unknown): boolean {
  const normalized = normalizeContactEmail(value);
  const separator = normalized.indexOf('@');
  if (separator <= 0 || emailDomain(normalized) !== 'stage.app') return false;
  const localPart = normalized.slice(0, separator);
  return localPart.startsWith('phone_') && localPart.length > 'phone_'.length;
}

export function isUsableContactEmail(value: unknown): boolean {
  return isValidContactEmail(value) &&
    !isApplePrivateRelayEmail(value) &&
    !isSyntheticAuthEmail(value);
}

export function publicContactEmailOrEmpty(value: unknown): string {
  return isUsableContactEmail(value) ? normalizeContactEmail(value) : '';
}

/**
 * Importação preserva sempre um contato público escolhido pelo usuário.
 * Um valor extraído só preenche perfil vazio/privado e nunca introduz relay.
 * `null` faz o RPC manter o valor existente por sua semântica de COALESCE.
 */
export function resolveImportedContactEmail(
  existingValue: unknown,
  importedValue: unknown,
): string | null {
  const existing = publicContactEmailOrEmpty(existingValue);
  if (existing) return existing;

  const imported = publicContactEmailOrEmpty(importedValue);
  return imported || null;
}
