import { ButtonHTMLAttributes, InputHTMLAttributes, SelectHTMLAttributes, TextareaHTMLAttributes } from 'react';
import { cn } from '../lib/utils';

export function Button(props: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: 'primary' | 'secondary' | 'ghost' | 'danger' }) {
  const { className, variant = 'primary', ...rest } = props;
  return (
    <button
      className={cn(
        'inline-flex h-9 items-center justify-center rounded-md px-3 text-sm font-medium transition disabled:cursor-not-allowed disabled:opacity-50',
        variant === 'primary' && 'bg-brand text-white hover:bg-sky-700',
        variant === 'secondary' && 'border border-border bg-white text-ink hover:bg-slate-50',
        variant === 'ghost' && 'text-slate-700 hover:bg-slate-100',
        variant === 'danger' && 'bg-rose-600 text-white hover:bg-rose-700',
        className,
      )}
      {...rest}
    />
  );
}

export function Input(props: InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      {...props}
      className={cn(
        'h-9 w-full rounded-md border border-border bg-white px-3 text-sm outline-none ring-brand/20 placeholder:text-slate-400 focus:ring-4',
        props.className,
      )}
    />
  );
}

export function Textarea(props: TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return (
    <textarea
      {...props}
      className={cn(
        'min-h-24 w-full rounded-md border border-border bg-white px-3 py-2 text-sm outline-none ring-brand/20 placeholder:text-slate-400 focus:ring-4',
        props.className,
      )}
    />
  );
}

export function Select(props: SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select
      {...props}
      className={cn(
        'h-9 w-full rounded-md border border-border bg-white px-3 text-sm outline-none ring-brand/20 focus:ring-4',
        props.className,
      )}
    />
  );
}

export function Card(props: { children: React.ReactNode; className?: string }) {
  return (
    <section className={cn('rounded-lg border border-border bg-white p-4 shadow-panel', props.className)}>
      {props.children}
    </section>
  );
}

export function Badge(props: { children: React.ReactNode; tone?: 'slate' | 'green' | 'amber' | 'red' | 'blue' }) {
  const tone = props.tone ?? 'slate';
  return (
    <span
      className={cn(
        'inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium',
        tone === 'slate' && 'bg-slate-100 text-slate-700',
        tone === 'green' && 'bg-emerald-100 text-emerald-700',
        tone === 'amber' && 'bg-amber-100 text-amber-700',
        tone === 'red' && 'bg-rose-100 text-rose-700',
        tone === 'blue' && 'bg-sky-100 text-sky-700',
      )}
    >
      {props.children}
    </span>
  );
}

export function Field(props: { label: string; children: React.ReactNode }) {
  return (
    <label className="grid gap-1.5 text-sm font-medium text-slate-700">
      <span>{props.label}</span>
      {props.children}
    </label>
  );
}
