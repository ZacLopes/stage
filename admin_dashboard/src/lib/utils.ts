import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function formatNumber(value: number | undefined | null) {
  return new Intl.NumberFormat('pt-BR').format(value ?? 0);
}

export function formatPercent(value: number | undefined | null) {
  return new Intl.NumberFormat('pt-BR', {
    style: 'percent',
    maximumFractionDigits: 1,
  }).format(value ?? 0);
}

export function formatDate(value: string | undefined | null) {
  if (!value) return '-';
  return new Intl.DateTimeFormat('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: '2-digit',
  }).format(new Date(value));
}

// Slug ASCII pra nomes de arquivo: remove acentos (via NFD + classe Unicode
// Diacritic), baixa pra minúsculas e troca não-alfanuméricos por hífen.
// "Estágio — Cliente X" -> "estagio-cliente-x".
export function slugify(value: string): string {
  return value
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60);
}
