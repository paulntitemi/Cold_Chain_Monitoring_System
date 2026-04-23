import { clsx } from 'clsx';
import type { RiskLevel } from '@/types/shipment';

interface Props {
  score: number;
  level: RiskLevel;
  temperature: number;
  unit?: string;
}

const levelStyles: Record<RiskLevel, { stroke: string; text: string; bg: string; label: string }> = {
  safe: { stroke: '#10B981', text: 'text-green', bg: 'bg-green/10', label: 'SAFE' },
  warning: { stroke: '#F59E0B', text: 'text-amber', bg: 'bg-amber/10', label: 'MONITOR' },
  high: { stroke: '#EF4444', text: 'text-red', bg: 'bg-red/10', label: 'HIGH' },
  critical: { stroke: '#EF4444', text: 'text-red', bg: 'bg-red/10', label: 'CRITICAL' },
};

export function RiskGauge({ score, level, temperature, unit = '°C' }: Props) {
  const pct = Math.max(0, Math.min(1, score));
  const radius = 95;
  const circumference = Math.PI * radius; // half circle
  const dash = circumference * pct;
  const style = levelStyles[level];

  return (
    <div className={clsx('relative flex flex-col items-center pt-4', style.bg)}>
      <svg width="240" height="140" viewBox="0 0 240 140">
        <path
          d={`M 25 120 A ${radius} ${radius} 0 0 1 215 120`}
          fill="none"
          stroke="#1E2D45"
          strokeWidth="14"
          strokeLinecap="round"
        />
        <path
          d={`M 25 120 A ${radius} ${radius} 0 0 1 215 120`}
          fill="none"
          stroke={style.stroke}
          strokeWidth="14"
          strokeLinecap="round"
          strokeDasharray={`${dash} ${circumference}`}
          style={{ transition: 'stroke-dasharray 600ms ease-out, stroke 300ms ease-out' }}
        />
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-end pb-3">
        <div className={clsx('font-display font-bold leading-none', style.text)} style={{ fontSize: 72 }}>
          {temperature.toFixed(1)}
        </div>
        <div className={clsx('font-mono text-xs uppercase tracking-[0.2em] mt-1', style.text)}>
          {unit} · {style.label} · {Math.round(pct * 100)}%
        </div>
      </div>
    </div>
  );
}
