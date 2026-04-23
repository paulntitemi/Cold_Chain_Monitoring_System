export type RiskLevel = 'safe' | 'warning' | 'high' | 'critical';
export type ShipmentStatus = 'active' | 'completed' | 'aborted';

export interface TemperatureReading {
  timestamp: string;
  temperature: number;
  humidity?: number;
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
