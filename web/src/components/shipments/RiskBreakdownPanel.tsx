import { clsx } from 'clsx';
import type { Shipment } from '@/types/shipment';

interface Props {
  shipment: Shipment;
}

interface Sub {
  label: string;
  value: number | undefined;
  hint: string;
}

function tone(v: number): string {
  if (v >= 70) return 'bg-red';
  if (v >= 40) return 'bg-amber';
  if (v >= 20) return 'bg-amber/70';
  return 'bg-green';
}

/**
 * Edge-explainability panel. The ESP32 firmware publishes a 0-100 score per
 * risk dimension; we render those four sub-scores as horizontal bars so the
 * operator can see at a glance *which* factor is driving a critical state
 * (temperature spike vs. excursion duration vs. shock vs. GPS dropout).
 *
 * Renders nothing if the shipment is mock-only — the sub-scores are
 * undefined for shipments not coming from a real ESP32 carrier.
 */
export function RiskBreakdownPanel({ shipment }: Props) {
  const subs: Sub[] = [
    {
      label: 'Temperature',
      value: shipment.temperatureRisk,
      hint: 'Distance of current temp from the safe band',
    },
    {
      label: 'Duration',
      value: shipment.durationRisk,
      hint: 'How long temp has been out of range',
    },
    {
      label: 'Vibration',
      value: shipment.vibrationRisk,
      hint: 'Recent shock events on the carrier',
    },
    {
      label: 'GPS',
      value: shipment.gpsRisk,
      hint: 'Confidence of the location fix',
    },
  ];

  // If none of the sub-scores are populated, this isn't a live-edge shipment.
  // Render nothing — the existing risk pill at the top already conveys enough.
  if (subs.every((s) => s.value === undefined)) return null;

  const profile = shipment.thresholdProfile?.replace(/_/g, ' ');
  const total = Math.round(shipment.riskScore * 100);

  return (
    <div className="rounded-sm border border-border bg-bg-card p-3 space-y-3">
      <div className="flex items-baseline justify-between">
        <div>
          <div className="text-[10px] uppercase tracking-widest text-text-secondary">
            Edge risk breakdown
          </div>
          {profile && (
            <div className="font-mono text-[11px] text-text-secondary mt-0.5">
              profile · {profile}
            </div>
          )}
        </div>
        <div className="font-display text-2xl text-text-primary tabular-nums">
          {total}
          <span className="text-xs text-text-secondary">/100</span>
        </div>
      </div>
      {shipment.temperatureSensorOk === false && (
        <div className="rounded-sm border border-amber/50 bg-amber/10 px-2.5 py-1.5 text-amber text-[11px] font-mono">
          ⚠ Temperature probe offline — risk driven by vibration / duration / GPS only
        </div>
      )}
      <ul className="space-y-2">
        {subs.map((s) => {
          const v = s.value ?? 0;
          const has = s.value !== undefined;
          return (
            <li key={s.label}>
              <div className="flex items-center justify-between text-xs">
                <span className="text-text-primary">{s.label}</span>
                <span className={clsx('font-mono tabular-nums', has ? 'text-text-primary' : 'text-text-secondary')}>
                  {has ? v : '—'}
                </span>
              </div>
              <div className="h-1.5 mt-1 bg-bg-secondary rounded-sm overflow-hidden">
                <div
                  className={clsx('h-full transition-all duration-500', has ? tone(v) : 'bg-text-dim')}
                  style={{ width: `${Math.min(100, v)}%` }}
                />
              </div>
              <div className="text-[10px] text-text-secondary mt-0.5">{s.hint}</div>
            </li>
          );
        })}
      </ul>
      {(typeof shipment.vibrationCount10s === 'number' || typeof shipment.satellites === 'number') && (
        <div className="grid grid-cols-2 gap-2 pt-1 border-t border-border/40">
          {typeof shipment.vibrationCount10s === 'number' && (
            <div className="text-xs">
              <span className="text-text-secondary">Vib events / 10s · </span>
              <span className="font-mono text-text-primary">{shipment.vibrationCount10s}</span>
            </div>
          )}
          {typeof shipment.satellites === 'number' && (
            <div className="text-xs">
              <span className="text-text-secondary">Satellites · </span>
              <span className="font-mono text-text-primary">{shipment.satellites}</span>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
