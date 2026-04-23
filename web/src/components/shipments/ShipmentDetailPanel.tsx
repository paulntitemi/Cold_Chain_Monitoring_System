import { useEffect, useMemo, useState } from 'react';
import { format, formatDistanceToNow } from 'date-fns';
import { useNavigate } from 'react-router-dom';
import toast from 'react-hot-toast';
import { useQueryClient } from '@tanstack/react-query';
import { useUiStore } from '@/store/uiStore';
import { useShipmentsStore } from '@/store/shipmentsStore';
import { useAlertsStore } from '@/store/alertsStore';
import { useShipmentDetail } from '@/hooks/useShipmentDetail';
import { RiskBadge } from '@/components/ui/RiskBadge';
import { CountdownTimer, ExcursionTimer } from '@/components/ui/CountdownTimer';
import { TemperatureFullChart } from '@/components/charts/TemperatureFullChart';
import { FleetMapInset } from '@/components/map/FleetMap';
import { AlertActionButtons } from '@/components/alerts/AlertActionButtons';
import { api } from '@/lib/apiClient';
import type { IncidentEventType } from '@/types/shipment';

const eventIcon: Record<IncidentEventType, string> = {
  excursionStart: '🌡️',
  excursionEnd: '✅',
  alertTriggered: '⚠️',
  riderAccepted: '✓',
  riderIgnored: '✗',
  diverted: '↪',
  delivered: '📦',
  aborted: '⛔',
  operatorNote: '📝',
};

