export type RiskLevel = 'safe' | 'warning' | 'high' | 'critical';
export type ShipmentStatus = 'active' | 'completed' | 'aborted';

export interface TemperatureReading {
  timestamp: string;
  temperature: number;
  humidity?: number;
}

/**
 * Optional sub-scores published by the ESP32 firmware (schema_version 1.0).
 * The device calculates risk at the edge — the cloud trusts the score and
 * never recomputes it. The four sub-scores explain *why* the overall score
 * is what it is, and feed the dashboard's "Why critical?" breakdown panel.
 */
export interface RiskBreakdown {
  temperatureRisk: number; // 0–100
  durationRisk: number;
  vibrationRisk: number;
  gpsRisk: number;
}

export interface Shipment {
  id: string;
  deviceId: string;
  riderId: string;
  riderName: string;
  riderPhone: string;
  batchIds: string[];
  origin: string;
  destination: string;
  startTime: string;
  estimatedArrival: string;
  status: ShipmentStatus;
  currentTemp: number;
  minSafeTemp: number;
  maxSafeTemp: number;
  riskScore: number;
  riskLevel: RiskLevel;
  remainingSafeMinutes: number;
  secondsOutsideRange: number;
  currentLocation: { lat: number; lng: number };
  destinationLocation?: { lat: number; lng: number };
  temperatureHistory: TemperatureReading[];
  lastUpdated: string;
  activeAlertId?: string;
  incidentLog?: IncidentLogEntry[];
  /**
   * Edge-published telemetry — populated for live shipments coming from
   * the firmware, undefined for purely-mocked rows.
   */
  temperatureRisk?: number;
  durationRisk?: number;
  vibrationRisk?: number;
  gpsRisk?: number;
  thresholdProfile?: string;
  gpsFix?: boolean;
  vibrationCount10s?: number;
  satellites?: number;
  /** False when the TMP102 probe is disconnected / NaN at source. */
  temperatureSensorOk?: boolean;
}

export type IncidentEventType =
  | 'excursionStart'
  | 'excursionEnd'
  | 'alertTriggered'
  | 'riderAccepted'
  | 'riderIgnored'
  | 'diverted'
  | 'delivered'
  | 'aborted'
  | 'operatorNote';

export interface IncidentLogEntry {
  id: string;
  timestamp: string;
  eventType: IncidentEventType;
  detail: string;
  tempAtEvent?: number;
  operatorName?: string;
}
