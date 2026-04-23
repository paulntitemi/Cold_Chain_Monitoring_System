import type { RiskLevel } from './shipment';
import type { StorageCentre } from './storageCentre';

export type AlertRiskLevel = Exclude<RiskLevel, 'safe'>;
export type RiderResponse = 'accepted' | 'ignored' | 'escalated';
export type AlertStatus = 'active' | 'resolved' | 'escalated';
export type AlertOutcome =
  | 'delivered_safe'
  | 'diverted'
  | 'discarded'
  | 'pending';

export interface Alert {
  id: string;
  shipmentId: string;
  riderName?: string;
  batchIds: string[];
  timestamp: string;
  riskLevel: AlertRiskLevel;
  riskScore: number;
  tempAtTrigger: number;
  remainingSafeMinutes: number;
  recommendedCentre?: StorageCentre;
  riderResponse?: RiderResponse;
  riderResponseTime?: number;
  resolvedAt?: string;
  resolvedBy?: 'rider' | 'operator' | 'auto';
  operatorNotes?: string;
  status: AlertStatus;
  outcome?: AlertOutcome;
  dosesAtRisk?: number;
}
