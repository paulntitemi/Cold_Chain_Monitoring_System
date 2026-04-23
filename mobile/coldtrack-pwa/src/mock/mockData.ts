import type { Shipment, TemperatureReading, IncidentLogEntry } from '@/types/shipment';
import type { VaccineBatch, CustodyEvent } from '@/types/batch';
import type { Rider } from '@/types/rider';
import type { Alert } from '@/types/alert';
import type { StorageCentre } from '@/types/storageCentre';
import type { MyAssignment } from '@/types/rider-ext';

/**
 * Mock data for the rider PWA — trimmed to Jake Fletcher's world so
 * `npm run dev` plays the full scenario end-to-end in ~40 seconds without
 * touching AWS.
 *
 * Shapes mirror /web/src/mock/mockData.ts exactly; the rider only sees their
 * own shipment + alerts, so this file carries Jake's row plus the storage
 * centres he could divert to.
 */

const now = Date.now();
const minutes = (m: number) => new Date(now - m * 60_000).toISOString();
const hours = (h: number) => new Date(now - h * 3_600_000).toISOString();
const days = (d: number) => new Date(now - d * 86_400_000).toISOString();
const future = (m: number) => new Date(now + m * 60_000).toISOString();
const futureDays = (d: number) => new Date(now + d * 86_400_000).toISOString();

// A clean in-range history up to T0. Temp excursion will be appended live.
function seriesInRange(count: number, base = 4.2, drift = 0.4): TemperatureReading[] {
  const out: TemperatureReading[] = [];
  for (let i = count - 1; i >= 0; i--) {
    const noise = Math.sin(i * 0.8) * drift + (Math.random() - 0.5) * 0.2;
    out.push({
      timestamp: minutes(i * 2),
      temperature: +(base + noise).toFixed(2),
      humidity: 40 + Math.round(Math.random() * 15),
    });
  }
  return out;
}

export const mockStorageCentres: StorageCentre[] = [
  {
    id: 'CENTRE-001',
    name: "St Thomas' Hospital Cold Store",
    address: 'Westminster Bridge Rd, London SE1 7EH',
    location: { lat: 51.4975, lng: -0.1184 },
    hasColdStorage: true,
    availableCapacity: 1800,
    phone: '+442071887188',
  },
  {
    id: 'CENTRE-002',
    name: 'Royal London Hospital Cold Store',
    address: 'Whitechapel Rd, London E1 1FR',
    location: { lat: 51.5179, lng: -0.0596 },
    hasColdStorage: true,
    availableCapacity: 900,
    phone: '+442035941000',
  },
  {
    id: 'CENTRE-003',
    name: "King's College Hospital Cold Store",
    address: 'Denmark Hill, London SE5 9RS',
    location: { lat: 51.4681, lng: -0.0933 },
    hasColdStorage: true,
    availableCapacity: 600,
    phone: '+442032999000',
  },
  {
    id: 'CENTRE-004',
    name: 'UCLH Cold Store',
    address: '235 Euston Rd, London NW1 2BU',
    location: { lat: 51.5245, lng: -0.1349 },
    hasColdStorage: true,
    availableCapacity: 400,
    phone: '+442034567890',
  },
];

export const mockRider: Rider = {
  id: 'R-006',
  name: 'Jake Fletcher',
  phone: '+447700900006',
  vehicleType: 'motorbike',
  activeShipmentId: 'SHIP-20240423-006',
  totalTrips: 71,
  alertResponseRate: 0.6,
};

function custody(
  batchId: string,
  events: Array<
    Partial<CustodyEvent> & {
      timestamp: string;
      eventType: CustodyEvent['eventType'];
      location: string;
      handledBy: string;
    }
  >,
): CustodyEvent[] {
  return events.map((e, i) => ({
    id: `${batchId}-CUST-${i + 1}`,
    notes: e.notes,
    tempAtEvent: e.tempAtEvent,
    ...e,
  }));
}

export const mockBatch: VaccineBatch = {
  batchId: 'YFV-2024-UK-0008',
  vaccineType: 'Yellow Fever',
  manufacturer: 'Sanofi Pasteur',
  manufactureDate: days(30),
  expiryDate: futureDays(180),
  doseCount: 300,
  dosesRemaining: 300,
  minSafeTemp: 2.0,
  maxSafeTemp: 8.0,
  vvmStatus: 'stage1',
  currentShipmentId: 'SHIP-20240423-006',
  totalExcursionMinutes: 0,
  status: 'in_transit',
  chainOfCustody: custody('YFV-2024-UK-0008', [
    {
      timestamp: hours(2),
      eventType: 'dispatched',
      location: "King's College Hospital",
      handledBy: 'Jake Fletcher',
      tempAtEvent: 4.2,
    },
  ]),
};

