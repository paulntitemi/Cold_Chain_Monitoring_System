import { useEffect, useState } from 'react';
import { clsx } from 'clsx';

interface Props {
  remainingMinutes: number;
  className?: string;
}

/**
 * Safe-for countdown. `remainingMinutes` is the current server-reported
 * budget; we tick it down locally between polls so the rider sees a
 * smooth second-by-second number instead of a jumpy mm value.
 */
export function SafeForTimer({ remainingMinutes, className }: Props) {
  const [tick, setTick] = useState(0);
  useEffect(() => {
    const id = window.setInterval(() => setTick((t) => t + 1), 1000);
    return () => window.clearInterval(id);
  }, []);

  // Server budget + local tick (reset each time the server value changes).
  const serverSeconds = Math.max(0, Math.round(remainingMinutes * 60));
  const seconds = Math.max(0, serverSeconds - tick);

  useEffect(() => {
    setTick(0);
  }, [remainingMinutes]);

  const mins = Math.floor(seconds / 60);
  const secs = seconds % 60;
  const low = seconds < 5 * 60;

  return (
    <div
      className={clsx(
        'font-mono text-xs uppercase tracking-[0.2em]',
        low ? 'text-red' : 'text-text-secondary',
        className,
      )}
    >
      Safe for{' '}
      <span className="tabular-nums font-semibold">
        {String(mins).padStart(2, '0')}:{String(secs).padStart(2, '0')}
      </span>
    </div>
  );
}
