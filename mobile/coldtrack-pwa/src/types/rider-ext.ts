import type { VaccineBatch } from './batch';

export interface MyAssignment {
  shipmentId: string;
  dispatchAt: string;
  batches: Pick<
    VaccineBatch,
    'batchId' | 'vaccineType' | 'doseCount' | 'minSafeTemp' | 'maxSafeTemp' | 'vvmStatus'
  >[];
  origin: string;
  destination: string;
  destinationLocation: { lat: number; lng: number };
}

export interface HandoffRecord {
  shipmentId: string;
  location: 'destination' | 'cold_store';
  coldStoreId?: string;
  recipientName: string;
  recipientRole?: string;
  signature?: string;
  photoUrl?: string;
  tempAtHandoff: number;
  notes?: string;
  clientTimestamp: string;
}

export interface PositionPing {
  shipmentId: string;
  lat: number;
  lng: number;
  clientTs: string;
  accuracy?: number;
  speed?: number | null;
  heading?: number | null;
}
