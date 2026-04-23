import { useMemo } from 'react';
import { useShipmentsStore } from '@/store/shipmentsStore';
import { useBatches } from '@/hooks/useBatches';
import { StatusPill } from '@/components/ui/StatusPill';
import { FleetMap } from '@/components/map/FleetMap';
import { ShipmentTable } from '@/components/shipments/ShipmentTable';

export function FleetOverview() {
  const shipments = useShipmentsStore((s) => s.shipments);
  const { data: batches } = useBatches();

  const stats = useMemo(() => {
    const safe = shipments.filter((s) => s.riskLevel === 'safe').length;
    const warning = shipments.filter((s) => s.riskLevel === 'warning').length;
    const high = shipments.filter((s) => s.riskLevel === 'high').length;
    const critical = shipments.filter((s) => s.riskLevel === 'critical').length;

    const inTransitBatchIds = new Set(shipments.flatMap((s) => s.batchIds));
    const doses = (batches ?? [])
      .filter((b) => inTransitBatchIds.has(b.batchId))
      .reduce((acc, b) => acc + b.dosesRemaining, 0);

    return { total: shipments.length, safe, warning, high, critical, doses };
  }, [shipments, batches]);

  return (
    <div className="flex flex-1 flex-col min-h-0">
      <div className="flex h-20 flex-none items-center gap-3 border-b border-border bg-bg-secondary px-5">
        <StatusPill label="Active shipments" value={stats.total} />
        <StatusPill label="In safe range" value={stats.safe} tone="green" />
        <StatusPill
          label="Warning"
          value={stats.warning}
          tone="amber"
          pulse={stats.warning ? 'amber' : null}
        />
        <StatusPill
          label="Critical"
          value={stats.critical + stats.high}
          tone="red"
          pulse={stats.critical || stats.high ? 'red' : null}
        />
        <StatusPill
          label="Doses in transit"
          value={stats.doses.toLocaleString()}
          tone="teal"
        />
      </div>

      <div className="flex min-h-0 flex-1 flex-col">
        <div className="flex-1 min-h-[360px] border-b border-border">
          <FleetMap />
        </div>
        <div className="flex-1 min-h-[320px] flex flex-col">
          <ShipmentTable />
        </div>
      </div>
    </div>
  );
}
