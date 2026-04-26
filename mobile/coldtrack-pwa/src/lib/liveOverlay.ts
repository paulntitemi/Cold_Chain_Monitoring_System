import { env } from '@/config/env';
import type { Shipment, TemperatureReading } from '@/types/shipment';
import type { Alert } from '@/types/alert';

/**
 * Hybrid demo. The PWA otherwise runs entirely on mock data. When both
 * `VITE_LIVE_SHIPMENT_ID` and `VITE_LIVE_API_URL` are set:
 *
 *   - `getMyShipment()` returns the AWS-hosted live shipment instead
 *     of Jake's mock row.
 *   - `getMyAlerts()` returns the live alerts targeting that shipment.
 *   - `patchAlert()` writes through to AWS so the dashboard's next
 *     poll sees the change.
 *
 * Failure mode is silent fallback to mock — never empty state.
 */

export function liveOverlayActive(): boolean {
  return !!env.liveShipmentId && !!env.liveApiUrl;
}

const HISTORY_CAP = 200;
const localHistory = new Map<string, TemperatureReading[]>();

function appendReading(id: string, ts: string, temp: number) {
  const list = localHistory.get(id) ?? [];
  if (list.length > 0 && list[list.length - 1].timestamp === ts) return list;
  list.push({ timestamp: ts, temperature: temp });
  if (list.length > HISTORY_CAP) list.splice(0, list.length - HISTORY_CAP);
  localHistory.set(id, list);
  return list;
}

async function liveFetch<T>(path: string): Promise<T | null> {
  if (!liveOverlayActive()) return null;
  const url = `${env.liveApiUrl.replace(/\/$/, '')}${path}`;
  try {
    const res = await fetch(url, {
      headers: { 'Content-Type': 'application/json' },
    });
    if (!res.ok) return null;
    return (await res.json()) as T;
  } catch {
    return null;
  }
}

export async function fetchLiveShipment(): Promise<Shipment | null> {
  const id = env.liveShipmentId;
  const live = await liveFetch<Shipment | null>(`/shipments/${id}`);
  if (!live) return null;
  const history = appendReading(id, live.lastUpdated, live.currentTemp);
  return {
    ...live,
    temperatureHistory:
      live.temperatureHistory && live.temperatureHistory.length > 0
        ? live.temperatureHistory
        : history,
    incidentLog: live.incidentLog ?? [],
    batchIds: live.batchIds ?? [],
  };
}

export async function fetchLiveAlertsForShipment(): Promise<Alert[]> {
  const all = await liveFetch<Alert[]>('/alerts/active');
  if (!all) return [];
  return all.filter((a) => a.shipmentId === env.liveShipmentId);
}

export async function patchLiveAlert(alertId: string, patch: Partial<Alert>): Promise<Alert | null> {
  if (!liveOverlayActive()) return null;
  const url = `${env.liveApiUrl.replace(/\/$/, '')}/alerts/${alertId}`;
  try {
    const res = await fetch(url, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(patch),
    });
    if (!res.ok) return null;
    return (await res.json()) as Alert;
  } catch {
    return null;
  }
}
