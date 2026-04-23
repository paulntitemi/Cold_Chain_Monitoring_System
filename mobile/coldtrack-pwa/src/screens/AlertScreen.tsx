import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useMutation } from '@tanstack/react-query';
import { api } from '@/lib/apiClient';
import { useAlertStore } from '@/store/alertStore';
import { useTripStore } from '@/store/tripStore';
import { useWakeLock } from '@/hooks/useWakeLock';
import { vibrate, stopVibration, PATTERNS } from '@/lib/haptic';
import { cancelSpeech } from '@/lib/speech';
import { AlertOverlay } from '@/components/alert/AlertOverlay';
import { AlertActions } from '@/components/alert/AlertActions';
import { AlertVoicePlayer } from '@/components/alert/AlertVoicePlayer';
import { SafeForTimer } from '@/components/trip/SafeForTimer';
import { clsx } from 'clsx';

/**
 * Full-bleed red takeover. Voice + haptic + flashing border + countdown-to-
 * dispatch-call. Respects prefers-reduced-motion on the border pulse only;
 * the voice + haptic are safety-critical and always fire.
 */
export function AlertScreen() {
  const navigate = useNavigate();
  const activeAlert = useAlertStore((s) => s.activeAlert);
  const markSeen = useAlertStore((s) => s.markSeen);
  const clearAlert = useAlertStore((s) => s.setActiveAlert);
  const shipment = useTripStore((s) => s.shipment);

  const [cantRespond, setCantRespond] = useState(false);
  const [dispatchCountdown, setDispatchCountdown] = useState(120);

  useWakeLock(true);

  useEffect(() => {
    vibrate(PATTERNS.alert);
    const id = window.setInterval(() => setDispatchCountdown((s) => Math.max(0, s - 1)), 1000);
    return () => {
      window.clearInterval(id);
      stopVibration();
      cancelSpeech();
    };
  }, []);

  useEffect(() => {
    if (!activeAlert) navigate('/trip', { replace: true });
  }, [activeAlert, navigate]);

  const accept = useMutation({
    mutationFn: () => {
      if (!activeAlert) return Promise.reject(new Error('No alert'));
      return api.patchAlert(activeAlert.id, { riderResponse: 'accepted' });
    },
    onSuccess: () => {
      if (activeAlert) {
        markSeen(activeAlert.id);
        clearAlert(null);
      }
      void api.logIncident({
        shipmentId: activeAlert?.shipmentId ?? '',
        eventType: 'riderAccepted',
        detail: 'Rider accepted diversion',
      });
      cancelSpeech();
      stopVibration();
      navigate(`/divert/${activeAlert?.shipmentId}`, { replace: true });
    },
  });

  const reject = useMutation({
    mutationFn: () => {
      if (!activeAlert) return Promise.reject(new Error('No alert'));
      return api.patchAlert(activeAlert.id, { riderResponse: 'escalated' });
    },
    onSuccess: () => {
      setCantRespond(true);
      void api.logIncident({
        shipmentId: activeAlert?.shipmentId ?? '',
        eventType: 'riderIgnored',
        detail: "Rider tapped I can't — escalating to dispatch",
      });
    },
  });

  const script = useMemo(() => {
    if (!activeAlert) return '';
    const centre = activeAlert.recommendedCentre;
    const temp = shipment?.currentTemp ?? activeAlert.tempAtTrigger;
    if (centre) {
      return `Alert. Your cargo is at ${temp.toFixed(1)} degrees. Divert to ${centre.name}, ${centre.distanceKm?.toFixed(1)} kilometres, ${centre.estimatedMinutes} minutes away. Safe for ${activeAlert.remainingSafeMinutes} minutes.`;
    }
    return `Alert. Your cargo is at ${temp.toFixed(1)} degrees. Safe for ${activeAlert.remainingSafeMinutes} minutes.`;
  }, [activeAlert, shipment]);

  if (!activeAlert) return null;

  const isCritical = activeAlert.riskLevel === 'critical';
  const centre = activeAlert.recommendedCentre;
  const currentTemp = shipment?.currentTemp ?? activeAlert.tempAtTrigger;

  return (
    <AlertOverlay critical={isCritical}>
      <AlertVoicePlayer script={script} escalated={cantRespond} />

      <div className="flex-1 flex flex-col px-4 pt-3">
        <div className="text-red font-display font-bold text-5xl tracking-tight">
          {isCritical ? 'CRITICAL' : 'HIGH ALERT'}
        </div>
        <div className="text-red/80 font-mono text-xs uppercase tracking-[0.2em] mt-1">
          {activeAlert.id}
        </div>

        <div className="mt-5 text-text-primary font-body text-[22px] leading-snug">
          Your cargo is at{' '}
          <span className="font-display font-bold text-red">{currentTemp.toFixed(1)}°C</span>.
          {centre ? (
            <>
              {' '}Divert to{' '}
              <span className="font-display font-semibold text-teal">{centre.name}</span> —{' '}
              {centre.distanceKm?.toFixed(1)} km, {centre.estimatedMinutes} min away.
            </>
          ) : (
            ' Return to cold storage immediately.'
          )}
        </div>

        <div className="mt-3">
          <SafeForTimer remainingMinutes={activeAlert.remainingSafeMinutes} className="text-red" />
        </div>

        {cantRespond && (
          <div className="mt-4 border border-red bg-red-tint p-3 rounded-sm text-red text-sm font-body">
            Dispatch will call you now. Pull over safely.
          </div>
        )}

        <div className="flex-1" />

        <div
          className={clsx('mb-2 text-center font-mono text-[11px] uppercase tracking-wider', dispatchCountdown < 30 ? 'text-red' : 'text-text-secondary')}
        >
          Dispatch will call in{' '}
          <span className="tabular-nums font-semibold">
            {Math.floor(dispatchCountdown / 60)}:{String(dispatchCountdown % 60).padStart(2, '0')}
          </span>{' '}
          if no response
        </div>
        <div
          className="pb-2"
          style={{ paddingBottom: 'calc(env(safe-area-inset-bottom) + 0.5rem)' }}
        >
          <AlertActions
            onAccept={() => accept.mutate()}
            onReject={() => reject.mutate()}
            disabled={accept.isPending || reject.isPending}
          />
        </div>
      </div>
    </AlertOverlay>
  );
}
