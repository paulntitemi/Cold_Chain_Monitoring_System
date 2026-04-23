import { useNavigate, useParams } from 'react-router-dom';
import { useMyShipment } from '@/hooks/useMyShipment';
import { StatusBar } from '@/components/layout/StatusBar';
import { ConnectivityBanner } from '@/components/trip/ConnectivityBanner';
import { HandoffForm } from '@/components/handoff/HandoffForm';

export function DestinationHandoffScreen() {
  const { shipmentId = '' } = useParams();
  const { data: shipment } = useMyShipment(true);
  const navigate = useNavigate();

  if (!shipment) {
    return <div className="min-h-screen flex items-center justify-center text-text-secondary">Loading…</div>;
  }

  return (
    <div className="min-h-screen flex flex-col" style={{ paddingTop: 'env(safe-area-inset-top)' }}>
      <StatusBar shipment={shipment} />
      <div className="p-4 flex-1 overflow-y-auto">
        <ConnectivityBanner />
        <h1 className="font-display font-semibold text-2xl mt-2">Destination handoff</h1>
        <div className="text-text-secondary font-mono text-xs mt-1">
          {shipmentId} → {shipment.destination}
        </div>
        <p className="text-text-secondary text-sm mt-3">
          Complete delivery by handing the vials to the receiving clinician.
        </p>
        <div className="mt-4">
          <HandoffForm
            shipment={shipment}
            location="destination"
            offerSignature
            onComplete={() => navigate(`/summary/${shipment.id}`, { replace: true })}
          />
        </div>
      </div>
    </div>
  );
}
