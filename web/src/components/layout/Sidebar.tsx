import clsx from 'clsx';
import { NavLink } from 'react-router-dom';
import { useShipmentsStore } from '@/store/shipmentsStore';
import { useAlertsStore } from '@/store/alertsStore';

const items = [
  { to: '/dashboard', label: 'Fleet Overview', icon: '🛰' },
  { to: '/batches', label: 'Batch Registry', icon: '💉' },
  { to: '/alerts', label: 'Alert History', icon: '⚠' },
];

export function Sidebar() {
  const total = useShipmentsStore((s) => s.shipments.length);
  const critical = useShipmentsStore((s) =>
    s.shipments.filter((x) => x.riskLevel === 'critical').length,
  );
  const high = useShipmentsStore((s) =>
    s.shipments.filter((x) => x.riskLevel === 'high').length,
  );
  const activeAlerts = useAlertsStore((s) =>
    s.alerts.filter((a) => a.status === 'active').length,
  );

  return (
    <aside className="w-[240px] flex-none border-r border-border bg-bg-secondary flex flex-col">
      <div className="px-5 py-5 border-b border-border">
        <div className="font-display text-xl font-bold tracking-widest text-teal">
          COLDTRACK
        </div>
        <div className="text-[10px] uppercase tracking-[0.22em] text-text-secondary mt-0.5">
          Control Centre
        </div>
      </div>

      <nav className="flex-1 px-2 py-3 space-y-1">
        {items.map((i) => (
          <NavLink
            key={i.to}
            to={i.to}
            className={({ isActive }) =>
              clsx(
                'flex items-center gap-3 rounded-sm border px-3 py-2 text-sm transition-colors',
                isActive
                  ? 'border-teal/40 bg-teal/10 text-teal'
                  : 'border-transparent text-text-secondary hover:text-text-primary hover:bg-bg-card',
              )
            }
          >
            <span className="text-base">{i.icon}</span>
            <span className="flex-1">{i.label}</span>
            {i.to === '/alerts' && activeAlerts > 0 && (
              <span className="rounded-sm bg-red/20 px-1.5 text-[10px] text-red font-mono">
                {activeAlerts}
              </span>
            )}
          </NavLink>
        ))}
      </nav>

      <div className="border-t border-border px-4 py-4 space-y-3">
        <div>
          <div className="text-[10px] uppercase tracking-widest text-text-secondary">
            System status
          </div>
          <div className="mt-1 flex items-center gap-2">
            <span className="h-1.5 w-1.5 rounded-full bg-green animate-pulse" />
            <span className="text-xs text-green">All systems nominal</span>
          </div>
        </div>
        <div className="space-y-1 text-xs">
          <SidebarStat label="Active shipments" value={total} />
          <SidebarStat label="Critical" value={critical} tone={critical ? 'red' : 'default'} />
          <SidebarStat label="High" value={high} tone={high ? 'red' : 'default'} />
          <SidebarStat label="Active alerts" value={activeAlerts} tone={activeAlerts ? 'amber' : 'default'} />
        </div>
        <div className="pt-2 text-[10px] font-mono text-text-dim">v0.1.0 · build mock</div>
      </div>
    </aside>
  );
}

function SidebarStat({
  label,
  value,
  tone = 'default',
}: {
  label: string;
  value: number;
  tone?: 'default' | 'red' | 'amber';
}) {
  return (
    <div className="flex items-center justify-between">
      <span className="text-text-secondary">{label}</span>
      <span
        className={clsx(
          'font-display text-sm font-semibold',
          tone === 'red' && 'text-red',
          tone === 'amber' && 'text-amber',
          tone === 'default' && 'text-text-primary',
        )}
      >
        {value}
      </span>
    </div>
  );
}
