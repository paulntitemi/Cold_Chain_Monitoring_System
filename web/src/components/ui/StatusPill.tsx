import clsx from 'clsx';
import type { ReactNode } from 'react';

interface Props {
  label: string;
  value: ReactNode;
  tone?: 'default' | 'teal' | 'amber' | 'red' | 'green';
  pulse?: 'amber' | 'red' | null;
}

const toneBg: Record<NonNullable<Props['tone']>, string> = {
  default: 'border-border bg-bg-card',
  teal: 'border-teal/40 bg-teal/10',
  amber: 'border-amber/40 bg-amber/10',
  red: 'border-red/40 bg-red/15',
  green: 'border-green/40 bg-green/10',
};

const toneValue: Record<NonNullable<Props['tone']>, string> = {
  default: 'text-text-primary',
  teal: 'text-teal',
  amber: 'text-amber',
  red: 'text-red',
  green: 'text-green',
};

export function StatusPill({ label, value, tone = 'default', pulse }: Props) {
  return (
    <div
      className={clsx(
        'flex h-full min-w-[160px] items-center gap-3 rounded-sm border px-4 py-2',
        toneBg[tone],
        pulse === 'red' && 'animate-pulse-red',
        pulse === 'amber' && 'animate-pulse-amber',
      )}
    >
      <span className="text-[10px] uppercase tracking-widest text-text-secondary font-medium">
        {label}
      </span>
      <span className={clsx('font-display text-2xl leading-none font-semibold tracking-wide', toneValue[tone])}>
        {value}
      </span>
    </div>
  );
}
