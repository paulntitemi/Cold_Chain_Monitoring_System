import axios, { type AxiosRequestConfig, type InternalAxiosRequestConfig } from 'axios';
import { env } from '@/config/env';
import { getAwsCredentials } from './cognitoAuth';
import { signRequest } from './sigv4';
import { haversineMeters } from './haversine';
import { enqueueWrite } from './offlineQueue';
import {
  mockAlert,
  mockAssignments,
  mockBatch,
  mockRider,
  mockShipment,
  mockStorageCentres,
} from '@/mock/mockData';
import type { Shipment, TemperatureReading } from '@/types/shipment';
import type { VaccineBatch } from '@/types/batch';
import type { Alert } from '@/types/alert';
import type { Rider } from '@/types/rider';
import type { MyAssignment, HandoffRecord, PositionPing } from '@/types/rider-ext';

/**
 * apiClient — single axios instance + SigV4 interceptor, mirrors the pattern
 * in /web/src/lib/apiClient.ts so a future backend swap is a one-file edit.
 *
 * Mock transport:
 *   - Shipment state (`liveShipment`) is the single source of truth for the
 *     rider's active trip. It drifts on each call to /riders/me/shipment.
 *   - Temperature ticks upward on every poll once the trip has started —
 *     4.2 → 5.0 → 6.1 → 7.2 → 8.1 → 8.4 → 9.0 — matching the dashboard's
 *     seriesExcursion curve.
 *   - /riders/me/alerts returns the pending HIGH alert once temp crosses
 *     8.3 OR 30s has elapsed, whichever is sooner.
 *   - PATCH /alerts/:id mutates the shared mockAlert so the /web dashboard
 *     (pointed at the same Jake row) flips to `riderResponse: accepted`.
 */

export const apiClient = axios.create({
  baseURL: env.apiGatewayBaseUrl || '/api',
  timeout: 15_000,
});

apiClient.interceptors.request.use(async (config: InternalAxiosRequestConfig) => {
  if (env.useMockData) return config;
  if (!env.apiGatewayBaseUrl) return config;

  const creds = await getAwsCredentials();
  const urlObj = new URL(
    (config.url ?? '').startsWith('http')
      ? (config.url as string)
      : `${env.apiGatewayBaseUrl.replace(/\/$/, '')}${config.url ?? ''}`,
  );

  const bodyString =
    config.data === undefined
      ? ''
      : typeof config.data === 'string'
      ? config.data
      : JSON.stringify(config.data);

  const signed = await signRequest({
    method: (config.method ?? 'GET').toUpperCase(),
    url: urlObj.toString(),
    region: env.awsRegion,
    service: 'execute-api',
    body: bodyString,
    headers:
      bodyString && !config.headers?.['Content-Type']
        ? { 'content-type': 'application/json' }
        : undefined,
    credentials: creds,
  });

  for (const [k, v] of Object.entries(signed)) {
    config.headers.set(k, v);
  }
  return config;
});

// ============================================================================
// Mock transport — Jake's scenario
// ============================================================================

const STEP_METERS_PER_POLL = 90;
const ARRIVAL_THRESHOLD_M = 50;

let liveShipment: Shipment = { ...mockShipment };
let mockAlertActive = false;
let tripStartAt: number | null = null;

// Temperature curve — replays the excursion profile from the dashboard's
// seriesExcursion helper. Values correspond to ticks after trip start.
const TEMP_CURVE: number[] = [4.2, 4.4, 4.7, 5.1, 5.7, 6.3, 7.0, 7.5, 8.1, 8.4, 8.7, 9.0, 9.1, 9.0, 8.7];
let tempIdx = 0;

