import clsx from 'clsx';
import { useEffect, useState } from 'react';
import { formatDistanceToNow } from 'date-fns';
import type { Alert } from '@/types/alert';
import { AlertActionButtons } from './AlertActionButtons';
import { useAlertsStore } from '@/store/alertsStore';
import { useUiStore } from '@/store/uiStore';
import { useShipmentsStore } from '@/store/shipmentsStore';

interface Props {
  alert: Alert;
}

const AUTO_ESC_MS = 2 * 60 * 1000;

export function AlertFeedItem({ alert }: Props) {
  const [, tick] = useState(0);
  const acknowledged = useAlertsStore((s) =>
    s.acknowledgedAutoEscalations.has(alert.id),
  );
  const ack = useAlertsStore((s) => s.acknowledgeAutoEscalation);
  const openDetail = useUiStore((s) => s.openDetailPanel);
  const rider = useShipmentsStore((s) => s.getById(alert.shipmentId));

  useEffect(() => {
    const id = window.setInterval(() => tick((x) => x + 1), 1000);
    return () => window.clearInterval(id);
  }, []);

  const triggered = new Date(alert.timestamp).getTime();
  const sinceMs = Math.max(0, Date.now() - triggered);
  const autoEscalateAtMs = Math.max(0, AUTO_ESC_MS - sinceMs);
  const autoEscalated =
    (alert.riskLevel === 'high' || alert.riskLevel === 'critical') &&
    !alert.riderResponse &&
    sinceMs > AUTO_ESC_MS;

  const borderColor =
    alert.riskLevel === 'critical' ? 'border-l-red'
    : alert.riskLevel === 'high' ? 'border-l-red'
    : 'border-l-amber';

  const pulse =
    alert.riskLevel === 'critical' ? 'animate-pulse-fast'
    : autoEscalated ? 'animate-pulse-fast'
    : '';

  return (
    <div
      className={clsx(
        'group relative border-l-2 bg-bg-card/60 hover:bg-bg-card border border-border px-3 py-3 cursor-pointer animate-slide-top',
        borderColor,
        autoEscalated && !acknowledged && 'bg-red/10',
        pulse,
      )}
      onClick={() => openDetail(alert.shipmentId)}
    >
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <span
              className={clsx(
                'font-display text-xs font-bold uppercase tracking-wider',
                alert.riskLevel === 'critical' || alert.riskLevel === 'high'
                  ? 'text-red'
                  : 'text-amber',
              )}
            >
              {alert.riskLevel}
            </span>
            <span className="font-mono text-[11px] text-text-secondary">
              {formatDistanceToNow(triggered, { addSuffix: true })}
            </span>
          </div>
          <div className="mt-0.5 font-mono text-xs text-teal truncate">{alert.shipmentId}</div>
          <div className="text-[11px] text-text-secondary truncate">
            {alert.riderName ?? rider?.riderName ?? '—'}
          </div>
        </div>
        <div className="text-right font-mono text-[11px] text-text-secondary whitespace-nowrap">
          <div className="text-red font-semibold">{alert.tempAtTrigger.toFixed(1)}°C</div>
          <div>risk {Math.round(alert.riskScore * 100)}%</div>
          <div>safe {alert.remainingSafeMinutes}m</div>
        </div>
      </div>

      <div className="mt-2 flex flex-wrap gap-1">
        {alert.batchIds.map((b) => (
          <span
            key={b}
            className="rounded-sm border border-border bg-bg-secondary px-1.5 py-0.5 text-[10px] font-mono text-text-secondary"
          >
            {b}
          </span>
        ))}
      </div>

      <div className="mt-2 text-[11px]">
        {alert.riderResponse === 'accepted' && (
          <div className="text-green">
            ✓ Rider en route to {alert.recommendedCentre?.name ?? 'centre'}
          </div>
        )}
        {alert.riderResponse === 'ignored' && (
          <div className="text-red">✗ Rider ignored — escalate?</div>
        )}
        {!alert.riderResponse && (
          <div
            className={clsx(
              'flex items-center justify-between gap-2',
              autoEscalated ? 'text-red font-semibold' : 'text-amber',
            )}
          >
            <span className={clsx(!autoEscalated && 'animate-pulse')}>
              {autoEscalated ? 'AUTO-ESCALATED — no response' : 'AWAITING RESPONSE'}
            </span>
            <span className="font-mono text-[10px] text-text-secondary">
              {autoEscalated
                ? 'action required'
                : `esc in ${Math.floor(autoEscalateAtMs / 1000)}s`}
            </span>
          </div>
        )}
      </div>

      {autoEscalated && !acknowledged && (
        <div className="mt-2 flex gap-1.5" onClick={(e) => e.stopPropagation()}>
          <button
            className="flex-1 rounded-sm border border-teal/50 bg-teal/10 text-teal text-[11px] py-1"
            onClick={() => ack(alert.id)}
          >
            Calling now
          </button>
          <button
            className="flex-1 rounded-sm border border-border-bright text-text-secondary text-[11px] py-1"
            onClick={() => ack(alert.id)}
          >
            Acknowledged
          </button>
        </div>
      )}

      <div className="mt-2" onClick={(e) => e.stopPropagation()}>
        <AlertActionButtons alert={alert} riderPhone={rider?.riderPhone} compact />
      </div>
    </div>
  );
}
