/**
 * watchPosition wrapper that emits position updates. Caller is responsible
 * for throttling / upstream reporting.
 */

export interface Position {
  lat: number;
  lng: number;
  accuracy?: number;
  speed?: number | null;
  heading?: number | null;
  timestamp: number;
}

export type PositionHandler = (pos: Position) => void;
export type PositionErrorHandler = (err: GeolocationPositionError) => void;

export function geolocationSupported(): boolean {
  return typeof navigator !== 'undefined' && 'geolocation' in navigator;
}

export function watchPosition(
  onPosition: PositionHandler,
  onError?: PositionErrorHandler,
): () => void {
  if (!geolocationSupported()) return () => {};

  const id = navigator.geolocation.watchPosition(
    (p) => {
      onPosition({
        lat: p.coords.latitude,
        lng: p.coords.longitude,
        accuracy: p.coords.accuracy,
        speed: p.coords.speed,
        heading: p.coords.heading,
        timestamp: p.timestamp,
      });
    },
    (err) => onError?.(err),
    {
      enableHighAccuracy: true,
      maximumAge: 5_000,
      timeout: 20_000,
    },
  );

  return () => {
    try {
      navigator.geolocation.clearWatch(id);
    } catch {
      // ignore
    }
  };
}

export function getCurrentPosition(): Promise<Position> {
  if (!geolocationSupported()) {
    return Promise.reject(new Error('Geolocation unsupported'));
  }
  return new Promise((resolve, reject) => {
    navigator.geolocation.getCurrentPosition(
      (p) =>
        resolve({
          lat: p.coords.latitude,
          lng: p.coords.longitude,
          accuracy: p.coords.accuracy,
          speed: p.coords.speed,
          heading: p.coords.heading,
          timestamp: p.timestamp,
        }),
      (err) => reject(err),
      { enableHighAccuracy: true, timeout: 15_000 },
    );
  });
}
