import { useMemo, useState } from 'react';
import { format } from 'date-fns';
import { Link } from 'react-router-dom';
import type { VaccineBatch, CustodyEventType } from '@/types/batch';
import { VVMBadge } from './VVMBadge';
import { TemperatureFullChart } from '@/components/charts/TemperatureFullChart';
import { useShipmentsStore } from '@/store/shipmentsStore';

interface Props {
  batch: VaccineBatch;
  onClose: () => void;
}

const tabs = [
  { id: 'overview', label: 'Overview' },
  { id: 'custody', label: 'Chain of Custody' },
  { id: 'temperature', label: 'Temperature' },
  { id: 'shipments', label: 'Linked Shipments' },
] as const;

type TabId = (typeof tabs)[number]['id'];

const custodyIcon: Record<CustodyEventType, string> = {
  dispatched: '🚚',
  received: '📥',
  excursion: '🌡️',
  alert: '⚠️',
  diverted: '↪',
  delivered: '📦',
};

const vvmExplain = `VVM (Vaccine Vial Monitor) is a heat-sensitive indicator on the vial.
Stage 1: Inner square lighter than outer — USE.
Stage 2: Inner square still lighter — USE FIRST.
Stage 3: Inner square same colour as outer — USE URGENTLY.
Stage 4: Inner square darker than outer — DISCARD.`;

