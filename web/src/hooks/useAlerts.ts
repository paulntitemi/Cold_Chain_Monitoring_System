import { useQuery } from '@tanstack/react-query';
import { useEffect, useRef } from 'react';
import toast from 'react-hot-toast';
import { api } from '@/lib/apiClient';
import { useAlertsStore } from '@/store/alertsStore';
import { env } from '@/config/env';

const POLL_MS = 5000;

let sharedAudioCtx: AudioContext | null = null;
function playPing() {
  if (!env.enableAudioAlerts) return;
  try {
    sharedAudioCtx ??= new (window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext)();
    const ctx = sharedAudioCtx;
    if (ctx.state === 'suspended') ctx.resume();
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = 'sine';
    osc.frequency.value = 880;
    gain.gain.setValueAtTime(0.001, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.2, ctx.currentTime + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.35);
    osc.connect(gain).connect(ctx.destination);
    osc.start();
    osc.stop(ctx.currentTime + 0.4);
  } catch {
    // Audio blocked until user gesture — safe to ignore.
  }
}

export function useActiveAlerts() {
  const setAlerts = useAlertsStore((s) => s.setAlerts);
  const seenIds = useAlertsStore((s) => s.seenIds);
  const seenRef = useRef(seenIds);
  seenRef.current = seenIds;

  const query = useQuery({
    queryKey: ['alerts', 'active'],
    queryFn: api.getActiveAlerts,
    refetchInterval: POLL_MS,
    refetchIntervalInBackground: true,
  });

  useEffect(() => {
    if (!query.data) return;
    setAlerts(query.data);

    for (const a of query.data) {
      if (seenRef.current.has(a.id)) continue;
      if (a.riskLevel === 'critical') {
        document.title = '⚠️ CRITICAL — ColdTrack';
        playPing();
      }
    }
    const hasCritical = query.data.some(
      (a) => a.riskLevel === 'critical' && a.status === 'active',
    );
    if (!hasCritical) document.title = 'ColdTrack — Control Centre';
  }, [query.data, setAlerts]);

  useEffect(() => {
    // Show a one-shot toast for genuinely new critical alerts.
    if (!query.data) return;
    for (const a of query.data) {
      if (a.riskLevel === 'critical' && !seenRef.current.has(a.id)) {
        toast.error(`CRITICAL — ${a.shipmentId}`, {
          id: `alert-${a.id}`,
          duration: 8000,
        });
      }
    }
  }, [query.data]);

  return query;
}

export function useAlertHistory(params?: Record<string, string>) {
  return useQuery({
    queryKey: ['alerts', 'history', params ?? {}],
    queryFn: () => api.getAlerts(params),
    refetchInterval: 30_000,
  });
}
