import { env } from '@/config/env';
import type { Shipment, TemperatureReading } from '@/types/shipment';
import type { Alert } from '@/types/alert';

/**
 * Hybrid-demo helper. The dashboard runs in mock mode for visual richness,
 * but one specific shipment id is transparently overlaid with live data
 * from the AWS API Gateway URL. Lets us show a fleet of 8 simulated rides
 * alongside the ONE physical sensor that's actually on the table at an
 * exhibition.
 *
 * Activation: set both VITE_LIVE_SHIPMENT_ID and VITE_LIVE_API_URL.
 * Inactive: nothing in this module fires; mock data flows untouched.
 *
 * Failure mode: if AWS is unreachable, we silently fall through to the
 * mock row — never the empty state. The demo never goes blank because of
 * a flaky tunnel or expired token.
 */

export function liveOverlayActive(): boolean {
  return !!env.liveShipmentId && !!env.liveApiUrl;
}

const HISTORY_CAP = 200;
const localHistory = new Map<string, TemperatureReading[]>();

function appendReading(shipmentId: string, ts: string, temp: number, humidity?: number) {
  const list = localHistory.get(shipmentId) ?? [];
  // Skip duplicates (same poll, same lastUpdated string).
  if (list.length > 0 && list[list.length - 1].timestamp === ts) return list;
  list.push({ timestamp: ts, temperature: temp, humidity });
  if (list.length > HISTORY_CAP) list.splice(0, list.length - HISTORY_CAP);
  localHistory.set(shipmentId, list);
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

  // Accumulate temperature history client-side: even if the backend doesn't
  // hydrate `temperatureHistory` from InfluxDB, the sparkline still grows
  // every poll cycle.
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

export async function fetchLiveAlertsForShipment(shipmentId: string): Promise<Alert[]> {
  // The /alerts/active endpoint returns ALL active alerts; filter to just
  // those targeting our live shipment. Cheaper than a per-shipment endpoint.
  const all = await liveFetch<Alert[]>('/alerts/active');
  if (!all) return [];
  return all.filter((a) => a.shipmentId === shipmentId);
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

/**
 * Replace (or append) the live shipment in a mock fleet. If a mock row with
 * the same id exists, swap it. Otherwise prepend so the live carrier shows
 * at the top of the dashboard.
 */
export function overlayShipmentInto(fleet: Shipment[], live: Shipment): Shipment[] {
  const idx = fleet.findIndex((s) => s.id === live.id);
  if (idx >= 0) {
    const next = fleet.slice();
    next[idx] = live;
    return next;
  }
  return [live, ...fleet];
}

/**
 * Merge live alerts into a mock alert list. Replaces alerts with the same
 * id; appends ones that don't exist in mock.
 */
export function overlayAlertsInto(alerts: Alert[], live: Alert[]): Alert[] {
  const out = alerts.slice();
  for (const a of live) {
    const idx = out.findIndex((x) => x.id === a.id);
    if (idx >= 0) out[idx] = a;
    else out.unshift(a);
  }
  return out;
}
