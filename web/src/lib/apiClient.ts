import axios, { type AxiosRequestConfig, type InternalAxiosRequestConfig } from 'axios';
import { env } from '@/config/env';
import { getAwsCredentials } from './cognitoAuth';
import { signRequest } from './sigv4';
import {
  mockAlerts,
  mockBatches,
  mockRiders,
  mockShipments,
} from '@/mock/mockData';
import type { Shipment } from '@/types/shipment';
import type { VaccineBatch } from '@/types/batch';
import type { Alert } from '@/types/alert';
import type { Rider } from '@/types/rider';

/**
 * apiClient — single axios instance for all backend calls.
 *
 * When VITE_USE_MOCK_DATA=true we short-circuit all GET requests to the
 * in-memory mock data (with a tiny jitter simulator so polling looks real).
 * To flip to the real backend, set VITE_USE_MOCK_DATA=false and populate
 * VITE_API_GATEWAY_BASE_URL + the Cognito vars.
 *
 * The SigV4 interceptor runs on every real request and attaches signed
 * headers using temporary Cognito creds. Requests fired before creds are
 * ready will await the pending promise — there's no unsigned-request race.
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

// ---------- Mock transport ----------

// Meters-per-poll — chosen so movement is visible at zoom 11 every 5s without
// being unrealistic (a motorbike in London traffic averages ~30 km/h ≈ 42 m/s;
// we step ~140m per 5s tick).
const STEP_METERS_PER_POLL = 140;

function stepToward(
  from: { lat: number; lng: number },
  to: { lat: number; lng: number },
  meters: number,
): { lat: number; lng: number } {
  const R = 6_371_000;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(to.lat - from.lat);
  const dLng = toRad(to.lng - from.lng);
  const lat1 = toRad(from.lat);
  const lat2 = toRad(to.lat);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  const distMeters = 2 * R * Math.asin(Math.sqrt(h));
  if (distMeters < 10) return to; // arrived
  const frac = Math.min(1, meters / distMeters);
  return {
    lat: from.lat + (to.lat - from.lat) * frac,
    lng: from.lng + (to.lng - from.lng) * frac,
  };
}

function haversineMeters(a: { lat: number; lng: number }, b: { lat: number; lng: number }): number {
  const R = 6_371_000;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

const ARRIVAL_THRESHOLD_M = 30;

/**
 * On arrival: mark the shipment completed, deliver each batch in the manifest
 * (with a custody event), and auto-resolve any open alert for this shipment.
 * If the rider arrived still in high/critical the outcome is `pending` —
 * warm vaccines aren't automatically safe to administer; the operator must
 * decide.
 */
function handleArrival(s: Shipment): Shipment {
  const arrivalTs = new Date().toISOString();

  for (const batchId of s.batchIds) {
    const batch = mockBatches.find((b) => b.batchId === batchId);
    if (!batch) continue;
    batch.status = 'delivered';
    batch.currentShipmentId = undefined;
    batch.storageLocation = s.destination;
    batch.chainOfCustody.push({
      id: `${batchId}-CUST-${Date.now()}`,
      timestamp: arrivalTs,
      eventType: 'delivered',
      location: s.destination,
      handledBy: s.riderName,
      tempAtEvent: s.currentTemp,
    });
  }

  const warmOnArrival = s.riskLevel === 'high' || s.riskLevel === 'critical';
  for (const alert of mockAlerts) {
    if (alert.shipmentId === s.id && alert.status === 'active') {
      alert.status = 'resolved';
      alert.resolvedAt = arrivalTs;
      alert.resolvedBy = 'rider';
      alert.outcome = warmOnArrival ? 'pending' : 'delivered_safe';
    }
  }

  return {
    ...s,
    status: 'completed',
    currentLocation: s.destinationLocation ?? s.currentLocation,
    lastUpdated: arrivalTs,
    incidentLog: [
      ...(s.incidentLog ?? []),
      {
        id: `${s.id}-INC-${Date.now()}`,
        timestamp: arrivalTs,
        eventType: 'delivered',
        detail: warmOnArrival
          ? `Arrived at ${s.destination} — WARM on arrival (${s.currentTemp.toFixed(1)}°C), operator disposition required`
          : `Delivered safe to ${s.destination} at ${s.currentTemp.toFixed(1)}°C`,
      },
    ],
  };
}

function jitter(items: Shipment[]): Shipment[] {
  return items.map((s) => {
    if (s.status !== 'active') return s;

    // Arrival check before stepping.
    if (s.destinationLocation) {
      const distRemaining = haversineMeters(s.currentLocation, s.destinationLocation);
      if (distRemaining < ARRIVAL_THRESHOLD_M) {
        return handleArrival(s);
      }
    }

    const tempDrift = (Math.random() - 0.5) * 0.15;
    const nextLocation = s.destinationLocation
      ? stepToward(s.currentLocation, s.destinationLocation, STEP_METERS_PER_POLL)
      : s.currentLocation;
    return {
      ...s,
      currentTemp: +(s.currentTemp + tempDrift).toFixed(2),
      currentLocation: nextLocation,
      lastUpdated: new Date().toISOString(),
    };
  });
}

// Shipments drift but stay stable on risk level — we freeze snapshots for the session.
let liveShipments: Shipment[] = [...mockShipments];

