import { useQuery } from '@tanstack/react-query';
import { useEffect, useRef } from 'react';
import toast from 'react-hot-toast';
import { api } from '@/lib/apiClient';
import { useShipmentsStore } from '@/store/shipmentsStore';
import { useUiStore } from '@/store/uiStore';
import type { RiskLevel } from '@/types/shipment';

const POLL_MS = 5000;

interface PrevMeta {
  riskLevel: RiskLevel;
  destination: string;
  riderName: string;
  currentTemp: number;
}

function riskRose(prev: RiskLevel | undefined, next: RiskLevel): boolean {
  if (!prev) return next === 'high' || next === 'critical';
  const rank: Record<RiskLevel, number> = { safe: 0, warning: 1, high: 2, critical: 3 };
  return rank[next] > rank[prev] && (next === 'high' || next === 'critical');
}

function riskResolved(prev: RiskLevel | undefined, next: RiskLevel): boolean {
  if (!prev) return false;
  return (prev === 'high' || prev === 'critical' || prev === 'warning') && next === 'safe';
}

export function useShipments() {
  const setShipments = useShipmentsStore((s) => s.setShipments);
  const setConnectionOk = useUiStore((s) => s.setConnectionOk);
  const prevRef = useRef<Record<string, PrevMeta>>({});

  const query = useQuery({
    queryKey: ['fleet', 'active'],
    queryFn: api.getActiveFleet,
    refetchInterval: POLL_MS,
    refetchIntervalInBackground: true,
    retry: 2,
  });

  useEffect(() => {
    const data = query.data;
    if (!data) return;

    const prev = prevRef.current;
    const currentIds = new Set(data.map((s) => s.id));

    // Shipments that were active on the previous tick but are no longer on
    // the active list — these just arrived (or were aborted). Show a toast
    // so the operator sees the hand-off they were watching.
    for (const [id, meta] of Object.entries(prev)) {
      if (currentIds.has(id)) continue;
      const warm = meta.currentTemp > 8.0 || meta.currentTemp < 2.0;
      if (warm) {
        toast(
          `${id} — arrived WARM at ${meta.destination}\nOperator disposition required`,
          { id: `arrived-${id}`, duration: 6500, icon: '⚠️' },
        );
      } else {
        toast.success(`${id} — delivered safe to ${meta.destination}\nRider ${meta.riderName}`, {
          id: `arrived-${id}`,
          duration: 4500,
        });
      }
    }

    // Risk-level transitions for shipments still active.
    for (const s of data) {
      const priorRisk = prev[s.id]?.riskLevel;
      if (riskRose(priorRisk, s.riskLevel)) {
        toast.error(
          `${s.riskLevel.toUpperCase()} — ${s.id} (${s.riderName})\n${s.currentTemp}°C · risk ${Math.round(
            s.riskScore * 100,
          )}%`,
          { id: `risk-${s.id}`, duration: 6000 },
        );
      } else if (riskResolved(priorRisk, s.riskLevel)) {
        toast.success(`${s.id} — Resolved, back in safe range`, {
          id: `ok-${s.id}`,
          duration: 4000,
        });
      }
    }

    const nextSnapshot: Record<string, PrevMeta> = {};
    for (const s of data) {
      nextSnapshot[s.id] = {
        riskLevel: s.riskLevel,
        destination: s.destination,
        riderName: s.riderName,
        currentTemp: s.currentTemp,
      };
    }
    prevRef.current = nextSnapshot;

    setShipments(data);
  }, [query.data, setShipments]);

  useEffect(() => {
    setConnectionOk(!query.isError);
  }, [query.isError, setConnectionOk]);

  return query;
}
