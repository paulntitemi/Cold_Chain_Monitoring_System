export interface StorageCentre {
  id: string;
  name: string;
  address: string;
  location: { lat: number; lng: number };
  hasColdStorage: boolean;
  availableCapacity: number;
  phone: string;
  distanceKm?: number;
  estimatedMinutes?: number;
}
