import { clsx } from 'clsx';
import type { ReactNode } from 'react';

interface Props {
  children: ReactNode;
  tone?: 'neutral' | 'teal' | 'amber' | 'red' | 'green';
  className?: string;
}

const toneStyles: Record<NonNullable<Props['tone']>, string> = {
  neutral: 'bg-bg-card text-text-primary border-border',
  teal: 'bg-teal/10 text-teal border-teal/30',
  amber: 'bg-amber/10 text-amber border-amber/30',
  red: 'bg-red/10 text-red border-red/30',
  green: 'bg-green/10 text-green border-green/30',
};

export function IconChip({ children, tone = 'neutral', className }: Props) {
  return (
    <span
      className={clsx(
        'inline-flex items-center gap-1.5 px-2.5 py-1 border rounded-sm',
        'text-[11px] font-mono uppercase tracking-wider',
        toneStyles[tone],
        className,
      )}
    >
      {children}
    </span>
  );
}
