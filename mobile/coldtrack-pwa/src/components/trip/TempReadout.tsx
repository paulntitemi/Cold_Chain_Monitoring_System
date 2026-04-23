import { clsx } from 'clsx';
import type { RiskLevel } from '@/types/shipment';

interface Props {
  temperature: number;
  level: RiskLevel;
  size?: 'sm' | 'md' | 'lg';
}

const levelColour: Record<RiskLevel, string> = {
  safe: 'text-green',
  warning: 'text-amber',
  high: 'text-red',
  critical: 'text-red',
};

const sizeStyles = {
  sm: 'text-3xl',
  md: 'text-5xl',
  lg: 'text-[72px] leading-none',
};

export function TempReadout({ temperature, level, size = 'lg' }: Props) {
  return (
    <span className={clsx('font-display font-bold tabular-nums', sizeStyles[size], levelColour[level])}>
      {temperature.toFixed(1)}
      <span className="text-xs font-mono align-top ml-1">°C</span>
    </span>
  );
}