function computeRisk(
  temp: number,
  minSafe: number,
  maxSafe: number,
): { score: number; level: Shipment['riskLevel']; remainingMin: number } {
  const excess = Math.max(0, temp - maxSafe, minSafe - temp);
  if (excess <= 0) return { score: +(Math.min(0.25, (temp - minSafe) / 20)).toFixed(2), level: 'safe', remainingMin: 80 };
  if (excess < 0.5) return { score: 0.45, level: 'warning', remainingMin: Math.max(12, 30 - Math.round(excess * 20)) };
  if (excess < 1.5) return { score: 0.74, level: 'high', remainingMin: Math.max(4, 10 - Math.round(excess * 3)) };
  return { score: 0.92, level: 'critical', remainingMin: Math.max(1, 4 - Math.round(excess)) };
}

function stepToward(
  from: { lat: number; lng: number },
  to: { lat: number; lng: number },
  meters: number,
): { lat: number; lng: number } {
  const dist = haversineMeters(from, to);
  if (dist < 10) return to;
  const frac = Math.min(1, meters / dist);
  return {
    lat: from.lat + (to.lat - from.lat) * frac,
    lng: from.lng + (to.lng - from.lng) * frac,
  };
}

function tickShipment(): Shipment {
  if (liveShipment.status !== 'active') return liveShipment;

  const now = Date.now();
  if (tripStartAt === null) tripStartAt = now;

  // Arrival check
  if (liveShipment.destinationLocation) {
    const dist = haversineMeters(liveShipment.currentLocation, liveShipment.destinationLocation);
    if (dist < ARRIVAL_THRESHOLD_M) {
      liveShipment = { ...liveShipment, status: 'completed', lastUpdated: new Date().toISOString() };
      return liveShipment;
    }
  }

  const nextTemp = TEMP_CURVE[Math.min(tempIdx, TEMP_CURVE.length - 1)];
  tempIdx++;
  const risk = computeRisk(nextTemp, liveShipment.minSafeTemp, liveShipment.maxSafeTemp);
  const nextLocation = liveShipment.destinationLocation
    ? stepToward(liveShipment.currentLocation, liveShipment.destinationLocation, STEP_METERS_PER_POLL)
    : liveShipment.currentLocation;

  const nextReading: TemperatureReading = {
    timestamp: new Date().toISOString(),
    temperature: +nextTemp.toFixed(2),
    humidity: 45 + Math.round(Math.random() * 10),
  };

  const secondsOutside =
    nextTemp > liveShipment.maxSafeTemp || nextTemp < liveShipment.minSafeTemp
      ? liveShipment.secondsOutsideRange + 5
      : liveShipment.secondsOutsideRange;

  liveShipment = {
    ...liveShipment,
    currentTemp: +nextTemp.toFixed(2),
    currentLocation: nextLocation,
    riskScore: risk.score,
    riskLevel: risk.level,
    remainingSafeMinutes: risk.remainingMin,
    secondsOutsideRange: secondsOutside,
    temperatureHistory: [...liveShipment.temperatureHistory, nextReading].slice(-120),
    lastUpdated: new Date().toISOString(),
    activeAlertId: mockAlertActive ? mockAlert.id : liveShipment.activeAlertId,
  };

  // Fire the alert when temp crosses the threshold OR 30s after trip start.
  const elapsed = now - (tripStartAt ?? now);
  if (
    !mockAlertActive &&
    (nextTemp >= 8.3 || elapsed > 30_000) &&
    liveShipment.status === 'active'
  ) {
    mockAlertActive = true;
    mockAlert.tempAtTrigger = +nextTemp.toFixed(2);
    mockAlert.timestamp = new Date().toISOString();
    liveShipment = {
      ...liveShipment,
      activeAlertId: mockAlert.id,
      incidentLog: [
        ...(liveShipment.incidentLog ?? []),
        {
          id: `SHIP-20240423-006-INC-${Date.now()}`,
          timestamp: new Date().toISOString(),
          eventType: 'excursionStart',
          detail: `Temperature exceeded 8.0°C (${nextTemp.toFixed(1)}°C)`,
          tempAtEvent: +nextTemp.toFixed(2),
        },
        {
          id: `SHIP-20240423-006-INC-${Date.now() + 1}`,
          timestamp: new Date().toISOString(),
          eventType: 'alertTriggered',
          detail: 'HIGH alert dispatched to rider',
        },
      ],
    };
  }

  return liveShipment;
}

