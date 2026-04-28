import { useLocation, useParams } from 'react-router-dom';
import { format } from 'date-fns';
import { useEffect, useState } from 'react';
import { ConnectionStatus } from '@/components/ui/ConnectionStatus';

const titleByPath: Record<string, string> = {
  '/dashboard': 'Fleet Overview',
  '/batches': 'Batch Registry',
  '/alerts': 'Alert History',
};

export function TopBar() {
  const location = useLocation();
  const params = useParams();
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const id = window.setInterval(() => setNow(new Date()), 1000);
    return () => window.clearInterval(id);
  }, []);

  let title = titleByPath[location.pathname] ?? 'Dashboard';
  if (location.pathname.startsWith('/shipments/') && params.id) {
    title = `Shipment · ${params.id}`;
  }

  return (
    <header className="h-12 flex-none border-b border-border bg-bg-secondary flex items-center gap-4 px-5">
      <div className="flex items-center gap-2">
        <span className="text-[10px] uppercase tracking-widest text-text-secondary">
          Control Centre
        </span>
        <span className="text-text-dim">/</span>
        <span className="font-display text-sm font-semibold uppercase tracking-wider text-text-primary">
          {title}
        </span>
      </div>

      <div className="flex-1" />

      <div className="font-mono text-[11px] text-text-secondary tabular-nums">
        {format(now, 'EEE dd MMM · HH:mm:ss')}
      </div>
      <a
        href="https://coldtrack.grafana.net/public-dashboards/483d4dd50e5f4fe4ba1727e68ec21e1a"
        target="_blank"
        rel="noopener noreferrer"
        className="flex items-center gap-1.5 rounded-sm border border-amber/40 bg-amber/10 px-2.5 py-1 text-[11px] font-mono uppercase tracking-wider text-amber hover:bg-amber/20 hover:border-amber/60 transition-colors"
        title="Open Grafana analytics dashboard in a new tab"
      >
        <span aria-hidden>📊</span>
        Analytics
        <span className="text-amber/60" aria-hidden>↗</span>
      </a>
      <ConnectionStatus />
      <div className="flex items-center gap-2 rounded-sm border border-border bg-bg-card px-3 py-1.5">
        <div className="h-5 w-5 rounded-full bg-teal/30 flex items-center justify-center text-[10px] font-bold text-teal">
          O
        </div>
        <div className="text-[11px]">
          <div className="text-text-primary leading-tight">Operator Desk</div>
          <div className="text-text-secondary leading-tight">london-ops-1</div>
        </div>
      </div>
    </header>
  );
}