export function ShipmentDetailPanel() {
  const open = useUiStore((s) => s.detailPanelOpen);
  const selected = useUiStore((s) => s.selectedShipmentId);
  const close = useUiStore((s) => s.closeDetailPanel);
  const storeShipment = useShipmentsStore((s) => (selected ? s.getById(selected) : undefined));
  const alerts = useAlertsStore((s) => s.alerts);
  const { data: fresh } = useShipmentDetail(open ? selected : null);
  const shipment = fresh ?? storeShipment;
  const qc = useQueryClient();
  const navigate = useNavigate();
  const [note, setNote] = useState('');

  const activeAlert = useMemo(
    () =>
      alerts.find((a) => a.shipmentId === selected && (a.status === 'active' || a.status === 'escalated')),
    [alerts, selected],
  );

  useEffect(() => {
    if (!open) setNote('');
  }, [open, selected]);

  if (!open || !shipment) return null;

  const divertTo = activeAlert?.recommendedCentre?.location;

  const submitNote = async () => {
    if (!note.trim()) return;
    await api.logIncident({
      shipmentId: shipment.id,
      eventType: 'operatorNote',
      detail: note.trim(),
      operatorName: 'Control Desk',
    });
    toast.success('Note added to timeline');
    setNote('');
    qc.invalidateQueries({ queryKey: ['shipment', shipment.id] });
  };

  return (
    <div
      className="fixed inset-y-0 right-[360px] z-30 flex w-[520px] flex-col border-l border-border bg-bg-primary shadow-2xl animate-slide-right"
      role="dialog"
      aria-label="Shipment detail"
    >
      <header className="flex items-start justify-between gap-3 border-b border-border px-5 py-4">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <RiskBadge level={shipment.riskLevel} pulse />
            <span className="font-mono text-sm text-teal">{shipment.id}</span>
          </div>
          <div className="mt-1 text-sm text-text-primary">
            {shipment.riderName}{' '}
            <a href={`tel:${shipment.riderPhone}`} className="ml-1 text-teal">
              {shipment.riderPhone}
            </a>
          </div>
          <div className="text-xs text-text-secondary">
            {shipment.origin} → {shipment.destination}
          </div>
          <div className="text-[11px] font-mono text-text-dim">
            Started {format(new Date(shipment.startTime), 'HH:mm')} · ETA{' '}
            {format(new Date(shipment.estimatedArrival), 'HH:mm')}
          </div>
        </div>
        <div className="flex items-center gap-1">
          <button
            onClick={() => navigate(`/shipments/${shipment.id}`)}
            className="rounded-sm border border-border bg-bg-card px-2 py-1 text-[11px] text-text-secondary hover:text-teal"
            title="Open full view"
          >
            ↗
          </button>
          <button
            onClick={close}
            className="rounded-sm border border-border bg-bg-card px-2 py-1 text-text-secondary hover:text-text-primary"
            title="Close"
          >
            ✕
          </button>
        </div>
      </header>

      <div className="flex-1 overflow-y-auto px-5 py-4 space-y-5">
        <section className="grid grid-cols-4 gap-2">
          <Metric label="Temp" value={`${shipment.currentTemp.toFixed(1)}°C`} tone={shipment.riskLevel} />
          <Metric label="Risk" value={`${Math.round(shipment.riskScore * 100)}%`} tone={shipment.riskLevel} />
          <Metric
            label="Safe for"
            value={
              <CountdownTimer
                minutesRemaining={shipment.remainingSafeMinutes}
                anchor={shipment.lastUpdated}
              />
            }
          />
          <Metric
            label="Excursion"
            value={<ExcursionTimer secondsOutside={shipment.secondsOutsideRange} />}
          />
        </section>

        <section>
          <SectionTitle>Temperature history</SectionTitle>
          <TemperatureFullChart
            readings={shipment.temperatureHistory}
            minSafe={shipment.minSafeTemp}
            maxSafe={shipment.maxSafeTemp}
            alertMarkers={
              activeAlert
                ? [{ timestamp: activeAlert.timestamp, label: 'alert' }]
                : undefined
            }
            height={200}
          />
        </section>

        <section>
          <SectionTitle>Batch manifest</SectionTitle>
          <div className="rounded-sm border border-border bg-bg-card">
            <table className="w-full text-xs">
              <thead className="text-[10px] uppercase text-text-secondary">
                <tr>
                  <th className="px-2 py-1.5 text-left">Batch</th>
                  <th className="px-2 py-1.5 text-left">Range</th>
                  <th className="px-2 py-1.5 text-left">Status</th>
                </tr>
              </thead>
              <tbody>
                {shipment.batchIds.map((b) => (
                  <tr key={b} className="border-t border-border/60">
                    <td className="px-2 py-1.5 font-mono text-teal">{b}</td>
                    <td className="px-2 py-1.5 text-text-secondary">
                      {shipment.minSafeTemp.toFixed(1)}°C – {shipment.maxSafeTemp.toFixed(1)}°C
                    </td>
                    <td className="px-2 py-1.5 text-text-secondary">In transit</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>

        {activeAlert && (
          <section>
            <SectionTitle>Active alert</SectionTitle>
            <div className="rounded-sm border border-red/40 bg-red/10 p-3">
              <div className="flex items-center justify-between text-xs">
                <span className="font-mono text-red">
                  {format(new Date(activeAlert.timestamp), 'HH:mm:ss')}
                </span>
                <RiskBadge level={activeAlert.riskLevel} pulse />
              </div>
              <div className="mt-1 text-sm text-text-primary">
                Risk {Math.round(activeAlert.riskScore * 100)}% at{' '}
                {activeAlert.tempAtTrigger.toFixed(1)}°C
              </div>
              {activeAlert.recommendedCentre && (
                <div className="mt-2 rounded-sm border border-border bg-bg-card p-2 text-xs">
                  <div className="text-[10px] uppercase tracking-widest text-text-secondary">
                    Recommended divert
                  </div>
                  <div className="font-display text-sm text-teal">
                    {activeAlert.recommendedCentre.name}
                  </div>
                  <div className="text-text-secondary">
                    {activeAlert.recommendedCentre.distanceKm?.toFixed(1)} km ·{' '}
                    {activeAlert.recommendedCentre.estimatedMinutes} min
                  </div>
                </div>
              )}
              <div className="mt-2 text-xs">
                {activeAlert.riderResponse === 'accepted' ? (
                  <span className="text-green">
                    Rider accepted — navigating to{' '}
                    {activeAlert.recommendedCentre?.name ?? 'centre'}
                  </span>
                ) : activeAlert.riderResponse === 'ignored' ? (
                  <span className="text-red">Rider ignored — re-alert in 36s</span>
                ) : (
                  <span className="text-amber animate-pulse">
                    AWAITING RIDER RESPONSE —{' '}
                    {formatDistanceToNow(new Date(activeAlert.timestamp), { addSuffix: false })}
                  </span>
                )}
              </div>
              <div className="mt-3">
                <AlertActionButtons alert={activeAlert} riderPhone={shipment.riderPhone} />
              </div>
            </div>
          </section>
        )}

        <section>
          <SectionTitle>Incident log</SectionTitle>
          <ol className="relative ml-3 border-l border-border pl-4 space-y-3">
            {(shipment.incidentLog ?? []).map((e) => (
              <li key={e.id} className="relative">
                <span className="absolute -left-[22px] top-1 flex h-3 w-3 items-center justify-center rounded-full bg-teal ring-2 ring-bg-primary" />
                <div className="text-[10px] font-mono text-text-dim">
                  {format(new Date(e.timestamp), 'HH:mm:ss')}
                </div>
                <div className="text-sm text-text-primary">
                  {eventIcon[e.eventType]} {e.detail}
                </div>
                {e.operatorName && (
                  <div className="text-[11px] text-text-secondary">— {e.operatorName}</div>
                )}
              </li>
            ))}
            {(shipment.incidentLog ?? []).length === 0 && (
              <li className="text-xs text-text-secondary">No events logged yet.</li>
            )}
          </ol>
          <div className="mt-3 flex gap-2">
            <input
              type="text"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="Add operator note…"
              className="flex-1 rounded-sm border border-border bg-bg-card px-2 py-1.5 text-xs text-text-primary placeholder:text-text-dim focus:border-teal focus:outline-none"
              onKeyDown={(e) => {
                if (e.key === 'Enter') submitNote();
              }}
            />
            <button
              onClick={submitNote}
              className="rounded-sm border border-teal/40 bg-teal/10 px-3 text-xs text-teal hover:bg-teal/20"
            >
              Add
            </button>
          </div>
        </section>

        <section>
          <SectionTitle>Location</SectionTitle>
          <div className="h-[260px] overflow-hidden rounded-sm border border-border">
            <FleetMapInset
              location={shipment.currentLocation}
              destination={shipment.destinationLocation}
              divertTo={divertTo}
            />
          </div>
        </section>
      </div>
    </div>
  );
}

function SectionTitle({ children }: { children: React.ReactNode }) {
  return (
    <h4 className="mb-2 font-display text-[11px] font-semibold uppercase tracking-widest text-text-secondary">
      {children}
    </h4>
  );
}

function Metric({
  label,
  value,
  tone,
}: {
  label: string;
  value: React.ReactNode;
  tone?: 'safe' | 'warning' | 'high' | 'critical';
}) {
  const toneCls =
    tone === 'critical' || tone === 'high'
      ? 'text-red'
      : tone === 'warning'
      ? 'text-amber'
      : tone === 'safe'
      ? 'text-green'
      : 'text-text-primary';
  return (
    <div className="rounded-sm border border-border bg-bg-card px-3 py-2">
      <div className="text-[10px] uppercase tracking-widest text-text-secondary">{label}</div>
      <div className={`font-display text-lg font-semibold ${toneCls}`}>{value}</div>
    </div>
  );
}
