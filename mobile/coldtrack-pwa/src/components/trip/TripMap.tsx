import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { GoogleMap, useLoadScript, Marker, DirectionsRenderer, Polyline } from '@react-google-maps/api';
import { env } from '@/config/env';
import { haversineMeters } from '@/lib/haversine';

export interface NavStep {
  instructionHtml: string;
  instructionText: string;
  maneuver: string;
  distanceText: string;
  distanceMeters: number;
  durationText: string;
  durationSec: number;
  startLocation: { lat: number; lng: number };
  endLocation: { lat: number; lng: number };
}

export interface RouteInfo {
  durationText: string;
  distanceText: string;
  durationSec: number;
  distanceMeters: number;
  steps: NavStep[];
  currentStepIndex: number;
  distanceToNextManeuverM: number;
  arrived: boolean;
}

interface Props {
  rider: { lat: number; lng: number };
  destination?: { lat: number; lng: number };
  height?: string;
  onRouteInfo?(info: RouteInfo): void;
  /**
   * When true, the camera smoothly follows the rider at a close zoom. The
   * user can still pan — any manual drag fires onExitNavMode so the parent
   * can flip the toggle off.
   */
  navMode?: boolean;
  onExitNavMode?(): void;
}

const darkStyle: google.maps.MapTypeStyle[] = [
  { elementType: 'geometry', stylers: [{ color: '#080C14' }] },
  { elementType: 'labels.text.stroke', stylers: [{ color: '#080C14' }] },
  { elementType: 'labels.text.fill', stylers: [{ color: '#64748B' }] },
  { featureType: 'administrative.country', elementType: 'geometry.stroke', stylers: [{ color: '#1E2D45' }] },
  { featureType: 'administrative.locality', elementType: 'labels.text.fill', stylers: [{ color: '#94A3B8' }] },
  { featureType: 'poi', stylers: [{ visibility: 'off' }] },
  { featureType: 'road', elementType: 'geometry', stylers: [{ color: '#1E2D45' }] },
  { featureType: 'road', elementType: 'geometry.stroke', stylers: [{ color: '#2A3F5F' }] },
  { featureType: 'road', elementType: 'labels.text.fill', stylers: [{ color: '#94A3B8' }] },
  { featureType: 'road.highway', elementType: 'geometry', stylers: [{ color: '#2A3F5F' }] },
  { featureType: 'road.highway', elementType: 'geometry.stroke', stylers: [{ color: '#334155' }] },
  { featureType: 'transit', stylers: [{ visibility: 'off' }] },
  { featureType: 'water', elementType: 'geometry', stylers: [{ color: '#0D1420' }] },
  { featureType: 'water', elementType: 'labels.text.fill', stylers: [{ color: '#334155' }] },
];

const containerStyle = { width: '100%', height: '100%' };

const REROUTE_DRIFT_METERS = 250;
const REROUTE_INTERVAL_MS = 3 * 60_000;
const NAV_ZOOM = 16;

function stripHtml(html: string): string {
  if (typeof DOMParser === 'undefined') return html.replace(/<[^>]+>/g, '');
  const doc = new DOMParser().parseFromString(html, 'text/html');
  return doc.body.textContent ?? '';
}

function parseSteps(result: google.maps.DirectionsResult): NavStep[] {
  const leg = result.routes[0]?.legs[0];
  if (!leg) return [];
  return leg.steps.map((s) => ({
    instructionHtml: s.instructions ?? '',
    instructionText: stripHtml(s.instructions ?? ''),
    maneuver: (s as google.maps.DirectionsStep & { maneuver?: string }).maneuver ?? '',
    distanceText: s.distance?.text ?? '',
    distanceMeters: s.distance?.value ?? 0,
    durationText: s.duration?.text ?? '',
    durationSec: s.duration?.value ?? 0,
    startLocation: { lat: s.start_location.lat(), lng: s.start_location.lng() },
    endLocation: { lat: s.end_location.lat(), lng: s.end_location.lng() },
  }));
}

/**
 * Find the step the rider is currently "on" by picking the step whose end
 * is the closest unpassed waypoint. Approximate but good enough for a demo;
 * a production system would use linear referencing on the polyline.
 */
function pickCurrentStep(
  rider: { lat: number; lng: number },
  steps: NavStep[],
): { index: number; distanceToNextManeuverM: number } {
  if (steps.length === 0) return { index: -1, distanceToNextManeuverM: 0 };
  let bestIdx = 0;
  let bestDist = Number.POSITIVE_INFINITY;
  for (let i = 0; i < steps.length; i++) {
    const d = haversineMeters(rider, steps[i].endLocation);
    // Prefer the earliest step whose end is still ahead of us (d < bestDist).
    if (d < bestDist) {
      bestDist = d;
      bestIdx = i;
    }
  }
  return { index: bestIdx, distanceToNextManeuverM: Math.round(bestDist) };
}

