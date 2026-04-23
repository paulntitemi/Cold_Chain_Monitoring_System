import clsx from 'clsx';
import type { RiskLevel } from '@/types/shipment';

interface Props {
  level: RiskLevel;
  size?: 'sm' | 'md';
  pulse?: boolean;
}

const styles: Record<RiskLevel, string> = {
  safe: 'bg-green/15 text-green border-green/40',
  warning: 'bg-amber/15 text-amber border-amber/40',
  high: 'bg-red/15 text-red border-red/40',
  critical: 'bg-red/25 text-red border-red/60',
};

const label: Record<RiskLevel, string> = {
  safe: 'SAFE',
  warning: 'WARNING',
  high: 'HIGH',
  critical: 'CRITICAL',
};

export function RiskBadge({ level, size = 'md', pulse }: Props) {
  return (
    <span
      className={clsx(
        'inline-flex items-center gap-1.5 rounded-sm border font-display font-semibold tracking-wider uppercase',
        size === 'sm' ? 'px-1.5 py-0.5 text-[10px]' : 'px-2 py-0.5 text-xs',
        styles[level],
        pulse && level === 'critical' && 'animate-pulse-fast',
        pulse && level === 'high' && 'animate-pulse-red',
        pulse && level === 'warning' && 'animate-pulse-amber',
      )}
    >
      <span
        className={clsx(
          'h-1.5 w-1.5 rounded-full',
          level === 'safe' && 'bg-green',
          level === 'warning' && 'bg-amber',
          (level === 'high' || level === 'critical') && 'bg-red',
        )}
      />
      {label[level]}
    </span>
  );
}
