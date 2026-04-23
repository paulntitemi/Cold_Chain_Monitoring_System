import { Link } from 'react-router-dom';
import { useAlertsStore } from '@/store/alertsStore';
import { AlertFeedItem } from '@/components/alerts/AlertFeedItem';

export function AlertsPanel() {
  const alerts = useAlertsStore((s) => s.alerts);
  const unread = useAlertsStore((s) => s.unreadCount());

  const active = alerts
    .filter((a) => a.status === 'active' || a.status === 'escalated')
    .sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime())
    .slice(0, 20);

  return (
    <aside className="w-[360px] flex-none border-l border-border bg-bg-secondary flex flex-col h-full">
      <header className="flex items-center justify-between border-b border-border px-4 py-3">
        <div className="flex items-center gap-2">
          <h2 className="font-display text-sm font-semibold tracking-wider uppercase text-text-primary">
            Live Alerts
          </h2>
          {unread > 0 && (
            <span className="rounded-sm bg-red px-1.5 py-0.5 text-[10px] font-semibold font-mono text-white">
              {unread}
            </span>
          )}
        </div>
        <span className="text-[10px] uppercase tracking-widest text-text-secondary">
          {active.length} active
        </span>
      </header>

      <div className="flex-1 overflow-y-auto p-2 space-y-2">
        {active.length === 0 ? (
          <div className="flex h-full items-center justify-center text-center px-6">
            <div>
              <div className="font-display text-lg text-green">All Safe</div>
              <div className="text-xs text-text-secondary mt-1">
                No active alerts across the fleet.
              </div>
            </div>
          </div>
        ) : (
          active.map((a) => <AlertFeedItem key={a.id} alert={a} />)
        )}
      </div>

      <footer className="border-t border-border px-4 py-2">
        <Link
          to="/alerts"
          className="text-[11px] uppercase tracking-widest text-teal hover:underline"
        >
          View Full History →
        </Link>
      </footer>
    </aside>
  );
}
