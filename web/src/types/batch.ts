export type VaccineType =
  | 'Polio'
  | 'Measles'
  | 'COVID-19'
  | 'Yellow Fever'
  | 'Meningitis'
  | 'Other';

export type VVMStage = 'stage1' | 'stage2' | 'stage3' | 'stage4';
export type BatchStatus = 'in_storage' | 'in_transit' | 'delivered' | 'discarded';

export type CustodyEventType =
  | 'dispatched'
  | 'received'
  | 'excursion'
  | 'alert'
  | 'diverted'
  | 'delivered';

export interface CustodyEvent {
  id: string;
  timestamp: string;
  eventType: CustodyEventType;
  location: string;
  handledBy: string;
  notes?: string;
  tempAtEvent?: number;
}

export interface VaccineBatch {
  batchId: string;
  vaccineType: VaccineType;
  manufacturer: string;
  manufactureDate: string;
  expiryDate: string;
  doseCount: number;
  dosesRemaining: number;
  minSafeTemp: number;
  maxSafeTemp: number;
  vvmStatus: VVMStage;
  currentShipmentId?: string;
  storageLocation?: string;
  totalExcursionMinutes: number;
  status: BatchStatus;
  chainOfCustody: CustodyEvent[];
  linkedShipmentIds?: string[];
}
