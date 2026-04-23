import clsx from 'clsx';
import { useEffect, useState } from 'react';

interface Props {
  /** Minutes remaining at the time lastUpdated was issued. */
  minutesRemaining: number;
  /** ISO timestamp for the reading that produced minutesRemaining. */
  anchor: string;
  className?: string;
}

/**
 * Counts down from (minutesRemaining) anchored at (anchor). Every second we
 * recompute from wall-clock so the timer stays honest across tab sleeps.
 */
export function CountdownTimer({ minutesRemaining, anchor, className }: Props) {
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    const id = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(id);
  }, []);

  const anchorMs = new Date(anchor).getTime();
  const elapsedMs = Math.max(0, now - anchorMs);
  const remainingMs = Math.max(0, minutesRemaining * 60_000 - elapsedMs);
  const totalSec = Math.floor(remainingMs / 1000);
  const mm = Math.floor(totalSec / 60);
  const ss = totalSec % 60;

  const urgent = remainingMs < 5 * 60_000;
  const spent = remainingMs === 0;

  return (
    <span
      className={clsx(
        'font-mono tabular-nums',
        spent ? 'text-red font-semibold' : urgent ? 'text-red' : 'text-text-primary',
        className,
      )}
    >
      {mm.toString().padStart(2, '0')}:{ss.toString().padStart(2, '0')}
    </span>
  );
}

export function ExcursionTimer({ secondsOutside, className }: { secondsOutside: number; className?: string }) {
  if (!secondsOutside) return <span className={clsx('text-text-secondary', className)}>—</span>;
  const mm = Math.floor(secondsOutside / 60);
  const ss = secondsOutside % 60;
  return (
    <span className={clsx('font-mono tabular-nums text-red', className)}>
      {mm.toString().padStart(2, '0')}:{ss.toString().padStart(2, '0')}
    </span>
  );
}
