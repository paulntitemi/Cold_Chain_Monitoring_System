import { useEffect, useRef } from 'react';
import { api } from '@/lib/apiClient';
import { watchPosition } from '@/lib/geolocation';

/**
 * While the Live Trip screen is mounted, emit a position ping every 10s.
 * watchPosition returns events on every movement; we throttle to 10s at
 * the send layer so the server load is bounded.
 */
export function useGeolocationReporting(shipmentId: string | undefined, active: boolean) {
  const lastSentAt = useRef(0);

  useEffect(() => {
    if (!active || !shipmentId) return;

    const stop = watchPosition((pos) => {
      const now = Date.now();
      if (now - lastSentAt.current < 10_000) return;
      lastSentAt.current = now;

      void api.postPing({
        shipmentId,
        lat: pos.lat,
        lng: pos.lng,
        accuracy: pos.accuracy,
        speed: pos.speed,
        heading: pos.heading,
        clientTs: new Date(pos.timestamp).toISOString(),
      });
    });

    return stop;
  }, [shipmentId, active]);
}
