import { differenceInDays } from 'date-fns';
import clsx from 'clsx';
import type { VaccineBatch } from '@/types/batch';
import { VVMBadge } from './VVMBadge';
import { safeDate, safeDistance, safeFormat } from '@/lib/safeDate';

interface Props {
  batch: VaccineBatch;
  onOpen: () => void;
  onEdit: () => void;
  onDiscard: () => void;
}

export function BatchRow({ batch, onOpen, onEdit, onDiscard }: Props) {
  const depletion = batch.doseCount > 0 ? batch.dosesRemaining / batch.doseCount : 0;
  const expiry = safeDate(batch.expiryDate);
  const daysLeft = expiry ? differenceInDays(expiry, new Date()) : null;
  const expiryTone =
    daysLeft === null
      ? 'text-text-secondary'
      : daysLeft < 30
      ? 'text-red'
      : daysLeft < 90
      ? 'text-amber'
      : 'text-text-primary';

  const statusLabel: Record<VaccineBatch['status'], { label: string; cls: string }> = {
    in_transit: { label: 'In Transit', cls: 'text-teal' },
    in_storage: { label: 'In Storage', cls: 'text-text-primary' },
    delivered: { label: 'Delivered', cls: 'text-green' },
    discarded: { label: 'Discarded', cls: 'text-red' },
  };
  const statusInfo = statusLabel[batch.status] ?? { label: batch.status ?? '—', cls: 'text-text-secondary' };
  const events = batch.chainOfCustody ?? [];
  const lastEventTs = events.length > 0 ? events[events.length - 1].timestamp : batch.manufactureDate;

  return (
    <tr
      onClick={onOpen}
      className="cursor-pointer border-b border-border/60 hover:bg-bg-card/50 transition-colors"
    >
      <td className="py-2 pl-3 pr-2">
        <VVMBadge stage={batch.vvmStatus} />
      </td>
      <td className="px-2 py-2">
        <div className="font-mono text-xs text-teal select-all">{batch.batchId}</div>
      </td>
      <td className="px-2 py-2">
        <div className="text-sm text-text-primary">{batch.vaccineType}</div>
        <div className="text-[11px] text-text-secondary">{batch.manufacturer}</div>
      </td>
      <td className="px-2 py-2 min-w-[140px]">
        <div className="flex items-center justify-between text-[11px] text-text-secondary font-mono">
          <span>
            {batch.dosesRemaining.toLocaleString()} / {batch.doseCount.toLocaleString()}
          </span>
          <span>{Math.round(depletion * 100)}%</span>
        </div>
        <div className="mt-1 h-1 w-full rounded-sm bg-bg-secondary overflow-hidden">
          <div
            className={clsx(
              'h-full',
              depletion > 0.5 ? 'bg-teal' : depletion > 0.2 ? 'bg-amber' : 'bg-red',
            )}
            style={{ width: `${Math.max(0, Math.round(depletion * 100))}%` }}
          />
        </div>
      </td>
      <td className="px-2 py-2 font-mono text-xs text-text-secondary">
        {batch.minSafeTemp}°C – {batch.maxSafeTemp}°C
      </td>
      <td className={clsx('px-2 py-2 font-mono text-xs', expiryTone)}>
        {safeFormat(batch.expiryDate, 'dd MMM yyyy')}
        <div className="text-[10px] text-text-secondary">
          {daysLeft === null
            ? 'no expiry set'
            : daysLeft > 0
            ? `${daysLeft}d left`
            : `expired ${Math.abs(daysLeft)}d`}
        </div>
      </td>
      <td className="px-2 py-2 font-mono text-xs">
        <span className={clsx(batch.totalExcursionMinutes > 30 ? 'text-red' : batch.totalExcursionMinutes > 0 ? 'text-amber' : 'text-text-secondary')}>
          {batch.totalExcursionMinutes}m
        </span>
      </td>
      <td className={clsx('px-2 py-2 text-xs', statusInfo.cls)}>
        <div>{statusInfo.label}</div>
        <div className="text-[10px] text-text-secondary font-mono">
          {batch.currentShipmentId ?? batch.storageLocation ?? '—'}
        </div>
      </td>
      <td className="px-2 py-2 text-[11px] text-text-secondary">
        {safeDistance(lastEventTs)}
      </td>
      <td className="px-3 py-2">
        <div className="flex items-center gap-1" onClick={(e) => e.stopPropagation()}>
          <button
            onClick={onOpen}
            className="rounded-sm border border-border bg-bg-card px-1.5 py-1 text-[11px] text-text-secondary hover:text-teal"
            title="Detail"
          >
            📋
          </button>
          <button
            onClick={onEdit}
            className="rounded-sm border border-border bg-bg-card px-1.5 py-1 text-[11px] text-text-secondary hover:text-text-primary"
            title="Edit"
          >
            📝
          </button>
          <button
            onClick={onDiscard}
            className="rounded-sm border border-red/40 bg-red/10 px-1.5 py-1 text-[11px] text-red"
            title="Mark discarded"
          >
            🗑
          </button>
        </div>
      </td>
    </tr>
  );
}
