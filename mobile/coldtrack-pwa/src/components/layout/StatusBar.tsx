import { useEffect, useState } from 'react';
import { clsx } from 'clsx';
import { useOnline } from '@/hooks/useOnline';
import type { Shipment } from '@/types/shipment';
import { formatDistanceToNowStrict } from 'date-fns';

interface Props {
  shipment?: Shipment | null;
  tripStartedAt?: string;
}

function useBattery() {
  const [level, setLevel] = useState<number | null>(null);
  useEffect(() => {
    const n = navigator as Navigator & {
      getBattery?: () => Promise<{ level: number; addEventListener: (t: string, cb: () => void) => void }>;
    };
    if (!n.getBattery) return;
    let mounted = true;
    void n.getBattery().then((b) => {
      if (!mounted) return;
      setLevel(b.level);
      b.addEventListener('levelchange', () => setLevel(b.level));
    });
    return () => {
      mounted = false;
    };
  }, []);
  return level;
}

export function StatusBar({ shipment, tripStartedAt }: Props) {
  const online = useOnline();
  const battery = useBattery();

  const deviceOk = shipment ? Date.now() - new Date(shipment.lastUpdated).getTime() < 60_000 : false;

  return (
    <div className="h-12 px-4 flex items-center justify-between border-b border-border bg-bg-secondary text-[11px] font-mono uppercase tracking-wider">
      <div className="flex items-center gap-3">
        <span className={clsx('flex items-center gap-1', online ? 'text-green' : 'text-amber')}>
          <span
            className={clsx(
              'inline-block w-1.5 h-1.5 rounded-full',
              online ? 'bg-green' : 'bg-amber animate-pulse',
            )}
          />
          {online ? 'Online' : 'Offline'}
        </span>
        <span className={clsx('flex items-center gap-1', deviceOk ? 'text-teal' : 'text-text-secondary')}>
          <span className={clsx('inline-block w-1.5 h-1.5 rounded-full', deviceOk ? 'bg-teal' : 'bg-text-dim')} />
          IoT
        </span>
      </div>
      <div className="flex items-center gap-3 text-text-secondary">
        {tripStartedAt && (
          <span className="text-text-primary">
            {formatDistanceToNowStrict(new Date(tripStartedAt), { unit: 'minute' })}
          </span>
        )}
        {battery !== null && <span>{Math.round(battery * 100)}%</span>}
      </div>
    </div>
  );
}
