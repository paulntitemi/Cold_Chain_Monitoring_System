import { useMemo } from 'react';
import { useShipmentsStore, sortedByRisk } from '@/store/shipmentsStore';
import { useAlertsStore } from '@/store/alertsStore';
import { useUiStore } from '@/store/uiStore';
import { ShipmentRow } from './ShipmentRow';
import { api } from '@/lib/apiClient';
import toast from 'react-hot-toast';
import { useQueryClient } from '@tanstack/react-query';

const headers = [
  'STATUS',
  'SHIPMENT ID',
  'RIDER',
  'BATCHES',
  'TEMP',
  'RISK',
  'SAFE FOR',
  'EXCURSION',
  'ROUTE',
  'ALERT STATUS',
  'HISTORY',
  'ACTIONS',
];

export function ShipmentTable() {
  const shipments = useShipmentsStore((s) => s.shipments);
  const alerts = useAlertsStore((s) => s.alerts);
  const selectedId = useUiStore((s) => s.selectedShipmentId);
  const open = useUiStore((s) => s.openDetailPanel);
  const qc = useQueryClient();

  const sorted = useMemo(() => sortedByRisk(shipments), [shipments]);
  const alertByShipment = useMemo(() => {
    const m = new Map<string, typeof alerts[number]>();
    for (const a of alerts) {
      if (a.status === 'active') m.set(a.shipmentId, a);
    }
    return m;
  }, [alerts]);

  return (
    <div className="flex min-h-0 flex-1 flex-col border-t border-border">
      <div className="flex items-center justify-between border-b border-border bg-bg-secondary px-4 py-2">
        <h3 className="font-display text-sm font-semibold uppercase tracking-wider text-text-primary">
          Active Shipments
        </h3>
        <span className="text-[10px] uppercase tracking-widest text-text-secondary">
          {sorted.length} {sorted.length === 1 ? 'shipment' : 'shipments'}
        </span>
      </div>
      <div className="flex-1 overflow-auto">
        <table className="w-full border-collapse text-sm">
          <thead className="sticky top-0 z-10 bg-bg-secondary">
            <tr className="text-left">
              {headers.map((h) => (
                <th
                  key={h}
                  className="border-b border-border px-2 py-2 text-[10px] font-semibold uppercase tracking-widest text-text-secondary"
                >
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {sorted.map((s) => (
              <ShipmentRow
                key={s.id}
                shipment={s}
                alert={alertByShipment.get(s.id)}
                selected={selectedId === s.id}
                onSelect={() => open(s.id)}
                onCall={() => {
                  window.location.href = `tel:${s.riderPhone}`;
                }}
                onEscalate={async () => {
                  const a = alertByShipment.get(s.id);
                  if (!a) {
                    toast(`No active alert on ${s.id}`, { icon: 'ℹ️' });
                    return;
                  }
                  await api.patchAlert(a.id, { status: 'escalated' });
                  toast.success(`Escalated ${s.id}`);
                  qc.invalidateQueries({ queryKey: ['alerts'] });
                }}
              />
            ))}
            {sorted.length === 0 && (
              <tr>
                <td
                  colSpan={headers.length}
                  className="py-8 text-center text-sm text-text-secondary"
                >
                  No active shipments.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
