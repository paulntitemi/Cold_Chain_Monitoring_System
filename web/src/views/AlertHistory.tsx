import { useMemo, useState } from 'react';
import clsx from 'clsx';
import { format, subDays } from 'date-fns';
import { Link } from 'react-router-dom';
import toast from 'react-hot-toast';
import { useQueryClient } from '@tanstack/react-query';
import { useAlertHistory } from '@/hooks/useAlerts';
import { useShipmentsStore } from '@/store/shipmentsStore';
import { RiskBadge } from '@/components/ui/RiskBadge';
import { api } from '@/lib/apiClient';
import type { AlertRiskLevel, AlertOutcome, RiderResponse } from '@/types/alert';

type LevelFilter = 'all' | AlertRiskLevel;
type ResponseFilter = 'all' | RiderResponse | 'unresolved';

export function AlertHistory() {
  const [from, setFrom] = useState(() => format(subDays(new Date(), 7), 'yyyy-MM-dd'));
  const [to, setTo] = useState(() => format(new Date(), 'yyyy-MM-dd'));
  const [level, setLevel] = useState<LevelFilter>('all');
  const [response, setResponse] = useState<ResponseFilter>('all');
  const [rider, setRider] = useState('');
  const [batchQuery, setBatchQuery] = useState('');
  const qc = useQueryClient();

  const { data, isLoading } = useAlertHistory();
  const shipments = useShipmentsStore((s) => s.shipments);

  const filtered = useMemo(() => {
    const src = data ?? [];
    const fromTs = new Date(from).getTime();
    const toTs = new Date(to).getTime() + 86_400_000;
    return src.filter((a) => {
      const ts = new Date(a.timestamp).getTime();
      if (ts < fromTs || ts > toTs) return false;
      if (level !== 'all' && a.riskLevel !== level) return false;
      if (response === 'unresolved' && a.status !== 'active') return false;
      if (
        response !== 'all' &&
        response !== 'unresolved' &&
        a.riderResponse !== response
      )
        return false;
      if (rider && !(a.riderName ?? '').toLowerCase().includes(rider.toLowerCase())) return false;
      if (batchQuery && !a.batchIds.some((b) => b.toLowerCase().includes(batchQuery.toLowerCase())))
        return false;
      return true;
    });
  }, [data, from, to, level, response, rider, batchQuery]);

  const riderOptions = useMemo(() => {
    const set = new Set<string>();
    (data ?? []).forEach((a) => a.riderName && set.add(a.riderName));
    shipments.forEach((s) => set.add(s.riderName));
    return Array.from(set).sort();
  }, [data, shipments]);

  const stats = useMemo(() => {
    const total = filtered.length;
    const responded = filtered.filter((a) => a.riderResponse).length;
    const rate = total ? Math.round((responded / total) * 100) : 0;
    const responseTimes = filtered
      .map((a) => a.riderResponseTime)
      .filter((v): v is number => typeof v === 'number');
    const avg = responseTimes.length
      ? Math.round(responseTimes.reduce((s, n) => s + n, 0) / responseTimes.length)
      : 0;
    const affectedBatches = new Set(filtered.flatMap((a) => a.batchIds)).size;
    const dosesAtRisk = filtered.reduce((s, a) => s + (a.dosesAtRisk ?? 0), 0);
    const dosesSaved = filtered
      .filter((a) => a.outcome === 'diverted' || a.outcome === 'delivered_safe')
      .reduce((s, a) => s + (a.dosesAtRisk ?? 0), 0);
    return { total, rate, avg, affectedBatches, dosesAtRisk, dosesSaved };
  }, [filtered]);

  const saveNote = async (id: string, notes: string) => {
    await api.patchAlert(id, { operatorNotes: notes });
    toast.success('Note saved');
    qc.invalidateQueries({ queryKey: ['alerts'] });
  };

  return (
    <div className="flex flex-1 flex-col min-h-0 p-5 gap-4 bg-bg-primary overflow-auto">
      <div className="flex flex-wrap items-end gap-3">
        <LabeledInput label="From">
          <input
            type="date"
            value={from}
            onChange={(e) => setFrom(e.target.value)}
            className={inputCls}
          />
        </LabeledInput>
        <LabeledInput label="To">
          <input type="date" value={to} onChange={(e) => setTo(e.target.value)} className={inputCls} />
        </LabeledInput>
        <LabeledInput label="Risk">
          <select value={level} onChange={(e) => setLevel(e.target.value as LevelFilter)} className={inputCls}>
            <option value="all">All</option>
            <option value="warning">Warning</option>
            <option value="high">High</option>
            <option value="critical">Critical</option>
          </select>
        </LabeledInput>
        <LabeledInput label="Response">
          <select value={response} onChange={(e) => setResponse(e.target.value as ResponseFilter)} className={inputCls}>
            <option value="all">All</option>
            <option value="accepted">Accepted</option>
            <option value="ignored">Ignored</option>
            <option value="escalated">Escalated</option>
            <option value="unresolved">Unresolved</option>
          </select>
        </LabeledInput>
        <LabeledInput label="Rider">
          <select value={rider} onChange={(e) => setRider(e.target.value)} className={inputCls}>
            <option value="">All riders</option>
            {riderOptions.map((r) => (
              <option key={r} value={r}>
                {r}
              </option>
            ))}
          </select>
        </LabeledInput>
        <LabeledInput label="Batch">
          <input
            value={batchQuery}
            onChange={(e) => setBatchQuery(e.target.value)}
            placeholder="batch id…"
            className={inputCls}
          />
        </LabeledInput>
      </div>

      <div className="grid grid-cols-6 gap-2">
        <Stat label="Total" value={stats.total} />
        <Stat label="Responded" value={`${stats.rate}%`} />
        <Stat label="Avg response" value={`${stats.avg}s`} />
        <Stat label="Batches" value={stats.affectedBatches} />
        <Stat label="Doses at risk" value={stats.dosesAtRisk.toLocaleString()} tone="red" />
        <Stat label="Doses saved" value={stats.dosesSaved.toLocaleString()} tone="green" />
      </div>

      {isLoading ? (
        <div className="flex-1 flex items-center justify-center text-text-secondary">
          Loading alert history…
        </div>
      ) : (
        <div className="flex-1 overflow-auto rounded-sm border border-border bg-bg-secondary">
          <table className="w-full border-collapse text-sm">
            <thead className="sticky top-0 z-10 bg-bg-secondary">
              <tr className="text-left">
                {['Triggered', 'Shipment', 'Batches', 'Risk', 'Temp', 'Score', 'Safe For', 'Response', 'Resolved', 'Outcome', 'Notes'].map(
                  (h) => (
                    <th
                      key={h}
                      className="border-b border-border px-2 py-2 text-[10px] font-semibold uppercase tracking-widest text-text-secondary"
                    >
                      {h}
                    </th>
                  ),
                )}
              </tr>
            </thead>
            <tbody>
              {filtered.map((a) => (
                <tr key={a.id} className="border-b border-border/60 hover:bg-bg-card/50">
                  <td className="px-2 py-2 font-mono text-[11px] text-text-primary whitespace-nowrap">
                    {format(new Date(a.timestamp), 'dd MMM HH:mm:ss')}
                  </td>
                  <td className="px-2 py-2">
                    <Link to={`/shipments/${a.shipmentId}`} className="font-mono text-xs text-teal hover:underline">
                      {a.shipmentId}
                    </Link>
                    <div className="text-[10px] text-text-secondary">{a.riderName ?? ''}</div>
                  </td>
                  <td className="px-2 py-2">
                    <div className="flex flex-wrap gap-1">
                      {a.batchIds.map((b) => (
                        <span key={b} className="rounded-sm border border-border bg-bg-card px-1 text-[10px] font-mono text-text-secondary">
                          {b}
                        </span>
                      ))}
                    </div>
                  </td>
                  <td className="px-2 py-2">
                    <RiskBadge level={a.riskLevel} size="sm" />
                  </td>
                  <td className="px-2 py-2 font-mono text-xs text-red">
                    {a.tempAtTrigger.toFixed(1)}°C
                  </td>
                  <td className="px-2 py-2 font-mono text-xs text-text-primary">
                    {Math.round(a.riskScore * 100)}%
                  </td>
                  <td className="px-2 py-2 font-mono text-xs text-text-secondary">
                    {a.remainingSafeMinutes}m
                  </td>
                  <td className="px-2 py-2 text-xs">
                    {a.riderResponse === 'accepted' && (
                      <span className="text-green">
                        Accepted
                        {a.riderResponseTime ? ` (${formatSec(a.riderResponseTime)})` : ''}
                      </span>
                    )}
                    {a.riderResponse === 'ignored' && <span className="text-red">Ignored</span>}
                    {a.riderResponse === 'escalated' && <span className="text-amber">Escalated by operator</span>}
                    {!a.riderResponse && <span className="text-text-secondary italic">No response</span>}
                  </td>
                  <td className="px-2 py-2 font-mono text-[11px] text-text-secondary whitespace-nowrap">
                    {a.resolvedAt ? format(new Date(a.resolvedAt), 'dd MMM HH:mm') : 'Unresolved'}
                  </td>
                  <td className="px-2 py-2 text-xs text-text-primary">
                    <OutcomeLabel outcome={a.outcome} />
                  </td>
                  <td className="px-2 py-2">
                    <input
                      defaultValue={a.operatorNotes ?? ''}
                      onBlur={(e) => {
                        if (e.target.value !== (a.operatorNotes ?? '')) {
                          saveNote(a.id, e.target.value);
                        }
                      }}
                      placeholder="Add note…"
                      className="w-48 rounded-sm border border-border bg-bg-card px-2 py-0.5 text-[11px] text-text-primary focus:border-teal focus:outline-none"
                    />
                  </td>
                </tr>
              ))}
              {filtered.length === 0 && (
                <tr>
                  <td colSpan={11} className="py-8 text-center text-sm text-text-secondary">
                    No alerts match these filters.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

function OutcomeLabel({ outcome }: { outcome?: AlertOutcome }) {
  switch (outcome) {
    case 'delivered_safe':
      return <span className="text-green">Delivered safe</span>;
    case 'diverted':
      return <span className="text-amber">Diverted</span>;
    case 'discarded':
      return <span className="text-red">Discarded</span>;
    case 'pending':
    default:
      return <span className="text-text-secondary">Pending</span>;
  }
}

function formatSec(sec: number): string {
  if (sec < 60) return `${sec}s`;
  return `${Math.floor(sec / 60)}m ${sec % 60}s`;
}

const inputCls =
  'rounded-sm border border-border bg-bg-card px-2 py-1 text-xs text-text-primary focus:border-teal focus:outline-none';

function LabeledInput({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="flex flex-col gap-1">
      <span className="text-[10px] uppercase tracking-widest text-text-secondary">{label}</span>
      {children}
    </label>
  );
}

function Stat({
  label,
  value,
  tone,
}: {
  label: string;
  value: React.ReactNode;
  tone?: 'red' | 'green';
}) {
  return (
    <div className="rounded-sm border border-border bg-bg-card px-3 py-2">
      <div className="text-[10px] uppercase tracking-widest text-text-secondary">{label}</div>
      <div
        className={clsx(
          'font-display text-xl font-semibold',
          tone === 'red' && 'text-red',
          tone === 'green' && 'text-green',
          !tone && 'text-text-primary',
        )}
      >
        {value}
      </div>
    </div>
  );
}
