import { useCallback, useMemo, useState } from 'react';
import { GoogleMap, Polyline, useJsApiLoader } from '@react-google-maps/api';
import { useShipmentsStore } from '@/store/shipmentsStore';
import { useUiStore } from '@/store/uiStore';
import { useAlertsStore } from '@/store/alertsStore';
import { mockStorageCentres } from '@/mock/mockData';
import { RiderMarker } from './RiderMarker';
import { StorageCentreMarker } from './StorageCentreMarker';
import { useSmoothPosition } from '@/hooks/useSmoothPosition';
import { env } from '@/config/env';
import clsx from 'clsx';
import type { Shipment } from '@/types/shipment';

const mapContainerStyle = { width: '100%', height: '100%' };

const LONDON_CENTER = { lat: 51.5074, lng: -0.1278 };

/**
 * Dark Google Maps styling — matches the ICU-control-room aesthetic. Paste-ready
 * from the Google Maps style reference; tuned to the ColdTrack palette.
 */
const mapStyles: google.maps.MapTypeStyle[] = [
  { elementType: 'geometry', stylers: [{ color: '#0D1420' }] },
  { elementType: 'labels.text.stroke', stylers: [{ color: '#0D1420' }] },
  { elementType: 'labels.text.fill', stylers: [{ color: '#64748B' }] },
  { featureType: 'administrative.locality', elementType: 'labels.text.fill', stylers: [{ color: '#94a3b8' }] },
  { featureType: 'poi', stylers: [{ visibility: 'off' }] },
  { featureType: 'road', elementType: 'geometry', stylers: [{ color: '#111B2E' }] },
  { featureType: 'road', elementType: 'geometry.stroke', stylers: [{ color: '#1E2D45' }] },
  { featureType: 'road', elementType: 'labels.text.fill', stylers: [{ color: '#475569' }] },
  { featureType: 'road.highway', elementType: 'geometry', stylers: [{ color: '#1E2D45' }] },
  { featureType: 'transit', stylers: [{ visibility: 'off' }] },
  { featureType: 'water', elementType: 'geometry', stylers: [{ color: '#050810' }] },
  { featureType: 'water', elementType: 'labels.text.fill', stylers: [{ color: '#334155' }] },
];

const routeColor: Record<string, string> = {
  safe: '#10B981',
  warning: '#F59E0B',
  high: '#EF4444',
  critical: '#EF4444',
};

export function FleetMap() {
  const shipments = useShipmentsStore((s) => s.shipments);
  const alerts = useAlertsStore((s) => s.alerts);
  const selectedId = useUiStore((s) => s.selectedShipmentId);
  const mapLayer = useUiStore((s) => s.mapLayer);
  const setMapLayer = useUiStore((s) => s.setMapLayer);
  const showCentres = useUiStore((s) => s.showStorageCentres);
  const toggleCentres = useUiStore((s) => s.toggleStorageCentres);
  const openDetail = useUiStore((s) => s.openDetailPanel);

  const [mapRef, setMapRef] = useState<google.maps.Map | null>(null);
  const onLoad = useCallback((map: google.maps.Map) => setMapRef(map), []);

  const { isLoaded, loadError } = useJsApiLoader({
    id: 'gmaps-script',
    googleMapsApiKey: env.googleMapsApiKey,
  });

  const anyAlerted = useMemo(
    () => shipments.some((s) => s.riskLevel === 'warning' || s.riskLevel === 'high' || s.riskLevel === 'critical'),
    [shipments],
  );

  const recommendedCentreByShipment = useMemo(() => {
    const m = new Map<string, { lat: number; lng: number }>();
    for (const a of alerts) {
      if (a.status === 'active' && a.recommendedCentre) {
        m.set(a.shipmentId, a.recommendedCentre.location);
      }
    }
    return m;
  }, [alerts]);

  if (loadError) {
    return (
      <div className="h-full flex items-center justify-center bg-bg-secondary text-red text-sm px-6 text-center">
        Failed to load Google Maps. Check VITE_GOOGLE_MAPS_API_KEY.
      </div>
    );
  }

  if (!isLoaded) {
    return (
      <div className="h-full flex items-center justify-center bg-bg-secondary text-text-secondary text-sm">
        Loading map…
      </div>
    );
  }

  return (
    <div className="relative h-full w-full">
      <GoogleMap
        mapContainerStyle={mapContainerStyle}
        center={LONDON_CENTER}
        zoom={11}
        onLoad={onLoad}
        mapTypeId={mapLayer}
        options={{
          styles: mapLayer === 'roadmap' ? mapStyles : undefined,
          disableDefaultUI: true,
          zoomControl: true,
          backgroundColor: '#080C14',
          clickableIcons: false,
          gestureHandling: 'greedy',
        }}
      >
        {showCentres && anyAlerted &&
          mockStorageCentres.map((c) => <StorageCentreMarker key={c.id} centre={c} />)}

        {shipments.map((s) => (
          <AnimatedShipment
            key={s.id}
            shipment={s}
            divertCentre={recommendedCentreByShipment.get(s.id)}
            selected={selectedId === s.id}
            onClick={(latest) => {
              openDetail(s.id);
              mapRef?.panTo(latest);
            }}
          />
        ))}
      </GoogleMap>

      <div className="absolute left-3 top-3 flex gap-1 rounded-sm border border-border bg-bg-secondary/90 p-1 backdrop-blur">
        {(['roadmap', 'satellite', 'terrain'] as const).map((m) => (
          <button
            key={m}
            onClick={() => setMapLayer(m)}
            className={clsx(
              'px-2 py-1 text-[11px] uppercase tracking-widest rounded-sm',
              mapLayer === m
                ? 'bg-teal/15 text-teal'
                : 'text-text-secondary hover:text-text-primary',
            )}
          >
            {m}
          </button>
        ))}
      </div>

      <button
        onClick={toggleCentres}
        className={clsx(
          'absolute right-3 top-3 rounded-sm border px-2 py-1 text-[11px] uppercase tracking-widest backdrop-blur',
          showCentres
            ? 'border-teal/40 bg-teal/10 text-teal'
            : 'border-border bg-bg-secondary/90 text-text-secondary',
        )}
      >
        Cold stores
      </button>
    </div>
  );
}

