import { useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { useQuery, useMutation } from '@tanstack/react-query';
import { api } from '@/lib/apiClient';
import { vibrate, PATTERNS } from '@/lib/haptic';
import { primeVoice } from '@/lib/speech';
import { useMyAssignments } from '@/hooks/useMyAssignments';
import { useMyShipment } from '@/hooks/useMyShipment';
import { useTripStore } from '@/store/tripStore';
import { BigButton } from '@/components/ui/BigButton';
import { IconChip } from '@/components/ui/IconChip';
import { VVMBadge } from '@/components/ui/VVMBadge';
import { StatusBar } from '@/components/layout/StatusBar';
import { ConnectivityBanner } from '@/components/trip/ConnectivityBanner';
import { QrScanner } from '@/components/handoff/QrScanner';
import { clsx } from 'clsx';

export function ManifestScreen() {
  const { shipmentId = '' } = useParams();
  const navigate = useNavigate();
  const { data: assignments = [] } = useMyAssignments();
  const { data: shipment } = useMyShipment(false);
  const verified = useTripStore((s) => s.manifestVerifiedBatchIds);
  const markVerified = useTripStore((s) => s.markBatchVerified);
  const resetManifest = useTripStore((s) => s.resetManifest);

  const [scanningBatchId, setScanningBatchId] = useState<string | null>(null);
  const [scanError, setScanError] = useState<string | null>(null);

  const assignment = assignments.find((a) => a.shipmentId === shipmentId);

  const { data: batch } = useQuery({
    queryKey: ['batch', assignment?.batches[0]?.batchId],
    queryFn: () => api.getBatch(assignment!.batches[0].batchId),
    enabled: !!assignment,
  });

  const startTrip = useMutation({
    mutationFn: () => api.startShipment(shipmentId),
    onSuccess: () => {
      resetManifest();
      vibrate(PATTERNS.confirm);
      primeVoice();
      navigate('/trip');
    },
  });

  if (!assignment) {
    return (
      <div className="min-h-screen flex items-center justify-center text-text-secondary">
        Assignment not found.
      </div>
    );
  }

  const allVerified = assignment.batches.every((b) => verified.has(b.batchId));
  const tempNow = shipment?.currentTemp ?? batch?.maxSafeTemp ?? 0;
  const tempInRange =
    !!shipment &&
    shipment.currentTemp >= shipment.minSafeTemp &&
    shipment.currentTemp <= shipment.maxSafeTemp;

  const handleScanResult = (text: string) => {
    if (!scanningBatchId) return;
    if (text === scanningBatchId) {
      markVerified(scanningBatchId);
      vibrate(PATTERNS.confirm);
      setScanError(null);
    } else {
      vibrate(PATTERNS.warningTick);
      setScanError(`Mismatch — expected ${scanningBatchId}, got ${text}`);
    }
    setScanningBatchId(null);
  };

  return (
    <div className="min-h-screen flex flex-col" style={{ paddingTop: 'env(safe-area-inset-top)' }}>
      <StatusBar shipment={shipment} />
      <div className="p-4 space-y-3 flex-1 overflow-y-auto">
        <ConnectivityBanner />
        <button
          onClick={() => navigate(-1)}
          className="text-text-secondary font-mono text-xs uppercase tracking-wider"
        >
          ‹ Back
        </button>
        <div>
          <h1 className="font-display font-semibold text-2xl">Verify manifest</h1>
          <div className="text-text-secondary font-mono text-xs mt-1">
            {shipmentId}
          </div>
          <div className="text-text-primary mt-1">
            {assignment.origin} → {assignment.destination}
          </div>
        </div>

        <div className="space-y-3">
          {assignment.batches.map((b) => {
            const isVerified = verified.has(b.batchId);
            return (
              <div
                key={b.batchId}
                className={clsx(
                  'border p-3 rounded-sm bg-bg-card',
                  isVerified ? 'border-teal' : 'border-border',
                )}
              >
                <div className="flex items-center justify-between gap-2 mb-2">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="font-display font-semibold text-lg text-teal">
                      {b.vaccineType}
                    </span>
                    <span className="text-text-secondary font-mono text-sm">{b.doseCount} doses</span>
                    <VVMBadge stage={b.vvmStatus} />
                  </div>
                  {isVerified && <IconChip tone="teal">VERIFIED</IconChip>}
                </div>
                <div className="font-mono text-xs text-text-secondary break-all mb-3">{b.batchId}</div>
                <BigButton
                  height="md"
                  variant={isVerified ? 'ghost' : 'teal'}
                  onClick={() => {
                    setScanError(null);
                    setScanningBatchId(b.batchId);
                  }}
                >
                  {isVerified ? 'Re-scan' : 'Scan QR'}
                </BigButton>
              </div>
            );
          })}
        </div>

        {scanError && (
          <div className="border border-red bg-red-tint text-red text-sm p-3 font-mono rounded-sm">
            {scanError}
          </div>
        )}

        <div className="border border-border bg-bg-secondary p-4 rounded-sm space-y-1">
          <div className="text-text-secondary font-mono text-xs uppercase tracking-wider">
            Temp at loading
          </div>
          <div className="flex items-baseline justify-between">
            <div className={clsx('font-display font-bold text-3xl', tempInRange ? 'text-green' : 'text-amber')}>
              {tempNow.toFixed(1)}°C
            </div>
            <div className="font-mono text-xs text-text-secondary">
              {tempInRange ? '✓ within range' : '⚠ out of range'}
            </div>
          </div>
        </div>
      </div>

      <div
        className="p-4 border-t border-border bg-bg-secondary"
        style={{ paddingBottom: 'calc(env(safe-area-inset-bottom) + 1rem)' }}
      >
        <BigButton
          disabled={!allVerified || !tempInRange || startTrip.isPending}
          onClick={() => startTrip.mutate()}
        >
          {startTrip.isPending ? 'Starting…' : 'Start trip'}
        </BigButton>
      </div>

      {scanningBatchId && (
        <QrScanner
          onDecode={handleScanResult}
          onCancel={() => setScanningBatchId(null)}
        />
      )}
    </div>
  );
}
