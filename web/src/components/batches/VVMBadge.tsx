import clsx from 'clsx';
import type { VVMStage } from '@/types/batch';

const meta: Record<VVMStage, { label: string; sub: string; cls: string }> = {
  stage1: { label: 'STAGE 1', sub: 'OK', cls: 'border-text-secondary/50 bg-text-secondary/5 text-text-primary' },
  stage2: { label: 'STAGE 2', sub: 'Use first', cls: 'border-yellow-400/50 bg-yellow-400/10 text-yellow-300' },
  stage3: { label: 'STAGE 3', sub: 'Use urgently', cls: 'border-amber/50 bg-amber/10 text-amber' },
  stage4: { label: 'STAGE 4', sub: 'Discard', cls: 'border-red/60 bg-red/15 text-red' },
};

interface Props {
  stage: VVMStage;
  compact?: boolean;
}

export function VVMBadge({ stage, compact }: Props) {
  const m = meta[stage];
  return (
    <span
      className={clsx(
        'inline-flex flex-col items-start rounded-sm border px-2 py-0.5 leading-tight',
        m.cls,
      )}
    >
      <span className="font-display text-[10px] font-bold tracking-wider">{m.label}</span>
      {!compact && <span className="text-[9px] uppercase tracking-widest opacity-80">{m.sub}</span>}
    </span>
  );
}
