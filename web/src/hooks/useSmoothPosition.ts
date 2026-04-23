import { useEffect, useRef, useState } from 'react';

interface LatLng {
  lat: number;
  lng: number;
}

/**
 * Smoothly interpolate a lat/lng target over time. Whenever the target
 * coordinates change, the hook eases from the currently-displayed point to
 * the new target over `durationMs`, driven by requestAnimationFrame.
 *
 * Matches the Uber-style "glide to next ping" behaviour: polls arrive every
 * few seconds, but the marker never teleports — each render interpolates the
 * in-flight position. If a new target lands mid-animation, we pivot from the
 * current displayed point rather than snapping.
 */
export function useSmoothPosition(target: LatLng, durationMs = 5000): LatLng {
  const [pos, setPos] = useState<LatLng>(target);

  const posRef = useRef<LatLng>(target);
  posRef.current = pos;

  const fromRef = useRef<LatLng>(target);
  const toRef = useRef<LatLng>(target);
  const startRef = useRef<number>(performance.now());
  const rafRef = useRef<number | null>(null);

  useEffect(() => {
    if (toRef.current.lat === target.lat && toRef.current.lng === target.lng) {
      return;
    }

    fromRef.current = posRef.current;
    toRef.current = target;
    startRef.current = performance.now();

    const tick = () => {
      const elapsed = performance.now() - startRef.current;
      const t = Math.min(1, elapsed / durationMs);
      // Ease-out quad — fast start, gentle arrival.
      const eased = 1 - (1 - t) * (1 - t);
      const f = fromRef.current;
      const to = toRef.current;
      setPos({
        lat: f.lat + (to.lat - f.lat) * eased,
        lng: f.lng + (to.lng - f.lng) * eased,
      });
      if (t < 1) {
        rafRef.current = requestAnimationFrame(tick);
      } else {
        rafRef.current = null;
      }
    };

    if (rafRef.current !== null) cancelAnimationFrame(rafRef.current);
    rafRef.current = requestAnimationFrame(tick);

    return () => {
      if (rafRef.current !== null) {
        cancelAnimationFrame(rafRef.current);
        rafRef.current = null;
      }
    };
  }, [target.lat, target.lng, durationMs]);

  return pos;
}