async function mockGet<T>(url: string): Promise<T> {
  // Simulate network latency.
  await new Promise((r) => setTimeout(r, 120 + Math.random() * 120));

  if (url.startsWith('/fleet/active')) {
    liveShipments = jitter(liveShipments);
    return liveShipments.filter((s) => s.status === 'active') as unknown as T;
  }
  if (url.startsWith('/shipments/')) {
    const id = url.split('/').pop();
    const s = liveShipments.find((x) => x.id === id);
    if (!s) throw new Error(`Shipment ${id} not found`);
    return s as unknown as T;
  }
  if (url.startsWith('/batches/')) {
    const id = url.split('/').pop();
    const b = mockBatches.find((x) => x.batchId === id);
    if (!b) throw new Error(`Batch ${id} not found`);
    return b as unknown as T;
  }
  if (url.startsWith('/batches')) return mockBatches as unknown as T;
  if (url.startsWith('/alerts/active')) {
    return mockAlerts.filter((a) => a.status === 'active') as unknown as T;
  }
  if (url.startsWith('/alerts')) return mockAlerts as unknown as T;
  if (url.startsWith('/riders')) return mockRiders as unknown as T;
  throw new Error(`Mock transport: unhandled URL ${url}`);
}

// ---------- Public API ----------

export const api = {
  async getActiveFleet(): Promise<Shipment[]> {
    if (env.useMockData) return mockGet<Shipment[]>('/fleet/active');
    const { data } = await apiClient.get<Shipment[]>('/fleet/active');
    return data;
  },

  async getShipment(id: string): Promise<Shipment> {
    if (env.useMockData) return mockGet<Shipment>(`/shipments/${id}`);
    const { data } = await apiClient.get<Shipment>(`/shipments/${id}`);
    return data;
  },

  async getBatches(): Promise<VaccineBatch[]> {
    if (env.useMockData) return mockGet<VaccineBatch[]>('/batches');
    const { data } = await apiClient.get<VaccineBatch[]>('/batches');
    return data;
  },

  async getBatch(id: string): Promise<VaccineBatch> {
    if (env.useMockData) return mockGet<VaccineBatch>(`/batches/${id}`);
    const { data } = await apiClient.get<VaccineBatch>(`/batches/${id}`);
    return data;
  },

  async createBatch(payload: Partial<VaccineBatch>): Promise<VaccineBatch> {
    if (env.useMockData) {
      const created: VaccineBatch = {
        batchId: payload.batchId ?? `BATCH-${Date.now()}`,
        vaccineType: payload.vaccineType ?? 'Other',
        manufacturer: payload.manufacturer ?? 'Unknown',
        manufactureDate: payload.manufactureDate ?? new Date().toISOString(),
        expiryDate: payload.expiryDate ?? new Date().toISOString(),
        doseCount: payload.doseCount ?? 0,
        dosesRemaining: payload.dosesRemaining ?? payload.doseCount ?? 0,
        minSafeTemp: payload.minSafeTemp ?? 2,
        maxSafeTemp: payload.maxSafeTemp ?? 8,
        vvmStatus: payload.vvmStatus ?? 'stage1',
        totalExcursionMinutes: 0,
        status: 'in_storage',
        chainOfCustody: [],
        storageLocation: payload.storageLocation,
      };
      mockBatches.unshift(created);
      return created;
    }
    const { data } = await apiClient.post<VaccineBatch>('/batches', payload);
    return data;
  },

  async updateBatch(id: string, patch: Partial<VaccineBatch>): Promise<VaccineBatch> {
    if (env.useMockData) {
      const b = mockBatches.find((x) => x.batchId === id);
      if (!b) throw new Error('Batch not found');
      Object.assign(b, patch);
      return b;
    }
    const { data } = await apiClient.patch<VaccineBatch>(`/batches/${id}`, patch);
    return data;
  },

  async getActiveAlerts(): Promise<Alert[]> {
    if (env.useMockData) return mockGet<Alert[]>('/alerts/active');
    const { data } = await apiClient.get<Alert[]>('/alerts/active');
    return data;
  },

  async getAlerts(params?: Record<string, string>): Promise<Alert[]> {
    if (env.useMockData) return mockGet<Alert[]>('/alerts');
    const { data } = await apiClient.get<Alert[]>('/alerts', { params });
    return data;
  },

  async patchAlert(id: string, patch: Partial<Alert>): Promise<Alert> {
    if (env.useMockData) {
      const a = mockAlerts.find((x) => x.id === id);
      if (!a) throw new Error('Alert not found');
      Object.assign(a, patch);
      return a;
    }
    const { data } = await apiClient.patch<Alert>(`/alerts/${id}`, patch);
    return data;
  },

  async logIncident(payload: {
    shipmentId: string;
    eventType: string;
    detail: string;
    operatorName?: string;
  }): Promise<void> {
    if (env.useMockData) {
      const s = liveShipments.find((x) => x.id === payload.shipmentId);
      if (s) {
        s.incidentLog = [
          ...(s.incidentLog ?? []),
          {
            id: `INC-${Date.now()}`,
            timestamp: new Date().toISOString(),
            eventType: payload.eventType as never,
            detail: payload.detail,
            operatorName: payload.operatorName,
          },
        ];
      }
      return;
    }
    await apiClient.post('/incidents', payload);
  },

  async getRiders(): Promise<Rider[]> {
    if (env.useMockData) return mockGet<Rider[]>('/riders');
    const { data } = await apiClient.get<Rider[]>('/riders');
    return data;
  },
};

export type { AxiosRequestConfig };
