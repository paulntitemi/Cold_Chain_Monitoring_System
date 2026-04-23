import { useNavigate, useParams } from 'react-router-dom';
import { useMyShipment } from '@/hooks/useMyShipment';
import { useAlertStore } from '@/store/alertStore';
import { StatusBar } from '@/components/layout/StatusBar';
import { ConnectivityBanner } from '@/components/trip/ConnectivityBanner';
import { HandoffForm } from '@/components/handoff/HandoffForm';

export function ColdStoreHandoffScreen() {
  const { shipmentId = '' } = useParams();
  const { data: shipment } = useMyShipment(true);
  const alert = useAlertStore((s) => s.activeAlert);
  const navigate = useNavigate();

  if (!shipment) {
    return <div className="min-h-screen flex items-center justify-center text-text-secondary">Loading…</div>;
  }

  return (
    <div className="min-h-screen flex flex-col" style={{ paddingTop: 'env(safe-area-inset-top)' }}>
      <StatusBar shipment={shipment} />
      <div className="p-4 flex-1 overflow-y-auto">
        <ConnectivityBanner />
        <h1 className="font-display font-semibold text-2xl mt-2">Cold store handoff</h1>
        <div className="text-text-secondary font-mono text-xs mt-1">
          {shipmentId} → {alert?.recommendedCentre?.name ?? 'Cold store'}
        </div>
        <p className="text-text-secondary text-sm mt-3">
          Hand the vials to a cold-store staff member and capture the transfer.
        </p>
        <div className="mt-4">
          <HandoffForm
            shipment={shipment}
            location="cold_store"
            coldStoreId={alert?.recommendedCentre?.id}
            onComplete={() => navigate(`/summary/${shipment.id}`, { replace: true })}
          />
        </div>
      </div>
    </div>
  );
}
