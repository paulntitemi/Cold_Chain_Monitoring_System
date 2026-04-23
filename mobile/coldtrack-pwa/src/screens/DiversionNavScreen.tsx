import { useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { useMyShipment } from '@/hooks/useMyShipment';
import { useAlertStore } from '@/store/alertStore';
import { useWakeLock } from '@/hooks/useWakeLock';
import { api } from '@/lib/apiClient';
import { haversineMeters } from '@/lib/haversine';
import { watchPosition } from '@/lib/geolocation';
import { StatusBar } from '@/components/layout/StatusBar';
import { ConnectivityBanner } from '@/components/trip/ConnectivityBanner';
import { TripMap } from '@/components/trip/TripMap';
import { BigButton } from '@/components/ui/BigButton';
import { SafeForTimer } from '@/components/trip/SafeForTimer';
import { TempReadout } from '@/components/trip/TempReadout';

const ARRIVAL_METERS = 100;

export function DiversionNavScreen() {
  const { shipmentId = '' } = useParams();
  const navigate = useNavigate();
  const { data: shipment } = useMyShipment(true);
  const activeAlert = useAlertStore((s) => s.activeAlert);
  const [nearby, setNearby] = useState(false);
  useWakeLock(true);

  const centre = activeAlert?.recommendedCentre;

  useEffect(() => {
    if (!centre) return;
    const stop = watchPosition((pos) => {
      const dist = haversineMeters({ lat: pos.lat, lng: pos.lng }, centre.location);
      setNearby(dist < ARRIVAL_METERS);
    });
    return stop;
  }, [centre]);

  // Mock-mode helper: "arrived" once the mock shipment is within 100m of the centre.
  useEffect(() => {
    if (!centre || !shipment) return;
    const dist = haversineMeters(shipment.currentLocation, centre.location);
    if (dist < ARRIVAL_METERS) setNearby(true);
  }, [shipment, centre]);

  if (!centre) {
    return (
      <div className="min-h-screen flex items-center justify-center text-text-secondary">
        No divert destination.
      </div>
    );
  }

  return (
    <div
      className="flex flex-col overflow-hidden"
      style={{ height: '100dvh', paddingTop: 'env(safe-area-inset-top)' }}
    >
      <StatusBar shipment={shipment} tripStartedAt={shipment?.startTime} />
      <div className="p-3 space-y-2">
        <ConnectivityBanner />
        <div className="border border-teal/40 bg-teal/10 p-3 rounded-sm">
          <div className="text-teal font-display font-semibold uppercase tracking-wider text-xs">
            Diverting
          </div>
          <div className="text-text-primary font-body text-lg mt-1 leading-tight">{centre.name}</div>
          <div className="text-text-secondary font-mono text-xs mt-1">
            {centre.distanceKm?.toFixed(1)} km · {centre.estimatedMinutes} min · {centre.address}
          </div>
        </div>
      </div>

      <div className="flex-1 min-h-[40vh] relative">
        <TripMap
          rider={shipment?.currentLocation ?? centre.location}
          destination={centre.location}
        />
        {shipment && (
          <div className="absolute top-2 right-2 bg-bg-primary/85 border border-red/60 px-2 py-1 rounded-sm flex items-center gap-2">
            <TempReadout temperature={shipment.currentTemp} level={shipment.riskLevel} size="sm" />
            <SafeForTimer remainingMinutes={shipment.remainingSafeMinutes} />
          </div>
        )}
      </div>

      <div
        className="border-t border-border bg-bg-secondary p-3 grid grid-cols-2 gap-2"
        style={{ paddingBottom: 'calc(env(safe-area-inset-bottom) + 0.75rem)' }}
      >
        <BigButton
          variant="ghost"
          height="lg"
          onClick={() => {
            const { lat, lng } = centre.location;
            window.location.href = `https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}&travelmode=driving`;
          }}
        >
          🧭 Open in Maps
        </BigButton>
        <BigButton
          variant="teal"
          height="lg"
          disabled={!nearby}
          onClick={async () => {
            await api.logIncident({
              shipmentId,
              eventType: 'diverted',
              detail: `Rider arrived at ${centre.name}`,
              tempAtEvent: shipment?.currentTemp,
            });
            navigate(`/handoff/cold-store/${shipmentId}`, { replace: true });
          }}
        >
          ✓ I've arrived
        </BigButton>
      </div>
    </div>
  );
}