export function TripMap({
  rider,
  destination,
  height = '100%',
  onRouteInfo,
  navMode = false,
  onExitNavMode,
}: Props) {
  const { isLoaded, loadError } = useLoadScript({
    googleMapsApiKey: env.googleMapsApiKey,
    id: 'coldtrack-gmaps',
  });

  const [directions, setDirections] = useState<google.maps.DirectionsResult | null>(null);
  const [routeError, setRouteError] = useState<string | null>(null);
  const [mapRef, setMapRef] = useState<google.maps.Map | null>(null);
  const [tilesLoaded, setTilesLoaded] = useState(false);
  const [containerPx, setContainerPx] = useState<{ w: number; h: number }>({ w: 0, h: 0 });
  const containerRef = useRef<HTMLDivElement | null>(null);
  const lastFetchedAt = useRef(0);
  const lastFetchedOrigin = useRef<{ lat: number; lng: number } | null>(null);
  const lastDestKey = useRef<string | null>(null);
  const onExitNavModeRef = useRef(onExitNavMode);
  const previousZoom = useRef<number | null>(null);
  onExitNavModeRef.current = onExitNavMode;

  const steps = useMemo(() => (directions ? parseSteps(directions) : []), [directions]);

  const initialCenter = useRef<{ lat: number; lng: number } | null>(null);
  if (initialCenter.current === null) {
    initialCenter.current = destination
      ? { lat: (rider.lat + destination.lat) / 2, lng: (rider.lng + destination.lng) / 2 }
      : rider;
  }
  const debugCenter = initialCenter.current;

  const onMapLoad = useCallback((map: google.maps.Map) => {
    setMapRef(map);
    map.addListener('tilesloaded', () => setTilesLoaded(true));
    map.addListener('dragstart', () => {
      // User panned manually — drop out of follow mode. Parent decides how
      // to handle: typically it sets navMode=false which re-exposes the
      // overview.
      onExitNavModeRef.current?.();
    });
    const kick = () => google.maps.event.trigger(map, 'resize');
    requestAnimationFrame(kick);
    setTimeout(kick, 300);
  }, []);

  useEffect(() => {
    if (!containerRef.current || typeof ResizeObserver === 'undefined') return;
    const ro = new ResizeObserver((entries) => {
      const rect = entries[0]?.contentRect;
      if (rect) setContainerPx({ w: Math.round(rect.width), h: Math.round(rect.height) });
      if (mapRef) google.maps.event.trigger(mapRef, 'resize');
    });
    ro.observe(containerRef.current);
    return () => ro.disconnect();
  }, [mapRef]);

  // Follow-camera: smoothly pan to the rider's position as it changes.
  useEffect(() => {
    if (!mapRef || !navMode) return;
    if (previousZoom.current === null) {
      previousZoom.current = mapRef.getZoom() ?? 12;
      mapRef.setZoom(NAV_ZOOM);
    }
    mapRef.panTo(rider);
  }, [mapRef, navMode, rider]);

  // When the user toggles navMode off, restore the prior zoom level.
  useEffect(() => {
    if (navMode || !mapRef || previousZoom.current === null) return;
    mapRef.setZoom(previousZoom.current);
    previousZoom.current = null;
  }, [navMode, mapRef]);

  // Fetch + refresh the driving route.
  useEffect(() => {
    if (!isLoaded || !destination) return;

    const destKey = `${destination.lat.toFixed(4)},${destination.lng.toFixed(4)}`;
    const destinationChanged = lastDestKey.current !== destKey;
    const drifted =
      lastFetchedOrigin.current &&
      haversineMeters(rider, lastFetchedOrigin.current) > REROUTE_DRIFT_METERS;
    const staleByTime = Date.now() - lastFetchedAt.current > REROUTE_INTERVAL_MS;

    if (!destinationChanged && !drifted && !staleByTime) return;

    const svc = new google.maps.DirectionsService();
    lastFetchedAt.current = Date.now();
    lastFetchedOrigin.current = rider;
    lastDestKey.current = destKey;

    svc.route(
      {
        origin: rider,
        destination,
        travelMode: google.maps.TravelMode.DRIVING,
      },
      (result, status) => {
        if (status === google.maps.DirectionsStatus.OK && result) {
          setDirections(result);
          setRouteError(null);
        } else {
          setRouteError(status);
        }
      },
    );
  }, [isLoaded, destination, rider]);

  // Emit RouteInfo whenever rider moves or the route changes. This drives
  // the in-app nav instruction card in LiveTripScreen.
  useEffect(() => {
    if (!directions || !onRouteInfo) return;
    const leg = directions.routes[0]?.legs[0];
    if (!leg) return;
    const { index, distanceToNextManeuverM } = pickCurrentStep(rider, steps);
    const arrived = destination
      ? haversineMeters(rider, destination) < 30
      : false;
    onRouteInfo({
      durationText: leg.duration?.text ?? '',
      distanceText: leg.distance?.text ?? '',
      durationSec: leg.duration?.value ?? 0,
      distanceMeters: leg.distance?.value ?? 0,
      steps,
      currentStepIndex: index,
      distanceToNextManeuverM,
      arrived,
    });
  }, [directions, steps, rider, destination, onRouteInfo]);

  if (!env.googleMapsApiKey || env.googleMapsApiKey === 'your_key_here') {
    return (
      <div
        style={{ height }}
        className="w-full flex items-center justify-center bg-bg-secondary border border-border text-text-secondary text-xs font-mono uppercase tracking-wider"
      >
        Map unavailable · set VITE_GOOGLE_MAPS_API_KEY in .env
      </div>
    );
  }

  if (loadError) {
    return (
      <div
        style={{ height }}
        className="w-full flex items-center justify-center bg-red-tint border border-red/60 text-red text-xs font-mono uppercase tracking-wider p-3 text-center"
      >
        Map failed to load · check key referrer + billing
      </div>
    );
  }

  if (!isLoaded) {
    return (
      <div
        style={{ height }}
        className="w-full flex items-center justify-center bg-bg-secondary text-text-secondary text-xs font-mono"
      >
        Loading map…
      </div>
    );
  }

  return (
    <div ref={containerRef} style={{ height, position: 'relative' }} className="w-full">
      <GoogleMap
        mapContainerStyle={containerStyle}
        onLoad={onMapLoad}
        options={{
          center: initialCenter.current,
          zoom: 12,
          styles: darkStyle,
          disableDefaultUI: true,
          gestureHandling: 'greedy',
          backgroundColor: '#080C14',
        }}
      >
        <Marker
          position={rider}
          icon={{
            path: google.maps.SymbolPath.CIRCLE,
            scale: 10,
            fillColor: '#00C9A7',
            fillOpacity: 1,
            strokeColor: '#080C14',
            strokeWeight: 3,
          }}
        />
        {destination && (
          <Marker
            position={destination}
            icon={{
              path: 'M 0,-10 L 8,10 L 0,4 L -8,10 Z',
              fillColor: '#00C9A7',
              fillOpacity: 0.85,
              strokeColor: '#00C9A7',
              strokeWeight: 1,
              scale: 1,
              anchor: new google.maps.Point(0, 10),
            }}
          />
        )}

        {directions ? (
          <DirectionsRenderer
            directions={directions}
            options={{
              suppressMarkers: true,
              suppressInfoWindows: true,
              preserveViewport: true,
              polylineOptions: {
                strokeColor: '#00C9A7',
                strokeOpacity: 0.9,
                strokeWeight: 5,
              },
            }}
          />
        ) : destination ? (
          <Polyline
            path={[rider, destination]}
            options={{
              strokeColor: '#00C9A7',
              strokeOpacity: 0,
              icons: [
                {
                  icon: { path: 'M 0,-1 0,1', strokeOpacity: 1, scale: 3 },
                  offset: '0',
                  repeat: '12px',
                },
              ],
            }}
          />
        ) : null}

        {routeError && (
          <div className="absolute top-2 left-1/2 -translate-x-1/2 bg-red-tint border border-red/60 text-red text-[10px] font-mono uppercase tracking-wider px-2 py-1 rounded-sm pointer-events-none">
            Route error · {routeError}
          </div>
        )}
      </GoogleMap>

      {import.meta.env.DEV && (
        <div className="absolute bottom-2 left-2 bg-black/80 border border-teal/60 text-teal text-[10px] font-mono uppercase px-2 py-1 rounded-sm pointer-events-none leading-tight">
          <div>box {containerPx.w}×{containerPx.h}</div>
          <div>loaded {isLoaded ? 'Y' : 'N'} · map {mapRef ? 'Y' : 'N'} · tiles {tilesLoaded ? 'Y' : 'N'}</div>
          <div>ctr {debugCenter.lat.toFixed(3)},{debugCenter.lng.toFixed(3)} · nav {navMode ? 'Y' : 'N'}</div>
        </div>
      )}
    </div>
  );
}
