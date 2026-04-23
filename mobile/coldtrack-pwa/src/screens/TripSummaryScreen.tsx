import { useMemo } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { format } from 'date-fns';
import { getLiveShipmentSnapshot } from '@/lib/apiClient';
import { useAlertStore } from '@/store/alertStore';
import { useTripStore } from '@/store/tripStore';
import { mockBatch } from '@/mock/mockData';
import { TemperatureFullChart } from '@/components/charts/TemperatureFullChart';
import { BigButton } from '@/components/ui/BigButton';
import { IconChip } from '@/components/ui/IconChip';
import { StatusBar } from '@/components/layout/StatusBar';

export function TripSummaryScreen() {
  const { shipmentId = '' } = useParams();
  const navigate = useNavigate();
  const alert = useAlertStore((s) => s.activeAlert);
  const clearTrip = useTripStore((s) => s.clear);

  // Trip state in mock mode is in-memory; real mode would fetch by id.
  const shipment = getLiveShipmentSnapshot();

  const diverted = alert?.outcome === 'diverted' || alert?.riderResponse === 'accepted';
  const dosesSaved = mockBatch.doseCount;

  const alertMarkers = useMemo(
    () =>
      shipment.incidentLog
        ?.filter((i) => i.eventType === 'alertTriggered')
        .map((i) => ({ timestamp: i.timestamp, label: 'ALERT' })) ?? [],
    [shipment.incidentLog],
  );

  const timeInRange = (() => {
    const readings = shipment.temperatureHistory;
    if (readings.length === 0) return 100;
    const inRange = readings.filter(
      (r) => r.temperature >= shipment.minSafeTemp && r.temperature <= shipment.maxSafeTemp,
    ).length;
    return Math.round((inRange / readings.length) * 100);
  })();

  return (
    <div className="min-h-screen flex flex-col" style={{ paddingTop: 'env(safe-area-inset-top)' }}>
      <StatusBar shipment={shipment} />
      <div className="p-4 flex-1 overflow-y-auto space-y-4">
        <div>
          <div className="font-mono text-[11px] uppercase tracking-[0.2em] text-text-secondary">
            {shipmentId} · completed
          </div>
          <h1 className="font-display font-bold text-3xl text-teal mt-1">
            {diverted ? `Diverted — ${dosesSaved} doses saved` : 'Delivered safe'}
          </h1>
          <div className="text-text-secondary text-sm mt-1">
            {shipment.origin} → {shipment.destination}
          </div>
        </div>

        <div className="border border-border bg-bg-card p-3 rounded-sm">
          <div className="text-text-secondary font-mono text-[11px] uppercase tracking-wider mb-2">
            Temperature trace
          </div>
          <TemperatureFullChart
            readings={shipment.temperatureHistory}
            minSafe={shipment.minSafeTemp}
            maxSafe={shipment.maxSafeTemp}
            alertMarkers={alertMarkers}
            height={220}
          />
        </div>

        <div className="flex gap-2 flex-wrap">
          <IconChip tone="teal">Time in range {timeInRange}%</IconChip>
          <IconChip tone="teal">
            Alerts responded to {alert?.riderResponse === 'accepted' ? '1/1' : '0/1'}
          </IconChip>
          <IconChip>
            {format(new Date(shipment.startTime), 'HH:mm')} →{' '}
            {format(new Date(shipment.lastUpdated), 'HH:mm')}
          </IconChip>
        </div>

        <div className="border border-border bg-bg-card rounded-sm">
          <div className="px-3 py-2 border-b border-border text-text-secondary font-mono text-[11px] uppercase tracking-wider">
            Incident timeline
          </div>
          <ul className="divide-y divide-border">
            {(shipment.incidentLog ?? []).map((i) => (
              <li key={i.id} className="px-3 py-2 flex items-start gap-3">
                <span className="mt-1 inline-block w-2 h-2 rounded-full bg-teal" />
                <div className="flex-1">
                  <div className="font-body text-sm text-text-primary">{i.detail}</div>
                  <div className="font-mono text-[10px] uppercase tracking-wider text-text-secondary mt-0.5">
                    {format(new Date(i.timestamp), 'HH:mm:ss')}
                    {typeof i.tempAtEvent === 'number' && ` · ${i.tempAtEvent.toFixed(1)}°C`}
                  </div>
                </div>
              </li>
            ))}
          </ul>
        </div>

        <div className="grid grid-cols-2 gap-2">
          <BigButton
            variant="teal"
            onClick={() => {
              clearTrip();
              navigate('/assignments', { replace: true });
            }}
          >
            Next assignment
          </BigButton>
          <BigButton
            variant="ghost"
            onClick={() => {
              window.location.href = 'tel:+442071887188';
            }}
          >
            ☎ Dispatch
          </BigButton>
        </div>
      </div>
    </div>
  );
}
