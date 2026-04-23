import { useCallback, useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useMyShipment } from '@/hooks/useMyShipment';
import { useMyAlerts } from '@/hooks/useMyAlerts';
import { useGeolocationReporting } from '@/hooks/useGeolocationReporting';
import { useWakeLock } from '@/hooks/useWakeLock';
import { useAlertStore } from '@/store/alertStore';
import { vibrate, PATTERNS } from '@/lib/haptic';
import { StatusBar } from '@/components/layout/StatusBar';
import { ConnectivityBanner } from '@/components/trip/ConnectivityBanner';
import { RiskGauge } from '@/components/trip/RiskGauge';
import { SafeForTimer } from '@/components/trip/SafeForTimer';
import { TripMap, type RouteInfo } from '@/components/trip/TripMap';
import { InstructionCard } from '@/components/trip/InstructionCard';
import { BigButton } from '@/components/ui/BigButton';

export function LiveTripScreen() {
  const navigate = useNavigate();
  const { data: shipment } = useMyShipment(true);
  useMyAlerts(true);
  const activeAlert = useAlertStore((s) => s.activeAlert);
  const prevLevel = useRef<string | null>(null);
  const [routeInfo, setRouteInfo] = useState<RouteInfo | null>(null);
  const [navMode, setNavMode] = useState(false);
  const handleRouteInfo = useCallback((info: RouteInfo) => setRouteInfo(info), []);
  const exitNavMode = useCallback(() => setNavMode(false), []);

  useWakeLock(true);
  useGeolocationReporting(shipment?.id, shipment?.status === 'active');

  // Lock orientation if supported (manifest already sets this; this is defence in depth).
  useEffect(() => {
    const orient = (screen as Screen & { orientation?: { lock?: (o: string) => Promise<void> } }).orientation;
    if (orient?.lock) {
      void orient.lock('portrait').catch(() => {
        // ignore — browsers without PWA install can't honour this
      });
    }
  }, []);

  // Haptic + tone shift on risk level transitions.
  useEffect(() => {
    if (!shipment) return;
    if (prevLevel.current && prevLevel.current !== shipment.riskLevel) {
      if (shipment.riskLevel === 'warning') vibrate(PATTERNS.warningTick);
    }
    prevLevel.current = shipment.riskLevel;
  }, [shipment?.riskLevel, shipment]);

  // When a new active alert lands, the alert store will have it — navigate.
  useEffect(() => {
    if (activeAlert) {
      navigate('/alert', { replace: false });
    }
  }, [activeAlert, navigate]);

  // Post-delivery: if the shipment completed, jump to handoff or summary.
  useEffect(() => {
    if (shipment?.status === 'completed') {
      navigate(`/summary/${shipment.id}`, { replace: true });
    }
  }, [shipment?.status, shipment?.id, navigate]);

  if (!shipment) {
    return (
      <div className="min-h-screen flex items-center justify-center text-text-secondary">
        No active trip.
      </div>
    );
  }

  const topTone =
    shipment.riskLevel === 'warning'
      ? 'bg-amber/20 border-amber/40 text-amber'
      : shipment.riskLevel === 'high' || shipment.riskLevel === 'critical'
      ? 'bg-red-tint border-red/60 text-red'
      : '';

  return (
    <div
      className="flex flex-col overflow-hidden"
      style={{ height: '100dvh', paddingTop: 'env(safe-area-inset-top)' }}
    >
      <StatusBar shipment={shipment} tripStartedAt={shipment.startTime} />
      <div className={`${topTone} transition-colors`}>
        <ConnectivityBanner />
      </div>

      <div className="flex flex-col flex-1 min-h-0">
        {/* Risk zone — collapses in nav mode to give the map more room. */}
        {!navMode && (
          <div className="flex-none">
            <RiskGauge
              score={shipment.riskScore}
              level={shipment.riskLevel}
              temperature={shipment.currentTemp}
            />
            <div className="pt-2 pb-3 text-center">
              <SafeForTimer remainingMinutes={shipment.remainingSafeMinutes} />
            </div>
          </div>
        )}

        {/* Map zone — flexes to fill */}
        <div className="flex-1 min-h-0 border-t border-border relative">
          <TripMap
            rider={shipment.currentLocation}
            destination={shipment.destinationLocation}
            onRouteInfo={handleRouteInfo}
            navMode={navMode}
            onExitNavMode={exitNavMode}
          />

          {/* Top-anchored: in nav mode, the turn-by-turn card. Otherwise the
              compact ETA pill. */}
          {navMode ? (
            <div className="absolute top-2 left-2 right-2">
              <InstructionCard info={routeInfo} onClose={exitNavMode} />
            </div>
          ) : (
            <div className="absolute top-2 left-2 bg-bg-primary/80 border border-border px-2 py-1 rounded-sm">
              <div className="font-mono text-[10px] uppercase tracking-wider text-text-secondary">
                ETA
              </div>
              <div className="font-display font-semibold text-sm text-teal">
                {routeInfo
                  ? routeInfo.durationText
                  : new Date(shipment.estimatedArrival).toLocaleTimeString([], {
                      hour: '2-digit',
                      minute: '2-digit',
                    })}
              </div>
              {routeInfo && (
                <div className="font-mono text-[10px] text-text-secondary">{routeInfo.distanceText}</div>
              )}
            </div>
          )}

          {/* In nav mode, show a small compact risk pill so the rider still
              sees temperature + safe-for at a glance. */}
          {navMode && (
            <div className="absolute bottom-2 right-2 bg-bg-primary/85 border border-border px-2 py-1 rounded-sm flex items-center gap-2">
              <span className="font-display font-bold text-teal tabular-nums text-xl">
                {shipment.currentTemp.toFixed(1)}°C
              </span>
              <SafeForTimer remainingMinutes={shipment.remainingSafeMinutes} />
            </div>
          )}
        </div>

        {/* Action strip */}
        <div
          className="border-t border-border bg-bg-secondary p-3 grid grid-cols-3 gap-2"
          style={{ paddingBottom: 'calc(env(safe-area-inset-bottom) + 0.75rem)' }}
        >
          <BigButton
            variant="ghost"
            height="lg"
            onClick={() => {
              window.location.href = `tel:+442071887188`;
            }}
          >
            ☎
          </BigButton>
          <BigButton
            variant={navMode ? 'amber' : 'teal'}
            height="lg"
            onClick={() => setNavMode((v) => !v)}
          >
            {navMode ? '✕ Exit nav' : '🧭 Navigate'}
          </BigButton>
          <BigButton
            variant="ghost"
            height="lg"
            onClick={() => {
              if (!shipment.destinationLocation) return;
              const { lat, lng } = shipment.destinationLocation;
              window.location.href = `https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}&travelmode=driving`;
            }}
          >
            Maps↗
          </BigButton>
        </div>

        {!navMode && (
          <div className="px-4 pb-2 text-center text-text-secondary text-xs font-mono">
            Heading to {shipment.destination}
          </div>
        )}
      </div>
    </div>
  );
}