function incident(
  s: string,
  entries: Array<Partial<IncidentLogEntry> & { timestamp: string; eventType: IncidentLogEntry['eventType']; detail: string }>,
): IncidentLogEntry[] {
  return entries.map((e, i) => ({ id: `${s}-INC-${i + 1}`, ...e }));
}

/**
 * Jake's shipment. Critically: unlike the dashboard mock (which pre-primes
 * the excursion), we start the rider's view SAFE at 4.2°C. The mock poller
 * drifts temperature upward on each tick, reproducing the 8.4°C breach
 * live so the rider actually sees the transition.
 */
export const mockShipment: Shipment = {
  id: 'SHIP-20240423-006',
  deviceId: 'THING-ESP32-006',
  riderId: 'R-006',
  riderName: 'Jake Fletcher',
  riderPhone: '+447700900006',
  batchIds: ['YFV-2024-UK-0008'],
  origin: "King's College Hospital",
  destination: 'Queen Elizabeth Hospital Woolwich',
  startTime: minutes(5),
  estimatedArrival: future(50),
  status: 'active',
  currentTemp: 4.2,
  minSafeTemp: 2.0,
  maxSafeTemp: 8.0,
  riskScore: 0.08,
  riskLevel: 'safe',
  remainingSafeMinutes: 80,
  secondsOutsideRange: 0,
  currentLocation: { lat: 51.4681, lng: -0.0933 },
  destinationLocation: { lat: 51.4948, lng: 0.0601 },
  temperatureHistory: seriesInRange(20, 4.2, 0.3),
  lastUpdated: new Date(now).toISOString(),
  incidentLog: incident('SHIP-20240423-006', [
    {
      timestamp: minutes(5),
      eventType: 'excursionEnd',
      detail: "Shipment dispatched from King's College Hospital",
    },
  ]),
};

/**
 * The pending HIGH alert — NOT surfaced until the rider mock has ticked temp
 * past the threshold. We pre-construct it so the shape is final.
 */
export const mockAlert: Alert = {
  id: 'ALERT-20240423-006',
  shipmentId: 'SHIP-20240423-006',
  riderName: 'Jake Fletcher',
  batchIds: ['YFV-2024-UK-0008'],
  timestamp: new Date(now).toISOString(),
  riskLevel: 'high',
  riskScore: 0.74,
  tempAtTrigger: 8.4,
  remainingSafeMinutes: 6,
  recommendedCentre: {
    ...mockStorageCentres[2], // King's College Hospital Cold Store
    distanceKm: 4.2,
    estimatedMinutes: 9,
  },
  status: 'active',
  dosesAtRisk: 300,
};

export const mockAssignments: MyAssignment[] = [
  {
    shipmentId: 'SHIP-20240423-006',
    dispatchAt: minutes(5),
    batches: [
      {
        batchId: mockBatch.batchId,
        vaccineType: mockBatch.vaccineType,
        doseCount: mockBatch.doseCount,
        minSafeTemp: mockBatch.minSafeTemp,
        maxSafeTemp: mockBatch.maxSafeTemp,
        vvmStatus: mockBatch.vvmStatus,
      },
    ],
    origin: "King's College Hospital",
    destination: 'Queen Elizabeth Hospital Woolwich',
    destinationLocation: { lat: 51.4948, lng: 0.0601 },
  },
];

export const mockPastTrips: Array<{
  id: string;
  completedAt: string;
  origin: string;
  destination: string;
  doseCount: number;
  outcome: 'delivered_safe' | 'diverted' | 'discarded';
}> = [
  {
    id: 'SHIP-20240422-041',
    completedAt: hours(20),
    origin: 'NHS Central Vaccine Depot',
    destination: 'Homerton University Hospital',
    doseCount: 2000,
    outcome: 'delivered_safe',
  },
  {
    id: 'SHIP-20240421-022',
    completedAt: days(2),
    origin: 'Royal London Hospital',
    destination: 'Lewisham Hospital',
    doseCount: 420,
    outcome: 'diverted',
  },
  {
    id: 'SHIP-20240419-018',
    completedAt: days(4),
    origin: "St Thomas' Hospital",
    destination: 'UCLH',
    doseCount: 1000,
    outcome: 'delivered_safe',
  },
];