/**
 * One render unit per shipment: the dashed route, the optional red divert line,
 * and the rider marker all read from a single smoothed position. This is what
 * keeps the circle locked on the line — they can't drift apart because there is
 * only one source of truth per frame.
 */
function AnimatedShipment({
  shipment,
  divertCentre,
  selected,
  onClick,
}: {
  shipment: Shipment;
  divertCentre?: { lat: number; lng: number };
  selected?: boolean;
  onClick: (latest: { lat: number; lng: number }) => void;
}) {
  const pos = useSmoothPosition(shipment.currentLocation, 5000);
  const dest = shipment.destinationLocation ?? shipment.currentLocation;
  const color = routeColor[shipment.riskLevel];

  return (
    <>
      <Polyline
        path={[pos, dest]}
        options={{
          strokeColor: color,
          strokeOpacity: 0,
          strokeWeight: 0,
          icons: [
            {
              icon: {
                path: 'M 0,-1 0,1',
                strokeOpacity: 0.7,
                strokeColor: color,
                scale: 2,
              },
              offset: '0',
              repeat: '10px',
            },
          ],
        }}
      />
      {divertCentre && (
        <Polyline
          path={[pos, divertCentre]}
          options={{
            strokeColor: '#EF4444',
            strokeOpacity: 0.95,
            strokeWeight: 3,
          }}
        />
      )}
      <RiderMarker
        shipment={shipment}
        position={pos}
        selected={selected}
        onClick={() => onClick(pos)}
      />
    </>
  );
}

export function FleetMapInset({
  location,
  destination,
  divertTo,
}: {
  location: { lat: number; lng: number };
  destination?: { lat: number; lng: number };
  divertTo?: { lat: number; lng: number };
}) {
  const { isLoaded } = useJsApiLoader({
    id: 'gmaps-script',
    googleMapsApiKey: env.googleMapsApiKey,
  });
  if (!isLoaded) {
    return (
      <div className="h-full w-full flex items-center justify-center bg-bg-secondary text-text-secondary text-xs">
        Loading map…
      </div>
    );
  }
  return (
    <GoogleMap
      mapContainerStyle={mapContainerStyle}
      center={location}
      zoom={13}
      options={{
        styles: mapStyles,
        disableDefaultUI: true,
        zoomControl: true,
        backgroundColor: '#080C14',
      }}
    >
      {destination && (
        <Polyline
          path={[location, destination]}
          options={{ strokeColor: '#00C9A7', strokeOpacity: 0.7, strokeWeight: 2 }}
        />
      )}
      {divertTo && (
        <Polyline
          path={[location, divertTo]}
          options={{ strokeColor: '#EF4444', strokeOpacity: 0.9, strokeWeight: 3 }}
        />
      )}
    </GoogleMap>
  );
}
