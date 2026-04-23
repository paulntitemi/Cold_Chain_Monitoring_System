import clsx from 'clsx';
import { formatDistanceToNow } from 'date-fns';
import type { Shipment } from '@/types/shipment';
import type { Alert } from '@/types/alert';
import { RiskBadge } from '@/components/ui/RiskBadge';
import { CountdownTimer, ExcursionTimer } from '@/components/ui/CountdownTimer';
import { TemperatureSparkline } from '@/components/charts/TemperatureSparkline';

interface Props {
  shipment: Shipment;
  alert?: Alert;
  selected?: boolean;
  onSelect: () => void;
  onCall: () => void;
  onEscalate: () => void;
}

function tempColor(temp: number, min: number, max: number) {
  if (temp > max + 2 || temp < min - 2) return 'text-red';
  if (temp > max || temp < min) return 'text-amber';
  return 'text-green';
}

function riskColor(score: number) {
  if (score >= 0.8) return 'text-red';
  if (score >= 0.5) return 'text-red';
  if (score >= 0.3) return 'text-amber';
  return 'text-green';
}

export function ShipmentRow({ shipment, alert, selected, onSelect, onCall, onEscalate }: Props) {
  const rowTint =
    shipment.riskLevel === 'critical'
      ? 'bg-red-row border-l-[3px] border-l-red'
      : shipment.riskLevel === 'high'
      ? 'border-l-[3px] border-l-red'
      : shipment.riskLevel === 'warning'
      ? 'border-l-[3px] border-l-amber'
      : 'border-l-[3px] border-l-transparent';

  const alertCell = (() => {
    if (!alert) return <span className="text-text-dim">No alert</span>;
    if (alert.riderResponse === 'accepted') {
      return (
        <span className="text-green">
          Rider accepted{' '}
          {alert.riderResponseTime ? `${alert.riderResponseTime}s` : ''} ago
        </span>
      );
    }
    if (alert.riderResponse === 'ignored') {
      return <span className="text-red">IGNORED</span>;
    }
    return <span className="text-amber animate-pulse">AWAITING RESPONSE</span>;
  })();

  return (
    <tr
      onClick={onSelect}
      className={clsx(
        'cursor-pointer border-b border-border/60 transition-colors hover:bg-bg-card/50',
        rowTint,
        selected && 'bg-bg-card',
      )}
    >
      <td className="py-2 pl-3 pr-2">
        <RiskBadge level={shipment.riskLevel} pulse />
      </td>
      <td className="px-2 py-2 font-mono text-xs text-teal">{shipment.id}</td>
      <td className="px-2 py-2">
        <div className="flex items-center gap-2">
          <span>{shipment.riderName}</span>
          <a
            href={`tel:${shipment.riderPhone}`}
            onClick={(e) => e.stopPropagation()}
            className="text-text-secondary hover:text-teal"
            title={shipment.riderPhone}
          >
            ☎
          </a>
        </div>
      </td>
      <td className="px-2 py-2 font-mono text-[11px] text-text-secondary">
        <div className="flex items-center gap-1.5">
          <span>{shipment.batchIds[0]}</span>
          {shipment.batchIds.length > 1 && (
            <span className="rounded-sm bg-bg-secondary border border-border px-1 text-[10px] text-text-secondary">
              +{shipment.batchIds.length - 1}
            </span>
          )}
        </div>
      </td>
      <td className={clsx('px-2 py-2 font-mono font-semibold', tempColor(shipment.currentTemp, shipment.minSafeTemp, shipment.maxSafeTemp))}>
        {shipment.currentTemp.toFixed(1)}°C
      </td>
      <td className={clsx('px-2 py-2 font-mono', riskColor(shipment.riskScore))}>
        {Math.round(shipment.riskScore * 100)}%
      </td>
      <td className="px-2 py-2 text-xs">
        <CountdownTimer
          minutesRemaining={shipment.remainingSafeMinutes}
          anchor={shipment.lastUpdated}
        />
      </td>
      <td className="px-2 py-2 text-xs">
        <ExcursionTimer secondsOutside={shipment.secondsOutsideRange} />
      </td>
      <td className="px-2 py-2 text-[11px] text-text-secondary whitespace-nowrap">
        <div className="truncate max-w-[180px]">
          {shipment.origin} → {shipment.destination}
        </div>
        <div className="text-text-dim">
          ETA {formatDistanceToNow(new Date(shipment.estimatedArrival), { addSuffix: true })}
        </div>
      </td>
      <td className="px-2 py-2 text-[11px]">{alertCell}</td>
      <td className="px-2 py-2">
        <TemperatureSparkline
          readings={shipment.temperatureHistory}
          minSafe={shipment.minSafeTemp}
          maxSafe={shipment.maxSafeTemp}
        />
      </td>
      <td className="px-3 py-2">
        <div className="flex items-center gap-1" onClick={(e) => e.stopPropagation()}>
          <button
            onClick={onSelect}
            className="rounded-sm border border-border bg-bg-card px-1.5 py-1 text-[11px] text-text-secondary hover:text-teal"
            title="Details"
          >
            📋
          </button>
          <button
            onClick={onCall}
            className="rounded-sm border border-teal/40 bg-teal/10 px-1.5 py-1 text-[11px] text-teal"
            title="Call rider"
          >
            📞
          </button>
          <button
            onClick={onEscalate}
            className="rounded-sm border border-red/40 bg-red/10 px-1.5 py-1 text-[11px] text-red"
            title="Escalate"
          >
            ⚠
          </button>
        </div>
      </td>
    </tr>
  );
}