/**
 * Called when the rider presses START TRIP on the Manifest screen. Resets the
 * simulation clock so the excursion fires at a predictable offset from when
 * the rider sees the map.
 */
function startTrip() {
  tripStartAt = Date.now();
  tempIdx = 0;
  mockAlertActive = false;
  liveShipment = {
    ...mockShipment,
    startTime: new Date().toISOString(),
    estimatedArrival: new Date(Date.now() + 50 * 60_000).toISOString(),
    status: 'active',
  };
}

async function mockDelay() {
  await new Promise((r) => setTimeout(r, 100 + Math.random() * 120));
}

// ============================================================================
// Public API
// ============================================================================

export const api = {
  // --- Rider endpoints ---

  async getMe(): Promise<Rider> {
    if (env.useMockData) {
      await mockDelay();
      return { ...mockRider };
    }
    const { data } = await apiClient.get<Rider>('/riders/me');
    return data;
  },

  async getMyShipment(): Promise<Shipment | null> {
    if (env.useMockData) {
      await mockDelay();
      return tickShipment();
    }
    const { data } = await apiClient.get<Shipment | null>('/riders/me/shipment');
    return data;
  },

  async getMyAlerts(): Promise<Alert[]> {
    if (env.useMockData) {
      await mockDelay();
      return mockAlertActive && mockAlert.status === 'active' ? [{ ...mockAlert }] : [];
    }
    const { data } = await apiClient.get<Alert[]>('/riders/me/alerts');
    return data;
  },

  async getMyAssignments(): Promise<MyAssignment[]> {
    if (env.useMockData) {
      await mockDelay();
      return liveShipment.status === 'completed' ? [] : mockAssignments;
    }
    const { data } = await apiClient.get<MyAssignment[]>('/riders/me/assignments');
    return data;
  },

  async getBatch(id: string): Promise<VaccineBatch> {
    if (env.useMockData) {
      await mockDelay();
      if (id !== mockBatch.batchId) throw new Error(`Batch ${id} not found`);
      return { ...mockBatch };
    }
    const { data } = await apiClient.get<VaccineBatch>(`/batches/${id}`);
    return data;
  },

  async getStorageCentres() {
    if (env.useMockData) {
      await mockDelay();
      return mockStorageCentres;
    }
    const { data } = await apiClient.get('/storage-centres');
    return data;
  },

  // --- Mutations ---

  async startShipment(shipmentId: string): Promise<Shipment> {
    if (env.useMockData) {
      await mockDelay();
      startTrip();
      mockBatch.chainOfCustody.push({
        id: `${mockBatch.batchId}-CUST-${Date.now()}`,
        timestamp: new Date().toISOString(),
        eventType: 'dispatched',
        location: liveShipment.origin,
        handledBy: liveShipment.riderName,
        tempAtEvent: liveShipment.currentTemp,
      });
      return liveShipment;
    }
    const { data } = await apiClient.post<Shipment>(`/shipments/${shipmentId}/start`);
    return data;
  },

  async postPing(ping: PositionPing): Promise<void> {
    if (env.useMockData) {
      // Swallow in mock mode.
      return;
    }
    if (!navigator.onLine) {
      await enqueueWrite('POST', `/shipments/${ping.shipmentId}/ping`, ping);
      return;
    }
    try {
      await apiClient.post(`/shipments/${ping.shipmentId}/ping`, ping);
    } catch {
      await enqueueWrite('POST', `/shipments/${ping.shipmentId}/ping`, ping);
    }
  },

  async patchAlert(id: string, patch: Partial<Alert>): Promise<Alert> {
    if (env.useMockData) {
      await mockDelay();
      Object.assign(mockAlert, patch);
      if (patch.riderResponse === 'accepted') {
        mockAlert.riderResponseTime = 38;
      }
      return { ...mockAlert };
    }
    if (!navigator.onLine) {
      await enqueueWrite('PATCH', `/alerts/${id}`, patch);
      return { ...mockAlert, ...patch };
    }
    const { data } = await apiClient.patch<Alert>(`/alerts/${id}`, patch);
    return data;
  },

  async logIncident(payload: {
    shipmentId: string;
    eventType: string;
    detail: string;
    tempAtEvent?: number;
  }): Promise<void> {
    if (env.useMockData) {
      liveShipment = {
        ...liveShipment,
        incidentLog: [
          ...(liveShipment.incidentLog ?? []),
          {
            id: `INC-${Date.now()}`,
            timestamp: new Date().toISOString(),
            eventType: payload.eventType as never,
            detail: payload.detail,
            tempAtEvent: payload.tempAtEvent,
          },
        ],
      };
      return;
    }
    if (!navigator.onLine) {
      await enqueueWrite('POST', '/incidents', payload);
      return;
    }
    try {
      await apiClient.post('/incidents', payload);
    } catch {
      await enqueueWrite('POST', '/incidents', payload);
    }
  },

  async postHandoff(record: HandoffRecord): Promise<void> {
    if (env.useMockData) {
      await mockDelay();
      // Complete shipment + deliver/store batch.
      const isDestination = record.location === 'destination';
      liveShipment = {
        ...liveShipment,
        status: 'completed',
        lastUpdated: new Date().toISOString(),
        incidentLog: [
          ...(liveShipment.incidentLog ?? []),
          {
            id: `HANDOFF-${Date.now()}`,
            timestamp: record.clientTimestamp,
            eventType: isDestination ? 'delivered' : 'diverted',
            detail: `Handed off to ${record.recipientName} at ${
              isDestination ? liveShipment.destination : record.coldStoreId ?? 'cold store'
            } (${record.tempAtHandoff.toFixed(1)}°C)`,
            tempAtEvent: record.tempAtHandoff,
          },
        ],
      };
      mockBatch.status = isDestination ? 'delivered' : 'in_storage';
      if (!isDestination) mockBatch.storageLocation = record.coldStoreId;
      mockBatch.chainOfCustody.push({
        id: `${mockBatch.batchId}-CUST-${Date.now()}`,
        timestamp: record.clientTimestamp,
        eventType: isDestination ? 'delivered' : 'received',
        location: isDestination ? liveShipment.destination : record.coldStoreId ?? 'cold store',
        handledBy: record.recipientName,
        tempAtEvent: record.tempAtHandoff,
        notes: record.notes,
      });
      // Resolve any active alert for this shipment.
      if (mockAlertActive) {
        mockAlert.status = 'resolved';
        mockAlert.resolvedAt = record.clientTimestamp;
        mockAlert.resolvedBy = 'rider';
        mockAlert.outcome = isDestination ? 'delivered_safe' : 'diverted';
      }
      return;
    }
    if (!navigator.onLine) {
      await enqueueWrite('POST', '/handoffs', record);
      return;
    }
    try {
      await apiClient.post('/handoffs', record);
    } catch {
      await enqueueWrite('POST', '/handoffs', record);
    }
  },

  async subscribePush(subscription: PushSubscriptionJSON): Promise<void> {
    if (env.useMockData) return;
    await apiClient.post('/rider/push/subscribe', subscription);
  },
};

// Expose live shipment for the Trip Summary view — a completed trip is still
// in memory when the rider navigates to `/summary/:shipmentId`.
export function getLiveShipmentSnapshot(): Shipment {
  return { ...liveShipment };
}

export function isMockAlertActive(): boolean {
  return mockAlertActive;
}

export type { AxiosRequestConfig };
