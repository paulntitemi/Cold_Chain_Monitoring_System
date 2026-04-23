import { useNavigate } from 'react-router-dom';
import { format } from 'date-fns';
import { useMyAssignments } from '@/hooks/useMyAssignments';
import { useMyShipment } from '@/hooks/useMyShipment';
import { BottomNav } from '@/components/layout/BottomNav';
import { StatusBar } from '@/components/layout/StatusBar';
import { ConnectivityBanner } from '@/components/trip/ConnectivityBanner';
import { VVMBadge } from '@/components/ui/VVMBadge';
import { IconChip } from '@/components/ui/IconChip';
import { InstallPrompt } from '@/components/ui/InstallPrompt';
import { BigButton } from '@/components/ui/BigButton';

export function AssignmentsScreen() {
  const { data: assignments = [], isLoading } = useMyAssignments();
  const { data: shipment } = useMyShipment(false);
  const navigate = useNavigate();

  const hasActive = shipment && shipment.status === 'active';

  return (
    <div className="min-h-screen flex flex-col" style={{ paddingTop: 'env(safe-area-inset-top)' }}>
      <StatusBar shipment={shipment} />
      <div className="p-4 space-y-3">
        <ConnectivityBanner />
        <h1 className="font-display font-semibold text-2xl">Today's assignments</h1>
        <p className="text-text-secondary text-sm">
          Tap an assignment to verify the manifest and start the trip.
        </p>
      </div>

      <div className="flex-1 px-4 pb-4 space-y-3 overflow-y-auto">
        {hasActive && (
          <button
            onClick={() => navigate('/trip')}
            className="w-full text-left border border-teal/40 bg-teal/10 p-4 rounded-sm active:bg-teal/15"
          >
            <div className="text-teal font-display font-semibold uppercase tracking-wider text-xs">
              Live trip in progress
            </div>
            <div className="font-body text-text-primary mt-1">
              {shipment.origin} → {shipment.destination}
            </div>
            <div className="text-text-secondary font-mono text-xs mt-1">Tap to resume</div>
          </button>
        )}

        {isLoading && <div className="text-text-secondary font-mono text-xs">Loading…</div>}

        {!isLoading && assignments.length === 0 && !hasActive && (
          <div className="border border-border bg-bg-secondary p-6 rounded-sm text-center">
            <div className="font-display text-lg">No active assignments</div>
            <div className="text-text-secondary text-sm mt-1">
              Check back at your next shift.
            </div>
          </div>
        )}

        {!hasActive &&
          assignments.map((a) => {
            const primary = a.batches[0];
            return (
              <button
                key={a.shipmentId}
                onClick={() => navigate(`/manifest/${a.shipmentId}`)}
                className="w-full text-left border border-border bg-bg-card p-4 rounded-sm active:bg-bg-secondary transition-colors"
              >
                <div className="flex items-start justify-between gap-2">
                  <div className="flex-1">
                    <div className="flex items-center gap-2 mb-2 flex-wrap">
                      <div className="font-display font-semibold text-xl text-teal">
                        {primary.vaccineType}
                      </div>
                      <div className="font-mono text-text-secondary text-sm">
                        {primary.doseCount} doses
                      </div>
                      <VVMBadge stage={primary.vvmStatus} />
                    </div>
                    <div className="font-body text-base text-text-primary leading-tight">
                      {a.origin}
                      <span className="text-text-secondary"> → </span>
                      {a.destination}
                    </div>
                    <div className="flex items-center gap-2 mt-2">
                      <IconChip tone="teal">DISPATCH {format(new Date(a.dispatchAt), 'HH:mm')}</IconChip>
                      <IconChip>{a.batches.length} BATCH{a.batches.length > 1 ? 'ES' : ''}</IconChip>
                    </div>
                  </div>
                  <div className="text-teal text-2xl font-display font-semibold">›</div>
                </div>
              </button>
            );
          })}

        <InstallPrompt />

        {hasActive && (
          <BigButton variant="ghost" height="md" onClick={() => navigate('/trip')}>
            Resume live trip
          </BigButton>
        )}
      </div>
      <BottomNav />
    </div>
  );
}
