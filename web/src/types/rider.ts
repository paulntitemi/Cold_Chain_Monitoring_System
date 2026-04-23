export type VehicleType = 'motorbike' | 'bicycle' | 'vehicle';

export interface Rider {
  id: string;
  name: string;
  phone: string;
  vehicleType: VehicleType;
  activeShipmentId?: string;
  totalTrips: number;
  alertResponseRate: number;
}
