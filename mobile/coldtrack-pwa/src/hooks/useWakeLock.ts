import { useEffect } from 'react';
import { acquireWakeLock } from '@/lib/wakeLock';

export function useWakeLock(active = true) {
  useEffect(() => {
    if (!active) return;
    let cancelled = false;
    const handlePromise = acquireWakeLock();

    return () => {
      cancelled = true;
      void handlePromise.then((h) => {
        if (!cancelled) return;
        void h.release();
      });
    };
  }, [active]);
}
