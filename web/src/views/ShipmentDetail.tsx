import { useMemo, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { format } from 'date-fns';
import toast from 'react-hot-toast';
import { useQueryClient } from '@tanstack/react-query';
import { useShipmentDetail } from '@/hooks/useShipmentDetail';
import { useAlertsStore } from '@/store/alertsStore';
import { useBatches } from '@/hooks/useBatches';
import { RiskBadge } from '@/components/ui/RiskBadge';
import { CountdownTimer, ExcursionTimer } from '@/components/ui/CountdownTimer';
import { TemperatureFullChart } from '@/components/charts/TemperatureFullChart';
import { FleetMapInset } from '@/components/map/FleetMap';
import { AlertActionButtons } from '@/components/alerts/AlertActionButtons';
import { VVMBadge } from '@/components/batches/VVMBadge';
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

export function ShipmentDetailView() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { data: shipment, isLoading } = useShipmentDetail(id);
  const alerts = useAlertsStore((s) => s.alerts);
  const { data: batches } = useBatches();
  const [note, setNote] = useState('');
  const qc = useQueryClient();

  const activeAlert = useMemo(
    () => alerts.find((a) => a.shipmentId === id && (a.status === 'active' || a.status === 'escalated')),
    [alerts, id],
  );

  const manifest = useMemo(() => {
    const all = batches ?? [];
    return (shipment?.batchIds ?? []).map((bid) => all.find((b) => b.batchId === bid)).filter(Boolean) as NonNullable<(typeof all)[number]>[];
  }, [batches, shipment]);

  if (isLoading || !shipment) {
    return (
      <div className="flex-1 flex items-center justify-center text-text-secondary">
        Loading shipment…
      </div>
    );
  }

  const submitNote = async () => {
    if (!note.trim()) return;
    await api.logIncident({
      shipmentId: shipment.id,
      eventType: 'operatorNote',
      detail: note.trim(),
      operatorName: 'Control Desk',
    });
    setNote('');
    toast.success('Added to timeline');
    qc.invalidateQueries({ queryKey: ['shipment', shipment.id] });
  };

  return (
    <div className="flex flex-1 flex-col min-h-0 overflow-auto bg-bg-primary">
      <header className="flex flex-wrap items-start justify-between gap-4 border-b border-border bg-bg-secondary px-6 py-4">
        <div>
          <div className="flex items-center gap-3">
            <button
              onClick={() => navigate(-1)}
              className="rounded-sm border border-border bg-bg-card px-2 py-1 text-xs text-text-secondary hover:text-text-primary"
            >
              ← Back
            </button>
            <RiskBadge level={shipment.riskLevel} pulse />
            <h1 className="font-mono text-lg text-teal">{shipment.id}</h1>
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
            Started {format(new Date(shipment.startTime), 'dd MMM HH:mm')} · ETA{' '}
            {format(new Date(shipment.estimatedArrival), 'HH:mm')}
          </div>
        </div>
      </header>

      <div className="grid grid-cols-12 gap-5 px-6 py-5">
        <section className="col-span-12 grid grid-cols-4 gap-3">
          <Card label="Current temp" value={`${shipment.currentTemp.toFixed(1)}°C`} tone={shipment.riskLevel} />
          <Card label="Risk score" value={`${Math.round(shipment.riskScore * 100)}%`} tone={shipment.riskLevel} />
          <Card
            label="Safe for"
            value={<CountdownTimer minutesRemaining={shipment.remainingSafeMinutes} anchor={shipment.lastUpdated} />}
          />
          <Card
            label="Excursion"
            value={<ExcursionTimer secondsOutside={shipment.secondsOutsideRange} />}
          />
        </section>

        <section className="col-span-12 lg:col-span-8 rounded-sm border border-border bg-bg-card p-4">
          <h3 className="mb-3 font-display text-[11px] font-semibold uppercase tracking-widest text-text-secondary">
            Temperature History
          </h3>
          <TemperatureFullChart
            readings={shipment.temperatureHistory}
            minSafe={shipment.minSafeTemp}
            maxSafe={shipment.maxSafeTemp}
            alertMarkers={activeAlert ? [{ timestamp: activeAlert.timestamp, label: 'alert' }] : undefined}
            height={280}
          />
        </section>

        <section className="col-span-12 lg:col-span-4 rounded-sm border border-border bg-bg-card p-4">
          <h3 className="mb-3 font-display text-[11px] font-semibold uppercase tracking-widest text-text-secondary">
            Location
          </h3>
          <div className="h-[280px] overflow-hidden rounded-sm border border-border">
            <FleetMapInset
              location={shipment.currentLocation}
              destination={shipment.destinationLocation}
              divertTo={activeAlert?.recommendedCentre?.location}
            />
          </div>
        </section>

        <section className="col-span-12 rounded-sm border border-border bg-bg-card p-4">
          <h3 className="mb-3 font-display text-[11px] font-semibold uppercase tracking-widest text-text-secondary">
            Batch Manifest
          </h3>
          <table className="w-full text-sm">
            <thead className="text-[10px] uppercase tracking-widest text-text-secondary">
              <tr>
                <th className="text-left py-1.5">Batch</th>
                <th className="text-left py-1.5">Vaccine</th>
                <th className="text-left py-1.5">Doses</th>
                <th className="text-left py-1.5">VVM</th>
                <th className="text-left py-1.5">Range</th>
                <th className="text-left py-1.5">Status</th>
              </tr>
            </thead>
            <tbody>
              {manifest.map((b) => (
                <tr key={b.batchId} className="border-t border-border/60">
                  <td className="py-1.5">
                    <Link to={`/batches`} className="font-mono text-xs text-teal hover:underline">
                      {b.batchId}
                    </Link>
                  </td>
                  <td className="py-1.5">{b.vaccineType}</td>
                  <td className="py-1.5 font-mono text-text-secondary">
                    {b.dosesRemaining}/{b.doseCount}
                  </td>
                  <td className="py-1.5">
                    <VVMBadge stage={b.vvmStatus} compact />
                  </td>
                  <td className="py-1.5 font-mono text-text-secondary">
                    {b.minSafeTemp}°C – {b.maxSafeTemp}°C
                  </td>
                  <td className="py-1.5 text-teal">In transit</td>
                </tr>
              ))}
              {manifest.length === 0 && (
                <tr>
                  <td colSpan={6} className="py-3 text-center text-text-secondary">
                    No batches matched in registry.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </section>

        {activeAlert && (
          <section className="col-span-12 rounded-sm border border-red/40 bg-red/10 p-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <RiskBadge level={activeAlert.riskLevel} pulse />
                <h3 className="font-display text-sm font-semibold uppercase tracking-widest text-red">
                  Active Alert
                </h3>
                <span className="font-mono text-[11px] text-text-secondary">
                  {format(new Date(activeAlert.timestamp), 'HH:mm:ss')}
                </span>
              </div>
              <AlertActionButtons alert={activeAlert} riderPhone={shipment.riderPhone} />
            </div>
            <div className="mt-3 grid grid-cols-3 gap-3 text-sm">
              <div>
                <div className="text-[10px] uppercase tracking-widest text-text-secondary">Risk at trigger</div>
                <div className="font-display text-lg text-red">
                  {Math.round(activeAlert.riskScore * 100)}%
                </div>
              </div>
              <div>
                <div className="text-[10px] uppercase tracking-widest text-text-secondary">Temp at trigger</div>
                <div className="font-display text-lg text-red">
                  {activeAlert.tempAtTrigger.toFixed(1)}°C
                </div>
              </div>
              {activeAlert.recommendedCentre && (
                <div>
                  <div className="text-[10px] uppercase tracking-widest text-text-secondary">Recommended divert</div>
                  <div className="font-display text-sm text-teal">
                    {activeAlert.recommendedCentre.name}
                  </div>
                  <div className="text-[11px] text-text-secondary">
                    {activeAlert.recommendedCentre.distanceKm?.toFixed(1)} km ·{' '}
                    {activeAlert.recommendedCentre.estimatedMinutes} min
                  </div>
                </div>
              )}
            </div>
            <div className="mt-3 text-xs">
              {activeAlert.riderResponse === 'accepted' ? (
                <span className="text-green">
                  Rider accepted — navigating to {activeAlert.recommendedCentre?.name ?? 'centre'}
                </span>
              ) : activeAlert.riderResponse === 'ignored' ? (
                <span className="text-red">Rider ignored — re-alert in 36s</span>
              ) : (
                <span className="text-amber animate-pulse">AWAITING RIDER RESPONSE</span>
              )}
            </div>
          </section>
        )}

        <section className="col-span-12 rounded-sm border border-border bg-bg-card p-4">
          <h3 className="mb-3 font-display text-[11px] font-semibold uppercase tracking-widest text-text-secondary">
            Incident Log
          </h3>
          <ol className="relative ml-3 border-l border-border pl-5 space-y-3">
            {(shipment.incidentLog ?? []).map((e) => (
              <li key={e.id} className="relative">
                <span className="absolute -left-[26px] top-1 flex h-4 w-4 items-center justify-center rounded-full bg-teal/20 border border-teal/50 text-[9px]">
                  {eventIcon[e.eventType]}
                </span>
                <div className="text-[10px] font-mono text-text-dim">
                  {format(new Date(e.timestamp), 'dd MMM HH:mm:ss')}
                </div>
                <div className="text-sm text-text-primary">{e.detail}</div>
                {e.operatorName && (
                  <div className="text-[11px] text-text-secondary">— {e.operatorName}</div>
                )}
              </li>
            ))}
            {(shipment.incidentLog ?? []).length === 0 && (
              <li className="text-xs text-text-secondary">No events logged yet.</li>
            )}
          </ol>
          <div className="mt-4 flex gap-2">
            <input
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="Add operator note…"
              className="flex-1 rounded-sm border border-border bg-bg-secondary px-3 py-1.5 text-sm text-text-primary placeholder:text-text-dim focus:border-teal focus:outline-none"
              onKeyDown={(e) => e.key === 'Enter' && submitNote()}
            />
            <button
              onClick={submitNote}
              className="rounded-sm border border-teal/40 bg-teal/10 px-4 text-xs text-teal hover:bg-teal/20"
            >
              Add note
            </button>
          </div>
        </section>
      </div>
    </div>
  );
}

function Card({
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
    <div className="rounded-sm border border-border bg-bg-card px-4 py-3">
      <div className="text-[10px] uppercase tracking-widest text-text-secondary">{label}</div>
      <div className={`font-display text-2xl font-semibold ${toneCls}`}>{value}</div>
    </div>
  );
}