export function BatchDetailModal({ batch, onClose }: Props) {
  const [tab, setTab] = useState<TabId>('overview');
  const shipments = useShipmentsStore((s) => s.shipments);

  const tempHistory = useMemo(() => {
    const inTransit = shipments.find((s) => s.id === batch.currentShipmentId);
    return inTransit?.temperatureHistory ?? [];
  }, [shipments, batch.currentShipmentId]);

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-6"
      onClick={onClose}
    >
      <div
        className="flex max-h-[90vh] w-full max-w-5xl flex-col rounded-sm border border-border bg-bg-primary shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <header className="flex items-start justify-between gap-3 border-b border-border px-6 py-4">
          <div>
            <div className="flex items-center gap-2">
              <VVMBadge stage={batch.vvmStatus} />
              <h2 className="font-mono text-sm text-teal">{batch.batchId}</h2>
            </div>
            <div className="mt-0.5 text-sm text-text-primary">
              {batch.vaccineType} · {batch.manufacturer}
            </div>
          </div>
          <button
            onClick={onClose}
            className="rounded-sm border border-border bg-bg-card px-2 py-1 text-text-secondary hover:text-text-primary"
          >
            ✕
          </button>
        </header>

        <nav className="flex border-b border-border bg-bg-secondary px-6">
          {tabs.map((t) => (
            <button
              key={t.id}
              onClick={() => setTab(t.id)}
              className={`px-4 py-2 text-xs font-semibold uppercase tracking-widest border-b-2 -mb-px ${
                tab === t.id
                  ? 'border-teal text-teal'
                  : 'border-transparent text-text-secondary hover:text-text-primary'
              }`}
            >
              {t.label}
            </button>
          ))}
        </nav>

        <div className="flex-1 overflow-y-auto px-6 py-5">
          {tab === 'overview' && (
            <div className="grid grid-cols-2 gap-6">
              <Panel title="Metadata">
                <Item label="Vaccine type" value={batch.vaccineType} />
                <Item label="Manufacturer" value={batch.manufacturer} />
                <Item
                  label="Manufactured"
                  value={format(new Date(batch.manufactureDate), 'dd MMM yyyy')}
                />
                <Item
                  label="Expires"
                  value={format(new Date(batch.expiryDate), 'dd MMM yyyy')}
                />
                <Item
                  label="Doses"
                  value={`${batch.dosesRemaining.toLocaleString()} / ${batch.doseCount.toLocaleString()}`}
                />
                <Item
                  label="Temp range"
                  value={`${batch.minSafeTemp}°C – ${batch.maxSafeTemp}°C`}
                />
              </Panel>

              <Panel title="VVM Status">
                <div className="flex items-center gap-3">
                  <VVMBadge stage={batch.vvmStatus} />
                  <span className="text-sm text-text-primary">
                    {
                      {
                        stage1: 'OK — no heat damage detected',
                        stage2: 'Use first — mild exposure',
                        stage3: 'Use urgently — significant exposure',
                        stage4: 'Discard — exceeded limits',
                      }[batch.vvmStatus]
                    }
                  </span>
                </div>
                <pre className="mt-3 whitespace-pre-wrap text-[11px] leading-relaxed text-text-secondary">
                  {vvmExplain}
                </pre>
              </Panel>

              <Panel title="Current location">
                <Item
                  label="Status"
                  value={batch.status.replace('_', ' ').replace(/\b\w/g, (c) => c.toUpperCase())}
                />
                <Item
                  label="Shipment"
                  value={batch.currentShipmentId ?? '—'}
                />
                <Item
                  label="Storage"
                  value={batch.storageLocation ?? '—'}
                />
              </Panel>

              <Panel title="Excursion summary">
                <Item
                  label="Cumulative time"
                  value={`${batch.totalExcursionMinutes} min`}
                />
                <Item
                  label="Excursion events"
                  value={batch.chainOfCustody.filter((e) => e.eventType === 'excursion').length}
                />
                <Item
                  label="Alerts"
                  value={batch.chainOfCustody.filter((e) => e.eventType === 'alert').length}
                />
              </Panel>
            </div>
          )}

          {tab === 'custody' && (
            <ol className="relative ml-3 border-l border-border pl-5 space-y-4">
              {batch.chainOfCustody.map((e) => (
                <li key={e.id} className="relative">
                  <span className="absolute -left-[30px] top-1 flex h-5 w-5 items-center justify-center rounded-full border border-border bg-bg-card text-[10px]">
                    {custodyIcon[e.eventType]}
                  </span>
                  <div className="flex items-center gap-2">
                    <span className="font-display text-xs font-semibold uppercase tracking-widest text-text-primary">
                      {e.eventType}
                    </span>
                    <span className="font-mono text-[11px] text-text-secondary">
                      {format(new Date(e.timestamp), 'dd MMM HH:mm')}
                    </span>
                  </div>
                  <div className="text-sm text-text-primary">{e.location}</div>
                  <div className="text-xs text-text-secondary">
                    Handled by {e.handledBy}
                    {typeof e.tempAtEvent === 'number' && ` · ${e.tempAtEvent.toFixed(1)}°C`}
                  </div>
                  {e.notes && <div className="text-xs text-text-secondary italic">{e.notes}</div>}
                </li>
              ))}
            </ol>
          )}

          {tab === 'temperature' && (
            <div>
              {tempHistory.length > 0 ? (
                <TemperatureFullChart
                  readings={tempHistory}
                  minSafe={batch.minSafeTemp}
                  maxSafe={batch.maxSafeTemp}
                  height={320}
                />
              ) : (
                <div className="py-12 text-center text-sm text-text-secondary">
                  No temperature history available — batch is not currently on an active shipment.
                </div>
              )}
            </div>
          )}

          {tab === 'shipments' && (
            <div className="space-y-2">
              {(batch.linkedShipmentIds ?? [batch.currentShipmentId].filter(Boolean) as string[])
                .filter(Boolean)
                .map((sid) => (
                  <Link
                    key={sid}
                    to={`/shipments/${sid}`}
                    className="flex items-center justify-between rounded-sm border border-border bg-bg-card px-3 py-2 hover:border-teal/50"
                  >
                    <span className="font-mono text-sm text-teal">{sid}</span>
                    <span className="text-xs text-text-secondary">Open →</span>
                  </Link>
                ))}
              {!batch.linkedShipmentIds?.length && !batch.currentShipmentId && (
                <div className="py-6 text-center text-sm text-text-secondary">
                  Batch has no shipment history yet.
                </div>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function Panel({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="rounded-sm border border-border bg-bg-card p-4">
      <h3 className="mb-2 font-display text-[11px] font-semibold uppercase tracking-widest text-text-secondary">
        {title}
      </h3>
      <div className="space-y-1.5">{children}</div>
    </div>
  );
}

function Item({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between text-sm">
      <span className="text-xs uppercase tracking-wider text-text-secondary">{label}</span>
      <span className="text-text-primary">{value}</span>
    </div>
  );
}
