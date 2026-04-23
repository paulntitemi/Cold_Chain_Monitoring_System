import { format } from 'date-fns';
import { useQuery } from '@tanstack/react-query';
import { api } from '@/lib/apiClient';
import { useAuthStore } from '@/store/authStore';
import { mockPastTrips } from '@/mock/mockData';
import { BottomNav } from '@/components/layout/BottomNav';
import { StatusBar } from '@/components/layout/StatusBar';
import { ConnectivityBanner } from '@/components/trip/ConnectivityBanner';
import { IconChip } from '@/components/ui/IconChip';
import { clsx } from 'clsx';

export function ProfileScreen() {
  const storeRider = useAuthStore((s) => s.rider);
  const { data: rider = storeRider } = useQuery({ queryKey: ['me'], queryFn: api.getMe });

  if (!rider) {
    return <div className="min-h-screen flex items-center justify-center text-text-secondary">Loading…</div>;
  }

  const responsePct = Math.round(rider.alertResponseRate * 100);
  const responseLow = responsePct < 80;

  return (
    <div className="min-h-screen flex flex-col" style={{ paddingTop: 'env(safe-area-inset-top)' }}>
      <StatusBar />
      <div className="p-4 flex-1 overflow-y-auto space-y-4">
        <ConnectivityBanner />

        <div className="flex items-center gap-3">
          <div className="w-14 h-14 rounded-full bg-teal/15 border border-teal/40 flex items-center justify-center text-teal font-display font-bold text-xl">
            {rider.name
              .split(' ')
              .map((n) => n[0])
              .join('')
              .slice(0, 2)}
          </div>
          <div>
            <div className="font-display font-semibold text-xl">{rider.name}</div>
            <div className="text-text-secondary font-mono text-xs uppercase tracking-wider">
              {rider.id} · {rider.vehicleType}
            </div>
          </div>
        </div>

        <div className="grid grid-cols-3 gap-2">
          <IconChip>
            <span className="text-text-primary font-display font-semibold text-base">{rider.totalTrips}</span>
            <span className="ml-1">trips</span>
          </IconChip>
          <IconChip>
            <span className="text-text-primary font-display font-semibold text-base">{mockPastTrips.reduce((s, t) => s + t.doseCount, 0)}</span>
            <span className="ml-1">doses</span>
          </IconChip>
          <IconChip tone="teal">
            <span className="font-display font-semibold text-base">97%</span>
            <span className="ml-1">on-time</span>
          </IconChip>
        </div>

        <div
          className={clsx(
            'border p-4 rounded-sm',
            responseLow ? 'border-red bg-red-tint' : 'border-green/40 bg-green/10',
          )}
        >
          <div
            className={clsx(
              'font-mono text-[11px] uppercase tracking-wider',
              responseLow ? 'text-red' : 'text-green',
            )}
          >
            Alert response rate
          </div>
          <div className={clsx('font-display font-bold text-4xl mt-1', responseLow ? 'text-red' : 'text-green')}>
            {responsePct}%
          </div>
          {responseLow && (
            <p className="text-red/90 text-sm mt-2 leading-snug">
              You missed {Math.round(rider.totalTrips * (1 - rider.alertResponseRate))} of {rider.totalTrips} alerts this month. Each missed alert risked ~300 doses.
            </p>
          )}
        </div>

        <div className="border border-border bg-bg-card rounded-sm">
          <div className="px-3 py-2 border-b border-border text-text-secondary font-mono text-[11px] uppercase tracking-wider">
            Recent trips
          </div>
          <ul className="divide-y divide-border">
            {mockPastTrips.map((t) => (
              <li key={t.id} className="px-3 py-3 flex items-start justify-between gap-2">
                <div className="flex-1">
                  <div className="font-body text-sm text-text-primary">
                    {t.origin} → {t.destination}
                  </div>
                  <div className="font-mono text-[10px] uppercase tracking-wider text-text-secondary mt-0.5">
                    {format(new Date(t.completedAt), 'MMM d, HH:mm')} · {t.doseCount} doses · {t.outcome.replace(/_/g, ' ')}
                  </div>
                </div>
              </li>
            ))}
          </ul>
        </div>
      </div>
      <BottomNav />
    </div>
  );
}
